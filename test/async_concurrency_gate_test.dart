import 'dart:async';

import 'package:akshi/core/services/async_concurrency_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('grows with submitted work but never exceeds its ceiling', () async {
    final gate = AsyncConcurrencyGate(maximum: 2);
    final releases = List<Completer<void>>.generate(
      3,
      (_) => Completer<void>(),
    );
    final started = <int>[];
    var active = 0;
    var peak = 0;

    Future<void> task(int index) => gate.run(() async {
      started.add(index);
      active++;
      if (active > peak) peak = active;
      await releases[index].future;
      active--;
    });

    final operations = <Future<void>>[task(0), task(1), task(2)];
    await Future<void>.delayed(Duration.zero);

    expect(started, <int>[0, 1]);
    expect(active, 2);
    expect(peak, 2);
    expect(gate.waitingCount, 1);

    releases[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, <int>[0, 1, 2]);
    expect(active, 2);
    expect(peak, 2);

    releases[1].complete();
    releases[2].complete();
    await Future.wait(operations);
    expect(gate.activeCount, 0);
    expect(gate.waitingCount, 0);
  });

  test('releases a slot when an operation throws', () async {
    final gate = AsyncConcurrencyGate(maximum: 1);

    await expectLater(
      gate.run<void>(() => Future<void>.error(StateError('failed'))),
      throwsStateError,
    );
    expect(await gate.run(() async => 42), 42);
    expect(gate.activeCount, 0);
  });
}
