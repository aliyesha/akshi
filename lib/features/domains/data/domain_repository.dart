import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/tags/domain/domain_tag.dart';
import 'package:sqflite/sqflite.dart';

/// Translates domain objects to SQLite rows and back.
class DomainRepository {
  DomainRepository(this._database);

  final AppDatabase _database;

  /// Returns domains in expiry-first order with their tag objects attached.
  Future<List<DomainEntry>> all() async {
    final database = await _database.instance;
    final rows = await database.query(
      'domains',
      orderBy:
          'CASE WHEN certificate_expires_at IS NULL THEN 1 ELSE 0 END, '
          'certificate_expires_at ASC, hostname ASC',
    );
    final tags = await _tagMap(database);
    return rows
        .map(DomainEntry.fromMap)
        .map((domain) => domain.copyWith(tags: tags[domain.id] ?? const []))
        .toList(growable: false);
  }

  /// Reads one domain and its tags, or returns null when it was deleted.
  Future<DomainEntry?> byId(String id) async {
    final database = await _database.instance;
    final rows = await database.query(
      'domains',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final tags = await _tagMap(database, domainId: id);
    return DomainEntry.fromMap(rows.single)
        .copyWith(tags: tags[id] ?? const []);
  }

  /// Inserts a domain and all tag links atomically.
  Future<void> create(
    DomainEntry domain, {
    Iterable<String> tagIds = const <String>[],
  }) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      await transaction.insert(
        'domains',
        domain.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _replaceTags(transaction, domain.id, tagIds);
    });
  }

  /// Updates a domain and optionally replaces its tag links in one transaction.
  Future<void> update(DomainEntry domain, {Iterable<String>? tagIds}) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final changed = await transaction.update(
        'domains',
        domain.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[domain.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (changed != 1) {
        throw StateError('Domain no longer exists');
      }
      if (tagIds != null) {
        await _replaceTags(transaction, domain.id, tagIds);
      }
    });
  }

  /// Persists a check result only if the domain row still exists.
  ///
  /// The boolean rejects a result when deletion or a definition edit changed
  /// the row after the check captured its inputs.
  Future<bool> updateObservationsIfPresent(DomainEntry domain) async {
    final database = await _database.instance;
    final changed = await database.update(
      'domains',
      domain.toObservationMap(),
      where: 'id = ? AND updated_at = ?',
      whereArgs: <Object?>[
        domain.id,
        domain.updatedAt.toUtc().toIso8601String(),
      ],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return changed == 1;
  }

  /// Commits a portfolio snapshot or rolls it all back if a definition changed.
  Future<void> updateObservationsAtomically(
    Iterable<DomainEntry> domains,
  ) async {
    final entries = domains.toList(growable: false);
    if (entries.isEmpty) return;

    final database = await _database.instance;
    await database.transaction((transaction) async {
      for (final domain in entries) {
        final changed = await transaction.update(
          'domains',
          domain.toObservationMap(),
          where: 'id = ? AND updated_at = ?',
          whereArgs: <Object?>[
            domain.id,
            domain.updatedAt.toUtc().toIso8601String(),
          ],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        if (changed != 1) {
          throw StateError('Domain no longer exists');
        }
      }
    });
  }

  /// Deletes tag links and the domain row atomically.
  Future<bool> delete(String id) async {
    final database = await _database.instance;
    return database.transaction((transaction) async {
      await transaction.delete(
        'domain_tags',
        where: 'domain_id = ?',
        whereArgs: <Object?>[id],
      );
      final deleted = await transaction.delete(
        'domains',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return deleted == 1;
    });
  }

  /// Replaces the complete domain/tag relation without leaving stale links.
  Future<void> _replaceTags(
    DatabaseExecutor database,
    String domainId,
    Iterable<String> tagIds,
  ) async {
    await database.delete(
      'domain_tags',
      where: 'domain_id = ?',
      whereArgs: <Object?>[domainId],
    );
    for (final tagId in tagIds.toSet()) {
      await database.insert('domain_tags', <String, Object?>{
        'domain_id': domainId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }

  /// Builds a domain-id to ordered tag list map from the join table.
  Future<Map<String, List<DomainTag>>> _tagMap(
    Database database, {
    String? domainId,
  }) async {
    final rows = await database.rawQuery('''
        SELECT mt.domain_id, t.id, t.name, t.color_argb, t.created_at
        FROM domain_tags mt
        INNER JOIN tags t ON t.id = mt.tag_id
        ${domainId == null ? '' : 'WHERE mt.domain_id = ?'}
        ORDER BY t.name COLLATE NOCASE
      ''', domainId == null ? null : <Object?>[domainId]);
    final result = <String, List<DomainTag>>{};
    for (final row in rows) {
      final id = row['domain_id']! as String;
      result.putIfAbsent(id, () => <DomainTag>[]).add(DomainTag.fromMap(row));
    }
    return result;
  }
}
