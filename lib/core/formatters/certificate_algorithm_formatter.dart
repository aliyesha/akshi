String formatSignatureAlgorithm(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return '—';
  }
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
  final oidDescription = switch (normalized) {
    '1.2.840.113549.1.1.2' => 'RSA PKCS#1 with MD2',
    '1.2.840.113549.1.1.4' => 'RSA PKCS#1 with MD5',
    '1.2.840.113549.1.1.5' => 'RSA PKCS#1 with SHA-1',
    '1.2.840.113549.1.1.10' => 'RSA-PSS',
    '1.2.840.113549.1.1.11' => 'RSA PKCS#1 with SHA-256',
    '1.2.840.113549.1.1.12' => 'RSA PKCS#1 with SHA-384',
    '1.2.840.113549.1.1.13' => 'RSA PKCS#1 with SHA-512',
    '1.2.840.113549.1.1.14' => 'RSA PKCS#1 with SHA-224',
    '1.2.840.113549.1.1.15' => 'RSA PKCS#1 with SHA-512/224',
    '1.2.840.113549.1.1.16' => 'RSA PKCS#1 with SHA-512/256',
    '1.2.840.10040.4.3' => 'DSA with SHA-1',
    '2.16.840.1.101.3.4.3.1' => 'DSA with SHA-224',
    '2.16.840.1.101.3.4.3.2' => 'DSA with SHA-256',
    '2.16.840.1.101.3.4.3.3' => 'DSA with SHA-384',
    '2.16.840.1.101.3.4.3.4' => 'DSA with SHA-512',
    '2.16.840.1.101.3.4.3.5' => 'DSA with SHA3-224',
    '2.16.840.1.101.3.4.3.6' => 'DSA with SHA3-256',
    '2.16.840.1.101.3.4.3.7' => 'DSA with SHA3-384',
    '2.16.840.1.101.3.4.3.8' => 'DSA with SHA3-512',
    '2.16.840.1.101.3.4.3.9' => 'ECDSA with SHA3-224',
    '2.16.840.1.101.3.4.3.10' => 'ECDSA with SHA3-256',
    '2.16.840.1.101.3.4.3.11' => 'ECDSA with SHA3-384',
    '2.16.840.1.101.3.4.3.12' => 'ECDSA with SHA3-512',
    '2.16.840.1.101.3.4.3.13' => 'RSA PKCS#1 with SHA3-224',
    '2.16.840.1.101.3.4.3.14' => 'RSA PKCS#1 with SHA3-256',
    '2.16.840.1.101.3.4.3.15' => 'RSA PKCS#1 with SHA3-384',
    '2.16.840.1.101.3.4.3.16' => 'RSA PKCS#1 with SHA3-512',
    '1.2.840.10045.4.1' => 'ECDSA with SHA-1',
    '1.2.840.10045.4.3.1' => 'ECDSA with SHA-224',
    '1.2.840.10045.4.3.2' => 'ECDSA with SHA-256',
    '1.2.840.10045.4.3.3' => 'ECDSA with SHA-384',
    '1.2.840.10045.4.3.4' => 'ECDSA with SHA-512',
    '1.3.6.1.5.5.7.6.30' => 'RSA-PSS with SHAKE128',
    '1.3.6.1.5.5.7.6.31' => 'RSA-PSS with SHAKE256',
    '1.3.6.1.5.5.7.6.32' => 'ECDSA with SHAKE128',
    '1.3.6.1.5.5.7.6.33' => 'ECDSA with SHAKE256',
    '1.3.101.112' => 'Ed25519',
    '1.3.101.113' => 'Ed448',
    '1.2.156.10197.1.501' => 'SM2 with SM3',
    '1.2.643.2.2.3' => 'GOST R 34.10-2001 with GOST R 34.11-94',
    '1.2.643.7.1.1.3.2' => 'GOST R 34.10-2012 (256-bit)',
    '1.2.643.7.1.1.3.3' => 'GOST R 34.10-2012 (512-bit)',
    _ => _nistPostQuantumAlgorithm(normalized),
  };
  if (oidDescription != null) {
    return _described(raw, oidDescription);
  }

  final digest = _digestName(normalized);

  if (normalized.contains('pss') ||
      normalized.contains('rsassapss') ||
      normalized.contains('mgf1')) {
    return _described(raw, digest == null ? 'RSA-PSS' : 'RSA-PSS with $digest');
  }
  if (normalized.contains('ecdsa') && digest != null) {
    return _described(raw, 'ECDSA with $digest');
  }
  if (normalized.contains('rsa') && digest != null) {
    return _described(raw, 'RSA PKCS#1 with $digest');
  }
  if (normalized.contains('dsa') && digest != null) {
    return _described(raw, 'DSA with $digest');
  }
  return raw;
}

