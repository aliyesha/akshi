import 'package:akshi/app/providers.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  Future<void> _saveTail = Future<void>.value();

  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  /// Persists the user's choice first, then reconciles platform alarms.
  ///
  /// Preferences and OS alarms cannot form one transaction. Rolling the user's
  /// choice back after a platform failure is misleading, so reminder health
  /// owns that failure and gives the user a deterministic Repair action.
  Future<ReminderHealth?> saveSettings(AppSettings value) {
    final request = _saveTail.then((_) => _commitSettings(value));
    _saveTail = request.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return request;
  }

  /// Returns the verified platform result when alarm-affecting values changed.
  /// Appearance-only saves return null because no reconciliation was needed.
  Future<ReminderHealth?> _commitSettings(AppSettings value) async {
    final repository = ref.read(settingsRepositoryProvider);
    final previous = state.value ?? await repository.load();
    await repository.save(value);
    state = AsyncData(value);

    if (!previous.hasSameReminderSchedule(value)) {
      return ref.read(reminderControllerProvider.notifier).reconcile();
    }
    return null;
  }
}
