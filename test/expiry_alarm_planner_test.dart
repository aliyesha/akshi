import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location utc;

  setUpAll(() {
    tz_data.initializeTimeZones();
    utc = tz.UTC;
  });

  DomainEntry domain({
    required String id,
    required String hostname,
    DateTime? domainExpiry,
    DateTime? tlsExpiry,
    bool checksCertificate = true,
    bool remindersEnabled = true,
  }) => DomainEntry(
    id: id,
    hostname: hostname,
    tlsHostname: hostname,
    tlsPort: 443,
    checksCertificate: checksCertificate,
    remindersEnabled: remindersEnabled,
    createdAt: DateTime.utc(2026, 2, 1),
    updatedAt: DateTime.utc(2026, 2, 1),
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: tlsExpiry,
  );

  final enabledSettings = AppSettings(remindersEnabled: true);

  test(
    'one domain and TLS expiry creates one alarm per date, not per reason',
    () {
      final plan = const ExpiryAlarmPlanner().build(
        domains: <DomainEntry>[
          domain(
            id: 'one',
            hostname: 'one.example',
            domainExpiry: DateTime.utc(2026, 5, 24, 18),
            tlsExpiry: DateTime.utc(2026, 5, 24, 18),
          ),
        ],
        settings: enabledSettings,
        now: DateTime.utc(2026, 5, 10),
        location: utc,
      );

      expect(plan.keys, <AlarmDate>[
        const AlarmDate(2026, 5, 14),
        const AlarmDate(2026, 5, 19),
        const AlarmDate(2026, 5, 23),
      ]);
      for (final alarm in plan.values) {
        expect(alarm.items, hasLength(1));
        expect(alarm.items.single.reasons, hasLength(2));
        expect(
          alarm.items.single.reasons.map((reason) => reason.kind),
          <ExpiryAlarmKind>[
            ExpiryAlarmKind.domainRegistration,
            ExpiryAlarmKind.tlsCertificate,
          ],
        );
      }
    },
  );

  test('multiple domains and offsets colliding on one day make one alarm', () {
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(
          id: 'alpha',
          hostname: 'alpha.example',
          tlsExpiry: DateTime.utc(2026, 5, 24),
        ),
        domain(
          id: 'beta',
          hostname: 'beta.example',
          domainExpiry: DateTime.utc(2026, 5, 19),
        ),
        domain(
          id: 'gamma',
          hostname: 'gamma.example',
          tlsExpiry: DateTime.utc(2026, 5, 15),
        ),
      ],
      settings: enabledSettings,
      now: DateTime.utc(2026, 5, 10),
      location: utc,
    );

    final alarm = plan[const AlarmDate(2026, 5, 14)]!;
    expect(alarm.items.map((item) => item.domainId), <String>[
      'alpha',
      'beta',
      'gamma',
    ]);
    expect(alarm.notificationId, ExpiryAlarmSpec.notificationIdFor(alarm.date));
  });

  test('disabled reminders produce an empty authoritative plan', () {
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(
          id: 'one',
          hostname: 'one.example',
          domainExpiry: DateTime.utc(2026, 5, 24),
        ),
      ],
      settings: AppSettings(remindersEnabled: false),
      now: DateTime.utc(2026, 5, 10),
      location: utc,
    );

    expect(plan, isEmpty);
  });

  test(
    'disabled domains, disabled TLS, null and past expiries are excluded',
    () {
      final plan = const ExpiryAlarmPlanner().build(
        domains: <DomainEntry>[
          domain(
            id: 'disabled',
            hostname: 'disabled.example',
            domainExpiry: DateTime.utc(2026, 5, 24),
            remindersEnabled: false,
          ),
          domain(
            id: 'tls-off',
            hostname: 'tls-off.example',
            tlsExpiry: DateTime.utc(2026, 5, 24),
            checksCertificate: false,
          ),
          domain(
            id: 'past',
            hostname: 'past.example',
            domainExpiry: DateTime.utc(2026, 5, 11),
          ),
          domain(id: 'null', hostname: 'null.example'),
        ],
        settings: enabledSettings,
        now: DateTime.utc(2026, 5, 10, 12),
        location: utc,
      );

      expect(plan, isEmpty);
    },
  );

  test('alarm at exactly now is excluded while later alarm dates remain', () {
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(
          id: 'boundary',
          hostname: 'boundary.example',
          domainExpiry: DateTime.utc(2026, 5, 24),
        ),
      ],
      settings: enabledSettings,
      now: DateTime.utc(2026, 5, 14, 9),
      location: utc,
    );

    expect(plan, isNot(contains(const AlarmDate(2026, 5, 14))));
    expect(plan, contains(const AlarmDate(2026, 5, 19)));
    expect(plan, contains(const AlarmDate(2026, 5, 23)));
  });

  test('calendar subtraction crosses February and March correctly', () {
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(
          id: 'month',
          hostname: 'month.example',
          domainExpiry: DateTime.utc(2026, 3, 5, 18),
        ),
      ],
      settings: enabledSettings,
      now: DateTime.utc(2026, 2, 1),
      location: utc,
    );

    expect(plan, contains(const AlarmDate(2026, 2, 23)));
  });

  test('expiry is converted to the explicit local calendar date', () {
    final losAngeles = tz.getLocation('America/Los_Angeles');
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(
          id: 'zone',
          hostname: 'zone.example',
          domainExpiry: DateTime.utc(2026, 3, 1, 1),
        ),
      ],
      settings: enabledSettings,
      now: DateTime.utc(2026, 2, 1),
      location: losAngeles,
    );

    // 2026-03-01 01:00Z is 2026-02-28 in Los Angeles.
    expect(plan, contains(const AlarmDate(2026, 2, 18)));
    expect(plan, contains(const AlarmDate(2026, 2, 23)));
    expect(plan, contains(const AlarmDate(2026, 2, 27)));
  });

  test('warning time follows the named zone across both DST transitions', () {
    final newYork = tz.getLocation('America/New_York');

    ExpiryAlarmSpec tenDayWarningFor(tz.TZDateTime localExpiry) {
      final plan = const ExpiryAlarmPlanner().build(
        domains: <DomainEntry>[
          domain(
            id: 'dst',
            hostname: 'dst.example',
            domainExpiry: localExpiry.toUtc(),
          ),
        ],
        settings: AppSettings(remindersEnabled: true, notificationHour: 9),
        now: DateTime.utc(2026, 1, 1),
        location: newYork,
      );
      final warningDate = AlarmDate.fromDateTime(
        localExpiry.subtract(const Duration(days: 10)),
      );
      return plan[warningDate]!;
    }

    final spring = tenDayWarningFor(tz.TZDateTime(newYork, 2026, 3, 18, 12));
    expect(spring.date, const AlarmDate(2026, 3, 8));
    expect(spring.scheduledAt.hour, 9);
    expect(spring.scheduledAt.minute, 0);
    expect(spring.scheduledAt.timeZoneOffset, const Duration(hours: -4));

    final autumn = tenDayWarningFor(tz.TZDateTime(newYork, 2026, 11, 11, 12));
    expect(autumn.date, const AlarmDate(2026, 11, 1));
    expect(autumn.scheduledAt.hour, 9);
    expect(autumn.scheduledAt.minute, 0);
    expect(autumn.scheduledAt.timeZoneOffset, const Duration(hours: -5));
  });

  test('same hostname remains two items because domain ID is identity', () {
    final expiry = DateTime.utc(2026, 6, 20);
    final plan = const ExpiryAlarmPlanner().build(
      domains: <DomainEntry>[
        domain(id: 'first', hostname: 'same.example', domainExpiry: expiry),
        domain(id: 'second', hostname: 'same.example', domainExpiry: expiry),
      ],
      settings: enabledSettings,
      now: DateTime.utc(2026, 6, 1),
      location: utc,
    );

    expect(plan.values.first.items.map((item) => item.domainId), <String>[
      'first',
      'second',
    ]);
  });

  test('input order does not change canonical payload or body', () {
    final first = domain(
      id: 'a',
      hostname: 'alpha.example',
      domainExpiry: DateTime.utc(2026, 7, 20),
    );
    final second = domain(
      id: 'b',
      hostname: 'beta.example',
      tlsExpiry: DateTime.utc(2026, 7, 20),
    );
    Map<AlarmDate, ExpiryAlarmSpec> build(List<DomainEntry> domains) =>
        const ExpiryAlarmPlanner().build(
          domains: domains,
          settings: enabledSettings,
          now: DateTime.utc(2026, 7, 1),
          location: utc,
        );

    final normal = build(<DomainEntry>[first, second]);
    final reversed = build(<DomainEntry>[second, first]);
    expect(normal.keys, reversed.keys);
    for (final date in normal.keys) {
      expect(normal[date]!.payload, reversed[date]!.payload);
      expect(normal[date]!.body, reversed[date]!.body);
    }
  });

  test('time changes replace content but retain stable date ID', () {
    final item = domain(
      id: 'one',
      hostname: 'one.example',
      domainExpiry: DateTime.utc(2026, 8, 20),
    );
    ExpiryAlarmSpec alarmAt(int hour) => const ExpiryAlarmPlanner()
        .build(
          domains: <DomainEntry>[item],
          settings: AppSettings(remindersEnabled: true, notificationHour: hour),
          now: DateTime.utc(2026, 8, 1),
          location: utc,
        )
        .values
        .first;

    final nine = alarmAt(9);
    final eighteen = alarmAt(18);
    expect(nine.date, eighteen.date);
    expect(nine.notificationId, eighteen.notificationId);
    expect(nine.payload, isNot(eighteen.payload));
  });

  test('only the earliest sixty dates are retained', () {
    final domains = List<DomainEntry>.generate(
      80,
      (index) => domain(
        id: 'm$index',
        hostname: 'm$index.example',
        domainExpiry: DateTime.utc(2026, 3, 1).add(Duration(days: index)),
      ),
    );
    final plan = const ExpiryAlarmPlanner().build(
      domains: domains,
      settings: enabledSettings,
      now: DateTime.utc(2026, 2, 1),
      location: utc,
    );

    expect(plan, hasLength(ExpiryAlarmSpec.maximumPendingAlarms));
    expect(plan.keys.toList(), orderedEquals(plan.keys.toList()..sort()));
  });
}
