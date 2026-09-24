# F-Droid submission material

`com.aliyesha.akshi.yml` is a draft for the external `fdroiddata` repository.
Before submission:

1. create and publish `https://github.com/aliyesha/akshi`;
2. verify the repository and issue-tracker URLs;
3. replace the draft commit tag with the immutable release commit if required;
4. add a 512 × 512 PNG at
   `fastlane/metadata/android/en-US/images/icon.png`;
5. add representative phone screenshots under
   `fastlane/metadata/android/en-US/images/phoneScreenshots/`;
6. run `fdroid rewritemeta`, `fdroid lint`, and an isolated `fdroid build`;
7. submit the finalized YAML to `fdroiddata/metadata/com.aliyesha.akshi.yml`.

This directory is preparation material only; F-Droid does not consume it from
the application repository.
