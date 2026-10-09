-- GIB2A POWER - V26.1.3
-- Telemetry only. No ESC configuration or control.

-- Metadata / constants
local WIDGET_VERSION = "V26.1.3"
local SOURCE_RECOVERY_SECONDS = 1
local DISPLAY_REFRESH_SECONDS = 1.00
local VOLTAGE_RECOVERY_HYSTERESIS = 0.10
local VOLTAGE_WARNING_CONFIRM_TIME = 4.0
local VOLTAGE_CRITICAL_CONFIRM_TIME = 2.0
local VOLTAGE_ALARM_REPEAT_SECONDS = 10
local TEMP_ALARM_HYSTERESIS = 2.0
local RPM_ALARM_MIN_HYSTERESIS = 100
local BATTERY_CALLOUT_50 = 50
local BATTERY_CALLOUT_35 = 35
local BATTERY_CALLOUT_50_REARM = 52
local BATTERY_CALLOUT_35_REARM = 37
local BATTERY_THRESHOLD_EPSILON = 0.000001
local BATTERY_STABILIZATION_DELAY = 1.5
local BATTERY_STABILIZATION_SAMPLES = 5
local BATTERY_STABILIZATION_SPREAD = 0.15
local BATTERY_MAX_CELL_VOLTAGE = 4.30
local BATTERY_MAX_VOLTAGE_FALL_PER_CELL_SECOND = 0.05
local BATTERY_MAX_DROP_PERCENT_PER_SECOND = 1
local BATTERY_SAG_COMPENSATION = 0.7
local BATTERY_RPM_ACTIVE_MINIMUM = 100
local FLIGHT_RPM_ACTIVE_MINIMUM = 100
local FLIGHT_END_CONFIRM_SECONDS = 5
local VOLTAGE_NORMAL = "NORMAL"
local VOLTAGE_WARNING = "WARNING"
local VOLTAGE_CRITICAL = "CRITICAL"
local LOGO_PATH = "gib2a_logo_ethos_180.png"
local logo = nil -- loaded once in init(), never from paint()
local audioPath = "/audio"
if system and system.getAudioVoice then
    local ok, path = pcall(system.getAudioVoice)
    if ok and type(path) == "string" and path ~= "" then audioPath = path end
end

-- User configuration: shared ordered schema for read/write.
local SETTINGS = {
    { key = "rpmMax", default = 20000, min = 1, max = 500000 },
    { key = "tempMax", default = 150, min = 1, max = 500 },
    { key = "batteryCells", default = 6, min = 2, max = 12 },
    { key = "batteryCalloutsEnabled", default = 1, min = 0, max = 1 },
    { key = "batteryWarningPercent", default = 25, min = 0, max = 100 },
    { key = "batteryCriticalPercent", default = 15, min = 0, max = 100 },
    { key = "voltageWarningPerCell", default = 3.8, min = 3.0, max = 4.5, decimals = 1 },
    { key = "voltageCriticalPerCell", default = 3.7, min = 3.0, max = 4.5, decimals = 1 },
    { key = "tempAlarmThreshold", default = 0, min = 0, max = 200 },
    { key = "rpmAlarmThreshold", default = 0, min = 0, max = 500000 },
    { key = "theme", default = 0, min = 0, max = 2 },
}
local FILE_SETTINGS = { "batteryCallout50File", "batteryCallout35File",
    "batteryWarningFile", "batteryCriticalFile",
    "voltageWarningFile", "voltageCriticalFile", "tempAlarmFile", "rpmAlarmFile" }

-- Source definitions. Auto Bind derives its roles from Neuron-marked entries.
local SOURCES = {
    { id = "voltage", field = "voltageSource", label = "ESC Voltage",
        unitKind = "voltage", appFamily = 0x0B50, neuron = true },
    { id = "escCurrent", field = "escCurrentSource", label = "ESC Current",
        unitKind = "current", appFamily = 0x0B50, neuron = true },
    { id = "rpm", field = "rpmSource", label = "ESC RPM",
        unitKind = "rpm", appFamily = 0x0B60, neuron = true },
    { id = "temp", field = "tempSource", label = "ESC Temp",
        unitKind = "temperature", appFamily = 0x0B70, neuron = true },
    { id = "consumption", field = "consumptionSource", label = "ESC Consumption",
        unitKind = "consumption", appFamily = 0x0B60, neuron = true },
    { id = "becVoltage", field = "becVoltageSource", label = "BEC Voltage",
        unitKind = "voltage", appFamily = 0x0E50, neuron = true },
    { id = "becCurrent", field = "becCurrentSource", label = "BEC Current",
        unitKind = "current", appFamily = 0x0E50, neuron = true },
    { id = "rx", field = "rxBatterySource", label = "RX Battery" },
    { id = "chrono", field = "chronoSource", storageKey = "chronoSource",
        label = "Chrono Source" },
    { id = "diy1", field = "diy1Source", label = "DIY 1" },
    { id = "diy2", field = "diy2Source", label = "DIY 2" },
    { id = "rssi1", field = "rssi24Source", label = "RSSI 2.4" },
    { id = "rssi2", field = "rssi900Source", label = "RSSI 900" },
}
local SOURCE_BY_ID = {}
local AUTO_BIND_TOTAL = 0
for _, definition in ipairs(SOURCES) do
    SOURCE_BY_ID[definition.id] = definition
    if definition.neuron then AUTO_BIND_TOTAL = AUTO_BIND_TOTAL + 1 end
end
local GAUGES = {
    { id = "voltage", unit = "VOLTAGE", type = "VOLTAGE", min = 0, max = 60 },
    { id = "battery", unit = "BATTERY %", type = "BATTERY", min = 0, max = 100 },
    { id = "rpm", unit = "RPM", type = "RPM", min = 0 },
    { id = "temp", unit = "TEMP °C", type = "TEMP", min = 0 },
}

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

-- GIB2A empirical LiPo SOC calibration based on independent battery measurements.
-- Provisional curve: add anchors only after new GIB2A measurements are validated.
local GIB2A_LIPO_SOC_CURVE = {
    { voltage = 3.000, soc = 0 },   -- Existing GIB2A per-cell safety limit.
    { voltage = 3.750, soc = 20 },  -- GIB2A Robbe / ISDT measurement zone.
    { voltage = 3.803, soc = 33 },  -- GIB2A Robbe / ISDT measurement zone.
    { voltage = 4.200, soc = 100 }, -- Standard LiPo full-charge endpoint.
}

local function validateBatteryAlarmThresholds(config)
    if config.batteryWarningPercent <= 0 then
        config.batteryWarningPercent, config.batteryCriticalPercent = 0, 0
    elseif config.batteryCriticalPercent >= config.batteryWarningPercent then
        config.batteryCriticalPercent = math.max(0, config.batteryWarningPercent - 1)
    end
end

local function validateVoltageAlarmThresholds(config)
    config.voltageWarningPerCell = clamp(config.voltageWarningPerCell, 3.0, 4.5)
    config.voltageCriticalPerCell = clamp(config.voltageCriticalPerCell, 3.0, 4.5)
    if config.voltageCriticalPerCell >= config.voltageWarningPerCell then
        if config.voltageWarningPerCell <= 3.0 then
            config.voltageWarningPerCell = 3.1
        end
        config.voltageCriticalPerCell = math.max(3.0, config.voltageWarningPerCell - 0.1)
    end
end

local function resetSmartBattery(widget)
    if widget.values and widget.values.battery ~= nil then widget.dirty = true end
    widget.batteryVoltageSamples = {}
    widget.batteryStabilizeNotBefore = nil
    widget.batteryFilteredVoltage = nil
    widget.batteryLastUpdateAt = nil
    widget.batteryLastRpm = nil
    widget.batteryConfigCells = widget.config.batteryCells
    widget.batteryCallout50Armed, widget.batteryCallout35Armed = true, true
    if widget.values then widget.values.battery = nil end
end

local function voltagePackThresholds(widget)
    local cells = widget.config.batteryCells
    return cells * widget.config.voltageWarningPerCell,
        cells * widget.config.voltageCriticalPerCell,
        cells * VOLTAGE_RECOVERY_HYSTERESIS
end

-- Same three-theme principle as GIB2A TURBINE, adapted to POWER roles.
local function getPalette(theme)
    if theme == 1 then
        return { background = lcd.RGB(0, 0, 0), main = lcd.RGB(0, 220, 255),
            inactive = lcd.RGB(40, 40, 60), text = lcd.RGB(255, 255, 255), value = lcd.RGB(255, 255, 255),
            warning = lcd.RGB(255, 210, 0), critical = lcd.RGB(255, 80, 120) }
    elseif theme == 2 then
        return { background = lcd.RGB(0, 0, 0), main = lcd.RGB(255, 180, 0),
            inactive = lcd.RGB(60, 30, 0), text = lcd.RGB(255, 230, 200), value = lcd.RGB(255, 255, 255),
            warning = lcd.RGB(255, 120, 0), critical = lcd.RGB(255, 60, 0) }
    end
    return { background = lcd.RGB(0, 0, 0), main = lcd.RGB(0, 160, 0),
        inactive = lcd.RGB(60, 60, 60), text = lcd.RGB(255, 255, 255), value = lcd.RGB(255, 255, 255),
        warning = lcd.RGB(255, 210, 0), critical = lcd.RGB(255, 0, 0) }
end

local function playConfiguredAudio(fileName)
    if type(fileName) ~= "string" or fileName == "" or not system.playFile then return end
    local path = fileName
    if string.sub(fileName, 1, 1) ~= "/" then path = audioPath .. "/" .. fileName end
    pcall(system.playFile, path)
