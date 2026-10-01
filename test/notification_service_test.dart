import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed initialization can be retried and success remains stable',
    () async {
      final plugin = _FakeNotificationPlugin(failuresRemaining: 1);
      final service = NotificationService(plugin: plugin);
      addTearDown(service.dispose);

      await expectLater(service.initialize(), throwsStateError);
      await service.initialize();
      await service.initialize();

      expect(plugin.initializeCalls, 2);
    },
  );

  test('concurrent initialization callers join one operation', () async {
    final gate = Completer<void>();
    final plugin = _FakeNotificationPlugin(gate: gate);
    final service = NotificationService(plugin: plugin);
    addTearDown(service.dispose);

    final first = service.initialize();
    final second = service.initialize();

    expect(identical(first, second), isTrue);
    expect(plugin.initializeCalls, 1);

    gate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(plugin.initializeCalls, 1);
  });

  test('provider disposal closes navigation and rejects later use', () async {
    final container = ProviderContainer();
    final service = container.read(notificationServiceProvider);
    final streamClosed = expectLater(service.navigationRoutes, emitsDone);

    container.dispose();

    await streamClosed;
    expect(service.initialize, throwsStateError);
  });
}

final class _FakeNotificationPlugin implements FlutterLocalNotificationsPlugin {
  _FakeNotificationPlugin({this.failuresRemaining = 0, this.gate});

  int failuresRemaining;
  final Completer<void>? gate;
  int initializeCalls = 0;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls += 1;
    final currentGate = gate;
    if (currentGate != null) await currentGate.future;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('notification initialization failed');
    }
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
