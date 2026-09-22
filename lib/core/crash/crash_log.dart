/// One locally captured uncaught error.
class CrashLog {
  const CrashLog({
    required this.id,
    required this.occurredAt,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    required this.context,
    required this.platform,
    required this.platformVersion,
  });

  final String id;
  final DateTime occurredAt;
  final String errorType;
  final String message;
  final String stackTrace;
  final String context;
  final String platform;
  final String platformVersion;

  Map<String, Object?> toMap() => <String, Object?>{
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'error_type': errorType,
    'message': message,
    'stack_trace': stackTrace,
    'context': context,
    'platform': platform,
    'platform_version': platformVersion,
  };

  factory CrashLog.fromMap(Map<String, Object?> map) => CrashLog(
    id: map['id']! as String,
    occurredAt: DateTime.parse(map['occurred_at']! as String).toLocal(),
    errorType: map['error_type']! as String,
    message: map['message']! as String,
    stackTrace: map['stack_trace']! as String,
    context: map['context']! as String,
    platform: map['platform']! as String,
    platformVersion: map['platform_version']! as String,
  );

  String get report =>
      '''Akshi crash log
When: $occurredAt
Type: $errorType
Message: $message
Context: $context
Platform: $platform $platformVersion

$stackTrace''';
}
