import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults match the product reminder policy', () {
    final settings = AppSettings();

    expect(settings.remindersEnabled, isTrue);
    expect(settings.firstWarningDays, 10);
    expect(settings.secondWarningDays, 5);
    expect(settings.notificationHour, 9);
    expect(settings.notificationMinute, 0);
    expect(settings.themeMode, AkshiThemeMode.system);
  });

  test('warning offsets reserve day one and remain strictly ordered', () {
    final closestAllowed = AppSettings(
      firstWarningDays: 3,
      secondWarningDays: 2,
    );

    expect(closestAllowed.firstWarningDays, 3);
    expect(closestAllowed.secondWarningDays, 2);
    expect(
      () => AppSettings(firstWarningDays: 10, secondWarningDays: 1),
      throwsRangeError,
    );
    expect(
      () => AppSettings(firstWarningDays: 3, secondWarningDays: 3),
      throwsArgumentError,
    );
    expect(
      () => AppSettings(firstWarningDays: 2, secondWarningDays: 3),
      throwsArgumentError,
    );
  });

  test('copyWith updates only selected settings', () {
    final original = AppSettings();
    final updated = original.copyWith(
      secondWarningDays: 7,
      notificationHour: 18,
      themeMode: AkshiThemeMode.dark,
      remindersEnabled: false,
    );

    expect(updated.remindersEnabled, isFalse);
    expect(updated.firstWarningDays, 10);
    expect(updated.secondWarningDays, 7);
    expect(updated.notificationHour, 18);
    expect(updated.notificationMinute, 0);
    expect(updated.themeMode, AkshiThemeMode.dark);
  });

  test('schedule equality ignores appearance but detects alarm inputs', () {
    final original = AppSettings();

    expect(
      original.hasSameReminderSchedule(
        original.copyWith(themeMode: AkshiThemeMode.dark),
      ),
      isTrue,
    );
    expect(
      original.hasSameReminderSchedule(original.copyWith(firstWarningDays: 30)),
      isFalse,
    );
    expect(
      original.hasSameReminderSchedule(
        original.copyWith(notificationMinute: 15),
      ),
      isFalse,
    );
    expect(
      original.hasSameReminderSchedule(
        original.copyWith(remindersEnabled: false),
      ),
      isFalse,
    );
  });

  test('schedule merge preserves unrelated settings', () {
    final current = AppSettings(
      firstWarningDays: 30,
      secondWarningDays: 15,
      themeMode: AkshiThemeMode.dark,
    );
    final draft = AppSettings(
      remindersEnabled: false,
      firstWarningDays: 20,
      secondWarningDays: 8,
      notificationHour: 18,
      notificationMinute: 30,
      themeMode: AkshiThemeMode.light,
    );

    final merged = current.withReminderScheduleFrom(draft);

    expect(merged.hasSameReminderSchedule(draft), isTrue);
    expect(merged.themeMode, AkshiThemeMode.dark);
  });
}
