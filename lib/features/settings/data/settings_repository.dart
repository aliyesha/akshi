import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository();

  SharedPreferencesAsync? _preferences;

  /// Initializes platform preferences only when real repository I/O begins.
  /// Test repositories that override [load] and [save] never touch a plugin.
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<AppSettings> load() async {
    final preferences = _store;
    final themeName = await preferences.getString('theme_mode');
    final storedFirst = await preferences.getInt('first_warning_days') ?? 10;
    final storedSecond = await preferences.getInt('second_warning_days') ?? 5;
    final (
      firstWarningDays,
      secondWarningDays,
    ) = AppSettings.areReminderOffsetsValid(storedFirst, storedSecond)
        ? (storedFirst, storedSecond)
        : (10, 5);
    return AppSettings(
      remindersEnabled: await preferences.getBool('reminders_enabled') ?? true,
      firstWarningDays: firstWarningDays,
      secondWarningDays: secondWarningDays,
      notificationHour: await preferences.getInt('notification_hour') ?? 9,
      notificationMinute: await preferences.getInt('notification_minute') ?? 0,
      themeMode: AkshiThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => AkshiThemeMode.system,
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    final preferences = _store;
    await Future.wait(<Future<void>>[
      preferences.setBool('reminders_enabled', settings.remindersEnabled),
      preferences.setInt('first_warning_days', settings.firstWarningDays),
      preferences.setInt('second_warning_days', settings.secondWarningDays),
      preferences.setInt('notification_hour', settings.notificationHour),
      preferences.setInt('notification_minute', settings.notificationMinute),
      preferences.setString('theme_mode', settings.themeMode.name),
    ]);
  }
}
