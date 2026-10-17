import 'dart:convert';

import 'package:akshi/core/services/notification_destination.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  late ExpiryAlarmSpec alarm;

  setUpAll(() {
    final utc = tz.UTC;
    const date = AlarmDate(2026, 5, 14);
    alarm = ExpiryAlarmSpec(
      date: date,
      scheduledAt: date.at(utc, 9, 0),
      timeZoneId: utc.name,
      items: const <ExpiryAlarmItem>[
        ExpiryAlarmItem(
          domainId: 'first-id',
          hostname: 'first.example',
          reasons: <ExpiryAlarmReason>[
            ExpiryAlarmReason(
              kind: ExpiryAlarmKind.domainRegistration,
              expiryDate: AlarmDate(2026, 5, 24),
              warningDays: 10,
            ),
          ],
        ),
        ExpiryAlarmItem(
          domainId: 'second-id',
          hostname: 'second.example',
          reasons: <ExpiryAlarmReason>[
            ExpiryAlarmReason(
              kind: ExpiryAlarmKind.tlsCertificate,
              expiryDate: AlarmDate(2026, 5, 24),
              warningDays: 10,
            ),
          ],
        ),
      ],
    );
  });

  test('versioned alarm payload routes to exact domains and alarm date', () {
    final destination = NotificationDestination.fromPayload(alarm.payload);

    expect(destination, isNotNull);
    expect(destination!.domainIds, <String>['first-id', 'second-id']);
    expect(destination.alarmDate, '2026-05-14');
    final uri = Uri.parse(destination.route);
    expect(uri.path, '/attention');
    expect(uri.queryParameters['source'], 'expiry');
    expect(uri.queryParameters['date'], '2026-05-14');
    expect(uri.queryParameters['ids'], 'first-id,second-id');
  });

  test('malformed and unsupported payloads are rejected', () {
    expect(NotificationDestination.fromPayload(null), isNull);
    expect(NotificationDestination.fromPayload(''), isNull);
    expect(NotificationDestination.fromPayload('not-json'), isNull);
    expect(NotificationDestination.fromPayload('{}'), isNull);
    expect(
      NotificationDestination.fromPayload(
        jsonEncode(<String, Object>{
          'version': 1,
          'type': 'other',
          'date': '2026-05-14',
          'items': <Object>[],
        }),
      ),
      isNull,
    );
    expect(
      NotificationDestination.fromPayload(
        jsonEncode(<String, Object>{
          'version': 1,
          'type': 'expiry_alarm',
          'date': '2026-05-14',
          'items': <Object>['bad'],
        }),
      ),
      isNull,
    );
  });

  test('oversized payloads are rejected before the native boundary', () {
    final oversized = List<String>.filled(
      maximumNotificationPayloadBytes + 1,
      'x',
    ).join();
    expect(notificationPayloadFits(oversized), isFalse);
    expect(NotificationDestination.fromPayload(oversized), isNull);

    final utc = tz.UTC;
    const date = AlarmDate(2026, 5, 14);
    final oversizedAlarm = ExpiryAlarmSpec(
      date: date,
      scheduledAt: date.at(utc, 9, 0),
      timeZoneId: utc.name,
      items: <ExpiryAlarmItem>[
        ExpiryAlarmItem(
          domainId: oversized,
          hostname: 'example.com',
          reasons: const <ExpiryAlarmReason>[
            ExpiryAlarmReason(
              kind: ExpiryAlarmKind.domainRegistration,
              expiryDate: AlarmDate(2026, 5, 24),
              warningDays: 10,
            ),
          ],
        ),
      ],
    );

    expect(() => oversizedAlarm.payload, throwsStateError);
  });

  test('observed parser rejects a modified integrity revision', () {
    final json = jsonDecode(alarm.payload) as Map<String, dynamic>;
    json['date'] = '2026-05-15';
    final observed = ObservedExpiryAlarm.tryParse(
      id: alarm.notificationId,
      title: alarm.title,
      body: alarm.body,
      payload: jsonEncode(json),
    );

    expect(observed, isNull);
  });

  test('observed parser round trips canonical title body and payload', () {
    final observed = ObservedExpiryAlarm.tryParse(
      id: alarm.notificationId,
      title: alarm.title,
      body: alarm.body,
      payload: alarm.payload,
    );

    expect(observed, isNotNull);
    expect(observed!.matches(alarm), isTrue);
    expect(observed.domainIds, <String>['first-id', 'second-id']);
  });

  test('alarm dates reject impossible calendar days', () {
    expect(AlarmDate.parse('2026-02-28'), const AlarmDate(2026, 2, 28));
    for (final value in <String>['2026-02-29', '2026-06-31']) {
      expect(() => AlarmDate.parse(value), throwsA(isA<FormatException>()));
    }
  });
}
