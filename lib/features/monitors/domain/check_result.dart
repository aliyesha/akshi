class CertificateCheckResult {
  const CertificateCheckResult({
    required this.validFrom,
    required this.expiresAt,
    required this.issuer,
    required this.subject,
    required this.fingerprint,
    required this.trusted,
  });

  final DateTime validFrom;
  final DateTime expiresAt;
  final String issuer;
  final String subject;
  final String fingerprint;
  final bool trusted;
}

class DomainCheckResult {
  const DomainCheckResult({
    required this.expiresAt,
    required this.source,
    required this.registeredDomain,
  });

  final DateTime expiresAt;
  final String source;
  final String registeredDomain;
}
