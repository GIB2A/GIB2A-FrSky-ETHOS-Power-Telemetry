# GIB2A POWER

### Advanced FrSky Neuron ESC Telemetry Dashboard for ETHOS

Part of the **GIB2A Advanced Telemetry Dashboard** family.

![GIB2A POWER](docs/GIB2A%20PW.png)

## Overview

GIB2A POWER is the electric power telemetry dashboard in the GIB2A product family. Designed for FrSky ETHOS radios and FrSky Neuron ESC telemetry, it presents essential propulsion and battery data in a clear in-flight display.

It is the official electric-power sibling to [GIB2A TURBINE](https://github.com/GIB2A/GIB2A-FrSky-ETHOS-Turbine-Telemetry) and follows the same focus on readable telemetry, controlled configuration, and flight-oriented alerts. The widget is telemetry-only and sends no control commands to the ESC, receiver, motor, or servos.

## Features

- 24-sector Voltage, Battery, RPM, and ESC temperature gauges
- Battery percentage calculated from stabilized and filtered pack voltage
- Monotonic Battery indication during a run, with controlled decreases and no upward rebound before reset
- ESC consumption display in mAh
- Auto Bind for seven FrSky Neuron telemetry roles using AppID families and units
- Manual source selection for receiver voltage, RSSI, DIY fields, and chrono
- Configurable battery, pack-voltage, temperature, and RPM alarms
- Battery callouts at 50% and 35%
- Standard, high-contrast, and amber themes
- Responsive layouts for 480x300, 480x320, and 800x480 widget areas
- Protected source reads and cached drawing data

## Telemetry

Auto Bind covers ESC voltage, ESC current, RPM, ESC temperature, consumed capacity, BEC voltage, and BEC current. Receiver voltage, RSSI 2.4 GHz, RSSI 900 MHz, two DIY fields, and a chrono source can be assigned manually.

Battery percentage is derived from the stabilized and filtered ESC pack voltage. Set the correct cell count before using the Battery gauge or voltage alarms.

## Compatibility

GIB2A POWER supports FrSky Neuron ESC telemetry through the public FrSky ETHOS Lua API. The code targets ETHOS 1.6.x and ETHOS 26.1.0-RC3 compatibility where the required public APIs are available.

### ETHOS Radio Compatibility

Responsive layouts for 480x300, 480x320, and 800x480 have passed local rendering checks. A specific radio, ETHOS firmware, and Neuron ESC combination must still be verified on target hardware before flight.

## Installation

### ETHOS Suite Installation

1. Download `GIB2A-POWER-v26.1.1.zip` from the GitHub Release.
2. Open ETHOS Suite and select `Lua Library` > `Install from local .zip`.
3. Select the ZIP without extracting it.
4. Let ETHOS Suite install the `GIB2APW` widget folder.
5. Restart the radio and add `GIB2A POWER V26.1.1` to a view.
6. Discover telemetry, run Auto Bind if appropriate, and verify every assigned source before flight.

The ETHOS Suite package stores its manifest and payload files directly at the ZIP root. The manifest installs those files into `RADIO:/scripts/GIB2APW/`.

For manual installation, create `SCRIPTS/GIB2APW/` on the radio SD card and copy `main.lua` and `gib2a_logo_ethos_180.png` from the package into that directory, then restart the radio.

See [Installation](docs/INSTALLATION.md) for the complete procedure.

## Configuration

Discover the telemetry sensors on the radio before opening the widget configuration. Auto Bind assigns the seven supported Neuron roles; all telemetry fields can also be selected manually. Configure the battery cell count, display ranges, alarm thresholds, sound files, and theme for the model.

The default pack-voltage thresholds are 3.8 V per cell for Warning and 3.7 V per cell for Critical.

## Audio Alerts

GIB2A POWER supports configurable battery, voltage, temperature, and RPM alert files. Battery callouts at 50% and 35% can be enabled or disabled. Audio alerts report telemetry conditions only and do not control the power system.

## Download

Download the ETHOS Suite installation package:

[GIB2A POWER v26.1.1 — Download ZIP](https://github.com/GIB2A/GIB2A-FrSky-ETHOS-Power-Telemetry/releases/download/v26.1.1/GIB2A-POWER-v26.1.1.zip)

## Release

- Version: `26.1.1`
- Tag: `v26.1.1`
- Package: `GIB2A-POWER-v26.1.1.zip`
- Installed folder: `GIB2APW`
- Internal widget key: `GIB2APW`

Local validation passed 161,010 assertions across 18 viewport sizes in a mock Lua 5.3 runtime. Installation of the final package through ETHOS Suite has also been confirmed. This evidence does not replace in-flight validation of a specific radio, firmware, and ESC combination. See the [v26.1.1 release notes](docs/release-notes/V26.1.1.md) and [SHA-256 checksums](releases/V26.1.1/SHA256SUMS.txt).

## GIB2A Product Family

- [GIB2A TURBINE](https://github.com/GIB2A/GIB2A-FrSky-ETHOS-Turbine-Telemetry) — Advanced turbine telemetry dashboard for ETHOS.
- **GIB2A POWER** — Advanced electric power and FrSky Neuron ESC telemetry dashboard for ETHOS.

Both products belong to **GIB2A — Advanced Telemetry Dashboards for ETHOS**.

## License

Released under the [MIT License](LICENSE).

GIB2A is an independent project and is not affiliated with FrSky. No manufacturer certification is claimed.
