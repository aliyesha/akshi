import 'dart:convert';
import 'dart:typed_data';

import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';

const _unset = Object();

/// Immutable definition plus latest observations for one monitored hostname.
///
/// The object is the shared contract between forms, checks, persistence,
/// notifications, and the overview/detail screens.
class MonitorEntry {
  const MonitorEntry({
    required this.id,
    required this.hostname,
    required this.tlsHostname,
    required this.tlsPort,
    this.checksCertificate = false,
    this.checksEmail = false,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.enabled = true,
    this.tags = const <MonitorTag>[],
    this.domainExpiresAt,
    this.domainRegisteredAt,
    this.domainUpdatedAt,
    this.domainRegistrar,
    this.domainPublicRegistrant,
    this.domainNameServers = const <String>[],
    this.certificateExpiresAt,
    this.certificateValidFrom,
    this.lastAttemptedAt,
    this.lastVerifiedAt,
    this.domainSource,
    this.certificateIssuer,
    this.certificateSubject,
    this.certificateFingerprint,
    this.previousCertificateFingerprint,
    this.tlsTrusted,
    this.domainError,
    this.certificateError,
    this.mailSends = true,
    this.mailReceives = true,
    this.dkimSelectors = const <String>[],
    this.domainActivity = const CheckActivity(),
    this.certificateActivity = const CheckActivity(),
    this.emailActivity = const CheckActivity(),
    this.certificateHostnameMatches,
    this.certificateSubjectAlternativeNames = const <String>[],
    this.certificateSerialNumber,
    this.certificateSignatureAlgorithm,
    this.certificatePublicKeyAlgorithm,
    this.certificatePublicKeyDetails,
    this.emailPosture,
    this.dnsSnapshot,
    this.siteIcon,
  });

  final String id;
  final String hostname;
  final String tlsHostname;
  final int tlsPort;
  final bool checksCertificate;
  final bool checksEmail;
  final String? label;
  final bool enabled;
  final List<MonitorTag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? domainExpiresAt;
  final DateTime? domainRegisteredAt;
  final DateTime? domainUpdatedAt;
  final String? domainRegistrar;
  final String? domainPublicRegistrant;
  final List<String> domainNameServers;
  final DateTime? certificateExpiresAt;
  final DateTime? certificateValidFrom;
  final DateTime? lastAttemptedAt;
  final DateTime? lastVerifiedAt;
  final String? domainSource;
  final String? certificateIssuer;
  final String? certificateSubject;
  final String? certificateFingerprint;
  final String? previousCertificateFingerprint;
  final bool? tlsTrusted;
  final String? domainError;
  final String? certificateError;
  final bool mailSends;
  final bool mailReceives;
  final List<String> dkimSelectors;
  final CheckActivity domainActivity;
  final CheckActivity certificateActivity;
  final CheckActivity emailActivity;
  final bool? certificateHostnameMatches;
  final List<String> certificateSubjectAlternativeNames;
  final String? certificateSerialNumber;
  final String? certificateSignatureAlgorithm;
  final String? certificatePublicKeyAlgorithm;
  final String? certificatePublicKeyDetails;
  final EmailPosture? emailPosture;
  final DnsSnapshot? dnsSnapshot;
  final SiteIcon? siteIcon;

  /// Uses the optional user name in the UI while retaining the hostname as the
  /// stable identity and search key.
  String get displayName =>
      label?.trim().isNotEmpty == true ? label! : hostname;

  /// Reports a certificate replacement when both fingerprints are comparable.
  bool get certificateChanged =>
      previousCertificateFingerprint != null &&
      previousCertificateFingerprint != certificateFingerprint;

  /// Records one finished run and advances verification only for a complete,
  /// failure-free observation set from that same attempt.
  MonitorEntry completeAttempt(DateTime attemptedAt) {
    final activities = <CheckActivity>[
      domainActivity,
      if (checksCertificate) certificateActivity,
      if (checksEmail) emailActivity,
    ];
    final sourcesVerified = activities.every(
      (activity) =>
          activity.failure == null &&
          activity.lastAttemptedAt == attemptedAt &&
          activity.lastVerifiedAt == attemptedAt,
    );
    final dnsVerified = dnsSnapshot != null && !dnsSnapshot!.hasFailures;
    final emailVerified =
        !checksEmail || (emailPosture != null && !emailPosture!.hasUnavailable);
    return copyWith(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: sourcesVerified && dnsVerified && emailVerified
          ? attemptedAt
          : lastVerifiedAt,
    );
  }

  /// Calculates a user-facing whole-day distance from now to an expiry value.
  int? daysUntil(DateTime? value) => value?.difference(DateTime.now()).inDays;

