import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 5, 1, 12);

  MonitorEntry monitor({
    DateTime? domainExpiry,
    DateTime? certificateExpiry,
    bool? tlsTrusted = true,
    String? domainError,
  }) => MonitorEntry(
    id: 'monitor-id',
    hostname: 'example.com',
    tlsHostname: 'example.com',
    tlsPort: 443,
    checksCertificate: true,
    createdAt: now,
    updatedAt: now,
    lastCheckedAt: now,
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: certificateExpiry,
    tlsTrusted: tlsTrusted,
    domainError: domainError,
  );

  test('domain and certificate remain independent findings', () {
    final findings = findingsForMonitor(
      monitor(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 3)),
      ),
      now: now,
    );

    expect(findings[0].kind, MonitorCheckKind.domainRegistration);
    expect(findings[0].status, MonitorStatus.healthy);
    expect(findings[1].kind, MonitorCheckKind.tlsCertificate);
    expect(findings[1].status, MonitorStatus.critical);
  });

  test('an untrusted certificate is critical regardless of expiry', () {
    final findings = findingsForMonitor(
      monitor(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 90)),
        tlsTrusted: false,
      ),
      now: now,
    );

    expect(findings[1].status, MonitorStatus.critical);
    expect(findings[1].needsAttention, isTrue);
  });

  test('partial check errors mark only the affected finding unavailable', () {
    final findings = findingsForMonitor(
      monitor(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 90)),
        domainError: 'Registry temporarily unavailable',
      ),
      now: now,
    );

    expect(findings[0].status, MonitorStatus.unavailable);
    expect(findings[1].status, MonitorStatus.healthy);
  });

  test('TLS and Email can be enabled together on one domain', () {
    final findings = findingsForMonitor(
      MonitorEntry(
        id: 'email-monitor',
        hostname: 'example.com',
        tlsHostname: 'mail.example.com',
        tlsPort: 465,
        checksCertificate: true,
        checksEmail: true,
        createdAt: now,
        updatedAt: now,
        lastCheckedAt: now,
        domainExpiresAt: now.add(const Duration(days: 90)),
        certificateExpiresAt: now.add(const Duration(days: 60)),
        tlsTrusted: true,
        emailPosture: EmailPosture(
          checkedAt: now,
          findings: const <MailFinding>[
            MailFinding(
              id: 'spf',
              title: 'SPF',
              state: MailFindingState.warning,
              summary: 'No SPF policy is published.',
            ),
          ],
        ),
      ),
      now: now,
    );

    expect(findings.map((finding) => finding.kind), <MonitorCheckKind>[
      MonitorCheckKind.domainRegistration,
      MonitorCheckKind.tlsCertificate,
      MonitorCheckKind.emailConfiguration,
    ]);
    expect(findings.last.status, MonitorStatus.warning);
  });

  test('domain, TLS, and Email attention states remain independent', () {
    final referenceTime = DateTime.utc(2026, 5, 1, 12);
    for (var mask = 0; mask < 8; mask++) {
      final domainNeedsAttention = mask & 1 != 0;
      final certificateNeedsAttention = mask & 2 != 0;
      final emailNeedsAttention = mask & 4 != 0;
      final entry = MonitorEntry(
        id: 'combination-$mask',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        checksCertificate: true,
        checksEmail: true,
        createdAt: now,
        updatedAt: now,
        lastCheckedAt: now,
        domainExpiresAt: referenceTime.add(
          Duration(days: domainNeedsAttention ? 3 : 90),
        ),
        certificateExpiresAt: referenceTime.add(
          Duration(days: certificateNeedsAttention ? 3 : 90),
        ),
        tlsTrusted: true,
        emailPosture: EmailPosture(
          checkedAt: now,
          findings: <MailFinding>[
            MailFinding(
              id: 'spf',
              title: 'SPF',
              state: emailNeedsAttention
                  ? MailFindingState.warning
                  : MailFindingState.healthy,
              summary: emailNeedsAttention
                  ? 'SPF needs review.'
                  : 'SPF is published.',
            ),
          ],
        ),
      );

      final findings = findingsForMonitor(entry, now: referenceTime);
      expect(findings, hasLength(3), reason: 'combination $mask');
      expect(findings.map((finding) => finding.needsAttention), <bool>[
        domainNeedsAttention,
        certificateNeedsAttention,
        emailNeedsAttention,
      ], reason: 'combination $mask');
      expect(
        entry.overallStatus(now: referenceTime),
        domainNeedsAttention || certificateNeedsAttention
            ? MonitorStatus.critical
            : emailNeedsAttention
            ? MonitorStatus.warning
            : MonitorStatus.healthy,
        reason: 'combination $mask',
      );
    }
  });

  test('check kinds parse stable attention route identifiers', () {
    for (final kind in MonitorCheckKind.values) {
      expect(MonitorCheckKind.fromId(kind.id), kind);
    }
    expect(MonitorCheckKind.fromId(null), isNull);
    expect(MonitorCheckKind.fromId('unknown-check'), isNull);
  });
}
