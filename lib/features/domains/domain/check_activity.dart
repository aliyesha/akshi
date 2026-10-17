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

extension CheckFailureMeaning on CheckFailure? {
  bool get isConnectivityInterruption => switch (this?.kind) {
    CheckFailureKind.offline || CheckFailureKind.internetUnavailable => true,
    _ => false,
  };
}

class CheckActivity {
  const CheckActivity({
    this.lastAttemptedAt,
    this.lastVerifiedAt,
    this.failure,
  });

  final DateTime? lastAttemptedAt;
  final DateTime? lastVerifiedAt;
  final CheckFailure? failure;

  bool get hasCurrentFailure => failure != null;
  bool get hasVerifiedResult => lastVerifiedAt != null;

  CheckActivity verified(DateTime at) =>
      CheckActivity(lastAttemptedAt: at, lastVerifiedAt: at);

  /// Records an inconclusive attempt without inventing a verified result.
  /// Component-level evidence retains the reason it was inconclusive.
  CheckActivity attempted(DateTime at) =>
      CheckActivity(lastAttemptedAt: at, lastVerifiedAt: lastVerifiedAt);

  CheckActivity failed(CheckFailure value) => CheckActivity(
    lastAttemptedAt: value.occurredAt,
    lastVerifiedAt: lastVerifiedAt,
    failure: value,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'last_attempted_at': lastAttemptedAt?.toUtc().toIso8601String(),
    'last_verified_at': lastVerifiedAt?.toUtc().toIso8601String(),
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
      lastVerifiedAt: readDate('last_verified_at'),
      failure: failure is Map
          ? CheckFailure.fromJson(Map<String, Object?>.from(failure))
          : null,
    );
  }
}
