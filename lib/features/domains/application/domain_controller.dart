import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/domains/domain/dns_snapshot.dart';
import 'package:akshi/features/domains/domain/hostname.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/site_icon.dart';
import 'package:akshi/features/domains/domain/tls_endpoint.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final domainControllerProvider =
    AsyncNotifierProvider<DomainController, List<DomainEntry>>(
      DomainController.new,
    );

/// One process-lifetime view of the active portfolio refresh.
class DomainRefreshState {
  const DomainRefreshState.idle({this.lastCompletedAt, this.lastFailedAt})
    : startedAt = null,
      completed = 0,
      total = 0;

  const DomainRefreshState.running({
    required this.startedAt,
    required this.completed,
    required this.total,
    this.lastCompletedAt,
    this.lastFailedAt,
  });

  final DateTime? startedAt;
  final DateTime? lastCompletedAt;
  final DateTime? lastFailedAt;
  final int completed;
  final int total;

  bool get isRunning => startedAt != null;

  bool get isFinalizing => isRunning && total > 0 && completed >= total;

  bool get hasUnresolvedFailure => !isRunning && lastFailedAt != null;

  bool get shouldShowStatus => isRunning || hasUnresolvedFailure;

  double? get fraction => total == 0 ? null : completed / total;

  bool completedWithin(Duration maximumAge, {DateTime? now}) {
    final completedAt = lastCompletedAt;
    if (completedAt == null) return false;
    final age = (now ?? DateTime.now()).difference(completedAt);
    return !age.isNegative && age < maximumAge;
  }
}

/// Publishes portfolio-refresh progress without replacing the saved domain list.
final domainRefreshProvider =
    NotifierProvider<DomainRefreshController, DomainRefreshState>(
      DomainRefreshController.new,
    );

class DomainRefreshController extends Notifier<DomainRefreshState> {
  int _activeMutations = 0;
  Completer<void>? _mutationsDrained;

  @override
  DomainRefreshState build() => const DomainRefreshState.idle();

  void start({required int total}) {
    state = DomainRefreshState.running(
      startedAt: DateTime.now(),
      completed: 0,
      total: total,
      lastCompletedAt: state.lastCompletedAt,
      lastFailedAt: state.lastFailedAt,
    );
  }

  void setTotal(int total) {
    if (!state.isRunning) return;
    state = DomainRefreshState.running(
      startedAt: state.startedAt!,
      completed: state.completed > total ? total : state.completed,
      total: total,
      lastCompletedAt: state.lastCompletedAt,
      lastFailedAt: state.lastFailedAt,
    );
  }

  void advance() {
    if (!state.isRunning) return;
    state = DomainRefreshState.running(
      startedAt: state.startedAt!,
      completed: state.completed < state.total
          ? state.completed + 1
          : state.total,
      total: state.total,
      lastCompletedAt: state.lastCompletedAt,
      lastFailedAt: state.lastFailedAt,
    );
  }

  Future<T> runMutation<T>(Future<T> Function() mutation) async {
    if (state.isRunning) {
      throw DomainRefreshInProgressException();
    }

    _activeMutations++;
    try {
      return await mutation();
    } finally {
      _activeMutations--;
      if (_activeMutations == 0) {
        final drained = _mutationsDrained;
        _mutationsDrained = null;
        drained?.complete();
      }
    }
  }

  Future<void> waitForMutations() {
    if (_activeMutations == 0) return Future<void>.value();
    return (_mutationsDrained ??= Completer<void>()).future;
  }

  void finish({required bool succeeded}) {
    final finishedAt = DateTime.now();
    state = DomainRefreshState.idle(
      lastCompletedAt: succeeded ? finishedAt : state.lastCompletedAt,
      lastFailedAt: succeeded ? null : finishedAt,
    );
  }
}

/// A domain command cannot mutate the snapshot during a portfolio refresh.
class DomainRefreshInProgressException extends StateError {
  DomainRefreshInProgressException()
    : super('A domain refresh is already running. Wait for it to finish.');
}

