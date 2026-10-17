import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual check activity is shared by domain ID', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(domainCheckActivityProvider.notifier);

    expect(container.read(domainCheckActivityProvider), isEmpty);

    controller.start('domain-a');
    controller.start('domain-a');
    controller.start('domain-b');

    final started = container.read(domainCheckActivityProvider);
    expect(started.keys, unorderedEquals(<String>['domain-a', 'domain-b']));
    expect(started['domain-a']?.message, 'Starting domain check…');

    const progress = DomainSaveProgress(
      stage: DomainSaveStage.dns,
      message: 'DNS received · 1 of 2 checks',
      fraction: .44,
    );
    controller.update('domain-b', progress);
    controller.update('unknown', progress);

    expect(container.read(domainCheckActivityProvider)['domain-b'], progress);

    controller.finish('domain-a');
    controller.finish('domain-a');

    expect(
      container.read(domainCheckActivityProvider).keys,
      unorderedEquals(<String>['domain-b']),
    );

    controller.finish('domain-b');
    expect(container.read(domainCheckActivityProvider), isEmpty);
  });
}
