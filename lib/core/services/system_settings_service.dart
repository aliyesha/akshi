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
  static const _channel = MethodChannel(
    'com.aliyesha.akshi/system_settings',
  );

  static Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;

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
