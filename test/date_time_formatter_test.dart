import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock formatting is always 24-hour', () {
    expect(format24HourTime(hour: 0, minute: 5), '00:05');
    expect(format24HourTime(hour: 17, minute: 5), '17:05');
    expect(format24HourTime(hour: 23, minute: 59), '23:59');
  });

  test('calendar dates use day, full month name, and year', () {
    expect(formatCalendarDate(year: 2026, month: 5, day: 24), '24 May 2026');
  });

  test('local date-time formatting is context-free and unambiguous', () {
    expect(
      formatLocalDateTime(DateTime(2026, 8, 23, 21, 7)),
      '23 August 2026 · 21:07',
    );
  });

  test('diagnostic UTC timestamps use the same date and clock contract', () {
    expect(
      formatUtcDateTime(DateTime.utc(2026, 5, 24, 18, 5)),
      '24 May 2026 · 18:05 UTC',
    );
  });

  test('invalid clock values fail at the formatter boundary', () {
    expect(() => format24HourTime(hour: 24, minute: 0), throwsRangeError);
  });

  test('invalid calendar values fail at the formatter boundary', () {
    expect(
      () => formatCalendarDate(year: 2026, month: 2, day: 29),
      throwsRangeError,
    );
  });
}