  /// Combines domain, certificate, and email states using the most severe one.
  ///
  /// Availability failures are distinct from expiry failures so the UI can
  /// explain whether a result is unsafe or simply could not be checked.
  MonitorStatus overallStatus({
    int warningDays = 10,
    int criticalDays = 5,
    DateTime? now,
  }) {
    final domainConnectionInterrupted =
        domainActivity.failure.isConnectivityInterruption;
    final certificateConnectionInterrupted =
        certificateActivity.failure.isConnectivityInterruption;
    final emailConnectionInterrupted =
        emailActivity.failure.isConnectivityInterruption;
    if (lastVerifiedAt == null &&
        ((domainError != null && !domainConnectionInterrupted) ||
            (checksCertificate &&
                certificateError != null &&
                !certificateConnectionInterrupted) ||
            (checksEmail &&
                emailActivity.failure != null &&
                !emailConnectionInterrupted))) {
      return MonitorStatus.failed;
    }
    var domain = statusForExpiry(
      domainExpiresAt,
      warningDays: warningDays,
      criticalDays: criticalDays,
      now: now,
    );
    if (domainError != null && !domainConnectionInterrupted) {
      domain = moreUrgentMonitorStatus(domain, MonitorStatus.unavailable);
    }

    var certificate = MonitorStatus.unknown;
    if (checksCertificate) {
      certificate = statusForExpiry(
        certificateExpiresAt,
        warningDays: warningDays,
        criticalDays: criticalDays,
        now: now,
      );
      if (certificateError != null && !certificateConnectionInterrupted) {
        certificate = moreUrgentMonitorStatus(
          certificate,
          MonitorStatus.unavailable,
        );
      }
      if (tlsTrusted == false || certificateHostnameMatches == false) {
        certificate = MonitorStatus.critical;
      }
    }

    var email = MonitorStatus.unknown;
    if (checksEmail) {
      email = emailActivity.failure != null && !emailConnectionInterrupted
          ? MonitorStatus.unavailable
          : emailPosture == null
          ? MonitorStatus.unknown
          : emailPosture!.needsAttention
          ? MonitorStatus.warning
          : emailPosture!.hasUnavailable
          ? MonitorStatus.incomplete
          : MonitorStatus.healthy;
    }
    return <MonitorStatus>[
      certificate,
      email,
    ].fold(domain, moreUrgentMonitorStatus);
  }

