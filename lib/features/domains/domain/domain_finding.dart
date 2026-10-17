import 'package:akshi/features/domains/domain/check_activity.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/domain_status.dart';

enum DomainCheckKind {
  domainRegistration('domain-registration', 'Domain registration'),
  tlsCertificate('tls-certificate', 'TLS certificate'),
  emailConfiguration('email-configuration', 'Email configuration');

  const DomainCheckKind(this.id, this.label);

  final String id;
  final String label;

  static DomainCheckKind? fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) {
        return kind;
      }
    }
    return null;
  }
}

class DomainFinding {
  const DomainFinding({
    required this.kind,
    required this.status,
    required this.summary,
    this.expiresAt,
  });

  final DomainCheckKind kind;
  final DomainStatus status;
  final String summary;
  final DateTime? expiresAt;

  bool get needsAttention => switch (status) {
    DomainStatus.warning ||
    DomainStatus.critical ||
    DomainStatus.expired ||
    DomainStatus.failed ||
    DomainStatus.unavailable => true,
    DomainStatus.unknown ||
    DomainStatus.healthy ||
    DomainStatus.incomplete => false,
  };
}

List<DomainFinding> findingsForDomain(
  DomainEntry domain, {
  int warningDays = 10,
  int criticalDays = 5,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  var domainStatus = statusForExpiry(
    domain.domainExpiresAt,
    warningDays: warningDays,
    criticalDays: criticalDays,
    now: referenceTime,
  );
  var certificateStatus = statusForExpiry(
    domain.certificateExpiresAt,
    warningDays: warningDays,
    criticalDays: criticalDays,
    now: referenceTime,
  );
  final domainUnavailable =
      domain.domainError != null &&
      domain.domainActivity.failure?.isConnectivityInterruption != true;
  final certificateUnavailable =
      domain.certificateError != null &&
      domain.certificateActivity.failure?.isConnectivityInterruption != true;
  final emailFailure = domain.emailActivity.failure;
  final emailUnavailable =
      emailFailure != null && !emailFailure.isConnectivityInterruption;
  if (domainUnavailable) {
    domainStatus = moreUrgentDomainStatus(
      domainStatus,
      DomainStatus.unavailable,
    );
  }
  if (certificateUnavailable) {
    certificateStatus = moreUrgentDomainStatus(
      certificateStatus,
      DomainStatus.unavailable,
    );
  }
  if (domain.tlsTrusted == false) certificateStatus = DomainStatus.critical;
  if (domain.certificateHostnameMatches == false) {
    certificateStatus = DomainStatus.critical;
  }

  return <DomainFinding>[
    DomainFinding(
      kind: DomainCheckKind.domainRegistration,
      status: domainStatus,
      summary: _summaryWithAvailability(
        label: 'Domain registration',
        status: domainStatus,
        expiry: domain.domainExpiresAt,
        now: referenceTime,
        unavailable: domainUnavailable,
        detail: domain.domainError,
      ),
      expiresAt: domain.domainExpiresAt,
    ),
    if (domain.checksCertificate)
      DomainFinding(
        kind: DomainCheckKind.tlsCertificate,
        status: certificateStatus,
        summary: domain.tlsTrusted == false
            ? 'Certificate trust could not be verified'
            : domain.certificateHostnameMatches == false
            ? 'Certificate does not match the TLS hostname'
            : _summaryWithAvailability(
                label: 'TLS certificate',
                status: certificateStatus,
                expiry: domain.certificateExpiresAt,
                now: referenceTime,
                unavailable: certificateUnavailable,
                detail: domain.certificateError,
              ),
        expiresAt: domain.certificateExpiresAt,
      ),
    if (domain.checksEmail)
      DomainFinding(
        kind: DomainCheckKind.emailConfiguration,
        status: emailUnavailable
            ? DomainStatus.unavailable
            : domain.emailPosture == null
            ? DomainStatus.unknown
            : domain.emailPosture!.needsAttention
            ? DomainStatus.warning
            : domain.emailPosture!.hasUnavailable
            ? DomainStatus.incomplete
            : DomainStatus.healthy,
        summary: emailUnavailable
            ? _unavailableSummary(
                'Email configuration',
                domain.emailActivity.failure?.message,
              )
            : domain.emailPosture == null
            ? 'Email configuration not checked yet'
            : domain.emailPosture!.needsAttention
            ? 'Published email configuration needs review'
            : domain.emailPosture!.hasUnavailable
            ? 'Email configuration check incomplete'
            : 'Published email configuration looks consistent',
      ),
  ];
}

String _summaryWithAvailability({
  required String label,
  required DomainStatus status,
  required DateTime? expiry,
  required DateTime now,
  required bool unavailable,
  required String? detail,
}) {
  if (!unavailable) return _summary(status, expiry, now);
  if (status != DomainStatus.warning &&
      status != DomainStatus.critical &&
      status != DomainStatus.expired) {
    return _unavailableSummary(label, detail);
  }
  final base = _summary(status, expiry, now);
  final message = detail?.trim();
  return message == null || message.isEmpty
      ? '$base · Latest check unavailable'
      : '$base · Latest check unavailable — $message';
}

String _unavailableSummary(String label, String? detail) {
  final message = detail?.trim();
  if (message == null || message.isEmpty) {
    return '$label check unavailable';
  }
  return '$label check unavailable — $message';
}

String _summary(DomainStatus status, DateTime? expiry, DateTime now) {
  if (expiry == null) return 'Expiry date unavailable';
  final days = expiry.difference(now).inDays;
  return switch (status) {
    DomainStatus.expired =>
      days == 0
          ? 'Expired today'
          : 'Expired ${days.abs()} ${days.abs() == 1 ? 'day' : 'days'} ago',
    DomainStatus.healthy || DomainStatus.warning || DomainStatus.critical =>
      days == 0
          ? 'Expires today'
          : 'Expires in $days ${days == 1 ? 'day' : 'days'}',
    DomainStatus.incomplete => 'Check incomplete',
    DomainStatus.failed => 'Check failed',
    DomainStatus.unavailable => 'Currently unavailable',
    DomainStatus.unknown => 'Not checked yet',
  };
}
