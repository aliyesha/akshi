import 'package:akshi/core/time/calendar_day.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('tomorrow is one day even when less than 24 hours away', () {
    expect(
      localCalendarDayDifference(
        from: DateTime(2026, 6, 1, 20),
        to: DateTime(2026, 6, 2, 8),
      ),
      1,
    );
  });

  test('yesterday is minus one even when less than 24 hours ago', () {
    expect(
      localCalendarDayDifference(
        from: DateTime(2026, 6, 2, 8),
        to: DateTime(2026, 6, 1, 20),
      ),
      -1,
    );
  });

  test('month and year boundaries use calendar dates', () {
    expect(
      localCalendarDayDifference(
        from: DateTime(2026, 12, 31, 23, 59),
        to: DateTime(2027, 1, 1),
      ),
      1,
    );
  });

  test('spring-forward day is one calendar day despite lasting 23 hours', () {
    final newYork = tz.getLocation('America/New_York');
    final from = tz.TZDateTime(newYork, 2026, 3, 8);
    final to = tz.TZDateTime(newYork, 2026, 3, 9);

    expect(to.difference(from), const Duration(hours: 23));
    expect(calendarDayDifference(from: from, to: to), 1);
  });

  test('fall-back day is one calendar day despite lasting 25 hours', () {
    final newYork = tz.getLocation('America/New_York');
    final from = tz.TZDateTime(newYork, 2026, 11, 1);
    final to = tz.TZDateTime(newYork, 2026, 11, 2);

    expect(to.difference(from), const Duration(hours: 25));
    expect(calendarDayDifference(from: from, to: to), 1);
  });
}
