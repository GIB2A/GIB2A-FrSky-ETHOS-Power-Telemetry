# GIB2A POWER v26.1.2 — FrSky Neuron ESC Telemetry for ETHOS

### Advanced FrSky Neuron ESC Telemetry Dashboard for ETHOS

GIB2A POWER is the electric telemetry dashboard of the GIB2A Advanced Telemetry Dashboard family.

## What's New in v26.1.2

- New independent GIB2A LiPo state-of-charge estimation curve
- Linear interpolation between SOC calibration points
- Improved Smart Battery behavior when RPM is inactive
- Initial Battery SOC now uses the current stabilized pack voltage rather than the stabilization sample average
- RPM-active SOC drop limiting and rebound protection retained
- Existing voltage, battery, RPM and temperature alarms remain unchanged
- Battery 50% and 35% callouts retained

## Smart Battery

Battery percentage is an estimated LiPo state of charge calculated from stabilized and filtered pack voltage.

When RPM is inactive, the Battery indication follows the calculated voltage-based SOC target.

When RPM is active, downward SOC changes are rate-limited and upward rebound is blocked to reduce load-induced display fluctuations.

## Telemetry

Auto Bind covers:

- ESC Voltage
- ESC Current
- RPM
- ESC Temperature
- ESC Consumption
- BEC Voltage
- BEC Current

Receiver Battery, RSSI, DIY sources and Chrono remain manually configurable.

## Compatibility

- FrSky Neuron ESC telemetry
- FrSky ETHOS radios using the required public Lua APIs
- ETHOS 26.1.x, including ETHOS 26.1.2

## Installation

The attached `GIB2A-POWER-v26.1.2.zip` is the ETHOS Suite installation package.

Open ETHOS Suite:

`Lua Library > Install from local .zip`

Select the ZIP without extracting it.

The manifest installs the widget into:

`RADIO:/scripts/GIB2APW/`

Restart the radio, discover telemetry and verify all assigned sources before flight.

## Download

Download the attached:

`GIB2A-POWER-v26.1.2.zip`

## Validation

- Lua syntax and local mock suite: PASS
- 161,145 assertions across 18 viewport sizes
- Smart Battery, RPM 0 direct target, RPM-active limiting, linear SOC interpolation, alarms, callouts, telemetry, layouts, annulus drawing, chrono, and persistence: PASS locally
- Physical radio and ESC validation: not performed for this release build

## License

MIT License.
