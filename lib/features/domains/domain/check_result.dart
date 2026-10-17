class CertificateCheckResult {
  const CertificateCheckResult({
    required this.validFrom,
    required this.expiresAt,
    required this.issuer,
    required this.subject,
    required this.fingerprint,
    required this.trusted,
    required this.hostnameMatches,
    required this.subjectAlternativeNames,
    this.serialNumber,
    this.signatureAlgorithm,
    this.publicKeyAlgorithm,
    this.publicKeyDetails,
  });

  final DateTime validFrom;
  final DateTime expiresAt;
  final String issuer;
  final String subject;
  final String fingerprint;
  final bool trusted;
  final bool? hostnameMatches;
  final List<String> subjectAlternativeNames;
  final String? serialNumber;
  final String? signatureAlgorithm;
  final String? publicKeyAlgorithm;
  final String? publicKeyDetails;
}

class DomainCheckResult {
  const DomainCheckResult({
    required this.expiresAt,
    required this.source,
    required this.registeredDomain,
    this.registeredAt,
    this.updatedAt,
    this.registrar,
    this.publicRegistrant,
    this.nameServers = const <String>[],
  });

  final DateTime? expiresAt;
  final String source;
  final String registeredDomain;
  final DateTime? registeredAt;
  final DateTime? updatedAt;
  final String? registrar;
  final String? publicRegistrant;
  final List<String> nameServers;
}
