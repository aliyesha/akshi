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

/// The independent result of querying one owner/type pair.
///
/// `absent` means the resolver answered successfully with no records. It is
/// different from `failed`, which preserves the reason a lookup was unavailable.
class DnsQueryResult {
  const DnsQueryResult({
    required this.name,
    required this.type,
    required this.state,
    this.records = const <DnsRecord>[],
    this.error,
  });

  final String name;
  final DnsRecordType type;
  final DnsQueryState state;
  final List<DnsRecord> records;
  final String? error;

  /// Serializes the query and every repeated answer for local persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type.name,
    'state': state.name,
    'records': records.map((record) => record.toJson()).toList(growable: false),
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

  /// Compares configuration values while ignoring TTL and answer ordering.
  ///
  /// Failed current queries are skipped because temporary unavailability is
  /// not evidence that a DNS configuration changed. Duplicate values remain
  /// in the canonical lists, so adding or removing one repeated answer is
  /// detected.
  bool hasRecordChangesFrom(DnsSnapshot previous) {
    for (final currentQuery in queries) {
      if (currentQuery.state == DnsQueryState.failed) continue;
      final previousQuery = previous.query(
        currentQuery.name,
        currentQuery.type,
      );
      if (previousQuery == null ||
          previousQuery.state == DnsQueryState.failed) {
        continue;
      }
      if (!_sameValues(currentQuery.records, previousQuery.records)) {
        return true;
      }
    }
    return false;
  }

  /// Whether at least one query could not be completed.
  bool get hasFailures =>
      queries.any((query) => query.state == DnsQueryState.failed);

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

/// Compares record multisets without considering resolver TTL churn.
bool _sameValues(List<DnsRecord> left, List<DnsRecord> right) {
  if (left.length != right.length) return false;
  List<String> values(List<DnsRecord> records) {
    final result = records
        .map(
          (record) =>
              '${record.owner}|${record.type.name}|'
              '${record.preference ?? ''}|${record.value}',
        )
        .toList();
    result.sort();
    return result;
  }

  final leftValues = values(left);
  final rightValues = values(right);
  return List<int>.generate(
    leftValues.length,
    (index) => index,
  ).every((index) => leftValues[index] == rightValues[index]);
}
