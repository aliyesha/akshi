import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
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
  var _checking = false;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(monitorControllerProvider);
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
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
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
            onPressed: () => context.push('/monitor/${monitor.id}/edit'),
            icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _delete(monitor),
            icon: const PhosphorIcon(PhosphorIconsDuotone.trash),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(monitor),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
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
            Row(
              children: <Widget>[
                StatusPill(status: overall),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _checking ? null : () => _refresh(monitor),
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const PhosphorIcon(
                          PhosphorIconsRegular.arrowsClockwise,
                          size: 17,
                        ),
                  label: Text(_checking ? 'Checking' : 'Check now'),
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
                  ? '$recordCount records · $failedQueries lookups unavailable'
                  : '$recordCount records from ${dns.queries.where((query) => query.state == DnsQueryState.answered).length} groups',
              status: dns == null
                  ? MonitorStatus.unknown
                  : failedQueries > 0
                  ? MonitorStatus.unavailable
                  : MonitorStatus.healthy,
              onTap: () => context.push('/monitor/${monitor.id}/dns'),
            ),
            const SizedBox(height: 18),
            Text(
              monitor.lastCheckedAt == null
                  ? 'Not checked yet'
                  : 'Last checked ${_formatDateTime(context, monitor.lastCheckedAt!)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await ref.read(monitorControllerProvider.notifier).check(monitor.id);
    } finally {
      if (mounted) setState(() => _checking = false);
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
    await ref.read(monitorControllerProvider.notifier).delete(monitor.id);
    if (mounted) context.go('/');
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final MonitorStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = monitorStatusColor(scheme, status);
    final attention = switch (status) {
      MonitorStatus.warning ||
      MonitorStatus.critical ||
      MonitorStatus.expired ||
      MonitorStatus.failed ||
      MonitorStatus.unavailable => true,
      MonitorStatus.unknown || MonitorStatus.healthy => false,
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
              StatusPill(status: status),
              const SizedBox(width: 4),
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

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatFullDate(local)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
