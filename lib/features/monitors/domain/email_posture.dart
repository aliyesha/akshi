enum MailFindingState {
  healthy,
  informational,
  warning,
  invalid,
  unavailable;

  String get storageValue => name;

  static MailFindingState fromStorage(String value) => values.firstWhere(
    (candidate) => candidate.storageValue == value,
    orElse: () => MailFindingState.unavailable,
  );
}

class MailFact {
  const MailFact({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'value': value,
  };

  factory MailFact.fromJson(Map<String, Object?> json) => MailFact(
    label: json['label']! as String,
    value: json['value']! as String,
  );
}

class MailFinding {
  const MailFinding({
    required this.id,
    required this.title,
    required this.state,
    required this.summary,
    this.facts = const <MailFact>[],
    this.observedAt,
    this.latestError,
  });

  final String id;
  final String title;
  final MailFindingState state;
  final String summary;
  final List<MailFact> facts;

  /// Time of the conclusive observation currently displayed.
  final DateTime? observedAt;

  /// Failure from the latest attempt when [summary] and [facts] are saved data.
  final String? latestError;

  /// Whether observed data demonstrates a configuration problem.
  ///
  /// An unavailable observation is tracked separately because it proves neither
  /// health nor harm.
  bool get needsAttention =>
      state == MailFindingState.warning || state == MailFindingState.invalid;

  bool get isUnavailable =>
      state == MailFindingState.unavailable || latestError != null;

  MailFinding copyWith({DateTime? observedAt, Object? latestError = _unset}) =>
      MailFinding(
        id: id,
        title: title,
        state: state,
        summary: summary,
        facts: facts,
        observedAt: observedAt ?? this.observedAt,
        latestError: identical(latestError, _unset)
            ? this.latestError
            : latestError as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'state': state.storageValue,
    'summary': summary,
    'facts': facts.map((fact) => fact.toJson()).toList(growable: false),
    'observed_at': observedAt?.toUtc().toIso8601String(),
    'latest_error': latestError,
  };

  factory MailFinding.fromJson(Map<String, Object?> json) => MailFinding(
    id: json['id']! as String,
    title: json['title']! as String,
    state: MailFindingState.fromStorage(json['state']! as String),
    summary: json['summary']! as String,
    facts: ((json['facts'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((fact) => MailFact.fromJson(Map<String, Object?>.from(fact)))
        .toList(growable: false),
    observedAt: _readDate(json['observed_at']),
    latestError: json['latest_error'] as String?,
  );
}

class EmailPosture {
  const EmailPosture({required this.checkedAt, required this.findings});

  final DateTime checkedAt;
  final List<MailFinding> findings;

  bool get needsAttention => findings.any((finding) => finding.needsAttention);

  /// Whether at least one requested Email check could not be completed.
  bool get hasUnavailable => findings.any((finding) => finding.isUnavailable);

  /// Retains each prior conclusive finding when only its latest dependency
  /// was unavailable. Other findings from the same attempt still advance.
  EmailPosture reconcileWith(EmailPosture? previous) {
    final previousById = <String, MailFinding>{
      for (final finding in previous?.findings ?? const <MailFinding>[])
        finding.id: finding,
    };
    final reconciled = findings
        .map((latest) {
          if (latest.state != MailFindingState.unavailable) {
            return latest.copyWith(observedAt: checkedAt, latestError: null);
          }
          final saved = previousById[latest.id];
          if (saved == null || saved.state == MailFindingState.unavailable) {
            return latest.copyWith(latestError: latest.summary);
          }
          return saved.copyWith(
            observedAt: saved.observedAt ?? previous!.checkedAt,
            latestError: latest.summary,
          );
        })
        .toList(growable: false);
    return EmailPosture(checkedAt: checkedAt, findings: reconciled);
  }

  String get changeSignature => findings
      .map(
        (finding) => <String>[
          finding.id,
          finding.state.storageValue,
          finding.summary,
          ...finding.facts.map((fact) => '${fact.label}:${fact.value}'),
        ].join('|'),
      )
      .join('||');

  Map<String, Object?> toJson() => <String, Object?>{
    'checked_at': checkedAt.toUtc().toIso8601String(),
    'findings': findings
        .map((finding) => finding.toJson())
        .toList(growable: false),
  };

  factory EmailPosture.fromJson(Map<String, Object?> json) => EmailPosture(
    checkedAt: DateTime.parse(json['checked_at']! as String).toLocal(),
    findings: ((json['findings'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (finding) => MailFinding.fromJson(Map<String, Object?>.from(finding)),
        )
        .toList(growable: false),
  );
}

const _unset = Object();

DateTime? _readDate(Object? value) => switch (value) {
  final String text => DateTime.tryParse(text)?.toLocal(),
  _ => null,
};
