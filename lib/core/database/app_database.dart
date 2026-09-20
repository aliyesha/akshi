import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _database;

  Future<Database> get instance async {
    final current = _database;
    if (current != null) return current;
    final root = await getDatabasesPath();
    return _database = await openDatabase(
      p.join(root, 'akshi.db'),
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE monitors (
            id TEXT PRIMARY KEY,
            hostname TEXT NOT NULL,
            port INTEGER NOT NULL,
            label TEXT,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            domain_expires_at TEXT,
            certificate_expires_at TEXT,
            certificate_valid_from TEXT,
            last_checked_at TEXT,
            domain_source TEXT,
            certificate_issuer TEXT,
            certificate_subject TEXT,
            certificate_fingerprint TEXT,
            previous_certificate_fingerprint TEXT,
            tls_trusted INTEGER,
            domain_error TEXT,
            certificate_error TEXT
          )
        ''');
        await database.execute(
          'CREATE UNIQUE INDEX monitor_endpoint '
          'ON monitors(hostname, port)',
        );
        await database.execute('''
          CREATE TABLE tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            color_argb INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE monitor_tags (
            monitor_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (monitor_id, tag_id),
            FOREIGN KEY (monitor_id) REFERENCES monitors(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX monitor_tags_tag ON monitor_tags(tag_id)',
        );
      },
    );
  }
}
