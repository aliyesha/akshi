import 'dart:typed_data';

import 'package:akshi/core/services/system_dns_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.akshi.monitor/dns');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decodes multi-segment TXT records', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'records': <Uint8List>[
              Uint8List.fromList(<int>[
                6,
                ...'v=spf1'.codeUnits,
                5,
                ...' -all'.codeUnits,
              ]),
            ],
          },
        );

    expect(await const SystemDnsService().txt('example.com'), <String>[
      'v=spf1 -all',
    ]);
  });

  test('decodes and sorts MX records by preference', () async {
    Uint8List mx(int preference, String exchange) {
      final labels = exchange.split('.');
      return Uint8List.fromList(<int>[
        preference >> 8,
        preference & 0xff,
        for (final label in labels) ...<int>[
          label.length,
          ...label.codeUnits,
        ],
        0,
      ]);
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'records': <Uint8List>[
              mx(20, 'backup.example.com'),
              mx(10, 'mail.example.com'),
            ],
          },
        );

    final records = await const SystemDnsService().mx('example.com');
    expect(records.map((record) => record.preference), <int>[10, 20]);
    expect(records.first.exchange, 'mail.example.com');
  });
}
