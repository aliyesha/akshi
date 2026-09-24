import 'dart:io';

import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/tls_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TLS port validation', () {
    test('accepts every in-range port without service assumptions', () {
      expect(validateTlsPort('1'), isNull);
      expect(validateTlsPort('22'), isNull);
      expect(validateTlsPort('80'), isNull);
      expect(validateTlsPort('443'), isNull);
      expect(validateTlsPort('65535'), isNull);
      expect(requireValidTlsPort(80), 80);
    });

    test('rejects malformed and out-of-range ports', () {
      for (final value in <String>['', 'https', '0', '65536', '-1']) {
        expect(validateTlsPort(value), isNotNull, reason: value);
      }
      expect(() => requireValidTlsPort(0), throwsRangeError);
      expect(() => requireValidTlsPort(65536), throwsRangeError);
    });
  });

  group('TLS endpoint failure reporting', () {
    final classifier = CheckFailureClassifier(
      offlineCheck: () async => false,
    );
    final occurredAt = DateTime.utc(2026, 9, 23);

    test('explains when a service does not speak direct TLS', () async {
      final failure = await classifier.classify(
        HandshakeException('unexpected protocol bytes'),
        occurredAt: occurredAt,
        source: 'TLS endpoint example.com:22',
        tls: true,
      );

      expect(failure.kind, CheckFailureKind.tls);
      expect(failure.message, contains('did not complete a TLS handshake'));
      expect(failure.message, contains('example.com:22'));
      expect(failure.message, isNot(contains('unexpected protocol bytes')));
    });

    test(
      'distinguishes a closed port from a protocol handshake failure',
      () async {
        final failure = await classifier.classify(
          SocketException('Connection refused'),
          occurredAt: occurredAt,
          source: 'TLS endpoint example.com:444',
          tls: true,
        );

        expect(failure.kind, CheckFailureKind.tls);
        expect(failure.message, contains('port may be closed'));
      },
    );

    test('keeps hostname lookup failures classified as DNS', () async {
      final failure = await classifier.classify(
        SocketException('Failed host lookup'),
        occurredAt: occurredAt,
        source: 'TLS endpoint missing.example:443',
        tls: true,
      );

      expect(failure.kind, CheckFailureKind.dns);
      expect(failure.message, contains('could not be resolved through DNS'));
    });
  });
}
