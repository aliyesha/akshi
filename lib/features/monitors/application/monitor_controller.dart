import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:akshi/features/monitors/domain/tls_endpoint.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final monitorControllerProvider =
    AsyncNotifierProvider<MonitorController, List<MonitorEntry>>(
      MonitorController.new,
    );

/// Ordered stages exposed while a monitor is being prepared and saved.
enum MonitorSaveStage {
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

/// Human-readable progress state for the add/edit monitor form.
class MonitorSaveProgress {
  const MonitorSaveProgress({
    required this.stage,
    required this.message,
    required this.fraction,
  });

  const MonitorSaveProgress.initial()
    : stage = MonitorSaveStage.preparing,
      message = 'Preparing monitor…',
      fraction = 0;

  final MonitorSaveStage stage;
  final String message;
  final double fraction;
}

typedef MonitorProgressCallback = void Function(MonitorSaveProgress progress);

/// Cross-screen state for a monitor's initial background snapshot.
class MonitorProvisioning {
  const MonitorProvisioning({
    required this.progress,
    this.failure,
  });

  final MonitorSaveProgress progress;
  final String? failure;

  bool get isRunning => failure == null;
}

final monitorProvisioningProvider = NotifierProvider<
  MonitorProvisioningController,
  Map<String, MonitorProvisioning>
>(MonitorProvisioningController.new);

class MonitorProvisioningController
    extends Notifier<Map<String, MonitorProvisioning>> {
  @override
  Map<String, MonitorProvisioning> build() =>
      const <String, MonitorProvisioning>{};

  void update(String monitorId, MonitorSaveProgress progress) {
    state = <String, MonitorProvisioning>{
      ...state,
      monitorId: MonitorProvisioning(progress: progress),
    };
  }

  void fail(String monitorId, MonitorSaveProgress progress, Object error) {
    state = <String, MonitorProvisioning>{
      ...state,
      monitorId: MonitorProvisioning(
        progress: progress,
        failure: error.toString(),
      ),
    };
  }

  void clear(String monitorId) {
    if (!state.containsKey(monitorId)) return;
    final next = <String, MonitorProvisioning>{...state}..remove(monitorId);
    state = next;
  }
}

/// Coordinates monitor definitions, foreground checks, persistence, and alerts.
class MonitorController extends AsyncNotifier<List<MonitorEntry>> {
  Future<void>? _refreshOperation;
  final Map<String, Future<_CheckOutcome>> _checkOperations =
      <String, Future<_CheckOutcome>>{};

  /// Loads the complete monitor list from SQLite when the provider is first read.
  @override
  Future<List<MonitorEntry>> build() =>
      ref.watch(monitorRepositoryProvider).all();

