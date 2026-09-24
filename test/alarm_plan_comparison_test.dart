import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location utc;

  setUpAll(() => utc = tz.UTC);

  ExpiryAlarmSpec spec(AlarmDate date, {int hour = 9, String id = 'one'}) =>
      ExpiryAlarmSpec(
        date: date,
        scheduledAt: date.at(utc, hour, 0),
        timeZoneId: utc.name,
        items: <ExpiryAlarmItem>[
          ExpiryAlarmItem(
            monitorId: id,
            hostname: '$id.example',
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

  ObservedExpiryAlarm observed(ExpiryAlarmSpec value) =>
      ObservedExpiryAlarm.tryParse(
        id: value.notificationId,
        title: value.title,
        body: value.body,
        payload: value.payload,
      )!;

  test('set comparison classifies create delete replace and unchanged', () {
    const createDate = AlarmDate(2026, 2, 14);
    const deleteDate = AlarmDate(2026, 3, 14);
    const replaceDate = AlarmDate(2026, 4, 14);
    const unchangedDate = AlarmDate(2026, 5, 14);
    final oldReplace = spec(replaceDate, hour: 9);
    final newReplace = spec(replaceDate, hour: 18);
    final unchanged = spec(unchangedDate);

    final comparison = compareAlarmPlans(
      current: <AlarmDate, ObservedExpiryAlarm>{
        deleteDate: observed(spec(deleteDate)),
        replaceDate: observed(oldReplace),
        unchangedDate: observed(unchanged),
      },
      desired: <AlarmDate, ExpiryAlarmSpec>{
        createDate: spec(createDate),
        replaceDate: newReplace,
        unchangedDate: unchanged,
      },
    );

    expect(
      <AlarmDate, AlarmChange>{
        for (final value in comparison) value.date: value.change,
      },
      <AlarmDate, AlarmChange>{
        createDate: AlarmChange.create,
        deleteDate: AlarmChange.delete,
        replaceDate: AlarmChange.replace,
        unchangedDate: AlarmChange.unchanged,
      },
    );
    expect(
      comparison.where((value) => value.isDirty),
      hasLength(3),
    );
  });

  test('single date remains one comparison when domain list changes', () {
    const date = AlarmDate(2026, 6, 14);
    final one = spec(date, id: 'alpha');
    final two = ExpiryAlarmSpec(
      date: date,
      scheduledAt: date.at(utc, 9, 0),
      timeZoneId: utc.name,
      items: <ExpiryAlarmItem>[
        ...one.items,
        spec(date, id: 'beta').items.single,
      ],
    );

    final comparison = compareAlarmPlans(
      current: <AlarmDate, ObservedExpiryAlarm>{date: observed(one)},
      desired: <AlarmDate, ExpiryAlarmSpec>{date: two},
    );

    expect(comparison, hasLength(1));
    expect(comparison.single.change, AlarmChange.replace);
  });
}
