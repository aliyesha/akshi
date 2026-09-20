enum AkshiThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.firstWarningDays = 10,
    this.secondWarningDays = 5,
    this.notificationHour = 9,
    this.notificationMinute = 0,
    this.themeMode = AkshiThemeMode.system,
  });

  final int firstWarningDays;
  final int secondWarningDays;
  final int notificationHour;
  final int notificationMinute;
  final AkshiThemeMode themeMode;

  AppSettings copyWith({
    int? firstWarningDays,
    int? secondWarningDays,
    int? notificationHour,
    int? notificationMinute,
    AkshiThemeMode? themeMode,
  }) => AppSettings(
    firstWarningDays: firstWarningDays ?? this.firstWarningDays,
    secondWarningDays: secondWarningDays ?? this.secondWarningDays,
    notificationHour: notificationHour ?? this.notificationHour,
    notificationMinute: notificationMinute ?? this.notificationMinute,
    themeMode: themeMode ?? this.themeMode,
  );
}
