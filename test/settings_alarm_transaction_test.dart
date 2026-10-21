import 'package:akshi/app/providers.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/data/settings_repository.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettingsRepository extends SettingsRepository {
  _MemorySettingsRepository(this.current);

  AppSettings current;
  final saved = <AppSettings>[];

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    saved.add(settings);
    current = settings;
  }
}

class _RecordingReminderController extends ReminderController {
  int reconciliations = 0;

  @override
  ReminderHealth build() => const ReminderHealth(
    kind: ReminderHealthKind.off,
    permission: NotificationPermissionStatus.notDetermined,
  );

  @override
  Future<ReminderHealth> reconcile() async {
    reconciliations++;
    const result = ReminderHealth(
      kind: ReminderHealthKind.needsAttention,
      permission: NotificationPermissionStatus.allowed,
    );
    state = result;
    return result;
  }
}

void main() {
  test(
    'reminder choices persist before unhealthy platform status is reported',
    () async {
      final previous = AppSettings();
      final candidate = AppSettings(
        remindersEnabled: true,
        firstWarningDays: 14,
        secondWarningDays: 7,
        notificationHour: 18,
      );
      final repository = _MemorySettingsRepository(previous);
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(settingsControllerProvider.future), previous);
      final health = await container
          .read(settingsControllerProvider.notifier)
          .saveSettings(candidate);

      expect(repository.current, candidate);
      expect(repository.saved, <AppSettings>[candidate]);
      expect(container.read(settingsControllerProvider).value, candidate);
      expect(reminders.reconciliations, 1);
      expect(
        container.read(reminderControllerProvider).kind,
        ReminderHealthKind.needsAttention,
      );
      expect(health?.kind, ReminderHealthKind.needsAttention);
    },
  );

  test('appearance-only changes do not reconcile alarms', () async {
    final previous = AppSettings();
    final candidate = AppSettings(themeMode: AkshiThemeMode.dark);
    final repository = _MemorySettingsRepository(previous);
    final reminders = _RecordingReminderController();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        reminderControllerProvider.overrideWith(() => reminders),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    final health = await container
        .read(settingsControllerProvider.notifier)
        .saveSettings(candidate);

    expect(repository.current, candidate);
    expect(reminders.reconciliations, 0);
    expect(health, isNull);
  });
}
