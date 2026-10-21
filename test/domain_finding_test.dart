import 'package:akshi/features/domains/domain/check_activity.dart';
import 'package:akshi/features/domains/domain/email_posture.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/domain_finding.dart';
import 'package:akshi/features/domains/domain/domain_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 5, 1, 12);

  DomainEntry domain({
    DateTime? domainExpiry,
    DateTime? certificateExpiry,
    bool? tlsTrusted = true,
    String? domainError,
    String? certificateError,
    bool checksEmail = false,
    CheckActivity domainActivity = const CheckActivity(),
    CheckActivity certificateActivity = const CheckActivity(),
    CheckActivity emailActivity = const CheckActivity(),
  }) => DomainEntry(
    id: 'domain-id',
    hostname: 'example.com',
    tlsHostname: 'example.com',
    tlsPort: 443,
    checksCertificate: true,
    checksEmail: checksEmail,
    createdAt: now,
    updatedAt: now,
    lastAttemptedAt: now,
    lastVerifiedAt: now,
    domainExpiresAt: domainExpiry,
    certificateExpiresAt: certificateExpiry,
    tlsTrusted: tlsTrusted,
    domainError: domainError,
    certificateError: certificateError,
    domainActivity: domainActivity,
    certificateActivity: certificateActivity,
    emailActivity: emailActivity,
  );

  test('domain and certificate remain independent findings', () {
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 3)),
      ),
      now: now,
    );

    expect(findings[0].kind, DomainCheckKind.domainRegistration);
    expect(findings[0].status, DomainStatus.healthy);
    expect(findings[1].kind, DomainCheckKind.tlsCertificate);
    expect(findings[1].status, DomainStatus.critical);
  });

  test('urgent expiry remains visible when the latest source check fails', () {
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 3)),
        certificateExpiry: now.add(const Duration(days: 90)),
        domainError: 'Registry temporarily unavailable',
      ),
      now: now,
    );

    expect(findings.first.status, DomainStatus.critical);
    expect(
      findings.first.summary,
      'Expires in 3 days · Latest check unavailable — '
      'Registry temporarily unavailable',
    );
  });

  test('summary calls a near tomorrow one calendar day away', () {
    final evening = DateTime(2026, 5, 1, 20);
    final findings = findingsForDomain(
      domain(domainExpiry: DateTime(2026, 5, 2, 8)),
      now: evening,
    );

    expect(findings.first.summary, 'Expires in 1 day');
  });

  test('summary calls a recent yesterday one calendar day ago', () {
    final morning = DateTime(2026, 5, 2, 8);
    final findings = findingsForDomain(
      domain(
        domainExpiry: DateTime(2026, 5, 1, 20),
        certificateExpiry: DateTime(2026, 6, 1),
      ),
      now: morning,
    );

    expect(findings.first.summary, 'Expired 1 day ago');
  });

  test('offline refresh does not create attention findings', () {
    final failure = CheckFailure(
      kind: CheckFailureKind.offline,
      message: 'The latest check ran without a network connection.',
      occurredAt: now,
    );
    final activity = CheckActivity(
      lastAttemptedAt: now,
      lastVerifiedAt: now.subtract(const Duration(days: 1)),
      failure: failure,
    );
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 60)),
        domainError: failure.message,
        certificateError: failure.message,
        domainActivity: activity,
        certificateActivity: activity,
      ),
      now: now,
    );

    expect(findings.map((finding) => finding.status), <DomainStatus>[
      DomainStatus.healthy,
      DomainStatus.healthy,
    ]);
    expect(findings.any((finding) => finding.needsAttention), isFalse);
  });

  test('an untrusted certificate is critical regardless of expiry', () {
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 90)),
        tlsTrusted: false,
      ),
      now: now,
    );

    expect(findings[1].status, DomainStatus.critical);
    expect(findings[1].needsAttention, isTrue);
  });

  test('partial check errors mark only the affected finding unavailable', () {
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 90)),
        domainError: 'Registry temporarily unavailable',
      ),
      now: now,
    );

    expect(findings[0].status, DomainStatus.unavailable);
    expect(findings[1].status, DomainStatus.healthy);
  });

  test('TLS and Email can be enabled together on one domain', () {
    final findings = findingsForDomain(
      DomainEntry(
        id: 'email-domain',
        hostname: 'example.com',
        tlsHostname: 'mail.example.com',
        tlsPort: 465,
        checksCertificate: true,
        checksEmail: true,
        createdAt: now,
        updatedAt: now,
        lastAttemptedAt: now,
        lastVerifiedAt: now,
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

    expect(findings.map((finding) => finding.kind), <DomainCheckKind>[
      DomainCheckKind.domainRegistration,
      DomainCheckKind.tlsCertificate,
      DomainCheckKind.emailConfiguration,
    ]);
    expect(findings.last.status, DomainStatus.warning);
  });

  test('domain, TLS, and Email attention states remain independent', () {
    final referenceTime = DateTime.utc(2026, 5, 1, 12);
    for (var mask = 0; mask < 8; mask++) {
      final domainNeedsAttention = mask & 1 != 0;
      final certificateNeedsAttention = mask & 2 != 0;
      final emailNeedsAttention = mask & 4 != 0;
      final entry = DomainEntry(
        id: 'combination-$mask',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        checksCertificate: true,
        checksEmail: true,
        createdAt: now,
        updatedAt: now,
        lastAttemptedAt: now,
        lastVerifiedAt: now,
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

      final findings = findingsForDomain(entry, now: referenceTime);
      expect(findings, hasLength(3), reason: 'combination $mask');
      expect(findings.map((finding) => finding.needsAttention), <bool>[
        domainNeedsAttention,
        certificateNeedsAttention,
        emailNeedsAttention,
      ], reason: 'combination $mask');
      expect(
        entry.overallStatus(now: referenceTime),
        domainNeedsAttention || certificateNeedsAttention
            ? DomainStatus.critical
            : emailNeedsAttention
            ? DomainStatus.warning
            : DomainStatus.healthy,
        reason: 'combination $mask',
      );
    }
  });

  test('unavailable findings preserve the useful failure reason', () {
    final findings = findingsForDomain(
      domain(
        domainExpiry: now.add(const Duration(days: 90)),
        certificateExpiry: now.add(const Duration(days: 90)),
        domainError: 'Registry temporarily unavailable',
        certificateError: 'TLS handshake timed out',
        checksEmail: true,
        emailActivity: CheckActivity(
          lastAttemptedAt: now,
          failure: CheckFailure(
            kind: CheckFailureKind.dns,
            message: 'DNS lookup timed out',
            occurredAt: now,
          ),
        ),
      ),
      now: now,
    );

    expect(
      findings[0].summary,
      'Domain registration check unavailable — Registry temporarily unavailable',
    );
    expect(
      findings[1].summary,
      'TLS certificate check unavailable — TLS handshake timed out',
    );
    expect(
      findings[2].summary,
      'Email configuration check unavailable — DNS lookup timed out',
    );
  });

  test('a partial Email lookup is incomplete, not a configuration warning', () {
    final entry = DomainEntry(
      id: 'email-unavailable',
      hostname: 'example.com',
      tlsHostname: 'example.com',
      tlsPort: 443,
      checksEmail: true,
      createdAt: now,
      updatedAt: now,
      lastAttemptedAt: now,
      lastVerifiedAt: now,
      domainExpiresAt: now.add(const Duration(days: 90)),
      emailPosture: EmailPosture(
        checkedAt: now,
        findings: const <MailFinding>[
          MailFinding(
            id: 'spf',
            title: 'SPF',
            state: MailFindingState.unavailable,
            summary: 'The SPF lookup timed out.',
          ),
        ],
      ),
    );

    final email = findingsForDomain(entry, now: now).last;
    expect(email.status, DomainStatus.incomplete);
    expect(email.needsAttention, isFalse);
    expect(email.summary, 'Email configuration check incomplete');
    expect(entry.overallStatus(now: now), DomainStatus.incomplete);
  });

  test('check kinds parse stable attention route identifiers', () {
    for (final kind in DomainCheckKind.values) {
      expect(DomainCheckKind.fromId(kind.id), kind);
    }
    expect(DomainCheckKind.fromId(null), isNull);
    expect(DomainCheckKind.fromId('unknown-check'), isNull);
  });
}