/// A remote-backed domain command was declined because the OS reports no
/// network transport. This is an admission outcome, not a failed observation:
/// callers must leave all saved evidence and verification times unchanged.
class DomainOfflineException extends StateError {
  DomainOfflineException([
    super.message = 'Device offline. Saved results are unchanged.',
  ]);
}

/// The outcome of one portfolio refresh request.
enum DomainRefreshOutcome { completed, skippedRecent, skippedOffline }

/// Ordered stages exposed while a domain is being prepared and saved.
enum DomainSaveStage {
  preparing,
  certificate,
  domain,
  icon,
  dns,
  email,
  saving,
  refreshing,
  complete,
}

/// Human-readable progress state for the add/edit domain form.
class DomainSaveProgress {
  const DomainSaveProgress({
    required this.stage,
    required this.message,
    required this.fraction,
  });

  const DomainSaveProgress.initial()
    : stage = DomainSaveStage.preparing,
      message = 'Preparing domain…',
      fraction = 0;

  const DomainSaveProgress.checking()
    : stage = DomainSaveStage.preparing,
      message = 'Starting domain check…',
      fraction = 0;

  final DomainSaveStage stage;
  final String message;
  final double fraction;
}

typedef DomainProgressCallback = void Function(DomainSaveProgress progress);

/// Cross-screen state for a domain's initial background snapshot.
class DomainProvisioning {
  const DomainProvisioning({required this.progress, this.failure});

  final DomainSaveProgress progress;
  final String? failure;

  bool get isRunning => failure == null;
}

final domainProvisioningProvider =
    NotifierProvider<
      DomainProvisioningController,
      Map<String, DomainProvisioning>
    >(DomainProvisioningController.new);

class DomainProvisioningController
    extends Notifier<Map<String, DomainProvisioning>> {
  @override
  Map<String, DomainProvisioning> build() =>
      const <String, DomainProvisioning>{};

  void update(String domainId, DomainSaveProgress progress) {
    state = <String, DomainProvisioning>{
      ...state,
      domainId: DomainProvisioning(progress: progress),
    };
  }

  void fail(String domainId, DomainSaveProgress progress, Object error) {
    state = <String, DomainProvisioning>{
      ...state,
      domainId: DomainProvisioning(
        progress: progress,
        failure: error.toString(),
      ),
    };
  }

  void clear(String domainId) {
    if (!state.containsKey(domainId)) return;
    final next = <String, DomainProvisioning>{...state}..remove(domainId);
    state = next;
  }
}

/// Cross-screen activity for complete manual domain checks.
final domainCheckActivityProvider =
    NotifierProvider<
      DomainCheckActivityController,
      Map<String, DomainSaveProgress>
    >(DomainCheckActivityController.new);

class DomainCheckActivityController
    extends Notifier<Map<String, DomainSaveProgress>> {
  @override
  Map<String, DomainSaveProgress> build() =>
      const <String, DomainSaveProgress>{};

  void start(String domainId) {
    if (state.containsKey(domainId)) return;
    state = Map<String, DomainSaveProgress>.unmodifiable(
      <String, DomainSaveProgress>{
        ...state,
        domainId: const DomainSaveProgress.checking(),
      },
    );
  }

  void update(String domainId, DomainSaveProgress progress) {
    if (!state.containsKey(domainId)) return;
    state = Map<String, DomainSaveProgress>.unmodifiable(
      <String, DomainSaveProgress>{...state, domainId: progress},
    );
  }

  void finish(String domainId) {
    if (!state.containsKey(domainId)) return;
    final next = <String, DomainSaveProgress>{...state}..remove(domainId);
    state = Map<String, DomainSaveProgress>.unmodifiable(next);
  }
}

/// Coordinates domain definitions, foreground checks, persistence, and alerts.
class DomainController extends AsyncNotifier<List<DomainEntry>> {
  static const _lifecycleRefreshMaximumAge = Duration(minutes: 15);

  Future<DomainRefreshOutcome>? _refreshOperation;
  final Map<String, Future<DomainEntry>> _manualCheckOperations =
      <String, Future<DomainEntry>>{};
  final Map<String, Future<DomainEntry>> _checkOperations =
      <String, Future<DomainEntry>>{};

