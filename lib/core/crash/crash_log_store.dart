import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/crash/crash_log.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Stores a bounded, private JSON array independently of the domain database.
///
/// Writes use a temporary sibling file followed by rename. Every public
/// operation is best effort so diagnostics can never become a new crash.
class CrashLogStore {
  CrashLogStore({Future<String> Function()? rootPath})
    : _rootPath = rootPath ?? getDatabasesPath;

  static const maxEntries = 50;

  final Future<String> Function() _rootPath;
  Future<void> _mutations = Future<void>.value();

  /// Reads newest-first logs; malformed or missing files are treated as empty.
  Future<List<CrashLog>> read() async {
    try {
      final file = await _file;
      if (!await file.exists()) return const <CrashLog>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <CrashLog>[];
      return decoded
          .whereType<Map>()
          .map((value) => CrashLog.fromMap(Map<String, Object?>.from(value)))
          .toList(growable: false);
    } catch (_) {
      return const <CrashLog>[];
    }
  }

  /// Adds one log and trims older entries to the retention limit.
  Future<void> append(CrashLog log) => _serialize(() async {
    try {
      final entries = <CrashLog>[log, ...await read()];
      await _write(entries.take(maxEntries).toList(growable: false));
    } catch (_) {
      // Crash diagnostics must never interfere with the application.
    }
  });

  /// Deletes exactly one entry selected by the end user.
  Future<void> delete(String id) => _serialize(() async {
    try {
      final entries = await read();
      await _write(entries.where((entry) => entry.id != id).toList());
    } catch (_) {
      // Best effort only.
    }
  });

  /// Removes every locally retained diagnostic.
  Future<void> clear() => _serialize(() async {
    try {
      final file = await _file;
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort only.
    }
  });

  Future<File> get _file async {
    final root = await _rootPath();
    return File(p.join(root, 'akshi_crash_logs.json'));
  }

  /// Runs read-modify-write operations in order so concurrent errors cannot
  /// overwrite one another or contend for the same temporary file.
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _mutations.then((_) => operation());
    _mutations = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  Future<void> _write(List<CrashLog> entries) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(
        entries
            .map((entry) => <String, Object?>{'id': entry.id, ...entry.toMap()})
            .toList(growable: false),
      ),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
