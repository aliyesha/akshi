import 'dart:async';
import 'dart:io';

import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// Opens a foreground TLS connection and extracts certificate facts.
///
/// A failed trust handshake is retried only to read the presented certificate;
/// the result retains that it was not trusted.
class TlsCheckService {
  const TlsCheckService();

  /// Connects to [hostname]:[port], verifies trust, and parses X.509 details.
  Future<CertificateCheckResult> check(String hostname, int port) async {
    appLogger.info(
      'service.tls.check.started',
      data: <String, Object?>{'hostname': hostname, 'port': port},
    );
    var trusted = true;
    SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        hostname,
        port,
        timeout: const Duration(seconds: 12),
      );
    } on HandshakeException {
      trusted = false;
      socket = await SecureSocket.connect(
        hostname,
        port,
        timeout: const Duration(seconds: 12),
        onBadCertificate: (_) => true,
      );
    }

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

/// Extracts SANs, serial, signature, and public-key facts from a PEM certificate.
_ParsedCertificateDetails _certificateDetails(String pem, String hostname) {
  try {
    final data = X509Utils.x509CertificateFromPem(pem);
    final tbsCertificate = data.tbsCertificate;
    final sans =
        tbsCertificate?.extensions?.subjectAlternativNames ?? const <String>[];
    final normalizedSans =
        sans
            .map(_cleanAlternativeName)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final publicKey = tbsCertificate?.subjectPublicKeyInfo;
    final algorithm = publicKey?.algorithmReadableName ?? publicKey?.algorithm;
    final keyLength = publicKey?.length;
    final parameter = publicKey?.parameterReadableName ?? publicKey?.parameter;
    return _ParsedCertificateDetails(
      hostnameMatches: normalizedSans.isEmpty
          ? null
          : normalizedSans.any((name) => _matchesHostname(hostname, name)),
      subjectAlternativeNames: normalizedSans,
      serialNumber: tbsCertificate?.serialNumber
          .toRadixString(16)
          .toUpperCase(),
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
    return const _ParsedCertificateDetails(
      hostnameMatches: null,
      subjectAlternativeNames: <String>[],
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
