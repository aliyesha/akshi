import 'dart:async';
import 'dart:ui';

import 'package:akshi/app/akshi_app.dart';
import 'package:akshi/core/crash/crash_log_service.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  appLogger.configure();
  appLogger.info('app.start');
  final crashLogs = CrashLogService();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLogger.error(
      'app.flutter_error',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    unawaited(
      crashLogs.record(
        details.exception,
        details.stack ?? StackTrace.current,
        context: 'Flutter framework error',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLogger.error('app.platform_error', error, stack);
    unawaited(
      crashLogs.record(error, stack, context: 'Uncaught platform error'),
    );
    return false;
  };
  runApp(const ProviderScope(child: AkshiApp()));
}
