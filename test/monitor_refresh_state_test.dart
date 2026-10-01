import 'dart:async';

import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh session reports progress without replacing monitor state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(monitorRefreshProvider.notifier);

    controller.start(total: 2);
    controller.advance();

    final running = container.read(monitorRefreshProvider);
    expect(running.isRunning, isTrue);
    expect(running.completed, 1);
    expect(running.total, 2);
    expect(running.fraction, .5);
    controller.advance();
    expect(container.read(monitorRefreshProvider).isFinalizing, isTrue);

    controller.finish(succeeded: true);

    final completed = container.read(monitorRefreshProvider);
    expect(completed.isRunning, isFalse);
    expect(completed.lastCompletedAt, isNotNull);
  });

  test(
    'refresh waits for an active mutation and blocks new mutations',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(monitorRefreshProvider.notifier);
      final mutationStarted = Completer<void>();
      final releaseMutation = Completer<void>();

      final mutation = controller.runMutation(() async {
        mutationStarted.complete();
        await releaseMutation.future;
      });
      await mutationStarted.future;

      controller.start(total: 0);
      var didDrain = false;
      final drained = controller.waitForMutations().then(
        (_) => didDrain = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);
      await expectLater(
        controller.runMutation(() async {}),
        throwsA(isA<MonitorRefreshInProgressException>()),
      );

      releaseMutation.complete();
      await mutation;
      await drained;
      expect(didDrain, isTrue);
      controller.finish(succeeded: false);
    },
  );

  test('freshness uses the latest successful completion only', () {
    final completedAt = DateTime.utc(2026, 6, 14, 9);
    final state = MonitorRefreshState.idle(lastCompletedAt: completedAt);

    expect(
      state.completedWithin(
        const Duration(minutes: 15),
        now: completedAt.add(const Duration(minutes: 14)),
      ),
      isTrue,
    );
    expect(
      state.completedWithin(
        const Duration(minutes: 15),
        now: completedAt.add(const Duration(minutes: 15)),
      ),
      isFalse,
    );
  });

  test('failed refresh keeps the previous successful completion time', () {
    final completedAt = DateTime.utc(2026, 6, 14, 9);
    final container = ProviderContainer(
      overrides: [
        monitorRefreshProvider.overrideWith(
          () => _CompletedRefreshController(completedAt),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(monitorRefreshProvider.notifier);

    controller.start(total: 1);
    controller.finish(succeeded: false);

    final failed = container.read(monitorRefreshProvider);
    expect(failed.lastCompletedAt, completedAt);
    expect(failed.lastFailedAt, isNotNull);
    expect(failed.hasUnresolvedFailure, isTrue);
    expect(failed.shouldShowStatus, isTrue);
  });
}

class _CompletedRefreshController extends MonitorRefreshController {
  _CompletedRefreshController(this.completedAt);

  final DateTime completedAt;

  @override
  MonitorRefreshState build() =>
      MonitorRefreshState.idle(lastCompletedAt: completedAt);
}
