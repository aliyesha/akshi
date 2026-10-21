import 'package:akshi/core/time/calendar_day.dart';

enum DomainStatus {
  unknown,
  healthy,

  /// A composite check produced useful results, but not every part completed.
  incomplete,
  warning,
  critical,
  expired,
  unavailable,
  failed,
}

extension DomainStatusLabel on DomainStatus {
  String get label => switch (this) {
    DomainStatus.unknown => 'Not checked',
    DomainStatus.healthy => 'Healthy',
    DomainStatus.incomplete => 'Incomplete',
    DomainStatus.warning => 'Needs attention',
    DomainStatus.critical => 'Critical',
    DomainStatus.expired => 'Expired',
    DomainStatus.unavailable => 'Unavailable',
    DomainStatus.failed => 'Check failed',
  };
}

DomainStatus statusForExpiry(
  DateTime? expiry, {
  int warningDays = 10,
  int criticalDays = 5,
  DateTime? now,
}) {
  if (expiry == null) return DomainStatus.unknown;
  final referenceTime = now ?? DateTime.now();
  if (!expiry.isAfter(referenceTime)) return DomainStatus.expired;
  final remainingDays = localCalendarDayDifference(
    from: referenceTime,
    to: expiry,
  );
  if (remainingDays <= criticalDays) return DomainStatus.critical;
  if (remainingDays <= warningDays) return DomainStatus.warning;
  return DomainStatus.healthy;
}

/// Returns the status that needs the user's attention first.
DomainStatus moreUrgentDomainStatus(DomainStatus first, DomainStatus second) {
  int urgency(DomainStatus status) => switch (status) {
    DomainStatus.unknown => 0,
    DomainStatus.healthy => 1,
    DomainStatus.incomplete => 2,
    DomainStatus.unavailable => 3,
    DomainStatus.warning => 4,
    DomainStatus.failed => 5,
    DomainStatus.critical => 6,
    DomainStatus.expired => 7,
  };

  return urgency(first) >= urgency(second) ? first : second;
}
