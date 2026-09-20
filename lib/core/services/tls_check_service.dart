import 'dart:async';
import 'dart:io';

import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';
import 'package:crypto/crypto.dart';

class TlsCheckService {
  const TlsCheckService();

  Future<CertificateCheckResult> check(String hostname, int port) async {
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
      return CertificateCheckResult(
        validFrom: certificate.startValidity.toLocal(),
        expiresAt: certificate.endValidity.toLocal(),
        issuer: formatCertificateIssuer(certificate.issuer),
        subject: formatCertificateSubject(certificate.subject),
        fingerprint: fingerprint,
        trusted: trusted,
      );
    } finally {
      await socket.close();
    }
  }
}

class TlsCheckException implements Exception {
  const TlsCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}
