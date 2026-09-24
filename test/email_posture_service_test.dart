import 'package:akshi/core/services/email_posture_service.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports concrete healthy mail facts without inventing a score',
    () async {
      final snapshot = _snapshot(<DnsQueryResult>[
        _answered('example.com', DnsRecordType.mx, <DnsRecord>[
          _mx('example.com', 10, 'mail.example.com'),
        ]),
        _txt('example.com', <String>['v=spf1 mx -all']),
        _txt('_dmarc.example.com', <String>['v=DMARC1; p=reject']),
        _absent('_mta-sts.example.com', DnsRecordType.txt),
        _txt('_smtp._tls.example.com', <String>[
          'v=TLSRPTv1; rua=mailto:tls@example.com',
        ]),
        _txt('mail._domainkey.example.com', <String>[
          'v=DKIM1; k=rsa; p=abc123',
        ]),
      ]);

      final posture = await EmailPostureService().check(
        snapshot,
        'example.com',
        sends: true,
        receives: true,
        dkimSelectors: const <String>['mail'],
      );

      MailFinding finding(String id) =>
          posture.findings.singleWhere((finding) => finding.id == id);
      expect(finding('mx').state, MailFindingState.healthy);
      expect(finding('spf').state, MailFindingState.healthy);
      expect(finding('dmarc').state, MailFindingState.healthy);
      expect(finding('tls-rpt').state, MailFindingState.healthy);
      expect(finding('dkim-mail').state, MailFindingState.healthy);
      expect(finding('mta-sts').state, MailFindingState.informational);
    },
  );

  test('preserves repeated TXT values when validating SPF', () async {
    final snapshot = _snapshot(<DnsQueryResult>[
      _answered('example.com', DnsRecordType.mx, <DnsRecord>[
        _mx('example.com', 0, '.'),
      ]),
      _txt('example.com', <String>['v=spf1 -all', 'v=spf1 ~all']),
      _absent('_dmarc.example.com', DnsRecordType.txt),
      _absent('_mta-sts.example.com', DnsRecordType.txt),
      _absent('_smtp._tls.example.com', DnsRecordType.txt),
    ]);

    final posture = await EmailPostureService().check(
      snapshot,
      'example.com',
      sends: true,
      receives: true,
      dkimSelectors: const <String>[],
    );

    expect(posture.needsAttention, isTrue);
    expect(
      posture.findings.singleWhere((finding) => finding.id == 'mx').state,
      MailFindingState.warning,
    );
    expect(
      posture.findings.singleWhere((finding) => finding.id == 'spf').state,
      MailFindingState.invalid,
    );
  });

  test(
    'isolates a failed lookup without hiding successful mail facts',
    () async {
      final snapshot = _snapshot(<DnsQueryResult>[
        _answered('example.com', DnsRecordType.mx, <DnsRecord>[
          _mx('example.com', 10, 'mail.example.com'),
        ]),
        const DnsQueryResult(
          name: 'example.com',
          type: DnsRecordType.txt,
          state: DnsQueryState.failed,
          error: 'The DNS lookup timed out.',
        ),
        _txt('_dmarc.example.com', <String>['v=DMARC1; p=reject']),
        _absent('_mta-sts.example.com', DnsRecordType.txt),
        _absent('_smtp._tls.example.com', DnsRecordType.txt),
      ]);

      final posture = await EmailPostureService().check(
        snapshot,
        'example.com',
        sends: true,
        receives: true,
        dkimSelectors: const <String>[],
      );

      expect(
        posture.findings.singleWhere((finding) => finding.id == 'mx').state,
        MailFindingState.healthy,
      );
      expect(
        posture.findings.singleWhere((finding) => finding.id == 'spf').state,
        MailFindingState.unavailable,
      );
      expect(
        posture.findings.singleWhere((finding) => finding.id == 'dmarc').state,
        MailFindingState.healthy,
      );
      expect(posture.hasUnavailable, isTrue);
    },
  );
}

DnsSnapshot _snapshot(List<DnsQueryResult> queries) =>
    DnsSnapshot(checkedAt: DateTime.utc(2026, 6, 15, 12), queries: queries);

DnsQueryResult _answered(
  String name,
  DnsRecordType type,
  List<DnsRecord> records,
) => DnsQueryResult(
  name: name,
  type: type,
  state: DnsQueryState.answered,
  records: records,
);

DnsQueryResult _absent(String name, DnsRecordType type) =>
    DnsQueryResult(name: name, type: type, state: DnsQueryState.absent);

DnsQueryResult _txt(String name, List<String> values) => _answered(
  name,
  DnsRecordType.txt,
  values
      .map(
        (value) => DnsRecord(
          owner: name,
          type: DnsRecordType.txt,
          ttlSeconds: 300,
          value: value,
        ),
      )
      .toList(growable: false),
);

DnsRecord _mx(String owner, int preference, String exchange) => DnsRecord(
  owner: owner,
  type: DnsRecordType.mx,
  ttlSeconds: 3600,
  value: exchange,
  preference: preference,
);
