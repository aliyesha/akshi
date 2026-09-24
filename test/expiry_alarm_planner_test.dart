import 'package:akshi/features/monitors/domain/monitor_entry.dart';
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

  MonitorEntry monitor({
    required String id,
    required String hostname,
    DateTime? domainExpiry,
    DateTime? tlsExpiry,
    bool checksCertificate = true,
    bool enabled = true,
  }) => MonitorEntry(
    id: id,
    hostname: hostname,
    tlsHostname: hostname,
    tlsPort: 443,
    checksCertificate: checksCertificate,
    enabled: enabled,
    createdAt: DateTime.utc(2026, 2, 1),
    updatedAt: DateTime.utc(2026, 2, 1),
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: tlsExpiry,
  );

  const enabled = AppSettings(remindersEnabled: true);

  test('one domain and TLS expiry creates one alarm per date, not per reason', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'one',
          hostname: 'one.example',
          domainExpiry: DateTime.utc(2026, 5, 24, 18),
          tlsExpiry: DateTime.utc(2026, 5, 24, 18),
        ),
      ],
      settings: enabled,
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
  });

  test('multiple domains and offsets colliding on one day make one alarm', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'alpha',
          hostname: 'alpha.example',
          tlsExpiry: DateTime.utc(2026, 5, 24),
        ),
        monitor(
          id: 'beta',
          hostname: 'beta.example',
          domainExpiry: DateTime.utc(2026, 5, 19),
        ),
        monitor(
          id: 'gamma',
          hostname: 'gamma.example',
          tlsExpiry: DateTime.utc(2026, 5, 15),
        ),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 5, 10),
      location: utc,
    );

    final alarm = plan[const AlarmDate(2026, 5, 14)]!;
    expect(alarm.items.map((item) => item.monitorId), <String>[
      'alpha',
      'beta',
      'gamma',
    ]);
    expect(alarm.notificationId, ExpiryAlarmSpec.notificationIdFor(alarm.date));
  });

  test('disabled reminders produce an empty authoritative plan', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'one',
          hostname: 'one.example',
          domainExpiry: DateTime.utc(2026, 5, 24),
        ),
      ],
      settings: const AppSettings(remindersEnabled: false),
      now: DateTime.utc(2026, 5, 10),
      location: utc,
    );

    expect(plan, isEmpty);
  });

  test('disabled monitors, disabled TLS, null and past expiries are excluded', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'disabled',
          hostname: 'disabled.example',
          domainExpiry: DateTime.utc(2026, 5, 24),
          enabled: false,
        ),
        monitor(
          id: 'tls-off',
          hostname: 'tls-off.example',
          tlsExpiry: DateTime.utc(2026, 5, 24),
          checksCertificate: false,
        ),
        monitor(
          id: 'past',
          hostname: 'past.example',
          domainExpiry: DateTime.utc(2026, 5, 11),
        ),
        monitor(id: 'null', hostname: 'null.example'),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 5, 10, 12),
      location: utc,
    );

    expect(plan, isEmpty);
  });

  test('alarm at exactly now is excluded while later alarm dates remain', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'boundary',
          hostname: 'boundary.example',
          domainExpiry: DateTime.utc(2026, 5, 24),
        ),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 5, 14, 9),
      location: utc,
    );

    expect(plan, isNot(contains(const AlarmDate(2026, 5, 14))));
    expect(plan, contains(const AlarmDate(2026, 5, 19)));
    expect(plan, contains(const AlarmDate(2026, 5, 23)));
  });

  test('calendar subtraction crosses February and March correctly', () {
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'month',
          hostname: 'month.example',
          domainExpiry: DateTime.utc(2026, 3, 5, 18),
        ),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 2, 1),
      location: utc,
    );

    expect(plan, contains(const AlarmDate(2026, 2, 23)));
  });

  test('expiry is converted to the explicit local calendar date', () {
    final losAngeles = tz.getLocation('America/Los_Angeles');
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(
          id: 'zone',
          hostname: 'zone.example',
          domainExpiry: DateTime.utc(2026, 3, 1, 1),
        ),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 2, 1),
      location: losAngeles,
    );

    // 2026-03-01 01:00Z is 2026-02-28 in Los Angeles.
    expect(plan, contains(const AlarmDate(2026, 2, 18)));
    expect(plan, contains(const AlarmDate(2026, 2, 23)));
    expect(plan, contains(const AlarmDate(2026, 2, 27)));
  });

  test('same hostname remains two items because monitor ID is identity', () {
    final expiry = DateTime.utc(2026, 6, 20);
    final plan = const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[
        monitor(id: 'first', hostname: 'same.example', domainExpiry: expiry),
        monitor(id: 'second', hostname: 'same.example', domainExpiry: expiry),
      ],
      settings: enabled,
      now: DateTime.utc(2026, 6, 1),
      location: utc,
    );

    expect(plan.values.first.items.map((item) => item.monitorId), <String>[
      'first',
      'second',
    ]);
  });

  test('input order does not change canonical payload or body', () {
    final first = monitor(
      id: 'a',
      hostname: 'alpha.example',
      domainExpiry: DateTime.utc(2026, 7, 20),
    );
    final second = monitor(
      id: 'b',
      hostname: 'beta.example',
      tlsExpiry: DateTime.utc(2026, 7, 20),
    );
    Map<AlarmDate, ExpiryAlarmSpec> build(List<MonitorEntry> monitors) =>
        const ExpiryAlarmPlanner().build(
          monitors: monitors,
          settings: enabled,
          now: DateTime.utc(2026, 7, 1),
          location: utc,
        );

    final normal = build(<MonitorEntry>[first, second]);
    final reversed = build(<MonitorEntry>[second, first]);
    expect(normal.keys, reversed.keys);
    for (final date in normal.keys) {
      expect(normal[date]!.payload, reversed[date]!.payload);
      expect(normal[date]!.body, reversed[date]!.body);
    }
  });

  test('time changes replace content but retain stable date ID', () {
    final item = monitor(
      id: 'one',
      hostname: 'one.example',
      domainExpiry: DateTime.utc(2026, 8, 20),
    );
    ExpiryAlarmSpec alarmAt(int hour) => const ExpiryAlarmPlanner().build(
      monitors: <MonitorEntry>[item],
      settings: AppSettings(remindersEnabled: true, notificationHour: hour),
      now: DateTime.utc(2026, 8, 1),
      location: utc,
    ).values.first;

    final nine = alarmAt(9);
    final eighteen = alarmAt(18);
    expect(nine.date, eighteen.date);
    expect(nine.notificationId, eighteen.notificationId);
    expect(nine.payload, isNot(eighteen.payload));
  });

  test('only the earliest sixty dates are retained', () {
    final monitors = List<MonitorEntry>.generate(
      80,
      (index) => monitor(
        id: 'm$index',
        hostname: 'm$index.example',
        domainExpiry: DateTime.utc(2026, 3, 1).add(Duration(days: index)),
      ),
    );
    final plan = const ExpiryAlarmPlanner().build(
      monitors: monitors,
      settings: enabled,
      now: DateTime.utc(2026, 2, 1),
      location: utc,
    );

    expect(plan, hasLength(ExpiryAlarmSpec.maximumPendingAlarms));
    expect(plan.keys.toList(), orderedEquals(plan.keys.toList()..sort()));
  });
}
