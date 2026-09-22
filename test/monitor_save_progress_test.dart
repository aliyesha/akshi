import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with a clear preparation message', () {
    const progress = MonitorSaveProgress.initial();

    expect(progress.stage, MonitorSaveStage.preparing);
    expect(progress.message, 'Preparing monitor…');
    expect(progress.fraction, 0);
  });

  test('save stages expose an ordered, human-readable contract', () {
    const stages = <MonitorSaveStage>[
      MonitorSaveStage.certificate,
      MonitorSaveStage.domain,
      MonitorSaveStage.icon,
      MonitorSaveStage.dns,
      MonitorSaveStage.email,
      MonitorSaveStage.saving,
      MonitorSaveStage.refreshing,
      MonitorSaveStage.complete,
    ];
    const progress = MonitorSaveProgress(
      stage: MonitorSaveStage.dns,
      message: 'Reading DNS records…',
      fraction: .62,
    );

    expect(stages.indexOf(progress.stage), 3);
    expect(progress.message, contains('DNS'));
    expect(progress.fraction, inInclusiveRange(0, 1));
  });
}