  /// Creates a changed immutable copy while allowing nullable fields to be
  /// explicitly cleared through the internal [_unset] sentinel.
  MonitorEntry copyWith({
    String? hostname,
    String? tlsHostname,
    int? tlsPort,
    bool? checksCertificate,
    bool? checksEmail,
    Object? label = _unset,
    bool? enabled,
    List<MonitorTag>? tags,
    DateTime? updatedAt,
    Object? domainExpiresAt = _unset,
    Object? domainRegisteredAt = _unset,
    Object? domainUpdatedAt = _unset,
    Object? domainRegistrar = _unset,
    Object? domainPublicRegistrant = _unset,
    List<String>? domainNameServers,
    DateTime? certificateExpiresAt,
    DateTime? certificateValidFrom,
    DateTime? lastAttemptedAt,
    DateTime? lastVerifiedAt,
    String? domainSource,
    String? certificateIssuer,
    String? certificateSubject,
    String? certificateFingerprint,
    String? previousCertificateFingerprint,
    bool? tlsTrusted,
    Object? domainError = _unset,
    Object? certificateError = _unset,
    bool? mailSends,
    bool? mailReceives,
    List<String>? dkimSelectors,
    CheckActivity? domainActivity,
    CheckActivity? certificateActivity,
    CheckActivity? emailActivity,
    Object? certificateHostnameMatches = _unset,
    List<String>? certificateSubjectAlternativeNames,
    Object? certificateSerialNumber = _unset,
    Object? certificateSignatureAlgorithm = _unset,
    Object? certificatePublicKeyAlgorithm = _unset,
    Object? certificatePublicKeyDetails = _unset,
    Object? emailPosture = _unset,
    Object? dnsSnapshot = _unset,
    Object? siteIcon = _unset,
  }) => MonitorEntry(
    id: id,
    hostname: hostname ?? this.hostname,
    tlsHostname: tlsHostname ?? this.tlsHostname,
    tlsPort: tlsPort ?? this.tlsPort,
    checksCertificate: checksCertificate ?? this.checksCertificate,
    checksEmail: checksEmail ?? this.checksEmail,
    label: identical(label, _unset) ? this.label : label as String?,
    enabled: enabled ?? this.enabled,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    domainExpiresAt: identical(domainExpiresAt, _unset)
        ? this.domainExpiresAt
        : domainExpiresAt as DateTime?,
    domainRegisteredAt: identical(domainRegisteredAt, _unset)
        ? this.domainRegisteredAt
        : domainRegisteredAt as DateTime?,
    domainUpdatedAt: identical(domainUpdatedAt, _unset)
        ? this.domainUpdatedAt
        : domainUpdatedAt as DateTime?,
    domainRegistrar: identical(domainRegistrar, _unset)
        ? this.domainRegistrar
        : domainRegistrar as String?,
    domainPublicRegistrant: identical(domainPublicRegistrant, _unset)
        ? this.domainPublicRegistrant
        : domainPublicRegistrant as String?,
    domainNameServers: domainNameServers ?? this.domainNameServers,
    certificateExpiresAt: certificateExpiresAt ?? this.certificateExpiresAt,
    certificateValidFrom: certificateValidFrom ?? this.certificateValidFrom,
    lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
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
    mailSends: mailSends ?? this.mailSends,
    mailReceives: mailReceives ?? this.mailReceives,
    dkimSelectors: dkimSelectors ?? this.dkimSelectors,
    domainActivity: domainActivity ?? this.domainActivity,
    certificateActivity: certificateActivity ?? this.certificateActivity,
    emailActivity: emailActivity ?? this.emailActivity,
    certificateHostnameMatches: identical(certificateHostnameMatches, _unset)
        ? this.certificateHostnameMatches
        : certificateHostnameMatches as bool?,
    certificateSubjectAlternativeNames:
        certificateSubjectAlternativeNames ??
        this.certificateSubjectAlternativeNames,
    certificateSerialNumber: identical(certificateSerialNumber, _unset)
        ? this.certificateSerialNumber
        : certificateSerialNumber as String?,
    certificateSignatureAlgorithm:
        identical(certificateSignatureAlgorithm, _unset)
        ? this.certificateSignatureAlgorithm
        : certificateSignatureAlgorithm as String?,
    certificatePublicKeyAlgorithm:
        identical(certificatePublicKeyAlgorithm, _unset)
        ? this.certificatePublicKeyAlgorithm
        : certificatePublicKeyAlgorithm as String?,
    certificatePublicKeyDetails: identical(certificatePublicKeyDetails, _unset)
        ? this.certificatePublicKeyDetails
        : certificatePublicKeyDetails as String?,
    emailPosture: identical(emailPosture, _unset)
        ? this.emailPosture
        : emailPosture as EmailPosture?,
    dnsSnapshot: identical(dnsSnapshot, _unset)
        ? this.dnsSnapshot
        : dnsSnapshot as DnsSnapshot?,
    siteIcon: identical(siteIcon, _unset)
        ? this.siteIcon
        : siteIcon as SiteIcon?,
  );