String formatPublicKeyAlgorithm(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return '—';
  }
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
  final description = switch (normalized) {
    '1.2.840.113549.1.1.1' => 'RSA',
    'rsaencryption' => 'RSA',
    'rsa' => 'RSA',
    '1.2.840.113549.1.1.7' => 'RSA-OAEP',
    'rsaesoaep' => 'RSA-OAEP',
    '1.2.840.113549.1.1.10' => 'RSA-PSS',
    'rsassapss' => 'RSA-PSS',
    '1.2.840.10045.2.1' => 'Elliptic Curve',
    'idecpublickey' => 'Elliptic Curve',
    'ecpublickey' => 'Elliptic Curve',
    'ec' => 'Elliptic Curve',
    '1.2.840.10040.4.1' => 'DSA',
    'iddsa' => 'DSA',
    'dsa' => 'DSA',
    '1.2.840.113549.1.3.1' => 'Diffie-Hellman',
    '1.2.840.10046.2.1' => 'Diffie-Hellman',
    'dhkeyagreement' => 'Diffie-Hellman',
    'dhpublicnumber' => 'Diffie-Hellman',
    '1.3.101.110' => 'X25519',
    'x25519' => 'X25519',
    '1.3.101.111' => 'X448',
    'x448' => 'X448',
    '1.3.101.112' => 'Ed25519',
    'ed25519' => 'Ed25519',
    '1.3.101.113' => 'Ed448',
    'ed448' => 'Ed448',
    '1.2.156.10197.1.301' => 'SM2',
    'sm2' => 'SM2',
    '1.2.643.2.2.19' => 'GOST R 34.10-2001',
    '1.2.643.7.1.1.1.1' => 'GOST R 34.10-2012 (256-bit)',
    '1.2.643.7.1.1.1.2' => 'GOST R 34.10-2012 (512-bit)',
    '2.16.840.1.101.3.4.4.1' => 'ML-KEM-512',
    '2.16.840.1.101.3.4.4.2' => 'ML-KEM-768',
    '2.16.840.1.101.3.4.4.3' => 'ML-KEM-1024',
    _ => _nistPostQuantumAlgorithm(normalized),
  };
  return description == null ? raw : _described(raw, description);
}

String? _nistPostQuantumAlgorithm(String oid) => switch (oid) {
  '2.16.840.1.101.3.4.3.17' => 'ML-DSA-44',
  '2.16.840.1.101.3.4.3.18' => 'ML-DSA-65',
  '2.16.840.1.101.3.4.3.19' => 'ML-DSA-87',
  '2.16.840.1.101.3.4.3.20' => 'SLH-DSA-SHA2-128s',
  '2.16.840.1.101.3.4.3.21' => 'SLH-DSA-SHA2-128f',
  '2.16.840.1.101.3.4.3.22' => 'SLH-DSA-SHA2-192s',
  '2.16.840.1.101.3.4.3.23' => 'SLH-DSA-SHA2-192f',
  '2.16.840.1.101.3.4.3.24' => 'SLH-DSA-SHA2-256s',
  '2.16.840.1.101.3.4.3.25' => 'SLH-DSA-SHA2-256f',
  '2.16.840.1.101.3.4.3.26' => 'SLH-DSA-SHAKE-128s',
  '2.16.840.1.101.3.4.3.27' => 'SLH-DSA-SHAKE-128f',
  '2.16.840.1.101.3.4.3.28' => 'SLH-DSA-SHAKE-192s',
  '2.16.840.1.101.3.4.3.29' => 'SLH-DSA-SHAKE-192f',
  '2.16.840.1.101.3.4.3.30' => 'SLH-DSA-SHAKE-256s',
  '2.16.840.1.101.3.4.3.31' => 'SLH-DSA-SHAKE-256f',
  '2.16.840.1.101.3.4.3.32' => 'HashML-DSA-44 with SHA-512',
  '2.16.840.1.101.3.4.3.33' => 'HashML-DSA-65 with SHA-512',
  '2.16.840.1.101.3.4.3.34' => 'HashML-DSA-87 with SHA-512',
  '2.16.840.1.101.3.4.3.35' => 'HashSLH-DSA-SHA2-128s with SHA-256',
  '2.16.840.1.101.3.4.3.36' => 'HashSLH-DSA-SHA2-128f with SHA-256',
  '2.16.840.1.101.3.4.3.37' => 'HashSLH-DSA-SHA2-192s with SHA-512',
  '2.16.840.1.101.3.4.3.38' => 'HashSLH-DSA-SHA2-192f with SHA-512',
  '2.16.840.1.101.3.4.3.39' => 'HashSLH-DSA-SHA2-256s with SHA-512',
  '2.16.840.1.101.3.4.3.40' => 'HashSLH-DSA-SHA2-256f with SHA-512',
  '2.16.840.1.101.3.4.3.41' => 'HashSLH-DSA-SHAKE-128s with SHAKE128',
  '2.16.840.1.101.3.4.3.42' => 'HashSLH-DSA-SHAKE-128f with SHAKE128',
  '2.16.840.1.101.3.4.3.43' => 'HashSLH-DSA-SHAKE-192s with SHAKE256',
  '2.16.840.1.101.3.4.3.44' => 'HashSLH-DSA-SHAKE-192f with SHAKE256',
  '2.16.840.1.101.3.4.3.45' => 'HashSLH-DSA-SHAKE-256s with SHAKE256',
  '2.16.840.1.101.3.4.3.46' => 'HashSLH-DSA-SHAKE-256f with SHAKE256',
  _ => null,
};

String? _digestName(String normalized) {
  final sha3Bits = RegExp(r'sha3(224|256|384|512)')
      .firstMatch(normalized)
      ?.group(1);
  if (sha3Bits != null) {
    return 'SHA3-$sha3Bits';
  }
  if (normalized.contains('sha512224')) {
    return 'SHA-512/224';
  }
  if (normalized.contains('sha512256')) {
    return 'SHA-512/256';
  }
  final shaBits = RegExp(r'sha(1|224|256|384|512)')
      .firstMatch(normalized)
      ?.group(1);
  if (shaBits != null) {
    return 'SHA-$shaBits';
  }
  if (normalized.contains('sm3')) {
    return 'SM3';
  }
  if (normalized.contains('md5')) {
    return 'MD5';
  }
  if (normalized.contains('md2')) {
    return 'MD2';
  }
  return null;
}

String _described(String raw, String description) =>
    raw.toLowerCase() == description.toLowerCase()
    ? raw
    : '$raw ($description)';
