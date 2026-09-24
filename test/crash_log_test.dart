import 'dart:async';
import 'dart:io';

import 'package:akshi/core/crash/crash_log.dart';
import 'package:akshi/core/crash/crash_log_store.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crash log round-trips its report fields', () {
    final original = CrashLog(
      id: 'log-1',
      occurredAt: DateTime.utc(2026, 5, 4, 12),
      errorType: 'StateError',
      message: 'example failure',
      stackTrace: 'stack',
      context: 'test action',
      platform: 'android',
      platformVersion: 'test',
    );
    final restored = CrashLog.fromMap(<String, Object?>{
      'id': original.id,
      ...original.toMap(),
    });

    expect(restored.id, original.id);
    expect(restored.message, original.message);
    expect(restored.report, contains('test action'));
  });

  test('user-facing errors hide platform and network internals', () {
    expect(
      userFacingError(TimeoutException('ic_launcher')),
      contains('took too long'),
    );
    expect(
      userFacingError(PlatformException(code: 'ic_launcher')),
      contains('device could not complete'),
    );
    expect(
      checkUserFacingError(PlatformException(code: 'ic_launcher')),
      allOf(
        contains('device could not complete'),
        isNot(contains('ic_launcher')),
      ),
    );
  });

  test(
    'serializes concurrent crash-log writes without losing entries',
    () async {
      final root = await Directory.systemTemp.createTemp('akshi-crash-test-');
      addTearDown(() => root.delete(recursive: true));
      final store = CrashLogStore(rootPath: () async => root.path);
      final logs = List<CrashLog>.generate(20, (index) {
        return CrashLog(
          id: 'log-$index',
          occurredAt: DateTime.utc(2026, 6, 10, 12, 0, index),
          errorType: 'StateError',
          message: 'failure $index',
          stackTrace: 'stack',
          context: 'concurrent test',
          platform: 'android',
          platformVersion: 'test',
        );
      });

      await Future.wait(logs.map(store.append));

      final restored = await store.read();
      expect(restored, hasLength(logs.length));
      expect(
        restored.map((entry) => entry.id).toSet(),
        logs.map((entry) => entry.id).toSet(),
      );
    },
  );
}
