import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
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

/// Coordinates monitor definitions, foreground checks, persistence, and alerts.
class MonitorController extends AsyncNotifier<List<MonitorEntry>> {
  Future<void>? _refreshOperation;

  /// Loads the complete monitor list from SQLite when the provider is first read.
  @override
  Future<List<MonitorEntry>> build() =>
      ref.watch(monitorRepositoryProvider).all();

  /// Prepares every foreground observation before persisting a new monitor.
  ///
  /// The check result, including explicit offline/source failures, is saved in
  /// the same monitor transaction. Permission prompts and notification setup
  /// happen only after the local save and cannot make it appear unsuccessful.
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
    final normalizedHostname = normalizeHostname(hostname);
    final normalizedTlsHostname = normalizeHostname(tlsHostname);
    final flow = appLogger.start(
      'monitor.add',
      data: <String, Object?>{
        'hostname': normalizedHostname,
        'tlsHostname': normalizedTlsHostname.isEmpty
            ? normalizedHostname
            : normalizedTlsHostname,
        'tlsPort': tlsPort,
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
      tlsPort: tlsPort,
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
      _progress(
        MonitorSaveStage.preparing,
        'Preparing ${monitor.hostname}…',
        .04,
      ),
    );
    late final MonitorEntry prepared;
    try {
      prepared = await _prepareCheck(
        monitor,
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
      await repository.create(prepared, tagIds: tagIds);
    } catch (error, stackTrace) {
      flow.error('persistence.failed', error, stackTrace);
      rethrow;
    }
    flow.info('persistence.succeeded');
    onProgress?.call(
      _progress(MonitorSaveStage.refreshing, 'Updating monitor list…', .96),
    );
    try {
      await _reload();
    } catch (error, stackTrace) {
      flow.error('state.reload.failed', error, stackTrace);
      final current = state.value ?? const <MonitorEntry>[];
      state = AsyncData(<MonitorEntry>[...current, prepared]);
    }

    // Notifications are a post-save side effect. A missing icon, denied
    // permission, or platform setup error must not undo or hide the monitor.
    try {
      await ref.read(notificationServiceProvider).requestPermission();
    } catch (error, stackTrace) {
      flow.error('notifications.permission.failed', error, stackTrace);
      // The monitor remains fully usable without local notification access.
    }
    onProgress?.call(_progress(MonitorSaveStage.complete, 'Monitor ready.', 1));
    return prepared;
  }

  /// Saves an edited definition and clears stale results when its check inputs
  /// changed. Label and tag edits retain the latest successful observations.
  Future<MonitorEntry> updateMonitor(
    MonitorEntry monitor, {
    Iterable<String>? tagIds,
    MonitorProgressCallback? onProgress,
  }) async {
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
      await _reload();
      await _rescheduleReminders();
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

  /// Runs enabled monitor checks in parallel, then refreshes reminders and
  /// emits only outcomes whose persisted semantic values changed.
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
      final outcomes = await Future.wait(enabled.map(_performCheck));
      await _reload();
      await _rescheduleReminders();
      await _notifyChanges(outcomes);
      flow.info('completed', data: <String, Object?>{'count': enabled.length});
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
  }

  /// Checks one monitor and emits a grouped change notification after saving.
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
      final outcome = await _performCheck(monitor, flow: flow);
      await _reload();
      await _rescheduleReminders();
      if (!outcome.persisted) {
        throw StateError('Monitor no longer exists');
      }
      await _notifyChanges(<_CheckOutcome>[outcome]);
      flow.info('completed');
      return outcome.monitor;
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
  }

