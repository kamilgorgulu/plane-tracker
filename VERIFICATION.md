# Verification

Last verified: September 30, 2026.

## Automated checks

- `zsh scripts/test.sh`: 20 geometry, unit conversion, timestamp, provider-decoding and language checks passed.
- iPhone 17 simulator build (iOS 26.5): succeeded.
- iPad (A16) simulator build (iOS 27.0): succeeded.
- App version: 1.3.0 (build 5), deployment target iOS/iPadOS 17.0.

## Visual checks

- English demo home screen launched on iPhone 17 without clipping or overflow.
- Turkish demo home screen launched on iPad without clipping or overflow.
- The full flight-detail sheet was opened on both device classes.
- The detail screen showed the current aircraft, observed path, destination target, route legend and altitude profile.
- English and Turkish flight-detail labels rendered correctly. The language preference persisted through relaunch.
- The demo altitude profile contained six time-ordered samples and matched the cyan observed route.

## Data behavior

- Automatic free mode uses OpenSky, ADSB.lol and adsb.fi with fallback behavior.
- A personal Flightradar24 API key can be selected for a paid account and remains in the device Keychain.
- Live route history is built only from positions received during the current tracking session. No missing path is invented.
- Airport/airline/aircraft enrichment comes from adsbdb and is labeled as community data.
- The orange current-to-destination line is explicitly described as a geographic connection, not a guaranteed flight plan.

## Remaining physical-device validation

AR label alignment, compass calibration, outdoor GPS accuracy, camera permission handling and real paid-provider credentials require a physical iPhone or iPad. Development provisioning profiles expire and must be renewed by rebuilding and reinstalling the app.
