import 'dart:math' as math;

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';

import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/formatters/certificate_algorithm_formatter.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/core/time/calendar_day.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/domain/check_activity.dart';
import 'package:akshi/features/domains/domain/email_posture.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/domain_finding.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_surface.dart';
import 'package:akshi/features/domains/presentation/widgets/site_identity.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class DomainDetailScreen extends ConsumerStatefulWidget {
  const DomainDetailScreen({
    required this.domainId,
    this.focusKind,
    this.revealAttention = false,
    super.key,
  });

  final String domainId;
  final DomainCheckKind? focusKind;

  /// Whether this visit came from the Attention screen. Section selection and
  /// attention reveal are separate so ordinary detail navigation never scrolls
  /// or pulses automatically.
  final bool revealAttention;

  @override
  ConsumerState<DomainDetailScreen> createState() => _DomainDetailScreenState();
}

class _DomainDetailScreenState extends ConsumerState<DomainDetailScreen> {
  final _domainSectionKey = GlobalKey();
  final _tlsSectionKey = GlobalKey();
  final _emailSectionKey = GlobalKey();
  final _scrollController = ScrollController();
  final _announcedKinds = <DomainCheckKind>{};
  final _pulseVersions = <DomainCheckKind, int>{};
  List<DomainFinding> _attentionFindings = const <DomainFinding>[];
  late DomainCheckKind? _activeFocusKind;
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
  void didUpdateWidget(covariant DomainDetailScreen oldWidget) {
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
    final items = ref.watch(domainControllerProvider);
    final refresh = ref.watch(domainRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final domain = _find(items.value ?? const <DomainEntry>[]);
    if (domain == null) {
      return Scaffold(
        appBar: AppBar(leading: _backButton(context)),
        body: Center(
          child: items.isLoading
              ? const CircularProgressIndicator()
              : const Text('Domain not found'),
        ),
      );
    }
    final checkProgress = ref.watch(
      domainCheckActivityProvider.select((active) => active[domain.id]),
    );
    final checking = checkProgress != null;
    final status = domain.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final focusedFailure = switch (widget.focusKind) {
      DomainCheckKind.domainRegistration => domain.domainActivity.failure,
      DomainCheckKind.tlsCertificate => domain.certificateActivity.failure,
      DomainCheckKind.emailConfiguration => domain.emailActivity.failure,
      null => null,
    };
    final focusConnectionInterrupted =
        focusedFailure.isConnectivityInterruption;
    final findings = findingsForDomain(
      domain,
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
      DomainCheckKind.domainRegistration,
    );
    final tlsAttention = _attentionFinding(
      findings,
      DomainCheckKind.tlsCertificate,
    );
    final emailAttention = _attentionFinding(
      findings,
      DomainCheckKind.emailConfiguration,
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
                    context.push('/domain/${domain.id}/edit');
                  },
            icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: checking || refresh.isRunning
                ? null
                : () => _delete(domain),
            icon: const PhosphorIcon(PhosphorIconsDuotone.trash),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh.isRunning
            ? () async {
                await ref.read(domainControllerProvider.notifier).refreshAll();
              }
            : () => _refresh(domain),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (refresh.shouldShowStatus) ...<Widget>[
                const DomainRefreshBanner(),
                const SizedBox(height: 14),
              ],
              if (offline) ...<Widget>[
                const OfflineNotice(),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SiteIdentity(domain: domain, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          domain.displayName,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          domain.hostname,
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
              if (domain.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: domain.tags
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
                        : () => _refresh(domain),
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
              if (widget.focusKind == DomainCheckKind.tlsCertificate &&
                  domain.certificateChanged) ...<Widget>[
                const SizedBox(height: 18),
                _Notice(
                  icon: PhosphorIconsDuotone.sparkle,
                  title: 'Renewal detected',
                  message: 'The live certificate fingerprint changed on the latest check.',
                ),
              ],
              if ((widget.focusKind == DomainCheckKind.domainRegistration &&
                      domain.domainError != null) ||
                  (widget.focusKind == DomainCheckKind.tlsCertificate &&
                      domain.certificateError != null) ||
                  (widget.focusKind == DomainCheckKind.emailConfiguration &&
                      domain.emailActivity.failure != null)) ...<Widget>[
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
                              DomainCheckKind.domainRegistration)
                            'Domain: ${domain.domainError}',
                          if (widget.focusKind ==
                              DomainCheckKind.tlsCertificate)
                            'Certificate: ${domain.certificateError}',
                          if (widget.focusKind ==
                              DomainCheckKind.emailConfiguration)
                            'Email: ${domain.emailActivity.failure!.message}',
                        ].join(String.fromCharCode(10)),
                  error: !focusConnectionInterrupted,
                ),
              ],
              if (widget.focusKind ==
                  DomainCheckKind.domainRegistration) ...<Widget>[
                const SizedBox(height: 26),
                _ExpiryPanel(
                  key: _domainSectionKey,
                  icon: PhosphorIconsDuotone.globeHemisphereWest,
                  title: 'Domain registration',
                  date: domain.domainExpiresAt,
                  source: domain.domainSource == null
                      ? 'No registry date available'
                      : 'Verified through ${domain.domainSource}',
                  focus: domainAttention,
                  focusPulse: _pulseFor(DomainCheckKind.domainRegistration),
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
                      value: _domainText(domain, domain.domainRegistrar),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.identificationCard,
                      label: 'Public registrant',
                      value: _domainText(
                        domain,
                        domain.domainPublicRegistrant,
                        unpublished: 'Not publicly disclosed',
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.calendarCheck,
                      label: 'Registered',
                      value: _domainDate(domain, domain.domainRegisteredAt),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.clock,
                      label: 'Last changed',
                      value: _domainDate(domain, domain.domainUpdatedAt),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.network,
                      label: 'Name servers',
                      value: _domainText(
                        domain,
                        domain.domainNameServers.isEmpty
                            ? null
                            : domain.domainNameServers.join('\n'),
                      ),
                      monospace: true,
                      last: true,
                    ),
                  ],
                ),
              ],
              if (widget.focusKind == DomainCheckKind.tlsCertificate &&
                  domain.checksCertificate) ...<Widget>[
                const SizedBox(height: 12),
                _ExpiryPanel(
                  key: _tlsSectionKey,
                  icon: PhosphorIconsDuotone.certificate,
                  title: 'TLS certificate',
                  date: domain.certificateExpiresAt,
                  source: domain.certificateIssuer == null
                      ? 'No certificate data available'
                      : 'Issued by ${formatCertificateIssuer(domain.certificateIssuer!)}',
                  focus: tlsAttention,
                  focusPulse: _pulseFor(DomainCheckKind.tlsCertificate),
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
                      value: _tlsEndpoint(domain),
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.shieldCheck,
                      label: 'Trust',
                      value: _trustLabel(domain.tlsTrusted),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.sealCheck,
                      label: 'Hostname match',
                      value: _hostnameMatchLabel(
                        domain.certificateHostnameMatches,
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.identificationCard,
                      label: 'Subject',
                      value: domain.certificateSubject ?? '—',
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.bank,
                      label: 'Issuer',
                      value: domain.certificateIssuer ?? '—',
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.listBullets,
                      label: 'Subject alternative names',
                      value: domain.certificateSubjectAlternativeNames.isEmpty
                          ? '—'
                          : domain.certificateSubjectAlternativeNames.join(
                              '\n',
                            ),
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.calendarCheck,
                      label: 'Valid from',
                      value: _formatDate(domain.certificateValidFrom),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsRegular.binary,
                      label: 'Serial number',
                      value: domain.certificateSerialNumber ?? '—',
                      monospace: true,
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.fileLock,
                      label: 'Signature algorithm',
                      value: formatSignatureAlgorithm(
                        domain.certificateSignatureAlgorithm,
                      ),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.key,
                      label: 'Public key',
                      value: _publicKeyLabel(domain),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsDuotone.fingerprint,
                      label: 'SHA-256 fingerprint',
                      value: _formatFingerprint(domain.certificateFingerprint),
                      monospace: true,
                      last: true,
                    ),
                  ],
                ),
              ],
              if (widget.focusKind == DomainCheckKind.emailConfiguration &&
                  domain.checksEmail) ...<Widget>[
                const SizedBox(height: 26),
                if (emailAttention != null) ...<Widget>[
                  KeyedSubtree(
                    key: _emailSectionKey,
                    child: _FocusReason(
                      key: ValueKey<String>(
                        'email-attention-${_pulseFor(DomainCheckKind.emailConfiguration)}',
                      ),
                      finding: emailAttention,
                      animate:
                          _pulseFor(DomainCheckKind.emailConfiguration) > 0,
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
                if (domain.emailPosture != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    domain.emailPosture!.hasUnavailable
                        ? 'Latest analysis attempted ${_formatDateTime(domain.emailPosture!.checkedAt)} · saved findings retained'
                        : 'Published email configuration checked ${_formatDateTime(domain.emailPosture!.checkedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (domain.emailPosture == null)
                  _Notice(
                    icon: domain.emailActivity.failure == null
                        ? PhosphorIconsDuotone.info
                        : PhosphorIconsDuotone.cloudSlash,
                    title: domain.emailActivity.failure == null
                        ? 'Email not analyzed yet'
                        : 'Email DNS lookup unavailable',
                    message: domain.emailActivity.failure?.message ?? 'Run a check to inspect the domain’s public mail records.',
                    error: domain.emailActivity.failure != null,
                  )
                else
                  ...domain.emailPosture!.findings.map(
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
                    value: domain.lastAttemptedAt == null
                        ? 'Never'
                        : _formatDateTime(domain.lastAttemptedAt!),
                  ),
                  _InfoRow(
                    icon: PhosphorIconsDuotone.checkCircle,
                    label: 'Last verified',
                    value: domain.lastVerifiedAt == null
                        ? 'Never'
                        : _formatDateTime(domain.lastVerifiedAt!),
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

  DomainFinding? _attentionFinding(
    List<DomainFinding> findings,
    DomainCheckKind kind,
  ) {
    for (final finding in findings) {
      if (finding.kind == kind &&
          (finding.needsAttention || _activeFocusKind == kind)) {
        return finding;
      }
    }
    return null;
  }

  int _pulseFor(DomainCheckKind kind) => _pulseVersions[kind] ?? 0;

  GlobalKey _keyFor(DomainCheckKind kind) => switch (kind) {
    DomainCheckKind.domainRegistration => _domainSectionKey,
    DomainCheckKind.tlsCertificate => _tlsSectionKey,
    DomainCheckKind.emailConfiguration => _emailSectionKey,
  };

  Future<void> _focusIssue(DomainCheckKind kind) async {
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
    DomainCheckKind kind, {
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

  void _announceKind(DomainCheckKind kind, {bool force = false}) {
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

  DomainEntry? _find(List<DomainEntry> items) {
    for (final item in items) {
      if (item.id == widget.domainId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _refresh(DomainEntry domain) async {
    if (ref.read(deviceOfflineProvider).value ?? false) {
      showOfflineMessage(context);
      return;
    }
    try {
      await ref.read(domainControllerProvider.notifier).check(domain.id);
      if (!mounted) return;
      showAkshiNotice(
        context,
        title: 'Check complete',
        message: 'Latest results are saved.',
        tone: AkshiNoticeTone.success,
      );
    } on DomainOfflineException {
      if (mounted) {
        showOfflineMessage(context);
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.domain_detail.check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'domainId': domain.id},
      );
      if (mounted) {
        showAkshiNotice(
          context,
          title: 'Check failed',
          message: checkUserFacingError(error),
          tone: AkshiNoticeTone.error,
        );
      }
    }
  }

  Future<void> _delete(DomainEntry domain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const PhosphorIcon(PhosphorIconsDuotone.trash, size: 34),
        title: const Text('Delete this domain?'),
        content: Text(
          '${domain.displayName} and its local reminders will be removed.',
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
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(domainControllerProvider.notifier).delete(domain.id);
      if (mounted) {
        context.go('/');
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.domain_detail.delete.failed',
        error,
        stackTrace,
        data: <String, Object?>{'domainId': domain.id},
      );
      if (mounted) {
        showAkshiNotice(
          context,
          title: 'Could not delete domain',
          message: checkUserFacingError(error),
          tone: AkshiNoticeTone.error,
        );
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

  final DomainFinding finding;
  final int position;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = domainStatusColor(scheme, finding.status);
    return DomainSurface(
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
  final DomainFinding? focus;
  final int focusPulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final expiry = date;
    final days = expiry == null
        ? null
        : localCalendarDayDifference(from: now, to: expiry);
    final focusedFinding = focus;
    final accent = focusedFinding == null
        ? scheme.primary
        : domainStatusColor(scheme, focusedFinding.status);
    final attentionTint = scheme.brightness == Brightness.dark ? .2 : .12;
    return DomainSurface(
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
            expiry == null
                ? 'Not available'
                : !expiry.isAfter(now)
                ? 'Expired'
                : days == 0
                ? 'Expires today'
                : days == 1
                ? '1 day left'
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

  final DomainFinding finding;
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
    final accent = domainStatusColor(scheme, widget.finding.status);
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
  Widget build(BuildContext context) => DomainSurface(
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
    return DomainSurface(
      padding: const EdgeInsets.all(16),
      border: BorderSide(color: color.withValues(alpha: .24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              DomainIconBadge(icon: icon, color: color),
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
    return DomainSurface(
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
  tooltip: 'Back to domains',
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
  DomainEntry domain,
  String? value, {
  String unpublished = 'Not published',
}) {
  if (domain.domainSource == null) {
    return 'Not available';
  }
  return value ?? unpublished;
}

String _domainDate(DomainEntry domain, DateTime? value) {
  if (domain.domainSource == null) {
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
  true => 'Matches the configured hostname',
  false => 'Does not match the configured hostname',
  null => 'Not available',
};

String _publicKeyLabel(DomainEntry domain) {
  final algorithm = formatPublicKeyAlgorithm(
    domain.certificatePublicKeyAlgorithm,
  );
  final parts = <String>[
    if (algorithm != '—') algorithm,
    ?domain.certificatePublicKeyDetails,
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

String _tlsEndpoint(DomainEntry domain) => domain.tlsPort == 443
    ? domain.tlsHostname
    : '${domain.tlsHostname}:${domain.tlsPort}';

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