  /// Serializes the complete monitor aggregate into SQLite-compatible values.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'hostname': hostname,
    'tls_hostname': tlsHostname,
    'tls_port': tlsPort,
    'checks_certificate': checksCertificate ? 1 : 0,
    'checks_email': checksEmail ? 1 : 0,
    'label': label,
    'enabled': enabled ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'mail_sends': mailSends ? 1 : 0,
    'mail_receives': mailReceives ? 1 : 0,
    'dkim_selectors_json': jsonEncode(dkimSelectors),
    ...toObservationMap(),
  };

  /// Serializes only fields produced by external monitor checks.
  Map<String, Object?> toObservationMap() => <String, Object?>{
    'domain_expires_at': domainExpiresAt?.toUtc().toIso8601String(),
    'domain_registered_at': domainRegisteredAt?.toUtc().toIso8601String(),
    'domain_updated_at': domainUpdatedAt?.toUtc().toIso8601String(),
    'domain_registrar': domainRegistrar,
    'domain_public_registrant': domainPublicRegistrant,
    'domain_nameservers_json': jsonEncode(domainNameServers),
    'certificate_expires_at': certificateExpiresAt?.toUtc().toIso8601String(),
    'certificate_valid_from': certificateValidFrom?.toUtc().toIso8601String(),
    'last_attempted_at': lastAttemptedAt?.toUtc().toIso8601String(),
    'last_verified_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'domain_source': domainSource,
    'certificate_issuer': certificateIssuer,
    'certificate_subject': certificateSubject,
    'certificate_fingerprint': certificateFingerprint,
    'previous_certificate_fingerprint': previousCertificateFingerprint,
    'tls_trusted': tlsTrusted == null ? null : (tlsTrusted! ? 1 : 0),
    'domain_error': domainError,
    'certificate_error': certificateError,
    'domain_activity_json': jsonEncode(domainActivity.toJson()),
    'certificate_activity_json': jsonEncode(certificateActivity.toJson()),
    'email_activity_json': jsonEncode(emailActivity.toJson()),
    'certificate_hostname_matches': certificateHostnameMatches == null
        ? null
        : (certificateHostnameMatches! ? 1 : 0),
    'certificate_sans_json': jsonEncode(certificateSubjectAlternativeNames),
    'certificate_serial_number': certificateSerialNumber,
    'certificate_signature_algorithm': certificateSignatureAlgorithm,
    'certificate_public_key_algorithm': certificatePublicKeyAlgorithm,
    'certificate_public_key_details': certificatePublicKeyDetails,
    'email_posture_json': emailPosture == null
        ? null
        : jsonEncode(emailPosture!.toJson()),
    'dns_snapshot_json': dnsSnapshot == null
        ? null
        : jsonEncode(dnsSnapshot!.toJson()),
    'site_icon_format': siteIcon?.format.storageValue,
    'site_icon_bytes': siteIcon?.bytes,
    'site_icon_source_url': siteIcon?.sourceUrl,
    'site_icon_checked_at': siteIcon?.checkedAt.toUtc().toIso8601String(),
  };

  /// Rehydrates a monitor row, tolerating nullable columns from a fresh check.
  factory MonitorEntry.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.tryParse(value)?.toLocal();
    }

    Map<String, Object?>? jsonMap(String key) {
      final value = map[key] as String?;
      if (value == null) return null;
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    }

    List<String> stringList(String key) {
      final value = map[key] as String?;
      if (value == null) return const <String>[];
      final decoded = jsonDecode(value);
      return decoded is List<Object?>
          ? decoded.whereType<String>().toList(growable: false)
          : const <String>[];
    }

    EmailPosture? readEmailPosture() {
      final value = jsonMap('email_posture_json');
      return value == null ? null : EmailPosture.fromJson(value);
    }

    DnsSnapshot? readDnsSnapshot() {
      final value = jsonMap('dns_snapshot_json');
      return value == null ? null : DnsSnapshot.fromJson(value);
    }

    SiteIcon? readSiteIcon() {
      final format = map['site_icon_format'] as String?;
      final bytes = map['site_icon_bytes'];
      final sourceUrl = map['site_icon_source_url'] as String?;
      final checkedAt = date('site_icon_checked_at');
      if (format == null ||
          bytes is! List<int> ||
          sourceUrl == null ||
          checkedAt == null) {
        return null;
      }
      return SiteIcon(
        format: SiteIconFormat.fromStorage(format),
        bytes: Uint8List.fromList(bytes),
        sourceUrl: sourceUrl,
        checkedAt: checkedAt,
      );
    }

    return MonitorEntry(
      id: map['id']! as String,
      hostname: map['hostname']! as String,
      tlsHostname: map['tls_hostname']! as String,
      tlsPort: map['tls_port']! as int,
      checksCertificate: (map['checks_certificate']! as int) == 1,
      checksEmail: (map['checks_email']! as int) == 1,
      label: map['label'] as String?,
      enabled: (map['enabled']! as int) == 1,
      createdAt: date('created_at')!,
      updatedAt: date('updated_at')!,
      domainExpiresAt: date('domain_expires_at'),
      domainRegisteredAt: date('domain_registered_at'),
      domainUpdatedAt: date('domain_updated_at'),
      domainRegistrar: map['domain_registrar'] as String?,
      domainPublicRegistrant: map['domain_public_registrant'] as String?,
      domainNameServers: stringList('domain_nameservers_json'),
      certificateExpiresAt: date('certificate_expires_at'),
      certificateValidFrom: date('certificate_valid_from'),
      lastAttemptedAt: date('last_attempted_at'),
      lastVerifiedAt: date('last_verified_at'),
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
      mailSends: (map['mail_sends'] as int? ?? 1) == 1,
      mailReceives: (map['mail_receives'] as int? ?? 1) == 1,
      dkimSelectors: stringList('dkim_selectors_json'),
      domainActivity: CheckActivity.fromJson(jsonMap('domain_activity_json')),
      certificateActivity: CheckActivity.fromJson(
        jsonMap('certificate_activity_json'),
      ),
      emailActivity: CheckActivity.fromJson(jsonMap('email_activity_json')),
      certificateHostnameMatches: map['certificate_hostname_matches'] == null
          ? null
          : (map['certificate_hostname_matches']! as int) == 1,
      certificateSubjectAlternativeNames: stringList('certificate_sans_json'),
      certificateSerialNumber: map['certificate_serial_number'] as String?,
      certificateSignatureAlgorithm:
          map['certificate_signature_algorithm'] as String?,
      certificatePublicKeyAlgorithm:
          map['certificate_public_key_algorithm'] as String?,
      certificatePublicKeyDetails:
          map['certificate_public_key_details'] as String?,
      emailPosture: readEmailPosture(),
      siteIcon: readSiteIcon(),
      dnsSnapshot: readDnsSnapshot(),
    );
  }
}
