/// Formats clock values consistently in Akshi's product-wide 24-hour style.
String format24HourTime({required int hour, required int minute}) {
  RangeError.checkValueInInterval(hour, 0, 23, 'hour');
  RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  return '${_twoDigits(hour)}:${_twoDigits(minute)}';
}

/// Formats a local calendar date without depending on widget context.
String formatLocalDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
}

/// Formats a local date and time with an unambiguous 24-hour clock.
String formatLocalDateTime(
  DateTime value, {
  String separator = ' · ',
}) {
  final local = value.toLocal();
  return '${formatLocalDate(local)}$separator'
      '${format24HourTime(hour: local.hour, minute: local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
