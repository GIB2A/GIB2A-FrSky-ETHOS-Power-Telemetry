# GIB2A POWER v26.1.1 — FrSky Neuron ESC Telemetry for ETHOS

### Advanced FrSky Neuron ESC Telemetry Dashboard for ETHOS

GIB2A POWER is the official electric telemetry sibling to GIB2A TURBINE in the **GIB2A Advanced Telemetry Dashboard** family. It provides a responsive, flight-oriented view of FrSky Neuron ESC telemetry and sends no control commands.

## Highlights

- 24-sector Voltage, Battery, RPM, and ESC temperature gauges
- Battery percentage calculated from stabilized and filtered pack voltage
- Monotonic Battery indication with controlled decreases and upward rebound blocked until reset
- ESC current and consumed capacity telemetry
- Auto Bind for seven Neuron telemetry roles using AppID families and units
- Configurable battery, pack-voltage, temperature, and RPM alarms
- Battery callouts at 50% and 35%
- Manual receiver voltage, RSSI, DIY, and chrono sources
- Three display themes and responsive layouts for 480x300, 480x320, and 800x480

## Telemetry

Auto Bind covers ESC voltage, ESC current, RPM, ESC temperature, consumed capacity, BEC voltage, and BEC current. Additional receiver voltage, RSSI, DIY, and chrono sources remain available through manual configuration.

## Compatibility

- FrSky Neuron ESC telemetry
- FrSky ETHOS radios with the required public Lua APIs
- ETHOS 1.6.x and ETHOS 26.1.0-RC3 compatibility targeted where possible

The supported layouts passed local mock and rendering checks. Physical validation on a specific radio, ETHOS firmware, and Neuron ESC has not been performed as part of this package review.

## Installation

The attached `GIB2A-POWER-v26.1.1.zip` is the ETHOS Suite installation package. Its manifest and payload files are stored directly at the ZIP root. The manifest installs the widget into `RADIO:/scripts/GIB2APW/`; the internal widget key remains `GIB2APW`.

Open ETHOS Suite, select `Lua Library` > `Install from local .zip`, and choose the archive without extracting it. Restart the radio, discover telemetry, and verify all assigned sources before flight.

## Download

Download the attached `GIB2A-POWER-v26.1.1.zip` asset from this Release.

## Validation

- Local mock Lua 5.3 validation: PASS — 161,010 assertions, 18 viewport sizes
- Installation of the final ZIP through ETHOS Suite: PASS
- In-flight validation of a specific radio, firmware, and ESC combination is not claimed by package validation

## GIB2A Product Family

- [GIB2A TURBINE](https://github.com/GIB2A/GIB2A-FrSky-ETHOS-Turbine-Telemetry) — Advanced turbine telemetry dashboard for ETHOS.
- **GIB2A POWER** — Advanced electric power and FrSky Neuron ESC telemetry dashboard for ETHOS.

Both products belong to **GIB2A — Advanced Telemetry Dashboards for ETHOS**.
