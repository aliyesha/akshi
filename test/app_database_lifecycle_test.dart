import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('concurrent callers share one open and the cached connection', () async {
    final connection = _FakeDatabase();
    final opening = Completer<Database>();
    var openCalls = 0;
    var closeCalls = 0;
    final database = AppDatabase(
      openConnection: () {
        openCalls++;
        return opening.future;
      },
      closeConnection: (_) async {
        closeCalls++;
      },
    );

    final first = database.instance;
    final joined = database.instance;

    expect(identical(first, joined), isTrue);
    expect(openCalls, 1);

    opening.complete(connection);
    expect(await first, same(connection));
    expect(await joined, same(connection));
    expect(await database.instance, same(connection));
    expect(openCalls, 1);

    await database.close();
    expect(closeCalls, 1);
  });

  test('a failed open can be retried before closure', () async {
    final connection = _FakeDatabase();
    var openCalls = 0;
    final database = AppDatabase(
      openConnection: () {
        openCalls++;
        if (openCalls == 1) {
          return Future<Database>.error(StateError('open failed'));
        }
        return Future<Database>.value(connection);
      },
      closeConnection: (_) async {},
    );

    await expectLater(database.instance, throwsA(isA<StateError>()));
    expect(await database.instance, same(connection));
    expect(openCalls, 2);

    await database.close();
  });

  test('close joins one operation and permanently rejects access', () async {
    final connection = _FakeDatabase();
    final closing = Completer<void>();
    var closeCalls = 0;
    final database = AppDatabase(
      openConnection: () async => connection,
      closeConnection: (_) {
        closeCalls++;
        return closing.future;
      },
    );
    await database.instance;

    final first = database.close();
    final joined = database.close();

    expect(identical(first, joined), isTrue);
    expect(closeCalls, 1);

    closing.complete();
    await first;
    await expectLater(database.instance, throwsA(isA<StateError>()));
    expect(closeCalls, 1);
  });

  test(
    'close during open closes the raw connection before completing',
    () async {
      final connection = _FakeDatabase();
      final opening = Completer<Database>();
      var closeCalls = 0;
      final database = AppDatabase(
        openConnection: () => opening.future,
        closeConnection: (value) async {
          expect(value, same(connection));
          closeCalls++;
        },
      );

      final instanceFailure = expectLater(
        database.instance,
        throwsA(isA<StateError>()),
      );
      final closing = database.close();
      opening.complete(connection);

      await instanceFailure;
      await closing;
      expect(closeCalls, 1);
      await expectLater(database.instance, throwsA(isA<StateError>()));
    },
  );

  test('Riverpod provider disposes its owned database', () async {
    final container = ProviderContainer();
    final database = container.read(databaseProvider);

    container.dispose();
    await Future<void>.delayed(Duration.zero);

    await expectLater(database.instance, throwsA(isA<StateError>()));
  });

  test('dispose owns asynchronous close from a synchronous callback', () async {
    final connection = _FakeDatabase();
    final closed = Completer<void>();
    final database = AppDatabase(
      openConnection: () async => connection,
      closeConnection: (_) async {
        closed.complete();
      },
    );
    await database.instance;

    database.dispose();

    await closed.future;
    await expectLater(database.instance, throwsA(isA<StateError>()));
  });
}

final class _FakeDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
