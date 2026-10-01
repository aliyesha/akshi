import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips repeated values through local JSON storage', () {
    final snapshot = _snapshot(<DnsRecord>[
      _txt('validation=one'),
      _txt('validation=two'),
    ]);

    final restored = DnsSnapshot.fromJson(snapshot.toJson());

    expect(
      restored.queries.single.records.map((record) => record.value),
      <String>['validation=one', 'validation=two'],
    );
  });

  test('absent records remain normal snapshot inventory', () {
    final snapshot = DnsSnapshot(
      checkedAt: DateTime.utc(2026, 7, 1, 9),
      queries: const <DnsQueryResult>[
        DnsQueryResult(
          name: 'example.com',
          type: DnsRecordType.a,
          state: DnsQueryState.answered,
        ),
        DnsQueryResult(
          name: 'example.com',
          type: DnsRecordType.aaaa,
          state: DnsQueryState.absent,
        ),
      ],
    );

    expect(snapshot.queries.last.state, DnsQueryState.absent);
    expect(snapshot.hasFailures, isFalse);
  });
}

DnsSnapshot _snapshot(List<DnsRecord> records) => DnsSnapshot(
  checkedAt: DateTime.utc(2026, 6, 15, 12),
  queries: <DnsQueryResult>[
    DnsQueryResult(
      name: 'example.com',
      type: DnsRecordType.txt,
      state: records.isEmpty ? DnsQueryState.absent : DnsQueryState.answered,
      records: records,
    ),
  ],
);

DnsRecord _txt(String value, {int ttl = 300}) => DnsRecord(
  owner: 'example.com',
  type: DnsRecordType.txt,
  ttlSeconds: ttl,
  value: value,
);
