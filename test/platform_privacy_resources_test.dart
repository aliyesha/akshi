import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android disables cloud backup and device transfer', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('@xml/data_extraction_rules'));
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    expect(rules, contains('domain="database" path="."'));
    expect(rules, contains('domain="sharedpref" path="."'));
  });

  test('iOS excludes local data directories from backup', () {
    final appDelegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(appDelegate, contains('excludeLocalDataFromBackup()'));
    expect(appDelegate, contains('.documentDirectory'));
    expect(appDelegate, contains('.libraryDirectory'));
    expect(appDelegate, contains('isExcludedFromBackupKey'));
  });

  test('Android release is never signed with the debug key', () {
    final buildFile = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(buildFile, isNot(contains('signingConfigs.getByName("debug")')));
  });
}
