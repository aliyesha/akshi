import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:sqflite/sqflite.dart';

class TagRepository {
  TagRepository(this._database);

  final AppDatabase _database;

  Future<List<MonitorTag>> all() async {
    final database = await _database.instance;
    final rows = await database.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map(MonitorTag.fromMap).toList(growable: false);
  }

  Future<void> save(MonitorTag tag) async {
    final database = await _database.instance;
    final existing = await database.query(
      'tags',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[tag.id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await database.insert(
        'tags',
        tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return;
    }
    await database.update(
      'tags',
      tag.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[tag.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> delete(String id) async {
    final database = await _database.instance;
    await database.delete('tags', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
