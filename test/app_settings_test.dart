import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults match the product reminder policy', () {
    const settings = AppSettings();

    expect(settings.firstWarningDays, 10);
    expect(settings.secondWarningDays, 5);
    expect(settings.notificationHour, 9);
    expect(settings.notificationMinute, 0);
    expect(settings.themeMode, AkshiThemeMode.system);
  });

  test('copyWith updates only selected settings', () {
    const original = AppSettings();
    final updated = original.copyWith(
      secondWarningDays: 7,
      notificationHour: 18,
      themeMode: AkshiThemeMode.dark,
    );

    expect(updated.firstWarningDays, 10);
    expect(updated.secondWarningDays, 7);
    expect(updated.notificationHour, 18);
    expect(updated.notificationMinute, 0);
    expect(updated.themeMode, AkshiThemeMode.dark);
  });
}
