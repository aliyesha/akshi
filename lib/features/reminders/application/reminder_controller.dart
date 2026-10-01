import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/alarm_reconciler.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reminderControllerProvider =
    NotifierProvider<ReminderController, ReminderHealth>(
      ReminderController.new,
    );

enum ReminderHealthKind {
  checking,
  off,
  permissionNeeded,
  ready,
  needsAttention,
}

/// Small, sanitized status surface shared by Settings and Diagnostics.
class ReminderHealth {
  const ReminderHealth({
    required this.kind,
    required this.permission,
    this.desiredCount = 0,
    this.pendingCount = 0,
    this.nextAlarmDate,
    this.lastVerifiedAt,
    this.timeZoneId,
    this.lastError,
    this.repaired = false,
  });

  const ReminderHealth.checking()
    : kind = ReminderHealthKind.checking,
      permission = NotificationPermissionStatus.unavailable,
      desiredCount = 0,
      pendingCount = 0,
      nextAlarmDate = null,
      lastVerifiedAt = null,
      timeZoneId = null,
      lastError = null,
      repaired = false;

  final ReminderHealthKind kind;
  final NotificationPermissionStatus permission;
  final int desiredCount;
  final int pendingCount;
  final AlarmDate? nextAlarmDate;
  final DateTime? lastVerifiedAt;
  final String? timeZoneId;
  final AlarmReconcileError? lastError;
  final bool repaired;

  bool get isBusy => kind == ReminderHealthKind.checking;
}

/// Reads fresh persisted state for every request and serializes platform work.
/// CRUD, refresh, settings changes, startup, and resume all call this one path.
class ReminderController extends Notifier<ReminderHealth> {
  Future<ReminderHealth> _tail = Future<ReminderHealth>.value(
    const ReminderHealth.checking(),
  );

  @override
  ReminderHealth build() => const ReminderHealth.checking();

  Future<ReminderHealth> reconcile() => _enqueue(forceRepair: false);

  Future<ReminderHealth> repair() => _enqueue(forceRepair: true);

  Future<ReminderHealth> _enqueue({required bool forceRepair}) {
    final request = _tail.then((_) => _run(forceRepair: forceRepair));
    _tail = request.then(
      (value) => value,
      onError: (Object _, StackTrace _) => state,
    );
    return request;
  }

  Future<ReminderHealth> _run({required bool forceRepair}) async {
    state = ReminderHealth(
      kind: ReminderHealthKind.checking,
      permission: state.permission,
      desiredCount: state.desiredCount,
      pendingCount: state.pendingCount,
      nextAlarmDate: state.nextAlarmDate,
      lastVerifiedAt: state.lastVerifiedAt,
      timeZoneId: state.timeZoneId,
      lastError: state.lastError,
    );
    try {
      final settings = await ref.read(settingsRepositoryProvider).load();
      final permission =
          await SystemSettingsService.notificationPermissionStatus();
      final reconciler = ref.read(alarmReconcilerProvider);

      // Off or denied always means an empty desired plan. This actively clears
      // previously scheduled alarms and verifies that none remain.
      if (!settings.remindersEnabled ||
          permission != NotificationPermissionStatus.allowed) {
        final result = forceRepair
            ? await reconciler.repair(const <AlarmDate, ExpiryAlarmSpec>{})
            : await reconciler.reconcile(const <AlarmDate, ExpiryAlarmSpec>{});
        final kind = !result.healthy
            ? ReminderHealthKind.needsAttention
            : !settings.remindersEnabled
            ? ReminderHealthKind.off
            : ReminderHealthKind.permissionNeeded;
        return _publish(
          ReminderHealth(
            kind: kind,
            permission: permission,
            pendingCount: result.pendingCount,
            lastVerifiedAt: result.verifiedAt,
            lastError: result.error,
            repaired: result.repaired,
          ),
        );
      }

      final notifications = ref.read(notificationServiceProvider);
      final location = await notifications.localLocation();
      final monitors = await ref.read(monitorRepositoryProvider).all();
      final desired = const ExpiryAlarmPlanner().build(
        monitors: monitors,
        settings: settings,
        now: DateTime.now(),
        location: location,
      );
      final result = forceRepair
          ? await reconciler.repair(desired)
          : await reconciler.reconcile(desired);
      return _publish(
        ReminderHealth(
          kind: result.healthy
              ? ReminderHealthKind.ready
              : ReminderHealthKind.needsAttention,
          permission: permission,
          desiredCount: result.desiredCount,
          pendingCount: result.pendingCount,
          nextAlarmDate: result.nextAlarmDate,
          lastVerifiedAt: result.verifiedAt,
          timeZoneId: location.name,
          lastError: result.error,
          repaired: result.repaired,
        ),
      );
    } on Object catch (error, stackTrace) {
      appLogger.error('reminders.reconcile.failed', error, stackTrace);
      return _publish(
        ReminderHealth(
          kind: ReminderHealthKind.needsAttention,
          permission: state.permission,
          desiredCount: state.desiredCount,
          pendingCount: state.pendingCount,
          nextAlarmDate: state.nextAlarmDate,
          lastVerifiedAt: state.lastVerifiedAt,
          timeZoneId: state.timeZoneId,
          lastError: AlarmReconcileError.inventoryUnavailable,
        ),
      );
    }
  }

  ReminderHealth _publish(ReminderHealth value) {
    ref.invalidate(alarmAuditDaysProvider);
    state = value;
    return value;
  }
}
