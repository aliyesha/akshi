import 'dart:async';
import 'dart:io';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:akshi/core/services/rdap_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/data/monitor_repository.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);

      final controller = container.read(monitorControllerProvider.notifier);
      final first = controller.refreshAll();
      final joined = controller.refreshAll();

      expect(identical(joined, first), isTrue);
      final outcomes = await Future.wait(<Future<MonitorRefreshOutcome>>[
        first,
        joined,
      ]);

      expect(outcomes, everyElement(MonitorRefreshOutcome.completed));
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
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
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
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(monitorCheckActivityProvider),
        containsPair(monitor.id, isA<MonitorSaveProgress>()),
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
    'known-offline checks leave every saved observation untouched',
    () async {
      final monitor = MonitorEntry(
        id: 'monitor-offline',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        createdAt: DateTime.utc(2026, 2, 14, 9),
        updatedAt: DateTime.utc(2026, 6, 14, 9),
        dnsSnapshot: DnsSnapshot(
          checkedAt: DateTime.utc(2026, 6, 14, 10),
          queries: <DnsQueryResult>[
            DnsQueryResult(
              name: 'example.com',
              type: DnsRecordType.a,
              state: DnsQueryState.answered,
              records: const <DnsRecord>[
                DnsRecord(
                  owner: 'example.com',
                  type: DnsRecordType.a,
                  ttlSeconds: 3600,
                  value: '192.0.2.1',
                ),
              ],
              lastAttemptedAt: DateTime.utc(2026, 6, 14, 10),
              lastVerifiedAt: DateTime.utc(2026, 6, 14, 10),
            ),
          ],
        ),
      );
      final repository = _MemoryMonitorRepository(monitor: monitor);
      final rdap = _ControlledRdapService();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          monitorRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(monitorControllerProvider.future);

      final controller = container.read(monitorControllerProvider.notifier);
      expect(
        await controller.refreshAll(),
        MonitorRefreshOutcome.skippedOffline,
      );
      await expectLater(
        controller.check(monitor.id),
        throwsA(isA<MonitorOfflineException>()),
      );

      expect(rdap.checks, 0);
      expect(dns.checks, 0);
      expect(repository.portfolioWrites, 0);
      expect(repository.observationWrites, 0);
      expect(reminders.reconciliations, 0);
      expect(container.read(monitorCheckActivityProvider), isEmpty);
      expect(container.read(monitorRefreshProvider).lastFailedAt, isNull);
      expect(
        (await repository.byId(monitor.id))!.dnsSnapshot,
        same(monitor.dnsSnapshot),
      );
    },
  );

  test('offline add is rejected before persistence or provisioning', () async {
    final repository = _MemoryMonitorRepository();
    final rdap = _ControlledRdapService();
    final dns = _StaticDnsSnapshotService();
    final container = ProviderContainer(
      overrides: [
        monitorRepositoryProvider.overrideWithValue(repository),
        connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
        rdapServiceProvider.overrideWithValue(rdap),
        dnsSnapshotServiceProvider.overrideWithValue(dns),
      ],
    );
    addTearDown(container.dispose);
    await container.read(monitorControllerProvider.future);

    await expectLater(
      container
          .read(monitorControllerProvider.notifier)
          .add(
            hostname: 'example.com',
            tlsHostname: 'example.com',
            tlsPort: 443,
          ),
      throwsA(
        isA<MonitorOfflineException>().having(
          (error) => error.message,
          'message',
          'Device offline. Connect before saving this monitor.',
        ),
      ),
    );

    expect(repository.createCalled, isFalse);
    expect(await repository.all(), isEmpty);
    expect(rdap.checks, 0);
    expect(dns.checks, 0);
    expect(repository.observationWrites, 0);
    expect(container.read(monitorProvisioningProvider), isEmpty);
  });

  test('offline edit is rejected before persistence', () async {
    final monitor = MonitorEntry(
      id: 'monitor-offline-edit',
      hostname: 'example.com',
      tlsHostname: 'example.com',
      tlsPort: 443,
      label: 'Original',
      createdAt: DateTime.utc(2026, 2, 14, 9),
      updatedAt: DateTime.utc(2026, 6, 14, 9),
    );
    final repository = _MemoryMonitorRepository(monitor: monitor);
    final container = ProviderContainer(
      overrides: [
        monitorRepositoryProvider.overrideWithValue(repository),
        connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
      ],
    );
    addTearDown(container.dispose);
    await container.read(monitorControllerProvider.future);

    await expectLater(
      container
          .read(monitorControllerProvider.notifier)
          .updateMonitor(monitor.copyWith(label: 'Changed')),
      throwsA(
        isA<MonitorOfflineException>().having(
          (error) => error.message,
          'message',
          'Device offline. Connect before saving changes.',
        ),
      ),
    );

    expect(repository.definitionWrites, 0);
    expect((await repository.byId(monitor.id))!.label, 'Original');
  });

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
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
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

const _onlineConnectivity = _StaticConnectivitySource(<ConnectivityResult>[
  ConnectivityResult.wifi,
]);
const _offlineConnectivity = _StaticConnectivitySource(<ConnectivityResult>[
  ConnectivityResult.none,
]);

class _StaticConnectivitySource implements ConnectivitySource {
  const _StaticConnectivitySource(this.states);

  final List<ConnectivityResult> states;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => states;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
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
    _monitor = monitor;
  }
}

class _ControlledRdapService extends RdapService {
  _ControlledRdapService() : super(_UnusedHttpClient());

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

final class _UnusedHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
