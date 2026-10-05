# GIB2A POWER — Installation

### Advanced FrSky Neuron ESC Telemetry Dashboard for ETHOS

GIB2A POWER is part of the **GIB2A Advanced Telemetry Dashboard** family and is the electric counterpart to [GIB2A TURBINE](https://github.com/GIB2A/GIB2A-FrSky-ETHOS-Turbine-Telemetry).

## ETHOS Suite Installation

1. Download `GIB2A-POWER-v26.1.2.zip` from the v26.1.2 GitHub Release.
2. Verify the ZIP SHA-256 against `releases/V26.1.2/SHA256SUMS.txt`.
3. Open ETHOS Suite.
4. Select `Lua Library` > `Install from local .zip`.
5. Select the archive without extracting it.
6. Let ETHOS Suite install the `GIB2APW` folder.
7. Restart the radio and add `GIB2A POWER V26.1.2` to a view.
8. Discover telemetry, run Auto Bind if appropriate, and verify each source.

The ZIP stores `ethos_lua_manifest.json` and all declared package files directly at its root. The manifest field `folder` instructs ETHOS Suite to install the widget into `RADIO:/scripts/GIB2APW/`. The ZIP root and the installed widget directory are therefore different concepts.

## Manual Installation

Create `SCRIPTS/GIB2APW/` on the radio SD card. Copy `main.lua` and `gib2a_logo_ethos_180.png` from the ZIP root into that directory, then restart the radio.

## Configuration Check

1. Discover the FrSky Neuron telemetry sensors.
2. Open the GIB2A POWER configuration page.
3. Run Auto Bind or assign each source manually.
4. Set the correct battery cell count.
5. Review voltage, Battery, RPM, and temperature thresholds.
6. Confirm the configured audio files are present on the radio.
7. Verify every displayed value before flight.

Battery percentage is an estimated LiPo state of charge calculated from stabilized and filtered ESC pack voltage. When RPM is inactive, it follows the calculated voltage-based target. When RPM is active, downward changes are rate-limited and upward rebound is blocked. The widget is telemetry-only and does not configure or control the ESC.

Responsive layouts have passed local checks at 480x300, 480x320, and 800x480. Validate the complete installation on the intended radio, ETHOS firmware, and Neuron ESC before flight.
