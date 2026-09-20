import 'package:akshi/core/formatters/certificate_name_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('certificate subject', () {
    test('extracts the common name from slash-separated iOS output', () {
      expect(
        formatCertificateSubject('/CN=www.example.com'),
        'www.example.com',
      );
    });

    test('prefers the common name in comma-separated output', () {
      expect(
        formatCertificateSubject(
          'C=US, O=Example Incorporated, CN=api.example.com',
        ),
        'api.example.com',
      );
    });
  });

  group('certificate issuer', () {
    test('humanizes slash-separated distinguished names', () {
      expect(
        formatCertificateIssuer('/C=US/O=Let’s Encrypt/CN=YE1'),
        'Let’s Encrypt · YE1 · US',
      );
    });

    test('preserves useful organization values', () {
      expect(
        formatCertificateIssuer('O=Example, Inc.,CN=Root CA,C=US'),
        'Example, Inc. · Root CA · US',
      );
    });

    test('leaves an already friendly name unchanged', () {
      expect(
        formatCertificateIssuer('Local development CA'),
        'Local development CA',
      );
    });
  });
}
