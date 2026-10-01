import 'package:akshi/features/reminders/application/alarm_reconciler.dart';
import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location utc;

  setUpAll(() => utc = tz.UTC);

  ExpiryAlarmSpec alarm(
    int month,
    int day, {
    String id = 'monitor',
    String hostname = 'monitor.example',
    int hour = 9,
  }) {
    final date = AlarmDate(2026, month, day);
    return ExpiryAlarmSpec(
      date: date,
      scheduledAt: date.at(utc, hour, 0),
      timeZoneId: utc.name,
      items: <ExpiryAlarmItem>[
        ExpiryAlarmItem(
          monitorId: id,
          hostname: hostname,
          reasons: <ExpiryAlarmReason>[
            ExpiryAlarmReason(
              kind: ExpiryAlarmKind.domainRegistration,
              expiryDate: date.subtractDays(-10),
              warningDays: 10,
            ),
          ],
        ),
      ],
    );
  }

  Map<AlarmDate, ExpiryAlarmSpec> plan(Iterable<ExpiryAlarmSpec> alarms) =>
      <AlarmDate, ExpiryAlarmSpec>{
        for (final value in alarms) value.date: value,
      };

  PlatformAlarmRequest request(ExpiryAlarmSpec value) => PlatformAlarmRequest(
    id: value.notificationId,
    title: value.title,
    body: value.body,
    payload: value.payload,
  );

  AlarmReconciler reconciler(
    _FakeAlarmPlatform platform, {
    AlarmAuditTrail audit = const NoOpAlarmAuditTrail(),
  }) => AlarmReconciler(
    platform,
    audit,
    clock: () => DateTime.utc(2026, 8, 1, 12),
  );

  test(
    'no pending alarms creates every desired date in chronological order',
    () async {
      final platform = _FakeAlarmPlatform();
      final first = alarm(2, 14);
      final second = alarm(3, 14);

      final result = await reconciler(platform)
          .reconcile(plan(<ExpiryAlarmSpec>[second, first]));

      expect(result.healthy, isTrue);
      expect(result.created, 2);
      expect(platform.operations, <String>[
        'schedule:${first.notificationId}',
        'schedule:${second.notificationId}',
      ]);
    },
  );

  test('an identical second reconciliation performs zero writes', () async {
    final existing = alarm(4, 10);
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
      request(existing),
    ]);
    final engine = reconciler(platform);

    final first = await engine.reconcile(plan(<ExpiryAlarmSpec>[existing]));
    final second = await engine.reconcile(plan(<ExpiryAlarmSpec>[existing]));

    expect(first.healthy, isTrue);
    expect(second.healthy, isTrue);
    expect(platform.operations, isEmpty);
  });

  test(
    'adding an earlier date never renumbers or rewrites later alarms',
    () async {
      final later = alarm(6, 20);
      final earlier = alarm(5, 20);
      final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
        request(later),
      ]);

      final result = await reconciler(platform)
          .reconcile(plan(<ExpiryAlarmSpec>[earlier, later]));

      expect(result.healthy, isTrue);
      expect(platform.operations, <String>[
        'schedule:${earlier.notificationId}',
      ]);
      expect(
        later.notificationId,
        ExpiryAlarmSpec.notificationIdFor(later.date),
      );
    },
  );

  test('deleting one date cancels only that stable ID', () async {
    final removed = alarm(5, 10);
    final retained = alarm(5, 20);
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
      request(removed),
      request(retained),
    ]);

    final result = await reconciler(platform)
        .reconcile(plan(<ExpiryAlarmSpec>[retained]));

    expect(result.healthy, isTrue);
    expect(platform.operations, <String>['cancel:${removed.notificationId}']);
    expect(platform.requests.single.id, retained.notificationId);
  });

  test('content or time update replaces the same notification ID', () async {
    final old = alarm(6, 14, hour: 9);
    final updated = alarm(6, 14, hour: 18);
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[request(old)]);

    final result = await reconciler(platform)
        .reconcile(plan(<ExpiryAlarmSpec>[updated]));

    expect(result.healthy, isTrue);
    expect(result.replaced, 1);
    expect(old.notificationId, updated.notificationId);
    expect(platform.operations, <String>['schedule:${updated.notificationId}']);
    expect(platform.requests.single.payload, updated.payload);
  });

  test('multiple-domain update replaces only the shared daily alarm', () async {
    final date = const AlarmDate(2026, 7, 14);
    final first = alarm(7, 14, id: 'alpha', hostname: 'alpha.example');
    final combined = ExpiryAlarmSpec(
      date: date,
      scheduledAt: date.at(utc, 9, 0),
      timeZoneId: utc.name,
      items: <ExpiryAlarmItem>[
        ...first.items,
        alarm(7, 14, id: 'beta', hostname: 'beta.example').items.single,
      ],
    );
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[request(first)]);

    final result = await reconciler(platform)
        .reconcile(plan(<ExpiryAlarmSpec>[combined]));

    expect(result.healthy, isTrue);
    expect(result.replaced, 1);
    expect(platform.operations, <String>[
      'schedule:${combined.notificationId}',
    ]);
    expect(platform.requests, hasLength(1));
  });

  test('malformed owned payload triggers one bounded repair', () async {
    final desired = alarm(7, 20);
    final malformedId = ExpiryAlarmSpec.notificationIdFor(
      const AlarmDate(2026, 7, 10),
    );
    const foreign = PlatformAlarmRequest(id: 42, payload: 'foreign');
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
      PlatformAlarmRequest(id: malformedId, payload: 'not-json'),
      foreign,
    ]);

    final result = await reconciler(platform)
        .reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isTrue);
    expect(result.repaired, isTrue);
    expect(platform.operations, <String>[
      'cancel:$malformedId',
      'schedule:${desired.notificationId}',
    ]);
    expect(platform.requests.any((value) => value.id == foreign.id), isTrue);
  });

  test(
    'post-write mismatch gets one automatic rebuild and converges',
    () async {
      final desired = alarm(8, 14);
      final platform = _FakeAlarmPlatform()..droppedSchedules = 1;

      final result = await reconciler(platform)
          .reconcile(plan(<ExpiryAlarmSpec>[desired]));

      expect(result.healthy, isTrue);
      expect(result.repaired, isTrue);
      expect(
        platform.operations.where((value) => value.startsWith('schedule:')),
        hasLength(2),
      );
    },
  );

  test(
    'platform write failure reports unhealthy without nuking valid alarms',
    () async {
      final retained = alarm(8, 10);
      final added = alarm(8, 20);
      final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
        request(retained),
      ])..failSchedule = true;

      final result = await reconciler(platform)
          .reconcile(plan(<ExpiryAlarmSpec>[retained, added]));

      expect(result.healthy, isFalse);
      expect(result.error, AlarmReconcileError.platformWriteFailed);
      expect(platform.cancelAllCalls, 0);
      expect(
        platform.requests.any((value) => value.id == retained.notificationId),
        isTrue,
      );
    },
  );

  test('repair verifies failure once and never loops', () async {
    final desired = alarm(8, 21);
    final platform = _FakeAlarmPlatform()..dropEverySchedule = true;

    final result = await reconciler(platform)
        .repair(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isFalse);
    expect(result.repaired, isTrue);
    expect(result.error, AlarmReconcileError.verificationFailed);
    expect(
      platform.operations.where((value) => value.startsWith('schedule:')),
      hasLength(1),
    );
  });

  test('empty desired plan removes and verifies every owned alarm', () async {
    final first = alarm(2, 20);
    final second = alarm(3, 20);
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
      request(first),
      request(second),
    ]);

    final result = await reconciler(platform)
        .reconcile(const <AlarmDate, ExpiryAlarmSpec>{});

    expect(result.healthy, isTrue);
    expect(result.pendingCount, 0);
    expect(platform.requests, isEmpty);
  });
  test(
    'successful handoff records computed, submitted, then verified',
    () async {
      final desired = alarm(8, 16);
      final platform = _FakeAlarmPlatform();
      final audit = _FakeAlarmAudit();

      final result = await reconciler(
        platform,
        audit: audit,
      ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

      expect(result.healthy, isTrue);
      expect(audit.events, <String>[
        'computed:2026-08-16',
        'submitted:2026-08-16',
        'verified:2026-08-16',
      ]);
    },
  );

  test('computed audit failure does not block platform handoff', () async {
    final desired = alarm(8, 17);
    final platform = _FakeAlarmPlatform();
    final audit = _FakeAlarmAudit()..failComputed = true;

    final result = await reconciler(
      platform,
      audit: audit,
    ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isTrue);
    expect(result.error, isNull);
    expect(platform.operations, <String>['schedule:${desired.notificationId}']);
    expect(audit.events, <String>[
      'submitted:2026-08-17',
      'verified:2026-08-17',
    ]);
  });

  test('platform rejection is recorded as a failed ledger entry', () async {
    final desired = alarm(8, 18);
    final platform = _FakeAlarmPlatform()..failSchedule = true;
    final audit = _FakeAlarmAudit();

    final result = await reconciler(
      platform,
      audit: audit,
    ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.error, AlarmReconcileError.platformWriteFailed);
    expect(audit.events, <String>[
      'computed:2026-08-18',
      'failed:2026-08-18:platformWriteFailed',
    ]);
  });

  test(
    'platform failure remains authoritative when failure audit fails',
    () async {
      final desired = alarm(8, 19);
      final platform = _FakeAlarmPlatform()..failSchedule = true;
      final audit = _FakeAlarmAudit()..failFailure = true;

      final result = await reconciler(
        platform,
        audit: audit,
      ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

      expect(result.healthy, isFalse);
      expect(result.error, AlarmReconcileError.platformWriteFailed);
    },
  );

  test('inventory failure never mutates platform state', () async {
    final desired = alarm(8, 20);
    final platform = _FakeAlarmPlatform()..failPending = true;

    final result = await reconciler(platform)
        .reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isFalse);
    expect(result.error, AlarmReconcileError.inventoryUnavailable);
    expect(platform.operations, isEmpty);
  });

  test('submitted audit failure does not change verified health', () async {
    final desired = alarm(8, 21);
    final platform = _FakeAlarmPlatform();
    final audit = _FakeAlarmAudit()..failSubmitted = true;

    final result = await reconciler(
      platform,
      audit: audit,
    ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isTrue);
    expect(result.error, isNull);
    expect(
      platform.operations.where((value) => value.startsWith('schedule:')),
      hasLength(1),
    );
    expect(audit.events, <String>[
      'computed:2026-08-21',
      'verified:2026-08-21',
    ]);
  });

  test('cancel audit failure does not stop remaining cancellations', () async {
    final first = alarm(8, 22);
    final second = alarm(8, 23);
    final platform = _FakeAlarmPlatform(<PlatformAlarmRequest>[
      request(first),
      request(second),
    ]);
    final audit = _FakeAlarmAudit()..failCancelled = true;

    final result = await reconciler(
      platform,
      audit: audit,
    ).reconcile(const <AlarmDate, ExpiryAlarmSpec>{});

    expect(result.healthy, isTrue);
    expect(result.deleted, 2);
    expect(platform.operations, <String>[
      'cancel:${first.notificationId}',
      'cancel:${second.notificationId}',
    ]);
    expect(platform.requests, isEmpty);
  });

  test('verified audit failure does not change platform health', () async {
    final desired = alarm(8, 24);
    final platform = _FakeAlarmPlatform();
    final audit = _FakeAlarmAudit()..failVerified = true;

    final result = await reconciler(
      platform,
      audit: audit,
    ).reconcile(plan(<ExpiryAlarmSpec>[desired]));

    expect(result.healthy, isTrue);
    expect(result.error, isNull);
    expect(result.pendingCount, 1);
  });

  test(
    'repair completes the platform plan when every audit write fails',
    () async {
      final first = alarm(8, 25);
      final second = alarm(8, 26);
      final platform = _FakeAlarmPlatform();
      final audit = _FakeAlarmAudit()
        ..failComputed = true
        ..failSubmitted = true
        ..failVerified = true;

      final result = await reconciler(
        platform,
        audit: audit,
      ).repair(plan(<ExpiryAlarmSpec>[first, second]));

      expect(result.healthy, isTrue);
      expect(result.repaired, isTrue);
      expect(platform.requests, hasLength(2));
      expect(
        platform.operations.where((value) => value.startsWith('schedule:')),
        hasLength(2),
      );
    },
  );
}