  /// Runs independent TLS, RDAP, icon, DNS, and Email operations.
  ///
  /// Each external operation has its own failure boundary and returns one
  /// immutable aggregate ready for a single persistence transaction.
  Future<MonitorEntry> _prepareCheck(
    MonitorEntry monitor, {
    MonitorProgressCallback? onProgress,
    AppLogFlow? flow,
  }) async {
    final attemptedAt = DateTime.now();
    var updated = monitor;

    if (monitor.checksCertificate) {
      onProgress?.call(
        _progress(
          MonitorSaveStage.certificate,
          'Checking TLS certificate…',
          .16,
        ),
      );
      flow?.info('check.started', data: <String, Object?>{'stage': 'tls'});
      try {
        final certificate = await ref
            .read(tlsCheckServiceProvider)
            .check(monitor.tlsHostname, monitor.tlsPort);
        updated = updated.copyWith(
          certificateValidFrom: certificate.validFrom,
          certificateExpiresAt: certificate.expiresAt,
          certificateIssuer: certificate.issuer,
          certificateSubject: certificate.subject,
          previousCertificateFingerprint: monitor.certificateFingerprint,
          certificateFingerprint: certificate.fingerprint,
          tlsTrusted: certificate.trusted,
          certificateHostnameMatches: certificate.hostnameMatches,
          certificateSubjectAlternativeNames:
              certificate.subjectAlternativeNames,
          certificateSerialNumber: certificate.serialNumber,
          certificateSignatureAlgorithm: certificate.signatureAlgorithm,
          certificatePublicKeyAlgorithm: certificate.publicKeyAlgorithm,
          certificatePublicKeyDetails: certificate.publicKeyDetails,
          certificateActivity: monitor.certificateActivity.succeeded(
            attemptedAt,
          ),
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
              source: 'Certificate endpoint',
              tls: true,
            );
        updated = updated.copyWith(
          certificateActivity: monitor.certificateActivity.failed(failure),
          certificateError: failure.message,
        );
      }
    }

    onProgress?.call(
      _progress(MonitorSaveStage.domain, 'Checking domain registration…', .30),
    );
    flow?.info('check.started', data: <String, Object?>{'stage': 'domain'});
    try {
      final domain = await ref
          .read(rdapServiceProvider)
          .check(monitor.hostname);
      if (domain == null) {
        throw const FormatException('No registration record was published');
      }
      updated = updated.copyWith(
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
      updated = updated.copyWith(
        domainActivity: monitor.domainActivity.failed(failure),
        domainError: failure.message,
      );
    }

    if (monitor.checksCertificate &&
        (monitor.siteIcon == null ||
            (monitor.siteIcon!.format != SiteIconFormat.png &&
                monitor.siteIcon!.format != SiteIconFormat.svg) ||
            attemptedAt.difference(monitor.siteIcon!.checkedAt) >=
                const Duration(days: 7))) {
      onProgress?.call(
        _progress(MonitorSaveStage.icon, 'Finding a site icon…', .46),
      );
      flow?.info('check.started', data: <String, Object?>{'stage': 'icon'});
      try {
        final icon = await ref
            .read(siteIconServiceProvider)
            .discover(monitor.tlsHostname, monitor.tlsPort);
        if (icon != null) {
          updated = updated.copyWith(siteIcon: icon);
        }
      } catch (error, stackTrace) {
        flow?.error(
          'check.failed',
          error,
          stackTrace,
          data: <String, Object?>{'stage': 'icon'},
        );
        // Site identity is optional and never blocks a monitor save.
      }
    }

    onProgress?.call(
      _progress(MonitorSaveStage.dns, 'Reading DNS records…', .62),
    );
    flow?.info('check.started', data: <String, Object?>{'stage': 'dns'});
    final dnsSnapshot = await ref
        .read(dnsSnapshotServiceProvider)
        .check(
          monitor.hostname,
          checkEmailSending: monitor.checksEmail && monitor.mailSends,
          checkEmailReceiving: monitor.checksEmail && monitor.mailReceives,
          dkimSelectors: monitor.dkimSelectors,
        );
    updated = updated.copyWith(dnsSnapshot: dnsSnapshot);

    if (monitor.checksEmail) {
      onProgress?.call(
        _progress(MonitorSaveStage.email, 'Checking Email configuration…', .76),
      );
      flow?.info('check.started', data: <String, Object?>{'stage': 'email'});
      try {
        final email = await ref
            .read(emailPostureServiceProvider)
            .check(
              dnsSnapshot,
              monitor.hostname,
              sends: monitor.mailSends,
              receives: monitor.mailReceives,
              dkimSelectors: monitor.dkimSelectors,
            );
        updated = updated.copyWith(
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
              source: 'System DNS resolver',
            );
        updated = updated.copyWith(
          emailActivity: monitor.emailActivity.failed(failure),
        );
      }
    }

    updated = updated.copyWith(
      updatedAt: attemptedAt,
      lastCheckedAt: attemptedAt,
    );
    return updated;
  }

  /// Persists one prepared result for an existing monitor and reports changes.
  Future<_CheckOutcome> _performCheck(
    MonitorEntry monitor, {
    AppLogFlow? flow,
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
    final updated = await _prepareCheck(monitor, flow: trace);
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

    final certificateChanged =
        monitor.certificateFingerprint != null &&
        monitor.certificateFingerprint != updated.certificateFingerprint;
    final domainChanged =
        monitor.domainExpiresAt != null &&
        monitor.domainExpiresAt != updated.domainExpiresAt;
    final emailChanged =
        monitor.emailPosture != null &&
        monitor.emailPosture!.changeSignature !=
            updated.emailPosture?.changeSignature;
    final dnsChanged =
        monitor.dnsSnapshot != null &&
        updated.dnsSnapshot != null &&
        updated.dnsSnapshot!.hasRecordChangesFrom(monitor.dnsSnapshot!);
    return (
      monitor: updated,
      changed:
          persisted &&
          (certificateChanged || domainChanged || emailChanged || dnsChanged),
      persisted: persisted,
    );
  }

  /// Reduces many changed checks to one notification-service operation.
  Future<void> _notifyChanges(Iterable<_CheckOutcome> outcomes) async {
    final changed = outcomes
        .where((outcome) => outcome.persisted && outcome.changed)
        .map((outcome) => outcome.monitor);
    await ref.read(notificationServiceProvider).showChanges(changed);
  }

  /// Rebuilds the device schedule from current persisted monitors and settings.
  Future<void> _rescheduleReminders() async {
    final monitors = await ref.read(monitorRepositoryProvider).all();
    final settings =
        ref.read(settingsControllerProvider).value ?? const AppSettings();
    await ref
        .read(notificationServiceProvider)
        .reconcileAll(monitors, settings);
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

typedef _CheckOutcome = ({MonitorEntry monitor, bool changed, bool persisted});

MonitorSaveProgress _progress(
  MonitorSaveStage stage,
  String message,
  double fraction,
) => MonitorSaveProgress(stage: stage, message: message, fraction: fraction);
