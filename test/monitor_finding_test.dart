import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_finding.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 19, 12);

  MonitorEntry monitor({
    DateTime? domainExpiry,
    DateTime? certificateExpiry,
    bool? tlsTrusted = true,
    String? domainError,
  }) => MonitorEntry(
    id: 'monitor-id',
    hostname: 'example.com',
    port: 443,
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
}
