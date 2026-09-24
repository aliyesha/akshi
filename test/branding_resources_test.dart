import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses color launcher assets without a monochrome override', () {
    for (final version in <String>['v26', 'v33']) {
      for (final name in <String>['ic_launcher.xml', 'ic_launcher_round.xml']) {
        final adaptive = File(
          'android/app/src/main/res/mipmap-anydpi-$version/$name',
        ).readAsStringSync();
        expect(adaptive, contains('@mipmap/ic_launcher_background'));
        expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
        expect(adaptive, isNot(contains('<monochrome')));
      }
    }

    for (final density in <String>[
      'mdpi',
      'hdpi',
      'xhdpi',
      'xxhdpi',
      'xxxhdpi',
    ]) {
      final directory = 'android/app/src/main/res/mipmap-$density';
      for (final name in <String>[
        'ic_launcher.png',
        'ic_launcher_round.png',
        'ic_launcher_background.png',
        'ic_launcher_foreground.png',
      ]) {
        expect(File('$directory/$name').existsSync(), isTrue);
      }
    }
  });

  test('portrait and landscape splash assets are wired on both platforms', () {
    expect(
      File(
        'android/app/src/main/res/drawable-port-xxxhdpi/akshi_splash.png',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        'android/app/src/main/res/drawable-land-xxxhdpi/akshi_splash.png',
      ).existsSync(),
      isTrue,
    );
    final androidLaunch = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    expect(androidLaunch, contains('@drawable/akshi_splash'));
    expect(androidLaunch, contains('android:gravity="center"'));
    expect(androidLaunch, isNot(contains('android:gravity="fill"')));

    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(storyboard, contains('image="AkshiSplashPortrait"'));
    expect(storyboard, contains('image="AkshiSplashLandscape"'));
    expect(storyboard, contains('heightClass=compact'));
    expect(storyboard, contains('contentMode="scaleAspectFit"'));
    expect(storyboard, isNot(contains('LaunchImage')));
  });

  test('designer mark is bundled for consistent in-app branding', () {
    expect(File('assets/branding/akshi_icon.png').existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final mark = File('lib/core/widgets/akshi_mark.dart').readAsStringSync();

    expect(pubspec, contains('- assets/branding/akshi_icon.png'));
    expect(mark, contains('assets/branding/akshi_icon.png'));
  });

  test('installed application name is capitalized consistently', () {
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();

    expect(android, contains('android:label="Akshi"'));
    expect(ios, contains('<string>Akshi</string>'));
  });
}