end

local function signalAlarm(fileName, hapticDuration, percent)
    if system.playHaptic then system.playHaptic(hapticDuration) end
    playConfiguredAudio(fileName)
    if finite(percent) and UNIT_PERCENT then
        system.playNumber(math.floor(percent + 0.5), UNIT_PERCENT, 0)
    end
end

local function signalVoltageAlarm(fileName, hapticDuration)
    if system.playHaptic then system.playHaptic(hapticDuration) end
    playConfiguredAudio(fileName)
end

local function playBatteryCallout(widget, percent)
    local fileName = percent == BATTERY_CALLOUT_50
        and widget.config.batteryCallout50File or widget.config.batteryCallout35File
    if type(fileName) == "string" and fileName ~= "" then
        playConfiguredAudio(fileName)
    end
    if system.playNumber and UNIT_PERCENT then
        system.playNumber(percent, UNIT_PERCENT, 0)
    end
end

local function resetFlightSummary(widget)
    widget.flightSummary = {
        active = false,
        completed = false,
        maxRpm = nil,
        maxCurrent = nil,
        maxPower = nil,
        minVoltage = nil,
        duration = 0,
        minRf1 = nil,
        minRf2 = nil,
        startedAt = nil,
        startChrono = nil,
        inactiveSince = nil,
        voltageLostSince = nil,
    }
    widget.dirty = true
end

local function create()
    local widget = { config = {}, values = {}, units = {},
        chrono = "--",
        view = "dashboard",
        voltageState = nil, voltageWarningPendingAt = nil, voltageCriticalPendingAt = nil,
        voltageAlarmRepeatAt = nil,
        tempAlarmActive = false, rpmAlarmActive = false,
        batteryCallout50Armed = true, batteryCallout35Armed = true,
        _autoBindStatus = string.format("Auto-bind NEURON: 0/%d sensors", AUTO_BIND_TOTAL),
        _normalizedTelemetrySources = {}, _resolvedRssiSources = {},
        _sourceRecoveryAt = {}, _sourceUnits = {}, _nextDisplayRefreshAt = nil,
        dirty = true }
    for _, setting in ipairs(SETTINGS) do
        widget.config[setting.key] = setting.default
    end
    resetSmartBattery(widget)
    resetFlightSummary(widget)
    return widget
end

local NORMALIZED_TELEMETRY_SOURCE_FIELDS = {
    voltageSource = true,
    escCurrentSource = true,
    rpmSource = true,
    consumptionSource = true,
    tempSource = true,
    becVoltageSource = true,
    becCurrentSource = true,
    rxBatterySource = true,
    chronoSource = true,
    diy1Source = true,
    diy2Source = true,
}

local SYSTEM_SOURCE_FIELDS = {
    rssi24Source = true,
    rssi900Source = true,
}

local function setWidgetSource(widget, definition, source, alreadyNormalized)
    widget[definition.field] = source
    widget._normalizedTelemetrySources[definition.field] = alreadyNormalized and source or nil
    widget._resolvedRssiSources = widget._resolvedRssiSources or {}
    widget._resolvedRssiSources[definition.field] = nil
    widget._sourceRecoveryAt[definition.field] = nil
    widget._sourceUnits[definition.id] = nil
    widget.values[definition.id], widget.units[definition.id] = nil, ""
end

local function normalizeTelemetrySource(widget, srcField)
    local src = widget[srcField]

    if not src then
        widget._normalizedTelemetrySources[srcField] = nil
        return nil
    end

    if not NORMALIZED_TELEMETRY_SOURCE_FIELDS[srcField] then
        return src
    end

    if widget._normalizedTelemetrySources[srcField] == src then
        return src
    end

    local resolvedSource = src
    if type(src.name) == "function" and system.getSource then
        local okName, name = pcall(src.name, src)
        if okName and type(name) == "string" and name ~= "" then
            local okSource, source = pcall(system.getSource, name)
            if okSource and source and type(source.value) == "function" then
                resolvedSource = source
                widget[srcField] = source
            end
        end
    end

    widget._normalizedTelemetrySources[srcField] = resolvedSource
    return resolvedSource
end

local function sourceEngineNow()
    if os and type(os.clock) == "function" then
        local ok, now = pcall(os.clock)
        if ok and finite(now) then return now end
    end
    if system.getTimeCounter then
        local ok, ticks = pcall(system.getTimeCounter)
        if ok and finite(ticks) then return ticks / 100 end
    end
    return nil
end

local function readSourceValue(widget, srcField)
    if not widget or not srcField then
        return nil
    end

    local src = normalizeTelemetrySource(widget, srcField)
    if not src or type(src.value) ~= "function" then
        return nil
    end

    local okValue, value = pcall(src.value, src)
    if okValue then
        return value
    end

    local now = system.getTimeCounter and system.getTimeCounter() / 100 or os.clock()
    widget._sourceRecoveryAt = widget._sourceRecoveryAt or {}
    local lastRecovery = widget._sourceRecoveryAt[srcField]
    if lastRecovery and (now - lastRecovery) < SOURCE_RECOVERY_SECONDS then
        return nil
    end
    widget._sourceRecoveryAt[srcField] = now

    if type(src.name) ~= "function" or not system.getSource then
        return nil
    end

    local okName, name = pcall(src.name, src)
    if not okName or type(name) ~= "string" or name == "" then
        return nil
    end

    local okSource, recoveredSource = pcall(system.getSource, name)
    if not okSource or not recoveredSource or type(recoveredSource.value) ~= "function" then
        return nil
    end

    widget[srcField] = recoveredSource
    widget._normalizedTelemetrySources[srcField] = recoveredSource
    local okRecoveredValue, recoveredValue = pcall(recoveredSource.value, recoveredSource)
    if okRecoveredValue then
        return recoveredValue
    end

    return nil
end

local function readSystemSourceValue(widget, srcField)
    local src = widget[srcField]
    if not src then
        return nil
    end

    if type(src.value) == "function" then
        local okValue, value = pcall(src.value, src)
        if okValue and finite(value) then
            return value
        end
    end

    local now = sourceEngineNow()
    if now == nil then return nil end
    local lastRecovery = widget._sourceRecoveryAt[srcField]
    if lastRecovery and (now - lastRecovery) < SOURCE_RECOVERY_SECONDS then
        return nil
    end
    widget._sourceRecoveryAt[srcField] = now

    if type(src.name) == "function" and system.getSource then
        local okName, name = pcall(src.name, src)
        if okName and type(name) == "string" and name ~= "" then
            local okSource, recoveredSource = pcall(system.getSource, name)
            if okSource and recoveredSource and recoveredSource ~= src
                and type(recoveredSource.value) == "function" then
                local okValue, value = pcall(recoveredSource.value, recoveredSource)
                if okValue and finite(value) then
                    return value
                end
            end
        end
    end

    return nil
end

local function readRssiSourceValue(widget, srcField)
    local src = widget[srcField]
    if not src then return nil end

    widget._resolvedRssiSources = widget._resolvedRssiSources or {}
    local cached = widget._resolvedRssiSources[srcField]
    if cached and cached.selected ~= src then
        widget._resolvedRssiSources[srcField] = nil
        widget._sourceRecoveryAt[srcField] = nil
        cached = nil
    end

    if cached and type(cached.source.value) == "function" then
        local okValue, value = pcall(cached.source.value, cached.source)
        if okValue then return value end
        widget._resolvedRssiSources[srcField] = nil
    end

    local now = sourceEngineNow()
    widget._sourceRecoveryAt = widget._sourceRecoveryAt or {}
    local lastRecovery = widget._sourceRecoveryAt[srcField]
    if now ~= nil and lastRecovery
        and (now - lastRecovery) < SOURCE_RECOVERY_SECONDS then
        if type(src.value) == "function" then
            local okFallback, fallbackValue = pcall(src.value, src)
            if okFallback then return fallbackValue end
        end
        return nil
    end
    widget._sourceRecoveryAt[srcField] = now or lastRecovery

    if type(src.name) == "function" and system.getSource then
        local okName, name = pcall(src.name, src)
        if okName and type(name) == "string" and name ~= "" then
            local okSource, resolvedSource = pcall(system.getSource, name)
            if okSource and resolvedSource and type(resolvedSource.value) == "function" then
                widget._resolvedRssiSources[srcField] = {
                    selected = src, source = resolvedSource }
                local okValue, value = pcall(resolvedSource.value, resolvedSource)
                if okValue then return value end
                widget._resolvedRssiSources[srcField] = nil
            end
        end
    end

    if type(src.value) == "function" then
        local okFallback, fallbackValue = pcall(src.value, src)
        if okFallback then return fallbackValue end
    end

    return nil
end

local function canonicalPhysicalUnit(unit)
    if UNIT_VOLT ~= nil and unit == UNIT_VOLT then return "V" end
    if UNIT_AMPERE ~= nil and unit == UNIT_AMPERE then return "A" end
    if UNIT_MILLIAMPERE ~= nil and unit == UNIT_MILLIAMPERE then return "mA" end
    if UNIT_MILLIAMPERE_HOUR ~= nil and unit == UNIT_MILLIAMPERE_HOUR then return "mAh" end
    if UNIT_AMPERE_HOUR ~= nil and unit == UNIT_AMPERE_HOUR then return "Ah" end
    if UNIT_RPM ~= nil and unit == UNIT_RPM then return "RPM" end
    if UNIT_CELSIUS ~= nil and unit == UNIT_CELSIUS then return "°C" end
    if UNIT_FAHRENHEIT ~= nil and unit == UNIT_FAHRENHEIT then return "°F" end
    if UNIT_PERCENT ~= nil and unit == UNIT_PERCENT then return "%" end
    return nil
