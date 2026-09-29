# Changelog

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
