# Validation — 14 October 2026

## Completed
- Dart 3.13.5 formatter parsed all 112 Dart files under `lib/` and `test/` without syntax errors. The check used `dart format --output=none`; it did not reformat the existing project.
- Every local Dart import/export was checked against the source tree; no missing targets were found.
- Bundled asset references and the new locally painted neighbourhood artwork were reviewed.
- Shared client/helper headers, helper discovery, forms, cards, wallet surfaces, navigation and empty states were reviewed in source.

## Not completed in this environment
The Flutter 3.47.7 SDK was installed, but `flutter pub get` could not finish because environment network policy blocked `https://pub.dev:443`. Dependencies were not fully resolved. Consequently, Flutter analyzer, widget tests, release compilation, and actual rendered UI previews could not run. A successful build or runtime verification is not claimed.

Tests are supplied for service search, narrow headers with 200% text, short-viewport empty states, helper search, client/helper synthetic screen rendering, and existing navigation/presentation regressions. These tests have not been executed for this update.

## Run locally
Use a compatible current Flutter stable SDK with access to pub.dev:

```sh
flutter pub get
flutter analyze
flutter test --dart-define=CAPTURE_UI=true
flutter build web --release
```

The capture flag writes synthetic client/helper home previews to `ui-previews/` during `role_screens_test.dart`. They are widget-test previews, not live account screenshots. No preview PNGs are included because rendering did not run here.

Check signed-out service search, both roles at 320/390px and desktop widths, enlarged text, permission denial, booking, task filters, active jobs, chat and wallet against your existing backend. Real payment and job operations require the existing service setup.

## Delivery scope
This is the updated Flutter source archive. Nothing was deployed. The pre-existing transfer action is labelled “Transfer · soon”; the older instant-dispatch flow still uses demo coordinates. See `UI_VIDEO_REDESIGN.md` and `UI_ENHANCEMENTS.md` for coverage and remaining scope.
