import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';

enum MonitorCheckKind {
  domainRegistration('domain-registration', 'Domain registration'),
  tlsCertificate('tls-certificate', 'TLS certificate');

  const MonitorCheckKind(this.id, this.label);

  final String id;
  final String label;
}

class MonitorFinding {
  const MonitorFinding({
    required this.kind,
    required this.status,
    required this.summary,
    this.expiresAt,
  });

  final MonitorCheckKind kind;
  final MonitorStatus status;
  final String summary;
  final DateTime? expiresAt;

  bool get needsAttention => switch (status) {
    MonitorStatus.warning ||
    MonitorStatus.critical ||
    MonitorStatus.expired ||
    MonitorStatus.failed ||
    MonitorStatus.unavailable => true,
    MonitorStatus.unknown || MonitorStatus.healthy => false,
  };
}

List<MonitorFinding> findingsForMonitor(
  MonitorEntry monitor, {
  int warningDays = 10,
  int criticalDays = 5,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  var domainStatus = statusForExpiry(
    monitor.domainExpiresAt,
    warningDays: warningDays,
    criticalDays: criticalDays,
    now: referenceTime,
  );
  var certificateStatus = statusForExpiry(
    monitor.certificateExpiresAt,
    warningDays: warningDays,
    criticalDays: criticalDays,
    now: referenceTime,
  );
  final domainUnavailable = monitor.domainError != null;
  final certificateUnavailable = monitor.certificateError != null;
  if (domainUnavailable) domainStatus = MonitorStatus.unavailable;
  if (certificateUnavailable) certificateStatus = MonitorStatus.unavailable;
  if (monitor.tlsTrusted == false) certificateStatus = MonitorStatus.critical;

  return <MonitorFinding>[
    MonitorFinding(
      kind: MonitorCheckKind.domainRegistration,
      status: domainStatus,
      summary: domainUnavailable
          ? 'Latest domain check unavailable'
          : _summary(domainStatus, monitor.domainExpiresAt, referenceTime),
      expiresAt: monitor.domainExpiresAt,
    ),
    MonitorFinding(
      kind: MonitorCheckKind.tlsCertificate,
      status: certificateStatus,
      summary: monitor.tlsTrusted == false
          ? 'Certificate trust could not be verified'
          : certificateUnavailable
          ? 'Latest certificate check unavailable'
          : _summary(
              certificateStatus,
              monitor.certificateExpiresAt,
              referenceTime,
            ),
      expiresAt: monitor.certificateExpiresAt,
    ),
  ];
}

String _summary(MonitorStatus status, DateTime? expiry, DateTime now) {
  if (expiry == null) return 'Expiry date unavailable';
  final days = expiry.difference(now).inDays;
  return switch (status) {
    MonitorStatus.expired =>
      days == 0
          ? 'Expired today'
          : 'Expired ${days.abs()} ${days.abs() == 1 ? 'day' : 'days'} ago',
    MonitorStatus.healthy || MonitorStatus.warning || MonitorStatus.critical =>
      days == 0
          ? 'Expires today'
          : 'Expires in $days ${days == 1 ? 'day' : 'days'}',
    MonitorStatus.failed => 'Check failed',
    MonitorStatus.unavailable => 'Currently unavailable',
    MonitorStatus.unknown => 'Not checked yet',
  };
}
