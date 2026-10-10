import 'dart:io';

import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// Opens a foreground TLS connection and extracts certificate facts.
///
/// Trust failures are accepted only long enough to inspect the presented
/// certificate; the result records that platform verification failed.
class TlsCheckService {
  const TlsCheckService();

  /// Connects to [hostname]:[port], verifies trust, and parses X.509 details.
  Future<CertificateCheckResult> check(String hostname, int port) async {
    appLogger.info(
      'service.tls.check.started',
      data: <String, Object?>{'hostname': hostname, 'port': port},
    );
    var trusted = true;
    final socket = await SecureSocket.connect(
      hostname,
      port,
      timeout: const Duration(seconds: 12),
      onBadCertificate: (_) {
        trusted = false;
        return true;
      },
    );

    try {
      final certificate = socket.peerCertificate;
      if (certificate == null) {
        throw const TlsCheckException(
          'The server did not provide a certificate',
        );
      }
      final fingerprint = sha256.convert(certificate.der).toString();
      final details = _certificateDetails(certificate.pem, hostname);
      appLogger.info(
        'service.tls.check.completed',
        data: <String, Object?>{
          'hostname': hostname,
          'port': port,
          'trusted': trusted,
        },
      );
      return CertificateCheckResult(
        validFrom: certificate.startValidity.toLocal(),
        expiresAt: certificate.endValidity.toLocal(),
        issuer: formatCertificateIssuer(certificate.issuer),
        subject: formatCertificateSubject(certificate.subject),
        fingerprint: fingerprint,
        trusted: trusted,
        hostnameMatches: details.hostnameMatches ?? (trusted ? true : null),
        subjectAlternativeNames: details.subjectAlternativeNames,
        serialNumber: details.serialNumber,
        signatureAlgorithm: details.signatureAlgorithm,
        publicKeyAlgorithm: details.publicKeyAlgorithm,
        publicKeyDetails: details.publicKeyDetails,
      );
    } finally {
      await socket.close();
    }
  }
}

/// Extracts one coherent SAN, serial, signature, and public-key observation.
///
/// A parser failure rejects the TLS result; it must never combine a new
/// fingerprint and validity period with details retained from an older leaf.
_ParsedCertificateDetails _certificateDetails(String pem, String hostname) {
  try {
    final data = X509Utils.x509CertificateFromPem(pem);
    final tbsCertificate = data.tbsCertificate;
    if (tbsCertificate == null) {
      throw const FormatException('Certificate has no signed body.');
    }
    final sans =
        tbsCertificate.extensions?.subjectAlternativNames ?? const <String>[];
    final normalizedSans =
        sans
            .map(_cleanAlternativeName)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final publicKey = tbsCertificate.subjectPublicKeyInfo;
    final algorithm = publicKey.algorithmReadableName ?? publicKey.algorithm;
    final keyLength = publicKey.length;
    final parameter = publicKey.parameterReadableName ?? publicKey.parameter;
    return _ParsedCertificateDetails(
      hostnameMatches: normalizedSans.isEmpty
          ? null
          : normalizedSans.any((name) => _matchesHostname(hostname, name)),
      subjectAlternativeNames: normalizedSans,
      serialNumber: tbsCertificate.serialNumber.toRadixString(16).toUpperCase(),
      signatureAlgorithm:
          data.signatureAlgorithmReadableName ?? data.signatureAlgorithm,
      publicKeyAlgorithm: algorithm,
      publicKeyDetails: <String>[
        if (keyLength != null) '$keyLength bit',
        ?parameter,
      ].join(' · ').nullIfEmpty,
    );
  } catch (error, stackTrace) {
    appLogger.error(
      'service.tls.certificate.parse.failed',
      error,
      stackTrace,
      data: <String, Object?>{'hostname': hostname},
    );
    throw const TlsCheckException(
      'The server certificate could not be parsed completely',
    );
  }
}

String _cleanAlternativeName(String value) => value
    .replaceFirst(RegExp(r'^(DNS|DNSName):\s*', caseSensitive: false), '')
    .trim()
    .toLowerCase();

/// Applies exact or one-label wildcard matching to certificate SANs.
bool _matchesHostname(String hostname, String pattern) {
  final normalizedHost = hostname.toLowerCase();
  final normalizedPattern = pattern.toLowerCase();
  if (!normalizedPattern.startsWith('*.')) {
    return normalizedHost == normalizedPattern;
  }
  final suffix = normalizedPattern.substring(1);
  return normalizedHost.endsWith(suffix) &&
      normalizedHost.split('.').length == normalizedPattern.split('.').length;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _ParsedCertificateDetails {
  const _ParsedCertificateDetails({
    required this.hostnameMatches,
    required this.subjectAlternativeNames,
    this.serialNumber,
    this.signatureAlgorithm,
    this.publicKeyAlgorithm,
    this.publicKeyDetails,
  });

  final bool? hostnameMatches;
  final List<String> subjectAlternativeNames;
  final String? serialNumber;
  final String? signatureAlgorithm;
  final String? publicKeyAlgorithm;
  final String? publicKeyDetails;
}

class TlsCheckException implements Exception {
  const TlsCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}
