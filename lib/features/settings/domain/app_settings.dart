enum AkshiThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.remindersEnabled = false,
    this.firstWarningDays = 10,
    this.secondWarningDays = 5,
    this.notificationHour = 9,
    this.notificationMinute = 0,
    this.themeMode = AkshiThemeMode.system,
  });

  final bool remindersEnabled;
  final int firstWarningDays;
  final int secondWarningDays;
  final int notificationHour;
  final int notificationMinute;
  final AkshiThemeMode themeMode;

  AppSettings copyWith({
    bool? remindersEnabled,
    int? firstWarningDays,
    int? secondWarningDays,
    int? notificationHour,
    int? notificationMinute,
    AkshiThemeMode? themeMode,
  }) => AppSettings(
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    firstWarningDays: firstWarningDays ?? this.firstWarningDays,
    secondWarningDays: secondWarningDays ?? this.secondWarningDays,
    notificationHour: notificationHour ?? this.notificationHour,
    notificationMinute: notificationMinute ?? this.notificationMinute,
    themeMode: themeMode ?? this.themeMode,
  );

  /// Only these values affect the set and delivery time of expiry alarms.
  bool hasSameReminderSchedule(AppSettings other) =>
      remindersEnabled == other.remindersEnabled &&
      firstWarningDays == other.firstWarningDays &&
      secondWarningDays == other.secondWarningDays &&
      notificationHour == other.notificationHour &&
      notificationMinute == other.notificationMinute;
}
