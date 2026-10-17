import 'dart:async';
import 'dart:io';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:akshi/core/services/rdap_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/data/domain_repository.dart';
import 'package:akshi/features/domains/domain/check_result.dart';
import 'package:akshi/features/domains/domain/dns_snapshot.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'controller rejects domain mutations while refresh is running',
    () async {
      final repository = _MemoryDomainRepository();
      final container = ProviderContainer(
        overrides: [domainRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);
      container.read(domainRefreshProvider.notifier).start(total: 1);

      await expectLater(
        container
            .read(domainControllerProvider.notifier)
            .add(
              hostname: 'example.com',
              tlsHostname: 'example.com',
              tlsPort: 443,
            ),
        throwsA(isA<DomainRefreshInProgressException>()),
      );
      expect(repository.createCalled, isFalse);
    },
  );

  test(
    'portfolio refresh uses one batch write and one reminder reconcile',
    () async {
      final repository = _MemoryDomainRepository();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          domainRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);

      final controller = container.read(domainControllerProvider.notifier);
      final first = controller.refreshAll();
      final joined = controller.refreshAll();

      expect(identical(joined, first), isTrue);
      final outcomes = await Future.wait(<Future<DomainRefreshOutcome>>[
        first,
        joined,
      ]);

      expect(outcomes, everyElement(DomainRefreshOutcome.completed));
      expect(repository.portfolioWrites, 1);
      expect(reminders.reconciliations, 1);
      expect(container.read(domainRefreshProvider).isRunning, isFalse);
    },
  );

  test(
    'manual check coalesces source work persistence and reminders',
    () async {
      final domain = DomainEntry(
        id: 'domain-a',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        createdAt: DateTime.utc(2026, 6, 14, 9),
        updatedAt: DateTime.utc(2026, 6, 14, 9),
      );
      final repository = _MemoryDomainRepository(domain: domain);
      final rdap = _ControlledRdapService();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          domainRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);

      final controller = container.read(domainControllerProvider.notifier);
      final first = controller.check(domain.id);
      final joined = controller.check(domain.id);

      expect(identical(joined, first), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(domainCheckActivityProvider),
        containsPair(domain.id, isA<DomainSaveProgress>()),
      );

      rdap.complete();
      await Future.wait(<Future<DomainEntry>>[first, joined]);

      expect(rdap.checks, 1);
      expect(dns.checks, 1);
      expect(repository.observationWrites, 1);
      expect(reminders.reconciliations, 1);
      expect(container.read(domainCheckActivityProvider), isEmpty);
    },
  );

  test(
    'known-offline checks leave every saved observation untouched',
    () async {
      final domain = DomainEntry(
        id: 'domain-offline',
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
      final repository = _MemoryDomainRepository(domain: domain);
      final rdap = _ControlledRdapService();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          domainRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);

      final controller = container.read(domainControllerProvider.notifier);
      expect(
        await controller.refreshAll(),
        DomainRefreshOutcome.skippedOffline,
      );
      await expectLater(
        controller.check(domain.id),
        throwsA(isA<DomainOfflineException>()),
      );

      expect(rdap.checks, 0);
      expect(dns.checks, 0);
      expect(repository.portfolioWrites, 0);
      expect(repository.observationWrites, 0);
      expect(reminders.reconciliations, 0);
      expect(container.read(domainCheckActivityProvider), isEmpty);
      expect(container.read(domainRefreshProvider).lastFailedAt, isNull);
      expect(
        (await repository.byId(domain.id))!.dnsSnapshot,
        same(domain.dnsSnapshot),
      );
    },
  );

  test('offline add is rejected before persistence or provisioning', () async {
    final repository = _MemoryDomainRepository();
    final rdap = _ControlledRdapService();
    final dns = _StaticDnsSnapshotService();
    final container = ProviderContainer(
      overrides: [
        domainRepositoryProvider.overrideWithValue(repository),
        connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
        rdapServiceProvider.overrideWithValue(rdap),
        dnsSnapshotServiceProvider.overrideWithValue(dns),
      ],
    );
    addTearDown(container.dispose);
    await container.read(domainControllerProvider.future);

    await expectLater(
      container
          .read(domainControllerProvider.notifier)
          .add(
            hostname: 'example.com',
            tlsHostname: 'example.com',
            tlsPort: 443,
          ),
      throwsA(
        isA<DomainOfflineException>().having(
          (error) => error.message,
          'message',
          'Device offline. Connect before saving this domain.',
        ),
      ),
    );

    expect(repository.createCalled, isFalse);
    expect(await repository.all(), isEmpty);
    expect(rdap.checks, 0);
    expect(dns.checks, 0);
    expect(repository.observationWrites, 0);
    expect(container.read(domainProvisioningProvider), isEmpty);
  });

  test('offline edit is rejected before persistence', () async {
    final domain = DomainEntry(
      id: 'domain-offline-edit',
      hostname: 'example.com',
      tlsHostname: 'example.com',
      tlsPort: 443,
      label: 'Original',
      createdAt: DateTime.utc(2026, 2, 14, 9),
      updatedAt: DateTime.utc(2026, 6, 14, 9),
    );
    final repository = _MemoryDomainRepository(domain: domain);
    final container = ProviderContainer(
      overrides: [
        domainRepositoryProvider.overrideWithValue(repository),
        connectivitySourceProvider.overrideWithValue(_offlineConnectivity),
      ],
    );
    addTearDown(container.dispose);
    await container.read(domainControllerProvider.future);

    await expectLater(
      container
          .read(domainControllerProvider.notifier)
          .updateDomain(domain.copyWith(label: 'Changed')),
      throwsA(
        isA<DomainOfflineException>().having(
          (error) => error.message,
          'message',
          'Device offline. Connect before saving changes.',
        ),
      ),
    );

    expect(repository.definitionWrites, 0);
    expect((await repository.byId(domain.id))!.label, 'Original');
  });

  test(
    'turning off reminders does not remove a domain from portfolio checks',
    () async {
      final domain = DomainEntry(
        id: 'reminders-off',
        hostname: 'example.com',
        tlsHostname: 'example.com',
        tlsPort: 443,
        remindersEnabled: false,
        createdAt: DateTime.utc(2026, 2, 14, 9),
        updatedAt: DateTime.utc(2026, 6, 14, 9),
      );
      final repository = _MemoryDomainRepository(domain: domain);
      final rdap = _ControlledRdapService()..complete();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          domainRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);

      final outcome = await container
          .read(domainControllerProvider.notifier)
          .refreshAll();

      expect(outcome, DomainRefreshOutcome.completed);
      expect(rdap.checks, 1);
      expect(dns.checks, 1);
      expect(repository.portfolioWrites, 1);
    },
  );

  test(
    'metadata-only edit retains observations and skips external checks',
    () async {
      final domain = DomainEntry(
        id: 'domain-a',
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
      final repository = _MemoryDomainRepository(domain: domain);
      final rdap = _ControlledRdapService()..complete();
      final dns = _StaticDnsSnapshotService();
      final reminders = _RecordingReminderController();
      final container = ProviderContainer(
        overrides: [
          domainRepositoryProvider.overrideWithValue(repository),
          connectivitySourceProvider.overrideWithValue(_onlineConnectivity),
          rdapServiceProvider.overrideWithValue(rdap),
          dnsSnapshotServiceProvider.overrideWithValue(dns),
          reminderControllerProvider.overrideWith(() => reminders),
        ],
      );
      addTearDown(container.dispose);
      await container.read(domainControllerProvider.future);

      final saved = await container
          .read(domainControllerProvider.notifier)
          .updateDomain(
            domain.copyWith(label: 'Production Website'),
            tagIds: const <String>['production'],
          );

      expect(saved.label, 'Production Website');
      expect(saved.domainExpiresAt, domain.domainExpiresAt);
      expect(saved.domainSource, domain.domainSource);
      expect(saved.dnsSnapshot, same(domain.dnsSnapshot));
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

class _MemoryDomainRepository extends DomainRepository {
  _MemoryDomainRepository({this._domain}) : super(AppDatabase());

  DomainEntry? _domain;
  bool createCalled = false;
  int observationWrites = 0;
  int portfolioWrites = 0;
  int definitionWrites = 0;
  List<String>? lastTagIds;

  @override
  Future<List<DomainEntry>> all() async =>
      _domain == null ? const <DomainEntry>[] : <DomainEntry>[_domain!];

  @override
  Future<DomainEntry?> byId(String id) async =>
      _domain?.id == id ? _domain : null;

  @override
  Future<void> update(DomainEntry domain, {Iterable<String>? tagIds}) async {
    definitionWrites++;
    lastTagIds = tagIds?.toList(growable: false);
    _domain = domain;
  }

  @override
  Future<bool> updateObservationsIfPresent(DomainEntry domain) async {
    if (_domain?.id != domain.id) return false;
    observationWrites++;
    _domain = domain;
    return true;
  }

  @override
  Future<void> updateObservationsAtomically(
    Iterable<DomainEntry> domains,
  ) async {
    portfolioWrites++;
  }

  @override
  Future<void> create(
    DomainEntry domain, {
    Iterable<String> tagIds = const <String>[],
  }) async {
    createCalled = true;
    _domain = domain;
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
