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

    expect(container.read(monitorCheckActivityProvider), <String>{
      'monitor-a',
      'monitor-b',
    });

    controller.finish('monitor-a');
    controller.finish('monitor-a');

    expect(container.read(monitorCheckActivityProvider), <String>{'monitor-b'});

    controller.finish('monitor-b');
    expect(container.read(monitorCheckActivityProvider), isEmpty);
  });
}
