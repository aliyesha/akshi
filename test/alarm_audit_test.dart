import 'dart:convert';

import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> row({
    required String date,
    required String revision,
    required String computedAt,
    String? submittedAt,
    String? verifiedAt,
    String? cancelledAt,
    String? failedAt,
  }) => <String, Object?>{
    'audit_key': '$date|$revision',
    'alarm_date': date,
    'notification_id': ExpiryAlarmSpec.notificationIdFor(
      AlarmDate.parse(date),
    ),
    'revision': revision,
    'scheduled_utc': '${date}T09:00:00.000Z',
    'time_zone_id': 'UTC',
    'requested_time': '09:00',
    'items_json': jsonEncode(<Map<String, Object>>[
      <String, Object>{
        'id': 'alpha',
        'hostname': 'alpha.example',
        'reasons': <Map<String, Object>>[
          <String, Object>{
            'kind': 'domain',
            'expiry': '2026-08-31',
            'days': 10,
          },
        ],
      },
    ]),
    'monitor_count': 1,
    'reason_count': 1,
    'domain_reason_count': 1,
    'tls_reason_count': 0,
    'computed_at': computedAt,
    'submitted_at': submittedAt,
    'verified_at': verifiedAt,
    'cancelled_at': cancelledAt,
    'failed_at': failedAt,
    'error_category': failedAt == null ? null : 'verificationFailed',
    'platform': 'android',
    'os_version': 'test',
  };

  test('decodes the complete proof snapshot and verified stage', () {
    final entry = AlarmAuditEntry.fromMap(
      row(
        date: '2026-08-21',
        revision: '0123456789abcdef',
        computedAt: '2026-02-01T08:00:00.000Z',
        submittedAt: '2026-02-01T08:00:01.000Z',
        verifiedAt: '2026-02-01T08:00:02.000Z',
      ),
    );

    expect(entry.stage, AlarmAuditStage.verified);
    expect(entry.shortRevision, '0123456789');
    expect(entry.items.single.hostname, 'alpha.example');
    expect(
      entry.items.single.reasons.single.kind,
      ExpiryAlarmKind.domainRegistration,
    );
  });

  test('groups one card per date with newest revision first', () {
    final oldRevision = AlarmAuditEntry.fromMap(
      row(
        date: '2026-06-14',
        revision: 'old',
        computedAt: '2026-02-01T08:00:00.000Z',
        cancelledAt: '2026-02-02T08:00:00.000Z',
      ),
    );
    final newRevision = AlarmAuditEntry.fromMap(
      row(
        date: '2026-06-14',
        revision: 'new',
        computedAt: '2026-02-02T08:00:00.000Z',
        verifiedAt: '2026-02-02T08:00:02.000Z',
      ),
    );
    final laterDate = AlarmAuditEntry.fromMap(
      row(
        date: '2026-07-14',
        revision: 'later',
        computedAt: '2026-03-01T08:00:00.000Z',
      ),
    );

    final days = AlarmAuditDay.group(<AlarmAuditEntry>[
      oldRevision,
      laterDate,
      newRevision,
    ]);

    expect(days, hasLength(2));
    expect(days.first.date, const AlarmDate(2026, 7, 14));
    expect(days.last.revisions.map((entry) => entry.revision), <String>[
      'new',
      'old',
    ]);
  });

  test('failed state takes precedence over partial handoff timestamps', () {
    final entry = AlarmAuditEntry.fromMap(
      row(
        date: '2026-05-20',
        revision: 'failed',
        computedAt: '2026-02-01T08:00:00.000Z',
        submittedAt: '2026-02-01T08:00:01.000Z',
        failedAt: '2026-02-01T08:00:02.000Z',
      ),
    );

    expect(entry.stage, AlarmAuditStage.failed);
    expect(entry.errorCategory, 'verificationFailed');
  });
}
