# Akshi Offline Device Workflow

## Purpose

This guide prepares one development laptop to build and run Akshi on a real
Android or iOS device while the laptop has no internet connection.

The phone is connected to the laptop by USB. The phone may still use Wi-Fi or
mobile data because Akshi itself needs network access to check domains, DNS,
certificates, and registration information. "Offline" in this guide refers to
the development laptop and build toolchain.

The workflow preserves the normal Flutter device experience. After one online
preparation build, connect the phone and run:

~~~sh
flutter run --release --no-pub -d <device-id>
~~~

The important option is "--no-pub". It prevents Flutter from invoking Pub
during the device run.

## What this workflow does

Online preparation completes one real release build for the selected platform.
That build causes the installed development tools to download any inputs missing
from their normal caches.

Preparation is platform-specific:

~~~sh
./tool/offline prepare android
~~~

or:

~~~sh
./tool/offline prepare ios
~~~

Do not prepare both platforms unless both will be used offline.

The workflow does not:

- create a second copy of Pub or Gradle caches inside Akshi;
- download every Flutter platform;
- build debug, profile, and release modes together;
- change the installed Flutter, Android, Java, CocoaPods, or Xcode toolchains;
- configure Android release-signing secrets;
- create an Apple certificate or provisioning profile without Apple;
- guarantee future builds after dependencies or toolchains change.

## Non-negotiable operating rule

Preparation, offline use, and cleanup have this order:

1. Clean old generated data only if space must be reclaimed.
2. Connect the laptop to the internet.
3. Prepare one platform.
4. Prove the real device run.
5. Disconnect the laptop.
6. Continue using the same toolchain and lockfile.
7. Do not clean until offline work is finished.

Running cleanup after preparation deliberately discards project-generated
inputs and invalidates the prepared state.

## Common prerequisites

Before preparing either platform:

- Work from the Akshi repository root.
- Use the Flutter SDK revision intended for the project.
- Keep "pubspec.lock" unchanged.
- Ensure "flutter doctor -v" reports the selected platform as usable.
- Close any older build or preparation process.
- Ensure the laptop clock is correct.
- Ensure enough disk space exists for one release build.
- Do not upgrade Flutter, Dart, Java, Gradle, Xcode, CocoaPods, or an SDK after
  preparation.
- Do not change "pubspec.yaml", "pubspec.lock", Gradle files, the Podfile, or
  native plugin versions after preparation.

Check the environment while online:

~~~sh
cd /path/to/akshi
flutter doctor -v
flutter --version
~~~

Record the Flutter version if the offline period is important.

## Recovering space from the abandoned workspace cache

An older version of the workflow created ".offline/pub" and
".offline/gradle". The current workflow does not use those directories.

Inspect current project-local usage:

~~~sh
du -sh .offline build .dart_tool android/.gradle ios/Pods 2>/dev/null
~~~

If the old cache or generated output must be removed, remain online and run:

~~~sh
./tool/offline clean
~~~

Cleanup removes only these project-local targets:

- ".offline";
- "android/.gradle";
- "ios/Pods";
- paths removed by "flutter clean", including ordinary project build output.

Cleanup does not remove:

- the Flutter SDK;
- the Flutter SDK artifact cache;
- the Android SDK or NDK;
- the normal Pub cache;
- the normal Gradle dependency and wrapper caches;
- CocoaPods' global cache;
- Xcode;
- Xcode DerivedData outside the project;
- signing certificates;
- provisioning profiles;
- Android keystores.

All removed project directories are generated again by the relevant tools.
Because regeneration may need downloaded inputs, run platform preparation
online immediately after cleaning.

Never run cleanup while Flutter, Gradle, CocoaPods, or Xcode is building Akshi.

## Android preparation

### Android prerequisites

The laptop must already have:

- Flutter with Android support;
- a compatible Android SDK and platform;
- the required Android build tools and NDK;
- Java 17 as required by the project;
- accepted Android SDK licences;
- a working Gradle wrapper;
- Android USB debugging support;
- an Android release signing configuration if a release build must be
  installed on the phone.

