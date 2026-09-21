import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 1, 12);

  MonitorEntry monitor(
    String hostname, {
    String? label,
    bool checksCertificate = true,
    DateTime? domainExpiry,
    DateTime? certificateExpiry,
    bool enabled = true,
  }) => MonitorEntry(
    id: hostname,
    hostname: hostname,
    tlsHostname: hostname,
    tlsPort: 443,
    checksCertificate: checksCertificate,
    label: label,
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: certificateExpiry,
  );

  test('combines multiple assets into one digest for the same day', () {
    final expiry = DateTime(2026, 8, 20, 18);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor('alpha.example', domainExpiry: expiry),
        monitor('beta.example', certificateExpiry: expiry),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final tenDayDigest = digests.singleWhere(
      (digest) => digest.scheduledAt == DateTime(2026, 8, 10, 9),
    );
    expect(tenDayDigest.assetCount, 2);
    expect(tenDayDigest.hostnames, <String>['alpha.example', 'beta.example']);
  });

  test('digest names the exact expiring component for each domain', () {
    final expiry = DateTime(2026, 8, 20, 18);
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          'both.example',
          domainExpiry: expiry,
          certificateExpiry: expiry,
        ),
        monitor('certificate.example', certificateExpiry: expiry),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    final tenDayDigest = digests.singleWhere(
      (digest) => digest.scheduledAt == DateTime(2026, 8, 10, 9),
    );
    expect(
      tenDayDigest.preview(),
      'both.example · domain + TLS certificate; '
      'certificate.example · TLS certificate',
    );
  });

  test('lists an asset once when both expiries share an alert day', () {
    final expiry = DateTime(2026, 8, 20, 18);
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

    expect(digests.every((digest) => digest.assetCount == 1), isTrue);
  });

  test('ignores disabled assets and reminder times already passed', () {
    final digests = buildDailyReminderDigests(
      <MonitorEntry>[
        monitor(
          'disabled.example',
          domainExpiry: DateTime(2026, 8, 20),
          enabled: false,
        ),
        monitor('past.example', domainExpiry: DateTime(2026, 8, 2)),
      ],
      const AppSettings(notificationHour: 9),
      now: now,
    );

    expect(digests, isEmpty);
  });

  test(
    'certificate-disabled monitors never schedule certificate reminders',
    () {
      final digests = buildDailyReminderDigests(
        <MonitorEntry>[
          monitor(
            'mail.example',
            checksCertificate: false,
            certificateExpiry: DateTime(2026, 8, 20, 18),
          ),
        ],
        const AppSettings(notificationHour: 9),
        now: now,
      );

      expect(digests, isEmpty);
    },
  );

  test('builds a concise preview and reports remaining assets', () {
    expect(
      compactMonitorNames(<String>[
        'alpha.io',
        'beta.io',
        'gamma.io',
        'delta.io',
      ]),
      'alpha.io, beta.io, gamma.io, and 1 more',
    );
  });

  test('preview removes duplicate names without changing order', () {
    expect(
      compactMonitorNames(<String>['Alpha.io', 'beta.io', 'alpha.io']),
      'Alpha.io, beta.io',
    );
  });
}
