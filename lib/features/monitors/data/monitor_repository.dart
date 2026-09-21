import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:sqflite/sqflite.dart';

class MonitorRepository {
  MonitorRepository(this._database);

  final AppDatabase _database;

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

  Future<bool> updateIfPresent(MonitorEntry monitor) async {
    final database = await _database.instance;
    final changed = await database.update(
      'monitors',
      monitor.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[monitor.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return changed == 1;
  }

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
