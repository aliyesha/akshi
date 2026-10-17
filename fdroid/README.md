# F-Droid release guide

This directory contains Akshi's candidate build recipe for the official
F-Droid repository. It is maintained beside the application so every release
can be reviewed against the source, dependency lockfile, tag, and store
metadata before a submission is opened.

## Repository roles

| Location | Responsibility |
| --- | --- |
| **fdroid/com.aliyesha.akshi.yml** | Candidate build recipe copied into **fdroiddata/metadata/** for submission |
| **fastlane/metadata/android/en-US/** | Canonical English title, descriptions, release notes, icon, and screenshots |
| **pubspec.yaml** | Application version name and version code |
| **pubspec.lock** | Locked Dart and Flutter package dependency graph |
| **CHANGELOG.md** | Human-readable project release history |

The recipe in this directory is preparation material. F-Droid does not read it
directly from the application repository. The reviewed copy submitted to the
external **fdroiddata** repository becomes F-Droid's authoritative build
recipe.

## Release contract

For release 1.0.0, the following values must agree:

- application ID: **com.aliyesha.akshi**;
- **pubspec.yaml**: version **1.0.0+1**;
- F-Droid recipe: version name **1.0.0** and version code **1**;
- immutable upstream tag: **v1.0.0**;
- Fastlane release notes: **changelogs/1.txt**;
- expected artifact: **build/app/outputs/flutter-apk/app-release.apk**.

The recipe pins a specific Flutter revision even though the source library is
declared as **flutter@stable**. Do not replace that revision with a moving
branch or an unreviewed SDK update.

## Pre-release checks

Complete these checks before creating the release tag:

1. Run formatting, static analysis, tests, and a release build.
2. Smoke-test a clean installation on a physical Android device.
3. Review the complete user-facing metadata and every screenshot.
4. Confirm that the public source, issue tracker, website, and changelog URLs
   resolve without authentication.
5. Confirm that **pubspec.lock** is current and committed.
6. Confirm that no signing keys, service credentials, local configuration, or
   generated build output is committed.
7. Inspect the final diff and commit only intentional release material.

    dart format --output=none --set-exit-if-changed lib test
    flutter analyze
    flutter test
    flutter build apk --release
    git diff --check
    git status --short

## Publish the upstream release

Commit the reviewed source and metadata, then create the exact tag referenced
by the recipe:

    git tag -a v1.0.0 -m "Akshi 1.0.0"
    git push origin main
    git push origin v1.0.0

A cryptographically signed Git tag may be used when the maintainer has an
established signing identity. An annotated tag is otherwise sufficient for the
recipe, provided the tag is immutable and points to the reviewed release
commit.

## Prepare the fdroiddata submission

Work from a current fork or clone of **fdroiddata**, copy the candidate recipe,
and validate it in that repository:

    cp /path/to/akshi/fdroid/com.aliyesha.akshi.yml \
      metadata/com.aliyesha.akshi.yml

    fdroid rewritemeta com.aliyesha.akshi
    fdroid lint com.aliyesha.akshi
    fdroid build --test com.aliyesha.akshi:1

Review any normalization produced by **rewritemeta**; do not accept semantic
changes blindly. The isolated build must resolve dependencies from declared
sources and produce the APK path specified by the recipe.

Submit the resulting **metadata/com.aliyesha.akshi.yml** in a focused
**fdroiddata** pull request. The pull request should state what Akshi does, why
it is appropriate for F-Droid, where the release tag is published, and which
validation commands completed successfully.

## Signing and distribution

The official F-Droid infrastructure builds and signs its distributed APK. Do
not add an Android signing key to this repository or the F-Droid recipe.

An independently distributed upstream APK may use the maintainer's own signing
key, but that is a separate release channel. Its signature will not normally
match the APK built and signed by F-Droid.

## Future releases

For every new version:

1. increment both parts of the version in **pubspec.yaml**;
2. add **fastlane/metadata/android/en-US/changelogs/<versionCode>.txt**;
3. add a new immutable **Builds** entry to the F-Droid recipe;
4. update **CurrentVersion** and **CurrentVersionCode**;
5. pin and review the Flutter revision;
6. repeat the application, metadata, and isolated-build checks; and
7. publish the matching upstream tag before opening the F-Droid update.

Do not rewrite an already published release tag or reuse a version code.
