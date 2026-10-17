import 'package:akshi/features/domains/domain/domain_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1, 12);

  test('unknown is used when no expiry date exists', () {
    expect(statusForExpiry(null, now: now), DomainStatus.unknown);
  });

  test('classifies upcoming expiry windows', () {
    expect(
      statusForExpiry(now.add(const Duration(days: 40)), now: now),
      DomainStatus.healthy,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 8)), now: now),
      DomainStatus.warning,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 3)), now: now),
      DomainStatus.critical,
    );
    expect(
      statusForExpiry(now.subtract(const Duration(minutes: 1)), now: now),
      DomainStatus.expired,
    );
  });

  test('uses inclusive warning and critical boundaries', () {
    expect(
      statusForExpiry(now.add(const Duration(days: 10)), now: now),
      DomainStatus.warning,
    );
    expect(
      statusForExpiry(now.add(const Duration(days: 5)), now: now),
      DomainStatus.critical,
    );
  });

  test('treats the exact expiry instant as expired', () {
    expect(statusForExpiry(now, now: now), DomainStatus.expired);
  });

  test('honors custom warning thresholds', () {
    expect(
      statusForExpiry(
        now.add(const Duration(days: 20)),
        warningDays: 30,
        criticalDays: 15,
        now: now,
      ),
      DomainStatus.warning,
    );
  });
}
