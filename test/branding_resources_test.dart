import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android app icon resources remain unchanged', () {
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

  test('Android uses one official system splash without a second screen', () {
    final androidSplashIcon = File(
      'android/app/src/main/res/drawable-nodpi/akshi_splash_icon.png',
    );
    expect(androidSplashIcon.existsSync(), isTrue);
    expect(androidSplashIcon.lengthSync(), greaterThan(200000));
    final androidSplashBytes = androidSplashIcon.readAsBytesSync();
    expect(
      androidSplashBytes.sublist(16, 24),
      orderedEquals(<int>[0, 0, 2, 0, 0, 0, 2, 0]),
      reason: 'The native splash artwork must remain 512×512.',
    );

    final mainActivity = File(
      'android/app/src/main/kotlin/com/aliyesha/akshi/MainActivity.kt',
    ).readAsStringSync();
    final installIndex = mainActivity.indexOf('installSplashScreen()');
    final createIndex = mainActivity.indexOf(
      'super.onCreate(savedInstanceState)',
    );
    expect(installIndex, greaterThanOrEqualTo(0));
    expect(installIndex, lessThan(createIndex));
    expect(mainActivity, isNot(contains('LinearLayout')));
    expect(mainActivity, isNot(contains('FlutterUiDisplayListener')));

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('androidx.core:core-splashscreen:1.2.0'));

    for (final directory in <String>['values', 'values-night']) {
      final styles = File('android/app/src/main/res/$directory/styles.xml')
          .readAsStringSync();
      expect(styles, contains('parent="Theme.SplashScreen"'));
      expect(styles, contains('windowSplashScreenBackground'));
      expect(styles, contains('@drawable/akshi_splash_icon'));
      expect(styles, contains('postSplashScreenTheme'));
    }

    final app = File('lib/app/akshi_app.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(app, isNot(contains('class _LaunchBrandScreen')));
    expect(app, isNot(contains('Duration(milliseconds: 700)')));
    expect(pubspec, isNot(contains('assets/branding/akshi_splash_icon.png')));
    expect(File('assets/branding/akshi_splash_icon.png').existsSync(), isFalse);

    for (final obsoleteAsset in <String>[
      'android/app/src/main/res/drawable-nodpi/akshi_splash.png',
      'android/app/src/main/res/drawable-port-nodpi/akshi_splash.png',
      'android/app/src/main/res/drawable-land-nodpi/akshi_splash.png',
      'android/app/src/main/res/drawable/transparent_splash_icon.xml',
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
      'android/app/src/main/res/drawable-v31/empty_system_splash_icon.xml',
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
      'android/app/src/main/res/font/space_grotesk_variable.ttf',
    ]) {
      expect(File(obsoleteAsset).existsSync(), isFalse);
    }
    expect(
      File('android/app/src/main/res/drawable-port-xxxhdpi/akshi_splash.png')
          .existsSync(),
      isFalse,
    );
    expect(
      File('android/app/src/main/res/drawable-land-xxxhdpi/akshi_splash.png')
          .existsSync(),
      isFalse,
    );

    final lightColors = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    final darkColors = File('android/app/src/main/res/values-night/colors.xml')
        .readAsStringSync();
    expect(lightColors, contains('#FFFCEEF5'));
    expect(darkColors, contains('#FF1E1B4B'));
  });

  test('iOS native splash is a valid text-only launch screen', () {
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final iosProject = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(
      iosInfo,
      isNot(contains('<string>SpaceGrotesk-Variable.ttf</string>')),
    );
    expect(
      iosProject,
      isNot(contains('SpaceGrotesk-Variable.ttf in Resources')),
    );
    expect(File('ios/Runner/SpaceGrotesk-Variable.ttf').existsSync(), isFalse);
    expect(
      Directory('ios/Runner/Assets.xcassets/AkshiSplashIcon.imageset')
          .existsSync(),
      isFalse,
    );

    final iosColors = File(
      'ios/Runner/Assets.xcassets/AkshiSplashBackground.colorset/'
      'Contents.json',
    ).readAsStringSync();
    expect(iosColors, contains('"value" : "dark"'));
    expect(iosColors, contains('"red" : "0.988"'));
    expect(iosColors, contains('"red" : "0.118"'));
    expect(iosColors, contains('"green" : "0.106"'));
    expect(iosColors, contains('"blue" : "0.294"'));

    final iosForeground = File(
      'ios/Runner/Assets.xcassets/AkshiSplashForeground.colorset/'
      'Contents.json',
    ).readAsStringSync();
    expect(iosForeground, contains('"value" : "dark"'));
    expect(iosForeground, contains('"red" : "0.267"'));
    expect(iosForeground, contains('"red" : "1.000"'));

    final storyboard = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();
    expect(storyboard, contains('text="Starting Akshi ..."'));
    expect(storyboard, contains('name="AkshiSplashBackground"'));
    expect(storyboard, contains('name="AkshiSplashForeground"'));
    expect(
      storyboard,
      contains('fontDescription" type="system" pointSize="20"'),
    );
    expect(storyboard, contains('firstAttribute="centerX"'));
    expect(storyboard, contains('firstAttribute="centerY"'));
    expect(storyboard, isNot(contains('userDefinedRuntimeAttributes')));
    expect(storyboard, isNot(contains('AkshiSplashIcon')));
    expect(storyboard, isNot(contains('<imageView')));
    expect(storyboard, isNot(contains('<customFonts')));
    expect(storyboard, isNot(contains('SpaceGrotesk')));
  });

  test('designer mark is bundled for consistent in-app branding', () {
    expect(File('assets/branding/akshi_icon.png').existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final mark = File('lib/core/widgets/akshi_mark.dart').readAsStringSync();

    expect(pubspec, contains('- assets/branding/akshi_icon.png'));
    expect(mark, contains('assets/branding/akshi_icon.png'));
  });

  test('installed application name is capitalized consistently', () {
    final android = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();

    expect(android, contains('android:label="Akshi"'));
    expect(ios, contains('<string>Akshi</string>'));
  });
}
