import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores TTL and answer ordering when comparing snapshots', () {
    final previous = _snapshot(<DnsRecord>[
      _txt('validation=one', ttl: 300),
      _txt('validation=two', ttl: 300),
    ]);
    final current = _snapshot(<DnsRecord>[
      _txt('validation=two', ttl: 60),
      _txt('validation=one', ttl: 60),
    ]);

    expect(current.hasRecordChangesFrom(previous), isFalse);
  });

  test('detects removal of one repeated owner and type value', () {
    final previous = _snapshot(<DnsRecord>[
      _txt('validation=one'),
      _txt('validation=two'),
    ]);
    final current = _snapshot(<DnsRecord>[_txt('validation=one')]);

    expect(current.hasRecordChangesFrom(previous), isTrue);
  });
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

  test('does not turn a failed refresh into a record change', () {
    final previous = _snapshot(<DnsRecord>[_txt('validation=one')]);
    final current = DnsSnapshot(
      checkedAt: DateTime.utc(2026, 7, 1, 9),
      queries: const <DnsQueryResult>[
        DnsQueryResult(
          name: 'example.com',
          type: DnsRecordType.txt,
          state: DnsQueryState.failed,
          error: 'The DNS lookup timed out.',
        ),
      ],
    );

    expect(current.hasRecordChangesFrom(previous), isFalse);
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
