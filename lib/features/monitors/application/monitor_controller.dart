import 'package:akshi/app/providers.dart';
import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/monitor_profile.dart';
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
    MonitorProfile profile = MonitorProfile.website,
    bool mailSends = true,
    bool mailReceives = true,
    List<String> dkimSelectors = const <String>[],
    String? label,
    Iterable<String> tagIds = const <String>[],
  }) async {
    final now = DateTime.now();
    final monitor = MonitorEntry(
      id: const Uuid().v4(),
      hostname: normalizeHostname(hostname),
      port: port,
      profile: profile,
      mailSends: mailSends,
      mailReceives: mailReceives,
      dkimSelectors: dkimSelectors,
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
    final checkDefinitionChanged =
        existing != null &&
        (existing.hostname != monitor.hostname ||
            existing.port != monitor.port ||
            existing.profile != monitor.profile ||
            existing.mailSends != monitor.mailSends ||
            existing.mailReceives != monitor.mailReceives ||
            !_sameStrings(existing.dkimSelectors, monitor.dkimSelectors));
    final updated = checkDefinitionChanged
        ? MonitorEntry(
            id: monitor.id,
            hostname: monitor.hostname,
            port: monitor.port,
            profile: monitor.profile,
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
    final attemptedAt = DateTime.now();
    var updated = monitor;

    if (monitor.profile.checksCertificate) {
      try {
        final certificate = await ref
            .read(tlsCheckServiceProvider)
            .check(monitor.hostname, monitor.port);
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
          certificateActivity:
              monitor.certificateActivity.succeeded(attemptedAt),
          certificateError: null,
        );
      } on Object catch (error) {
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

    try {
      final domain = await ref
          .read(rdapServiceProvider)
          .check(monitor.hostname);
      if (domain == null) {
        throw const FormatException('No registration expiry was published');
      }
      updated = updated.copyWith(
        domainExpiresAt: domain.expiresAt,
        domainSource: domain.source,
        domainActivity: monitor.domainActivity.succeeded(attemptedAt),
        domainError: null,
      );
    } on Object catch (error) {
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

    if (monitor.profile.discoversSiteIcon &&
        (monitor.siteIcon == null ||
            attemptedAt.difference(monitor.siteIcon!.checkedAt) >=
                const Duration(days: 7))) {
      final icon = await ref
          .read(siteIconServiceProvider)
          .discover(monitor.hostname, monitor.port);
      if (icon != null) updated = updated.copyWith(siteIcon: icon);
    }

    if (monitor.profile.checksEmail) {
      try {
        final email = await ref
            .read(emailPostureServiceProvider)
            .check(
              monitor.hostname,
              sends: monitor.mailSends,
              receives: monitor.mailReceives,
              dkimSelectors: monitor.dkimSelectors,
            );
        updated = updated.copyWith(
          emailPosture: email,
          emailActivity: monitor.emailActivity.succeeded(attemptedAt),
        );
      } on Object catch (error) {
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
    await ref.read(monitorRepositoryProvider).save(updated);

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
    return (
      monitor: updated,
      changed: certificateChanged || domainChanged || emailChanged,
    );
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

}

bool _sameStrings(List<String> left, List<String> right) {
  final leftValues = left.toSet();
  final rightValues = right.toSet();
  return leftValues.length == rightValues.length &&
      leftValues.every(rightValues.contains);
}

typedef _CheckOutcome = ({MonitorEntry monitor, bool changed});
