import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeHostname', () {
    test('accepts a plain hostname', () {
      expect(normalizeHostname('Example.COM'), 'example.com');
    });

    test('extracts the host from a URL', () {
      expect(
        normalizeHostname('https://status.example.com/health?full=true'),
        'status.example.com',
      );
    });

    test('removes a trailing root dot', () {
      expect(normalizeHostname('example.com.'), 'example.com');
    });
  });

  group('validateHostname', () {
    test('rejects empty and malformed hostnames', () {
      expect(validateHostname(''), isNotNull);
      expect(validateHostname('-example.com'), isNotNull);
      expect(validateHostname('bad domain.com'), isNotNull);
    });

    test('accepts localhost and subdomains', () {
      expect(validateHostname('localhost'), isNull);
      expect(validateHostname('api.staging.example.com'), isNull);
    });
  });
}
