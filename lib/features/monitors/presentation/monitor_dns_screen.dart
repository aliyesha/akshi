import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_refresh_banner.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class MonitorDnsScreen extends ConsumerStatefulWidget {
  const MonitorDnsScreen({required this.monitorId, super.key});

  final String monitorId;

  @override
  ConsumerState<MonitorDnsScreen> createState() => _MonitorDnsScreenState();
}

class _MonitorDnsScreenState extends ConsumerState<MonitorDnsScreen> {
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
    final snapshot = monitor.dnsSnapshot;
    final visible =
        snapshot?.queries
            .where(
              (query) =>
                  query.state != DnsQueryState.absent ||
                  query.hasCurrentFailure,
            )
            .toList(growable: false) ??
        const <DnsQueryResult>[];
    final absentCount =
        snapshot?.queries
            .where(
              (query) =>
                  query.state == DnsQueryState.absent &&
                  !query.hasCurrentFailure,
            )
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        title: const Text('DNS records'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Check now',
            onPressed: checking || refresh.isRunning
                ? null
                : () => _refresh(monitor),
            icon: checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: <Widget>[
          if (refresh.shouldShowStatus) ...<Widget>[
            const MonitorRefreshBanner(),
            const SizedBox(height: 14),
          ],
          if (checkProgress != null) ...<Widget>[
            Text(checkProgress.message),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: checkProgress.fraction),
            const SizedBox(height: 14),
          ],
          Text(monitor.hostname, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'A snapshot from this device’s system DNS resolver. Akshi asks for specific record types; it does not use an incomplete ANY response.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              snapshot.hasFailures
                  ? 'Latest attempt ${_formatDateTime(snapshot.checkedAt)} · saved results retained where lookups failed'
                  : 'Snapshot verified ${_formatDateTime(snapshot.checkedAt)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (snapshot == null)
            _EmptyDns(
              onCheck: checking || refresh.isRunning
                  ? null
                  : () => _refresh(monitor),
            )
          else if (visible.isEmpty)
            const _NoPublishedRecords()
          else
            for (final query in visible) ...<Widget>[
              _QueryCard(query: query),
              const SizedBox(height: 10),
            ],
          if (snapshot != null && absentCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '$absentCount requested record ${absentCount == 1 ? 'group is' : 'groups are'} '
              'not published. Missing types are normal and do not affect health.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
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
    try {
      await ref.read(monitorControllerProvider.notifier).check(monitor.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Check complete. Results updated.')),
        );
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.monitor_dns.check.failed',
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

class _QueryCard extends StatelessWidget {
  const _QueryCard({required this.query});

  final DnsQueryResult query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = query.hasCurrentFailure;
    final hasSavedResult = query.state != DnsQueryState.failed;
    final info = AkshiTheme.infoSurface(scheme);
    return MonitorSurface(
      color: failed ? info.background : scheme.surfaceContainerLowest,
      border: failed ? BorderSide(color: info.border) : null,
      child: failed && !hasSavedResult
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _DnsTypeIcon(type: query.type, failed: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _QueryTitle(query: query),
                        const SizedBox(height: 5),
                        Text(
                          query.error ?? 'This lookup could not be completed.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: info.foreground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : ExpansionTile(
              // Flutter's default expanded shape paints top and bottom borders.
              // Explicit empty shapes avoid the glow/stripe seen on some
              // mid-range Android renderers.
              shape: const Border(),
              collapsedShape: const Border(),
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
              initiallyExpanded: query.records.length <= 3,
              leading: _DnsTypeIcon(type: query.type),
              title: _QueryTitle(query: query),
              subtitle: Text(
                failed
                    ? query.state == DnsQueryState.absent
                          ? 'Saved as not published · latest lookup failed'
                          : '${query.records.length} saved ${query.records.length == 1 ? 'value' : 'values'} · latest lookup failed'
                    : '${query.records.length} ${query.records.length == 1 ? 'value' : 'values'}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: <Widget>[
                if (failed) ...<Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      query.error ??
                          'The latest lookup failed. Saved results are shown.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: info.foreground),
                    ),
                  ),
                  if (query.lastVerifiedAt != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Saved result verified ${_formatDateTime(query.lastVerifiedAt!)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
                for (var index = 0; index < query.records.length; index++)
                  _RecordRow(
                    record: query.records[index],
                    showDivider: index != query.records.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _QueryTitle extends StatelessWidget {
  const _QueryTitle({required this.query});

  final DnsQueryResult query;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(query.type.label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 2),
      Text(
        query.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFamily: AkshiTheme.monoFontFamily,
        ),
      ),
    ],
  );
}

class _DnsTypeIcon extends StatelessWidget {
  const _DnsTypeIcon({required this.type, this.failed = false});

  final DnsRecordType type;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = failed
        ? AkshiTheme.infoSurface(scheme).accent
        : scheme.primary;
    return MonitorIconBadge(
      icon: failed ? PhosphorIconsDuotone.cloudSlash : _dnsIcon(type),
      color: foreground,
    );
  }
}

IconData _dnsIcon(DnsRecordType type) => switch (type) {
  DnsRecordType.a ||
  DnsRecordType.aaaa => PhosphorIconsDuotone.globeHemisphereWest,
  DnsRecordType.mx => PhosphorIconsDuotone.envelopeSimpleOpen,
  DnsRecordType.txt => PhosphorIconsDuotone.listBullets,
  DnsRecordType.caa => PhosphorIconsDuotone.certificate,
  DnsRecordType.ns || DnsRecordType.cname => PhosphorIconsDuotone.network,
};

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.showDivider});

  final DnsRecord record;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    record.displayValue,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: AkshiTheme.monoFontFamily,
                      fontFeatures: const <FontFeature>[
                        FontFeature.slashedZero(),
                      ],
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'TTL ${_ttl(record.ttlSeconds)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy value',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: record.displayValue),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('DNS value copied')),
                  );
                }
              },
              icon: const PhosphorIcon(PhosphorIconsRegular.copy, size: 19),
            ),
          ],
        ),
      ),
      if (showDivider) const Divider(),
    ],
  );
}

class _EmptyDns extends StatelessWidget {
  const _EmptyDns({required this.onCheck});

  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: <Widget>[
        const PhosphorIcon(PhosphorIconsDuotone.network, size: 42),
        const SizedBox(height: 12),
        const Text('No DNS snapshot yet'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onCheck, child: const Text('Check now')),
      ],
    ),
  );
}

class _NoPublishedRecords extends StatelessWidget {
  const _NoPublishedRecords();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Text(
        'No requested DNS records were published. This is a valid snapshot.',
      ),
    ),
  );
}

Widget _backButton(BuildContext context) => IconButton(
  tooltip: 'Back to monitor',
  onPressed: () => context.canPop() ? context.pop() : context.go('/'),
  icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
);

String _ttl(int seconds) {
  if (seconds >= 86400 && seconds % 86400 == 0) {
    final days = seconds ~/ 86400;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  if (seconds >= 3600 && seconds % 3600 == 0) {
    final hours = seconds ~/ 3600;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  if (seconds >= 60 && seconds % 60 == 0) {
    final minutes = seconds ~/ 60;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
  return '$seconds seconds';
}

String _formatDateTime(DateTime value) => formatLocalDateTime(value);
