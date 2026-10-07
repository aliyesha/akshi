import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual check activity is shared by monitor ID', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(monitorCheckActivityProvider.notifier);

    expect(container.read(monitorCheckActivityProvider), isEmpty);

    controller.start('monitor-a');
    controller.start('monitor-a');
    controller.start('monitor-b');

    final started = container.read(monitorCheckActivityProvider);
    expect(started.keys, unorderedEquals(<String>['monitor-a', 'monitor-b']));
    expect(started['monitor-a']?.message, 'Starting monitor check…');

    const progress = MonitorSaveProgress(
      stage: MonitorSaveStage.dns,
      message: 'DNS received · 1 of 2 checks',
      fraction: .44,
    );
    controller.update('monitor-b', progress);
    controller.update('unknown', progress);

    expect(container.read(monitorCheckActivityProvider)['monitor-b'], progress);

    controller.finish('monitor-a');
    controller.finish('monitor-a');

    expect(
      container.read(monitorCheckActivityProvider).keys,
      unorderedEquals(<String>['monitor-b']),
    );

    controller.finish('monitor-b');
    expect(container.read(monitorCheckActivityProvider), isEmpty);
  });
}
