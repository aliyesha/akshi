import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MonitorEntry monitor({
    required String hostname,
    required DateTime now,
    required DateTime expiry,
    String? label,
  }) => MonitorEntry(
    id: hostname,
    hostname: hostname,
    tlsHostname: hostname,
    tlsPort: 443,
    checksCertificate: true,
    label: label,
    createdAt: now,
    updatedAt: now,
    certificateExpiresAt: expiry,
  );

  test('warning dates cross month boundaries by local calendar day', () {
    final now = DateTime(2026, 2, 1, 12);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          hostname: 'month.example',
          now: now,
          expiry: DateTime(2026, 3, 5, 18),
        ),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    expect(
      digests.map((digest) => digest.scheduledAt),
      contains(DateTime(2026, 2, 23, 9)),
    );
  });

  test('notification identity remains the unique hostname, not its label', () {
    final now = DateTime(2026, 2, 1, 12);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          hostname: 'shop-one.example',
          label: 'Production',
          now: now,
          expiry: DateTime(2026, 3, 5),
        ),
        monitor(
          hostname: 'shop-two.example',
          label: 'Production',
          now: now,
          expiry: DateTime(2026, 3, 5),
        ),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final firstDigest = digests.first;
    expect(firstDigest.assetCount, 2);
    expect(firstDigest.hostnames, <String>[
      'shop-one.example',
      'shop-two.example',
    ]);
  });
}
