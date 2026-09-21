import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 1, 12);

  MonitorEntry monitor(String hostname, DateTime expiry) => MonitorEntry(
    id: hostname,
    hostname: hostname,
    tlsHostname: hostname,
    tlsPort: 443,
    checksCertificate: true,
    createdAt: now,
    updatedAt: now,
    certificateExpiresAt: expiry,
  );

  test('combines different warning thresholds that land on the same day', () {
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor('ten-day.example', DateTime(2026, 8, 20)),
        monitor('five-day.example', DateTime(2026, 8, 15)),
        monitor('one-day.example', DateTime(2026, 8, 11)),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final augustTenth = digests.singleWhere(
      (digest) => digest.scheduledAt == DateTime(2026, 8, 10, 9),
    );
    expect(augustTenth.assetCount, 3);
    expect(augustTenth.hostnames, <String>[
      'five-day.example',
      'one-day.example',
      'ten-day.example',
    ]);
  });

  test('six assets produce three visible names and a remainder count', () {
    expect(
      compactMonitorNames(<String>[
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
