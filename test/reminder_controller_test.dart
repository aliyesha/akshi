import 'package:akshi/app/providers.dart';
import 'package:akshi/core/services/notification_service.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/alarm_reconciler.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:akshi/features/settings/data/settings_repository.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aliyesha.akshi/system_settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

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

  test('missing permission remains the primary recovery action', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'notificationPermissionStatus') {
        return 'notDetermined';
      }
      return true;
    });
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _EnabledSettingsRepository(),
        ),
        alarmReconcilerProvider.overrideWithValue(
          AlarmReconciler(
            _UnavailableAlarmGateway(),
            const NoOpAlarmAuditTrail(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(reminderControllerProvider.notifier)
        .reconcile();

    expect(result.kind, ReminderHealthKind.permissionNeeded);
    expect(result.permission, NotificationPermissionStatus.notDetermined);
    expect(result.lastError, AlarmReconcileError.inventoryUnavailable);
  });

  test('a later failure retains the freshly observed permission', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'notificationPermissionStatus') return 'allowed';
      return true;
    });
    final notifications = _FailingLocationNotificationService();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _EnabledSettingsRepository(),
        ),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(notifications.dispose);

    final result = await container
        .read(reminderControllerProvider.notifier)
        .reconcile();

    expect(result.kind, ReminderHealthKind.needsAttention);
    expect(result.permission, NotificationPermissionStatus.allowed);
  });
}

class _FailingSettingsRepository extends SettingsRepository {
  @override
  Future<AppSettings> load() =>
      Future<AppSettings>.error(StateError('Settings unavailable'));
}

class _FailingLocationNotificationService extends NotificationService {
  @override
  Future<Never> localLocation() =>
      Future<Never>.error(StateError('Timezone unavailable'));
}

class _EnabledSettingsRepository extends SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings(remindersEnabled: true);
}

class _UnavailableAlarmGateway implements AlarmPlatformGateway {
  @override
  Future<List<PlatformAlarmRequest>> pendingAlarms() =>
      Future<List<PlatformAlarmRequest>>.error(
        StateError('Alarm inventory unavailable'),
      );

  @override
  Future<void> cancelAlarm(int id) async {}

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Future<void> scheduleAlarm(ExpiryAlarmSpec alarm) async {}
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
