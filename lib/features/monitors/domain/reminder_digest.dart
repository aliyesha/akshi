import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';

enum ExpiryReminderKind {
  domainRegistration('domain'),
  tlsCertificate('TLS certificate');

  const ExpiryReminderKind(this.label);

  final String label;
}

class ReminderAsset {
  const ReminderAsset({
    required this.monitorId,
    required this.hostname,
    required this.kinds,
  });

  final String monitorId;
  final String hostname;
  final Set<ExpiryReminderKind> kinds;
}

class DailyReminderDigest {
  const DailyReminderDigest({required this.scheduledAt, required this.assets});

  final DateTime scheduledAt;
  final List<ReminderAsset> assets;

  int get assetCount => assets.length;
  List<String> get monitorIds =>
      assets.map((asset) => asset.monitorId).toList(growable: false);
  List<String> get hostnames =>
      assets.map((asset) => asset.hostname).toList(growable: false);

  String preview({int visibleNames = 3}) {
    final shown = assets
        .take(visibleNames)
        .map(_formatReminderAsset)
        .join('; ');
    final remaining = assets.length - visibleNames;
    return remaining > 0 ? '$shown; and $remaining more' : shown;
  }
}

List<DailyReminderDigest> buildDailyReminderDigests(
  Iterable<MonitorEntry> monitors,
  AppSettings settings, {
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final warningDays = <int>{
    settings.firstWarningDays,
    settings.secondWarningDays,
    1,
  };
  final grouped = <DateTime, Map<String, ReminderAsset>>{};

  for (final monitor in monitors.where((item) => item.enabled)) {
    final expiries = <(DateTime?, ExpiryReminderKind)>[
      (monitor.domainExpiresAt, ExpiryReminderKind.domainRegistration),
      if (monitor.checksCertificate)
        (monitor.certificateExpiresAt, ExpiryReminderKind.tlsCertificate),
    ];
    for (final (expiry, kind) in expiries) {
      if (expiry == null) continue;
      final localExpiry = expiry.toLocal();
      for (final days in warningDays) {
        final scheduledAt = DateTime(
          localExpiry.year,
          localExpiry.month,
          localExpiry.day - days,
          settings.notificationHour,
          settings.notificationMinute,
        );
        if (!scheduledAt.isAfter(referenceTime)) continue;
        final dailyAssets = grouped.putIfAbsent(
          scheduledAt,
          () => <String, ReminderAsset>{},
        );
        final existing = dailyAssets[monitor.hostname];
        dailyAssets[monitor.hostname] = ReminderAsset(
          monitorId: monitor.id,
          hostname: monitor.hostname,
          kinds: <ExpiryReminderKind>{...?existing?.kinds, kind},
        );
      }
    }
  }

  final dates = grouped.keys.toList()..sort();
  return dates
      .map((date) {
        final assets = grouped[date]!.values.toList()
          ..sort(
            (left, right) => left.hostname.toLowerCase().compareTo(
              right.hostname.toLowerCase(),
            ),
          );
        return DailyReminderDigest(scheduledAt: date, assets: assets);
      })
      .toList(growable: false);
}

String _formatReminderAsset(ReminderAsset asset) {
  final labels = ExpiryReminderKind.values
      .where(asset.kinds.contains)
      .map((kind) => kind.label)
      .join(' + ');
  return labels.isEmpty ? asset.hostname : '${asset.hostname} · $labels';
}

String compactMonitorNames(Iterable<String> names, {int visibleNames = 3}) {
  final uniqueNames = <String>[];
  final seen = <String>{};
  for (final name in names) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    uniqueNames.add(name.trim());
  }
  if (uniqueNames.isEmpty) return '';
  final shown = uniqueNames.take(visibleNames).join(', ');
  final remaining = uniqueNames.length - visibleNames;
  return remaining > 0 ? '$shown, and $remaining more' : shown;
}