class _FakeAlarmPlatform implements AlarmPlatformGateway {
  _FakeAlarmPlatform([Iterable<PlatformAlarmRequest> initial = const []])
    : requests = initial.toList();

  final List<PlatformAlarmRequest> requests;
  final List<String> operations = <String>[];
  int droppedSchedules = 0;
  bool dropEverySchedule = false;
  bool failSchedule = false;
  bool failPending = false;
  int cancelAllCalls = 0;

  @override
  Future<List<PlatformAlarmRequest>> pendingAlarms() async {
    if (failPending) throw StateError('inventory unavailable');
    return List<PlatformAlarmRequest>.from(requests);
  }

  @override
  Future<void> scheduleAlarm(ExpiryAlarmSpec alarm) async {
    operations.add('schedule:${alarm.notificationId}');
    if (failSchedule) throw StateError('schedule failed');
    if (dropEverySchedule || droppedSchedules-- > 0) return;
    requests.removeWhere((value) => value.id == alarm.notificationId);
    requests.add(
      PlatformAlarmRequest(
        id: alarm.notificationId,
        title: alarm.title,
        body: alarm.body,
        payload: alarm.payload,
      ),
    );
  }

  @override
  Future<void> cancelAlarm(int id) async {
    operations.add('cancel:$id');
    requests.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> cancelAllAlarms() async {
    cancelAllCalls++;
    operations.add('cancelAll');
    requests.clear();
  }
}

class _FakeAlarmAudit implements AlarmAuditTrail {
  final List<String> events = <String>[];
  bool failComputed = false;
  bool failSubmitted = false;
  bool failVerified = false;
  bool failCancelled = false;
  bool failFailure = false;

  @override
  Future<void> recordComputed(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {
    if (failComputed) throw StateError('ledger unavailable');
    for (final alarm in alarms) {
      events.add('computed:${alarm.date}');
    }
  }

  @override
  Future<void> recordSubmitted(ExpiryAlarmSpec alarm, DateTime at) async {
    if (failSubmitted) throw StateError('ledger unavailable');
    events.add('submitted:${alarm.date}');
  }

  @override
  Future<void> recordVerified(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {
    if (failVerified) throw StateError('ledger unavailable');
    for (final alarm in alarms) {
      events.add('verified:${alarm.date}');
    }
  }

  @override
  Future<void> recordCancelled(int notificationId, DateTime at) async {
    if (failCancelled) throw StateError('ledger unavailable');
    events.add('cancelled:$notificationId');
  }

  @override
  Future<void> recordFailure(
    ExpiryAlarmSpec? alarm,
    String category,
    DateTime at,
  ) async {
    if (failFailure) throw StateError('ledger unavailable');
    events.add('failed:${alarm?.date}:$category');
  }
}