end

local function sourceUnit(src)
    if not src or type(src.stringUnit) ~= "function" then return nil end
    local okUnit, unit = pcall(src.stringUnit, src)
    if not okUnit or type(unit) ~= "string" then return nil end
    unit = unit:gsub("^%s+", ""):gsub("%s+$", "")
    if unit == "" then return nil end
    return unit
end

local function sourcePhysicalUnit(src)
    if not src or type(src.unit) ~= "function" then return nil end
    local okUnit, unit = pcall(src.unit, src)
    if okUnit then return unit end
    return nil
end

local function physicalIs(physical, expected)
    return expected ~= nil and physical == expected
end

local function normalize(id, value, unit, physical)
    if not finite(value) then return nil, "" end
    -- Preserve every finite raw value. Convert only units with a known scale;
    -- otherwise use the role's expected display unit.
    if id == "voltage" then
        if unit == "mV" then return value / 1000, "V" end
        return value, "V"
    elseif id == "becVoltage" then
        if unit == "mV" then return value / 1000, "V" end
        return value, "V"
    elseif id == "escCurrent" or id == "becCurrent" then
        if unit == "mA" or physicalIs(physical, UNIT_MILLIAMPERE) then
            return value / 1000, "A"
        end
        return value, "A"
    elseif id == "consumption" then
        if value < 0 then return nil, "" end
        if unit == "Ah" then return value * 1000, "mAh" end
        if physicalIs(physical, UNIT_AMPERE_HOUR) then return value * 1000, "mAh" end
        return value, "mAh"
    elseif id == "chrono" then
        return value, ""
    elseif id == "rpm" then
        return value, "RPM"
    elseif id == "temp" then
        if unit == "°F" or unit == "F" then return (value - 32) * 5 / 9, "°C" end
        if physicalIs(physical, UNIT_FAHRENHEIT) then return (value - 32) * 5 / 9, "°C" end
        return value, "°C"
    elseif id == "rssi1" or id == "rssi2" then
        return value, unit ~= "" and unit or "dB"
    elseif id == "rx" or id == "diy1" or id == "diy2" then
        return value, unit -- generic sources retain the exact ETHOS unit
    end
    return nil, ""
end

local function isUsableSource(src)
    return src and (type(src.name) == "function" or type(src.value) == "function")
end

local function protectedAutoBindProperty(source, method)
    local okMethod, fn = pcall(function() return source[method] end)
    if not okMethod or type(fn) ~= "function" then return nil end
    local okValue, value = pcall(fn, source)
    if okValue then return value end
    return nil
end