Check the Android toolchain:

~~~sh
flutter doctor -v
flutter doctor --android-licenses
~~~

Only accept or review licences while the laptop is online.

### Prepare Android online

Run:

~~~sh
cd /path/to/akshi
./tool/offline prepare android
~~~

Wait for the command to finish successfully. Do not interrupt it merely because
the first Gradle build is quiet for several minutes.

A successful preparation has completed locked Pub dependency resolution and an
Android release APK build. It has exercised the same release dependency graph
needed later.

Typical release output is under:

~~~text
build/app/outputs/flutter-apk/
~~~

The exact filename can vary with signing and build configuration.

### Android signing boundary

Akshi's Android release configuration intentionally does not use the debug
keystore as a release-signing shortcut. Therefore:

- release compilation can be prepared without committing signing secrets;
- an unsigned release APK cannot be installed on a physical Android device;
- actual release deployment requires a local or release-system signing
  configuration;
- keystores and passwords must remain outside version control.

Offline caching does not solve signing. Configure and test signing separately
before depending on release-mode device deployment.

### Prove Android offline operation

While still in a location where reconnecting is possible:

1. Complete Android preparation.
2. Connect the intended Android phone by USB.
3. Enable Developer options and USB debugging.
4. Accept the computer's debugging key on the phone.
5. Confirm the device is visible.
6. Disable Wi-Fi and disconnect Ethernet on the laptop.
7. Run the release command with Pub disabled.

~~~sh
flutter devices
flutter run --release --no-pub -d <android-device-id>
~~~

Success means Flutter builds, installs, and starts Akshi without the laptop
using the internet.

If this proof fails because signing is not configured, fix signing online and
repeat the proof. Do not substitute debug signing into the release build as a
permanent solution.

## iOS preparation

### iOS prerequisites

The laptop must be a Mac with:

- the project-supported Flutter SDK;
- a compatible Xcode installation;
- Xcode command-line tools selected;
- CocoaPods available;
- an Apple Developer account available in Xcode;
- Akshi's bundle identifier registered as required;
- a valid development certificate;
- a provisioning profile covering the application and device;
- the physical iPhone trusted by the Mac;
- Developer Mode enabled on the iPhone.

Check the environment:

~~~sh
flutter doctor -v
xcodebuild -version
pod --version
~~~

Open Xcode while online and confirm the correct development team is selected for
the Runner target and embedded targets.

### Prepare generic iOS build inputs online

Run:

~~~sh
cd /path/to/akshi
./tool/offline prepare ios
~~~

This completes an unsigned iOS release build. It warms the general Flutter,
Pub, CocoaPods, and Xcode compilation inputs without pretending that Apple
signing is available offline.

Typical output is under:

~~~text
build/ios/iphoneos/
~~~

### Prepare the exact iPhone online

Generic iOS preparation cannot guarantee device-specific Apple material. Before
travelling or disconnecting:

1. Connect the exact iPhone by USB.
2. Unlock it and choose Trust if prompted.
3. Confirm Developer Mode is enabled.
4. Confirm it appears in "flutter devices".
5. Keep the laptop online.
6. Run Akshi once in release mode on that device.

~~~sh
flutter devices
flutter run --release --no-pub -d <ios-device-id>
~~~

This step lets Xcode obtain or validate the provisioning profile, register the
device when necessary, and acquire support material for that iPhone and iOS
version.

Repeat this online device preparation after:

- changing the iPhone;
- upgrading the iPhone to an iOS version not previously used by this Xcode;
- changing the bundle identifier or entitlements;
- changing the Apple team;
- replacing or renewing certificates or provisioning profiles;
- upgrading Xcode in a way that changes device support.

### Prove iOS offline operation

After the online device run succeeds:

1. Leave the same iPhone connected.
2. Disable Wi-Fi and disconnect Ethernet on the Mac.
3. Run the identical command again.

