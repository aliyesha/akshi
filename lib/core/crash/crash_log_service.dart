import 'dart:io';

import 'package:akshi/core/crash/crash_log.dart';
import 'package:akshi/core/crash/crash_log_store.dart';

/// Captures uncaught errors without network access or database dependency.
class CrashLogService {
  CrashLogService({CrashLogStore? store}) : _store = store ?? CrashLogStore();

  final CrashLogStore _store;

  /// Records an error best-effort; this method never throws to its caller.
  Future<void> record(
    Object error,
    StackTrace stackTrace, {
    required String context,
  }) async {
    try {
      await _store.append(
        CrashLog(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          occurredAt: DateTime.now(),
          errorType: error.runtimeType.toString(),
          message: error.toString(),
          stackTrace: stackTrace.toString(),
          context: context,
          platform: Platform.operatingSystem,
          platformVersion: Platform.operatingSystemVersion,
        ),
      );
    } catch (_) {
      // Diagnostics must not become another uncaught error.
    }
  }
}
