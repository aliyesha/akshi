import 'package:akshi/core/services/system_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aliyesha.akshi/system_settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('opens this app notification settings through the platform channel', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    expect(await SystemSettingsService.openNotificationSettings(), isTrue);
    expect(received?.method, 'openNotificationSettings');
    expect(received?.arguments, isNull);
  });

  test('reports when platform settings cannot be opened', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);

    expect(await SystemSettingsService.openNotificationSettings(), isFalse);
  });

  test('reads the current notification permission status', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'notificationPermissionStatus');
      return 'allowed';
    });

    expect(
      await SystemSettingsService.notificationPermissionStatus(),
      NotificationPermissionStatus.allowed,
    );
  });

  test('unknown permission values are unavailable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'unexpected');

    expect(
      await SystemSettingsService.notificationPermissionStatus(),
      NotificationPermissionStatus.unavailable,
    );
  });
}
