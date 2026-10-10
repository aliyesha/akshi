import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Disclosure of the destinations Akshi can contact.
///
/// This is intentionally derived from monitor definitions and observations.
/// It is not another settings surface and cannot silently diverge from what a
/// monitor is configured to check.
class NetworkDestinationsScreen extends ConsumerWidget {
  const NetworkDestinationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitors = ref.watch(monitorControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to settings',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
          icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
        ),
        title: const Text('Network destinations'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: <Widget>[
          const _DestinationCard(
            icon: PhosphorIconsDuotone.shieldCheck,
            title: 'Direct from this device',
            description:
                'Checks connect to the destinations shown below. Monitor data '
                'is not routed through an Akshi account, analytics service, '
                'or monitoring backend.',
            destinations: <_DestinationValue>[],
          ),
          const SizedBox(height: 28),
          const _SectionHeader(
            icon: PhosphorIconsDuotone.hardDrives,
            title: 'Services used for checks',
            description: 'Shared services used to discover registration data and resolve DNS.',
          ),
          const SizedBox(height: 12),
          const _DestinationCard(
            icon: PhosphorIconsDuotone.globeHemisphereWest,
            title: 'Domain registration discovery',
            description: 'Identifies the registration service responsible for each domain.',
            destinations: <_DestinationValue>[
              _DestinationValue(
                label: 'Address',
                value: 'https://data.iana.org/rdap/dns.json',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _DestinationCard(
            icon: PhosphorIconsDuotone.network,
            title: 'DNS resolver',
            description: 'Selected by Android, iOS, or the current network. Akshi does not use a DNS proxy.',
            destinations: <_DestinationValue>[
              _DestinationValue(
                label: 'Destination',
                value: 'Device or network DNS resolver',
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionHeader(
            icon: PhosphorIconsDuotone.globeHemisphereWest,
            title: 'Destinations from your monitors',
            description: 'Domain-specific destinations derived from monitors saved on this device.',
          ),
          const SizedBox(height: 12),
          monitors.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => const _DestinationCard(
              icon: PhosphorIconsDuotone.warningCircle,
              title: 'Monitor inventory unavailable',
              description:
                  'Return to this page after the local monitor list loads.',
              destinations: <_DestinationValue>[],
            ),
            data: (items) => items.isEmpty
                ? const _DestinationCard(
                    icon: PhosphorIconsDuotone.globeHemisphereWest,
                    title: 'No monitored domains yet',
                    description:
                        'Domain-specific registration, DNS, TLS, website, icon, '
                        'and email-policy destinations will appear here after '
                        'you add a monitor.',
                    destinations: <_DestinationValue>[],
                  )
                : Column(
                    children: <Widget>[
                      for (
                        var index = 0;
                        index < items.length;
                        index++
                      ) ...<Widget>[
                        _MonitorDestinations(monitor: items[index]),
                        if (index != items.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 28),
          const _SectionHeader(
            icon: PhosphorIconsRegular.globe,
            title: 'Links you open',
            description:
                'These addresses are contacted only after an explicit action.',
          ),
          const SizedBox(height: 12),
          const _DestinationCard(
            icon: PhosphorIconsRegular.globe,
            title: 'Project website',
            description:
                'Opened only when selected from the About Akshi screen.',
            destinations: <_DestinationValue>[
              _DestinationValue(
                label: 'Address',
                value: 'https://aliyesha.com',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonitorDestinations extends StatelessWidget {
  const _MonitorDestinations({required this.monitor});

  final MonitorEntry monitor;

  @override
  Widget build(BuildContext context) {
    final destinations = <_DestinationValue>[
      _DestinationValue(label: 'Domain registration', value: monitor.hostname),
      _DestinationValue(
        label: 'Registration service',
        value:
            monitor.domainSource ?? 'Determined during the first domain check',
      ),
      _DestinationValue(
        label: 'DNS lookups',
        value: _dnsRequests(monitor).join('\n'),
      ),
      if (monitor.checksCertificate)
        _DestinationValue(
          label: 'TLS endpoint',
          value: '${monitor.tlsHostname}:${monitor.tlsPort}',
        ),
      if (monitor.checksCertificate)
        _DestinationValue(label: 'Website', value: _websiteUri(monitor)),
      if (monitor.checksCertificate)
        const _DestinationValue(
          label: 'Website discovery',
          value:
              'HTTPS redirects and site-declared icon addresses, when present',
        ),
      if (monitor.siteIcon != null)
        _DestinationValue(
          label: 'Last icon source',
          value: monitor.siteIcon!.sourceUrl,
        ),
      if (monitor.checksEmail && monitor.mailReceives)
        _DestinationValue(
          label: 'MTA-STS policy',
          value: 'https://mta-sts.${monitor.hostname}/.well-known/mta-sts.txt',
        ),
    ];
    return _DestinationCard(
      icon: monitor.checksEmail
          ? PhosphorIconsDuotone.envelopeSimpleOpen
          : PhosphorIconsDuotone.globeHemisphereWest,
      title: monitor.displayName,
      description: monitor.enabled
          ? 'Saved monitor. Used during active checks.'
          : 'Saved monitor. Network checks are currently disabled.',
      destinations: destinations,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: PhosphorIcon(icon, size: 21, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.destinations,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<_DestinationValue> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: PhosphorIcon(
                    icon,
                    size: 22,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (destinations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 4),
              for (
                var index = 0;
                index < destinations.length;
                index++
              ) ...<Widget>[
                _DestinationRow(destination: destinations[index]),
                if (index != destinations.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.destination});

  final _DestinationValue destination;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          destination.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          destination.value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: AkshiTheme.monoFontFamily,
            color: scheme.onSurface,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _DestinationValue {
  const _DestinationValue({required this.label, required this.value});

  final String label;
  final String value;
}

List<String> _dnsRequests(MonitorEntry monitor) {
  final requests = <String>[
    '${monitor.hostname} (${DnsRecordType.values.map((type) => type.label).join(', ')})',
    if (monitor.checksEmail && monitor.mailSends)
      '_dmarc.${monitor.hostname} (TXT)',
    if (monitor.checksEmail && monitor.mailSends)
      for (final selector in monitor.dkimSelectors)
        '$selector._domainkey.${monitor.hostname} (TXT)',
    if (monitor.checksEmail && monitor.mailReceives)
      '_mta-sts.${monitor.hostname} (TXT)',
    if (monitor.checksEmail && monitor.mailReceives)
      '_smtp._tls.${monitor.hostname} (TXT)',
  ];
  return requests;
}

String _websiteUri(MonitorEntry monitor) => Uri(
  scheme: 'https',
  host: monitor.tlsHostname,
  port: monitor.tlsPort == 443 ? null : monitor.tlsPort,
  path: '/',
).toString();
