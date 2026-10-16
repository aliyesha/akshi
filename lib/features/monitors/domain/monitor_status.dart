enum MonitorStatus {
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

extension MonitorStatusLabel on MonitorStatus {
  String get label => switch (this) {
    MonitorStatus.unknown => 'Not checked',
    MonitorStatus.healthy => 'Healthy',
    MonitorStatus.incomplete => 'Incomplete',
    MonitorStatus.warning => 'Needs attention',
    MonitorStatus.critical => 'Critical',
    MonitorStatus.expired => 'Expired',
    MonitorStatus.unavailable => 'Unavailable',
    MonitorStatus.failed => 'Check failed',
  };
}

MonitorStatus statusForExpiry(
  DateTime? expiry, {
  int warningDays = 10,
  int criticalDays = 5,
  DateTime? now,
}) {
  if (expiry == null) return MonitorStatus.unknown;
  final referenceTime = now ?? DateTime.now();
  if (!expiry.isAfter(referenceTime)) return MonitorStatus.expired;
  final remaining = expiry.difference(referenceTime);
  if (remaining <= Duration(days: criticalDays)) return MonitorStatus.critical;
  if (remaining <= Duration(days: warningDays)) return MonitorStatus.warning;
  return MonitorStatus.healthy;
}

/// Returns the status that needs the user's attention first.
MonitorStatus moreUrgentMonitorStatus(
  MonitorStatus first,
  MonitorStatus second,
) {
  int urgency(MonitorStatus status) => switch (status) {
    MonitorStatus.unknown => 0,
    MonitorStatus.healthy => 1,
    MonitorStatus.incomplete => 2,
    MonitorStatus.unavailable => 3,
    MonitorStatus.warning => 4,
    MonitorStatus.failed => 5,
    MonitorStatus.critical => 6,
    MonitorStatus.expired => 7,
  };

  return urgency(first) >= urgency(second) ? first : second;
}
