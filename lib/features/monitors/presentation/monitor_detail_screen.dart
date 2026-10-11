import 'dart:math' as math;

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';

import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/formatters/certificate_algorithm_formatter.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_refresh_banner.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_surface.dart';
import 'package:akshi/features/monitors/presentation/widgets/site_identity.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class MonitorDetailScreen extends ConsumerStatefulWidget {
  const MonitorDetailScreen({
    required this.monitorId,
    this.focusKind,
    this.revealAttention = false,
    super.key,
  });

  final String monitorId;
  final MonitorCheckKind? focusKind;

  /// Whether this visit came from the Attention screen. Section selection and
  /// attention reveal are separate so ordinary detail navigation never scrolls
  /// or pulses automatically.
  final bool revealAttention;

  @override
  ConsumerState<MonitorDetailScreen> createState() =>
      _MonitorDetailScreenState();
}

class _MonitorDetailScreenState extends ConsumerState<MonitorDetailScreen> {
  final _domainSectionKey = GlobalKey();
  final _tlsSectionKey = GlobalKey();
  final _emailSectionKey = GlobalKey();
  final _scrollController = ScrollController();
  final _announcedKinds = <MonitorCheckKind>{};
  final _pulseVersions = <MonitorCheckKind, int>{};
  List<MonitorFinding> _attentionFindings = const <MonitorFinding>[];
  late MonitorCheckKind? _activeFocusKind;
  late bool _focusVisitSettled;
  var _focusScrollScheduled = false;
  var _visibilityScanScheduled = false;

  @override
  void initState() {
    super.initState();
    _activeFocusKind = widget.revealAttention ? widget.focusKind : null;
    _focusVisitSettled = !widget.revealAttention;
    _scrollController.addListener(_scheduleVisibilityScan);
  }

