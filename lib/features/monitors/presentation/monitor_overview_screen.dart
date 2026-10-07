import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_refresh_banner.dart';
import 'package:akshi/features/monitors/presentation/widgets/site_identity.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class MonitorOverviewScreen extends ConsumerStatefulWidget {
  const MonitorOverviewScreen({required this.monitorId, super.key});

  final String monitorId;

  @override
  ConsumerState<MonitorOverviewScreen> createState() =>
      _MonitorOverviewScreenState();
}

class _MonitorOverviewScreenState extends ConsumerState<MonitorOverviewScreen> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(monitorControllerProvider);
    final refresh = ref.watch(monitorRefreshProvider);
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
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final provisioning = ref.watch(monitorProvisioningProvider)[monitor.id];
    final findings = findingsForMonitor(
      monitor,
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final overall = monitor.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final dns = monitor.dnsSnapshot;
    final recordCount =
        dns?.queries.expand((query) => query.records).length ?? 0;
    final failedQueries =
        dns?.queries
            .where((query) => query.state == DnsQueryState.failed)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            onPressed:
                checking ||
                    refresh.isRunning ||
                    (provisioning?.isRunning ?? false)
                ? null
                : () => context.push('/monitor/${monitor.id}/edit'),
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
            ? () => ref.read(monitorControllerProvider.notifier).refreshAll()
            : () => _refresh(monitor),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            if (refresh.shouldShowStatus) ...<Widget>[
              const MonitorRefreshBanner(),
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
                      const SizedBox(height: 5),
                      Text(
                        monitor.hostname,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                children: monitor.tags.map((tag) => TagPill(tag: tag)).toList(),
              ),
            ],
            const SizedBox(height: 18),
            if (provisioning != null) ...<Widget>[
              _MonitorProgressCard(
                progress: provisioning.progress,
                failure: provisioning.failure,
                failureTitle: 'Initial check needs another try',
                description:
                    'Initial checks continue in the background and are saved '
                    'together as one consistent snapshot. They can take time '
                    'and depend on your connection and each source, so please '
                    'be patient.',
                failureDescription:
                    'The monitor definition is saved safely. Use Check now to '
                    'retry the initial snapshot.',
              ),
              const SizedBox(height: 14),
            ] else if (checkProgress != null) ...<Widget>[
              _MonitorProgressCard(
                progress: checkProgress,
                description:
                    'Akshi is checking the selected domain, DNS, certificate, '
                    'site identity, and email sources. New results appear '
                    'together when the complete snapshot is ready.',
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: <Widget>[
                StatusPill(status: overall),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      checking ||
                          refresh.isRunning ||
                          (provisioning?.isRunning ?? false)
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
            const SizedBox(height: 24),
            Text('Overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final finding in findings) ...<Widget>[
              _SectionCard(
                icon: _iconFor(finding.kind),
                title: finding.kind.label,
                summary: finding.summary,
                status: finding.status,
                onTap: () => context.push(
                  '/monitor/${monitor.id}/${_pathFor(finding.kind)}',
                ),
              ),
              const SizedBox(height: 10),
            ],
            _SectionCard(
              icon: PhosphorIconsDuotone.network,
              title: 'DNS records',
              summary: dns == null
                  ? 'No DNS snapshot yet'
                  : failedQueries > 0
                  ? '$recordCount records captured · '
                        '$failedQueries lookups could not be read'
                  : '$recordCount records captured',
              status: null,
              onTap: () => context.push('/monitor/${monitor.id}/dns'),
            ),
            const SizedBox(height: 18),
            Text(
              <String>[
                monitor.lastAttemptedAt == null
                    ? 'No check attempted yet'
                    : 'Last attempt ${_formatDateTime(monitor.lastAttemptedAt!)}',
                monitor.lastVerifiedAt == null
                    ? 'Never fully verified'
                    : 'Last verified ${_formatDateTime(monitor.lastVerifiedAt!)}',
              ].join('\n'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  MonitorEntry? _find(List<MonitorEntry> items) {
    for (final item in items) {
      if (item.id == widget.monitorId) return item;
    }
    return null;
  }

  Future<void> _refresh(MonitorEntry monitor) async {
    ref.read(monitorProvisioningProvider.notifier).clear(monitor.id);
    try {
      await ref.read(monitorControllerProvider.notifier).check(monitor.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Check complete. Results updated.')),
          );
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.monitor_overview.check.failed',
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
    if (confirmed != true) return;
    try {
      await ref.read(monitorControllerProvider.notifier).delete(monitor.id);
      if (mounted) context.go('/');
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.monitor_overview.delete.failed',
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

class _MonitorProgressCard extends StatelessWidget {
  const _MonitorProgressCard({
    required this.progress,
    required this.description,
    this.failure,
    this.failureTitle,
    this.failureDescription,
  }) : assert(failure == null || failureTitle != null),
       assert(failure == null || failureDescription != null);

  final MonitorSaveProgress progress;
  final String description;
  final String? failure;
  final String? failureTitle;
  final String? failureDescription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = failure != null;
    final colors = AkshiTheme.progressSurface(scheme);
    final background = failed ? scheme.errorContainer : colors.background;
    final foreground = failed ? scheme.onErrorContainer : colors.foreground;
    final accent = failed ? scheme.error : colors.accent;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: failed ? scheme.error.withValues(alpha: .45) : colors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 20,
                  child: failed
                      ? PhosphorIcon(
                          PhosphorIconsDuotone.warningCircle,
                          color: accent,
                          size: 20,
                        )
                      : CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: accent,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    failed ? failureTitle! : progress.message,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!failed) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.fraction,
                color: accent,
                backgroundColor: foreground.withValues(alpha: .16),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              failed ? failureDescription! : description,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.summary,
    this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final MonitorStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentStatus = status;
    final accent = currentStatus == null
        ? scheme.primary
        : monitorStatusColor(scheme, currentStatus);
    final attention = switch (currentStatus) {
      MonitorStatus.warning ||
      MonitorStatus.critical ||
      MonitorStatus.expired ||
      MonitorStatus.failed ||
      MonitorStatus.unavailable => true,
      MonitorStatus.unknown ||
      MonitorStatus.healthy ||
      MonitorStatus.incomplete ||
      null => false,
    };
    return Material(
      color: attention
          ? Color.alphaBlend(
              accent.withValues(
                alpha: scheme.brightness == Brightness.dark ? .18 : .1,
              ),
              scheme.surfaceContainerLowest,
            )
          : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: attention
              ? accent.withValues(alpha: .5)
              : scheme.outlineVariant.withValues(alpha: .45),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: PhosphorIcon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (currentStatus != null) ...<Widget>[
                StatusPill(status: currentStatus),
                const SizedBox(width: 4),
              ],
              const PhosphorIcon(PhosphorIconsDuotone.caretRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(MonitorCheckKind kind) => switch (kind) {
  MonitorCheckKind.domainRegistration =>
    PhosphorIconsDuotone.globeHemisphereWest,
  MonitorCheckKind.tlsCertificate => PhosphorIconsDuotone.certificate,
  MonitorCheckKind.emailConfiguration =>
    PhosphorIconsDuotone.envelopeSimpleOpen,
};

String _pathFor(MonitorCheckKind kind) => switch (kind) {
  MonitorCheckKind.domainRegistration => 'domain',
  MonitorCheckKind.tlsCertificate => 'tls',
  MonitorCheckKind.emailConfiguration => 'email',
};

Widget _backButton(BuildContext context) => IconButton(
  tooltip: 'Back to monitors',
  onPressed: () => context.canPop() ? context.pop() : context.go('/'),
  icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
);

String _formatDateTime(DateTime value) => formatLocalDateTime(value);
