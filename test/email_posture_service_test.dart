import 'package:akshi/core/services/email_posture_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports concrete healthy mail facts without inventing a score', () async {
    final service = EmailPostureService(
      dns: _FakeDns(
        mxRecords: const <MxRecord>[
          MxRecord(preference: 10, exchange: 'mail.example.com'),
        ],
        txtRecords: const <String, List<String>>{
          'example.com': <String>['v=spf1 mx -all'],
          '_dmarc.example.com': <String>['v=DMARC1; p=reject'],
          '_smtp._tls.example.com': <String>[
            'v=TLSRPTv1; rua=mailto:tls@example.com',
          ],
          'mail._domainkey.example.com': <String>[
            'v=DKIM1; k=rsa; p=abc123',
          ],
        },
      ),
    );

    final posture = await service.check(
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
  });

  test('treats Null MX and multiple SPF policies as actionable', () async {
    final service = EmailPostureService(
      dns: _FakeDns(
        mxRecords: const <MxRecord>[
          MxRecord(preference: 0, exchange: '.'),
        ],
        txtRecords: const <String, List<String>>{
          'example.com': <String>['v=spf1 -all', 'v=spf1 ~all'],
        },
      ),
    );

    final posture = await service.check(
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
}

class _FakeDns extends SystemDnsService {
  const _FakeDns({
    this.mxRecords = const <MxRecord>[],
    this.txtRecords = const <String, List<String>>{},
  });

  final List<MxRecord> mxRecords;
  final Map<String, List<String>> txtRecords;

  @override
  Future<List<MxRecord>> mx(String name) async => mxRecords;

  @override
  Future<List<String>> txt(String name) async =>
      txtRecords[name] ?? const <String>[];
}
