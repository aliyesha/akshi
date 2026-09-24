import 'dart:async';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/notification_destination.dart';
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
  String? _pendingRoute;

  Stream<String> get navigationRoutes => _navigationRoutes.stream;

  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
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
    _queuePayload(response.payload);
  }

  void _queuePayload(String? payload) {
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
}
