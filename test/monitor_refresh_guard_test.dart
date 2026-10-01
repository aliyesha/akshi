import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/core/services/rdap_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/data/monitor_repository.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller rejects monitor mutations while refresh is running',
    () async {
      final repository = _MemoryMonitorRepository();
      final container = ProviderContainer(
        overrides: [monitorRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);
      container.read(monitorRefreshProvider.notifier).start(total: 1);

      await expectLater(
        container
            .read(monitorControllerProvider.notifier)
            .add(
              hostname: 'example.com',
              tlsHostname: 'example.com',
              tlsPort: 443,
            ),
        throwsA(isA<MonitorRefreshInProgressException>()),
      );
      expect(repository.createCalled, isFalse);
    },
  );

  test(
    'portfolio refresh uses one batch write and one reminder reconcile',
    () async {
      final repository = _MemoryMonitorRepository();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          monitorRepositoryProvider.overrideWithValue(repository),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);

      final controller = container.read(monitorControllerProvider.notifier);
      final first = controller.refreshAll();
      final joined = controller.refreshAll();

      expect(identical(joined, first), isTrue);
      await Future.wait(<Future<void>>[first, joined]);

      expect(repository.portfolioWrites, 1);
      expect(reminders.reconciliations, 1);
      expect(container.read(monitorRefreshProvider).isRunning, isFalse);
    },
  );

  test(
    'manual check coalesces source work persistence and reminders',
    () async {
      final monitor = MonitorEntry(
        id: 'monitor-a',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        createdAt: DateTime.utc(2026, 6, 14, 9),
        updatedAt: DateTime.utc(2026, 6, 14, 9),
      );
      final repository = _MemoryMonitorRepository(monitor: monitor);
      final rdap = _ControlledRdapService();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          monitorRepositoryProvider.overrideWithValue(repository),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);

      final controller = container.read(monitorControllerProvider.notifier);
      final first = controller.check(monitor.id);
      final joined = controller.check(monitor.id);

      expect(identical(joined, first), isTrue);
      expect(
        container.read(monitorCheckActivityProvider),
        contains(monitor.id),
      );

      rdap.complete();
      await Future.wait(<Future<MonitorEntry>>[first, joined]);

      expect(rdap.checks, 1);
      expect(dns.checks, 1);
      expect(repository.observationWrites, 1);
      expect(reminders.reconciliations, 1);
      expect(container.read(monitorCheckActivityProvider), isEmpty);
    },
  );
  test(
    'metadata-only edit retains observations and skips external checks',
    () async {
      final monitor = MonitorEntry(
        id: 'monitor-a',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        label: 'Old name',
        createdAt: DateTime.utc(2026, 2, 14, 9),
        updatedAt: DateTime.utc(2026, 6, 14, 9),
        domainExpiresAt: DateTime.utc(2026, 8, 14, 9),
        domainSource: 'rdap.example',
        dnsSnapshot: DnsSnapshot(
          checkedAt: DateTime.utc(2026, 6, 14, 10),
          queries: const <DnsQueryResult>[],
        ),
      );
      final repository = _MemoryMonitorRepository(monitor: monitor);
      final rdap = _ControlledRdapService()..complete();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          monitorRepositoryProvider.overrideWithValue(repository),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);

      final saved = await container
          .read(monitorControllerProvider.notifier)
          .updateMonitor(
            monitor.copyWith(label: 'Production Website'),
            tagIds: const <String>['production'],
          );

      expect(saved.label, 'Production Website');
      expect(saved.domainExpiresAt, monitor.domainExpiresAt);
      expect(saved.domainSource, monitor.domainSource);
      expect(saved.dnsSnapshot, same(monitor.dnsSnapshot));
      expect(rdap.checks, 0);
      expect(dns.checks, 0);
      expect(repository.definitionWrites, 1);
      expect(repository.lastTagIds, <String>['production']);
      expect(reminders.reconciliations, 1);
    },
  );
}

class _MemoryMonitorRepository extends MonitorRepository {
  _MemoryMonitorRepository({this._monitor}) : super(AppDatabase());

  MonitorEntry? _monitor;
  bool createCalled = false;
  int observationWrites = 0;
  int portfolioWrites = 0;
  int definitionWrites = 0;
  List<String>? lastTagIds;

  @override
  Future<List<MonitorEntry>> all() async =>
      _monitor == null ? const <MonitorEntry>[] : <MonitorEntry>[_monitor!];

  @override
  Future<MonitorEntry?> byId(String id) async =>
      _monitor?.id == id ? _monitor : null;

  @override
  Future<void> update(MonitorEntry monitor, {Iterable<String>? tagIds}) async {
    definitionWrites++;
    lastTagIds = tagIds?.toList(growable: false);
    _monitor = monitor;
  }

  @override
  Future<bool> updateObservationsIfPresent(MonitorEntry monitor) async {
    if (_monitor?.id != monitor.id) return false;
    observationWrites++;
    _monitor = monitor;
    return true;
  }

  @override
  Future<void> updateObservationsAtomically(
    Iterable<MonitorEntry> monitors,
  ) async {
    portfolioWrites++;
  }

  @override
  Future<void> create(
    MonitorEntry monitor, {
    Iterable<String> tagIds = const <String>[],
  }) async {
    createCalled = true;
  }
}

class _ControlledRdapService extends RdapService {
  final _result = Completer<DomainCheckResult?>();
  int checks = 0;

  @override
  Future<DomainCheckResult?> check(String hostname) {
    checks++;
    return _result.future;
  }

  void complete() {
    _result.complete(
      DomainCheckResult(
        expiresAt: DateTime.utc(2026, 8, 14, 9),
        source: 'rdap.example',
        registeredDomain: 'example.com',
        registeredAt: DateTime.utc(2026, 2, 14, 9),
        updatedAt: DateTime.utc(2026, 7, 14, 9),
      ),
    );
  }
}

class _StaticDnsSnapshotService extends DnsSnapshotService {
  int checks = 0;

  @override
  Future<DnsSnapshot> check(
    String domain, {
    required bool checkEmailSending,
    required bool checkEmailReceiving,
    required List<String> dkimSelectors,
  }) async {
    checks++;
    return DnsSnapshot(
      checkedAt: DateTime.utc(2026, 6, 14, 10),
      queries: const <DnsQueryResult>[],
    );
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
    return state;
  }
}
