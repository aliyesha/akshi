import 'dart:async';

import 'package:akshi/core/crash/crash_log.dart';
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
  });
}
