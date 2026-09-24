import 'package:akshi/core/services/external_link_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aliyesha.akshi/external_links');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('opens validated HTTPS links through the native channel', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });

    await ExternalLinkService.openHttps(Uri.parse('https://aliyesha.com'));

    expect(received?.method, 'open');
    expect(received?.arguments, <String, Object?>{
      'url': 'https://aliyesha.com',
    });
  });

  test('rejects non-HTTPS links before invoking the platform', () async {
    await expectLater(
      ExternalLinkService.openHttps(Uri.parse('http://aliyesha.com')),
      throwsArgumentError,
    );
  });

  test('reports when no native application can open the link', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);

    await expectLater(
      ExternalLinkService.openHttps(Uri.parse('https://aliyesha.com')),
      throwsStateError,
    );
  });
}
