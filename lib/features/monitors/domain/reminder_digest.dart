import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';

class ReminderSite {
  const ReminderSite({required this.monitorId, required this.hostname});

  final String monitorId;
  final String hostname;
}

class DailyReminderDigest {
  const DailyReminderDigest({required this.scheduledAt, required this.sites});

  final DateTime scheduledAt;
  final List<ReminderSite> sites;

  int get siteCount => sites.length;
  List<String> get monitorIds =>
      sites.map((site) => site.monitorId).toList(growable: false);
  List<String> get siteNames =>
      sites.map((site) => site.hostname).toList(growable: false);

  String preview({int visibleNames = 3}) =>
      compactSiteNames(siteNames, visibleNames: visibleNames);
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
  final grouped = <DateTime, Map<String, ReminderSite>>{};

  for (final monitor in monitors.where((item) => item.enabled)) {
    final expiries = <DateTime?>[
      monitor.domainExpiresAt,
      monitor.certificateExpiresAt,
    ];
    for (final expiry in expiries.whereType<DateTime>()) {
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
        grouped
            .putIfAbsent(scheduledAt, () => <String, ReminderSite>{})
            .putIfAbsent(
              monitor.hostname,
              () => ReminderSite(
                monitorId: monitor.id,
                hostname: monitor.hostname,
              ),
            );
      }
    }
  }

  final dates = grouped.keys.toList()..sort();
  return dates
      .map((date) {
        final sites = grouped[date]!.values.toList()
          ..sort(
            (left, right) => left.hostname.toLowerCase().compareTo(
              right.hostname.toLowerCase(),
            ),
          );
        return DailyReminderDigest(scheduledAt: date, sites: sites);
      })
      .toList(growable: false);
}

String compactSiteNames(Iterable<String> names, {int visibleNames = 3}) {
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