  /// Persists a complete definition, then starts its initial snapshot.
  ///
  /// Navigation never waits for network sources. Selected checks join in memory
  /// and replace the observation fields as one consistent database row.
  Future<MonitorEntry> add({
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
    MonitorProgressCallback? onProgress,
  }) async {
    final repository = ref.read(monitorRepositoryProvider);
    final now = DateTime.now();
    final validatedTlsPort = requireValidTlsPort(tlsPort);
    final normalizedHostname = normalizeHostname(hostname);
    final normalizedTlsHostname = normalizeHostname(tlsHostname);
    final flow = appLogger.start(
      'monitor.add',
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
    final monitor = MonitorEntry(
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

    onProgress?.call(
      _progress(MonitorSaveStage.saving, 'Saving monitor definition…', .35),
    );
    flow.info('persistence.started');
    try {
      // The definition and tag links are one SQLite transaction. It is complete
      // and navigable even if every external source is slow or unavailable.
      await repository.create(monitor, tagIds: tagIds);
      await _reload();
    } catch (error, stackTrace) {
      flow.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    flow.info('persistence.succeeded');

    final initialProgress = _progress(
      MonitorSaveStage.preparing,
      'Starting initial checks…',
      .05,
    );
    ref
        .read(monitorProvisioningProvider.notifier)
        .update(monitor.id, initialProgress);
    onProgress?.call(
      _progress(
        MonitorSaveStage.complete,
        'Saved. Initial checks will continue on the summary.',
        1,
      ),
    );

    // Navigation must not wait on the network. This task owns all errors and
    // publishes its state so no asynchronous failure becomes unobserved.
    unawaited(_runInitialCheck(monitor.id, flow: flow));
    return monitor;
  }

  Future<void> _runInitialCheck(
    String monitorId, {
    required AppLogFlow flow,
  }) async {
    final provisioning = ref.read(monitorProvisioningProvider.notifier);
    try {
      final monitor = await ref.read(monitorRepositoryProvider).byId(monitorId);
      if (monitor == null) {
        provisioning.clear(monitorId);
        return;
      }
      final outcome = await _runCheck(
        monitor,
        flow: flow,
        onProgress: (progress) => provisioning.update(monitorId, progress),
      );
      if (!outcome.persisted) {
        provisioning.clear(monitorId);
        return;
      }
      await _reload();
      await _rescheduleReminders(flow: flow);
      provisioning.clear(monitorId);
      flow.info('initial_check.completed');
    } catch (error, stackTrace) {
      flow.error('initial_check.failed', error, stackTrace);
      provisioning.fail(
        monitorId,
        _progress(
          MonitorSaveStage.preparing,
          'Initial check could not finish',
          0,
        ),
        error,
      );
    }
  }

  /// Saves an edited definition and clears stale results when its check inputs
  /// changed. Label and tag edits retain the latest successful observations.
  Future<MonitorEntry> updateMonitor(
    MonitorEntry monitor, {
    Iterable<String>? tagIds,
    MonitorProgressCallback? onProgress,
  }) async {
    requireValidTlsPort(monitor.tlsPort);
    final repository = ref.read(monitorRepositoryProvider);
    final flow = appLogger.start(
      'monitor.update',
      data: <String, Object?>{
        'monitorId': monitor.id,
        'hostname': monitor.hostname,
        'tlsHostname': monitor.tlsHostname,
        'tlsPort': monitor.tlsPort,
        'checksCertificate': monitor.checksCertificate,
        'checksEmail': monitor.checksEmail,
      },
    );
    final existing = await repository.byId(monitor.id);
    final checkDefinitionChanged =
        existing != null &&
        (existing.hostname != monitor.hostname ||
            existing.tlsHostname != monitor.tlsHostname ||
            existing.tlsPort != monitor.tlsPort ||
            existing.checksCertificate != monitor.checksCertificate ||
            existing.checksEmail != monitor.checksEmail ||
            existing.mailSends != monitor.mailSends ||
            existing.mailReceives != monitor.mailReceives ||
            !_sameStrings(existing.dkimSelectors, monitor.dkimSelectors));
    final updated = checkDefinitionChanged
        ? MonitorEntry(
            id: monitor.id,
            hostname: monitor.hostname,
            tlsHostname: monitor.tlsHostname,
            tlsPort: monitor.tlsPort,
            checksCertificate: monitor.checksCertificate,
            checksEmail: monitor.checksEmail,
            mailSends: monitor.mailSends,
            mailReceives: monitor.mailReceives,
            dkimSelectors: monitor.dkimSelectors,
            label: monitor.label,
            enabled: monitor.enabled,
            tags: monitor.tags,
            createdAt: monitor.createdAt,
            updatedAt: DateTime.now(),
          )
        : monitor.copyWith(updatedAt: DateTime.now());
    onProgress?.call(
      _progress(
        MonitorSaveStage.preparing,
        'Preparing ${updated.hostname}…',
        .04,
      ),
    );
    late final MonitorEntry prepared;
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
    onProgress?.call(
      _progress(MonitorSaveStage.saving, 'Saving monitor…', .88),
    );
    flow.info('persistence.started');
    try {
      await repository.update(prepared, tagIds: tagIds);
    } catch (error, stackTrace) {
      flow.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    flow.info('persistence.succeeded');
    onProgress?.call(
      _progress(MonitorSaveStage.refreshing, 'Updating monitor list…', .96),
    );
    await _reload();
    await _rescheduleReminders(flow: flow);
    onProgress?.call(_progress(MonitorSaveStage.complete, 'Monitor ready.', 1));
    return prepared;
  }

  /// Removes a monitor, reloads state, and removes its reminder participation.
  Future<void> delete(String id) async {
    final flow = appLogger.start(
      'monitor.delete',
      data: <String, Object?>{'monitorId': id},
    );
    flow.info('persistence.started');
    try {
      await ref.read(monitorRepositoryProvider).delete(id);
      ref.read(monitorProvisioningProvider.notifier).clear(id);
      await _reload();
      await _rescheduleReminders(flow: flow);
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
  }

  /// Refreshes enabled monitors as one coalesced foreground operation.
  Future<void> refreshAll() =>
      _refreshOperation ??= _runRefreshAll().whenComplete(() {
        _refreshOperation = null;
      });

  /// Runs enabled monitor checks in parallel, then refreshes expiry reminders.
  Future<void> _runRefreshAll() async {
    final flow = appLogger.start('monitor.refresh_all');
    try {
      final monitors =
          state.value ?? await ref.read(monitorRepositoryProvider).all();
      final enabled = monitors.where((monitor) => monitor.enabled).toList();
      flow.info(
        'checks.started',
        data: <String, Object?>{'count': enabled.length},
      );
      await Future.wait(enabled.map(_runCheck));
      await _reload();
      await _rescheduleReminders(flow: flow);
      flow.info('completed', data: <String, Object?>{'count': enabled.length});
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
  }

  /// Checks one monitor and rebuilds expiry reminders after saving.
  ///
  /// A missing row after the check is reported as a state error rather than
  /// silently reintroducing deleted data.
  Future<MonitorEntry> check(String id) async {
    final monitor = await ref.read(monitorRepositoryProvider).byId(id);
    if (monitor == null) {
      throw StateError('Monitor no longer exists');
    }
    final flow = appLogger.start(
      'monitor.check',
      data: <String, Object?>{
        'monitorId': monitor.id,
        'hostname': monitor.hostname,
        'tlsHostname': monitor.tlsHostname,
        'tlsPort': monitor.tlsPort,
      },
    );
    try {
      final outcome = await _runCheck(monitor, flow: flow);
      await _reload();
      await _rescheduleReminders(flow: flow);
      if (!outcome.persisted) {
        throw StateError('Monitor no longer exists');
      }
      flow.info('completed');
      return outcome.monitor;
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
  }

  /// Runs selected external checks through a dynamic, shared I/O window.
  ///
  /// Domain, DNS, TLS, and site identity are independent and start together.
  /// Email analysis starts after DNS because it consumes that exact snapshot.
  /// All patches join in memory and [_performCheck] writes one coherent row, so
  /// readers never observe a partially refreshed domain/TLS/Email snapshot.
  Future<MonitorEntry> _prepareCheck(
    MonitorEntry monitor, {
    MonitorProgressCallback? onProgress,
    AppLogFlow? flow,
  }) async {
    final attemptedAt = DateTime.now();
    final refreshIcon =
        monitor.checksCertificate &&
        (monitor.siteIcon == null ||
            (monitor.siteIcon!.format != SiteIconFormat.png &&
                monitor.siteIcon!.format != SiteIconFormat.svg) ||
            attemptedAt.difference(monitor.siteIcon!.checkedAt) >=
                const Duration(days: 7));
    final total =
        2 +
        (monitor.checksCertificate ? 1 : 0) +
        (refreshIcon ? 1 : 0) +
        (monitor.checksEmail ? 1 : 0);
    var completed = 0;

    Future<_MonitorPatch> track(
      Future<_MonitorPatch> operation,
      MonitorSaveStage stage,
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
        MonitorSaveStage.preparing,
        'Checking selected sources in parallel…',
        .05,
      ),
    );

    final dnsFuture = ref
        .read(dnsSnapshotServiceProvider)
        .check(
          monitor.hostname,
          checkEmailSending: monitor.checksEmail && monitor.mailSends,
          checkEmailReceiving: monitor.checksEmail && monitor.mailReceives,
          dkimSelectors: monitor.dkimSelectors,
        );
    final phaseOne = <Future<_MonitorPatch>>[
      track(
        _domainPatch(monitor, attemptedAt, flow: flow),
        MonitorSaveStage.domain,
        'Domain registration',
      ),
      track(
        dnsFuture.then(
          (snapshot) => (MonitorEntry current) =>
              current.copyWith(dnsSnapshot: snapshot),
        ),
        MonitorSaveStage.dns,
        'DNS',
      ),
      if (monitor.checksCertificate)
        track(
          _certificatePatch(monitor, attemptedAt, flow: flow),
          MonitorSaveStage.certificate,
          'TLS certificate',
        ),
      if (refreshIcon)
        track(
          _siteIconPatch(monitor, flow: flow),
          MonitorSaveStage.icon,
          'Site identity',
        ),
    ];

    var updated = monitor;
    for (final patch in await Future.wait(phaseOne)) {
      updated = patch(updated);
    }
    final dnsSnapshot = await dnsFuture;

    if (monitor.checksEmail) {
      final emailPatch = await track(
        _emailPatch(monitor, dnsSnapshot, attemptedAt, flow: flow),
        MonitorSaveStage.email,
        'Email configuration',
      );
      updated = emailPatch(updated);
    }

    onProgress?.call(
      _progress(
        MonitorSaveStage.saving,
        'Saving one consistent snapshot…',
        .92,
      ),
    );
    return updated.copyWith(
      updatedAt: attemptedAt,
      lastCheckedAt: attemptedAt,
    );
  }

  Future<_MonitorPatch> _domainPatch(
    MonitorEntry monitor,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'domain'});
    try {
      final domain = await ref
          .read(checkConcurrencyGateProvider)
          .run(() => ref.read(rdapServiceProvider).check(monitor.hostname));
      if (domain == null) {
        throw const FormatException('No registration record was published');
      }
      return (MonitorEntry current) => current.copyWith(
        domainExpiresAt: domain.expiresAt,
        domainRegisteredAt: domain.registeredAt,
        domainUpdatedAt: domain.updatedAt,
        domainRegistrar: domain.registrar,
        domainPublicRegistrant: domain.publicRegistrant,
        domainNameServers: domain.nameServers,
        domainSource: domain.source,
        domainActivity: monitor.domainActivity.succeeded(attemptedAt),
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
      return (MonitorEntry current) => current.copyWith(
        domainActivity: monitor.domainActivity.failed(failure),
        domainError: failure.message,
      );
    }
  }

  Future<_MonitorPatch> _certificatePatch(
    MonitorEntry monitor,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'tls'});
    try {
      final certificate = await ref.read(checkConcurrencyGateProvider).run(
        () => ref
            .read(tlsCheckServiceProvider)
            .check(monitor.tlsHostname, monitor.tlsPort),
      );
      return (MonitorEntry current) => current.copyWith(
        certificateValidFrom: certificate.validFrom,
        certificateExpiresAt: certificate.expiresAt,
        certificateIssuer: certificate.issuer,
        certificateSubject: certificate.subject,
        previousCertificateFingerprint: monitor.certificateFingerprint,
        certificateFingerprint: certificate.fingerprint,
        tlsTrusted: certificate.trusted,
        certificateHostnameMatches: certificate.hostnameMatches,
        certificateSubjectAlternativeNames: certificate.subjectAlternativeNames,
        certificateSerialNumber: certificate.serialNumber,
        certificateSignatureAlgorithm: certificate.signatureAlgorithm,
        certificatePublicKeyAlgorithm: certificate.publicKeyAlgorithm,
        certificatePublicKeyDetails: certificate.publicKeyDetails,
        certificateActivity: monitor.certificateActivity.succeeded(attemptedAt),
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
            source: 'TLS endpoint ${monitor.tlsHostname}:${monitor.tlsPort}',
            tls: true,
          );
      return (MonitorEntry current) => current.copyWith(
        certificateActivity: monitor.certificateActivity.failed(failure),
        certificateError: failure.message,
      );
    }
  }

  Future<_MonitorPatch> _siteIconPatch(
    MonitorEntry monitor, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'icon'});
    try {
      final icon = await ref.read(checkConcurrencyGateProvider).run(
        () => ref
            .read(siteIconServiceProvider)
            .discover(monitor.tlsHostname, monitor.tlsPort),
      );
      return icon == null
          ? _identityPatch
          : (MonitorEntry current) => current.copyWith(siteIcon: icon);
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

  Future<_MonitorPatch> _emailPatch(
    MonitorEntry monitor,
    DnsSnapshot dnsSnapshot,
    DateTime attemptedAt, {
    AppLogFlow? flow,
  }) async {
    flow?.info('check.started', data: <String, Object?>{'stage': 'email'});
    try {
      final email = await ref.read(checkConcurrencyGateProvider).run(
        () => ref
            .read(emailPostureServiceProvider)
            .check(
              dnsSnapshot,
              monitor.hostname,
              sends: monitor.mailSends,
              receives: monitor.mailReceives,
              dkimSelectors: monitor.dkimSelectors,
            ),
      );
      return (MonitorEntry current) => current.copyWith(
        emailPosture: email,
        emailActivity: monitor.emailActivity.succeeded(attemptedAt),
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
      return (MonitorEntry current) => current.copyWith(
        emailActivity: monitor.emailActivity.failed(failure),
      );
    }
  }

  Future<_CheckOutcome> _runCheck(
    MonitorEntry monitor, {
    AppLogFlow? flow,
    MonitorProgressCallback? onProgress,
  }) {
    final active = _checkOperations[monitor.id];
    if (active != null) return active;

    late final Future<_CheckOutcome> operation;
    operation = _performCheck(
      monitor,
      flow: flow,
      onProgress: onProgress,
    ).whenComplete(() {
      if (identical(_checkOperations[monitor.id], operation)) {
        _checkOperations.remove(monitor.id);
      }
    });
    _checkOperations[monitor.id] = operation;
    return operation;
  }

  /// Persists one prepared result for an existing monitor and reports changes.
  Future<_CheckOutcome> _performCheck(
    MonitorEntry monitor, {
    AppLogFlow? flow,
    MonitorProgressCallback? onProgress,
  }) async {
    final trace =
        flow ??
        appLogger.start(
          'monitor.check',
          data: <String, Object?>{
            'monitorId': monitor.id,
            'hostname': monitor.hostname,
            'tlsHostname': monitor.tlsHostname,
            'tlsPort': monitor.tlsPort,
          },
        );
    trace.info('checks.started');
    final updated = await _prepareCheck(
      monitor,
      flow: trace,
      onProgress: onProgress,
    );
    trace.info('persistence.started');
    late final bool persisted;
    try {
      persisted = await ref
          .read(monitorRepositoryProvider)
          .updateIfPresent(updated);
    } catch (error, stackTrace) {
      trace.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    trace.info(
      'persistence.succeeded',
      data: <String, Object?>{'present': persisted},
    );

    return (monitor: updated, persisted: persisted);
  }

  /// Rebuilds reminders without turning a saved monitor operation into failure.
  Future<void> _rescheduleReminders({required AppLogFlow flow}) async {
    try {
      await ref.read(reminderControllerProvider.notifier).reconcile();
    } catch (error, stackTrace) {
      flow.error('notifications.reconcile.failed', error, stackTrace);
    }
  }

  /// Reloads the provider from SQLite so every screen observes persisted state.
  Future<void> _reload() async {
    state = AsyncData(await ref.read(monitorRepositoryProvider).all());
  }
}

/// Compares check-definition lists as sets because selector order is not semantic.
bool _sameStrings(List<String> left, List<String> right) {
  final leftValues = left.toSet();
  final rightValues = right.toSet();
  return leftValues.length == rightValues.length &&
      leftValues.every(rightValues.contains);
}

typedef _MonitorPatch = MonitorEntry Function(MonitorEntry current);

MonitorEntry _identityPatch(MonitorEntry current) => current;

typedef _CheckOutcome = ({MonitorEntry monitor, bool persisted});

MonitorSaveProgress _progress(
  MonitorSaveStage stage,
  String message,
  double fraction,
) => MonitorSaveProgress(stage: stage, message: message, fraction: fraction);
