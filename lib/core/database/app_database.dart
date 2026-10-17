import 'dart:async';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the single local SQLite connection used by Akshi repositories.
///
/// The schema is created as one clean development schema. Foreign keys are
/// enabled before any repository transaction runs.
class AppDatabase {
  factory AppDatabase({
    Future<Database> Function()? openConnection,
    Future<void> Function(Database database)? closeConnection,
  }) => AppDatabase._(
    openConnection ?? _openApplicationDatabase,
    closeConnection ?? _closeApplicationDatabase,
  );

  AppDatabase._(this._openConnection, this._closeConnection);

  final Future<Database> Function() _openConnection;
  final Future<void> Function(Database database) _closeConnection;

  Database? _database;
  Future<Database>? _openingDatabase;
  Future<Database>? _instanceOperation;
  Future<void>? _closeOperation;
  var _isClosed = false;

  /// Opens the database lazily and returns the shared connection.
  ///
  /// Concurrent callers join the same in-flight open. After [close] begins,
  /// access is permanently rejected because a disposed provider must never
  /// recreate a connection behind repositories that are also being disposed.
  Future<Database> get instance {
    if (_isClosed) {
      return Future<Database>.error(
        StateError('AppDatabase is already closed.'),
      );
    }
    final current = _database;
    if (current != null) return Future<Database>.value(current);
    final active = _instanceOperation;
    if (active != null) return active;

    final opening = Future<Database>.sync(_openConnection);
    _openingDatabase = opening;
    late final Future<Database> operation;
    operation = _completeOpen(opening).whenComplete(() {
      if (identical(_instanceOperation, operation)) {
        _instanceOperation = null;
        _openingDatabase = null;
      }
    });
    _instanceOperation = operation;
    return operation;
  }

  /// Closes the connection once and rejects all future access.
  ///
  /// If opening is still in flight, closure waits for the raw connection and
  /// closes it before completing. Repeated callers join the same close future.
  Future<void> close() {
    final active = _closeOperation;
    if (active != null) return active;

    _isClosed = true;
    final opening = _openingDatabase;
    final current = _database;
    _database = null;

    final operation = _close(opening: opening, current: current);
    _closeOperation = operation;
    return operation;
  }

  /// Starts owned shutdown for synchronous lifecycle callbacks.
  ///
  /// Explicit callers that need completion or failure should await [close].
  void dispose() {
    unawaited(_closeForDisposal());
  }

  Future<Database> _completeOpen(Future<Database> opening) async {
    final database = await opening;
    if (_isClosed) {
      throw StateError('AppDatabase was closed while it was opening.');
    }
    _database = database;
    return database;
  }

  Future<void> _close({
    required Future<Database>? opening,
    required Database? current,
  }) async {
    var database = current;
    if (database == null && opening != null) {
      try {
        database = await opening;
      } on Object {
        // A failed open produced no resource to close. Its original caller
        // still owns and observes that opening failure.
        return;
      }
    }
    if (database != null) {
      await _closeConnection(database);
    }
  }

  Future<void> _closeForDisposal() async {
    try {
      await close();
    } on Object catch (error, stackTrace) {
      appLogger.error('database.close.failed', error, stackTrace);
    }
  }

  static Future<Database> _openApplicationDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'akshi.db'),
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) => _createSchema(database),
    );
  }

  static Future<void> _closeApplicationDatabase(Database database) =>
      database.close();

  static Future<void> _createSchema(Database database) async {
    await database.execute('''
      CREATE TABLE domains (
        id TEXT PRIMARY KEY,
        hostname TEXT NOT NULL,
        tls_hostname TEXT NOT NULL,
        tls_port INTEGER NOT NULL,
        checks_certificate INTEGER NOT NULL DEFAULT 0,
        checks_email INTEGER NOT NULL DEFAULT 0,
        label TEXT,
        reminders_enabled INTEGER NOT NULL DEFAULT 1,
        mail_sends INTEGER NOT NULL DEFAULT 1,
        mail_receives INTEGER NOT NULL DEFAULT 1,
        dkim_selectors_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        domain_expires_at TEXT,
        domain_registered_at TEXT,
        domain_updated_at TEXT,
        domain_registrar TEXT,
        domain_public_registrant TEXT,
        domain_nameservers_json TEXT NOT NULL,
        certificate_expires_at TEXT,
        certificate_valid_from TEXT,
        last_attempted_at TEXT,
        last_verified_at TEXT,
        domain_source TEXT,
        certificate_issuer TEXT,
        certificate_subject TEXT,
        certificate_fingerprint TEXT,
        previous_certificate_fingerprint TEXT,
        tls_trusted INTEGER,
        domain_error TEXT,
        certificate_error TEXT,
        domain_activity_json TEXT NOT NULL,
        certificate_activity_json TEXT NOT NULL,
        email_activity_json TEXT NOT NULL,
        certificate_hostname_matches INTEGER,
        certificate_sans_json TEXT NOT NULL,
        certificate_serial_number TEXT,
        certificate_signature_algorithm TEXT,
        certificate_public_key_algorithm TEXT,
        certificate_public_key_details TEXT,
        email_posture_json TEXT,
        dns_snapshot_json TEXT,
        site_icon_format TEXT,
        site_icon_bytes BLOB,
        site_icon_source_url TEXT,
        site_icon_checked_at TEXT
      )
    ''');
    await database.execute(
      'CREATE UNIQUE INDEX domains_hostname ON domains(hostname)',
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
      CREATE TABLE domain_tags (
        domain_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (domain_id, tag_id),
        FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX domain_tags_tag ON domain_tags(tag_id)',
    );
    await database.execute('''
      CREATE TABLE alarm_audit (
        audit_key TEXT PRIMARY KEY,
        alarm_date TEXT NOT NULL,
        notification_id INTEGER NOT NULL,
        revision TEXT NOT NULL,
        scheduled_utc TEXT NOT NULL,
        time_zone_id TEXT NOT NULL,
        requested_time TEXT NOT NULL,
        items_json TEXT NOT NULL,
        domain_count INTEGER NOT NULL,
        reason_count INTEGER NOT NULL,
        domain_reason_count INTEGER NOT NULL,
        tls_reason_count INTEGER NOT NULL,
        computed_at TEXT NOT NULL,
        submitted_at TEXT,
        verified_at TEXT,
        cancelled_at TEXT,
        failed_at TEXT,
        error_category TEXT,
        platform TEXT NOT NULL,
        os_version TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX alarm_audit_date ON alarm_audit(alarm_date DESC)',
    );
    await database.execute(
      'CREATE INDEX alarm_audit_computed ON alarm_audit(computed_at DESC)',
    );
  }
}
