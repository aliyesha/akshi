import 'package:akshi/app/providers.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/domain/dns_snapshot.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_identity_header.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class DomainDnsScreen extends ConsumerStatefulWidget {
  const DomainDnsScreen({required this.domainId, super.key});

  final String domainId;

  @override
  ConsumerState<DomainDnsScreen> createState() => _DomainDnsScreenState();
}

class _DomainDnsScreenState extends ConsumerState<DomainDnsScreen> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(domainControllerProvider);
    final refresh = ref.watch(domainRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
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
    final snapshot = domain.dnsSnapshot;
    final visible =
        snapshot?.queries
            .where(
              (query) =>
                  query.state != DnsQueryState.absent ||
                  query.hasCurrentFailure,
            )
            .toList(growable: false) ??
        const <DnsQueryResult>[];
    final absent =
        snapshot?.queries
            .where(
              (query) =>
                  query.state == DnsQueryState.absent &&
                  !query.hasCurrentFailure,
            )
            .toList(growable: false) ??
        const <DnsQueryResult>[];

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        title: const Text('DNS records'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Check domain',
            onPressed: checking || refresh.isRunning || offline
                ? null
                : () => _refresh(domain),
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
      body: RefreshIndicator(
        onRefresh: refresh.isRunning
            ? () async {
                await ref.read(domainControllerProvider.notifier).refreshAll();
              }
            : () => _refresh(domain),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          children: <Widget>[
            if (refresh.shouldShowStatus) ...<Widget>[
              const DomainRefreshBanner(),
              const SizedBox(height: 14),
            ],
            if (offline) ...<Widget>[
              const OfflineNotice(),
              const SizedBox(height: 14),
            ],
            if (checkProgress != null) ...<Widget>[
              Text(checkProgress.message),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: checkProgress.fraction),
              const SizedBox(height: 14),
            ],
            DomainIdentityHeader(domain: domain),
            const SizedBox(height: 12),
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
                onCheck: checking || refresh.isRunning || offline
                    ? null
                    : () => _refresh(domain),
              )
            else if (visible.isEmpty)
              const _NoPublishedRecords()
            else
              for (final query in visible) ...<Widget>[
                _QueryCard(query: query),
                const SizedBox(height: 10),
              ],
            if (absent.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _AbsentDnsSummary(queries: absent, hostname: domain.hostname),
            ],
          ],
        ),
      ),
    );
  }

  DomainEntry? _find(List<DomainEntry> items) {
    for (final item in items) {
      if (item.id == widget.domainId) return item;
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
        'ui.domain_dns.check.failed',
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
}

class _QueryCard extends StatelessWidget {
  const _QueryCard({required this.query});

  final DnsQueryResult query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = query.hasCurrentFailure;
    final hasSavedResult = query.state != DnsQueryState.failed;
    return DomainSurface(
      child: failed && !hasSavedResult
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _DnsTypeIcon(type: query.type),
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
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        _DnsVerificationStatus(query: query),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: <Widget>[
                ExpansionTile(
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
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  children: <Widget>[
                    if (failed) ...<Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          query.error ?? 'The latest lookup failed. Saved results are shown.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _DnsVerificationStatus(query: query),
                  ),
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
  const _DnsTypeIcon({required this.type});

  final DnsRecordType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DomainIconBadge(icon: _dnsIcon(type), color: scheme.primary);
  }
}

class _DnsVerificationStatus extends StatelessWidget {
  const _DnsVerificationStatus({required this.query});

  final DnsQueryResult query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, message) = query.hasCurrentFailure
        ? (
            PhosphorIconsDuotone.cloudSlash,
            scheme.tertiary,
            query.state == DnsQueryState.failed
                ? 'Not available'
                : 'Latest lookup unavailable · saved result shown',
          )
        : query.state == DnsQueryState.absent
        ? (
            PhosphorIconsDuotone.minusCircle,
            scheme.onSurfaceVariant,
            'Verified · not published',
          )
        : (
            PhosphorIconsDuotone.checkCircle,
            scheme.brightness == Brightness.dark
                ? const Color(0xFF7ED39B)
                : const Color(0xFF227A45),
            'Verified',
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PhosphorIcon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            message,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
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

class _AbsentDnsSummary extends StatelessWidget {
  const _AbsentDnsSummary({required this.queries, required this.hostname});

  final List<DnsQueryResult> queries;
  final String hostname;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = queries.map(
      (query) => query.name == hostname
          ? query.type.label
          : '${query.type.label} ${query.name}',
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PhosphorIcon(
          PhosphorIconsDuotone.minusCircle,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Not published: ${labels.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

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
                  showAkshiNotice(
                    context,
                    title: 'DNS value copied',
                    message: 'The record value is on your clipboard.',
                    tone: AkshiNoticeTone.success,
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
        FilledButton(onPressed: onCheck, child: const Text('Check domain')),
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
  tooltip: 'Back to domain',
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
