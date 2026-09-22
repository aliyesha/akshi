import 'dart:developer' as developer;

import 'package:logging/logging.dart';

/// One process-wide logger for diagnostic output.
///
/// Logging is deliberately console-only. It is not a telemetry channel and it
/// never records service responses or arbitrary user-entered text. Callers
/// should pass only public workflow metadata such as a normalized hostname,
/// port, enabled check flags, and an operation name.
final appLogger = AppLogger._();

class AppLogger {
  AppLogger._();

  final Logger _logger = Logger('akshi');
  var _configured = false;
  var _sequence = 0;

  /// Configures the official Dart logging stream once during app startup.
  void configure() {
    if (_configured) {
      return;
    }
    _configured = true;
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      developer.log(
        record.message,
        name: record.loggerName,
        time: record.time,
        level: record.level.value,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    });
  }

  /// Starts a traceable workflow. The returned flow carries its ID to errors.
  AppLogFlow start(
    String operation, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final id =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${++_sequence}';
    final flow = AppLogFlow._(this, id, operation);
    flow.info('started', data: data);
    return flow;
  }

  void info(
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _logger.info(_format(event, data));
  }

  void error(
    String event,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final errorType = _safeErrorType(error);
    _logger.severe(
      _format(event, <String, Object?>{...data, 'errorType': errorType}),
      _SafeLogError(errorType),
      stackTrace,
    );
  }

  String _format(String event, Map<String, Object?> data) {
    final fields = <String, Object?>{'event': event, ...data};
    return fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${_safeValue(entry.value)}')
        .join(' ');
  }
}

/// A named workflow context used to correlate start, progress, and failures.
class AppLogFlow {
  AppLogFlow._(this._owner, this.id, this.operation);

  final AppLogger _owner;
  final String id;
  final String operation;

  void info(
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _owner.info(
      event,
      data: <String, Object?>{'flow': id, 'operation': operation, ...data},
    );
  }

  void error(
    String event,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _owner.error(
      event,
      error,
      stackTrace,
      data: <String, Object?>{'flow': id, 'operation': operation, ...data},
    );
  }
}

String _safeErrorType(Object error) => error.runtimeType.toString();

String _safeValue(Object? value) {
  final text = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (text.length <= 160) {
    return text;
  }
  return '${text.substring(0, 157)}…';
}

class _SafeLogError implements Exception {
  const _SafeLogError(this.type);

  final String type;

  @override
  String toString() => type;
}