~~~sh
flutter run --release --no-pub -d <ios-device-id>
~~~

Success means compilation, signing, installation, and launch all complete using
material already present on the Mac.

An offline failure mentioning signing, provisioning, device registration,
Developer Mode, or device support is an Apple-managed prerequisite failure, not
a Pub cache failure.

## Normal offline operation

For every offline session:

1. Do not change the dependency lockfile or toolchains.
2. Connect and unlock the phone.
3. Verify Flutter sees it.
4. Run release mode with Pub disabled.

~~~sh
cd /path/to/akshi
flutter devices
flutter run --release --no-pub -d <device-id>
~~~

If only one device is connected, Flutter may allow omission of "-d", but using
the explicit device identifier is more predictable.

Hot reload is a debug-mode facility and is not available in the same way during
a release-mode run. This workflow is intended for release behaviour and
physical-device verification.

## IDE operation

The terminal command is the authoritative offline workflow.

An IDE may automatically invoke Pub before launching Flutter. If using an IDE,
configure its Flutter launch arguments to include:

~~~text
--release
--no-pub
~~~

If the IDE still runs dependency resolution or an online inspection, use the
terminal command instead. IDE indexes, plugin marketplaces, source downloads,
and update checks are outside Akshi's build cache.

Running the native iOS project from Xcode does not replace the need to have
Flutter-generated project inputs current. Run Akshi's preparation before
depending on Xcode offline.

## Where downloaded material normally lives

Exact paths can vary when environment variables or custom SDK locations are
used. Common locations are:

| Material | Typical location | Managed by |
| --- | --- | --- |
| Dart and Flutter packages | "~/.pub-cache" | Pub |
| Flutter engine artifacts | "<flutter-sdk>/bin/cache" | Flutter |
| Gradle distributions | "~/.gradle/wrapper/dists" | Gradle |
| Gradle plugins and Maven artifacts | "~/.gradle/caches" | Gradle |
| Android platforms, tools, and NDK | Android SDK directory | Android SDK Manager |
| CocoaPods download cache | "~/Library/Caches/CocoaPods" | CocoaPods |
| Installed project pods | "ios/Pods" | CocoaPods |
| Xcode build and device data | "~/Library/Developer/Xcode" | Xcode |
| Project package configuration | ".dart_tool" | Flutter and Pub |
| Project build output | "build" | Flutter |
| Android project state | "android/.gradle" | Gradle |

The preparation workflow deliberately reuses these normal locations. It does
not promise that everything is contained in Akshi or that all global caches are
safe to delete.

## Disk-space control

The smallest practical approach is to prepare only the platform currently
needed.

Inspect project-local data:

~~~sh
du -sh .offline build .dart_tool android/.gradle ios/Pods 2>/dev/null
~~~

Inspect common shared caches on macOS:

~~~sh
du -sh ~/.pub-cache ~/.gradle ~/Library/Caches/CocoaPods \
  ~/Library/Developer/Xcode/DerivedData 2>/dev/null
~~~

The workflow cannot promise a fixed amount of additional space. Requirements
depend on what is already installed, the Flutter revision, Android SDK and NDK
components, Gradle artifacts, Xcode data, and CocoaPods.

Do not delete shared caches merely to save space immediately before offline
work. Deleting them can affect every Flutter, Android, or iOS project on the
machine and is intentionally outside the cleanup command.

## Troubleshooting

### Flutter contacts pub.dev

Symptom:

- Flutter prints package-resolution messages or attempts to reach pub.dev.

Action:

~~~sh
flutter run --release --no-pub -d <device-id>
~~~

Confirm "--no-pub" is present. A plain "flutter run" may invoke Pub even when
"pubspec.lock" has not changed.

### Offline Pub reports a missing package

Cause:

- preparation did not finish;
- the lockfile changed;
- the Pub cache was removed;
- a different Flutter/Dart environment is being used.

Recovery:

