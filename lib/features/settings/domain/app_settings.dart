enum AkshiThemeMode { system, light, dark }

class AppSettings {
  factory AppSettings({
    bool remindersEnabled = true,
    int firstWarningDays = 10,
    int secondWarningDays = 5,
    int notificationHour = 9,
    int notificationMinute = 0,
    AkshiThemeMode themeMode = AkshiThemeMode.system,
  }) {
    _validateReminderOffsets(firstWarningDays, secondWarningDays);
    RangeError.checkValueInInterval(
      notificationHour,
      0,
      23,
      'notificationHour',
    );
    RangeError.checkValueInInterval(
      notificationMinute,
      0,
      59,
      'notificationMinute',
    );
    return AppSettings._(
      remindersEnabled: remindersEnabled,
      firstWarningDays: firstWarningDays,
      secondWarningDays: secondWarningDays,
      notificationHour: notificationHour,
      notificationMinute: notificationMinute,
      themeMode: themeMode,
    );
  }

  const AppSettings._({
    required this.remindersEnabled,
    required this.firstWarningDays,
    required this.secondWarningDays,
    required this.notificationHour,
    required this.notificationMinute,
    required this.themeMode,
  });

  static const minimumWarningDays = 2;
  static const maximumWarningDays = 90;

  final bool remindersEnabled;
  final int firstWarningDays;
  final int secondWarningDays;
  final int notificationHour;
  final int notificationMinute;
  final AkshiThemeMode themeMode;

  static bool areReminderOffsetsValid(int first, int second) =>
      second >= minimumWarningDays &&
      first > second &&
      first <= maximumWarningDays;

  static void _validateReminderOffsets(int first, int second) {
    if (second < minimumWarningDays || second >= maximumWarningDays) {
      throw RangeError.range(
        second,
        minimumWarningDays,
        maximumWarningDays - 1,
        'secondWarningDays',
      );
    }
    if (first <= second || first > maximumWarningDays) {
      throw ArgumentError.value(
        first,
        'firstWarningDays',
        'must be greater than secondWarningDays and at most '
            '$maximumWarningDays',
      );
    }
  }

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

  /// Applies only alarm-affecting values while preserving unrelated settings.
  AppSettings withReminderScheduleFrom(AppSettings source) => copyWith(
    remindersEnabled: source.remindersEnabled,
    firstWarningDays: source.firstWarningDays,
    secondWarningDays: source.secondWarningDays,
    notificationHour: source.notificationHour,
    notificationMinute: source.notificationMinute,
  );

  /// Only these values affect the set and delivery time of expiry alarms.
  bool hasSameReminderSchedule(AppSettings other) =>
      remindersEnabled == other.remindersEnabled &&
      firstWarningDays == other.firstWarningDays &&
      secondWarningDays == other.secondWarningDays &&
      notificationHour == other.notificationHour &&
      notificationMinute == other.notificationMinute;
}
