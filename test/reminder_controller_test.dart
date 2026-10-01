import 'package:akshi/app/providers.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/data/settings_repository.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed reconciliation preserves the last verified time', () async {
    final verifiedAt = DateTime.utc(2026, 6, 14, 9);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FailingSettingsRepository(),
        ),
        reminderControllerProvider.overrideWith(
          () => _PreviouslyVerifiedReminderController(verifiedAt),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(reminderControllerProvider.notifier)
        .reconcile();

    expect(result.kind, ReminderHealthKind.needsAttention);
    expect(result.lastVerifiedAt, verifiedAt);
  });
}

class _FailingSettingsRepository extends SettingsRepository {
  @override
  Future<AppSettings> load() =>
      Future<AppSettings>.error(StateError('Settings unavailable'));
}

class _PreviouslyVerifiedReminderController extends ReminderController {
  _PreviouslyVerifiedReminderController(this.verifiedAt);

  final DateTime verifiedAt;

  @override
  ReminderHealth build() => ReminderHealth(
    kind: ReminderHealthKind.ready,
    permission: NotificationPermissionStatus.allowed,
    lastVerifiedAt: verifiedAt,
  );
}
