import 'dart:convert';
import 'dart:typed_data';

import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:akshi/features/monitors/domain/monitor_profile.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';

const _unset = Object();

class MonitorEntry {
  const MonitorEntry({
    required this.id,
    required this.hostname,
    required this.port,
    this.profile = MonitorProfile.website,
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
    this.siteIcon,
  });

  final String id;
  final String hostname;
  final int port;
  final MonitorProfile profile;
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
  final SiteIcon? siteIcon;

  String get displayName =>
      label?.trim().isNotEmpty == true ? label! : hostname;

  bool get certificateChanged =>
      previousCertificateFingerprint != null &&
      previousCertificateFingerprint != certificateFingerprint;

  DateTime? get latestAttemptedAt => latestCheckTime(<CheckActivity>[
    domainActivity,
    if (profile.checksCertificate) certificateActivity,
    if (profile.checksEmail) emailActivity,
  ]);

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
    if (!profile.checksCertificate) certificate = MonitorStatus.unknown;
    if (domainError != null) domain = MonitorStatus.unavailable;
    if (certificateError != null) certificate = MonitorStatus.unavailable;
    if (tlsTrusted == false) certificate = MonitorStatus.critical;
    if (certificateHostnameMatches == false) {
      certificate = MonitorStatus.critical;
    }
    var email = MonitorStatus.unknown;
    if (profile.checksEmail) {
      email = emailActivity.failure != null
          ? MonitorStatus.unavailable
          : emailPosture == null
          ? MonitorStatus.unknown
          : emailPosture!.needsAttention
          ? MonitorStatus.warning
          : MonitorStatus.healthy;
    }
    const severity = <MonitorStatus, int>{
      MonitorStatus.unknown: 0,
      MonitorStatus.healthy: 1,
      MonitorStatus.unavailable: 2,
      MonitorStatus.warning: 3,
      MonitorStatus.failed: 4,
      MonitorStatus.critical: 5,
      MonitorStatus.expired: 6,
    };
    final states = <MonitorStatus>[domain, certificate, email];
    states.sort((left, right) => severity[right]!.compareTo(severity[left]!));
    return states.first;
  }

  MonitorEntry copyWith({
    String? hostname,
    int? port,
    MonitorProfile? profile,
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
    bool? mailSends,
    bool? mailReceives,
    List<String>? dkimSelectors,
    CheckActivity? domainActivity,
    CheckActivity? certificateActivity,
    CheckActivity? emailActivity,
    bool? certificateHostnameMatches,
    List<String>? certificateSubjectAlternativeNames,
    String? certificateSerialNumber,
    String? certificateSignatureAlgorithm,
    String? certificatePublicKeyAlgorithm,
    String? certificatePublicKeyDetails,
    Object? emailPosture = _unset,
    Object? siteIcon = _unset,
  }) => MonitorEntry(
    id: id,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    profile: profile ?? this.profile,
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
    mailSends: mailSends ?? this.mailSends,
    mailReceives: mailReceives ?? this.mailReceives,
    dkimSelectors: dkimSelectors ?? this.dkimSelectors,
    domainActivity: domainActivity ?? this.domainActivity,
    certificateActivity: certificateActivity ?? this.certificateActivity,
    emailActivity: emailActivity ?? this.emailActivity,
    certificateHostnameMatches:
        certificateHostnameMatches ?? this.certificateHostnameMatches,
    certificateSubjectAlternativeNames:
        certificateSubjectAlternativeNames ??
        this.certificateSubjectAlternativeNames,
    certificateSerialNumber:
        certificateSerialNumber ?? this.certificateSerialNumber,
    certificateSignatureAlgorithm:
        certificateSignatureAlgorithm ?? this.certificateSignatureAlgorithm,
    certificatePublicKeyAlgorithm:
        certificatePublicKeyAlgorithm ?? this.certificatePublicKeyAlgorithm,
    certificatePublicKeyDetails:
        certificatePublicKeyDetails ?? this.certificatePublicKeyDetails,
    emailPosture: identical(emailPosture, _unset)
        ? this.emailPosture
        : emailPosture as EmailPosture?,
    siteIcon: identical(siteIcon, _unset)
        ? this.siteIcon
        : siteIcon as SiteIcon?,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'hostname': hostname,
    'port': port,
    'profile': profile.storageValue,
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
    'mail_sends': mailSends ? 1 : 0,
    'mail_receives': mailReceives ? 1 : 0,
    'dkim_selectors_json': jsonEncode(dkimSelectors),
    'domain_activity_json': jsonEncode(domainActivity.toJson()),
    'certificate_activity_json':
        jsonEncode(certificateActivity.toJson()),
    'email_activity_json': jsonEncode(emailActivity.toJson()),
    'certificate_hostname_matches': certificateHostnameMatches == null
        ? null
        : (certificateHostnameMatches! ? 1 : 0),
    'certificate_sans_json':
        jsonEncode(certificateSubjectAlternativeNames),
    'certificate_serial_number': certificateSerialNumber,
    'certificate_signature_algorithm': certificateSignatureAlgorithm,
    'certificate_public_key_algorithm': certificatePublicKeyAlgorithm,
    'certificate_public_key_details': certificatePublicKeyDetails,
    'email_posture_json': emailPosture == null
        ? null
        : jsonEncode(emailPosture!.toJson()),
    'site_icon_format': siteIcon?.format.storageValue,
    'site_icon_bytes': siteIcon?.bytes,
    'site_icon_source_url': siteIcon?.sourceUrl,
    'site_icon_checked_at':
        siteIcon?.checkedAt.toUtc().toIso8601String(),
  };

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
      port: map['port']! as int,
      profile: MonitorProfile.fromStorage(map['profile'] as String?),
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
      mailSends: (map['mail_sends'] as int? ?? 1) == 1,
      mailReceives: (map['mail_receives'] as int? ?? 1) == 1,
      dkimSelectors: stringList('dkim_selectors_json'),
      domainActivity: CheckActivity.fromJson(jsonMap('domain_activity_json')),
      certificateActivity: CheckActivity.fromJson(
        jsonMap('certificate_activity_json'),
      ),
      emailActivity: CheckActivity.fromJson(jsonMap('email_activity_json')),
      certificateHostnameMatches:
          map['certificate_hostname_matches'] == null
          ? null
          : (map['certificate_hostname_matches']! as int) == 1,
      certificateSubjectAlternativeNames:
          stringList('certificate_sans_json'),
      certificateSerialNumber: map['certificate_serial_number'] as String?,
      certificateSignatureAlgorithm:
          map['certificate_signature_algorithm'] as String?,
      certificatePublicKeyAlgorithm:
          map['certificate_public_key_algorithm'] as String?,
      certificatePublicKeyDetails:
          map['certificate_public_key_details'] as String?,
      emailPosture: readEmailPosture(),
      siteIcon: readSiteIcon(),
    );
  }
}
