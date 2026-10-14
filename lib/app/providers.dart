import 'dart:async';
import 'dart:io';

import 'package:akshi/core/crash/crash_log.dart';
import 'package:akshi/core/crash/crash_log_store.dart';
import 'package:akshi/core/services/async_concurrency_gate.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:akshi/core/services/email_posture_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/core/services/notification_service.dart';
import 'package:akshi/core/services/rdap_service.dart';
import 'package:akshi/core/services/site_icon_service.dart';
import 'package:akshi/core/services/tls_check_service.dart';
import 'package:akshi/features/monitors/data/monitor_repository.dart';
import 'package:akshi/features/reminders/application/alarm_reconciler.dart';
import 'package:akshi/features/reminders/data/alarm_audit_repository.dart';
import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:akshi/features/settings/data/settings_repository.dart';
import 'package:akshi/features/tags/data/tag_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Operating-system connectivity source shared by failure classification and UI.
final connectivitySourceProvider = Provider<ConnectivitySource>(
  (ref) => SystemConnectivitySource(),
);

/// Live offline state for transient UI such as the portfolio notice.
///
/// Check failures remain immutable history. This stream independently removes
/// the global notice as soon as a transport returns, without starting a refresh.
final deviceOfflineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivitySourceProvider);
  bool? last;

  try {
    last = connectivityIsOffline(await connectivity.checkConnectivity());
    yield last;
  } catch (error, stackTrace) {
    appLogger.error(
      'service.connectivity.initial_check.failed',
      error,
      stackTrace,
    );
  }

  try {
    await for (final states in connectivity.onConnectivityChanged) {
      final offline = connectivityIsOffline(states);
      if (offline == last) continue;
      last = offline;
      yield offline;
    }
  } catch (error, stackTrace) {
    appLogger.error('service.connectivity.stream.failed', error, stackTrace);
  }
});

/// Shared FIFO I/O window that prevents foreground checks from overwhelming
/// the device, resolver, or remote sources.
final checkConcurrencyGateProvider = Provider<AsyncConcurrencyGate>(
  (ref) => AsyncConcurrencyGate(maximum: 10),
);

/// Local database shared by repositories through Riverpod.
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.dispose);
  return database;
});

final monitorRepositoryProvider = Provider<MonitorRepository>(
  (ref) => MonitorRepository(ref.watch(databaseProvider)),
);

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(),
);

final tlsCheckServiceProvider = Provider<TlsCheckService>(
  (ref) => const TlsCheckService(),
);

/// Reusable HTTP connection pool owned by the application provider scope.
final httpClientProvider = Provider<HttpClient>((ref) {
  final client = HttpClient();
  ref.onDispose(() => client.close(force: true));
  return client;
});

final rdapServiceProvider = Provider<RdapService>(
  (ref) => RdapService(ref.watch(httpClientProvider)),
);

final siteIconServiceProvider = Provider<SiteIconService>(
  (ref) => SiteIconService(ref.watch(httpClientProvider)),
);

final checkFailureClassifierProvider = Provider<CheckFailureClassifier>(
  (ref) => CheckFailureClassifier(
    connectivity: ref.watch(connectivitySourceProvider),
  ),
);

final dnsSnapshotServiceProvider = Provider<DnsSnapshotService>(
  (ref) => DnsSnapshotService(gate: ref.watch(checkConcurrencyGateProvider)),
);

final emailPostureServiceProvider = Provider<EmailPostureService>(
  (ref) => EmailPostureService(ref.watch(httpClientProvider)),
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final alarmAuditRepositoryProvider = Provider<AlarmAuditRepository>(
  (ref) => AlarmAuditRepository(ref.watch(databaseProvider)),
);

final alarmAuditDaysProvider = FutureProvider<List<AlarmAuditDay>>((ref) async {
  final entries = await ref.watch(alarmAuditRepositoryProvider).all();
  return AlarmAuditDay.group(entries);
});

final alarmAuditDateProvider =
    FutureProvider.family<List<AlarmAuditEntry>, AlarmDate>((ref, date) {
      return ref.watch(alarmAuditRepositoryProvider).forDate(date);
    });

final alarmReconcilerProvider = Provider<AlarmReconciler>(
  (ref) => AlarmReconciler(
    ref.watch(notificationServiceProvider),
    ref.watch(alarmAuditRepositoryProvider),
  ),
);

final crashLogStoreProvider = Provider<CrashLogStore>((ref) => CrashLogStore());

final crashLogsProvider = FutureProvider<List<CrashLog>>(
  (ref) => ref.watch(crashLogStoreProvider).read(),
);
