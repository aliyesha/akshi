import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1, 12);

  MonitorEntry entry({
    String? label = 'Production',
    DateTime? domainExpiresAt,
    DateTime? certificateExpiresAt,
    String? certificateFingerprint,
    String? previousCertificateFingerprint,
    bool? tlsTrusted = true,
  }) => MonitorEntry(
    id: 'monitor-id',
    hostname: 'example.com',
    tlsHostname: 'example.com',
    tlsPort: 443,
    checksCertificate: true,
    label: label,
    createdAt: now,
    updatedAt: now,
    domainExpiresAt: domainExpiresAt,
    certificateExpiresAt: certificateExpiresAt,
    certificateFingerprint: certificateFingerprint,
    previousCertificateFingerprint: previousCertificateFingerprint,
    tlsTrusted: tlsTrusted,
  );

  test('new monitors default to registration only', () {
    final monitor = MonitorEntry(
      id: 'domain-only',
      hostname: 'example.com',
      tlsHostname: 'example.com',
      tlsPort: 443,
      createdAt: now,
      updatedAt: now,
    );

    expect(monitor.checksCertificate, isFalse);
    expect(monitor.checksEmail, isFalse);
  });

  test('database mapping round trips monitor data', () {
    final original =
        entry(
          certificateExpiresAt: now.add(const Duration(days: 30)),
          certificateFingerprint: 'abc123',
        ).copyWith(
          domainExpiresAt: DateTime.utc(2026, 8, 31),
          domainRegisteredAt: DateTime.utc(2026, 2, 1),
          domainUpdatedAt: DateTime.utc(2026, 6, 14),
          domainRegistrar: 'Example Registrar',
          domainPublicRegistrant: 'Example Studio',
          domainNameServers: const <String>[
            'ns1.example.net',
            'ns2.example.net',
          ],
        );

    final restored = MonitorEntry.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.hostname, original.hostname);
    expect(restored.tlsHostname, original.tlsHostname);
    expect(restored.tlsPort, original.tlsPort);
    expect(restored.displayName, 'Production');
    expect(restored.tlsTrusted, isTrue);
    expect(restored.certificateFingerprint, 'abc123');
    expect(restored.domainExpiresAt?.toUtc(), DateTime.utc(2026, 8, 31));
    expect(restored.domainRegisteredAt?.toUtc(), DateTime.utc(2026, 2, 1));
    expect(restored.domainUpdatedAt?.toUtc(), DateTime.utc(2026, 6, 14));
    expect(restored.domainRegistrar, 'Example Registrar');
    expect(restored.domainPublicRegistrant, 'Example Studio');
    expect(restored.domainNameServers, <String>[
      'ns1.example.net',
      'ns2.example.net',
    ]);
  });

  test('a new certificate snapshot can clear absent optional details', () {
    final previous = entry().copyWith(
      certificateHostnameMatches: true,
      certificateSerialNumber: 'A1',
      certificateSignatureAlgorithm: 'SHA-256',
      certificatePublicKeyAlgorithm: 'RSA',
      certificatePublicKeyDetails: '2048 bit',
    );

    final replaced = previous.copyWith(
      certificateHostnameMatches: null,
      certificateSerialNumber: null,
      certificateSignatureAlgorithm: null,
      certificatePublicKeyAlgorithm: null,
      certificatePublicKeyDetails: null,
    );

    expect(replaced.certificateHostnameMatches, isNull);
    expect(replaced.certificateSerialNumber, isNull);
    expect(replaced.certificateSignatureAlgorithm, isNull);
    expect(replaced.certificatePublicKeyAlgorithm, isNull);
    expect(replaced.certificatePublicKeyDetails, isNull);
  });

  test('falls back to the hostname when the label is blank', () {
    expect(entry(label: '  ').displayName, 'example.com');
    expect(entry(label: null).displayName, 'example.com');
  });

  test('detects a changed certificate fingerprint', () {
    expect(
      entry(
        certificateFingerprint: 'new',
        previousCertificateFingerprint: 'old',
      ).certificateChanged,
      isTrue,
    );
    expect(entry(certificateFingerprint: 'same').certificateChanged, isFalse);
  });

  test('overall status uses the most urgent expiry', () {
    final monitor = entry(
      domainExpiresAt: now.add(const Duration(days: 40)),
      certificateExpiresAt: now.add(const Duration(days: 3)),
    );
    expect(monitor.overallStatus(now: now), MonitorStatus.critical);
  });

  test('a later source failure cannot hide a retained urgent expiry', () {
    final attemptedAt = now.add(const Duration(minutes: 1));
    final verifiedAt = now.subtract(const Duration(days: 1));
    final failure = CheckFailure(
      kind: CheckFailureKind.sourceUnavailable,
      message: 'Registry temporarily unavailable',
      occurredAt: attemptedAt,
    );
    final monitor =
        entry(
          domainExpiresAt: now.subtract(const Duration(days: 1)),
          certificateExpiresAt: now.add(const Duration(days: 90)),
        ).copyWith(
          lastAttemptedAt: attemptedAt,
          lastVerifiedAt: verifiedAt,
          domainError: failure.message,
          domainActivity: CheckActivity(
            lastAttemptedAt: attemptedAt,
            lastVerifiedAt: verifiedAt,
            failure: failure,
          ),
        );

    expect(monitor.overallStatus(now: now), MonitorStatus.expired);
  });

  test('DNS inventory never changes expiry or TLS health', () {
    final monitor =
        entry(
          domainExpiresAt: now.add(const Duration(days: 40)),
          certificateExpiresAt: now.add(const Duration(days: 40)),
        ).copyWith(
          dnsSnapshot: DnsSnapshot(
            checkedAt: now,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.absent,
              ),
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.aaaa,
                state: DnsQueryState.absent,
              ),
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.txt,
                state: DnsQueryState.failed,
                error: 'Temporary resolver failure',
              ),
            ],
          ),
        );

    expect(monitor.dnsSnapshot?.hasFailures, isTrue);
    expect(monitor.overallStatus(now: now), MonitorStatus.healthy);
  });

  test('offline refresh keeps the last saved expiry health', () {
    final occurredAt = now.add(const Duration(minutes: 1));
    final lastVerifiedAt = now.subtract(const Duration(days: 1));
    final failure = CheckFailure(
      kind: CheckFailureKind.offline,
      message: 'The latest check ran without a network connection.',
      occurredAt: occurredAt,
    );
    final monitor = MonitorEntry(
      id: 'offline-monitor',
      hostname: 'example.com',
      tlsHostname: 'example.com',
      tlsPort: 443,
      checksCertificate: true,
      createdAt: now,
      updatedAt: occurredAt,
      lastAttemptedAt: occurredAt,
      lastVerifiedAt: lastVerifiedAt,
      domainExpiresAt: now.add(const Duration(days: 90)),
      certificateExpiresAt: now.add(const Duration(days: 60)),
      tlsTrusted: true,
      domainError: failure.message,
      certificateError: failure.message,
      domainActivity: CheckActivity(
        lastAttemptedAt: occurredAt,
        lastVerifiedAt: lastVerifiedAt,
        failure: failure,
      ),
      certificateActivity: CheckActivity(
        lastAttemptedAt: occurredAt,
        lastVerifiedAt: lastVerifiedAt,
        failure: failure,
      ),
    );

    expect(monitor.overallStatus(now: now), MonitorStatus.healthy);
  });

  test('an untrusted certificate is always critical', () {
    final monitor = entry(
      domainExpiresAt: now.add(const Duration(days: 40)),
      certificateExpiresAt: now.add(const Duration(days: 40)),
      tlsTrusted: false,
    );
    expect(monitor.overallStatus(now: now), MonitorStatus.critical);
  });

  test('copyWith can explicitly clear the latest error', () {
    final monitor = entry().copyWith(domainError: 'Network unavailable');
    expect(monitor.copyWith(domainError: null).domainError, isNull);
  });

  test('copyWith can clear RDAP fields that stop being published', () {
    final monitor = entry().copyWith(
      domainExpiresAt: DateTime.utc(2026, 8, 31),
      domainRegistrar: 'Example Registrar',
      domainPublicRegistrant: 'Example Studio',
    );
    final refreshed = monitor.copyWith(
      domainExpiresAt: null,
      domainRegistrar: null,
      domainPublicRegistrant: null,
    );

    expect(refreshed.domainExpiresAt, isNull);
    expect(refreshed.domainRegistrar, isNull);
    expect(refreshed.domainPublicRegistrant, isNull);
  });

  test('database mapping round trips independent checks and email posture', () {
    final checkedAt = DateTime.utc(2026, 8, 20, 8, 30);
    final original = MonitorEntry(
      id: 'email-monitor',
      hostname: 'mail.example.com',
      tlsHostname: 'secure.mail.example.com',
      tlsPort: 465,
      checksCertificate: true,
      checksEmail: true,
      mailSends: true,
      mailReceives: false,
      dkimSelectors: const <String>['selector1'],
      emailPosture: EmailPosture(
        checkedAt: checkedAt,
        findings: const <MailFinding>[
          MailFinding(
            id: 'spf',
            title: 'SPF',
            state: MailFindingState.healthy,
            summary: 'One SPF policy is published.',
            facts: <MailFact>[MailFact(label: 'Policy', value: 'v=spf1 -all')],
          ),
        ],
      ),
      createdAt: now,
      updatedAt: now,
    );

    final restored = MonitorEntry.fromMap(original.toMap());

    expect(restored.checksCertificate, isTrue);
    expect(restored.checksEmail, isTrue);
    expect(restored.tlsHostname, 'secure.mail.example.com');
    expect(restored.tlsPort, 465);
    expect(restored.mailSends, isTrue);
    expect(restored.mailReceives, isFalse);
    expect(restored.dkimSelectors, <String>['selector1']);
    expect(restored.emailPosture?.findings.single.id, 'spf');
    expect(
      restored.emailPosture?.findings.single.facts.single.value,
      'v=spf1 -all',
    );
  });

  test('check activity stores attempted and verified timestamps', () {
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final verifiedAt = DateTime.utc(2026, 6, 11, 8);
    final activity = CheckActivity(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: verifiedAt,
    );

    expect(activity.toJson(), <String, Object?>{
      'last_attempted_at': attemptedAt.toIso8601String(),
      'last_verified_at': verifiedAt.toIso8601String(),
      'failure': null,
    });

    final restored = CheckActivity.fromJson(activity.toJson());
    expect(restored.lastAttemptedAt?.toUtc(), attemptedAt);
    expect(restored.lastVerifiedAt?.toUtc(), verifiedAt);
    expect(restored.failure, isNull);
  });

  test('complete attempt advances attempt and verification together', () {
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final activity = CheckActivity(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: attemptedAt,
    );
    final completed = entry()
        .copyWith(
          domainActivity: activity,
          certificateActivity: activity,
          dnsSnapshot: DnsSnapshot(
            checkedAt: attemptedAt,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.absent,
              ),
            ],
          ),
        )
        .completeAttempt(attemptedAt);

    expect(completed.lastAttemptedAt, attemptedAt);
    expect(completed.lastVerifiedAt, attemptedAt);

    final restored = MonitorEntry.fromMap(completed.toMap());
    expect(restored.lastAttemptedAt?.toUtc(), attemptedAt);
    expect(restored.lastVerifiedAt?.toUtc(), attemptedAt);
  });

  test('failed source advances attempt and preserves prior verification', () {
    final previousVerifiedAt = DateTime.utc(2026, 6, 11, 9);
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final failure = CheckFailure(
      kind: CheckFailureKind.sourceUnavailable,
      message: 'Registration source unavailable',
      occurredAt: attemptedAt,
    );
    final completed = entry()
        .copyWith(
          lastAttemptedAt: previousVerifiedAt,
          lastVerifiedAt: previousVerifiedAt,
          domainActivity: CheckActivity(
            lastAttemptedAt: attemptedAt,
            lastVerifiedAt: previousVerifiedAt,
            failure: failure,
          ),
          certificateActivity: CheckActivity(
            lastAttemptedAt: attemptedAt,
            lastVerifiedAt: attemptedAt,
          ),
          dnsSnapshot: DnsSnapshot(
            checkedAt: attemptedAt,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.absent,
              ),
            ],
          ),
        )
        .completeAttempt(attemptedAt);

    expect(completed.lastAttemptedAt, attemptedAt);
    expect(completed.lastVerifiedAt, previousVerifiedAt);
  });

  test('failed DNS query blocks full verification', () {
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final activity = CheckActivity(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: attemptedAt,
    );
    final completed = entry()
        .copyWith(
          domainActivity: activity,
          certificateActivity: activity,
          dnsSnapshot: DnsSnapshot(
            checkedAt: attemptedAt,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.failed,
                error: 'Resolver unavailable',
              ),
            ],
          ),
        )
        .completeAttempt(attemptedAt);

    expect(completed.lastAttemptedAt, attemptedAt);
    expect(completed.lastVerifiedAt, isNull);
  });

  test('unavailable email evidence blocks full verification', () {
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final activity = CheckActivity(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: attemptedAt,
    );
    final completed = entry()
        .copyWith(
          checksEmail: true,
          domainActivity: activity,
          certificateActivity: activity,
          emailActivity: activity,
          emailPosture: EmailPosture(
            checkedAt: attemptedAt,
            findings: const <MailFinding>[
              MailFinding(
                id: 'mta-sts',
                title: 'MTA-STS',
                state: MailFindingState.unavailable,
                summary: 'The HTTPS policy could not be verified.',
              ),
            ],
          ),
          dnsSnapshot: DnsSnapshot(
            checkedAt: attemptedAt,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.absent,
              ),
            ],
          ),
        )
        .completeAttempt(attemptedAt);

    expect(completed.lastAttemptedAt, attemptedAt);
    expect(completed.lastVerifiedAt, isNull);
  });

  test('observed unhealthy email evidence can be fully verified', () {
    final attemptedAt = DateTime.utc(2026, 6, 14, 9);
    final activity = CheckActivity(
      lastAttemptedAt: attemptedAt,
      lastVerifiedAt: attemptedAt,
    );
    final completed = entry()
        .copyWith(
          checksEmail: true,
          domainActivity: activity,
          certificateActivity: activity,
          emailActivity: activity,
          emailPosture: EmailPosture(
            checkedAt: attemptedAt,
            findings: const <MailFinding>[
              MailFinding(
                id: 'spf',
                title: 'SPF',
                state: MailFindingState.invalid,
                summary: 'Multiple SPF policies are published.',
              ),
            ],
          ),
          dnsSnapshot: DnsSnapshot(
            checkedAt: attemptedAt,
            queries: const <DnsQueryResult>[
              DnsQueryResult(
                name: 'example.com',
                type: DnsRecordType.a,
                state: DnsQueryState.absent,
              ),
            ],
          ),
        )
        .completeAttempt(attemptedAt);

    expect(completed.lastAttemptedAt, attemptedAt);
    expect(completed.lastVerifiedAt, attemptedAt);
  });

  test('observation mapping cannot overwrite monitor definitions', () {
    final monitor =
        entry(
          domainExpiresAt: DateTime.utc(2026, 8, 31),
          certificateExpiresAt: DateTime.utc(2026, 8, 20),
        ).copyWith(
          lastAttemptedAt: DateTime.utc(2026, 6, 14, 9),
          lastVerifiedAt: DateTime.utc(2026, 6, 14, 8),
        );

    final observations = monitor.toObservationMap();
    const definitionColumns = <String>{
      'id',
      'hostname',
      'tls_hostname',
      'tls_port',
      'checks_certificate',
      'checks_email',
      'label',
      'enabled',
      'mail_sends',
      'mail_receives',
      'dkim_selectors_json',
      'created_at',
      'updated_at',
    };

    expect(observations.keys.toSet().intersection(definitionColumns), isEmpty);
    expect(observations['domain_expires_at'], isNotNull);
    expect(observations['certificate_expires_at'], isNotNull);
    expect(observations['last_attempted_at'], isNotNull);
    expect(observations['last_verified_at'], isNotNull);
    expect(
      monitor.toMap().keys.toSet(),
      containsAll(<String>{...definitionColumns, ...observations.keys}),
    );
  });
}
