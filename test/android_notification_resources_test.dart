import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notifications use the monochrome Phosphor bird icon', () {
    final icon = File('android/app/src/main/res/drawable/ic_notification.xml');
    final service = File('lib/core/services/notification_service.dart')
        .readAsStringSync();

    expect(icon.existsSync(), isTrue);
    final iconXml = icon.readAsStringSync();
    expect(iconXml, contains('<vector'));
    expect(iconXml, contains('android:width="24dp"'));
    expect(iconXml, contains('android:height="24dp"'));
    expect(iconXml, contains('android:fillColor="#FFFFFFFF"'));
    expect(iconXml, contains('android:pathData='));
    expect(
      service,
      contains("AndroidInitializationSettings('ic_notification')"),
    );
  });

  test('Android manifest declares scheduled notification recovery', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
  });
}
