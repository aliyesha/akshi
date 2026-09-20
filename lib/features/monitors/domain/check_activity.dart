enum CheckFailureKind {
  offline,
  internetUnavailable,
  timeout,
  dns,
  sourceUnavailable,
  invalidResponse,
  tls;

  String get storageValue => name;

  String get label => switch (this) {
    CheckFailureKind.offline => 'Device is offline',
    CheckFailureKind.internetUnavailable =>
      'Internet access appears unavailable',
    CheckFailureKind.timeout => 'The check timed out',
    CheckFailureKind.dns => 'DNS lookup unavailable',
    CheckFailureKind.sourceUnavailable => 'Information source unavailable',
    CheckFailureKind.invalidResponse => 'The source returned invalid data',
    CheckFailureKind.tls => 'TLS connection failed',
  };

  static CheckFailureKind fromStorage(String value) => values.firstWhere(
    (candidate) => candidate.storageValue == value,
    orElse: () => CheckFailureKind.sourceUnavailable,
  );
}

class CheckFailure {
  const CheckFailure({
    required this.kind,
    required this.message,
    required this.occurredAt,
  });

  final CheckFailureKind kind;
  final String message;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.storageValue,
    'message': message,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };

  factory CheckFailure.fromJson(Map<String, Object?> json) => CheckFailure(
    kind: CheckFailureKind.fromStorage(json['kind']! as String),
    message: json['message']! as String,
    occurredAt: DateTime.parse(json['occurred_at']! as String).toLocal(),
  );
}

class CheckActivity {
  const CheckActivity({
    this.lastAttemptedAt,
    this.lastSucceededAt,
    this.failure,
  });

  final DateTime? lastAttemptedAt;
  final DateTime? lastSucceededAt;
  final CheckFailure? failure;

  bool get hasCurrentFailure => failure != null;
  bool get hasSavedResult => lastSucceededAt != null;

  CheckActivity succeeded(DateTime at) => CheckActivity(
    lastAttemptedAt: at,
    lastSucceededAt: at,
  );

  CheckActivity failed(CheckFailure value) => CheckActivity(
    lastAttemptedAt: value.occurredAt,
    lastSucceededAt: lastSucceededAt,
    failure: value,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'last_attempted_at': lastAttemptedAt?.toUtc().toIso8601String(),
    'last_succeeded_at': lastSucceededAt?.toUtc().toIso8601String(),
    'failure': failure?.toJson(),
  };

  factory CheckActivity.fromJson(Map<String, Object?>? json) {
    if (json == null) return const CheckActivity();
    DateTime? readDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.tryParse(value)?.toLocal();
    }

    final failure = json['failure'];
    return CheckActivity(
      lastAttemptedAt: readDate('last_attempted_at'),
      lastSucceededAt: readDate('last_succeeded_at'),
      failure: failure is Map
          ? CheckFailure.fromJson(Map<String, Object?>.from(failure))
          : null,
    );
  }
}

DateTime? latestCheckTime(Iterable<CheckActivity> activities) {
  DateTime? latest;
  for (final activity in activities) {
    final candidate = activity.lastAttemptedAt;
    if (candidate != null && (latest == null || candidate.isAfter(latest))) {
      latest = candidate;
    }
  }
  return latest;
}
