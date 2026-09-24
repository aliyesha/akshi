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
  });

  final String id;
  final String title;
  final MailFindingState state;
  final String summary;
  final List<MailFact> facts;

  bool get needsAttention =>
      state == MailFindingState.warning ||
      state == MailFindingState.invalid ||
      state == MailFindingState.unavailable;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'state': state.storageValue,
    'summary': summary,
    'facts': facts.map((fact) => fact.toJson()).toList(growable: false),
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
  );
}

class EmailPosture {
  const EmailPosture({required this.checkedAt, required this.findings});

  final DateTime checkedAt;
  final List<MailFinding> findings;

  bool get needsAttention => findings.any((finding) => finding.needsAttention);

  /// Whether at least one requested DNS-backed Email check could not run.
  bool get hasUnavailable =>
      findings.any((finding) => finding.state == MailFindingState.unavailable);

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
