import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DNS observation reconciliation', () {
    test('failed query retains its last verified records', () {
      final verifiedAt = DateTime.utc(2026, 6, 14, 9);
      final attemptedAt = DateTime.utc(2026, 7, 14, 10);
      final previous = DnsSnapshot(
        checkedAt: verifiedAt,
        queries: <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.mx,
            state: DnsQueryState.answered,
            records: const <DnsRecord>[
              DnsRecord(
                owner: 'example.com',
                type: DnsRecordType.mx,
                ttlSeconds: 300,
                value: 'mail.example.com',
                preference: 10,
              ),
            ],
          ),
        ],
      );
      final attempt = DnsSnapshot(
        checkedAt: attemptedAt,
        queries: const <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.mx,
            state: DnsQueryState.failed,
            error: 'The device is offline.',
          ),
        ],
      );

      final reconciled = attempt.reconcileWith(previous);
      final query = reconciled.queries.single;

      expect(query.state, DnsQueryState.answered);
      expect(query.records.single.value, 'mail.example.com');
      expect(query.lastAttemptedAt, attemptedAt);
      expect(query.lastVerifiedAt, verifiedAt);
      expect(query.error, 'The device is offline.');
      expect(reconciled.hasFailures, isTrue);
    });

    test('advances a conclusive RRset while retaining a failed RRset', () {
      final verifiedAt = DateTime.utc(2026, 6, 14, 9);
      final attemptedAt = DateTime.utc(2026, 7, 14, 10);
      final previous = DnsSnapshot(
        checkedAt: verifiedAt,
        queries: const <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.mx,
            state: DnsQueryState.answered,
            records: <DnsRecord>[
              DnsRecord(
                owner: 'example.com',
                type: DnsRecordType.mx,
                ttlSeconds: 300,
                value: 'old-mail.example.com',
                preference: 10,
              ),
            ],
          ),
          DnsQueryResult(
            name: '_dmarc.example.com',
            type: DnsRecordType.txt,
            state: DnsQueryState.answered,
            records: <DnsRecord>[
              DnsRecord(
                owner: '_dmarc.example.com',
                type: DnsRecordType.txt,
                ttlSeconds: 300,
                value: 'v=DMARC1; p=none',
              ),
            ],
          ),
        ],
      );
      final attempt = DnsSnapshot(
        checkedAt: attemptedAt,
        queries: const <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.mx,
            state: DnsQueryState.answered,
            records: <DnsRecord>[
              DnsRecord(
                owner: 'example.com',
                type: DnsRecordType.mx,
                ttlSeconds: 300,
                value: 'new-mail.example.com',
                preference: 10,
              ),
            ],
          ),
          DnsQueryResult(
            name: '_dmarc.example.com',
            type: DnsRecordType.txt,
            state: DnsQueryState.failed,
            error: 'The DNS lookup timed out.',
          ),
        ],
      );

      final reconciled = attempt.reconcileWith(previous);
      final mx = reconciled.query('example.com', DnsRecordType.mx)!;
      final dmarc = reconciled.query('_dmarc.example.com', DnsRecordType.txt)!;

      expect(mx.records.single.value, 'new-mail.example.com');
      expect(mx.lastAttemptedAt, attemptedAt);
      expect(mx.lastVerifiedAt, attemptedAt);
      expect(dmarc.records.single.value, 'v=DMARC1; p=none');
      expect(dmarc.lastAttemptedAt, attemptedAt);
      expect(dmarc.lastVerifiedAt, verifiedAt);
      expect(dmarc.error, 'The DNS lookup timed out.');
      expect(reconciled.hasFailures, isTrue);
    });

    test('conclusive absence replaces previously published records', () {
      final previous = DnsSnapshot(
        checkedAt: DateTime.utc(2026, 6, 14, 9),
        queries: <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.txt,
            state: DnsQueryState.answered,
            records: const <DnsRecord>[
              DnsRecord(
                owner: 'example.com',
                type: DnsRecordType.txt,
                ttlSeconds: 300,
                value: 'v=spf1 -all',
              ),
            ],
          ),
        ],
      );
      final attemptedAt = DateTime.utc(2026, 8, 14, 11);
      final attempt = DnsSnapshot(
        checkedAt: attemptedAt,
        queries: const <DnsQueryResult>[
          DnsQueryResult(
            name: 'example.com',
            type: DnsRecordType.txt,
            state: DnsQueryState.absent,
          ),
        ],
      );

      final query = attempt.reconcileWith(previous).queries.single;

      expect(query.state, DnsQueryState.absent);
      expect(query.records, isEmpty);
      expect(query.lastVerifiedAt, attemptedAt);
      expect(query.error, isNull);
    });
  });

  group('email finding reconciliation', () {
    test('updates successful findings and retains only unavailable ones', () {
      final previousAt = DateTime.utc(2026, 6, 14, 9);
      final attemptedAt = DateTime.utc(2026, 7, 14, 10);
      final previous = EmailPosture(
        checkedAt: previousAt,
        findings: <MailFinding>[
          MailFinding(
            id: 'spf',
            title: 'SPF',
            state: MailFindingState.healthy,
            summary: 'One valid SPF policy is published.',
            observedAt: previousAt,
          ),
          MailFinding(
            id: 'dmarc',
            title: 'DMARC',
            state: MailFindingState.warning,
            summary: 'DMARC is not published.',
            observedAt: previousAt,
          ),
        ],
      );
      final attempt = EmailPosture(
        checkedAt: attemptedAt,
        findings: const <MailFinding>[
          MailFinding(
            id: 'spf',
            title: 'SPF',
            state: MailFindingState.unavailable,
            summary: 'The device is offline.',
          ),
          MailFinding(
            id: 'dmarc',
            title: 'DMARC',
            state: MailFindingState.healthy,
            summary: 'One valid DMARC policy is published.',
          ),
        ],
      );

      final reconciled = attempt.reconcileWith(previous);
      final spf = reconciled.findings.first;
      final dmarc = reconciled.findings.last;

      expect(spf.state, MailFindingState.healthy);
      expect(spf.summary, 'One valid SPF policy is published.');
      expect(spf.observedAt, previousAt);
      expect(spf.latestError, 'The device is offline.');
      expect(dmarc.state, MailFindingState.healthy);
      expect(dmarc.observedAt, attemptedAt);
      expect(dmarc.latestError, isNull);
      expect(reconciled.hasUnavailable, isTrue);
    });
  });
}
