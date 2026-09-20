import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 1, 12);

  MonitorEntry monitor(String hostname, DateTime expiry) => MonitorEntry(
    id: hostname,
    hostname: hostname,
    port: 443,
    createdAt: now,
    updatedAt: now,
    certificateExpiresAt: expiry,
  );

  test('combines different warning thresholds that land on the same day', () {
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor('ten-day.example', DateTime(2026, 9, 20)),
        monitor('five-day.example', DateTime(2026, 9, 15)),
        monitor('one-day.example', DateTime(2026, 9, 11)),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final septemberTenth = digests.singleWhere(
      (digest) => digest.scheduledAt == DateTime(2026, 9, 10, 9),
    );
    expect(septemberTenth.siteCount, 3);
    expect(septemberTenth.siteNames, <String>[
      'five-day.example',
      'one-day.example',
      'ten-day.example',
    ]);
  });

  test('six websites produce three visible names and a remainder count', () {
    expect(
      compactSiteNames(<String>[
        'alpha.io',
        'beta.io',
        'gamma.io',
        'delta.io',
        'epsilon.io',
        'zeta.io',
      ]),
      'alpha.io, beta.io, gamma.io, and 3 more',
    );
  });
}
