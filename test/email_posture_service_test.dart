import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/services/email_posture_service.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = EmailPostureService(_UnusedHttpClient());
  group('bounded MTA-STS policy reader', () {
    const reader = MtaStsPolicyReader(maxBytes: 64);

    test('uses a 128 KiB production boundary', () {
      expect(MtaStsPolicyReader.defaultMaxBytes, 128 * 1024);
    });

    test('reads valid UTF-8 policy text', () async {
      final bytes = utf8.encode(
        'version: STSv1\nmode: enforce\nmx: mail.example.com\nmax_age: 86400',
      );

      final policy = await reader.read(
        Stream<List<int>>.value(bytes),
        contentType: 'text/plain; charset=utf-8',
        contentLength: bytes.length,
      );

      expect(policy, contains('mode: enforce'));
    });

    test('rejects and cancels an oversized declared body', () async {
      const smallReader = MtaStsPolicyReader(maxBytes: 4);
      var wasCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          wasCancelled = true;
        },
      );
      addTearDown(() => unawaited(body.close()));

      await expectLater(
        smallReader.read(
          body.stream,
          contentType: 'text/plain',
          contentLength: 5,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(wasCancelled, isTrue);
    });

    test('applies one timeout to the complete response body', () async {
      final body = StreamController<List<int>>();
      addTearDown(() => unawaited(body.close()));
      const impatientReader = MtaStsPolicyReader(
        maxBytes: 64,
        timeout: Duration(milliseconds: 20),
      );

      await expectLater(
        impatientReader.read(
          body.stream,
          contentType: 'text/plain',
          contentLength: null,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('rejects and cancels a non-text policy response', () async {
      var wasCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          wasCancelled = true;
        },
      );
      addTearDown(() => unawaited(body.close()));

      await expectLater(
        reader.read(
          body.stream,
          contentType: 'text/html; charset=utf-8',
          contentLength: null,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(wasCancelled, isTrue);
    });
  });

  test('reports concrete mail facts without inventing validation', () async {
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
      _txt('mail._domainkey.example.com', <String>['v=DKIM1; k=rsa; p=abc123']),
    ]);

    final posture = await service.check(
      snapshot,
      'example.com',
      sends: true,
      receives: true,
      dkimSelectors: const <String>['mail'],
    );

    MailFinding finding(String id) =>
        posture.findings.singleWhere((finding) => finding.id == id);
    expect(finding('mx').state, MailFindingState.healthy);
    expect(finding('spf').state, MailFindingState.informational);
    expect(finding('dmarc').state, MailFindingState.informational);
    expect(finding('tls-rpt').state, MailFindingState.informational);
    expect(finding('dkim-mail').state, MailFindingState.informational);
    expect(finding('mta-sts').state, MailFindingState.informational);
    expect(
      finding('spf').summary,
      contains('does not test it against a sending server'),
    );
  });

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

    final posture = await service.check(
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

      final posture = await service.check(
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
        MailFindingState.informational,
      );
      expect(posture.needsAttention, isFalse);
      expect(posture.hasUnavailable, isTrue);
    },
  );

  test('MTA-STS remains unavailable when its MX dependency failed', () async {
    final snapshot = _snapshot(<DnsQueryResult>[
      const DnsQueryResult(
        name: 'example.com',
        type: DnsRecordType.mx,
        state: DnsQueryState.failed,
        error: 'The DNS lookup timed out.',
      ),
      _txt('_mta-sts.example.com', <String>['v=STSv1; id=20260714']),
      _absent('_smtp._tls.example.com', DnsRecordType.txt),
    ]);

    final posture = await service.check(
      snapshot,
      'example.com',
      sends: false,
      receives: true,
      dkimSelectors: const <String>[],
    );

    final mx = posture.findings.singleWhere((finding) => finding.id == 'mx');
    final mtaSts = posture.findings.singleWhere(
      (finding) => finding.id == 'mta-sts',
    );

    expect(mx.state, MailFindingState.unavailable);
    expect(mtaSts.state, MailFindingState.unavailable);
    expect(mtaSts.summary, 'The DNS lookup timed out.');
  });

  test('absent MTA-STS remains conclusive when MX is unavailable', () async {
    final snapshot = _snapshot(<DnsQueryResult>[
      const DnsQueryResult(
        name: 'example.com',
        type: DnsRecordType.mx,
        state: DnsQueryState.failed,
        error: 'The DNS lookup timed out.',
      ),
      _absent('_mta-sts.example.com', DnsRecordType.txt),
      _absent('_smtp._tls.example.com', DnsRecordType.txt),
    ]);

    final posture = await service.check(
      snapshot,
      'example.com',
      sends: false,
      receives: true,
      dkimSelectors: const <String>[],
    );

    final mtaSts = posture.findings.singleWhere(
      (finding) => finding.id == 'mta-sts',
    );

    expect(mtaSts.state, MailFindingState.informational);
    expect(mtaSts.summary, 'No MTA-STS policy is published.');
  });

  test('shows only findings for the selected email role', () async {
    final snapshot = _snapshot(<DnsQueryResult>[
      _answered('example.com', DnsRecordType.mx, <DnsRecord>[
        _mx('example.com', 10, 'mail.example.com'),
      ]),
      _absent('_mta-sts.example.com', DnsRecordType.txt),
      _absent('_smtp._tls.example.com', DnsRecordType.txt),
    ]);

    final posture = await service.check(
      snapshot,
      'example.com',
      sends: false,
      receives: true,
      dkimSelectors: const <String>['ignored'],
    );

    expect(posture.findings.map((finding) => finding.id), <String>[
      'mx',
      'mta-sts',
      'tls-rpt',
    ]);
  });
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

final class _UnusedHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
