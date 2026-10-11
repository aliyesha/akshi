import 'package:akshi/app/providers.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_refresh_banner.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class AttentionScreen extends ConsumerWidget {
  const AttentionScreen({
    required this.source,
    required this.monitorIds,
    this.alarmDate,
    super.key,
  });

  final String source;
  final List<String> monitorIds;
  final String? alarmDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitors = ref.watch(monitorControllerProvider);
    final refresh = ref.watch(monitorRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final title = source == 'expiry' ? 'Expiry reminder' : 'Needs attention';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: refresh.isRunning ? 'Refreshing…' : 'Refresh all',
            onPressed: refresh.isRunning || offline
                ? null
                : () => _refreshAll(context, ref, announce: true),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: refresh.isRunning
                  ? const SizedBox.square(
                      key: ValueKey<String>('refresh-progress'),
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const PhosphorIcon(
                      PhosphorIconsRegular.arrowsClockwise,
                      key: ValueKey<String>('refresh-icon'),
                    ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: monitors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          appLogger.error('ui.attention.load.failed', error, stack);
          return AsyncErrorView(
            onRetry: () => ref.invalidate(monitorControllerProvider),
          );
        },
        data: (items) {
          final visible = _visible(items, settings);
          final missing = monitorIds.length - visible.length;
          return RefreshIndicator(
            onRefresh: () => _refreshAll(context, ref, announce: false),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              children: <Widget>[
                if (refresh.shouldShowStatus) ...<Widget>[
                  const MonitorRefreshBanner(),
                  const SizedBox(height: 14),
                ],
                if (offline) ...<Widget>[
                  const OfflineNotice(),
                  const SizedBox(height: 14),
                ],
                _AttentionHeader(
                  count: visible.length,
                  source: source,
                  alarmDate: alarmDate,
                  missing: missing > 0 ? missing : 0,
                ),
                const SizedBox(height: 16),
                if (visible.isEmpty)
                  const _ClearState()
                else
                  for (final monitor in visible) ...<Widget>[
                    _AttentionCard(
                      monitor: monitor,
                      settings: settings,
                      showResolved: source == 'expiry' && monitorIds.isNotEmpty,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshAll(
    BuildContext context,
    WidgetRef ref, {
    required bool announce,
  }) async {
    try {
      final outcome = await ref
          .read(monitorControllerProvider.notifier)
          .refreshAll();
      if (!context.mounted) return;
      if (outcome == MonitorRefreshOutcome.skippedOffline) {
        showOfflineMessage(context);
        return;
      }
      if (!announce) return;
      final message = outcome == MonitorRefreshOutcome.skippedRecent
          ? 'The monitor list was checked recently.'
          : 'Monitors checked.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error, stackTrace) {
      appLogger.error('ui.attention.refresh.failed', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(checkUserFacingError(error))));
      }
    }
  }

  List<MonitorEntry> _visible(
    List<MonitorEntry> monitors,
    AppSettings settings,
  ) {
    if (monitorIds.isNotEmpty) {
      final byId = <String, MonitorEntry>{
        for (final item in monitors) item.id: item,
      };
      return monitorIds
          .map((id) => byId[id])
          .whereType<MonitorEntry>()
          .toList();
    }
    return monitors.where((monitor) {
      final findings = findingsForMonitor(
        monitor,
        warningDays: settings.firstWarningDays,
        criticalDays: settings.secondWarningDays,
      );
      return findings.any((finding) => finding.needsAttention);
    }).toList();
  }
}

class _AttentionHeader extends StatelessWidget {
  const _AttentionHeader({
    required this.count,
    required this.source,
    required this.missing,
    this.alarmDate,
  });

  final int count;
  final String source;
  final int missing;
  final String? alarmDate;

  @override
  Widget build(BuildContext context) {
    final fromReminder = source == 'expiry';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          PhosphorIcon(
            fromReminder
                ? PhosphorIconsDuotone.bellRinging
                : PhosphorIconsDuotone.warningCircle,
            size: 32,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fromReminder
                      ? '$count expiry ${count == 1 ? 'reminder' : 'reminders'}'
                      : '$count ${count == 1 ? 'monitor needs' : 'monitors need'} attention',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 5),
                Text(
                  fromReminder
                      ? '${alarmDate == null ? '' : 'Scheduled for $alarmDate. '}'
                            'Opened from a scheduled expiry alert. It used the '
                            'last saved expiry dates; a newer check may have '
                            'resolved it.'
                      : 'These current results need review.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    height: 1.35,
                  ),
                ),
                if (missing > 0) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    '$missing no longer ${missing == 1 ? 'exists' : 'exist'} locally.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.monitor,
    required this.settings,
    required this.showResolved,
  });

  final MonitorEntry monitor;
  final AppSettings settings;
  final bool showResolved;

  @override
  Widget build(BuildContext context) {
    final findings = findingsForMonitor(
      monitor,
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final resolved = !findings.any((finding) => finding.needsAttention);
    final scheme = Theme.of(context).colorScheme;
    final status = monitor.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final accent = monitorStatusColor(scheme, status);
    final attentionTint = scheme.brightness == Brightness.dark ? .15 : .09;
    final cardColor = resolved
        ? scheme.surfaceContainerLowest
        : Color.alphaBlend(
            accent.withValues(alpha: attentionTint),
            scheme.surfaceContainerLowest,
          );
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: resolved
            ? BorderSide.none
            : BorderSide(color: accent.withValues(alpha: .46), width: 1.2),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(_detailLocation(monitor.id, findings)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          monitor.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          monitor.hostname,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const PhosphorIcon(PhosphorIconsDuotone.caretRight, size: 17),
                ],
              ),
              if (monitor.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: monitor.tags
                      .map((tag) => TagPill(tag: tag))
                      .toList(),
                ),
              ],
              if (showResolved && resolved) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  'Resolved since notification',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              for (final finding in findings) ...<Widget>[
                _FindingRow(finding: finding),
                if (finding != findings.last) const Divider(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final MonitorFinding finding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = monitorStatusColor(scheme, finding.status);
    final iconColor = finding.needsAttention ? accent : scheme.onSurfaceVariant;
    final icon = switch (finding.kind) {
      MonitorCheckKind.domainRegistration =>
        PhosphorIconsDuotone.globeHemisphereWest,
      MonitorCheckKind.tlsCertificate => PhosphorIconsDuotone.certificate,
      MonitorCheckKind.emailConfiguration =>
        PhosphorIconsDuotone.envelopeSimpleOpen,
    };
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(
              alpha: finding.needsAttention ? .14 : .07,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: PhosphorIcon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                finding.kind.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                finding.summary,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(status: finding.status),
      ],
    );
  }
}

class _ClearState extends StatelessWidget {
  const _ClearState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
    child: Column(
      children: <Widget>[
        PhosphorIcon(
          PhosphorIconsDuotone.shieldCheck,
          size: 58,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Nothing needs attention',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        const Text(
          'The latest local results are clear.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

String _detailLocation(String monitorId, List<MonitorFinding> findings) {
  MonitorFinding? focus;
  for (final finding in findings) {
    if (finding.needsAttention) {
      focus = finding;
      break;
    }
  }
  focus ??= findings.isEmpty ? null : findings.first;
  final path = switch (focus?.kind) {
    MonitorCheckKind.domainRegistration => 'domain',
    MonitorCheckKind.tlsCertificate => 'tls',
    MonitorCheckKind.emailConfiguration => 'email',
    null => null,
  };
  return path == null
      ? '/monitor/$monitorId'
      : '/monitor/$monitorId/$path?attention=1';
}
