import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/domain/tag_policy.dart';
import 'package:sqflite/sqflite.dart';

class TagRepository {
  TagRepository(this._database);

  final AppDatabase _database;

  Future<List<MonitorTag>> all() async {
    final database = await _database.instance;
    final rows = await database.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map(MonitorTag.fromMap).toList(growable: false);
  }

  /// Inserts a tag while enforcing the product limit in one transaction.
  ///
  /// The visible count guides the user; this transactional count is the
  /// authoritative boundary when two create intents arrive close together.
  Future<void> create(MonitorTag tag) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final count =
          Sqflite.firstIntValue(
            await transaction.rawQuery('SELECT COUNT(*) FROM tags'),
          ) ??
          0;
      if (!TagPolicy.canCreate(count)) {
        throw const TagLimitReachedException();
      }
      await transaction.insert(
        'tags',
        tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  /// Updates an existing tag without consuming another capacity slot.
  Future<void> update(MonitorTag tag) async {
    final database = await _database.instance;
    final changed = await database.update(
      'tags',
      tag.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[tag.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (changed != 1) {
      throw StateError('Tag no longer exists');
    }
  }

  Future<void> delete(String id) async {
    final database = await _database.instance;
    await database.delete('tags', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
