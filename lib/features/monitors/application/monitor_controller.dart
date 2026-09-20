import 'package:akshi/app/providers.dart';
import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final monitorControllerProvider =
    AsyncNotifierProvider<MonitorController, List<MonitorEntry>>(
      MonitorController.new,
    );

class MonitorController extends AsyncNotifier<List<MonitorEntry>> {
  Future<void>? _refreshOperation;

  @override
  Future<List<MonitorEntry>> build() =>
      ref.watch(monitorRepositoryProvider).all();

  Future<MonitorEntry> add({
    required String hostname,
    required int port,
    String? label,
    Iterable<String> tagIds = const <String>[],
  }) async {
    final now = DateTime.now();
    final monitor = MonitorEntry(
      id: const Uuid().v4(),
      hostname: normalizeHostname(hostname),
      port: port,
      label: label?.trim().isEmpty == true ? null : label?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(monitorRepositoryProvider).save(monitor, tagIds: tagIds);
    await ref.read(notificationServiceProvider).requestPermission();
    await _reload();
    return check(monitor.id);
  }

  Future<MonitorEntry> updateMonitor(
    MonitorEntry monitor, {
    Iterable<String>? tagIds,
  }) async {
    final repository = ref.read(monitorRepositoryProvider);
    final existing = await repository.byId(monitor.id);
    final endpointChanged =
        existing != null &&
        (existing.hostname != monitor.hostname ||
            existing.port != monitor.port);
    final updated = endpointChanged
        ? MonitorEntry(
            id: monitor.id,
            hostname: monitor.hostname,
            port: monitor.port,
            label: monitor.label,
            enabled: monitor.enabled,
            tags: monitor.tags,
            createdAt: monitor.createdAt,
            updatedAt: DateTime.now(),
          )
        : monitor.copyWith(updatedAt: DateTime.now());
    await repository.save(updated, tagIds: tagIds);
    await _reload();
    return check(updated.id);
  }

  Future<void> delete(String id) async {
    await ref.read(monitorRepositoryProvider).delete(id);
    await _reload();
    await _rescheduleReminders();
  }

  Future<void> refreshAll() =>
      _refreshOperation ??= _runRefreshAll().whenComplete(() {
        _refreshOperation = null;
      });

  Future<void> _runRefreshAll() async {
    final monitors =
        state.value ?? await ref.read(monitorRepositoryProvider).all();
    final outcomes = await Future.wait(
      monitors.where((monitor) => monitor.enabled).map(_performCheck),
    );
    await _reload();
    await _rescheduleReminders();
    await _notifyChanges(outcomes);
  }

  Future<MonitorEntry> check(String id) async {
    final monitor = await ref.read(monitorRepositoryProvider).byId(id);
    if (monitor == null) throw StateError('Monitor no longer exists');
    final outcome = await _performCheck(monitor);
    await _reload();
    await _rescheduleReminders();
    await _notifyChanges(<_CheckOutcome>[outcome]);
    return outcome.monitor;
  }

  Future<_CheckOutcome> _performCheck(MonitorEntry monitor) async {
    var updated = monitor;
    String? certificateError;
    String? domainError;

    try {
      final certificate = await ref
          .read(tlsCheckServiceProvider)
          .check(monitor.hostname, monitor.port);
      updated = updated.copyWith(
        certificateValidFrom: certificate.validFrom,
        certificateExpiresAt: certificate.expiresAt,
        certificateIssuer: certificate.issuer,
        certificateSubject: certificate.subject,
        previousCertificateFingerprint:
            monitor.certificateFingerprint != null &&
                monitor.certificateFingerprint != certificate.fingerprint
            ? monitor.certificateFingerprint
            : monitor.previousCertificateFingerprint,
        certificateFingerprint: certificate.fingerprint,
        tlsTrusted: certificate.trusted,
      );
    } on Object catch (error) {
      certificateError = _message(error);
    }

    try {
      final domain = await ref
          .read(rdapServiceProvider)
          .check(monitor.hostname);
      if (domain != null) {
        updated = updated.copyWith(
          domainExpiresAt: domain.expiresAt,
          domainSource: domain.source,
        );
      }
    } on Object catch (error) {
      domainError = _message(error);
    }

    updated = updated.copyWith(
      updatedAt: DateTime.now(),
      lastCheckedAt: DateTime.now(),
      domainError: domainError,
      certificateError: certificateError,
    );
    await ref.read(monitorRepositoryProvider).save(updated);

    final certificateChanged =
        monitor.certificateFingerprint != null &&
        monitor.certificateFingerprint != updated.certificateFingerprint;
    final domainChanged =
        monitor.domainExpiresAt != null &&
        monitor.domainExpiresAt != updated.domainExpiresAt;
    return (monitor: updated, changed: certificateChanged || domainChanged);
  }

  Future<void> _notifyChanges(Iterable<_CheckOutcome> outcomes) async {
    final changed = outcomes
        .where((outcome) => outcome.changed)
        .map((outcome) => outcome.monitor);
    await ref.read(notificationServiceProvider).showChanges(changed);
  }

  Future<void> _rescheduleReminders() async {
    final monitors = await ref.read(monitorRepositoryProvider).all();
    final settings =
        ref.read(settingsControllerProvider).value ?? const AppSettings();
    await ref
        .read(notificationServiceProvider)
        .reconcileAll(monitors, settings);
  }

  Future<void> _reload() async {
    state = AsyncData(await ref.read(monitorRepositoryProvider).all());
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '')
      .trim();
}

typedef _CheckOutcome = ({MonitorEntry monitor, bool changed});
