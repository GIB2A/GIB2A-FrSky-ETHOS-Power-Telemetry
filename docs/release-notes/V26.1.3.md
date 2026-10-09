# GIB2A POWER v26.1.3 — FrSky Neuron ESC Telemetry for ETHOS

### Advanced FrSky Neuron ESC Telemetry Dashboard for ETHOS

GIB2A POWER is the electric telemetry dashboard of the GIB2A Advanced Telemetry Dashboard family.

## What's New in v26.1.3

- Improved ETHOS context-menu responsiveness by limiting automatic display invalidation to 1 Hz
- Telemetry acquisition frequency remains unchanged
- Explicit user actions retain immediate display invalidation
- Annular gauge sectors use the native ETHOS renderer directly
- Experimental pre-rasterized PNG masks and their renderer were removed
- RSSI 2.4 and RSSI 900 use a `dB` display fallback when ETHOS supplies an empty unit, on both Dashboard and Flight Summary
- RX Battery uses the normalized and cached standard telemetry-source engine while remaining manually selected
- Source recovery preserves cached direct reads and keeps the dedicated delayed-retry behavior for RSSI
- Flight Summary includes Max RPM, Max Current, Max Power, Min Pack Voltage, duration, and separate RSSI 2.4/900 minima
- Existing telemetry mappings, Auto Bind, Smart Battery, alarms, callouts, chrono, persistence, and X20/X18/X14 layouts otherwise remain unchanged

## Compatibility

- FrSky Neuron ESC telemetry
- FrSky ETHOS radios using the required public Lua APIs
- ETHOS 26.1.x
- Native gauge rendering and 1 Hz display-refresh behavior validated on X20 Pro AW with ETHOS 26.1 Nightly
- Validation on every stable ETHOS release is not claimed

## Installation

The attached `GIB2A-POWER-v26.1.3.zip` is the ETHOS Suite installation package.

Open ETHOS Suite:

`Lua Library > Install from local .zip`

Select the ZIP without extracting it. The manifest installs the widget into:

`RADIO:/scripts/GIB2APW/`

Restart the radio, discover telemetry and verify all assigned sources before flight.

## Validation

- Lua syntax and package integrity must pass before publication
- Native gauge rendering and the 1 Hz graphical refresh behavior were validated on X20 Pro AW with ETHOS 26.1 Nightly
- This validation does not cover every stable ETHOS release
- Local Lua and package checks do not replace complete validation of the final package on the target radio and ESC

## License

MIT License.
