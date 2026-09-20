import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class AttentionScreen extends ConsumerWidget {
  const AttentionScreen({
    required this.source,
    required this.monitorIds,
    super.key,
  });

  final String source;
  final List<String> monitorIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitors = ref.watch(monitorControllerProvider);
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
    final title = source == 'changes' ? 'Recent changes' : 'Needs attention';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: monitors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(monitorControllerProvider),
        ),
        data: (items) {
          final visible = _visible(items, settings);
          final missing = monitorIds.length - visible.length;
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(monitorControllerProvider.notifier).refreshAll(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              children: <Widget>[
                _AttentionHeader(
                  count: visible.length,
                  source: source,
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
  });

  final int count;
  final String source;
  final int missing;

  @override
  Widget build(BuildContext context) {
    final changes = source == 'changes';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            changes ? LucideIcons.sparkle : LucideIcons.circle_alert,
            size: 32,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  changes
                      ? '$count ${count == 1 ? 'monitor has' : 'monitors have'} recent changes'
                      : '$count ${count == 1 ? 'monitor needs' : 'monitors need'} attention',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
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
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/monitor/${monitor.id}'),
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
                  const Icon(LucideIcons.chevron_right, size: 17),
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
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(switch (finding.kind) {
        MonitorCheckKind.domainRegistration => Icons.public_rounded,
        MonitorCheckKind.tlsCertificate => Icons.verified_user_rounded,
        MonitorCheckKind.emailConfiguration => LucideIcons.mail_check,
      }, size: 21),
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      StatusPill(status: finding.status),
    ],
  );
}

class _ClearState extends StatelessWidget {
  const _ClearState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
    child: Column(
      children: <Widget>[
        Icon(
          LucideIcons.shield_check,
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
