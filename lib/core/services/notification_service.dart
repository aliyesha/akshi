import 'dart:async';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/notification_destination.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/alarm_reconciler.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Thin platform adapter for local notifications.
///
/// Planning and reconciliation intentionally live outside this class. Keeping
/// this boundary small makes the critical algorithm testable without Android,
/// iOS, clocks, permissions, or plugin state.
class NotificationService implements AlarmPlatformGateway {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _navigationRoutes =
      StreamController<String>.broadcast();
  Future<void>? _initialization;
  bool _initialized = false;
  bool _disposed = false;
  String? _pendingRoute;

  /// Routes produced when a validated notification is selected.
  Stream<String> get navigationRoutes => _navigationRoutes.stream;

  /// Removes and returns the route captured before navigation subscribed.
  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  /// Initializes the plugin once, joining concurrent callers.
  ///
  /// A failed attempt clears itself so a later foreground operation can retry.
  Future<void> initialize() {
    _ensureActive();
    if (_initialized) return Future<void>.value();
    final active = _initialization;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _initialize().whenComplete(() {
      if (identical(_initialization, operation)) {
        _initialization = null;
      }
    });
    _initialization = operation;
    return operation;
  }

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    final initialized = await _plugin.initialize(
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
    if (initialized == false) {
      throw StateError('Notification plugin initialization failed');
    }
    if (_disposed) return;
    _initialized = true;
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _queuePayload(launchDetails?.notificationResponse?.payload);
      }
    } on Object catch (error, stackTrace) {
      appLogger.error(
        'service.notifications.launch_details.failed',
        error,
        stackTrace,
      );
    }
  }

  /// Returns an explicit IANA location or fails reconciliation.
  ///
  /// UTC is not a safe fallback: silently using it can move a 09:00 reminder
  /// by many hours. The UI instead reports that reminders need attention.
  Future<tz.Location> localLocation() async {
    await initialize();
    final local = await FlutterTimezone.getLocalTimezone();
    return tz.getLocation(local.identifier);
  }

  void _handleResponse(NotificationResponse response) {
    if (_disposed) return;
    _queuePayload(response.payload);
  }

  void _queuePayload(String? payload) {
    if (_disposed) return;
    final destination = NotificationDestination.fromPayload(payload);
    if (destination == null) return;
    if (_navigationRoutes.hasListener) {
      _navigationRoutes.add(destination.route);
    } else {
      _pendingRoute = destination.route;
    }
  }

  Future<bool> requestPermission() async {
    await initialize();
    try {
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
      await SystemSettingsService.markNotificationPermissionRequested();
      return android ?? ios ?? true;
    } on Object catch (error, stackTrace) {
      appLogger.error(
        'service.notifications.permission.failed',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  Future<List<PlatformAlarmRequest>> pendingAlarms() async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return pending
        .map(
          (request) => PlatformAlarmRequest(
            id: request.id,
            title: request.title,
            body: request.body,
            payload: request.payload,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> scheduleAlarm(ExpiryAlarmSpec alarm) async {
    await initialize();
    await _plugin.zonedSchedule(
      id: alarm.notificationId,
      title: alarm.title,
      body: alarm.body,
      scheduledDate: alarm.scheduledAt,
      notificationDetails: _expiryDetails(alarm.body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: alarm.payload,
    );
  }

  @override
  Future<void> cancelAlarm(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAllAlarms() async {
    await initialize();
    await _plugin.cancelAll();
  }

  NotificationDetails _expiryDetails(String body) => NotificationDetails(
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

  /// Releases the navigation stream owned by this service.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pendingRoute = null;
    await _navigationRoutes.close();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('NotificationService has been disposed');
    }
  }
}
