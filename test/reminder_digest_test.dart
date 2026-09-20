import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 1, 12);

  MonitorEntry monitor(
    String hostname, {
    String? label,
    DateTime? domainExpiry,
    DateTime? certificateExpiry,
    bool enabled = true,
  }) => MonitorEntry(
    id: hostname,
    hostname: hostname,
    port: 443,
    label: label,
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: certificateExpiry,
  );

  test('combines multiple websites into one digest for the same day', () {
    final expiry = DateTime(2026, 9, 20, 18);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor('alpha.example', domainExpiry: expiry),
        monitor('beta.example', certificateExpiry: expiry),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final tenDayDigest = digests.singleWhere(
      (digest) => digest.scheduledAt == DateTime(2026, 9, 10, 9),
    );
    expect(tenDayDigest.siteCount, 2);
    expect(tenDayDigest.siteNames, <String>['alpha.example', 'beta.example']);
  });

  test('lists a website once when both expiries share an alert day', () {
    final expiry = DateTime(2026, 9, 20, 18);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          'alpha.example',
          domainExpiry: expiry,
          certificateExpiry: expiry,
        ),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    expect(digests.every((digest) => digest.siteCount == 1), isTrue);
  });

  test('ignores disabled websites and reminder times already passed', () {
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          'disabled.example',
          domainExpiry: DateTime(2026, 9, 20),
          enabled: false,
        ),
        monitor('past.example', domainExpiry: DateTime(2026, 9, 2)),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    expect(digests, isEmpty);
  });

  test('builds a concise preview and reports remaining websites', () {
    expect(
      compactSiteNames(<String>['alpha.io', 'beta.io', 'gamma.io', 'delta.io']),
      'alpha.io, beta.io, gamma.io, and 1 more',
    );
  });

  test('preview removes duplicate names without changing order', () {
    expect(
      compactSiteNames(<String>['Alpha.io', 'beta.io', 'alpha.io']),
      'Alpha.io, beta.io',
    );
  });
}
