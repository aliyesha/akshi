/// Formats clock values consistently in Akshi's product-wide 24-hour style.
String format24HourTime({required int hour, required int minute}) {
  RangeError.checkValueInInterval(hour, 0, 23, 'hour');
  RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  return '${_twoDigits(hour)}:${_twoDigits(minute)}';
}

/// Formats a calendar date in Akshi's single user-facing date style.
///
/// Storage, notification payloads, and route parameters may continue to use
/// ISO 8601. Anything a person reads should use this formatter instead.
String formatCalendarDate({
  required int year,
  required int month,
  required int day,
}) {
  RangeError.checkValueInInterval(month, 1, 12, 'month');
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  RangeError.checkValueInInterval(day, 1, lastDay, 'day');
  return '$day ${_monthNames[month - 1]} $year';
}

/// Formats a local calendar date without depending on widget context.
String formatLocalDate(DateTime value) {
  final local = value.toLocal();
  return formatCalendarDate(
    year: local.year,
    month: local.month,
    day: local.day,
  );
}

/// Formats a local date and time with an unambiguous 24-hour clock.
String formatLocalDateTime(DateTime value, {String separator = ' · '}) {
  final local = value.toLocal();
  return '${formatLocalDate(local)}$separator'
      '${format24HourTime(hour: local.hour, minute: local.minute)}';
}

/// Formats an instant in UTC for diagnostics while keeping the product's
/// human-readable date and 24-hour time style.
String formatUtcDateTime(DateTime value, {String separator = ' · '}) {
  final utc = value.toUtc();
  return '${formatCalendarDate(year: utc.year, month: utc.month, day: utc.day)}'
      '$separator${format24HourTime(hour: utc.hour, minute: utc.minute)} UTC';
}

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _twoDigits(int value) => value.toString().padLeft(2, '0');
