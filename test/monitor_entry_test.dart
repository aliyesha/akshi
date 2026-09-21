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
          domainUpdatedAt: DateTime.utc(2026, 6, 12),
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
    expect(restored.domainUpdatedAt?.toUtc(), DateTime.utc(2026, 6, 12));
    expect(restored.domainRegistrar, 'Example Registrar');
    expect(restored.domainPublicRegistrant, 'Example Studio');
    expect(restored.domainNameServers, <String>[
      'ns1.example.net',
      'ns2.example.net',
    ]);
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
}
