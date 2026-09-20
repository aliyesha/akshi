enum MonitorStatus {
  unknown,
  healthy,
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
    MonitorStatus.warning => 'Due soon',
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
