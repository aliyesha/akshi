import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';

enum MonitorCheckKind {
  domainRegistration('domain-registration', 'Domain registration'),
  tlsCertificate('tls-certificate', 'TLS certificate'),
  emailConfiguration('email-configuration', 'Email configuration');

  const MonitorCheckKind(this.id, this.label);

  final String id;
  final String label;

  static MonitorCheckKind? fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) {
        return kind;
      }
    }
    return null;
  }
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
    MonitorStatus.unknown ||
    MonitorStatus.healthy ||
    MonitorStatus.incomplete => false,
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
  final domainUnavailable =
      monitor.domainError != null &&
      monitor.domainActivity.failure?.isConnectivityInterruption != true;
  final certificateUnavailable =
      monitor.certificateError != null &&
      monitor.certificateActivity.failure?.isConnectivityInterruption != true;
  final emailFailure = monitor.emailActivity.failure;
  final emailUnavailable =
      emailFailure != null && !emailFailure.isConnectivityInterruption;
  if (domainUnavailable) {
    domainStatus = MonitorStatus.unavailable;
  }
  if (certificateUnavailable) {
    certificateStatus = MonitorStatus.unavailable;
  }
  if (monitor.tlsTrusted == false) certificateStatus = MonitorStatus.critical;
  if (monitor.certificateHostnameMatches == false) {
    certificateStatus = MonitorStatus.critical;
  }

  return <MonitorFinding>[
    MonitorFinding(
      kind: MonitorCheckKind.domainRegistration,
      status: domainStatus,
      summary: domainUnavailable
          ? _unavailableSummary('Domain registration', monitor.domainError)
          : _summary(domainStatus, monitor.domainExpiresAt, referenceTime),
      expiresAt: monitor.domainExpiresAt,
    ),
    if (monitor.checksCertificate)
      MonitorFinding(
        kind: MonitorCheckKind.tlsCertificate,
        status: certificateStatus,
        summary: monitor.tlsTrusted == false
            ? 'Certificate trust could not be verified'
            : monitor.certificateHostnameMatches == false
            ? 'Certificate does not match the TLS hostname'
            : certificateUnavailable
            ? _unavailableSummary('TLS certificate', monitor.certificateError)
            : _summary(
                certificateStatus,
                monitor.certificateExpiresAt,
                referenceTime,
              ),
        expiresAt: monitor.certificateExpiresAt,
      ),
    if (monitor.checksEmail)
      MonitorFinding(
        kind: MonitorCheckKind.emailConfiguration,
        status: emailUnavailable
            ? MonitorStatus.unavailable
            : monitor.emailPosture == null
            ? MonitorStatus.unknown
            : monitor.emailPosture!.needsAttention
            ? MonitorStatus.warning
            : monitor.emailPosture!.hasUnavailable
            ? MonitorStatus.incomplete
            : MonitorStatus.healthy,
        summary: emailUnavailable
            ? _unavailableSummary(
                'Email configuration',
                monitor.emailActivity.failure?.message,
              )
            : monitor.emailPosture == null
            ? 'Email configuration not checked yet'
            : monitor.emailPosture!.needsAttention
            ? 'Published Email configuration needs review'
            : monitor.emailPosture!.hasUnavailable
            ? 'Email configuration check incomplete'
            : 'Published Email configuration looks consistent',
      ),
  ];
}

String _unavailableSummary(String label, String? detail) {
  final message = detail?.trim();
  if (message == null || message.isEmpty) {
    return '$label check unavailable';
  }
  return '$label check unavailable — $message';
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
    MonitorStatus.incomplete => 'Check incomplete',
    MonitorStatus.failed => 'Check failed',
    MonitorStatus.unavailable => 'Currently unavailable',
    MonitorStatus.unknown => 'Not checked yet',
  };
}
