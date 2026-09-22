import 'package:akshi/core/crash/crash_log.dart';
import 'package:akshi/core/crash/crash_log_store.dart';
import 'package:akshi/core/database/app_database.dart';
import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:akshi/core/services/email_posture_service.dart';
import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/core/services/notification_service.dart';
import 'package:akshi/core/services/rdap_service.dart';
import 'package:akshi/core/services/site_icon_service.dart';
import 'package:akshi/core/services/tls_check_service.dart';
import 'package:akshi/features/monitors/data/monitor_repository.dart';
import 'package:akshi/features/settings/data/settings_repository.dart';
import 'package:akshi/features/tags/data/tag_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wires the local database, repositories, check services, and notifications.
///
/// Riverpod owns these long-lived dependencies so screens and controllers share
/// one database and consistent service instances.
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

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

final rdapServiceProvider = Provider<RdapService>((ref) => RdapService());

final siteIconServiceProvider = Provider<SiteIconService>(
  (ref) => SiteIconService(),
);

final checkFailureClassifierProvider = Provider<CheckFailureClassifier>(
  (ref) => CheckFailureClassifier(),
);

final dnsSnapshotServiceProvider = Provider<DnsSnapshotService>(
  (ref) => const DnsSnapshotService(),
);

final emailPostureServiceProvider = Provider<EmailPostureService>(
  (ref) => EmailPostureService(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
final crashLogStoreProvider = Provider<CrashLogStore>((ref) => CrashLogStore());

final crashLogsProvider = FutureProvider<List<CrashLog>>(
  (ref) => ref.watch(crashLogStoreProvider).read(),
);