  /// Loads the complete domain list from SQLite when the provider is first read.
  @override
  Future<List<DomainEntry>> build() =>
      ref.watch(domainRepositoryProvider).all();

  /// Persists a complete definition, then starts its initial snapshot.
  ///
  /// Navigation never waits for network sources. Selected checks join in memory
  /// and replace the observation fields as one consistent database row.
  Future<DomainEntry> add({
    required String hostname,
    required String tlsHostname,
    required int tlsPort,
    bool checksCertificate = false,
    bool checksEmail = false,
    bool mailSends = true,
    bool mailReceives = true,
    List<String> dkimSelectors = const <String>[],
    String? label,
    Iterable<String> tagIds = const <String>[],
    DomainProgressCallback? onProgress,
  }) => _runCommand(
    () => _add(
      hostname: hostname,
      tlsHostname: tlsHostname,
      tlsPort: tlsPort,
      checksCertificate: checksCertificate,
      checksEmail: checksEmail,
      mailSends: mailSends,
      mailReceives: mailReceives,
      dkimSelectors: dkimSelectors,
      label: label,
      tagIds: tagIds,
      onProgress: onProgress,
    ),
  );

  Future<DomainEntry> _add({
    required String hostname,
    required String tlsHostname,
    required int tlsPort,
    bool checksCertificate = false,
    bool checksEmail = false,
    bool mailSends = true,
    bool mailReceives = true,
    List<String> dkimSelectors = const <String>[],
    String? label,
    Iterable<String> tagIds = const <String>[],
    DomainProgressCallback? onProgress,
  }) async {
    final repository = ref.read(domainRepositoryProvider);
    final now = DateTime.now();
    final validatedTlsPort = requireValidTlsPort(tlsPort);
    final normalizedHostname = normalizeHostname(hostname);
    final normalizedTlsHostname = normalizeHostname(tlsHostname);
    final flow = appLogger.start(
      'domain.add',
      data: <String, Object?>{
        'hostname': normalizedHostname,
        'tlsHostname': normalizedTlsHostname.isEmpty
            ? normalizedHostname
            : normalizedTlsHostname,
        'tlsPort': validatedTlsPort,
        'checksCertificate': checksCertificate,
        'checksEmail': checksEmail,
      },
    );
    final domain = DomainEntry(
      id: const Uuid().v4(),
      hostname: normalizedHostname,
      tlsHostname: normalizedTlsHostname.isEmpty
          ? normalizedHostname
          : normalizedTlsHostname,
      tlsPort: validatedTlsPort,
      checksCertificate: checksCertificate,
      checksEmail: checksEmail,
      mailSends: mailSends,
      mailReceives: mailReceives,
      dkimSelectors: dkimSelectors,
      label: label?.trim().isEmpty == true ? null : label?.trim(),
      createdAt: now,
      updatedAt: now,
    );

    await _requireNetworkTransport(
      message: 'Device offline. Connect before saving this domain.',
    );

    onProgress?.call(
      _progress(DomainSaveStage.saving, 'Saving domain definition…', .35),
    );
    flow.info('persistence.started');
    try {
      // The definition and tag links are one SQLite transaction. It is complete
      // and navigable even if every external source is slow or unavailable.
      await repository.create(domain, tagIds: tagIds);
      await _reload();
    } catch (error, stackTrace) {
      flow.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    flow.info('persistence.succeeded');

    final initialProgress = _progress(
      DomainSaveStage.preparing,
      'Starting initial checks…',
      .05,
    );
    ref
        .read(domainProvisioningProvider.notifier)
        .update(domain.id, initialProgress);
    onProgress?.call(
      _progress(
        DomainSaveStage.complete,
        'Saved. Initial checks will continue on the summary.',
        1,
      ),
    );

    // Navigation must not wait on the network. This task owns all errors and
    // publishes its state so no asynchronous failure becomes unobserved.
    unawaited(_runInitialCheck(domain.id, flow: flow));
    return domain;
  }

  Future<void> _runInitialCheck(
    String domainId, {
    required AppLogFlow flow,
  }) async {
    final provisioning = ref.read(domainProvisioningProvider.notifier);
    try {
      final domain = await ref.read(domainRepositoryProvider).byId(domainId);
      if (domain == null) {
        provisioning.clear(domainId);
        return;
      }
      final updated = await _runCheck(
        domain,
        flow: flow,
        onProgress: (progress) => provisioning.update(domainId, progress),
      );
      final persisted = await ref
          .read(domainRepositoryProvider)
          .updateObservationsIfPresent(updated);
      if (!persisted) {
        provisioning.clear(domainId);
        return;
      }
      final published = await _reload(unlessRefreshing: true);
      if (published) {
        await _rescheduleReminders(flow: flow);
      }
      provisioning.clear(domainId);
      flow.info('initial_check.completed');
    } catch (error, stackTrace) {
      flow.error('initial_check.failed', error, stackTrace);
      provisioning.fail(
        domainId,
        _progress(
          DomainSaveStage.preparing,
          'Initial check could not finish',
          0,
        ),
        error,
      );
    }
  }

  /// Saves an edited definition and clears stale results when its check inputs
  /// changed. Label and tag edits retain the latest verified observations.
  Future<DomainEntry> updateDomain(
    DomainEntry domain, {
    Iterable<String>? tagIds,
    DomainProgressCallback? onProgress,
  }) => _runCommand(
    () => _updateDomain(domain, tagIds: tagIds, onProgress: onProgress),
  );

  Future<DomainEntry> _updateDomain(
    DomainEntry domain, {
    Iterable<String>? tagIds,
    DomainProgressCallback? onProgress,
  }) async {
    requireValidTlsPort(domain.tlsPort);
    await _requireNetworkTransport(
      message: 'Device offline. Connect before saving changes.',
    );
    final repository = ref.read(domainRepositoryProvider);
    final flow = appLogger.start(
      'domain.update',
      data: <String, Object?>{
        'domainId': domain.id,
        'hostname': domain.hostname,
        'tlsHostname': domain.tlsHostname,
        'tlsPort': domain.tlsPort,
        'checksCertificate': domain.checksCertificate,
        'checksEmail': domain.checksEmail,
      },
    );
    final existing = await repository.byId(domain.id);
    final checkDefinitionChanged =
        existing != null &&
        (existing.hostname != domain.hostname ||
            existing.tlsHostname != domain.tlsHostname ||
            existing.tlsPort != domain.tlsPort ||
            existing.checksCertificate != domain.checksCertificate ||
            existing.checksEmail != domain.checksEmail ||
            existing.mailSends != domain.mailSends ||
            existing.mailReceives != domain.mailReceives ||
            !_sameStrings(existing.dkimSelectors, domain.dkimSelectors));
    final updated = checkDefinitionChanged
        ? DomainEntry(
            id: domain.id,
            hostname: domain.hostname,
            tlsHostname: domain.tlsHostname,
            tlsPort: domain.tlsPort,
            checksCertificate: domain.checksCertificate,
            checksEmail: domain.checksEmail,
            mailSends: domain.mailSends,
            mailReceives: domain.mailReceives,
            dkimSelectors: domain.dkimSelectors,
            label: domain.label,
            remindersEnabled: domain.remindersEnabled,
            tags: domain.tags,
            createdAt: domain.createdAt,
            updatedAt: DateTime.now(),
          )
        : domain.copyWith(updatedAt: DateTime.now());
    late final DomainEntry prepared;
    if (checkDefinitionChanged) {
      onProgress?.call(
        _progress(
          DomainSaveStage.preparing,
          'Preparing ${updated.hostname}…',
          .04,
        ),
      );
      try {
        prepared = await _prepareCheck(
          updated,
          onProgress: onProgress,
          flow: flow,
        );
      } catch (error, stackTrace) {
        flow.error('checks.prepare.failed', error, stackTrace);
        rethrow;
      }
    } else {
      prepared = updated;
    }
    onProgress?.call(_progress(DomainSaveStage.saving, 'Saving domain…', .88));
    flow.info('persistence.started');
    try {
      await repository.update(prepared, tagIds: tagIds);
    } catch (error, stackTrace) {
      flow.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    flow.info('persistence.succeeded');
    onProgress?.call(
      _progress(DomainSaveStage.refreshing, 'Updating domain list…', .96),
    );
    await _reload();
    await _rescheduleReminders(flow: flow);
    onProgress?.call(_progress(DomainSaveStage.complete, 'Domain ready.', 1));
    return prepared;
  }

  /// Removes a domain, reloads state, and removes its reminder participation.
  Future<void> delete(String id) => _runCommand(() => _delete(id));

  Future<void> _delete(String id) async {
    final flow = appLogger.start(
      'domain.delete',
      data: <String, Object?>{'domainId': id},
    );
    flow.info('persistence.started');
    try {
      await ref.read(domainRepositoryProvider).delete(id);
      ref.read(domainProvisioningProvider.notifier).clear(id);
      await _reload();
      await _rescheduleReminders(flow: flow);
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
  }

  /// Refreshes all saved domains as one coalesced foreground operation.
  ///
  /// Lifecycle callers can skip a recently completed refresh. Explicit user
  /// actions use the default forced behavior.
  Future<DomainRefreshOutcome> refreshAll({bool force = true}) {
    final active = _refreshOperation;
    if (active != null) return active;

    final refresh = ref.read(domainRefreshProvider);
    if (!force && refresh.completedWithin(_lifecycleRefreshMaximumAge)) {
      return Future<DomainRefreshOutcome>.value(
        DomainRefreshOutcome.skippedRecent,
      );
    }

    late final Future<DomainRefreshOutcome> operation;
    operation = _runRefreshAll().whenComplete(() {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
      }
    });
    _refreshOperation = operation;
    return operation;
  }

  /// Prepares every saved domain, then publishes one committed snapshot.
  Future<DomainRefreshOutcome> _runRefreshAll() async {
    final flow = appLogger.start('domain.refresh_all');
    if (!await _hasNetworkTransport()) {
      flow.info('skipped_offline');
      return DomainRefreshOutcome.skippedOffline;
    }
    final refresh = ref.read(domainRefreshProvider.notifier);
    final knownTotal = state.value?.length ?? 0;
    refresh.start(total: knownTotal);
    var succeeded = false;
    try {
      await refresh.waitForMutations();
      final repository = ref.read(domainRepositoryProvider);
      final domains = await repository.all();
      refresh.setTotal(domains.length);
      flow.info(
        'checks.started',
        data: <String, Object?>{'count': domains.length},
      );
      final observations = await Future.wait(
        domains.map((domain) async {
          final updated = await _runCheck(domain, flow: flow);
          refresh.advance();
          return updated;
        }),
      );
      await repository.updateObservationsAtomically(observations);
      await _reload();
      await _rescheduleReminders(flow: flow);
      succeeded = true;
      flow.info('completed', data: <String, Object?>{'count': domains.length});
      return DomainRefreshOutcome.completed;
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    } finally {
      refresh.finish(succeeded: succeeded);
    }
  }

  /// Checks one domain and rebuilds expiry reminders after saving.
  ///
  /// A missing row after the check is reported as a state error rather than
  /// silently reintroducing deleted data.
  Future<DomainEntry> check(String id) {
    final active = _manualCheckOperations[id];
    if (active != null) return active;

    late final Future<DomainEntry> operation;
    operation = _runManualCheck(id).whenComplete(() {
      if (identical(_manualCheckOperations[id], operation)) {
        _manualCheckOperations.remove(id);
      }
    });
    _manualCheckOperations[id] = operation;
    return operation;
  }

  Future<DomainEntry> _runManualCheck(String id) async {
    await _requireNetworkTransport();
    final activity = ref.read(domainCheckActivityProvider.notifier);
    activity.start(id);
    try {
      return await _runCommand(
        () =>
            _check(id, onProgress: (progress) => activity.update(id, progress)),
      );
    } finally {
      activity.finish(id);
    }
  }

  Future<DomainEntry> _check(
    String id, {
    DomainProgressCallback? onProgress,
  }) async {
    final domain = await ref.read(domainRepositoryProvider).byId(id);
    if (domain == null) {
      throw StateError('Domain no longer exists');
    }
    final flow = appLogger.start(
      'domain.check',
      data: <String, Object?>{
        'domainId': domain.id,
        'hostname': domain.hostname,
        'tlsHostname': domain.tlsHostname,
        'tlsPort': domain.tlsPort,
      },
    );
    try {
      final updated = await _runCheck(
        domain,
        flow: flow,
        onProgress: onProgress,
      );
      final persisted = await ref
          .read(domainRepositoryProvider)
          .updateObservationsIfPresent(updated);
      if (!persisted) {
        throw StateError('Domain no longer exists');
      }
      await _reload();
      await _rescheduleReminders(flow: flow);
      flow.info('completed');
      return updated;
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
  }

  /// Runs selected external checks through a dynamic, shared I/O window.
  ///
  /// Domain, DNS, TLS, and site identity are independent and start together.
  /// Email analysis starts after DNS because it consumes that exact snapshot.
  /// All patches join in memory. The caller selects the persistence boundary,
  /// so readers never observe a partially refreshed domain/TLS/Email snapshot.
  Future<DomainEntry> _prepareCheck(
    DomainEntry domain, {
    DomainProgressCallback? onProgress,
    AppLogFlow? flow,
  }) async {
    final attemptedAt = DateTime.now();
    final refreshIcon =
        domain.checksCertificate &&
        (domain.siteIcon == null ||
            (domain.siteIcon!.format != SiteIconFormat.png &&
                domain.siteIcon!.format != SiteIconFormat.svg) ||
            attemptedAt.difference(domain.siteIcon!.checkedAt) >=
                const Duration(days: 7));
    final total =
        2 +
        (domain.checksCertificate ? 1 : 0) +
        (refreshIcon ? 1 : 0) +
        (domain.checksEmail ? 1 : 0);
    var completed = 0;

    Future<_DomainPatch> track(
      Future<_DomainPatch> operation,
      DomainSaveStage stage,
      String label,
    ) async {
      final patch = await operation;
      completed++;
      onProgress?.call(
        _progress(
          stage,
          '$label received · $completed of $total checks',
          .08 + (.72 * completed / total),
        ),
      );
      return patch;
    }

    onProgress?.call(
      _progress(
        DomainSaveStage.preparing,
        'Checking selected sources in parallel…',
        .05,
      ),
    );

    // This single DNS Future is deliberately shared by the DNS observation
    // patch and email analysis. Re-querying would waste gate capacity and could
    // make the two views describe different resolver snapshots.
    final dnsFuture = ref
        .read(dnsSnapshotServiceProvider)
        .check(
          domain.hostname,
          checkEmailSending: domain.checksEmail && domain.mailSends,
          checkEmailReceiving: domain.checksEmail && domain.mailReceives,
          dkimSelectors: domain.dkimSelectors,
        );
    final phaseOne = <Future<_DomainPatch>>[
      track(
        _domainPatch(domain, attemptedAt, flow: flow),
        DomainSaveStage.domain,
        'Domain registration',
      ),
      track(
        dnsFuture.then((snapshot) {
          final reconciled = snapshot.reconcileWith(domain.dnsSnapshot);
          return (DomainEntry current) =>
              current.copyWith(dnsSnapshot: reconciled);
        }),
        DomainSaveStage.dns,
        'DNS',
      ),
      if (domain.checksCertificate)
        track(
          _certificatePatch(domain, attemptedAt, flow: flow),
          DomainSaveStage.certificate,
          'TLS certificate',
        ),
      if (refreshIcon)
        track(
          _siteIconPatch(domain, flow: flow),
          DomainSaveStage.icon,
          'Site identity',
        ),
    ];

    var updated = domain;
    for (final patch in await Future.wait(phaseOne)) {
      updated = patch(updated);
    }
    final dnsSnapshot = await dnsFuture;

    if (domain.checksEmail) {
      final emailPatch = await track(
        _emailPatch(domain, dnsSnapshot, attemptedAt, flow: flow),
        DomainSaveStage.email,
        'Email configuration',
      );
      updated = emailPatch(updated);
    }

    onProgress?.call(
      _progress(DomainSaveStage.saving, 'Saving one consistent snapshot…', .92),
    );
    return updated.completeAttempt(attemptedAt);
  }

  Future<_DomainPatch> _domainPatch(
    DomainEntry domain,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'domain'});
    try {
      final registration = await ref
          .read(checkConcurrencyGateProvider)
          .run(() => ref.read(rdapServiceProvider).check(domain.hostname));
      if (registration == null) {
        throw const FormatException('No registration record was published');
      }
      return (DomainEntry current) => current.copyWith(
        domainExpiresAt: registration.expiresAt,
        domainRegisteredAt: registration.registeredAt,
        domainUpdatedAt: registration.updatedAt,
        domainRegistrar: registration.registrar,
        domainPublicRegistrant: registration.publicRegistrant,
        domainNameServers: registration.nameServers,
        domainSource: registration.source,
        domainActivity: domain.domainActivity.verified(attemptedAt),
        domainError: null,
      );
    } catch (error, stackTrace) {
      flow?.error(
        'check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'stage': 'domain'},
      );
      final failure = await ref
          .read(checkFailureClassifierProvider)
          .classify(
            error,
            occurredAt: attemptedAt,
            source: 'Domain registration source',
          );
      return (DomainEntry current) => current.copyWith(
        domainActivity: domain.domainActivity.failed(failure),
        domainError: failure.message,
      );
    }
  }

  Future<_DomainPatch> _certificatePatch(
    DomainEntry domain,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'tls'});
    try {
      final certificate = await ref
          .read(checkConcurrencyGateProvider)
          .run(
            () => ref
                .read(tlsCheckServiceProvider)
                .check(domain.tlsHostname, domain.tlsPort),
          );
      return (DomainEntry current) => current.copyWith(
        certificateValidFrom: certificate.validFrom,
        certificateExpiresAt: certificate.expiresAt,
        certificateIssuer: certificate.issuer,
        certificateSubject: certificate.subject,
        previousCertificateFingerprint: domain.certificateFingerprint,
        certificateFingerprint: certificate.fingerprint,
        tlsTrusted: certificate.trusted,
        certificateHostnameMatches: certificate.hostnameMatches,
        certificateSubjectAlternativeNames: certificate.subjectAlternativeNames,
        certificateSerialNumber: certificate.serialNumber,
        certificateSignatureAlgorithm: certificate.signatureAlgorithm,
        certificatePublicKeyAlgorithm: certificate.publicKeyAlgorithm,
        certificatePublicKeyDetails: certificate.publicKeyDetails,
        certificateActivity: domain.certificateActivity.verified(attemptedAt),
        certificateError: null,
      );
    } catch (error, stackTrace) {
      flow?.error(
        'check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'stage': 'tls'},
      );
      final failure = await ref
          .read(checkFailureClassifierProvider)
          .classify(
            error,
            occurredAt: attemptedAt,
            source: 'TLS endpoint ${domain.tlsHostname}:${domain.tlsPort}',
            tls: true,
          );
      return (DomainEntry current) => current.copyWith(
        certificateActivity: domain.certificateActivity.failed(failure),
        certificateError: failure.message,
      );
    }
  }

  Future<_DomainPatch> _siteIconPatch(
    DomainEntry domain, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'icon'});
    try {
      final icon = await ref
          .read(checkConcurrencyGateProvider)
          .run(
            () => ref
                .read(siteIconServiceProvider)
                .discover(domain.tlsHostname, domain.tlsPort),
          );
      return icon == null
          ? _identityPatch
          : (DomainEntry current) => current.copyWith(siteIcon: icon);
    } catch (error, stackTrace) {
      flow?.error(
        'check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'stage': 'icon'},
      );
      return _identityPatch;
    }
  }

  Future<_DomainPatch> _emailPatch(
    DomainEntry domain,
    DnsSnapshot dnsSnapshot,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'email'});
    try {
      final email = await ref
          .read(checkConcurrencyGateProvider)
          .run(
            () => ref
                .read(emailPostureServiceProvider)
                .check(
                  dnsSnapshot,
                  domain.hostname,
                  sends: domain.mailSends,
                  receives: domain.mailReceives,
                  dkimSelectors: domain.dkimSelectors,
                ),
          );
      final reconciled = email.reconcileWith(domain.emailPosture);
      return (DomainEntry current) => current.copyWith(
        emailPosture: reconciled,
        emailActivity: reconciled.hasUnavailable
            ? domain.emailActivity.attempted(attemptedAt)
            : domain.emailActivity.verified(attemptedAt),
      );
    } catch (error, stackTrace) {
      flow?.error(
        'check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'stage': 'email'},
      );
      final failure = await ref
          .read(checkFailureClassifierProvider)
          .classify(
            error,
            occurredAt: attemptedAt,
            source: 'Email configuration source',
          );
      return (DomainEntry current) =>
          current.copyWith(emailActivity: domain.emailActivity.failed(failure));
    }
  }

  Future<DomainEntry> _runCheck(
    DomainEntry domain, {
    AppLogFlow? flow,
    DomainProgressCallback? onProgress,
  }) {
    final active = _checkOperations[domain.id];
    if (active != null) return active;

    late final Future<DomainEntry> operation;
    operation = _performCheck(domain, flow: flow, onProgress: onProgress)
        .whenComplete(() {
          if (identical(_checkOperations[domain.id], operation)) {
            _checkOperations.remove(domain.id);
          }
        });
    _checkOperations[domain.id] = operation;
    return operation;
  }

  /// Produces one coherent observation set without writing persistent state.
  Future<DomainEntry> _performCheck(
    DomainEntry domain, {
    AppLogFlow? flow,
    DomainProgressCallback? onProgress,
  }) {
    final trace =
        flow ??
        appLogger.start(
          'domain.check',
          data: <String, Object?>{
            'domainId': domain.id,
            'hostname': domain.hostname,
            'tlsHostname': domain.tlsHostname,
            'tlsPort': domain.tlsPort,
          },
        );
    trace.info('checks.started');
    return _prepareCheck(domain, flow: trace, onProgress: onProgress);
  }

  Future<T> _runCommand<T>(Future<T> Function() command) =>
      ref.read(domainRefreshProvider.notifier).runMutation(command);

  /// Uses the OS transport state only as a conservative admission gate.
  /// A positive Wi-Fi/cellular result does not promise internet access, so
  /// source-specific failures after admission still follow normal atomic
  /// reconciliation. If the platform status itself cannot be read, the
  /// classifier returns false and Akshi permits the check.
  Future<bool> _hasNetworkTransport() async =>
      !await ref.read(checkFailureClassifierProvider).deviceIsOffline;

  Future<void> _requireNetworkTransport({String? message}) async {
    if (!await _hasNetworkTransport()) {
      throw message == null
          ? DomainOfflineException()
          : DomainOfflineException(message);
    }
  }

  /// Rebuilds reminders without turning a saved domain operation into failure.
  Future<void> _rescheduleReminders({required AppLogFlow flow}) async {
    try {
      await ref.read(reminderControllerProvider.notifier).reconcile();
    } catch (error, stackTrace) {
      flow.error('notifications.reconcile.failed', error, stackTrace);
    }
  }

  /// Reloads persisted state unless a portfolio refresh owns publication.
  Future<bool> _reload({bool unlessRefreshing = false}) async {
    final domains = await ref.read(domainRepositoryProvider).all();
    if (unlessRefreshing && ref.read(domainRefreshProvider).isRunning) {
      return false;
    }
    state = AsyncData(domains);
    return true;
  }
}

/// Compares check-definition lists as sets because selector order is not semantic.
bool _sameStrings(List<String> left, List<String> right) {
  final leftValues = left.toSet();
  final rightValues = right.toSet();
  return leftValues.length == rightValues.length &&
      leftValues.every(rightValues.contains);
}

typedef _DomainPatch = DomainEntry Function(DomainEntry current);

DomainEntry _identityPatch(DomainEntry current) => current;

DomainSaveProgress _progress(
  DomainSaveStage stage,
  String message,
  double fraction,
) => DomainSaveProgress(stage: stage, message: message, fraction: fraction);
