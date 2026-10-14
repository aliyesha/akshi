import 'package:akshi/core/services/mta_sts_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MTA-STS policy syntax', () {
    test('accepts repeated MX and the maximum permitted age', () {
      final policy = MtaStsPolicy.tryParse('''
version: STSv1
mode: enforce
mx: mail.example.com
mx: *.backup.example.com
max_age: 31557600
extension: retained-by-the-protocol
''');

      expect(policy, isNotNull);
      expect(policy!.mode, 'enforce');
      expect(policy.maxAgeSeconds, MtaStsPolicy.maximumAgeSeconds);
      expect(policy.mxPatterns, <String>[
        'mail.example.com',
        '*.backup.example.com',
      ]);
    });

    test('allows mode none without an MX pattern', () {
      final policy = MtaStsPolicy.tryParse('''
version: STSv1
mode: none
max_age: 0
''');

      expect(policy, isNotNull);
      expect(policy!.mxPatterns, isEmpty);
    });

    test('rejects signed, overlong, and out-of-range maximum ages', () {
      for (final maxAge in <String>['-1', '+1', '00000000000', '31557601']) {
        expect(MtaStsPolicy.tryParse(_policy(maxAge: maxAge)), isNull);
      }
    });

    test('keeps the first non-MX field as required by RFC 8461', () {
      final policy = MtaStsPolicy.tryParse('''
version: STSv1
version: future-extension
mode: testing
mode: enforce
mx: mail.example.com
max_age: 86400
max_age: 31557601
''');

      expect(policy, isNotNull);
      expect(policy!.mode, 'testing');
      expect(policy.maxAgeSeconds, 86400);
    });

    test('rejects missing or malformed MX, wrong version, and bad lines', () {
      expect(MtaStsPolicy.tryParse(_policy(includeMx: false)), isNull);
      expect(
        MtaStsPolicy.tryParse(_policy(mx: '*.bad_domain.example')),
        isNull,
      );
      expect(MtaStsPolicy.tryParse(_policy(mx: '*example.com')), isNull);
      expect(
        MtaStsPolicy.tryParse(_policy().replaceFirst('STSv1', 'stsv1')),
        isNull,
      );
      expect(MtaStsPolicy.tryParse('${_policy()}\nnot-a-field'), isNull);
      expect(
        MtaStsPolicy.tryParse(_policy().replaceFirst('mode:', '\nmode:')),
        isNull,
      );
    });
  });
}

String _policy({
  String maxAge = '86400',
  String mx = 'mail.example.com',
  bool includeMx = true,
}) =>
    '''
version: STSv1
mode: enforce
${includeMx ? 'mx: $mx\n' : ''}max_age: $maxAge
''';
