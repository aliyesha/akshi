import 'dart:convert';

import 'package:akshi/features/reminders/domain/expiry_alarm.dart';

/// What Akshi can honestly prove about one alarm revision.
///
/// Delivery is deliberately absent: after a request is pending, Android or iOS
/// controls when (and whether) it is presented.
enum AlarmAuditStage { computed, submitted, verified, cancelled, failed }

class AlarmAuditEntry {
  const AlarmAuditEntry({
    required this.auditKey,
    required this.date,
    required this.notificationId,
    required this.revision,
    required this.scheduledUtc,
    required this.timeZoneId,
    required this.requestedTime,
    required this.items,
    required this.monitorCount,
    required this.reasonCount,
    required this.domainReasonCount,
    required this.tlsReasonCount,
    required this.computedAt,
    required this.platform,
    required this.osVersion,
    this.submittedAt,
    this.verifiedAt,
    this.cancelledAt,
    this.failedAt,
    this.errorCategory,
  });

  final String auditKey;
  final AlarmDate date;
  final int notificationId;
  final String revision;
  final DateTime scheduledUtc;
  final String timeZoneId;
  final String requestedTime;
  final List<ExpiryAlarmItem> items;
  final int monitorCount;
  final int reasonCount;
  final int domainReasonCount;
  final int tlsReasonCount;
  final DateTime computedAt;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final DateTime? cancelledAt;
  final DateTime? failedAt;
  final String? errorCategory;
  final String platform;
  final String osVersion;

  AlarmAuditStage get stage {
    if (failedAt != null) return AlarmAuditStage.failed;
    if (cancelledAt != null) return AlarmAuditStage.cancelled;
    if (verifiedAt != null) return AlarmAuditStage.verified;
    if (submittedAt != null) return AlarmAuditStage.submitted;
    return AlarmAuditStage.computed;
  }

  String get shortRevision =>
      revision.length <= 10 ? revision : revision.substring(0, 10);

  static AlarmAuditEntry fromMap(Map<String, Object?> row) {
    final rawItems = jsonDecode(row['items_json']! as String);
    if (rawItems is! List<dynamic>) {
      throw const FormatException('Invalid alarm audit items');
    }
    return AlarmAuditEntry(
      auditKey: row['audit_key']! as String,
      date: AlarmDate.parse(row['alarm_date']! as String),
      notificationId: row['notification_id']! as int,
      revision: row['revision']! as String,
      scheduledUtc: DateTime.parse(row['scheduled_utc']! as String),
      timeZoneId: row['time_zone_id']! as String,
      requestedTime: row['requested_time']! as String,
      items: rawItems
          .map(
            (value) =>
                ExpiryAlarmItem.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      monitorCount: row['monitor_count']! as int,
      reasonCount: row['reason_count']! as int,
      domainReasonCount: row['domain_reason_count']! as int,
      tlsReasonCount: row['tls_reason_count']! as int,
      computedAt: DateTime.parse(row['computed_at']! as String),
      submittedAt: _optionalDate(row['submitted_at']),
      verifiedAt: _optionalDate(row['verified_at']),
      cancelledAt: _optionalDate(row['cancelled_at']),
      failedAt: _optionalDate(row['failed_at']),
      errorCategory: row['error_category'] as String?,
      platform: row['platform']! as String,
      osVersion: row['os_version']! as String,
    );
  }

  static DateTime? _optionalDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

/// All revisions for one daily alarm, newest first.
class AlarmAuditDay {
  const AlarmAuditDay({required this.date, required this.revisions});

  final AlarmDate date;
  final List<AlarmAuditEntry> revisions;

  AlarmAuditEntry get latest => revisions.first;

  static List<AlarmAuditDay> group(Iterable<AlarmAuditEntry> entries) {
    final grouped = <AlarmDate, List<AlarmAuditEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.date, () => <AlarmAuditEntry>[]).add(entry);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return dates
        .map((date) {
          final revisions = grouped[date]!
            ..sort((a, b) => b.computedAt.compareTo(a.computedAt));
          return AlarmAuditDay(
            date: date,
            revisions: List<AlarmAuditEntry>.unmodifiable(revisions),
          );
        })
        .toList(growable: false);
  }
}

/// Non-authoritative proof trail written around platform operations.
abstract interface class AlarmAuditTrail {
  Future<void> recordComputed(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  );

  Future<void> recordSubmitted(ExpiryAlarmSpec alarm, DateTime at);

  Future<void> recordVerified(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  );

  Future<void> recordCancelled(int notificationId, DateTime at);

  Future<void> recordFailure(
    ExpiryAlarmSpec? alarm,
    String category,
    DateTime at,
  );
}

/// Explicit test/no-storage implementation; production injects SQLite.
class NoOpAlarmAuditTrail implements AlarmAuditTrail {
  const NoOpAlarmAuditTrail();

  @override
  Future<void> recordComputed(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {}

  @override
  Future<void> recordSubmitted(ExpiryAlarmSpec alarm, DateTime at) async {}

  @override
  Future<void> recordVerified(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {}

  @override
  Future<void> recordCancelled(int notificationId, DateTime at) async {}

  @override
  Future<void> recordFailure(
    ExpiryAlarmSpec? alarm,
    String category,
    DateTime at,
  ) async {}
}
