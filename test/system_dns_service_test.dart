import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.aliyesha.akshi/dns');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('preserves repeated and multi-segment TXT values', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'records': <Object?>[
              _nativeRecord(
                type: DnsRecordType.txt,
                ttl: 300,
                data: <int>[6, ...'v=spf1'.codeUnits, 5, ...' -all'.codeUnits],
              ),
              _nativeRecord(
                type: DnsRecordType.txt,
                ttl: 600,
                data: <int>[6, ...'verify'.codeUnits, 4, ...'=abc'.codeUnits],
              ),
            ],
          },
        );

    final result = await const SystemDnsService().query(
      'example.com',
      DnsRecordType.txt,
    );
    expect(result.state, DnsQueryState.answered);
    expect(result.records.map((record) => record.value), <String>[
      'v=spf1 -all',
      'verify=abc',
    ]);
    expect(result.records.map((record) => record.ttlSeconds), <int>[300, 600]);
  });

  test('decodes and sorts MX records by preference', () async {
    Uint8List mx(int preference, String exchange) {
      final labels = exchange.split('.');
      return Uint8List.fromList(<int>[
        preference >> 8,
        preference & 0xff,
        for (final label in labels) ...<int>[label.length, ...label.codeUnits],
        0,
      ]);
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'records': <Object?>[
              _nativeRecord(
                type: DnsRecordType.mx,
                ttl: 3600,
                data: mx(20, 'backup.example.com'),
              ),
              _nativeRecord(
                type: DnsRecordType.mx,
                ttl: 3600,
                data: mx(10, 'mail.example.com'),
              ),
            ],
          },
        );

    final result = await const SystemDnsService().query(
      'example.com',
      DnsRecordType.mx,
    );
    expect(result.records.map((record) => record.preference), <int>[10, 20]);
    expect(result.records.first.value, 'mail.example.com');
  });
}

Map<String, Object?> _nativeRecord({
  required DnsRecordType type,
  required int ttl,
  required List<int> data,
}) => <String, Object?>{
  'owner': 'example.com.',
  'type': type.code,
  'ttl': ttl,
  'data': Uint8List.fromList(data),
};
