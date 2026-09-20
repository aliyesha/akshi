import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';

const _unset = Object();

class MonitorEntry {
  const MonitorEntry({
    required this.id,
    required this.hostname,
    required this.port,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.enabled = true,
    this.tags = const <MonitorTag>[],
    this.domainExpiresAt,
    this.certificateExpiresAt,
    this.certificateValidFrom,
    this.lastCheckedAt,
    this.domainSource,
    this.certificateIssuer,
    this.certificateSubject,
    this.certificateFingerprint,
    this.previousCertificateFingerprint,
    this.tlsTrusted,
    this.domainError,
    this.certificateError,
  });

  final String id;
  final String hostname;
  final int port;
  final String? label;
  final bool enabled;
  final List<MonitorTag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? domainExpiresAt;
  final DateTime? certificateExpiresAt;
  final DateTime? certificateValidFrom;
  final DateTime? lastCheckedAt;
  final String? domainSource;
  final String? certificateIssuer;
  final String? certificateSubject;
  final String? certificateFingerprint;
  final String? previousCertificateFingerprint;
  final bool? tlsTrusted;
  final String? domainError;
  final String? certificateError;

  String get displayName =>
      label?.trim().isNotEmpty == true ? label! : hostname;

  bool get certificateChanged =>
      previousCertificateFingerprint != null &&
      previousCertificateFingerprint != certificateFingerprint;

  int? daysUntil(DateTime? value) => value?.difference(DateTime.now()).inDays;

  MonitorStatus overallStatus({int warningDays = 10, int criticalDays = 5}) {
    if (lastCheckedAt == null &&
        (domainError != null || certificateError != null)) {
      return MonitorStatus.failed;
    }
    var domain = statusForExpiry(
      domainExpiresAt,
      warningDays: warningDays,
      criticalDays: criticalDays,
    );
    var certificate = statusForExpiry(
      certificateExpiresAt,
      warningDays: warningDays,
      criticalDays: criticalDays,
    );
    if (domainError != null) domain = MonitorStatus.unavailable;
    if (certificateError != null) certificate = MonitorStatus.unavailable;
    if (tlsTrusted == false) certificate = MonitorStatus.critical;
    const severity = <MonitorStatus, int>{
      MonitorStatus.unknown: 0,
      MonitorStatus.healthy: 1,
      MonitorStatus.unavailable: 2,
      MonitorStatus.warning: 3,
      MonitorStatus.failed: 4,
      MonitorStatus.critical: 5,
      MonitorStatus.expired: 6,
    };
    return severity[domain]! >= severity[certificate]! ? domain : certificate;
  }

  MonitorEntry copyWith({
    String? hostname,
    int? port,
    Object? label = _unset,
    bool? enabled,
    List<MonitorTag>? tags,
    DateTime? updatedAt,
    DateTime? domainExpiresAt,
    DateTime? certificateExpiresAt,
    DateTime? certificateValidFrom,
    DateTime? lastCheckedAt,
    String? domainSource,
    String? certificateIssuer,
    String? certificateSubject,
    String? certificateFingerprint,
    String? previousCertificateFingerprint,
    bool? tlsTrusted,
    Object? domainError = _unset,
    Object? certificateError = _unset,
  }) => MonitorEntry(
    id: id,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    label: identical(label, _unset) ? this.label : label as String?,
    enabled: enabled ?? this.enabled,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    domainExpiresAt: domainExpiresAt ?? this.domainExpiresAt,
    certificateExpiresAt: certificateExpiresAt ?? this.certificateExpiresAt,
    certificateValidFrom: certificateValidFrom ?? this.certificateValidFrom,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    domainSource: domainSource ?? this.domainSource,
    certificateIssuer: certificateIssuer ?? this.certificateIssuer,
    certificateSubject: certificateSubject ?? this.certificateSubject,
    certificateFingerprint:
        certificateFingerprint ?? this.certificateFingerprint,
    previousCertificateFingerprint:
        previousCertificateFingerprint ?? this.previousCertificateFingerprint,
    tlsTrusted: tlsTrusted ?? this.tlsTrusted,
    domainError: identical(domainError, _unset)
        ? this.domainError
        : domainError as String?,
    certificateError: identical(certificateError, _unset)
        ? this.certificateError
        : certificateError as String?,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'hostname': hostname,
    'port': port,
    'label': label,
    'enabled': enabled ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'domain_expires_at': domainExpiresAt?.toUtc().toIso8601String(),
    'certificate_expires_at': certificateExpiresAt?.toUtc().toIso8601String(),
    'certificate_valid_from': certificateValidFrom?.toUtc().toIso8601String(),
    'last_checked_at': lastCheckedAt?.toUtc().toIso8601String(),
    'domain_source': domainSource,
    'certificate_issuer': certificateIssuer,
    'certificate_subject': certificateSubject,
    'certificate_fingerprint': certificateFingerprint,
    'previous_certificate_fingerprint': previousCertificateFingerprint,
    'tls_trusted': tlsTrusted == null ? null : (tlsTrusted! ? 1 : 0),
    'domain_error': domainError,
    'certificate_error': certificateError,
  };

  factory MonitorEntry.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.tryParse(value)?.toLocal();
    }

    return MonitorEntry(
      id: map['id']! as String,
      hostname: map['hostname']! as String,
      port: map['port']! as int,
      label: map['label'] as String?,
      enabled: (map['enabled']! as int) == 1,
      createdAt: date('created_at')!,
      updatedAt: date('updated_at')!,
      domainExpiresAt: date('domain_expires_at'),
      certificateExpiresAt: date('certificate_expires_at'),
      certificateValidFrom: date('certificate_valid_from'),
      lastCheckedAt: date('last_checked_at'),
      domainSource: map['domain_source'] as String?,
      certificateIssuer: map['certificate_issuer'] as String?,
      certificateSubject: map['certificate_subject'] as String?,
      certificateFingerprint: map['certificate_fingerprint'] as String?,
      previousCertificateFingerprint:
          map['previous_certificate_fingerprint'] as String?,
      tlsTrusted: map['tls_trusted'] == null
          ? null
          : (map['tls_trusted']! as int) == 1,
      domainError: map['domain_error'] as String?,
      certificateError: map['certificate_error'] as String?,
    );
  }
}
