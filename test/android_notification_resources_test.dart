import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notifications use the approved monochrome Akshi icon', () {
    final icon = File('android/app/src/main/res/drawable/ic_notification.png');
    final service = File('lib/core/services/notification_service.dart')
        .readAsStringSync();

    expect(icon.existsSync(), isTrue);
    expect(
      sha256.convert(icon.readAsBytesSync()).toString(),
      '7264f1fab3ae8a2cc4f92a8a79629d1594b95a1d0e8bbe8d2e4e70fa4f3ecd0c',
    );
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
