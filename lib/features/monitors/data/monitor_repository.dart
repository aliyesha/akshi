import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:sqflite/sqflite.dart';

/// Translates monitor domain objects to SQLite rows and back.
class MonitorRepository {
  MonitorRepository(this._database);

  final AppDatabase _database;

  /// Returns monitors in expiry-first order with their tag objects attached.
  Future<List<MonitorEntry>> all() async {
    final database = await _database.instance;
    final rows = await database.query(
      'monitors',
      orderBy:
          'CASE WHEN certificate_expires_at IS NULL THEN 1 ELSE 0 END, '
          'certificate_expires_at ASC, hostname ASC',
    );
    final tags = await _tagMap(database);
    return rows
        .map(MonitorEntry.fromMap)
        .map((monitor) => monitor.copyWith(tags: tags[monitor.id] ?? const []))
        .toList(growable: false);
  }

  /// Reads one monitor and its tags, or returns null when it was deleted.
  Future<MonitorEntry?> byId(String id) async {
    final database = await _database.instance;
    final rows = await database.query(
      'monitors',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final tags = await _tagMap(database, monitorId: id);
    return MonitorEntry.fromMap(rows.single)
        .copyWith(tags: tags[id] ?? const []);
  }

  /// Inserts a monitor and all tag links atomically.
  Future<void> create(
    MonitorEntry monitor, {
    Iterable<String> tagIds = const <String>[],
  }) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      await transaction.insert(
        'monitors',
        monitor.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _replaceTags(transaction, monitor.id, tagIds);
    });
  }

  /// Updates a monitor and optionally replaces its tag links in one transaction.
  Future<void> update(MonitorEntry monitor, {Iterable<String>? tagIds}) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final changed = await transaction.update(
        'monitors',
        monitor.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[monitor.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (changed != 1) {
        throw StateError('Monitor no longer exists');
      }
      if (tagIds != null) {
        await _replaceTags(transaction, monitor.id, tagIds);
      }
    });
  }

  /// Persists a check result only if the monitor row still exists.
  ///
  /// The boolean rejects a result when deletion or a definition edit changed
  /// the row after the check captured its inputs.
  Future<bool> updateObservationsIfPresent(MonitorEntry monitor) async {
    final database = await _database.instance;
    final changed = await database.update(
      'monitors',
      monitor.toObservationMap(),
      where: 'id = ? AND updated_at = ?',
      whereArgs: <Object?>[
        monitor.id,
        monitor.updatedAt.toUtc().toIso8601String(),
      ],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return changed == 1;
  }

  /// Commits a portfolio snapshot or rolls it all back if a definition changed.
  Future<void> updateObservationsAtomically(
    Iterable<MonitorEntry> monitors,
  ) async {
    final entries = monitors.toList(growable: false);
    if (entries.isEmpty) return;

    final database = await _database.instance;
    await database.transaction((transaction) async {
      for (final monitor in entries) {
        final changed = await transaction.update(
          'monitors',
          monitor.toObservationMap(),
          where: 'id = ? AND updated_at = ?',
          whereArgs: <Object?>[
            monitor.id,
            monitor.updatedAt.toUtc().toIso8601String(),
          ],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        if (changed != 1) {
          throw StateError('Monitor no longer exists');
        }
      }
    });
  }

  /// Deletes tag links and the monitor row atomically.
  Future<bool> delete(String id) async {
    final database = await _database.instance;
    return database.transaction((transaction) async {
      await transaction.delete(
        'monitor_tags',
        where: 'monitor_id = ?',
        whereArgs: <Object?>[id],
      );
      final deleted = await transaction.delete(
        'monitors',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return deleted == 1;
    });
  }

  /// Replaces the complete monitor/tag relation without leaving stale links.
  Future<void> _replaceTags(
    DatabaseExecutor database,
    String monitorId,
    Iterable<String> tagIds,
  ) async {
    await database.delete(
      'monitor_tags',
      where: 'monitor_id = ?',
      whereArgs: <Object?>[monitorId],
    );
    for (final tagId in tagIds.toSet()) {
      await database.insert('monitor_tags', <String, Object?>{
        'monitor_id': monitorId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }

  /// Builds a monitor-id to ordered tag list map from the join table.
  Future<Map<String, List<MonitorTag>>> _tagMap(
    Database database, {
    String? monitorId,
  }) async {
    final rows = await database.rawQuery('''
        SELECT mt.monitor_id, t.id, t.name, t.color_argb, t.created_at
        FROM monitor_tags mt
        INNER JOIN tags t ON t.id = mt.tag_id
        ${monitorId == null ? '' : 'WHERE mt.monitor_id = ?'}
        ORDER BY t.name COLLATE NOCASE
      ''', monitorId == null ? null : <Object?>[monitorId]);
    final result = <String, List<MonitorTag>>{};
    for (final row in rows) {
      final id = row['monitor_id']! as String;
      result.putIfAbsent(id, () => <MonitorTag>[]).add(MonitorTag.fromMap(row));
    }
    return result;
  }
}
