-- https://stackoverflow.com/a/1283608/483349
local function tableMerge(t1, t2)
    for k,v in pairs(t2) do
        if type(v) == "table" then
            if type(t1[k] or false) == "table" then
                tableMerge(t1[k] or {}, t2[k] or {})
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
    return t1
end

-- https://stackoverflow.com/a/7615129/483349
local function splitString(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local FloodWeatherSync = {
    _state = {
        tickCounter = 0,
        previousClockTime = nil,
        init = false,
        timeOfDay = nil,
        currentPreset = nil,
        manualOverride = false -- Track if weather was manually set
    },
    _defaultOptions = {
        timeOfDay = {
            dayLengthRealTimeSeconds = 1800,
            serverWorldStartTime = "15:00",
            daytimeScale = 1,
            nighttimeScale = 2,
            azimuth = 0,
            fixed = false
        },
        syncRate = 2,
        debug = false
    },
    options = {},
    weatherPresets = {},
    weatherSettings = {},
    MINUTES_PER_DAY = 1440,
    MINUTES_PER_HOUR = 60,
    SECONDS_PER_MINUTE = 60,
    SECONDS_PER_HOUR = 3600,
    SECONDS_PER_DAY = 3600 * 24,
    GAME_NIGHTTIME_START_VALUE = 0.275, -- approx. 18:36
    GAME_DAYTIME_START_VALUE = 0.7425, -- approx. 05:23
    GAME_TIME_MAX_REF = 1.0,
    GAME_TIME_SCALE_MIN = 0.5,
    GAME_TIME_SCALE_MAX = 10,
    SYNC_RATE_MIN = 1,
    SYNC_RATE_MAX = 30,
}

    function FloodWeatherSync:init(mapConfig, postInit)
        if (self._state.init) then
            self:print("FloodWeatherSync already initialized")
            return
        end
        self:loadMapConfig(mapConfig)
        self._state.init = true
        
        -- Apply default preset if auto change is enabled
        if self.weatherSettings.autoChangeWeather then
            self:applyPreset(self.weatherSettings.defaultPreset)
        else
            self:recalcServerTimeOfDay()
            self:printDebug("Set initial time of day (" .. self._state.timeOfDay .. ")")
        end
        
        if postInit then postInit() end
    end

    function FloodWeatherSync:loadMapConfig(mapConfig)
        -- Load weather presets and settings from map.json
        self.weatherPresets = mapConfig.weatherPresets or {}
        self.weatherSettings = mapConfig.weatherSettings or {}
        
        -- Set default options
        tableMerge(self.options, self._defaultOptions)
        
        -- Apply default weather settings
        if not self.weatherSettings.defaultPreset then
            self.weatherSettings.defaultPreset = "clear"
        end
        if not self.weatherSettings.floodStartPreset then
            self.weatherSettings.floodStartPreset = "stormy" 
        end
        if not self.weatherSettings.floodEndPreset then
            self.weatherSettings.floodEndPreset = "clear"
        end
        if self.weatherSettings.autoChangeWeather == nil then
            self.weatherSettings.autoChangeWeather = true
        end
        
        -- Initialize with default preset if available
        local defaultPreset = self.weatherPresets[self.weatherSettings.defaultPreset]
        if defaultPreset then
            self._state.timeOfDay = self:convertClockTimeToGameTime(defaultPreset.timeOfDay) or 0.5
            self.options.timeOfDay.dayLengthRealTimeSeconds = defaultPreset.dayLengthRealTimeSeconds or self._defaultOptions.timeOfDay.dayLengthRealTimeSeconds
            self.options.timeOfDay.daytimeScale = defaultPreset.daytimeScale or self._defaultOptions.timeOfDay.daytimeScale
            self.options.timeOfDay.nighttimeScale = defaultPreset.nighttimeScale or self._defaultOptions.timeOfDay.nighttimeScale
            self.options.timeOfDay.azimuth = defaultPreset.azimuth or self._defaultOptions.timeOfDay.azimuth
            self.options.timeOfDay.fixed = defaultPreset.fixed or self._defaultOptions.timeOfDay.fixed
        else
            self._state.timeOfDay = self:convertClockTimeToGameTime(self._defaultOptions.timeOfDay.serverWorldStartTime) or 0.5
        end
        
        -- Normalize/sanitize options
        self.options.syncRate = math.min(self.SYNC_RATE_MAX, math.max(self.SYNC_RATE_MIN, self.options.syncRate or self._defaultOptions.syncRate))
        self.options.timeOfDay.daytimeScale = math.min(self.GAME_TIME_SCALE_MAX, math.max(self.GAME_TIME_SCALE_MIN, self.options.timeOfDay.daytimeScale))
        self.options.timeOfDay.nighttimeScale = math.min(self.GAME_TIME_SCALE_MAX, math.max(self.GAME_TIME_SCALE_MIN, self.options.timeOfDay.nighttimeScale))
        self.options.timeOfDay.dayLengthRealTimeSeconds = math.max(0, self.options.timeOfDay.dayLengthRealTimeSeconds)
        
        -- Other calculations
        self.options.timeOfDay.__dayLengthRealTimeSecondsPart = 1.0 / self.options.timeOfDay.dayLengthRealTimeSeconds
        self:updateDerivedOptions()
        
        self:printDebug("Loaded " .. self:countTable(self.weatherPresets) .. " weather presets")
    end
    
    function FloodWeatherSync:countTable(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end
    
    function FloodWeatherSync:applyPreset(presetName, isManual)
        local preset = self.weatherPresets[presetName]
        if not preset then
            self:print("Weather preset '" .. tostring(presetName) .. "' not found")
            return false
        end
        
        local timeValue = self:convertClockTimeToGameTime(preset.timeOfDay)
        if not timeValue then
            self:print("Invalid time format in preset '" .. presetName .. "': " .. tostring(preset.timeOfDay))
            return false
        end
        
        -- Update options with preset values
        self.options.timeOfDay.dayLengthRealTimeSeconds = preset.dayLengthRealTimeSeconds or self._defaultOptions.timeOfDay.dayLengthRealTimeSeconds
        self.options.timeOfDay.daytimeScale = preset.daytimeScale or self._defaultOptions.timeOfDay.daytimeScale
        self.options.timeOfDay.nighttimeScale = preset.nighttimeScale or self._defaultOptions.timeOfDay.nighttimeScale
        self.options.timeOfDay.azimuth = preset.azimuth or self._defaultOptions.timeOfDay.azimuth
        self.options.timeOfDay.fixed = preset.fixed ~= nil and preset.fixed or self._defaultOptions.timeOfDay.fixed
        
        -- Recalculate derived options
        self.options.timeOfDay.__dayLengthRealTimeSecondsPart = 1.0 / self.options.timeOfDay.dayLengthRealTimeSeconds
        self:updateDerivedOptions()
        
        -- Set time and sync
        self:setTimeOfDay(timeValue, self.options.timeOfDay.fixed)
        self._state.currentPreset = presetName
        
        -- Track if this was a manual change
        if isManual then
            self._state.manualOverride = true
            self:print("Applied weather preset manually: " .. preset.name .. " (" .. presetName .. ")")
        else
            self:print("Applied weather preset automatically: " .. preset.name .. " (" .. presetName .. ")")
        end
        
        return true
    end
    
    function FloodWeatherSync:getAvailablePresets()
        local presets = {}
        for name, preset in pairs(self.weatherPresets) do
            table.insert(presets, {name = name, displayName = preset.name})
        end
        return presets
    end
    
    function FloodWeatherSync:getCurrentPreset()
        return self._state.currentPreset
    end
    
    function FloodWeatherSync:clearManualOverride()
        self._state.manualOverride = false
        self:print("Manual weather override cleared")
    end
    
    function FloodWeatherSync:isManualOverride()
        return self._state.manualOverride
    end
    
    -- Event handlers for flood state changes
    function FloodWeatherSync:onFloodStart()
        -- Only auto-change weather if no manual override is active
        if self.weatherSettings.autoChangeWeather and self.weatherSettings.floodStartPreset and not self._state.manualOverride then
            self:applyPreset(self.weatherSettings.floodStartPreset, false)
        end
    end
    
    function FloodWeatherSync:onFloodEnd()
        -- Only auto-change weather if no manual override is active
        if self.weatherSettings.autoChangeWeather and self.weatherSettings.floodEndPreset and not self._state.manualOverride then
            self:applyPreset(self.weatherSettings.floodEndPreset, false)
        end
    end

    function FloodWeatherSync:updateDerivedOptions()
        if self.options.timeOfDay.fixed then
            self.options.timeOfDay.__play = 0
        else
            self.options.timeOfDay.__play = 1
        end
    end

    function FloodWeatherSync:recalcServerTimeOfDay()
        if not self._state.previousClockTime then
            self._state.previousClockTime = os.time()
            return
        end
        local elapsedSeconds = os.time() - self._state.previousClockTime
        self._state.previousClockTime = os.time()
        if self.options.timeOfDay.fixed then
            return
        end
        local newTimeOfDay = self._state.timeOfDay
        local inc = self.options.timeOfDay.__dayLengthRealTimeSecondsPart
        for i = 1, elapsedSeconds do
            local isNighttime = newTimeOfDay >= self.GAME_NIGHTTIME_START_VALUE and newTimeOfDay < self.GAME_DAYTIME_START_VALUE
            if isNighttime then
                newTimeOfDay = newTimeOfDay + (inc * self.options.timeOfDay.nighttimeScale)
            else
                newTimeOfDay = newTimeOfDay + (inc * self.options.timeOfDay.daytimeScale)
            end
            if newTimeOfDay >= 1 then newTimeOfDay = newTimeOfDay - 1 end
        end
        self._state.timeOfDay = newTimeOfDay
    end

    function FloodWeatherSync:setTimeOfDay(value, fixed)
        self.options.timeOfDay.fixed = fixed
        self:updateDerivedOptions()
        self._state.timeOfDay = value
        self._state.previousClockTime = os.time()
        self:syncTimeOfDay()
    end

    function FloodWeatherSync:convertClockTimeToGameTime(value)
        local h_s, m_s = string.match(value, "^(%d%d):(%d%d)$")
        if not h_s or not m_s then return nil end
        return self:convertSecondsToGameTime(((tonumber(h_s) * self.SECONDS_PER_HOUR) + (tonumber(m_s) * self.SECONDS_PER_MINUTE)) % self.SECONDS_PER_DAY)
    end

    function FloodWeatherSync:convertSecondsToGameTime(seconds)
        -- sanitize
        local s = math.min(self.SECONDS_PER_DAY, math.max(0, seconds or 0))
        -- need to convert range [0,86400) (12am-11:59pm) to [0,1) (12pm-11:59am)
        local a = s + (self.SECONDS_PER_DAY / 2)
        if a >= self.SECONDS_PER_DAY then
            a = a - self.SECONDS_PER_DAY
        end
        return a / self.SECONDS_PER_DAY
    end

    function FloodWeatherSync:syncTimeOfDay()
        local t = self._state.timeOfDay
        -- [1] = time
        -- [2] = dayLength
        -- [3] = dayScale
        -- [4] = nightScale
        -- [5] = play
        -- [6] = azimuthOverride
        local data = t .. "|" .. self.options.timeOfDay.dayLengthRealTimeSeconds .. "|" .. self.options.timeOfDay.daytimeScale .. "|" .. self.options.timeOfDay.nighttimeScale .. "|" .. self.options.timeOfDay.__play .. "|" .. self.options.timeOfDay.azimuth
        self:printDebug("Syncing time of day (" .. t .. ")")
        MP.TriggerClientEvent(-1, "BeamMPEnvSyncSetTimeOfDay", data)
    end

    function FloodWeatherSync:tick()
        local c = self._state.tickCounter
        if c > 60 / self.options.syncRate then
            c = 0
            self:recalcServerTimeOfDay()
            self:syncTimeOfDay()
        end
        c = c + 1
        self._state.tickCounter = c
    end

    function FloodWeatherSync:print(s)
        print(self:createPrintMessage(s))
    end

    function FloodWeatherSync:printDebug(s)
        if self.options.debug then
            self:print(s)
        end
    end

    function FloodWeatherSync:createPrintMessage(s)
        return "[WEATHER] " .. s
    end

-- Global instance for use by flood system
WeatherSync = FloodWeatherSync

return FloodWeatherSync