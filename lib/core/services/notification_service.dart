import 'dart:async';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/notification_destination.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/monitors/domain/reminder_digest.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Owns local notifications, grouped expiry reminders, and tap destinations.
///
/// No server is involved: schedules are rebuilt from the monitors currently
/// stored on the device, and one digest can represent many affected monitors.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _navigationRoutes =
      StreamController<String>.broadcast();
  bool _initialized = false;
  String? _pendingRoute;

  static const _digestIdBase = 100000000;
  static const _digestSlotCount = 60;
  static const _changeNotificationId = 200000000;

  Stream<String> get navigationRoutes => _navigationRoutes.stream;

  /// Returns and clears a notification route received before the router listened.
  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  static const _changeDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'monitor_changes',
      'Monitor changes',
      channelDescription: 'Changes to monitored registration, certificates, and Email configuration',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'monitor-changes',
    ),
  );

  /// Initializes timezone data, platform channels, and launch-response capture.
  ///
  /// Initialization is idempotent because foreground checks and app startup can
  /// both reach the service.
  Future<void> initialize() async {
    if (_initialized) return;
    appLogger.info('service.notifications.initialize.started');
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (error, stackTrace) {
      appLogger.error(
        'service.notifications.timezone.failed',
        error,
        stackTrace,
      );
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _queuePayload(launchDetails?.notificationResponse?.payload);
    }
    appLogger.info('service.notifications.initialize.completed');
  }

  /// Converts a foreground notification tap into a route event.
  void _handleResponse(NotificationResponse response) {
    _queuePayload(response.payload);
  }

  /// Delivers a decoded destination immediately or retains it until navigation
  /// has mounted its listener.
  void _queuePayload(String? payload) {
    final destination = NotificationDestination.fromPayload(payload);
    if (destination == null) return;
    final route = destination.route;
    if (_navigationRoutes.hasListener) {
      _navigationRoutes.add(route);
    } else {
      _pendingRoute = route;
    }
  }

  /// Requests platform notification permission after ensuring initialization.
  Future<bool> requestPermission() async {
    appLogger.info('service.notifications.permission.started');
    await initialize();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final granted = android ?? ios ?? true;
    appLogger.info(
      'service.notifications.permission.completed',
      data: <String, Object?>{'granted': granted},
    );
    return granted;
  }

  /// Rebuilds all grouped daily reminder slots from current monitor state.
  ///
  /// Existing slots are cancelled first, then one inexact OS alarm is created
  /// per digest slot. This avoids one alarm per website and removes stale alerts.
  Future<void> reconcileAll(
    Iterable<MonitorEntry> monitors,
    AppSettings settings,
  ) async {
    final monitorList = monitors.toList(growable: false);
    appLogger.info(
      'service.notifications.reconcile.started',
      data: <String, Object?>{'monitorCount': monitorList.length},
    );
    await initialize();
    await _cancelDigestSlots();
    final digests = buildDailyReminderDigests(
      monitorList,
      settings,
    ).take(_digestSlotCount).toList(growable: false);

    appLogger.info(
      'service.notifications.reconcile.completed',
      data: <String, Object?>{'digestCount': digests.length},
    );
    for (var index = 0; index < digests.length; index++) {
      final digest = digests[index];
      final body = digest.preview();
      final scheduledAt = digest.scheduledAt;
      final destination = NotificationDestination(
        kind: NotificationDestinationKind.expiry,
        monitorIds: digest.monitorIds,
      );
      await _plugin.zonedSchedule(
        id: _digestIdBase + index,
        title: digest.assetCount == 1
            ? '1 monitor needs attention'
            : '${digest.assetCount} monitors need attention',
        body: body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          scheduledAt.year,
          scheduledAt.month,
          scheduledAt.day,
          scheduledAt.hour,
          scheduledAt.minute,
        ),
        notificationDetails: _digestDetails(body),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: destination.toPayload(),
      );
    }
  }

  /// Clears the fixed slot range used by the current reminder schedule.
  Future<void> _cancelDigestSlots() async {
    for (var index = 0; index < _digestSlotCount; index++) {
      await _plugin.cancel(id: _digestIdBase + index);
    }
  }

  NotificationDetails _digestDetails(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'expiry_reminders',
      'Expiry reminders',
      channelDescription:
          'Consolidated registration and certificate expiry reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      styleInformation: BigTextStyleInformation(body),
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'expiry-reminders',
    ),
  );

  /// Shows one grouped change alert and routes its tap to affected monitors.
  ///
  /// Duplicate monitor IDs are removed before sorting so concurrent checks do
  /// not produce repeated names or a burst of notifications.
  Future<void> showChanges(Iterable<MonitorEntry> monitors) async {
    final changedById = <String, MonitorEntry>{
      for (final monitor in monitors) monitor.id: monitor,
    };
    final changed = changedById.values.toList()
      ..sort(
        (left, right) =>
            left.hostname.toLowerCase().compareTo(right.hostname.toLowerCase()),
      );
    if (changed.isEmpty) {
      return;
    }
    appLogger.info(
      'service.notifications.changes.started',
      data: <String, Object?>{'monitorCount': changed.length},
    );
    final names = changed.map((monitor) => monitor.hostname);
    final destination = NotificationDestination(
      kind: NotificationDestinationKind.changes,
      monitorIds: changed.map((monitor) => monitor.id).toList(),
    );
    await initialize();
    await _plugin.show(
      id: _changeNotificationId,
      title: changed.length == 1
          ? '1 monitor changed'
          : '${changed.length} monitors changed',
      body: compactMonitorNames(names),
      notificationDetails: _changeDetails,
      payload: destination.toPayload(),
    );
    appLogger.info(
      'service.notifications.changes.completed',
      data: <String, Object?>{'monitorCount': changed.length},
    );
  }
}