local function unitMatches(kind, text, physical)
    local normalized = type(text) == "string"
        and string.lower(text:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    if kind == "voltage" then
        return physicalIs(physical, UNIT_VOLT) or normalized == "v" or normalized == "mv"
    elseif kind == "current" then
        return physicalIs(physical, UNIT_AMPERE) or physicalIs(physical, UNIT_MILLIAMPERE)
            or normalized == "a" or normalized == "ma"
    elseif kind == "rpm" then
        return physicalIs(physical, UNIT_RPM) or normalized == "rpm" or normalized == "r/min"
    elseif kind == "consumption" then
        return physicalIs(physical, UNIT_MILLIAMPERE_HOUR) or physicalIs(physical, UNIT_AMPERE_HOUR)
            or normalized == "mah" or normalized == "ah"
    elseif kind == "temperature" then
        return physicalIs(physical, UNIT_CELSIUS) or normalized == "°c" or normalized == "c"
    end
    return false
end

local function collectTelemetrySources()
    if not system.getSources or CATEGORY_TELEMETRY_SENSOR == nil then return nil end
    local okSources, sources = pcall(system.getSources, CATEGORY_TELEMETRY_SENSOR)
    if not okSources or type(sources) ~= "table" then return nil end
    local discovered = {}
    for _, source in ipairs(sources) do
        if isUsableSource(source) then
            discovered[#discovered + 1] = {
                source = source,
                stringUnit = protectedAutoBindProperty(source, "stringUnit") or "",
                physicalUnit = protectedAutoBindProperty(source, "unit"),
                appId = protectedAutoBindProperty(source, "appId"),
            }
        end
    end
    return discovered
end

local function addAutoBindCandidate(candidates, id, record)
    local bucket = candidates[id]
    if not bucket then bucket = {}; candidates[id] = bucket end
    for _, existing in ipairs(bucket) do
        if existing.source == record.source then return end
    end
    bucket[#bucket + 1] = record
end

local function autoBindNeuron(widget)
    local discovered = collectTelemetrySources() or {}
    local candidates = {}
    for _, record in ipairs(discovered) do
        local family = type(record.appId) == "number"
            and record.appId - record.appId % 0x10 or nil
        for _, definition in ipairs(SOURCES) do
            if definition.neuron and definition.appFamily == family
                and unitMatches(definition.unitKind, record.stringUnit, record.physicalUnit) then
                addAutoBindCandidate(candidates, definition.id, record)
            end
        end
    end

    local bound = 0
    for _, definition in ipairs(SOURCES) do
        local matches = definition.neuron and candidates[definition.id] or nil
        if matches and #matches == 1 then
            setWidgetSource(widget, definition, matches[1].source, true)
            bound = bound + 1
        end
    end

    widget._autoBindStatus = "Auto-bind NEURON: "
        .. tostring(bound) .. "/" .. tostring(AUTO_BIND_TOTAL) .. " sensors"

    lcd.invalidate()
end

local function batteryPercentFromCellVoltage(cellVoltage)
    if not finite(cellVoltage) then return nil end
    local first = GIB2A_LIPO_SOC_CURVE[1]
    if cellVoltage < first.voltage then return 0 end
    for index = 2, #GIB2A_LIPO_SOC_CURVE do
        local lower = GIB2A_LIPO_SOC_CURVE[index - 1]
        local upper = GIB2A_LIPO_SOC_CURVE[index]
        if cellVoltage <= upper.voltage then
            local soc = lower.soc
                + (cellVoltage - lower.voltage)
                / (upper.voltage - lower.voltage)
                * (upper.soc - lower.soc)
            return clamp(soc, 0, 100)
        end
    end
    return 100
end

local function batterySagCompensatedCellVoltage(widget, cellVoltage)
    local rpm = widget.values.rpm
    if not finite(rpm) or rpm < BATTERY_RPM_ACTIVE_MINIMUM then
        return cellVoltage, false
    end
    local previousRpm = widget.batteryLastRpm
    widget.batteryLastRpm = rpm
    if not finite(previousRpm) or previousRpm <= 0 then return cellVoltage, true end
    local rpmDropFactor = math.max(0, (previousRpm - rpm) / previousRpm)
    local compensationScale = BATTERY_SAG_COMPENSATION ^ 1.5
    return cellVoltage + compensationScale * rpmDropFactor * 0.5, true
end

-- DashX-style Voltage Sensor: stabilized/filtered cell voltage drives Battery %.
local function updateBattery(widget)
    local values = widget.values
    local previous = values.battery
    local battery = nil
    local cells = widget.config.batteryCells
    local voltage = values.voltage

    if widget.batteryConfigCells ~= cells then
        resetSmartBattery(widget)
        previous = nil
    end

    local valid = finite(voltage) and voltage > 0 and finite(cells) and cells > 0
    local now = valid and sourceEngineNow() or nil
    if not valid or now == nil then
        if widget.batteryStabilizeNotBefore ~= nil or widget.batteryFilteredVoltage ~= nil
            or #widget.batteryVoltageSamples > 0 then
            resetSmartBattery(widget)
            previous = nil
        end
    elseif widget.batteryFilteredVoltage == nil then
        if widget.batteryStabilizeNotBefore == nil then
            widget.batteryStabilizeNotBefore = now + BATTERY_STABILIZATION_DELAY
        elseif now >= widget.batteryStabilizeNotBefore then
            local samples = widget.batteryVoltageSamples
            samples[#samples + 1] = voltage
            if #samples > BATTERY_STABILIZATION_SAMPLES then table.remove(samples, 1) end
            if #samples == BATTERY_STABILIZATION_SAMPLES then
                local minimum, maximum = samples[1], samples[1]
                for index = 1, BATTERY_STABILIZATION_SAMPLES do
                    local sample = samples[index]
                    minimum, maximum = math.min(minimum, sample), math.max(maximum, sample)
                end
                if maximum - minimum <= BATTERY_STABILIZATION_SPREAD then
                    widget.batteryFilteredVoltage = clamp(
                        voltage, 0,
                        BATTERY_MAX_CELL_VOLTAGE * cells)
                    widget.batteryLastUpdateAt = now
                    battery = batteryPercentFromCellVoltage(widget.batteryFilteredVoltage / cells)
                end
            end
        end
    else
        local elapsed = math.max(0, now - widget.batteryLastUpdateAt)
        local filteredVoltage = widget.batteryFilteredVoltage
        if voltage >= filteredVoltage then
            filteredVoltage = voltage
        else
            local maximumFall = BATTERY_MAX_VOLTAGE_FALL_PER_CELL_SECOND * cells * elapsed
            filteredVoltage = math.max(voltage, filteredVoltage - maximumFall)
        end
        widget.batteryFilteredVoltage = clamp(filteredVoltage, 0,
            BATTERY_MAX_CELL_VOLTAGE * cells)
        widget.batteryLastUpdateAt = now
        local compensatedCellVoltage, rpmActive = batterySagCompensatedCellVoltage(
            widget, widget.batteryFilteredVoltage / cells)
        local target = batteryPercentFromCellVoltage(compensatedCellVoltage)
        if previous ~= nil and rpmActive then
            if target < previous then
                battery = math.max(target, previous - BATTERY_MAX_DROP_PERCENT_PER_SECOND * elapsed)
            else
                battery = previous
            end
        else
            battery = target
        end
    end
    if previous ~= battery then widget.dirty = true end
    values.battery = battery
    if battery == nil then return end
    if battery > BATTERY_CALLOUT_50_REARM then widget.batteryCallout50Armed = true end
    if battery > BATTERY_CALLOUT_35_REARM then widget.batteryCallout35Armed = true end
    if previous == nil then return end
    if widget.config.batteryCalloutsEnabled == 1 then
        if widget.batteryCallout50Armed
            and previous > BATTERY_CALLOUT_50 + BATTERY_THRESHOLD_EPSILON
            and battery <= BATTERY_CALLOUT_50 + BATTERY_THRESHOLD_EPSILON then
            widget.batteryCallout50Armed = false
            playBatteryCallout(widget, BATTERY_CALLOUT_50)
        end
        if widget.batteryCallout35Armed
            and previous > BATTERY_CALLOUT_35 + BATTERY_THRESHOLD_EPSILON
            and battery <= BATTERY_CALLOUT_35 + BATTERY_THRESHOLD_EPSILON then
            widget.batteryCallout35Armed = false
            playBatteryCallout(widget, BATTERY_CALLOUT_35)
        end
    end
    local warning = widget.config.batteryWarningPercent
    local critical = widget.config.batteryCriticalPercent
    if critical > 0 and previous > critical + BATTERY_THRESHOLD_EPSILON
        and battery <= critical + BATTERY_THRESHOLD_EPSILON then
        signalAlarm(widget.config.batteryCriticalFile, 500, battery)
    elseif warning > 0 and previous > warning + BATTERY_THRESHOLD_EPSILON
        and battery <= warning + BATTERY_THRESHOLD_EPSILON then
        signalAlarm(widget.config.batteryWarningFile, 300, battery)
    end
end

local function updateVoltageState(widget)
    local voltage = widget.values.voltage
    local cells = widget.config.batteryCells
    local previous = widget.voltageState
    if voltage == nil or not finite(cells) or cells <= 0 then
        widget.voltageState = nil
        widget.voltageWarningPendingAt = nil
        widget.voltageCriticalPendingAt = nil
        widget.voltageAlarmRepeatAt = nil
        return
    end
    local warningPackVoltage, criticalPackVoltage, recoveryHysteresis = voltagePackThresholds(widget)
    local nextState = previous or VOLTAGE_NORMAL
    local now = sourceEngineNow()
    if previous == VOLTAGE_CRITICAL then
        widget.voltageWarningPendingAt = nil
        widget.voltageCriticalPendingAt = nil
        if voltage > warningPackVoltage + recoveryHysteresis then
            nextState = VOLTAGE_NORMAL
        elseif voltage > criticalPackVoltage + recoveryHysteresis then
            nextState = VOLTAGE_WARNING
        end
    elseif previous == VOLTAGE_WARNING then
        widget.voltageWarningPendingAt = nil
        if voltage > warningPackVoltage + recoveryHysteresis then
            nextState = VOLTAGE_NORMAL
            widget.voltageCriticalPendingAt = nil
        elseif voltage <= criticalPackVoltage + 0.000001 then
            if now == nil then
                widget.voltageCriticalPendingAt = nil
            elseif widget.voltageCriticalPendingAt == nil then
                widget.voltageCriticalPendingAt = now
            elseif now - widget.voltageCriticalPendingAt >= VOLTAGE_CRITICAL_CONFIRM_TIME then
                nextState = VOLTAGE_CRITICAL
                widget.voltageCriticalPendingAt = nil
            end
        else
            widget.voltageCriticalPendingAt = nil
        end
    else
        nextState = VOLTAGE_NORMAL
        if now == nil then
            widget.voltageWarningPendingAt = nil
            widget.voltageCriticalPendingAt = nil
        elseif voltage <= criticalPackVoltage + 0.000001 then
            widget.voltageWarningPendingAt = nil
            if widget.voltageCriticalPendingAt == nil then
                widget.voltageCriticalPendingAt = now
            elseif now - widget.voltageCriticalPendingAt >= VOLTAGE_CRITICAL_CONFIRM_TIME then
                nextState = VOLTAGE_CRITICAL
                widget.voltageCriticalPendingAt = nil
            end
        elseif voltage <= warningPackVoltage + 0.000001 then
            widget.voltageCriticalPendingAt = nil
            if widget.voltageWarningPendingAt == nil then
                widget.voltageWarningPendingAt = now
            elseif now - widget.voltageWarningPendingAt >= VOLTAGE_WARNING_CONFIRM_TIME then
                nextState = VOLTAGE_WARNING
                widget.voltageWarningPendingAt = nil
            end
        else
            widget.voltageWarningPendingAt = nil
            widget.voltageCriticalPendingAt = nil
        end
    end
    if nextState ~= previous then widget.dirty = true end
    widget.voltageState = nextState
    -- Initial acquisition and recovery transitions are deliberately silent.
    if previous == VOLTAGE_NORMAL and nextState == VOLTAGE_WARNING then
        signalVoltageAlarm(widget.config.voltageWarningFile, 300)
        widget.voltageAlarmRepeatAt = now and (now + VOLTAGE_ALARM_REPEAT_SECONDS) or nil
    elseif previous ~= nil and nextState == VOLTAGE_CRITICAL
        and previous ~= VOLTAGE_CRITICAL then
        signalVoltageAlarm(widget.config.voltageCriticalFile, 500)
        widget.voltageAlarmRepeatAt = now and (now + VOLTAGE_ALARM_REPEAT_SECONDS) or nil
    elseif nextState == VOLTAGE_NORMAL or nextState ~= previous then
        widget.voltageAlarmRepeatAt = nil
    elseif now and widget.voltageAlarmRepeatAt and now >= widget.voltageAlarmRepeatAt then
        if nextState == VOLTAGE_WARNING then
            playConfiguredAudio(widget.config.voltageWarningFile)
        elseif nextState == VOLTAGE_CRITICAL then
            playConfiguredAudio(widget.config.voltageCriticalFile)
        end
        widget.voltageAlarmRepeatAt = widget.voltageAlarmRepeatAt + VOLTAGE_ALARM_REPEAT_SECONDS
    end
end

local function rearmVoltageAlarm(widget)
    widget.voltageState = VOLTAGE_NORMAL
    widget.voltageWarningPendingAt = nil
    widget.voltageCriticalPendingAt = nil
    widget.voltageAlarmRepeatAt = nil
end

local function updateHighAlarms(widget)
    local temp, tempThreshold = widget.values.temp, widget.config.tempAlarmThreshold
    if tempThreshold <= 0 then
        widget.tempAlarmActive = false
    elseif finite(temp) then
        if not widget.tempAlarmActive and temp >= tempThreshold then
            widget.tempAlarmActive = true
            signalAlarm(widget.config.tempAlarmFile, 500)
        elseif widget.tempAlarmActive and temp <= tempThreshold - TEMP_ALARM_HYSTERESIS then
            widget.tempAlarmActive = false
        end
    end

    local rpm, rpmThreshold = widget.values.rpm, widget.config.rpmAlarmThreshold
    if rpmThreshold <= 0 then
        widget.rpmAlarmActive = false
    elseif finite(rpm) then
        local hysteresis = math.max(RPM_ALARM_MIN_HYSTERESIS, rpmThreshold * 0.02)
        if not widget.rpmAlarmActive and rpm >= rpmThreshold then
            widget.rpmAlarmActive = true
            signalAlarm(widget.config.rpmAlarmFile, 500)
        elseif widget.rpmAlarmActive and rpm <= rpmThreshold - hysteresis then
            widget.rpmAlarmActive = false
        end
    end
end

-- Chrono Source formatting, aligned with GIB2A TURBINE.
local function updateChrono(widget)
    local value = widget.values.chrono
    local text = "--"
    if finite(value) then
        local total = math.floor(math.abs(value))
        text = string.format("%d:%02d", math.floor(total / 60), total % 60)
        if value < 0 then text = "-" .. text end
    end
    if widget.chrono ~= text then widget.dirty = true end
    widget.chrono = text
end

local function flightMaximum(current, value)
    if not finite(value) then return current end
    if current == nil or value > current then return value end
    return current
end

local function flightMinimum(current, value)
    if not finite(value) then return current end
    if current == nil or value < current then return value end
    return current
end

local function updateFlightDuration(summary, chrono, now)
    if finite(summary.startChrono) and finite(chrono) then
        summary.duration = math.abs(chrono - summary.startChrono)
    elseif finite(summary.startedAt) and finite(now) then
        summary.duration = math.max(0, now - summary.startedAt)
    end
end

local function updateFlightSummary(widget)
    local now = sourceEngineNow()
    if now == nil then return end
    local summary = widget.flightSummary
    local voltage, rpm = widget.values.voltage, widget.values.rpm
    local engineActive = finite(voltage) and voltage > 0
        and finite(rpm) and rpm >= FLIGHT_RPM_ACTIVE_MINIMUM

    if not summary.active and engineActive then
        resetFlightSummary(widget)
        summary = widget.flightSummary
        summary.active = true
        summary.startedAt = now
        summary.startChrono = finite(widget.values.chrono) and widget.values.chrono or nil
    end

    if not summary.active then return end

    local current = widget.values.escCurrent
    local rf1, rf2 = widget.values.rssi1, widget.values.rssi2
    summary.maxRpm = flightMaximum(summary.maxRpm, rpm)
    summary.maxCurrent = flightMaximum(summary.maxCurrent,
        finite(current) and current >= 0 and current or nil)
    summary.minVoltage = flightMinimum(summary.minVoltage, voltage)
    summary.minRf1 = flightMinimum(summary.minRf1, rf1)
    summary.minRf2 = flightMinimum(summary.minRf2, rf2)
    if finite(voltage) and finite(current) and current >= 0 then
        summary.maxPower = flightMaximum(summary.maxPower, voltage * current)
    end
    updateFlightDuration(summary, widget.values.chrono, now)

    if finite(rpm) and rpm < FLIGHT_RPM_ACTIVE_MINIMUM then
        summary.inactiveSince = summary.inactiveSince or now
    elseif finite(rpm) and rpm >= FLIGHT_RPM_ACTIVE_MINIMUM then
        summary.inactiveSince = nil
    end
    if not finite(voltage) or voltage <= 0 then
        summary.voltageLostSince = summary.voltageLostSince or now
    else
        summary.voltageLostSince = nil
    end

    local inactiveConfirmed = summary.inactiveSince
        and now - summary.inactiveSince >= FLIGHT_END_CONFIRM_SECONDS
    local voltageLossConfirmed = summary.voltageLostSince
        and now - summary.voltageLostSince >= FLIGHT_END_CONFIRM_SECONDS
    if inactiveConfirmed or voltageLossConfirmed then
        updateFlightDuration(summary, widget.values.chrono, now)
        summary.active = false
        summary.completed = true
        summary.inactiveSince = nil
        summary.voltageLostSince = nil
        widget.dirty = true
    end
end

-- Responsive geometry, based on available window, never radio model.
local function getLayout(widget, width, height)
    local cached = widget.layout
    if cached and cached.width == width and cached.height == height then return cached end
    if width >= 700 and height >= 430 then
        -- X20 reference canvas. One scale preserves circles and visual hierarchy.
        local scale = math.min(width / 800, height / 480)
        local offsetX = (width - 800 * scale) / 2
        local function rect(x, y, w, h)
            return { x = offsetX + x * scale, y = y * scale,
                w = w * scale, h = h * scale }
        end
        local function gauge(cx, cy, radius, titleY)
            return { x = offsetX + cx * scale, y = cy * scale,
                radius = radius * scale, titleY = titleY * scale,
                width = (radius * 2 + 12) * scale, segmented = true }
        end
        local panelMargin = math.max(5, math.floor(width * 0.012))
        local panelWidth = math.floor(width * 0.255)
        local panelHeight = math.max(1, 314 * scale - 128 * scale - panelMargin - 2)
        local layout = { width = width, height = height, profile = "FULL",
            chrono = rect(258, 18, 284, 64),
            logo = rect(328, 94, 144, 63.2),
            consumed = rect(280, 338, 240, 76),
            consumedTitle = rect(280, 338, 240, 22),
            consumedValue = rect(280, 370, 240, 38),
            leftColumn = { x = panelMargin, y = panelMargin,
                w = panelWidth, h = panelHeight },
            rightColumn = { x = width - panelMargin - panelWidth, y = panelMargin,
                w = panelWidth, h = panelHeight },
            voltageGauge = gauge(140, 314, 128, 156),
            batteryGauge = gauge(660, 314, 128, 156),
            rpmGauge = gauge(332, 248, 60.5, 160),
            tempGauge = gauge(468, 248, 60.5, 160) }
        layout.gauges = { layout.voltageGauge, layout.batteryGauge,
            layout.rpmGauge, layout.tempGauge }
        widget.layout = layout
        return layout
    end
    local small = height < 300
    local mediumNarrow = not small and width >= 460 and width < 600
    local profile = small and "SMALL" or (mediumNarrow and "MEDIUM-NARROW" or "MEDIUM LARGE")
    local margin = math.max(6, math.floor(width * 0.018))
    local bigR, gaugeY, smallY, titleY
    if small then
        bigR = math.floor(math.min(width * 0.12, height * 0.205))
        gaugeY, smallY, titleY = math.floor(height * 0.71), math.floor(height * 0.60), math.floor(height * 0.34)
    elseif mediumNarrow then
        bigR = math.floor(math.min(width * 0.1292, height * 0.194))
        gaugeY, smallY, titleY = math.floor(height * 0.70), math.floor(height * 0.54), math.floor(height * 0.29)
    else
        bigR = math.floor(math.min(width * 0.15, height * 0.26))
        gaugeY, smallY, titleY = math.floor(height * 0.68), math.floor(height * 0.53), math.floor(height * 0.29)
    end
    bigR = math.max(24, bigR)
    local smallR = math.max(14, math.floor(bigR * 0.46))
    local center = width / 2
    local smallOffset = smallR + math.max(7, math.floor(width * 0.012))
    local panelMargin = math.max(5, math.floor(width * 0.012))
    local panelAvailableHeight = math.max(1, gaugeY - bigR - panelMargin - 2)
    local narrowPanelsFit = mediumNarrow and panelAvailableHeight >= 121
    local widePanels = (not small) and width >= 600 and height >= 320
    local showSecondary = widePanels or narrowPanelsFit
    local function compactGauge(x, y, radius, segmented, primary)
        return { x = x, y = y, radius = radius, titleY = titleY,
            width = radius * 2 + (segmented and 14 or 8),
            segmented = segmented, compact = segmented == true,
            compactPrimary = primary == true }
    end
    local consumedW = math.min(150, math.floor(width * 0.28))
    local consumedH = small and math.min(56, height - (gaugeY + 4)) or math.min(76, height - (gaugeY - 4))
    local consumedY = small and (height - consumedH - 10) or math.floor(height * 0.68)
    local chronoW = mediumNarrow and showSecondary
        and math.floor(width * 0.38) or math.min(240, width - 24)
    local chronoH = small and 44 or 48
    local chronoX = center - chronoW / 2
    local layout = { width = width, height = height, profile = profile,
        chrono = { x = chronoX, y = 4, w = chronoW, h = chronoH },
        consumed = { x = center - consumedW / 2, y = consumedY, w = consumedW, h = consumedH },
        consumedTitle = { x = center - consumedW / 2, y = consumedY, w = consumedW, h = 18 },
        consumedValue = { x = center - consumedW / 2, y = consumedY + 22, w = consumedW, h = 24 },
        showSecondary = showSecondary, gauges = {} }
    if layout.showSecondary then
        local columnY = panelMargin
        local columnW = math.max(1, math.floor(width * 0.255))
        layout.leftColumn = { x = panelMargin, y = columnY,
            w = columnW, h = panelAvailableHeight }
        layout.rightColumn = { x = width - panelMargin - columnW, y = columnY,
            w = columnW, h = panelAvailableHeight }
    end
    layout.voltageGauge = compactGauge(margin + bigR, gaugeY, bigR, true, true)
    layout.batteryGauge = compactGauge(width - margin - bigR, gaugeY, bigR, true, true)
    layout.rpmGauge = compactGauge(center - smallOffset, smallY, smallR, true)
    layout.tempGauge = compactGauge(center + smallOffset, smallY, smallR, true)
    layout.gauges = { layout.voltageGauge, layout.batteryGauge, layout.rpmGauge, layout.tempGauge }
    widget.layout = layout
    return layout
end

local ANNULUS_SEGMENT_COUNT = 24
local ANNULUS_START_ANGLE = 210
local ANNULUS_SWEEP_ANGLE = 300
local ANNULUS_FILL_RATIO = 0.84
local ANNULUS_THICKNESS_RATIO = 0.15
local ANNULUS_PIXEL_TUNING_ENABLED = true
local FONTS = { FONT_XXL, FONT_XL, FONT_L, FONT_M, FONT_S, FONT_XS, FONT_XXS }

local function fittedText(x, y, text, width, height, color, centerVertically)
    lcd.color(color)
    for _, font in ipairs(FONTS) do
        lcd.font(font)
        local tw, th = lcd.getTextSize(text)
        if tw <= width and th <= height then
            local drawY = centerVertically and (y + (height - th) / 2) or y
            lcd.drawText(math.floor(x - tw / 2), math.floor(drawY), text)
            return
        end
    end
    -- Long values/units cannot spill into the adjacent instrument.
    lcd.font(FONT_XS)
    local tw, th = lcd.getTextSize("---")
    if tw <= width and th <= height then lcd.drawText(math.floor(x - tw / 2), math.floor(y), "---") end
end

local function fittedCircleText(x, centerY, text, innerRadius,
        anchorY, anchorBottom, maxHeight, color, smallestOnly)
    lcd.color(color)
    for _, candidate in ipairs(FONTS) do
        lcd.font(candidate)
        local tw, th = lcd.getTextSize(text)
        if (not smallestOnly or candidate == FONT_XXS) and th <= maxHeight then
            local drawY = anchorBottom and (anchorY - th) or anchorY
            local verticalExtent = math.max(math.abs(drawY - centerY),
                math.abs(drawY + th - centerY))
            local chord = 2 * math.sqrt(math.max(0,
                innerRadius * innerRadius - verticalExtent * verticalExtent))
            if tw <= chord then
                lcd.drawText(math.floor(x - tw / 2), math.floor(drawY), text)
                return true
            end
        end
    end
    return false
end

local function drawCompactTempLabel(x, y, color)
    lcd.color(color)
    lcd.font(FONT_XXS)
    local label, unit = "TEMP", "°C"
    local labelWidth = lcd.getTextSize(label)
    local unitWidth = lcd.getTextSize(unit)
    local gap = 0
    local drawX = math.floor(x - (labelWidth + gap + unitWidth) / 2)
    lcd.drawText(drawX, math.floor(y), label)
    lcd.drawText(drawX + labelWidth + gap, math.floor(y), unit)
end

local function fittedValueUnit(x, y, valueText, unitText, width, height, valueColor, unitColor)
    local gap = unitText ~= "" and 5 or 0
    for _, font in ipairs(FONTS) do
        lcd.font(font)
        local valueW, valueH = lcd.getTextSize(valueText)
        local unitW, unitH = 0, 0
        if unitText ~= "" then unitW, unitH = lcd.getTextSize(unitText) end
        local totalW, totalH = valueW + gap + unitW, math.max(valueH, unitH)
        if totalW <= width and totalH <= height then
            local drawX = math.floor(x - totalW / 2)
            local drawY = math.floor(y + (height - totalH) / 2)
            lcd.color(valueColor)
            lcd.drawText(drawX, drawY, valueText)
            if unitText ~= "" then
                lcd.color(unitColor)
                lcd.drawText(drawX + valueW + gap, drawY, unitText)
            end
            return
        end
    end
    fittedText(x, y, "---", width, height, valueColor, true)
end

local function numberText(value, decimals)
    if not finite(value) then return "---" end
    if math.abs(value) >= 10000000 then return string.format("%.2g", value) end
    if decimals == 2 then return string.format("%.2f", value) end
    return string.format(decimals == 1 and "%.1f" or "%.0f", value)
end

local function drawGauge(x, y, radius, minValue, maxValue, value, unit,
        gaugeType, box, activeColor, palette)
    local fraction = value and clamp((value - minValue) / (maxValue - minValue), 0, 1) or 0
    activeColor = activeColor or palette.main
    local segmentedInner = radius - math.max(3, radius * ANNULUS_THICKNESS_RATIO)
    local contentInner = radius - math.max(3, math.floor(radius * 0.13))
    if box.segmented then
        local inner = segmentedInner
        local stepAngle = ANNULUS_SWEEP_ANGLE / ANNULUS_SEGMENT_COUNT
        local visibleAngle = stepAngle * ANNULUS_FILL_RATIO
        local gapAngle = stepAngle - visibleAngle
        local turbineStyle = (gaugeType == "RPM" or gaugeType == "TEMP")
            and finite(value) and finite(maxValue) and maxValue > 0
        local gaugePercent = turbineStyle and value * 100 / maxValue or nil
        local activePercent = turbineStyle and clamp(gaugePercent, 0, 110) or nil
        local yellow = lcd.RGB(255, 210, 0)
        local orange = lcd.RGB(255, 110, 0)
        local function segmentColor(i)
            local color = palette.inactive
            if turbineStyle then
                local fromPercent = 110 * i / ANNULUS_SEGMENT_COUNT
                local midPercent = 110 * (i + 0.5) / ANNULUS_SEGMENT_COUNT
                if activePercent > fromPercent then
                    if midPercent < 110 * 0.62 then color = palette.main
                    elseif midPercent < 110 * 0.78 then color = yellow
                    elseif midPercent < 110 * 0.91 then color = orange
                    else color = palette.critical end
                end
            elseif value and fraction > i / ANNULUS_SEGMENT_COUNT then
                color = activeColor
            end
            return color
        end
        for i = 0, ANNULUS_SEGMENT_COUNT - 1 do
            local color = segmentColor(i)
            lcd.color(color)
            local slotStart = ANNULUS_START_ANGLE + i * stepAngle
            local segmentStart = slotStart
                + (ANNULUS_PIXEL_TUNING_ENABLED and gapAngle / 2 or 0)
            local segmentEnd = ANNULUS_PIXEL_TUNING_ENABLED
                and ANNULUS_START_ANGLE + (i + 1) * stepAngle - gapAngle / 2
                or segmentStart + visibleAngle
            lcd.drawAnnulusSector(x, y, inner, radius,
                segmentStart, segmentEnd)
        end
    end
    local valueWidth = box.compact and box.width
        or (radius >= 28 and radius * 1.55 or box.width)
    local valueHeight = math.max(16, math.min(52, radius * 0.62))
    local valueY = y - valueHeight / 2 - 5
    local labelWidth, labelY = valueWidth, y + valueHeight / 2 - 3
    local numericColor = (gaugeType == "RPM" or gaugeType == "TEMP")
        and palette.value or activeColor
    if box.compact then
        local primary = box.compactPrimary
        local valueBottom = y + contentInner * (primary and 0.18 or -0.08)
        local labelTop = y + contentInner * (primary and 0.25 or -0.04)
        fittedCircleText(x, y,
            numberText(value, gaugeType == "VOLTAGE" and 1 or 0),
            contentInner, valueBottom, true, primary and 36 or 16, numericColor)
        local labelDrawn = fittedCircleText(x, y, unit, contentInner,
            labelTop, false, primary and 20 or 16, palette.value, not primary)
        if not labelDrawn and not primary and gaugeType == "TEMP" then
            drawCompactTempLabel(x, labelTop, palette.value)
            labelDrawn = true
        end
        if not labelDrawn and not primary then
            labelDrawn = fittedCircleText(x, y, unit, contentInner,
                labelTop, false, 16, palette.value, true)
        end
        if not labelDrawn and not primary then
            lcd.color(palette.value)
            lcd.font(FONT_XXS)
            local tw = lcd.getTextSize(unit)
            lcd.drawText(math.floor(x - tw / 2), math.floor(labelTop), unit)
        end
        return
    end
    fittedText(x, valueY, numberText(value, gaugeType == "VOLTAGE" and 1 or 0),
        valueWidth, valueHeight, numericColor)
    fittedText(x, labelY, unit, labelWidth, 22, palette.value, true)
end

local function bindingSource(widget, id)
    local definition = SOURCE_BY_ID[id]
    return definition and widget[definition.field] or nil
end

local function sensorDecimals(unit, fallback)
    if unit == "mAh" or unit == "%" or unit == "rpm" or unit == "RPM" then return 0 end
    return fallback or 1
end

local function buildColumnEntries(widget)
    local left, right = {}, {}
    local function add(entries, id, label, decimals)
        if bindingSource(widget, id) == nil then return end
        local unit = widget.units[id] or ""
        local value = numberText(widget.values[id], sensorDecimals(unit, decimals))
        if value == "---" then value, unit = "--", "" end
        entries[#entries + 1] = { label, value, unit }
    end
    add(left, "becVoltage", "BEC V", 1)
    add(left, "becCurrent", "BEC A", 2)
    add(left, "escCurrent", "ESC A", 1)
    add(left, "diy1", "DIY 1", 1)
    add(right, "rssi1", "RSSI 2.4", 0)
    add(right, "rssi2", "RSSI 900", 0)
    add(right, "rx", "RX V", 1)
    add(right, "diy2", "DIY 2", 1)
    return left, right
end

local function getTelemetryPanelLayout(rowCount, availableHeight, compact)
    if rowCount <= 0 then
        return compact and FONT_XXS or FONT_XS, 1
    end

    local maxRowH = math.max(1, math.floor(availableHeight / rowCount))
    local font, preferredRowH
    if compact then
        if rowCount <= 3 and maxRowH >= 16 then
            font, preferredRowH = FONT_XS, 18
        else
            font, preferredRowH = FONT_XXS, rowCount <= 6 and 14 or 13
        end
    else
        if rowCount <= 4 and maxRowH >= 22 then
            font, preferredRowH = FONT_STD, 22
        elseif rowCount <= 6 and maxRowH >= 18 then
            font, preferredRowH = FONT_XS, 19
        else
            font, preferredRowH = FONT_XXS, rowCount <= 9 and 16 or 14
        end
    end

    return font, math.max(1, math.min(preferredRowH, maxRowH))
end

local function drawTelemetryPanel(x, y, width, rows, availableHeight, palette, compact)
    local font, rowH = getTelemetryPanelLayout(#rows, availableHeight, compact)
    lcd.font(font)
    for i, row in ipairs(rows) do
        local rowY = y + (i - 1) * rowH
        lcd.color(palette.text)
        lcd.drawText(x, rowY, row[1], 0)
        local value, unit = row[2] or "---", row[3] or ""
        local valueW, unitW = lcd.getTextSize(value), lcd.getTextSize(unit)
        local valueX = x + width - valueW - unitW - (unit ~= "" and 3 or 0)
        lcd.color(palette.text)
        lcd.drawText(valueX, rowY, value, 0)
        if unit ~= "" and value ~= "---" then
            lcd.color(palette.main)
            lcd.drawText(valueX + valueW + 3, rowY, unit, 0)
        end
        lcd.color(palette.inactive)
        lcd.drawLine(x, rowY + rowH - 2, x + width, rowY + rowH - 2)
    end
end

local function drawLargeHeader(widget, layout, palette)
    local chrono, image = layout.chrono, layout.logo
    fittedText(chrono.x + chrono.w / 2, chrono.y, widget.chrono,
        chrono.w, chrono.h, palette.text, true)
    if logo then
        lcd.drawBitmap(image.x, image.y, logo, image.w, image.h)
    else
        fittedText(image.x + image.w / 2, image.y, "GIB2A", image.w, image.h, palette.main)
    end
    local left, right = buildColumnEntries(widget)
    drawTelemetryPanel(layout.leftColumn.x, layout.leftColumn.y, layout.leftColumn.w,
        left, layout.leftColumn.h, palette, false)
    drawTelemetryPanel(layout.rightColumn.x, layout.rightColumn.y, layout.rightColumn.w,
        right, layout.rightColumn.h, palette, false)
end

local function drawCompactHeader(widget, layout, palette)
    local chrono = layout.chrono
    fittedText(chrono.x + chrono.w / 2, chrono.y, widget.chrono,
        chrono.w, chrono.h, palette.text, true)
    if layout.showSecondary then
        local left, right = buildColumnEntries(widget)
        drawTelemetryPanel(layout.leftColumn.x, layout.leftColumn.y, layout.leftColumn.w,
            left, layout.leftColumn.h, palette, true)
        drawTelemetryPanel(layout.rightColumn.x, layout.rightColumn.y, layout.rightColumn.w,
            right, layout.rightColumn.h, palette, true)
    end
end

local function durationText(seconds)
    if not finite(seconds) then return "--" end
    local total = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

local function summaryValue(value, decimals, unit)
    local text = numberText(value, decimals)
    if text == "---" then return "--" end
    return text .. (unit and unit ~= "" and " " .. unit or "")
end

local function drawMetricCard(x, y, width, height, label, value, palette)
    local inset = math.max(4, math.floor(width * 0.04))
    local labelHeight = 14
    lcd.color(palette.inactive)
    lcd.drawRectangle(math.floor(x), math.floor(y), math.floor(width), math.floor(height))
    fittedText(x + width / 2, y + 5, label,
        width - inset * 2, labelHeight, palette.text, true)
    fittedText(x + width / 2, y + labelHeight + 8, value,
        width - inset * 2, height - labelHeight - 14, palette.value, true)
end

local function drawFlightSummary(widget, width, height, palette)
    local summary = widget.flightSummary
    fittedText(width / 2, 4, "FLIGHT SUMMARY", width - 12, 28, palette.main, true)
    local status = summary.active and "ACTIVE" or (summary.completed and "COMPLETE" or "NO FLIGHT")
    fittedText(width / 2, 30, status, width - 12, 18,
        summary.active and palette.warning or palette.text, true)
    local margin = math.max(8, math.floor(width * 0.025))
    local gap = math.max(5, math.floor(width * 0.012))
    local rowGap = math.max(8, math.floor(height * 0.025))
    local metricsTop = 64
    local cardHeight = math.floor((height - metricsTop - margin - rowGap) * 0.38)
    local rowOneWidth = (width - margin * 2 - gap * 3) / 4
    local rowTwoWidth = (width - margin * 2 - gap * 2) / 3
    local rowTwoY = metricsTop + cardHeight + rowGap

    drawMetricCard(margin, metricsTop, rowOneWidth, cardHeight,
        "MAX RPM", summaryValue(summary.maxRpm, 0, "RPM"), palette)
    drawMetricCard(margin + rowOneWidth + gap, metricsTop, rowOneWidth, cardHeight,
        "MAX CURRENT", summaryValue(summary.maxCurrent, 1, "A"), palette)
    drawMetricCard(margin + (rowOneWidth + gap) * 2, metricsTop, rowOneWidth, cardHeight,
        "MAX POWER", summaryValue(summary.maxPower, 0, "W"), palette)
    drawMetricCard(margin + (rowOneWidth + gap) * 3, metricsTop, rowOneWidth, cardHeight,
        "MIN PACK", summaryValue(summary.minVoltage, 1, "V"), palette)

    drawMetricCard(margin, rowTwoY, rowTwoWidth, cardHeight,
        "DURATION", durationText(summary.duration), palette)
    drawMetricCard(margin + rowTwoWidth + gap, rowTwoY, rowTwoWidth, cardHeight,
        "RSSI 2.4 MIN", summaryValue(summary.minRf1, 0, widget.units.rssi1), palette)
    drawMetricCard(margin + (rowTwoWidth + gap) * 2, rowTwoY, rowTwoWidth, cardHeight,
        "RSSI 900 MIN", summaryValue(summary.minRf2, 0, widget.units.rssi2), palette)
end

-- Drawing: paint() consumes cached data only.
local function paint(widget)
    local width, height = lcd.getWindowSize()
    local palette = getPalette(widget.config.theme)
    lcd.color(palette.background)
    lcd.drawFilledRectangle(0, 0, width, height)
    if widget.view == "summary" then
        drawFlightSummary(widget, width, height, palette)
        return
    end
    if width < 240 or height < 240 or (width < 460 and height < 320) then
        fittedText(width / 2, math.max(0, height / 2 - 12), "Enlarge widget", width, 24, palette.text)
        return
    end
    local layout = getLayout(widget, width, height)
    if layout.logo then
        drawLargeHeader(widget, layout, palette)
    else
        drawCompactHeader(widget, layout, palette)
    end
    for i, gauge in ipairs(GAUGES) do
        local box = layout.gauges[i]
        local minValue = gauge.min
        local maxValue = gauge.max or (gauge.id == "temp"
            and widget.config.tempMax or widget.config.rpmMax)
        local activeColor = palette.main
        if gauge.id == "voltage" then
            minValue = widget.config.batteryCells * 3.0
            maxValue = widget.config.batteryCells * 4.3
            local warningPackVoltage, criticalPackVoltage = voltagePackThresholds(widget)
            local voltage = widget.values.voltage
            if finite(voltage)
                and voltage <= criticalPackVoltage + BATTERY_THRESHOLD_EPSILON then
                activeColor = palette.critical
            elseif finite(voltage)
                and voltage <= warningPackVoltage + BATTERY_THRESHOLD_EPSILON then
                activeColor = palette.warning
            end
        elseif gauge.id == "battery" and widget.values.battery ~= nil then
            if widget.config.batteryCriticalPercent > 0
                and widget.values.battery <= widget.config.batteryCriticalPercent then
                activeColor = palette.critical
            elseif widget.config.batteryWarningPercent > 0
                and widget.values.battery <= widget.config.batteryWarningPercent then
                activeColor = palette.warning
            end
        elseif gauge.id == "temp" and widget.config.tempAlarmThreshold > 0
            and widget.tempAlarmActive then
            activeColor = palette.critical
        elseif gauge.id == "rpm" and widget.config.rpmAlarmThreshold > 0
            and widget.rpmAlarmActive then
            activeColor = palette.critical
        end
        drawGauge(box.x, box.y, box.radius, minValue, maxValue,
            widget.values[gauge.id], gauge.unit, gauge.type, box, activeColor, palette)
    end
    if layout.consumed then
        local title, value = layout.consumedTitle, layout.consumedValue
        local consumed = widget.values.consumption -- already normalized to mAh in wakeup()
        local valueText = finite(consumed) and numberText(consumed, 0) or "--------"
        local unitText = finite(consumed) and "mAh" or ""
        local topValueHeight = math.max(1, value.y - title.y - 2)
        fittedValueUnit(value.x + value.w / 2, title.y, valueText, unitText,
            value.w, topValueHeight, palette.value, palette.main)
        fittedText(title.x + title.w / 2, value.y, "CONSUMED",
            title.w, title.h, palette.text)
    end
end

-- Acquisition / processing on every ETHOS wakeup().
local function wakeup(widget)
    for _, definition in ipairs(SOURCES) do
        local id = definition.id
        local field = definition.field
        local source = widget[field]
        if source then
            local raw
            if id == "rssi1" or id == "rssi2" then
                raw = readRssiSourceValue(widget, field)
            elseif SYSTEM_SOURCE_FIELDS[field] then
                raw = readSystemSourceValue(widget, field)
            else
                raw = readSourceValue(widget, field)
            end
            local cachedUnit = widget._sourceUnits[id]
            if not cachedUnit or cachedUnit.source ~= source then
                local physical = sourcePhysicalUnit(source)
                cachedUnit = { source = source,
                    text = sourceUnit(source) or canonicalPhysicalUnit(physical) or "",
                    physical = physical }
                widget._sourceUnits[id] = cachedUnit
            end
            local unit, physical = cachedUnit.text, cachedUnit.physical
            local value, normalizedUnit = normalize(id, raw, unit, physical)
            if widget.values[id] ~= value or widget.units[id] ~= normalizedUnit then
                widget.dirty = true
            end
            widget.values[id], widget.units[id] = value, normalizedUnit
        elseif widget.values[id] ~= nil or (widget.units[id] or "") ~= "" then
            widget.values[id], widget.units[id] = nil, ""
            widget.dirty = true
        end
    end

    if widget.chronoSource or widget.chrono ~= "--" then updateChrono(widget) end
    if widget.voltageSource or widget.values.battery ~= nil
        or widget.batteryStabilizeNotBefore ~= nil
        or widget.batteryFilteredVoltage ~= nil
        or #widget.batteryVoltageSamples > 0 then
        updateBattery(widget)
    end
    if widget.voltageSource or widget.voltageState ~= nil
        or widget.voltageWarningPendingAt ~= nil
        or widget.voltageCriticalPendingAt ~= nil
        or widget.voltageAlarmRepeatAt ~= nil then
        updateVoltageState(widget)
    end
    if widget.tempSource or widget.rpmSource then updateHighAlarms(widget) end
    if widget.voltageSource or widget.rpmSource or widget.flightSummary.active then
        updateFlightSummary(widget)
    end

    if widget.dirty and lcd.isVisible() then
        local now = sourceEngineNow()
        if now == nil or widget._nextDisplayRefreshAt == nil
            or now >= widget._nextDisplayRefreshAt then
            lcd.invalidate()
            widget.dirty = false
            widget._nextDisplayRefreshAt = now and (now + DISPLAY_REFRESH_SECONDS) or nil
        end
    end
end

-- Configuration UI. Manual selection and Auto Bind write the same Source field.
local function buildConfig(widget)
    local function addSource(id, label)
        local definition = SOURCE_BY_ID[id]
        form.addSourceField(form.addLine(label or definition.label), nil,
            function() return widget[definition.field] end,
            function(source)
                setWidgetSource(widget, definition, source, false)
                widget.dirty = true
            end)
    end
    local function addNumber(label, key, lo, hi, scale, suffix, step)
        scale = scale or 1
        local field = form.addNumberField(form.addLine(label), nil, lo, hi,
            function() return math.floor(widget.config[key] * scale + 0.5) end,
            function(value)
                local newValue = value / scale
                if widget.config[key] == newValue then return end
                widget.config[key] = newValue
                if key == "voltageWarningPerCell" or key == "voltageCriticalPerCell"
                    or key == "batteryCells" then
                    validateVoltageAlarmThresholds(widget.config)
                    rearmVoltageAlarm(widget)
                end
                if key == "batteryCells" then
                    resetSmartBattery(widget)
                end
                widget.dirty = true
            end)
        if field and field.step then field:step(step or 1) end
        if field and scale > 1 and field.decimals then field:decimals(1) end
        if field and suffix and field.suffix then field:suffix(suffix) end
    end
    local function addFile(label, key)
        if not form.addFileField then return end
        form.addFileField(form.addLine(label), nil, audioPath, "audio +ext",
            function() return widget.config[key] end,
            function(value) widget.config[key] = value end)
    end
    local function addSection(label)
        form.addStaticText(form.addLine(label), nil, "")
    end

    addSection("SENSORS")
    local autoLine = form.addLine("Auto Bind")
    local function pressAutoBind()
        autoBindNeuron(widget)
        if form.clear then
            form.clear()
            buildConfig(widget)
        end
    end
    local buttonAdded = false
    if form.addButton then
        local ok, button = pcall(form.addButton, autoLine, nil,
            { text = "Auto Bind", icon = "", press = pressAutoBind })
        buttonAdded = ok and button ~= nil
    end
    if not buttonAdded and form.addTextButton then
        local ok, button = pcall(form.addTextButton, autoLine, nil, "Auto Bind", pressAutoBind)
        buttonAdded = ok and button ~= nil
    end
    if not buttonAdded then
        form.addStaticText(autoLine, nil, "Auto Bind unavailable")
    end
    form.addStaticText(form.addLine("Auto-bind status"), nil, widget._autoBindStatus)

    addSource("rpm", "RPM Source")
    addSource("temp", "TEMP Source")
    addSource("voltage", "Voltage Source")
    addSource("escCurrent", "Current Source")
    addSource("consumption", "Consumption Source")
    addSource("becVoltage", "BEC Voltage Source")
    addSource("becCurrent", "BEC Current Source")
    addSource("rx", "RX Battery Source")
    addSource("rssi1", "RSSI 2.4 Source")
    addSource("rssi2", "RSSI 900 Source")
    addSource("diy1", "DIY 1 Source")
    addSource("diy2", "DIY 2 Source")

    addSection("MAIN GAUGES")
    addNumber("RPM Max", "rpmMax", 1, 500000, 1, nil, 100)
    addNumber("TEMP Max", "tempMax", 1, 500, 1, "°C")

    addSection("BATTERY")
    addNumber("Battery Cell Count", "batteryCells", 2, 12)

    addSection("ALARMS")
    addNumber("RPM Alarm", "rpmAlarmThreshold", 0, 500000)
    addFile("RPM Alarm Sound", "rpmAlarmFile")
    addNumber("TEMP Alarm", "tempAlarmThreshold", 0, 200, 1, "°C")
    addFile("TEMP Alarm Sound", "tempAlarmFile")
    addNumber("Voltage Warning / Cell", "voltageWarningPerCell", 30, 45, 10, "V")
    addNumber("Voltage Critical / Cell", "voltageCriticalPerCell", 30, 45, 10, "V")
    addFile("Voltage Warning Sound", "voltageWarningFile")
    addFile("Voltage Critical Sound", "voltageCriticalFile")
    local warningField = form.addNumberField(form.addLine("Battery Warning %"), nil, 0, 100,
        function() return widget.config.batteryWarningPercent end,
        function(value)
            widget.config.batteryWarningPercent = value
            if value <= 0 then widget.config.batteryCriticalPercent = 0
            elseif widget.config.batteryCriticalPercent >= value then
                widget.config.batteryCriticalPercent = value - 1
            end
            widget.dirty = true
    end)
    if warningField and warningField.suffix then warningField:suffix("%") end
    local criticalField = form.addNumberField(form.addLine("Battery Critical %"), nil, 0, 100,
        function() return widget.config.batteryCriticalPercent end,
        function(value)
            widget.config.batteryCriticalPercent = math.min(value,
                math.max(0, widget.config.batteryWarningPercent - 1))
            widget.dirty = true
    end)
    if criticalField and criticalField.suffix then criticalField:suffix("%") end
    form.addChoiceField(form.addLine("Battery Callouts"), nil,
        { { "OFF", 0 }, { "ON", 1 } },
        function() return widget.config.batteryCalloutsEnabled end,
        function(value) widget.config.batteryCalloutsEnabled = value; widget.dirty = true end)
    addFile("Battery 50% Sound", "batteryCallout50File")
    addFile("Battery 35% Sound", "batteryCallout35File")
    addFile("Battery Warning Sound", "batteryWarningFile")
    addFile("Battery Critical Sound", "batteryCriticalFile")

    addSection("CHRONO")
    addSource("chrono")

    addSection("DISPLAY")
    local choices = { { "Standard", 1 }, { "High contrast", 2 }, { "Amber", 3 } }
    if form.addChoiceField then
        form.addChoiceField(form.addLine("Theme"), nil, choices,
            function() return widget.config.theme + 1 end,
            function(value)
                widget.config.theme = clamp((value or 1) - 1, 0, 2)
                widget.dirty = true
                if lcd.isVisible() then lcd.invalidate() end
            end)
    else
        addNumber("Theme (0=Std 1=High 2=Amber)", "theme", 0, 2)
    end
end

local function configure(widget)
    buildConfig(widget)
end

local function menu(widget)
    local function invalidateMenuAction()
        if lcd.isVisible() then
            lcd.invalidate()
            widget.dirty = false
        else
            widget.dirty = true
        end
    end
    local function selectView(view)
        widget.view = view
        invalidateMenuAction()
    end
    return {
        { "Dashboard", function() selectView("dashboard") end },
        { "Flight Summary", function() selectView("summary") end },
        { "Reset Flight Summary", function()
            resetFlightSummary(widget)
            invalidateMenuAction()
        end },
    }
end

-- Persistence: identical pwr_ key sequence in read and write.
-- Manual and Auto Bind selections persist through the same Source fields.
local function read(widget)
    for _, setting in ipairs(SETTINGS) do
        local value = storage.read("pwr_" .. setting.key)
        if not finite(value) or value < setting.min or value > setting.max
            or (not setting.decimals and value % 1 ~= 0) then
            value = setting.default
        end
        widget.config[setting.key] = value
    end
    if widget.config.voltageWarningPerCell == 3.5
        and widget.config.voltageCriticalPerCell == 3.3 then
        widget.config.voltageWarningPerCell = 3.8
        widget.config.voltageCriticalPerCell = 3.7
    elseif widget.config.voltageWarningPerCell == 3.8
        and (widget.config.voltageCriticalPerCell == 3.3
            or widget.config.voltageCriticalPerCell == 3.5) then
        widget.config.voltageCriticalPerCell = 3.7
    end
    validateBatteryAlarmThresholds(widget.config)
    validateVoltageAlarmThresholds(widget.config)
    for _, key in ipairs(FILE_SETTINGS) do
        local value = storage.read("pwr_" .. key)
        widget.config[key] = type(value) == "string" and value or nil
    end
    for _, definition in ipairs(SOURCES) do
        local source = storage.read("pwr_" .. (definition.storageKey or definition.id))
        if definition.id == "rssi1" and source == nil then source = storage.read("pwr_rssi") end
        setWidgetSource(widget, definition, source, false)
    end
    widget.values, widget.units, widget.chrono = {}, {}, "--"
    widget.voltageState = nil
    widget.voltageWarningPendingAt, widget.voltageCriticalPendingAt = nil, nil
    widget.voltageAlarmRepeatAt = nil
    widget.tempAlarmActive, widget.rpmAlarmActive = false, false
    widget.batteryCallout50Armed, widget.batteryCallout35Armed = true, true
    resetSmartBattery(widget)
    widget.dirty = true
    widget._autoBindStatus = string.format("Auto-bind NEURON: 0/%d sensors", AUTO_BIND_TOTAL)
end

local function write(widget)
    for _, setting in ipairs(SETTINGS) do
        storage.write("pwr_" .. setting.key, widget.config[setting.key])
    end
    for _, key in ipairs(FILE_SETTINGS) do
        storage.write("pwr_" .. key, widget.config[key])
    end
    for _, definition in ipairs(SOURCES) do
        storage.write("pwr_" .. (definition.storageKey or definition.id), widget[definition.field])
    end
end

-- Registration: independent widget, no turbine dependencies.
local function init()
    local ok, bitmap = pcall(lcd.loadBitmap, LOGO_PATH)
    if ok then logo = bitmap end
    system.registerWidget({ key = "GIB2APW", name = "GIB2A POWER " .. WIDGET_VERSION,
        create = create, wakeup = wakeup, paint = paint, configure = configure, menu = menu,
        read = read, write = write })
end

return { init = init }
