/// DNS resource-record types that Akshi requests explicitly.
///
/// The numeric code is the wire value used by Android's `DnsResolver` and
/// Apple's `DNSServiceQueryRecord`; [label] is the human-readable UI label.
enum DnsRecordType {
  a(1, 'A'),
  ns(2, 'NS'),
  cname(5, 'CNAME'),
  mx(15, 'MX'),
  txt(16, 'TXT'),
  aaaa(28, 'AAAA'),
  caa(257, 'CAA');

  const DnsRecordType(this.code, this.label);

  final int code;
  final String label;

  /// Converts a native DNS type code into the domain enum.
  ///
  /// Unknown future types are returned as `null` so a newer platform resolver
  /// cannot make an older app persist a record it does not understand.
  static DnsRecordType? fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// The outcome of one explicit DNS query.
enum DnsQueryState { answered, absent, failed }

/// One DNS record, retaining repeated owner/type values as separate objects.
///
/// [ttlSeconds] is display context and is deliberately not part of semantic
/// change detection. MX records use [preference]; other types leave it null.
class DnsRecord {
  const DnsRecord({
    required this.owner,
    required this.type,
    required this.ttlSeconds,
    required this.value,
    this.preference,
  });

  final String owner;
  final DnsRecordType type;
  final int ttlSeconds;
  final String value;
  final int? preference;

  /// The value shown to people, including MX priority when present.
  String get displayValue => preference == null ? value : '$preference  $value';

  /// Serializes a record for the monitor's local JSON column.
  Map<String, Object?> toJson() => <String, Object?>{
    'owner': owner,
    'type': type.name,
    'ttl_seconds': ttlSeconds,
    'value': value,
    'preference': preference,
  };

  /// Restores a record previously produced by [toJson].
  factory DnsRecord.fromJson(Map<String, Object?> json) => DnsRecord(
    owner: json['owner']! as String,
    type: DnsRecordType.values.byName(json['type']! as String),
    ttlSeconds: json['ttl_seconds']! as int,
    value: json['value']! as String,
    preference: json['preference'] as int?,
  );
}

/// The independent result of querying one owner/type/class RRset.
///
/// Every member in [records] belongs to the same requested `IN` RRset and is
/// replaced as one unit. `absent` is a conclusive negative answer; `failed`
/// preserves why the latest attempt could not verify or replace saved evidence.
class DnsQueryResult {
  const DnsQueryResult({
    required this.name,
    required this.type,
    required this.state,
    this.records = const <DnsRecord>[],
    this.lastAttemptedAt,
    this.lastVerifiedAt,
    this.error,
  });

  final String name;
  final DnsRecordType type;
  final DnsQueryState state;
  final List<DnsRecord> records;

  /// When this owner/type pair was most recently requested.
  final DateTime? lastAttemptedAt;

  /// When [state] and [records] were most recently obtained conclusively.
  ///
  /// A later transport failure advances [lastAttemptedAt] and sets [error],
  /// but deliberately retains this timestamp and the verified observation.
  final DateTime? lastVerifiedAt;

  /// Failure from the latest attempt, while verified evidence is retained.
  final String? error;

  bool get hasCurrentFailure => state == DnsQueryState.failed || error != null;

  DnsQueryResult _withActivity({
    required DateTime attemptedAt,
    required DateTime? verifiedAt,
    required String? latestError,
  }) => DnsQueryResult(
    name: name,
    type: type,
    state: state,
    records: records,
    lastAttemptedAt: attemptedAt,
    lastVerifiedAt: verifiedAt,
    error: latestError,
  );

  /// Serializes the query and every repeated answer for local persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type.name,
    'state': state.name,
    'records': records.map((record) => record.toJson()).toList(growable: false),
    'last_attempted_at': lastAttemptedAt?.toUtc().toIso8601String(),
    'last_verified_at': lastVerifiedAt?.toUtc().toIso8601String(),
    'error': error,
  };

