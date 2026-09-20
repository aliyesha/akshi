import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();

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
    port: 443,
    label: label,
    createdAt: now,
    updatedAt: now,
    domainExpiresAt: domainExpiresAt,
    certificateExpiresAt: certificateExpiresAt,
    certificateFingerprint: certificateFingerprint,
    previousCertificateFingerprint: previousCertificateFingerprint,
    tlsTrusted: tlsTrusted,
  );

  test('database mapping round trips monitor data', () {
    final original = entry(
      certificateExpiresAt: now.add(const Duration(days: 30)),
      certificateFingerprint: 'abc123',
    );

    final restored = MonitorEntry.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.hostname, original.hostname);
    expect(restored.port, original.port);
    expect(restored.displayName, 'Production');
    expect(restored.tlsTrusted, isTrue);
    expect(restored.certificateFingerprint, 'abc123');
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
    expect(monitor.overallStatus(), MonitorStatus.critical);
  });

  test('an untrusted certificate is always critical', () {
    final monitor = entry(
      domainExpiresAt: now.add(const Duration(days: 40)),
      certificateExpiresAt: now.add(const Duration(days: 40)),
      tlsTrusted: false,
    );
    expect(monitor.overallStatus(), MonitorStatus.critical);
  });

  test('copyWith can explicitly clear the latest error', () {
    final monitor = entry().copyWith(domainError: 'Network unavailable');
    expect(monitor.copyWith(domainError: null).domainError, isNull);
  });
}
