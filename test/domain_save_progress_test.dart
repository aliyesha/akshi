import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with a clear preparation message', () {
    const progress = DomainSaveProgress.initial();

    expect(progress.stage, DomainSaveStage.preparing);
    expect(progress.message, 'Preparing domain…');
    expect(progress.fraction, 0);
  });

  test('save stages expose an ordered, human-readable contract', () {
    const stages = <DomainSaveStage>[
      DomainSaveStage.certificate,
      DomainSaveStage.domain,
      DomainSaveStage.icon,
      DomainSaveStage.dns,
      DomainSaveStage.email,
      DomainSaveStage.saving,
      DomainSaveStage.refreshing,
      DomainSaveStage.complete,
    ];
    const progress = DomainSaveProgress(
      stage: DomainSaveStage.dns,
      message: 'Reading DNS records…',
      fraction: .62,
    );

    expect(stages.indexOf(progress.stage), 3);
    expect(progress.message, contains('DNS'));
    expect(progress.fraction, inInclusiveRange(0, 1));
  });
}
