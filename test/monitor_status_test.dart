import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1, 12);

  test('unknown is used when no expiry date exists', () {
    expect(statusForExpiry(null, now: now), MonitorStatus.unknown);
  });

  test('classifies upcoming expiry windows', () {
    expect(
      statusForExpiry(now.add(const Duration(days: 40)), now: now),
      MonitorStatus.healthy,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 8)), now: now),
      MonitorStatus.warning,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 3)), now: now),
      MonitorStatus.critical,
    );
    expect(
      statusForExpiry(now.subtract(const Duration(minutes: 1)), now: now),
      MonitorStatus.expired,
    );
  });

  test('uses inclusive warning and critical boundaries', () {
    expect(
      statusForExpiry(now.add(const Duration(days: 10)), now: now),
      MonitorStatus.warning,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 5)), now: now),
      MonitorStatus.critical,
    );
  });

  test('treats the exact expiry instant as expired', () {
    expect(statusForExpiry(now, now: now), MonitorStatus.expired);
  });

  test('honors custom warning thresholds', () {
    expect(
      statusForExpiry(
        now.add(const Duration(days: 20)),
        warningDays: 30,
        criticalDays: 15,
        now: now,
      ),
      MonitorStatus.warning,
    );
  });
}