  /// Restores a query result from local JSON.
  factory DnsQueryResult.fromJson(Map<String, Object?> json) => DnsQueryResult(
    name: json['name']! as String,
    type: DnsRecordType.values.byName(json['type']! as String),
    state: DnsQueryState.values.byName(json['state']! as String),
    records: (json['records']! as List<Object?>)
        .whereType<Map>()
        .map((value) => DnsRecord.fromJson(Map<String, Object?>.from(value)))
        .toList(growable: false),
    lastAttemptedAt: _readDate(json['last_attempted_at']),
    lastVerifiedAt: _readDate(json['last_verified_at']),
    error: json['error'] as String?,
  );
}

/// A timestamped collection of DNS query results captured on the device.
class DnsSnapshot {
  const DnsSnapshot({required this.checkedAt, required this.queries});

  final DateTime checkedAt;
  final List<DnsQueryResult> queries;

  /// Returns every record for [name] and [type], preserving response order.
  Iterable<DnsRecord> records(String name, DnsRecordType type) => queries
      .where((query) => query.name == name && query.type == type)
      .expand((query) => query.records);

  /// Finds the result for one owner/type pair, if that query was requested.
  DnsQueryResult? query(String name, DnsRecordType type) {
    for (final query in queries) {
      if (query.name == name && query.type == type) return query;
    }

    return null;
  }

  /// Combines a new resolver attempt with the preceding verified snapshot.
  ///
  /// A complete answer or conclusive absence replaces one whole RRset. A
  /// failed question is not evidence about its records, so it advances only
  /// the attempt and error while retaining that RRset's last complete answer
  /// or absence and verification time. Other RRsets still advance. This is the
  /// single observation policy used by Android and iOS.
  DnsSnapshot reconcileWith(DnsSnapshot? previous) {
    final previousByQuery = <String, DnsQueryResult>{
      for (final query in previous?.queries ?? const <DnsQueryResult>[])
        _queryKey(query.name, query.type): query,
    };
    final reconciled = queries
        .map((latest) {
          if (latest.state != DnsQueryState.failed) {
            return latest._withActivity(
              attemptedAt: checkedAt,
              verifiedAt: checkedAt,
              latestError: null,
            );
          }

          final saved = previousByQuery[_queryKey(latest.name, latest.type)];
          if (saved == null || saved.state == DnsQueryState.failed) {
            return latest._withActivity(
              attemptedAt: checkedAt,
              verifiedAt: null,
              latestError:
                  latest.error ?? 'This DNS lookup could not be completed.',
            );
          }
          return saved._withActivity(
            attemptedAt: checkedAt,
            verifiedAt: saved.lastVerifiedAt ?? previous!.checkedAt,
            latestError:
                latest.error ?? 'This DNS lookup could not be completed.',
          );
        })
        .toList(growable: false);
    return DnsSnapshot(checkedAt: checkedAt, queries: reconciled);
  }

  /// Whether at least one query could not be completed. This is diagnostic
  /// context only and must never participate in monitor health.
  bool get hasFailures => queries.any((query) => query.hasCurrentFailure);

  /// Serializes the full snapshot, including absent and failed queries.
  Map<String, Object?> toJson() => <String, Object?>{
    'checked_at': checkedAt.toUtc().toIso8601String(),
    'queries': queries.map((query) => query.toJson()).toList(growable: false),
  };

  /// Restores a snapshot from local JSON.
  factory DnsSnapshot.fromJson(Map<String, Object?> json) => DnsSnapshot(
    checkedAt: DateTime.parse(json['checked_at']! as String).toLocal(),
    queries: (json['queries']! as List<Object?>)
        .whereType<Map>()
        .map(
          (value) => DnsQueryResult.fromJson(Map<String, Object?>.from(value)),
        )
        .toList(growable: false),
  );
}

DateTime? _readDate(Object? value) => switch (value) {
  final String text => DateTime.tryParse(text)?.toLocal(),
  _ => null,
};

String _queryKey(String name, DnsRecordType type) =>
    '${name.toLowerCase()}|${type.name}';
