import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';

/// Minimal cross-platform request shape needed by the pure reconciler.
class PlatformAlarmRequest {
  const PlatformAlarmRequest({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

/// Platform boundary. Tests use an in-memory fake; production uses the local
/// notifications plugin through NotificationService.
abstract interface class AlarmPlatformGateway {
  Future<List<PlatformAlarmRequest>> pendingAlarms();
  Future<void> scheduleAlarm(ExpiryAlarmSpec alarm);
  Future<void> cancelAlarm(int id);
  Future<void> cancelAllAlarms();
}

enum AlarmReconcileError {
  inventoryUnavailable,
  platformWriteFailed,
  verificationFailed,
  auditUnavailable,
}

class AlarmReconcileResult {
  const AlarmReconcileResult({
    required this.healthy,
    required this.desiredCount,
    required this.pendingCount,
    required this.created,
    required this.replaced,
    required this.deleted,
    required this.repaired,
    required this.verifiedAt,
    this.nextAlarmDate,
    this.error,
  });

  final bool healthy;
  final int desiredCount;
  final int pendingCount;
  final int created;
  final int replaced;
  final int deleted;
  final bool repaired;
  final DateTime verifiedAt;
  final AlarmDate? nextAlarmDate;
  final AlarmReconcileError? error;
}

/// Makes the platform adapter's observed inventory equal the pure desired plan.
///
/// Normal operation is incremental. A full owned-alarm rebuild happens only
/// once when inventory is malformed/duplicated or verification fails. Every
/// platform handoff is written to the non-authoritative audit trail.
class AlarmReconciler {
  AlarmReconciler(
    this._platform,
    this._audit, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AlarmPlatformGateway _platform;
  final AlarmAuditTrail _audit;
  final DateTime Function() _clock;

  Future<AlarmReconcileResult> reconcile(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
  ) async {
    if (!await _recordComputed(desired)) {
      return _failure(desired, AlarmReconcileError.auditUnavailable);
    }

    late final _AlarmInventory initial;
    try {
      initial = _AlarmInventory.read(await _platform.pendingAlarms());
    } on Object {
      return _failure(desired, AlarmReconcileError.inventoryUnavailable);
    }

    if (initial.isCorrupt) {
      return _repair(desired, initial: initial, auditRecorded: true);
    }

    final comparisons = compareAlarmPlans(
      current: initial.byDate,
      desired: desired,
    );
    var created = 0;
    var replaced = 0;
    var deleted = 0;

    for (final comparison in comparisons) {
      if (comparison.change != AlarmChange.replace) continue;
      final writeError = await _schedule(comparison.desired!);
      if (writeError != null) {
        return _failure(
          desired,
          writeError,
          pendingCount: initial.byDate.length,
          created: created,
          replaced: replaced,
          deleted: deleted,
        );
      }
      replaced++;
    }
    for (final comparison in comparisons) {
      if (comparison.change != AlarmChange.delete) continue;
      final writeError = await _cancel(comparison.current!.id);
      if (writeError != null) {
        return _failure(
          desired,
          writeError,
          pendingCount: initial.byDate.length,
          created: created,
          replaced: replaced,
          deleted: deleted,
        );
      }
      deleted++;
    }
    for (final comparison in comparisons) {
      if (comparison.change != AlarmChange.create) continue;
      final writeError = await _schedule(comparison.desired!);
      if (writeError != null) {
        return _failure(
          desired,
          writeError,
          pendingCount: initial.byDate.length,
          created: created,
          replaced: replaced,
          deleted: deleted,
        );
      }
      created++;
    }

    final verification = await _readInventory();
    if (verification != null && _matches(verification, desired)) {
      if (!await _recordVerified(desired)) {
        return _failure(
          desired,
          AlarmReconcileError.auditUnavailable,
          pendingCount: verification.byDate.length,
          created: created,
          replaced: replaced,
          deleted: deleted,
        );
      }
      return _success(
        desired,
        pendingCount: verification.byDate.length,
        created: created,
        replaced: replaced,
        deleted: deleted,
      );
    }

    // Incremental writes did not converge. One bounded repair is allowed.
    return _repair(
      desired,
      initial: verification ?? initial,
      auditRecorded: true,
    );
  }

  /// User-invoked recovery using the same single bounded rebuild.
  Future<AlarmReconcileResult> repair(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
  ) async => _repair(desired);

  Future<AlarmReconcileResult> _repair(
    Map<AlarmDate, ExpiryAlarmSpec> desired, {
    _AlarmInventory? initial,
    bool auditRecorded = false,
  }) async {
    if (!auditRecorded && !await _recordComputed(desired)) {
      return _failure(
        desired,
        AlarmReconcileError.auditUnavailable,
        repaired: true,
      );
    }

    var inventory = initial;
    try {
      inventory ??= _AlarmInventory.read(await _platform.pendingAlarms());
      final ownedIds = inventory.ownedIds.toList()..sort();
      for (final id in ownedIds) {
        final writeError = await _cancel(id);
        if (writeError != null) {
          return _failure(
            desired,
            writeError,
            repaired: true,
          );
        }
      }
    } on Object {
      // Akshi currently has one notification family. The broad cancellation is
      // permitted only when a repair cannot determine the owned inventory.
      try {
        await _platform.cancelAllAlarms();
      } on Object {
        return _failure(
          desired,
          AlarmReconcileError.platformWriteFailed,
          repaired: true,
        );
      }
    }

    final dates = desired.keys.toList()..sort();
    for (final date in dates) {
      final writeError = await _schedule(desired[date]!);
      if (writeError != null) {
        return _failure(
          desired,
          writeError,
          repaired: true,
        );
      }
    }

    final verification = await _readInventory();
    if (verification == null) {
      await _recordFailures(desired, AlarmReconcileError.inventoryUnavailable);
      return _failure(
        desired,
        AlarmReconcileError.inventoryUnavailable,
        repaired: true,
      );
    }
    if (!_matches(verification, desired)) {
      await _recordFailures(desired, AlarmReconcileError.verificationFailed);
      return _failure(
        desired,
        AlarmReconcileError.verificationFailed,
        pendingCount: verification.byDate.length,
        repaired: true,
      );
    }
    if (!await _recordVerified(desired)) {
      return _failure(
        desired,
        AlarmReconcileError.auditUnavailable,
        pendingCount: verification.byDate.length,
        repaired: true,
      );
    }
    return _success(
      desired,
      pendingCount: verification.byDate.length,
      created: desired.length,
      repaired: true,
    );
  }

  Future<AlarmReconcileError?> _schedule(ExpiryAlarmSpec alarm) async {
    try {
      await _platform.scheduleAlarm(alarm);
    } on Object {
      try {
        await _audit.recordFailure(
          alarm,
          AlarmReconcileError.platformWriteFailed.name,
          _clock(),
        );
      } on Object {
        // The platform error remains the primary failure.
      }
      return AlarmReconcileError.platformWriteFailed;
    }
    try {
      await _audit.recordSubmitted(alarm, _clock());
      return null;
    } on Object {
      return AlarmReconcileError.auditUnavailable;
    }
  }

  Future<AlarmReconcileError?> _cancel(int id) async {
    try {
      await _platform.cancelAlarm(id);
    } on Object {
      return AlarmReconcileError.platformWriteFailed;
    }
    try {
      await _audit.recordCancelled(id, _clock());
      return null;
    } on Object {
      return AlarmReconcileError.auditUnavailable;
    }
  }

  Future<bool> _recordComputed(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
  ) async {
    try {
      await _audit.recordComputed(desired.values, _clock());
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _recordVerified(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
  ) async {
    try {
      await _audit.recordVerified(desired.values, _clock());
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _recordFailures(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
    AlarmReconcileError error,
  ) async {
    for (final alarm in desired.values) {
      try {
        await _audit.recordFailure(alarm, error.name, _clock());
      } on Object {
        return;
      }
    }
  }

  Future<_AlarmInventory?> _readInventory() async {
    try {
      return _AlarmInventory.read(await _platform.pendingAlarms());
    } on Object {
      return null;
    }
  }

  bool _matches(
    _AlarmInventory inventory,
    Map<AlarmDate, ExpiryAlarmSpec> desired,
  ) =>
      !inventory.isCorrupt &&
      compareAlarmPlans(
        current: inventory.byDate,
        desired: desired,
      ).every((comparison) => !comparison.isDirty);

  AlarmReconcileResult _success(
    Map<AlarmDate, ExpiryAlarmSpec> desired, {
    required int pendingCount,
    int created = 0,
    int replaced = 0,
    int deleted = 0,
    bool repaired = false,
  }) => AlarmReconcileResult(
    healthy: true,
    desiredCount: desired.length,
    pendingCount: pendingCount,
    created: created,
    replaced: replaced,
    deleted: deleted,
    repaired: repaired,
    verifiedAt: _clock(),
    nextAlarmDate: desired.keys.isEmpty
        ? null
        : (desired.keys.toList()..sort()).first,
  );

  AlarmReconcileResult _failure(
    Map<AlarmDate, ExpiryAlarmSpec> desired,
    AlarmReconcileError error, {
    int pendingCount = 0,
    int created = 0,
    int replaced = 0,
    int deleted = 0,
    bool repaired = false,
  }) => AlarmReconcileResult(
    healthy: false,
    desiredCount: desired.length,
    pendingCount: pendingCount,
    created: created,
    replaced: replaced,
    deleted: deleted,
    repaired: repaired,
    verifiedAt: _clock(),
    nextAlarmDate: desired.keys.isEmpty
        ? null
        : (desired.keys.toList()..sort()).first,
    error: error,
  );
}

class _AlarmInventory {
  const _AlarmInventory({
    required this.byDate,
    required this.ownedIds,
    required this.isCorrupt,
  });

  final Map<AlarmDate, ObservedExpiryAlarm> byDate;
  final Set<int> ownedIds;
  final bool isCorrupt;

  factory _AlarmInventory.read(Iterable<PlatformAlarmRequest> requests) {
    final byDate = <AlarmDate, ObservedExpiryAlarm>{};
    final ownedIds = <int>{};
    var corrupt = false;
    for (final request in requests) {
      if (!ExpiryAlarmSpec.ownsNotificationId(request.id)) continue;
      ownedIds.add(request.id);
      final alarm = ObservedExpiryAlarm.tryParse(
        id: request.id,
        title: request.title,
        body: request.body,
        payload: request.payload,
      );
      if (alarm == null || byDate.containsKey(alarm.date)) {
        corrupt = true;
        continue;
      }
      byDate[alarm.date] = alarm;
    }
    return _AlarmInventory(
      byDate: Map<AlarmDate, ObservedExpiryAlarm>.unmodifiable(byDate),
      ownedIds: Set<int>.unmodifiable(ownedIds),
      isCorrupt: corrupt,
    );
  }
}
