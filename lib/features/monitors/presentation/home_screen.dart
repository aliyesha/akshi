import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_mark.dart';
import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/core/widgets/expiry_metric.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _query = '';
  String? _selectedTagId;
  var _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final monitors = ref.watch(monitorControllerProvider);
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add monitor',
        onPressed: () => context.push('/monitor/new'),
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        bottom: false,
        child: monitors.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => AsyncErrorView(
            error: error,
            onRetry: () => ref.invalidate(monitorControllerProvider),
          ),
          data: (items) {
            final tags = _availableTags(items);
            final offline = items.any(_hasOfflineFailure);
            if (_selectedTagId != null &&
                !tags.any((tag) => tag.id == _selectedTagId)) {
              _selectedTagId = null;
            }
            final visible = items.where((item) {
              final query = _query.trim().toLowerCase();
              final matchesQuery =
                  query.isEmpty ||
                  item.hostname.contains(query) ||
                  (item.label?.toLowerCase().contains(query) ?? false) ||
                  item.tags.any(
                    (tag) => tag.name.toLowerCase().contains(query),
                  );
              final matchesTag =
                  _selectedTagId == null ||
                  item.tags.any((tag) => tag.id == _selectedTagId);
              return matchesQuery && matchesTag;
            }).toList();
            return RefreshIndicator(
              onRefresh: () => _refreshAll(announce: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  SliverAppBar(
                    pinned: true,
                    toolbarHeight: 72,
                    leadingWidth: 72,
                    leading: const Padding(
                      padding: EdgeInsets.fromLTRB(18, 12, 8, 12),
                      child: AkshiMark(),
                    ),
                    title: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Akshi'),
                        Text(
                          'Watch What Matters',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    actions: <Widget>[
                      IconButton(
                        tooltip: _refreshing ? 'Refreshing…' : 'Refresh all',
                        onPressed: items.isEmpty || _refreshing
                            ? null
                            : () => _refreshAll(),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _refreshing
                              ? const SizedBox.square(
                                  key: ValueKey<String>('refresh-progress'),
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.refresh_cw,
                                  key: ValueKey<String>('refresh-icon'),
                                ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => context.push('/settings'),
                        icon: const Icon(LucideIcons.sliders_horizontal),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PortfolioCard(items: items, settings: settings),
                    ),
                  ),
                  if (offline)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(18, 10, 18, 0),
                      sliver: SliverToBoxAdapter(child: _OfflineNotice()),
                    ),
                  if (items.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
                      sliver: SliverToBoxAdapter(
                        child: SearchBar(
                          hintText: 'Search domains, labels, or tags',
                          leading: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(LucideIcons.search),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                    ),
                  if (tags.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 0, 2),
                      sliver: SliverToBoxAdapter(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(right: 18),
                          child: Row(
                            children: <Widget>[
                              for (final tag in tags) ...<Widget>[
                                TagPill(
                                  tag: tag,
                                  selected: _selectedTagId == tag.id,
                                  onTap: () => setState(
                                    () => _selectedTagId =
                                        _selectedTagId == tag.id
                                        ? null
                                        : tag.id,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(),
                    )
                  else if (visible.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No matching monitors')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _SwipeableMonitorCard(
                          monitor: visible[index],
                          settings: settings,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refreshAll({bool announce = true}) async {
    final controller = ref.read(monitorControllerProvider.notifier);
    if (_refreshing) {
      await controller.refreshAll();
      return;
    }

    setState(() => _refreshing = true);
    final enabledCount =
        (ref.read(monitorControllerProvider).value ?? const <MonitorEntry>[])
            .where((monitor) => monitor.enabled)
            .length;
    try {
      await controller.refreshAll();
      if (!mounted || !announce) return;
      final message = enabledCount == 0
          ? 'No enabled monitors to check.'
          : enabledCount == 1
          ? '1 monitor checked.'
          : '$enabledCount monitors checked.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Refresh failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<MonitorTag> _availableTags(List<MonitorEntry> items) {
    final byId = <String, MonitorTag>{};
    for (final monitor in items) {
      for (final tag in monitor.tags) {
        byId[tag.id] = tag;
      }
    }
    final tags = byId.values.toList()
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    return tags;
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.wifi_off, size: 19, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are offline · showing saved results',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({required this.items, required this.settings});

  final List<MonitorEntry> items;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attention = items.where((item) {
      final status = item.overallStatus(
        warningDays: settings.firstWarningDays,
        criticalDays: settings.secondWarningDays,
      );
      return status != MonitorStatus.healthy && status != MonitorStatus.unknown;
    }).length;
    final allGood = items.isNotEmpty && attention == 0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              scheme.primaryContainer,
              Color.lerp(
                scheme.primaryContainer,
                scheme.tertiaryContainer,
                .22,
              )!,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          onTap: attention > 0 ? () => context.push('/attention') : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: (180) / 255),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    allGood ? LucideIcons.shield_check : LucideIcons.activity,
                    size: 22,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        items.isEmpty
                            ? 'Ready when you are'
                            : allGood
                            ? 'Everything looks calm'
                            : '$attention ${attention == 1 ? 'item needs' : 'items need'} attention',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        items.isEmpty
                            ? 'Add your first domain to begin.'
                            : attention > 0
                            ? 'Open the attention list · ${items.length} monitored'
                            : '${items.length} ${items.length == 1 ? 'endpoint' : 'endpoints'} · Pull down to check now',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: (190) / 255,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (attention > 0)
                  Icon(
                    LucideIcons.chevron_right,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeableMonitorCard extends ConsumerWidget {
  const _SwipeableMonitorCard({required this.monitor, required this.settings});

  final MonitorEntry monitor;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey<String>(monitor.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: .35,
        DismissDirection.endToStart: .35,
      },
      background: _SwipeActionBackground(
        alignment: Alignment.centerLeft,
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      secondaryBackground: _SwipeActionBackground(
        alignment: Alignment.centerRight,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      confirmDismiss: (direction) => _handleSwipe(context, ref, direction),
      child: _MonitorCard(monitor: monitor, settings: settings),
    );
  }

  Future<bool> _handleSwipe(
    BuildContext context,
    WidgetRef ref,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.endToStart) {
      await context.push<void>('/monitor/${monitor.id}/edit');
      return false;
    }
    if (direction != DismissDirection.startToEnd) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, size: 34),
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
    if (confirmed != true || !context.mounted) return false;

    try {
      await ref.read(monitorControllerProvider.notifier).delete(monitor.id);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete monitor: $error')),
        );
      }
    }
    return false;
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.alignment,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: foregroundColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: foregroundColor, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.monitor, required this.settings});

  final MonitorEntry monitor;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = monitor.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final accent = monitorStatusColor(scheme, status);
    final highlighted =
        status != MonitorStatus.healthy && status != MonitorStatus.unknown;
    final surfaceColor = highlighted
        ? Color.lerp(scheme.surfaceContainerLowest, accent, .055)!
        : scheme.surfaceContainerLowest;
    final borderSide = highlighted
        ? BorderSide(color: accent.withValues(alpha: .38))
        : BorderSide.none;
    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: borderSide,
      ),
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
                  _SiteIdentity(monitor: monitor),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          monitor.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          monitor.port == 443
                              ? monitor.hostname
                              : '${monitor.hostname}:${monitor.port}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFamily: AkshiTheme.monoFontFamily,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.slashedZero(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: status),
                ],
              ),
              if (monitor.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 13),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: monitor.tags
                      .map((tag) => TagPill(tag: tag))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  ExpiryMetric(
                    label: 'Domain',
                    date: monitor.domainExpiresAt,
                    icon: Icons.public_rounded,
                  ),
                  if (monitor.profile.checksCertificate) ...<Widget>[
                    const SizedBox(width: 10),
                    ExpiryMetric(
                      label: 'Certificate',
                      date: monitor.certificateExpiresAt,
                      icon: Icons.verified_user_rounded,
                    ),
                  ] else if (monitor.profile.checksEmail) ...<Widget>[
                    const SizedBox(width: 10),
                    _EmailMetric(monitor: monitor),
                  ],
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: <Widget>[
                  Icon(LucideIcons.clock, size: 15, color: scheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    _freshness(monitor.lastCheckedAt),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Icon(
                    LucideIcons.chevron_right,
                    size: 16,
                    color: scheme.outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteIdentity extends StatelessWidget {
  const _SiteIdentity({required this.monitor});

  final MonitorEntry monitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fallbackColor = dark
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF59616B);
    Widget content;
    if (monitor.profile.checksEmail) {
      content = Icon(LucideIcons.mail, size: 23, color: fallbackColor);
    } else if (!monitor.profile.discoversSiteIcon) {
      content = Icon(LucideIcons.scan_search, size: 23, color: fallbackColor);
    } else if (monitor.siteIcon case final icon?) {
      content = icon.format.name == 'svg'
          ? SvgPicture.memory(
              icon.bytes,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
            )
          : Image.memory(
              icon.bytes,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            );
    } else {
      content = Icon(LucideIcons.globe_2, size: 23, color: fallbackColor);
    }
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? Colors.black : Colors.white,
        border: Border.all(
          color: dark ? const Color(0xFF656B73) : const Color(0xFFD6DAE0),
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: content,
    );
  }
}

class _EmailMetric extends StatelessWidget {
  const _EmailMetric({required this.monitor});

  final MonitorEntry monitor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final posture = monitor.emailPosture;
    final failed = monitor.emailActivity.failure != null;
    final attention = posture?.needsAttention ?? false;
    final color = failed
        ? scheme.error
        : attention
        ? scheme.tertiary
        : scheme.primary;
    final value = failed
        ? 'Unavailable'
        : posture == null
        ? 'Not checked'
        : attention
        ? 'Needs review'
        : 'Published';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            Icon(LucideIcons.mail_check, size: 19, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Email', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const AkshiMark(size: 88),
        const SizedBox(height: 24),
        Text(
          'Nothing to watch yet',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Add a domain and choose the checks that matter for it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

bool _hasOfflineFailure(MonitorEntry monitor) {
  final failures = <CheckFailure?>[
    monitor.domainActivity.failure,
    if (monitor.profile.checksCertificate) monitor.certificateActivity.failure,
    if (monitor.profile.checksEmail) monitor.emailActivity.failure,
  ];
  return failures.any(
    (failure) => failure?.kind == CheckFailureKind.offline,
  );
}

String _freshness(DateTime? date) {
  if (date == null) return 'Never checked';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'Checked just now';
  if (elapsed.inHours < 1) return 'Checked ${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return 'Checked ${elapsed.inHours}h ago';
  return 'Checked ${elapsed.inDays}d ago';
}
