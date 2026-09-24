import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notification icon exists and is referenced by the app', () {
    final notificationIcon = File(
      'android/app/src/main/res/drawable/ic_notification.xml',
    );
    final service = File('lib/core/services/notification_service.dart')
        .readAsStringSync();

    expect(notificationIcon.existsSync(), isTrue);
    expect(notificationIcon.readAsStringSync(), contains('<vector'));
    expect(
      service,
      contains("AndroidInitializationSettings('ic_notification')"),
    );
    expect(service, contains("icon: 'ic_notification'"));
  });

  test('Android manifest declares scheduled notification recovery', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
  });
}
