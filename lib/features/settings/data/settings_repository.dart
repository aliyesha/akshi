import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<AppSettings> load() async {
    final themeName = await _preferences.getString('theme_mode');
    return AppSettings(
      firstWarningDays: await _preferences.getInt('first_warning_days') ?? 10,
      secondWarningDays: await _preferences.getInt('second_warning_days') ?? 5,
      notificationHour: await _preferences.getInt('notification_hour') ?? 9,
      notificationMinute: await _preferences.getInt('notification_minute') ?? 0,
      themeMode: AkshiThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => AkshiThemeMode.system,
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    await Future.wait(<Future<void>>[
      _preferences.setInt('first_warning_days', settings.firstWarningDays),
      _preferences.setInt('second_warning_days', settings.secondWarningDays),
      _preferences.setInt('notification_hour', settings.notificationHour),
      _preferences.setInt('notification_minute', settings.notificationMinute),
      _preferences.setString('theme_mode', settings.themeMode.name),
    ]);
  }
}