1. Reconnect the laptop.
2. Restore the intended lockfile if the change was accidental.
3. Run the relevant preparation command again.
4. Repeat the offline proof.

### Gradle attempts a download or reports a missing artifact

Cause:

- Android preparation did not complete;
- a Gradle, plugin, Java, Flutter, SDK, or dependency version changed;
- the normal Gradle cache was removed;
- preparation built a different configuration.

Recovery:

~~~sh
./tool/offline prepare android
~~~

Run it online, then repeat the offline device proof. Do not copy Gradle cache
directories manually between unrelated machines.

### Android SDK or NDK component is missing

Recovery:

1. Reconnect the laptop.
2. Install the exact component through the Android SDK tools.
3. Accept required licences.
4. Rerun Android preparation.
5. Repeat the offline proof.

### Android release will not install

Common cause:

- the release APK is unsigned or signed with an untrusted or inconsistent key.

Recovery:

- configure the intended local release signing;
- remove an incompatible previously installed build if appropriate;
- keep signing material outside Git;
- prepare and test again online.

This is not fixed by downloading more Pub packages.

### CocoaPods attempts to reach its CDN or a source repository

Cause:

- "ios/Pods" was removed;
- the Podfile or lockfile changed;
- a pod is absent from normal caches;
- iOS preparation did not complete.

Recovery:

~~~sh
./tool/offline prepare ios
~~~

Run it online and retain "ios/Pods" for the offline period.

### Xcode asks for a profile, certificate, account, or device registration

Cause:

- the exact device/signing state was not prepared;
- Apple-managed credentials expired or changed;
- the device or application identity changed.

Recovery:

1. Reconnect the Mac.
2. Open Xcode and validate the development team.
3. Connect and trust the exact iPhone.
4. Run Akshi on it once in release mode.
5. Repeat the offline proof.

### The iPhone is not listed

Check:

- a data-capable USB cable is used;
- the phone is unlocked;
- Trust was accepted;
- Developer Mode is enabled;
- Xcode recognises the device;
- the installed Xcode supports the phone's iOS version.

### Preparation was interrupted

Completed downloads normally remain in the owning tool's cache. Reconnect and
run the same preparation command again. Do not assume an interrupted run has
fully warmed the platform.

### The workflow worked before an upgrade

Toolchain upgrades can require different engine artifacts, Gradle plugins,
Android components, Pods, Xcode support data, or generated files. Reconnect and
prepare again after any toolchain upgrade.

## Pre-travel or unreliable-network checklist

Complete this checklist separately for each required platform:

- [ ] "flutter doctor -v" is acceptable.
- [ ] The intended Flutter SDK revision is recorded.
- [ ] "pubspec.lock" is committed and unchanged.
- [ ] Old project-local caches were cleaned only if necessary.
- [ ] The required platform preparation completed online.
- [ ] The exact physical phone is trusted and visible.
- [ ] Android release signing works, if Android release deployment is needed.
- [ ] iOS certificate and provisioning profile are valid.
- [ ] The exact iPhone completed one online release run.
- [ ] Laptop networking was disabled.
- [ ] "flutter devices" still found the phone over USB.
- [ ] The offline release command built, installed, and launched Akshi.
- [ ] No cleanup or toolchain upgrade will be performed before offline work.

## Returning online

Reconnect and repeat preparation whenever any of these change:

- Flutter or Dart;
- "pubspec.yaml" or "pubspec.lock";
- a Flutter plugin;
- Gradle, Android Gradle Plugin, Kotlin, Java, SDK, or NDK;
- Android signing configuration;
- Xcode or CocoaPods;
- Podfile, Podfile.lock, or native iOS dependencies;
- Apple team, certificate, provisioning profile, bundle identifier, or
  entitlements;
- the physical iPhone or its iOS version.

When offline work is finished and disk space is more important than retaining
the prepared project state, run:

~~~sh
./tool/offline clean
~~~

Shared global caches remain under the control of their respective development
tools.
