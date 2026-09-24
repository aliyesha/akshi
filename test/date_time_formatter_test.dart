import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock formatting is always 24-hour', () {
    expect(format24HourTime(hour: 0, minute: 5), '00:05');
    expect(format24HourTime(hour: 17, minute: 5), '17:05');
    expect(format24HourTime(hour: 23, minute: 59), '23:59');
  });

  test('date-time formatting is context-free and unambiguous', () {
    expect(
      formatLocalDateTime(DateTime(2026, 9, 23, 21, 7)),
      '2026-09-23 · 21:07',
    );
  });

  test('invalid clock values fail at the formatter boundary', () {
    expect(
      () => format24HourTime(hour: 24, minute: 0),
      throwsRangeError,
    );
  });
}
