import 'package:akshi/core/formatters/certificate_algorithm_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explains ECDSA signature names without hiding the source value', () {
    expect(
      formatSignatureAlgorithm('ecdsaWithSha384'),
      'ecdsaWithSha384 (ECDSA with SHA-384)',
    );
  });

  test('explains common RSA signature names', () {
    expect(
      formatSignatureAlgorithm('sha256WithRSAEncryption'),
      'sha256WithRSAEncryption (RSA PKCS#1 with SHA-256)',
    );
  });

  test('explains RSA-PSS names and digest when it is available', () {
    expect(
      formatSignatureAlgorithm('SHA512withRSAandMGF1'),
      'SHA512withRSAandMGF1 (RSA-PSS with SHA-512)',
    );
    expect(
      formatSignatureAlgorithm('1.2.840.113549.1.1.10'),
      '1.2.840.113549.1.1.10 (RSA-PSS)',
    );
  });

  test('explains DSA and legacy RSA signature identifiers', () {
    expect(
      formatSignatureAlgorithm('2.16.840.1.101.3.4.3.2'),
      '2.16.840.1.101.3.4.3.2 (DSA with SHA-256)',
    );
    expect(
      formatSignatureAlgorithm('1.2.840.113549.1.1.5'),
      '1.2.840.113549.1.1.5 (RSA PKCS#1 with SHA-1)',
    );
  });

  test('handles SHA-3 without confusing its bit length', () {
    expect(
      formatSignatureAlgorithm('ecdsa_with_SHA3-384'),
      'ecdsa_with_SHA3-384 (ECDSA with SHA3-384)',
    );
  });

  test('explains public-key algorithm identifiers', () {
    expect(
      formatPublicKeyAlgorithm('id-ecPublicKey'),
      'id-ecPublicKey (Elliptic Curve)',
    );
  });

  test('explains modern and classic public-key families', () {
    expect(formatPublicKeyAlgorithm('1.3.101.110'), '1.3.101.110 (X25519)');
    expect(
      formatPublicKeyAlgorithm('1.2.840.113549.1.3.1'),
      '1.2.840.113549.1.3.1 (Diffie-Hellman)',
    );
    expect(formatPublicKeyAlgorithm('DSA'), 'DSA');
  });

  test('explains SHAKE and post-quantum certificate identifiers', () {
    expect(
      formatSignatureAlgorithm('1.3.6.1.5.5.7.6.30'),
      '1.3.6.1.5.5.7.6.30 (RSA-PSS with SHAKE128)',
    );
    expect(
      formatSignatureAlgorithm('2.16.840.1.101.3.4.3.18'),
      '2.16.840.1.101.3.4.3.18 (ML-DSA-65)',
    );
    expect(
      formatPublicKeyAlgorithm('2.16.840.1.101.3.4.4.2'),
      '2.16.840.1.101.3.4.4.2 (ML-KEM-768)',
    );
  });

  test('preserves unknown algorithms', () {
    expect(formatSignatureAlgorithm('futureAlgorithm'), 'futureAlgorithm');
  });
}
