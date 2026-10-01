import 'package:flutter/services.dart';

enum NotificationPermissionStatus {
  allowed,
  notAllowed,
  notDetermined,
  unavailable;

  String get label => switch (this) {
    NotificationPermissionStatus.allowed => 'Allowed',
    NotificationPermissionStatus.notAllowed => 'Not allowed',
    NotificationPermissionStatus.notDetermined => 'Not requested',
    NotificationPermissionStatus.unavailable => 'Status unavailable',
  };
}

/// Opens the operating system's notification settings for Akshi.
///
/// Permission prompts are controlled by the OS and may only be shown once.
/// This route gives users a deterministic recovery path after a denial.
abstract final class SystemSettingsService {
  static const _channel = MethodChannel('com.aliyesha.akshi/system_settings');

  static Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;

  /// Records that Akshi has handed the notification request to the OS.
  ///
  /// Android needs this distinction because a denied runtime permission and a
  /// permission that has never been requested otherwise have the same native
  /// grant value. iOS reports `notDetermined` directly, so its implementation
  /// is intentionally a no-op.
  static Future<void> markNotificationPermissionRequested() async {
    try {
      await _channel.invokeMethod<bool>('markNotificationPermissionRequested');
    } on MissingPluginException {
      // Tests and unsupported platforms do not have a native marker.
    } on PlatformException {
      // Permission state remains authoritative even if the marker is unavailable.
    }
  }

  static Future<NotificationPermissionStatus>
  notificationPermissionStatus() async {
    try {
      final value = await _channel.invokeMethod<String>(
        'notificationPermissionStatus',
      );
      return switch (value) {
        'allowed' => NotificationPermissionStatus.allowed,
        'notAllowed' => NotificationPermissionStatus.notAllowed,
        'notDetermined' => NotificationPermissionStatus.notDetermined,
        _ => NotificationPermissionStatus.unavailable,
      };
    } on MissingPluginException {
      return NotificationPermissionStatus.unavailable;
    } on PlatformException {
      return NotificationPermissionStatus.unavailable;
    }
  }
}
