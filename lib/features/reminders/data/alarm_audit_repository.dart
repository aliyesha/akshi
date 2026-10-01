import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:sqflite/sqflite.dart';

/// Local proof-of-work ledger for alarm handoff.
///
/// This repository is intentionally not a scheduling source. The planner always
/// recomputes desired alarms from monitors and settings; these rows only explain
/// what Akshi computed and what the platform adapter accepted and reported back.
class AlarmAuditRepository implements AlarmAuditTrail {
  AlarmAuditRepository(this._database);

  static const retention = Duration(days: 365);
  static const maximumEntries = 1000;

  final AppDatabase _database;

  Future<List<AlarmAuditEntry>> all() async {
    final database = await _database.instance;
    final rows = await database.query(
      'alarm_audit',
      orderBy: 'alarm_date DESC, computed_at DESC',
    );
    return rows.map(AlarmAuditEntry.fromMap).toList(growable: false);
  }

  Future<List<AlarmAuditEntry>> forDate(AlarmDate date) async {
    final database = await _database.instance;
    final rows = await database.query(
      'alarm_audit',
      where: 'alarm_date = ?',
      whereArgs: <Object?>[date.toIso8601String()],
      orderBy: 'computed_at DESC',
    );
    return rows.map(AlarmAuditEntry.fromMap).toList(growable: false);
  }

  @override
  Future<void> recordComputed(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {
    final values = alarms.toList(growable: false);
    if (values.isEmpty) return;
    final database = await _database.instance;
    await database.transaction((transaction) async {
      for (final alarm in values) {
        final reasons = alarm.items.expand((item) => item.reasons).toList();
        await transaction.insert('alarm_audit', <String, Object?>{
          'audit_key': _key(alarm),
          'alarm_date': alarm.date.toIso8601String(),
          'notification_id': alarm.notificationId,
          'revision': alarm.revision,
          'scheduled_utc': alarm.scheduledAt.toUtc().toIso8601String(),
          'time_zone_id': alarm.timeZoneId,
          'requested_time':
              '${alarm.scheduledAt.hour.toString().padLeft(2, '0')}:'
              '${alarm.scheduledAt.minute.toString().padLeft(2, '0')}',
          'items_json': jsonEncode(
            alarm.items.map((item) => item.toJson()).toList(growable: false),
          ),
          'monitor_count': alarm.items.length,
          'reason_count': reasons.length,
          'domain_reason_count': reasons
              .where(
                (reason) => reason.kind == ExpiryAlarmKind.domainRegistration,
              )
              .length,
          'tls_reason_count': reasons
              .where((reason) => reason.kind == ExpiryAlarmKind.tlsCertificate)
              .length,
          'computed_at': at.toUtc().toIso8601String(),
          'platform': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await _prune(transaction, at);
    });
  }

  @override
  Future<void> recordSubmitted(ExpiryAlarmSpec alarm, DateTime at) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      // A newer revision for the same date replaces the earlier request while
      // retaining the date's stable notification ID.
      await transaction.rawUpdate(
        '''
        UPDATE alarm_audit
        SET cancelled_at = COALESCE(cancelled_at, ?)
        WHERE alarm_date = ? AND audit_key <> ? AND cancelled_at IS NULL
        ''',
        <Object?>[
          at.toUtc().toIso8601String(),
          alarm.date.toIso8601String(),
          _key(alarm),
        ],
      );
      await transaction.update(
        'alarm_audit',
        <String, Object?>{
          'submitted_at': at.toUtc().toIso8601String(),
          'cancelled_at': null,
          'failed_at': null,
          'error_category': null,
        },
        where: 'audit_key = ?',
        whereArgs: <Object?>[_key(alarm)],
      );
    });
  }

  @override
  Future<void> recordVerified(
    Iterable<ExpiryAlarmSpec> alarms,
    DateTime at,
  ) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      for (final alarm in alarms) {
        await transaction.update(
          'alarm_audit',
          <String, Object?>{
            'verified_at': at.toUtc().toIso8601String(),
            'failed_at': null,
            'error_category': null,
          },
          where: 'audit_key = ?',
          whereArgs: <Object?>[_key(alarm)],
        );
      }
    });
  }

  @override
  Future<void> recordCancelled(int notificationId, DateTime at) async {
    final database = await _database.instance;
    await database.rawUpdate(
      '''
      UPDATE alarm_audit
      SET cancelled_at = COALESCE(cancelled_at, ?)
      WHERE audit_key = (
        SELECT audit_key FROM alarm_audit
        WHERE notification_id = ?
        ORDER BY computed_at DESC
        LIMIT 1
      )
      ''',
      <Object?>[at.toUtc().toIso8601String(), notificationId],
    );
  }

  @override
  Future<void> recordFailure(
    ExpiryAlarmSpec? alarm,
    String category,
    DateTime at,
  ) async {
    if (alarm == null) return;
    final database = await _database.instance;
    await database.update(
      'alarm_audit',
      <String, Object?>{
        'failed_at': at.toUtc().toIso8601String(),
        'error_category': category,
      },
      where: 'audit_key = ?',
      whereArgs: <Object?>[_key(alarm)],
    );
  }

  String _key(ExpiryAlarmSpec alarm) =>
      '${alarm.date.toIso8601String()}|${alarm.revision}';

  Future<void> _prune(DatabaseExecutor database, DateTime now) async {
    await database.delete(
      'alarm_audit',
      where: 'computed_at < ?',
      whereArgs: <Object?>[now.toUtc().subtract(retention).toIso8601String()],
    );
    await database.rawDelete('''
      DELETE FROM alarm_audit
      WHERE audit_key IN (
        SELECT audit_key FROM alarm_audit
        ORDER BY computed_at DESC
        LIMIT -1 OFFSET $maximumEntries
      )
    ''');
  }
}
