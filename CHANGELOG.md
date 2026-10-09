# Changelog

## v26.1.3 — 2026-10-09

- Improved ETHOS context-menu responsiveness by limiting automatic display invalidation to 1 Hz.
- Telemetry acquisition frequency is unchanged.
- Explicit user actions retain their immediate display invalidation.
- Annular gauge sectors now use the native ETHOS renderer directly.
- Removed the experimental pre-rasterized PNG mask renderer and its development assets.
- RSSI 2.4 and RSSI 900 now display `dB` on the Dashboard and Flight Summary when ETHOS supplies no unit; explicit ETHOS units remain unchanged.
- RX Battery now uses the same normalized, cached source engine as the other standard column telemetry sources while remaining manually selected.
- Source acquisition and recovery tests cover successful normalization, cache reuse, delayed RSSI recovery, and invalid-source display behavior.
- Flight Summary reports Max RPM, Max Current, Max Power, Min Pack Voltage, duration, RSSI 2.4 minimum, and RSSI 900 minimum.
- Gauge rendering was validated on X20 Pro AW with ETHOS 26.1 Nightly; validation on every stable ETHOS release is not claimed.
- Telemetry mappings, Auto Bind, Smart Battery, alarms, Flight Summary calculations, chrono, persistence, and X20/X18/X14 layouts are otherwise unchanged.

## v26.1.2 — 2026-10-05

- New independent empirical GIB2A LiPo SOC curve.
- Linear interpolation between SOC calibration points.
- Improved Smart Battery behavior at RPM 0: the indication follows the calculated voltage-based target.
- Initial SOC now uses the current stabilized voltage instead of the stabilization sample average.
- RPM-active monotonic behavior and the 1% per second drop limit are retained.
- Existing alarms, battery callouts, telemetry mappings, and layouts are unchanged.

## [26.1.1] - Unreleased

### Added

- Introduced GIB2A POWER as the electric telemetry dashboard in the GIB2A Advanced Telemetry Dashboard family.
- FrSky Neuron ESC telemetry dashboard for voltage, current, battery percentage, RPM, temperature, consumption, BEC voltage, and BEC current.
- 24-sector annular gauges tuned for the 480x300, 480x320, and 800x480 layouts.
- Battery percentage derived from stabilized and filtered pack voltage.
- Monotonic Battery indication with a controlled decrease rate and upward rebound blocked until reset.
- Auto Bind for seven Neuron telemetry roles using AppID families and units.
- Configurable battery, voltage, temperature, and RPM alarms.
- Battery callouts, manual auxiliary telemetry fields, chrono, and three themes.
- Responsive layouts for full-size and compact ETHOS widget areas.

### Changed

- Default pack-voltage thresholds are 3.8 V per cell for Warning and 3.7 V per cell for Critical, with migration from earlier stored defaults.
- Refined telemetry handling and display behavior while preserving saved configuration compatibility.

### Distribution

- Corrected the ETHOS Suite package layout and set the valid `GIB2APW` installation folder.
- Added an ETHOS Suite manifest and direct-install ZIP package.
- Added English installation and release documentation.
- Added reproducible package validation and SHA-256 reporting.

### Validation

- Local mock validation: PASS — 161,010 assertions, 18 viewport sizes.
- Installation of the final ZIP through ETHOS Suite: PASS.
- In-flight validation of a specific radio, firmware, and ESC combination is not claimed by package validation.
