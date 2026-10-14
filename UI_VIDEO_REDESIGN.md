# Zivo — client and helper visual update

The supplied ZePay video is a visual reference. Zivo keeps its own name,
existing service categories, task workflows and backend integrations.

## Design direction

White rounded cards, restrained green accents, charcoal text, compact
illustrated headers, clear service icons, pill filters, and quiet transitions.
The new neighbourhood illustration is local Flutter vector artwork: no network
image fetches, no raster scaling artifacts, and no third-party artwork copied
from the video. Inter remains the bundled typeface.

## Coverage

| Area | What changed |
| --- | --- |
| Client home | Illustrated header, searchable services, balanced category grid, active tasks, quieter wallet shortcut |
| Client task history | Active / Completed / All filters; existing chat, OTP and dispute controls |
| Helper home | Matching header, availability card, white earnings summary, Active job / Earnings shortcuts |
| Helper discovery | Working search across title, description, service and location; every category filter; clear-filter state |
| Job cards | Larger service icon, readable summary, earnings emphasis and clear Accept job action |
| Active job | Shared white cards and status styling; wrapping detail chips for narrow screens |
| Wallet / earnings | Mint balance panel, white action tiles, readable statistics; retry action on load failure |
| Chat | Dark-green outgoing messages and white incoming cards |
| Booking | Consistent outlined fields, labelled steps, editable review summary |
| Account and sign-in | Shared light surfaces, typography, field and dialog styling; original authentication flows retained |
| Other screens | Shared app-bar, cards, forms, tabs, switches, dialogs and empty-state theme |
| Navigation | Green selected state, matching desktop sidebar, readable mobile labels; helper and client destinations retained |
| Accessibility | Enlarged-text header layout, narrow-screen category layout, scrollable empty states, reduced-motion route transitions |

## Behaviour fixes included

Helper search is no longer an empty tap action. Job filters use actual category
identifiers rather than emoji strings. A read-only cached nearby-job accessor
keeps the helper list visible when another task operation updates Bloc state.
Helper availability now requests a device position when enabled instead of
publishing fixed Colombo coordinates. A denied request shows an error and does
not change the availability switch.

These changes do not deploy the app, alter API credentials, migrate the
database or modify the payment backend. The existing transfer placeholder is
labelled "Transfer · soon". The older instant-dispatch flow still includes demo
coordinates, as recorded in UI_ENHANCEMENTS.md; this UI update does not claim
that every existing backend workflow is production-ready.

## Validation

See VALIDATION.md for the final validation outcome. Tests use synthetic data
and do not sign in, pay, accept real jobs, or publish location to a live service.
