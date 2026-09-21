import 'package:akshi/core/formatters/certificate_algorithm_formatter.dart';
import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class MonitorDetailScreen extends ConsumerStatefulWidget {
  const MonitorDetailScreen({required this.monitorId, super.key});
  final String monitorId;

  @override
  ConsumerState<MonitorDetailScreen> createState() =>
      _MonitorDetailScreenState();
}

class _MonitorDetailScreenState extends ConsumerState<MonitorDetailScreen> {
  var _checking = false;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(monitorControllerProvider);
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
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
    final status = monitor.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            Text(
              monitor.displayName,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 6),
            Text(
              monitor.hostname,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: AkshiTheme.monoFontFamily,
                fontFeatures: const <FontFeature>[FontFeature.slashedZero()],
              ),
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
                StatusPill(status: status),
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
            if (monitor.certificateChanged) ...<Widget>[
              const SizedBox(height: 18),
              _Notice(
                icon: PhosphorIconsDuotone.sparkle,
                title: 'Renewal detected',
                message: 'The live certificate fingerprint changed on the latest check.',
              ),
            ],
            if (monitor.domainError != null ||
                (monitor.checksCertificate &&
                    monitor.certificateError != null) ||
                (monitor.checksEmail &&
                    monitor.emailActivity.failure != null)) ...<Widget>[
              const SizedBox(height: 18),
              _Notice(
                icon: PhosphorIconsDuotone.warningCircle,
                title: 'Some data could not be verified',
                message: [
                  if (monitor.domainError != null)
                    'Domain: ${monitor.domainError}',
                  if (monitor.checksCertificate &&
                      monitor.certificateError != null)
                    'Certificate: ${monitor.certificateError}',
                  if (monitor.checksEmail &&
                      monitor.emailActivity.failure != null)
                    'Email: ${monitor.emailActivity.failure!.message}',
                ].join(String.fromCharCode(10)),
                error: true,
              ),
            ],
            const SizedBox(height: 26),
            _ExpiryPanel(
              icon: PhosphorIconsDuotone.globeHemisphereWest,
              title: 'Domain registration',
              date: monitor.domainExpiresAt,
              source: monitor.domainSource == null
                  ? 'No registry date available'
                  : 'Verified through ${monitor.domainSource}',
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
                  value: _domainDate(
                    context,
                    monitor,
                    monitor.domainRegisteredAt,
                  ),
                ),
                _InfoRow(
                  icon: PhosphorIconsRegular.clock,
                  label: 'Last changed',
                  value: _domainDate(context, monitor, monitor.domainUpdatedAt),
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
            if (monitor.checksCertificate) ...<Widget>[
              const SizedBox(height: 12),
              _ExpiryPanel(
                icon: PhosphorIconsDuotone.certificate,
                title: 'TLS certificate',
                date: monitor.certificateExpiresAt,
                source: monitor.certificateIssuer == null
                    ? 'No certificate data available'
                    : 'Issued by ${formatCertificateIssuer(monitor.certificateIssuer!)}',
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
                        : monitor.certificateSubjectAlternativeNames.join('\n'),
                    monospace: true,
                  ),
                  _InfoRow(
                    icon: PhosphorIconsDuotone.calendarCheck,
                    label: 'Valid from',
                    value: _formatDate(context, monitor.certificateValidFrom),
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
            if (monitor.checksEmail) ...<Widget>[
              const SizedBox(height: 26),
              Text(
                'Email posture',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Published configuration, not a delivery or reputation score.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (monitor.emailPosture != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'DNS data checked ${_formatDateTime(context, monitor.emailPosture!.checkedAt)}',
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
                      ? 'Email not checked yet'
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
                  label: 'Last checked',
                  value: monitor.lastCheckedAt == null
                      ? 'Never'
                      : _formatDateTime(context, monitor.lastCheckedAt!),
                  last: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    if (_checking) {
      return;
    }
    setState(() => _checking = true);
    try {
      await ref.read(monitorControllerProvider.notifier).check(monitor.id);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
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
    await ref.read(monitorControllerProvider.notifier).delete(monitor.id);
    if (mounted) {
      context.go('/');
    }
  }
}

class _ExpiryPanel extends StatelessWidget {
  const _ExpiryPanel({
    required this.icon,
    required this.title,
    required this.date,
    required this.source,
  });

  final IconData icon;
  final String title;
  final DateTime? date;
  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = date?.difference(DateTime.now()).inDays;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
            date == null ? source : '${_formatDate(context, date)} · $source',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(22),
    ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: color.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PhosphorIcon(icon, size: 19, color: color),
              ),
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
    final color = error ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: (22) / 255),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
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

String _formatDate(BuildContext context, DateTime? value) => value == null
    ? '—'
    : MaterialLocalizations.of(context).formatFullDate(value.toLocal());

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

String _domainDate(
  BuildContext context,
  MonitorEntry monitor,
  DateTime? value,
) {
  if (monitor.domainSource == null) {
    return 'Not available';
  }
  return value == null ? 'Not published' : _formatDate(context, value);
}

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${_formatDate(context, local)} at ${TimeOfDay.fromDateTime(local).format(context)}';
}

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