  @override
  void didUpdateWidget(covariant MonitorDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusKind != widget.focusKind ||
        oldWidget.revealAttention != widget.revealAttention) {
      _activeFocusKind = widget.revealAttention ? widget.focusKind : null;
      _focusVisitSettled = !widget.revealAttention;
      _focusScrollScheduled = false;
      _announcedKinds.clear();
      _pulseVersions.clear();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_scheduleVisibilityScan)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(monitorControllerProvider);
    final refresh = ref.watch(monitorRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final monitor = _find(items.value ?? const <MonitorEntry>[]);
    if (monitor == null) {
      return Scaffold(
        appBar: AppBar(leading: _backButton(context)),
        body: Center(
          child: items.isLoading
              ? const CircularProgressIndicator()
              : const Text('Monitor not found'),
        ),
      );
    }
    final checkProgress = ref.watch(
      monitorCheckActivityProvider.select((active) => active[monitor.id]),
    );
    final checking = checkProgress != null;
    final status = monitor.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final focusedFailure = switch (widget.focusKind) {
      MonitorCheckKind.domainRegistration => monitor.domainActivity.failure,
      MonitorCheckKind.tlsCertificate => monitor.certificateActivity.failure,
      MonitorCheckKind.emailConfiguration => monitor.emailActivity.failure,
      null => null,
    };
    final focusConnectionInterrupted =
        focusedFailure.isConnectivityInterruption;
    final findings = findingsForMonitor(
      monitor,
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    _attentionFindings = findings
        .where(
          (finding) =>
              finding.needsAttention && finding.kind == widget.focusKind,
        )
        .toList(growable: false);
    final domainAttention = _attentionFinding(
      findings,
      MonitorCheckKind.domainRegistration,
    );
    final tlsAttention = _attentionFinding(
      findings,
      MonitorCheckKind.tlsCertificate,
    );
    final emailAttention = _attentionFinding(
      findings,
      MonitorCheckKind.emailConfiguration,
    );
    final issueIndex = _attentionFindings.indexWhere(
      (finding) => finding.kind == _activeFocusKind,
    );
    final activeIssueIndex = issueIndex < 0 ? 0 : issueIndex;
    _scheduleFocusScroll();
    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            onPressed: checking || refresh.isRunning
                ? null
                : () {
                    if (offline) {
                      showOfflineMessage(context);
                      return;
                    }
                    context.push('/monitor/${monitor.id}/edit');
                  },
            icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: checking || refresh.isRunning
                ? null
                : () => _delete(monitor),
            icon: const PhosphorIcon(PhosphorIconsDuotone.trash),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh.isRunning
            ? () async {
                await ref.read(monitorControllerProvider.notifier).refreshAll();
              }
            : () => _refresh(monitor),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (refresh.shouldShowStatus) ...<Widget>[
                const MonitorRefreshBanner(),
                const SizedBox(height: 14),
              ],
              if (offline) ...<Widget>[
                const OfflineNotice(),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SiteIdentity(monitor: monitor, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          monitor.displayName,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          monitor.hostname,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontFamily: AkshiTheme.monoFontFamily,
                            fontFeatures: const <FontFeature>[
                              FontFeature.slashedZero(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (monitor.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: monitor.tags
                      .map((tag) => TagPill(tag: tag))
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  StatusPill(status: status),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: checking || refresh.isRunning || offline
                        ? null
                        : () => _refresh(monitor),
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const PhosphorIcon(
                            PhosphorIconsRegular.arrowsClockwise,
                            size: 17,
                          ),
                    label: Text(checking ? 'Checking' : 'Check now'),
                  ),
                ],
              ),
              if (checkProgress != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(checkProgress.message),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: checkProgress.fraction),
              ],
              if (widget.revealAttention &&
                  _attentionFindings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _AttentionNavigator(
                  finding: _attentionFindings[activeIssueIndex],
                  position: activeIssueIndex + 1,
                  total: _attentionFindings.length,
                  onPrevious: activeIssueIndex == 0
                      ? null
                      : () => _focusIssue(
                          _attentionFindings[activeIssueIndex - 1].kind,
                        ),
                  onNext: activeIssueIndex == _attentionFindings.length - 1
                      ? null
                      : () => _focusIssue(
                          _attentionFindings[activeIssueIndex + 1].kind,
                        ),
                ),
              ],
              if (widget.focusKind == MonitorCheckKind.tlsCertificate &&
                  monitor.certificateChanged) ...<Widget>[
                const SizedBox(height: 18),
                _Notice(
                  icon: PhosphorIconsDuotone.sparkle,
                  title: 'Renewal detected',
                  message: 'The live certificate fingerprint changed on the latest check.',
                ),
              ],
              if ((widget.focusKind == MonitorCheckKind.domainRegistration &&
                      monitor.domainError != null) ||
                  (widget.focusKind == MonitorCheckKind.tlsCertificate &&
                      monitor.certificateError != null) ||
                  (widget.focusKind == MonitorCheckKind.emailConfiguration &&
                      monitor.emailActivity.failure != null)) ...<Widget>[
                const SizedBox(height: 18),
                _Notice(
                  icon: focusConnectionInterrupted
                      ? PhosphorIconsDuotone.cloudSlash
                      : PhosphorIconsDuotone.warningCircle,
                  title: focusConnectionInterrupted
                      ? 'Latest check could not connect'
                      : 'Some data could not be verified',
                  message: focusConnectionInterrupted
                      ? 'Saved results remain visible. Akshi connects only '
                            'during a check and keeps no persistent connection.'
                      : [
                          if (widget.focusKind ==
                              MonitorCheckKind.domainRegistration)
                            'Domain: ${monitor.domainError}',
                          if (widget.focusKind ==
                              MonitorCheckKind.tlsCertificate)
                            'Certificate: ${monitor.certificateError}',
                          if (widget.focusKind ==
                              MonitorCheckKind.emailConfiguration)
                            'Email: ${monitor.emailActivity.failure!.message}',
                        ].join(String.fromCharCode(10)),
                  error: !focusConnectionInterrupted,
                ),
              ],
              if (widget.focusKind ==
                  MonitorCheckKind.domainRegistration) ...<Widget>[
                const SizedBox(height: 26),
                _ExpiryPanel(
                  key: _domainSectionKey,
                  icon: PhosphorIconsDuotone.globeHemisphereWest,
                  title: 'Domain registration',
                  date: monitor.domainExpiresAt,
                  source: monitor.domainSource == null
                      ? 'No registry date available'
                      : 'Verified through ${monitor.domainSource}',
                  focus: domainAttention,
                  focusPulse: _pulseFor(MonitorCheckKind.domainRegistration),
                ),
                const SizedBox(height: 26),
                Text(
                  'Domain details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  children: <Widget>[
                    _InfoRow(
                      icon: PhosphorIconsDuotone.bank,
                      label: 'Registrar',
                      value: _domainText(monitor, monitor.domainRegistrar),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.identificationCard,
                      label: 'Public registrant',
                      value: _domainText(
                        monitor,
                        monitor.domainPublicRegistrant,
                        unpublished: 'Not publicly disclosed',
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.calendarCheck,
                      label: 'Registered',
                      value: _domainDate(monitor, monitor.domainRegisteredAt),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.clock,
                      label: 'Last changed',
                      value: _domainDate(monitor, monitor.domainUpdatedAt),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.network,
                      label: 'Name servers',
                      value: _domainText(
                        monitor,
                        monitor.domainNameServers.isEmpty
                            ? null
                            : monitor.domainNameServers.join('\n'),
                      ),
                      monospace: true,
                      last: true,
                    ),
                  ],
                ),
              ],
              if (widget.focusKind == MonitorCheckKind.tlsCertificate &&
                  monitor.checksCertificate) ...<Widget>[
                const SizedBox(height: 12),
                _ExpiryPanel(
                  key: _tlsSectionKey,
                  icon: PhosphorIconsDuotone.certificate,
                  title: 'TLS certificate',
                  date: monitor.certificateExpiresAt,
                  source: monitor.certificateIssuer == null
                      ? 'No certificate data available'
                      : 'Issued by ${formatCertificateIssuer(monitor.certificateIssuer!)}',
                  focus: tlsAttention,
                  focusPulse: _pulseFor(MonitorCheckKind.tlsCertificate),
                ),
                const SizedBox(height: 26),
                Text(
                  'Certificate details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  children: <Widget>[
                    _InfoRow(
                      icon: PhosphorIconsRegular.network,
                      label: 'TLS endpoint',
                      value: _tlsEndpoint(monitor),
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.shieldCheck,
                      label: 'Trust',
                      value: _trustLabel(monitor.tlsTrusted),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.sealCheck,
                      label: 'Hostname match',
                      value: _hostnameMatchLabel(
                        monitor.certificateHostnameMatches,
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.identificationCard,
                      label: 'Subject',
                      value: monitor.certificateSubject ?? '—',
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.bank,
                      label: 'Issuer',
                      value: monitor.certificateIssuer ?? '—',
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.listBullets,
                      label: 'Subject alternative names',
                      value: monitor.certificateSubjectAlternativeNames.isEmpty
                          ? '—'
                          : monitor.certificateSubjectAlternativeNames.join(
                              '\n',
                            ),
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.calendarCheck,
                      label: 'Valid from',
                      value: _formatDate(monitor.certificateValidFrom),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.binary,
                      label: 'Serial number',
                      value: monitor.certificateSerialNumber ?? '—',
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.fileLock,
                      label: 'Signature algorithm',
                      value: formatSignatureAlgorithm(
                        monitor.certificateSignatureAlgorithm,
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.key,
                      label: 'Public key',
                      value: _publicKeyLabel(monitor),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.fingerprint,
                      label: 'SHA-256 fingerprint',
                      value: _formatFingerprint(monitor.certificateFingerprint),
                      monospace: true,
                      last: true,
                    ),
                  ],
                ),
              ],
              if (widget.focusKind == MonitorCheckKind.emailConfiguration &&
                  monitor.checksEmail) ...<Widget>[
                const SizedBox(height: 26),
                if (emailAttention != null) ...<Widget>[
                  KeyedSubtree(
                    key: _emailSectionKey,
                    child: _FocusReason(
                      key: ValueKey<String>(
                        'email-attention-${_pulseFor(MonitorCheckKind.emailConfiguration)}',
                      ),
                      finding: emailAttention,
                      animate:
                          _pulseFor(MonitorCheckKind.emailConfiguration) > 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  'Email posture',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  'Published configuration only; Akshi does not test mail delivery, reputation, or live mail flow.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (monitor.emailPosture != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    monitor.emailPosture!.hasUnavailable
                        ? 'Latest analysis attempted ${_formatDateTime(monitor.emailPosture!.checkedAt)} · saved findings retained'
                        : 'Email configuration verified ${_formatDateTime(monitor.emailPosture!.checkedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (monitor.emailPosture == null)
                  _Notice(
                    icon: monitor.emailActivity.failure == null
                        ? PhosphorIconsDuotone.info
                        : PhosphorIconsDuotone.cloudSlash,
                    title: monitor.emailActivity.failure == null
                        ? 'Email not analyzed yet'
                        : 'Email DNS lookup unavailable',
                    message: monitor.emailActivity.failure?.message ?? 'Run a check to inspect the domain’s public mail records.',
                    error: monitor.emailActivity.failure != null,
                  )
                else
                  ...monitor.emailPosture!.findings.map(
                    (finding) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MailFindingCard(finding: finding),
                    ),
                  ),
              ],
              const SizedBox(height: 26),
              Text('Freshness', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _InfoCard(
                children: <Widget>[
                  _InfoRow(
                    icon: PhosphorIconsRegular.clock,
                    label: 'Last attempted',
                    value: monitor.lastAttemptedAt == null
                        ? 'Never'
                        : _formatDateTime(monitor.lastAttemptedAt!),
                  ),
                  _InfoRow(
                    icon: PhosphorIconsDuotone.checkCircle,
                    label: 'Last verified',
                    value: monitor.lastVerifiedAt == null
                        ? 'Never'
                        : _formatDateTime(monitor.lastVerifiedAt!),
                    last: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  MonitorFinding? _attentionFinding(
    List<MonitorFinding> findings,
    MonitorCheckKind kind,
  ) {
    for (final finding in findings) {
      if (finding.kind == kind &&
          (finding.needsAttention || _activeFocusKind == kind)) {
        return finding;
      }
    }
    return null;
  }

  int _pulseFor(MonitorCheckKind kind) => _pulseVersions[kind] ?? 0;

  GlobalKey _keyFor(MonitorCheckKind kind) => switch (kind) {
    MonitorCheckKind.domainRegistration => _domainSectionKey,
    MonitorCheckKind.tlsCertificate => _tlsSectionKey,
    MonitorCheckKind.emailConfiguration => _emailSectionKey,
  };

  Future<void> _focusIssue(MonitorCheckKind kind) async {
    _focusVisitSettled = false;
    if (_activeFocusKind != kind) {
      setState(() => _activeFocusKind = kind);
    }
    await _scrollToKind(kind, forcePulse: true);
    if (mounted) {
      _focusVisitSettled = true;
    }
  }

  void _scheduleFocusScroll() {
    final focusKind = _activeFocusKind;
    if (!widget.revealAttention || focusKind == null || _focusScrollScheduled) {
      return;
    }
    _focusScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _scrollToKind(focusKind, forcePulse: true);
      if (!mounted) {
        return;
      }
      _focusVisitSettled = true;
    });
  }

  Future<void> _scrollToKind(
    MonitorCheckKind kind, {
    required bool forcePulse,
  }) async {
    final targetContext = _keyFor(kind).currentContext;
    if (targetContext == null) {
      _focusScrollScheduled = false;
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
    if (mounted) {
      _announceKind(kind, force: forcePulse);
    }
  }

  void _announceKind(MonitorCheckKind kind, {bool force = false}) {
    if (!force && _announcedKinds.contains(kind)) {
      return;
    }
    setState(() {
      _activeFocusKind = kind;
      _announcedKinds.add(kind);
      _pulseVersions[kind] = _pulseFor(kind) + 1;
    });
  }

  void _scheduleVisibilityScan() {
    if (!mounted ||
        !widget.revealAttention ||
        !_focusVisitSettled ||
        _visibilityScanScheduled) {
      return;
    }
    _visibilityScanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScanScheduled = false;
      if (mounted) {
        _scanVisibleAttention();
      }
    });
  }

  void _scanVisibleAttention() {
    final media = MediaQuery.of(context);
    final visibleTop = media.padding.top + kToolbarHeight;
    final visibleBottom = media.size.height - media.padding.bottom;

    for (final finding in _attentionFindings) {
      if (_announcedKinds.contains(finding.kind)) {
        continue;
      }
      final targetContext = _keyFor(finding.kind).currentContext;
      final box = targetContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) {
        continue;
      }
      final topLeft = box.localToGlobal(Offset.zero);
      final visibleHeight =
          math.min(topLeft.dy + box.size.height, visibleBottom) -
          math.max(topLeft.dy, visibleTop);
      final threshold = math.min(72.0, box.size.height * .35);
      if (visibleHeight >= threshold) {
        _announceKind(finding.kind);
        break;
      }
    }
  }

  MonitorEntry? _find(List<MonitorEntry> items) {
    for (final item in items) {
      if (item.id == widget.monitorId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _refresh(MonitorEntry monitor) async {
    if (ref.read(deviceOfflineProvider).value ?? false) {
      showOfflineMessage(context);
      return;
    }
    try {
      await ref.read(monitorControllerProvider.notifier).check(monitor.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Check complete. Results updated.')),
        );
    } on MonitorOfflineException {
      if (mounted) {
        showOfflineMessage(context);
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.monitor_detail.check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'monitorId': monitor.id},
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(checkUserFacingError(error))));
      }
    }
  }

  Future<void> _delete(MonitorEntry monitor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const PhosphorIcon(PhosphorIconsDuotone.trash, size: 34),
        title: const Text('Delete this monitor?'),
        content: Text(
          '${monitor.displayName} and its local reminders will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(monitorControllerProvider.notifier).delete(monitor.id);
      if (mounted) {
        context.go('/');
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.monitor_detail.delete.failed',
        error,
        stackTrace,
        data: <String, Object?>{'monitorId': monitor.id},
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(checkUserFacingError(error))));
      }
    }
  }
}

class _AttentionNavigator extends StatelessWidget {
  const _AttentionNavigator({
    required this.finding,
    required this.position,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final MonitorFinding finding;
  final int position;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = monitorStatusColor(scheme, finding.status);
    return MonitorSurface(
      radius: 18,
      color: Color.lerp(scheme.surfaceContainerLow, accent, .06),
      border: BorderSide(color: accent.withValues(alpha: .22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            PhosphorIcon(
              PhosphorIconsDuotone.bellRinging,
              size: 22,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    finding.kind.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    total == 1
                        ? '1 issue needs attention'
                        : 'Issue $position of $total',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (total > 1) ...<Widget>[
              IconButton(
                tooltip: 'Previous issue',
                visualDensity: VisualDensity.compact,
                onPressed: onPrevious,
                icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft),
              ),
              IconButton(
                tooltip: 'Next issue',
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const PhosphorIcon(PhosphorIconsRegular.caretRight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpiryPanel extends StatelessWidget {
  const _ExpiryPanel({
    required this.icon,
    required this.title,
    required this.date,
    required this.source,
    this.focus,
    this.focusPulse = 0,
    super.key,
  });

  final IconData icon;
  final String title;
  final DateTime? date;
  final String source;
  final MonitorFinding? focus;
  final int focusPulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = date?.difference(DateTime.now()).inDays;
    final focusedFinding = focus;
    final accent = focusedFinding == null
        ? scheme.primary
        : monitorStatusColor(scheme, focusedFinding.status);
    final attentionTint = scheme.brightness == Brightness.dark ? .2 : .12;
    return MonitorSurface(
      radius: 24,
      padding: const EdgeInsets.all(20),
      color: focusedFinding == null
          ? scheme.surfaceContainerLowest
          : Color.alphaBlend(
              accent.withValues(alpha: attentionTint),
              scheme.surfaceContainerLowest,
            ),
      border: focusedFinding == null
          ? null
          : BorderSide(color: accent.withValues(alpha: .72), width: 1.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (focusedFinding != null) ...<Widget>[
            _FocusReason(
              key: ValueKey<String>(
                '${focusedFinding.kind.id}-attention-$focusPulse',
              ),
              finding: focusedFinding,
              animate: focusPulse > 0,
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: PhosphorIcon(
                  icon,
                  size: 23,
                  color: scheme.onPrimaryContainer,
                  semanticLabel: title,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            days == null
                ? 'Not available'
                : days < 0
                ? 'Expired'
                : '$days days left',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            date == null ? source : '${_formatDate(date)} · $source',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FocusReason extends StatefulWidget {
  const _FocusReason({required this.finding, this.animate = false, super.key});

  final MonitorFinding finding;
  final bool animate;

  @override
  State<_FocusReason> createState() => _FocusReasonState();
}

class _FocusReasonState extends State<_FocusReason>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    if (widget.animate && !reduceMotion) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = monitorStatusColor(scheme, widget.finding.status);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final animating = _controller.isAnimating;
        final glow = animating
            ? math.sin(progress * math.pi * 2).abs() * (1 - progress * .18)
            : 0.0;
        final shakeEnvelope = progress < .82 ? 1 - (progress / .82) : 0.0;
        final shake = animating
            ? math.sin(progress * math.pi * 14) * shakeEnvelope * .22
            : 0.0;
        final scale = 1 + glow * .075;
        final baseTint = scheme.brightness == Brightness.dark ? .22 : .15;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: baseTint + glow * .1),
              scheme.surfaceContainerLowest,
            ),
            border: Border.all(
              color: accent.withValues(alpha: .48 + glow * .42),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: glow == 0
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: glow * .28),
                      blurRadius: 22 * glow,
                      spreadRadius: 2.4 * glow,
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Transform.rotate(
                angle: shake,
                child: Transform.scale(
                  scale: scale,
                  child: PhosphorIcon(
                    PhosphorIconsDuotone.bellRinging,
                    size: 24,
                    color: accent,
                    semanticLabel: 'Attention',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.finding.needsAttention
                          ? '${widget.finding.kind.label} needs attention'
                          : '${widget.finding.kind.label} current result',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.finding.summary,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurface, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(status: widget.finding.status),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MonitorSurface(
    radius: 22,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.last = false,
    this.monospace = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool last;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowIcon = icon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (rowIcon != null) ...<Widget>[
                    PhosphorIcon(
                      rowIcon,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  fontFamily: monospace ? AkshiTheme.monoFontFamily : null,
                  fontFeatures: monospace
                      ? const <FontFeature>[
                          FontFeature.slashedZero(),
                          FontFeature.tabularFigures(),
                        ]
                      : null,
                  letterSpacing: monospace ? .2 : null,
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(),
      ],
    );
  }
}

class _MailFindingCard extends StatelessWidget {
  const _MailFindingCard({required this.finding});

  final MailFinding finding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (finding.state) {
      MailFindingState.healthy => (
        PhosphorIconsDuotone.checkCircle,
        scheme.primary,
      ),
      MailFindingState.informational => (
        PhosphorIconsDuotone.info,
        scheme.secondary,
      ),
      MailFindingState.warning => (
        PhosphorIconsDuotone.warning,
        scheme.tertiary,
      ),
      MailFindingState.invalid => (PhosphorIconsDuotone.xCircle, scheme.error),
      MailFindingState.unavailable => (
        PhosphorIconsDuotone.cloudSlash,
        scheme.error,
      ),
    };
    return MonitorSurface(
      padding: const EdgeInsets.all(16),
      border: BorderSide(color: color.withValues(alpha: .24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              MonitorIconBadge(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  finding.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(finding.summary),
          if (finding.latestError != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                [
                  'Latest check unavailable: ${finding.latestError}',
                  if (finding.observedAt != null)
                    'Showing the result verified ${_formatDateTime(finding.observedAt!)}.',
                ].join(' '),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          if (finding.facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            for (final fact in finding.facts) ...<Widget>[
              Text(
                fact.label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 3),
              SelectableText(
                fact.value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: AkshiTheme.monoFontFamily,
                  fontFeatures: const <FontFeature>[FontFeature.slashedZero()],
                ),
              ),
              const SizedBox(height: 9),
            ],
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    this.error = false,
  });
  final IconData icon;
  final String title;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = AkshiTheme.infoSurface(scheme);
    final background = error ? scheme.errorContainer : info.background;
    final foreground = error ? scheme.onErrorContainer : info.foreground;
    final accent = error ? scheme.onErrorContainer : info.accent;
    final border = error ? scheme.error.withValues(alpha: .42) : info.border;
    return MonitorSurface(
      padding: const EdgeInsets.all(16),
      color: background,
      border: BorderSide(color: border),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(icon, color: accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: foreground, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _backButton(BuildContext context) => IconButton(
  tooltip: 'Back to monitors',
  onPressed: () {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  },
  icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
);

String _formatDate(DateTime? value) =>
    value == null ? '—' : formatLocalDate(value);

String _domainText(
  MonitorEntry monitor,
  String? value, {
  String unpublished = 'Not published',
}) {
  if (monitor.domainSource == null) {
    return 'Not available';
  }
  return value ?? unpublished;
}

String _domainDate(MonitorEntry monitor, DateTime? value) {
  if (monitor.domainSource == null) {
    return 'Not available';
  }
  return value == null ? 'Not published' : _formatDate(value);
}

String _formatDateTime(DateTime value) =>
    formatLocalDateTime(value, separator: ' at ');

String _trustLabel(bool? value) => switch (value) {
  true => 'Trusted',
  false => 'Certificate warning',
  null => 'Not checked',
};

String _hostnameMatchLabel(bool? value) => switch (value) {
  true => 'Matches the monitored hostname',
  false => 'Does not match the monitored hostname',
  null => 'Not available',
};

String _publicKeyLabel(MonitorEntry monitor) {
  final algorithm = formatPublicKeyAlgorithm(
    monitor.certificatePublicKeyAlgorithm,
  );
  final parts = <String>[
    if (algorithm != '—') algorithm,
    ?monitor.certificatePublicKeyDetails,
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

String _tlsEndpoint(MonitorEntry monitor) => monitor.tlsPort == 443
    ? monitor.tlsHostname
    : '${monitor.tlsHostname}:${monitor.tlsPort}';

String _formatFingerprint(String? value) {
  if (value == null || value.isEmpty) {
    return '—';
  }
  final normalized = value
      .replaceAll(':', '')
      .replaceAll(' ', '')
      .toUpperCase();
  final groups = <String>[];
  for (var index = 0; index < normalized.length; index += 4) {
    final end = index + 4 < normalized.length ? index + 4 : normalized.length;
    groups.add(normalized.substring(index, end));
  }
  return groups.join(' ');
}
