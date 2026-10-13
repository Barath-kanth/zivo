# Zivo — monochrome and glass UI

Complete project, including the previous opening animation and glass navigation, plus a responsive desktop workspace and refreshed service icon styling.

## Footer visibility and navigation lifecycle repair

- Fixed a confirmed glass-painting bug: Flutter ignores BoxDecoration.color when gradient is non-null. The translucent white scrim is now a separate ColoredBox beneath the gradient, so dark page content does not obscure the Account icon and label.
- Removed AnimatedSwitcher around the shell's routed subtree. The nested ShellRoute navigator now stays mounted in a stable Offstage/TickerMode/ExcludeFocus branch while the home screen is visible. This avoids disposing/reintroducing the navigator and retaining outgoing navigator widgets across rapid Home/Account/Wallet transitions.
- The reported `_dependents.isEmpty` assertion is a framework lifecycle error. The changed shell structure addresses a concrete lifecycle risk found in this app, but the screenshot has no complete exception stack and this repair has not been runtime-reproduced here. A separate underlying cause remains possible.
- Added test/navigation_regression_test.dart for the white scrim over black content and repeated route changes during the launch animation. Tests are included but unrun because Flutter is unavailable here.
- After applying this version, fully stop and restart the running Flutter app to recreate the navigator tree. Run `flutter test test/navigation_regression_test.dart`. If the assertion recurs, capture the first console exception with its full stack trace and the action that triggered it.

## Design

- Palette: black #000000, white #FFFFFF, neutral surfaces #F6F6F6 / #F3F3F3, secondary text #545454 and muted text #686868. Green remains a Zivo semantic accent for helper and success states.
- Typography: locally bundled Inter, tuned with compact bold headings, natural body spacing, consistent Material title styles, 16px action labels and tabular figures in the shared money styles. No external font requests or new package dependencies. This is Uber-inspired typography, not Uber's own Uber Move font.
- Opening: the existing Zivo logo fades in with a subtle 4% scale and 8px rise, then reveals the app. Total duration is 1.15 seconds. It runs once per root mount; the underlying router remains mounted. Input and focus are protected while the overlay is visible. Reduced-motion settings skip it. This is the Flutter opening sequence, not a replacement for native platform launch screens.
- Footer: floating frosted-glass navigation, clipped 18px background blur, translucent white surface, subtle highlight and shadow, rounded selected tabs, black mode-switch button, keyboard focus/hover feedback, labels and tooltips.
- High-contrast mode removes transparency and blur. The dock respects device safe areas, caps desktop width at 680px and hides while the keyboard is open. Selected-tab transitions respect reduced motion.

## Desktop and service icons

- Desktop navigation begins at 1100px viewport width: a 216px persistent sidebar replaces the mobile dock. Desktop and mobile share one destination list and the existing guarded navigation function.
- When the home content area is at least 900px wide, services and search occupy the main column; active requests and neighbourhood options occupy a separately scrollable 320px right column. Narrower content uses the original single-column order.
- The content viewport is bounded at 1440px on large displays. Existing screens and the helper view retain their data and actions within the desktop shell.
- Service selection uses consistent vector outline icons inside rounded white tiles. Decorative green corner dots have been removed. Browsing and task creation share the same icon component. The supplied green #06C167 remains in the existing Zivo logo. Darker #087F5B remains for status text.
- Palette values are also documented in DESIGN_TOKENS.md. The black and green values come from the supplied screenshot; supporting neutral values are Zivo's chosen UI palette.

## Scope

No changes to existing backend code, models, repositories, state management, routes, API configuration, payment logic, platform configuration, dependencies or assets. Existing interaction callbacks outside the task creation form remain identical. Task creation adds service selection, category-specific field validation and stale request protection. The opening animation adds only presentation lifecycle state. Existing incomplete features remain as supplied.

## Verification and limitations

All Dart files under lib/ and test/ passed tree-sitter syntax parsing. Original project files remain present. Existing callback expressions were compared token by token, including multiplicity. Primary text contrast is 21:1; secondary text on the conservative #D9D9D9 glass background is 5.36:1; muted text on #F3F3F3 is 5.02:1. These are calculated color checks, not a full accessibility audit.

Added test/ui_presentation_test.dart covers launch dismissal, input protection, state preservation, reduced motion, disposal and high-contrast glass fallback. Flutter is not installed in this environment, so these widget tests, compilation, actual screenshots and device rendering have NOT been run. This should be visually tested on devices before a production release; source parsing alone does not establish production readiness.

Run with the project's existing Flutter environment:

```sh
flutter pub get
flutter analyze
flutter test test/ui_presentation_test.dart
flutter run
```

Check a narrow phone, large text, a notched iPhone, keyboard-open forms, client/helper switching, wallet, map tracking, deep links and the admin console. Native map compositing and glass blur performance need device verification.

The requested Mobbin page was not accessible and no Mobbin connector was available. Uber's official typography reference is https://base.uber.com/6d2425e9f/p/976582-typography . No GitHub push or deployment was performed.

## Category forms and overflow repair

- Removed decorative green dots from the shared category icon component.
- Active task cards wrap price chips and place their action beneath them, avoiding the narrow desktop panel overflow.
- Helper empty states can grow and scroll in short viewports.
- All 21 categories offer relevant task suggestions plus a custom option; titles remain editable.
- Desktop creation forms are limited to 840px for readability.
- Valid live category-specific pricing fields remain supported. Generic, missing or mismatched fallback schemas are replaced with category-specific questions.
- Choice questions use dropdowns; quantities, text and dates use appropriate inputs. Required answers and minimum quantities are validated.
- Switching categories clears old answers and purchase items. Stale field and price responses are ignored. Submission refreshes the quote using the current answers.
- Backend, repositories, models, routes, payment implementation and dependencies remain unchanged.
- These latest changes passed source syntax and scope checks only. Flutter compilation and overflow reproduction still require the project's Flutter environment.
