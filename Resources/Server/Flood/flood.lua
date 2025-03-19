require("multiplayer")
local C = require("libs/client")
local U = require("libs/utils")

-- Templates
local playerTemplate = {
    name = "", -- Player name
    vehicle = "",
    status = "", -- Whether player is spectating or in game. spectating|inGame
    dead = false, -- Player is dead
    respawnedCount = 0 -- Times the player has respawned
}

local vehicleTemplate = {
    positionRaw = "", -- Fetched from getPositionRaw
    config = "" -- JSON config
}

local M = {}

M.mapConfig = Util.JsonDecode(io.open("Resources/Server/Flood/config/map.json"):read("*all"))

M.options = {
    oceanLevel = M.mapConfig.floodOptions.oceanLevel,
    floodSpeed = M.mapConfig.floodOptions.floodSpeed,
    limit = 0.0,
    limitEnabled = false,
    enabled = false,
    decrease = false,
    resetAt = 0.0, -- Doesn't reset everything, just the ocean level. Will be used for automatic flooding
    rainAmount = 0.0,
    rainVolume = -1.0, -- -1.0 = automatic, 0.0 = off, 1.0 = max
    floodWithRain = true
}

M.isOceanValid = false
M.initialLevel = 0.0
M.commands = {}

M.countdown = {
    started = false,
    count = 5,
    currentCount = 0
}

M.state = {
    players = {},
    ET_FreezeVehicles = {
        tick = 0
    }
}

local invalidCount = 0

local function setWaterLevel(level)
    if not M.isOceanValid then
        print("setWaterLevel: ocean is nil")
        return
    end

    MP.TriggerClientEvent(-1, "E_SetWaterLevel", tostring(level))
end

local function beginFlood()
    M.options.enabled = true;
    M.countdown.currentCount = 0;

    MP.CreateEventTimer("ET_Update", 25)

    C.setVehicleFreeze(false)

    MP.hSendChatMessage(-1, "A flood has started!")
end

local function startCountdown()
    MP.CreateEventTimer("ET_FreezeVehicles", 200)
    
    MP.CreateEventTimer("ET_Countdown", 1000)
end

local function countdownComplete()
    MP.CancelEventTimer("ET_Countdown")
    M.countdown.started = false;

    beginFlood()
end

local function resetCountdown()
    MP.CancelEventTimer("ET_Countdown")
    M.options.enabled = false;
    M.countdown.currentCount = 0;
    M.countdown.started = false;
end

local function getPlayerState(pid)
    if M.state.players[pid] ~= nil then
        return M.state.players[pid]
    else
        return false
    end
end

local function updatePlayerStateVehicle(pid)
    local playerVehicles = MP.GetPlayerVehicles(pid);
    local playerState = getPlayerState(pid);

    if playerVehicles then
        playerState.vehicle.config = playerVehicles[0];
        playerState.vehicle.positionRaw = MP.GetPositionRaw(pid, 0)
    end
end

local function updatePlayersStatesVehicles()
    for pid, playerState in pairs(M.state.players) do
        updatePlayerStateVehicle(pid)
    end
end

local function createPlayerState(pid)
    local playerState = getPlayerState(pid)

    if not playerState then
        M.state.players[pid] = U.deepcopy(playerTemplate)
        M.state.players[pid].vehicle = U.deepcopy(vehicleTemplate)
        playerState = getPlayerState(pid);
    end
end

local function deletePlayerState(pid)
    M.state.players[pid] = nil;
end

local function updatePlayerState(pid)
    createPlayerState(pid)

    getPlayerState(pid).name = MP.GetPlayerName(pid);
    getPlayerState(pid).id = pid;

    updatePlayerStateVehicle(pid)
end

local function incrementPlayerRespawnedCount(pid)
    local playerState = getPlayerState(pid)
    playerState.respawnedCount = playerState.respawnedCount + 1
end

local function resetPlayersRespawnedCount()
    for pid, playerState in pairs(M.state.players) do
        playerState.respawnedCount = 0
    end
end

local function setPlayerDead(pid, dead)
    M.state.players[pid].dead = dead
end

local function resetVehiclesToStartPositions()
    local positions = {}
    local playerCount = 0
    for _ in pairs(M.state.players) do
        playerCount = playerCount + 1
    end
    
    for i = 1, math.min(playerCount, #M.mapConfig.startPositions) do
        table.insert(positions, i)
    end
    
    for pid, playerState in pairs(M.state.players) do
        if #positions > 0 then
            local randomIndex = math.random(1, #positions)
            local posIndex = positions[randomIndex]
            table.remove(positions, randomIndex)
            
            local startPos = M.mapConfig.startPositions[posIndex]
            if startPos then
                MP.TriggerClientEvent(pid, "E_ResetVehicleToPos", Util.JsonEncode(startPos))
            end
        end
    end
end

local function isFloodOrCountdownStarted()
    return M.options.enabled or M.countdown.started
end

local function ensureVehiclesAreAboveWaterLine()
    for pid, playerState in pairs(M.state.players) do
        if playerState.vehicle.positionRaw then
            if playerState.vehicle.positionRaw.pos[3] < M.options.oceanLevel + 3 and not playerState.dead then
                playerState.dead = true
                MP.GetPlayerVehicles(pid, 0)
                print("Player " .. pid .. " is dead")
            end
        end
    end
end

local function welcomePlayer(pid)
    MP.hSendChatMessage(pid, "Welcome to the flood! ^gSpawn a vehicle and start the flood!")
    MP.hSendChatMessage(pid, "Use ^b/flood_start^r to start the flood.")
    MP.hSendChatMessage(pid, "Use ^b/flood_stop^r to stop the flood.")
    MP.hSendChatMessage(pid, "Use ^b/flood_restart^r to restart the flood.")
    MP.hSendChatMessage(pid, "Use ^b/flood_reset^r to reset the flood.")
    MP.hSendChatMessage(pid, "Use ^b/flood_level^r to set the flood level.")
    MP.hSendChatMessage(pid, "Use ^b/flood_speed^r to set the flood speed.")
end

-- BeamMP events

function onPlayerJoin(pid)
    local success = MP.TriggerClientEvent(pid, "E_OnPlayerLoaded", "")
    if not success then
        print("Failed to send \"E_OnPlayerLoaded\" to " .. pid)
    end

    -- Sync rain & volume
    if M.options.rainAmount > 0.0 then
        MP.TriggerClientEvent(pid, "E_SetRainAmount", tostring(M.options.rainAmount))
    end

    if M.options.rainVolume == -1.0 or M.options.rainVolume > 0.0 then
        MP.TriggerClientEvent(pid, "E_SetRainVolume", tostring(M.options.rainVolume))
    end

    updatePlayerState(pid)

    welcomePlayer(pid)
end

function onPlayerDisconnect(pid)
    deletePlayerState(pid)

    return true
end

function onVehicleSpawn(pid, vid, data)
    return true
end

function onVehicleReset(pid, pName, data)
    return true
end

function onVehicleEdited(pid, pName, data)
    return true
end

function onVehicleDeleted(pid, pName)
    return true;
end

function onInit()
    MP.CancelEventTimer("ET_Update")

    for pid, player in pairs(MP.GetPlayers()) do
        onPlayerJoin(pid)
    end
end


function T_FreezeVehicles()
    M.state.ET_FreezeVehicles.tick = M.state.ET_FreezeVehicles.tick + 1;
    if M.state.ET_FreezeVehicles.tick > 1 then
        M.state.ET_FreezeVehicles.tick = 0;
        MP.CancelEventTimer("ET_FreezeVehicles")
        C.setVehicleFreeze(true)
        C.setVehicleRecoveryEnabled(false)
    end
end

function T_Countdown()
    if (M.countdown.currentCount <= M.countdown.count) then
        if M.countdown.currentCount == M.countdown.count then
            MP.hSendChatMessage(-1, "GO!")
            countdownComplete()
        else
            MP.hSendChatMessage(-1, M.countdown.count - M.countdown.currentCount .. "!")
            M.countdown.currentCount = M.countdown.currentCount + 1;
        end
    end
end

function T_Update()
    if not M.isOceanValid or not M.options.enabled then return end

    local level = M.options.oceanLevel
    local changeAmount = M.options.floodSpeed
    local limit = M.options.limit
    local limitEnabled = M.options.limitEnabled
    local decrease = M.options.decrease

    -- If we have rain, add the rain amount to the change amount. The flood speed will now act as a multiplier.
    if M.floodWithRain then
        local rainAmount = M.options.rainAmount
        if rainAmount > 0.0 then
            changeAmount = changeAmount + rainAmount * 0.0001
        end
    end

    -- Increase or decrease the level
    if decrease then
        level = level - changeAmount
    else
        level = level + changeAmount
    end

    -- Reset at (0 = disabled)
    if M.options.resetAt > 0.0 and level >= M.options.resetAt then
        level = M.initialLevel
    elseif M.options.resetAt < 0.0 and level <= M.options.resetAt then
        level = M.initialLevel
    end

    -- Limit the level
    if limitEnabled then
        if decrease then
            if level < limit then
                level = limit
            end
        else
            if level > limit then
                level = limit
            end
        end
    end
    
    M.options.oceanLevel = level
    setWaterLevel(level)

    updatePlayersStatesVehicles()
    ensureVehiclesAreAboveWaterLine()
end

function E_OnInitialize(pid, waterLevel)
    waterLevel = tonumber(waterLevel) or nil

    -- Make sure the level has an ocean, we use "invalidCount" to make sure it's not just 1 player that doesn't have an ocean
    if not waterLevel and invalidCount < 2 then
        print("E_OnInitialize: waterLevel for player " .. MP.GetPlayerName(pid) .. " is nil")
        invalidCount = invalidCount + 1
        return
    elseif not waterLevel and invalidCount >= 2 then
        print("This map doesn't have an ocean, disabling flood")
        M.isOceanValid = false
        return
    end

    M.isOceanValid = true
    if M.initialLevel == 0.0 then
        print("Setting initial water level to " .. waterLevel)
        M.initialLevel = waterLevel -- We sadly have to rely on the client 😅🔫
    end
end

M.commands["start"] = function(pid)
    if not M.isOceanValid then
        MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
        return
    end

    if isFloodOrCountdownStarted() then
        MP.hSendChatMessage(pid, "Flood has already started")
        return
    end
    
    if M.options.oceanLevel == 0.0 then
        M.options.oceanLevel = M.initialLevel
    end

    resetVehiclesToStartPositions()
    resetPlayersRespawnedCount()

    for pid, playerState in pairs(M.state.players) do
        setPlayerDead(pid, false)
    end

    startCountdown()
end

M.commands["stop"] = function(pid)
    if not isFloodOrCountdownStarted() then
        MP.hSendChatMessage(pid, "Flood is already stopped")
        return
    end

    MP.CancelEventTimer("ET_Update")
    resetPlayersRespawnedCount()
    resetCountdown();
    C.setVehicleRecoveryEnabled(true)
    MP.hSendChatMessage(-1, "The flood has stopped!")
end

M.commands["reset"] = function(pid)
    if not M.isOceanValid then
        MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
        return
    end

    MP.CancelEventTimer("ET_Update")
    M.options.enabled = false
    M.options.oceanLevel = M.initialLevel
    setWaterLevel(M.initialLevel)
end

M.commands["restart"] = function(pid)
    if not M.isOceanValid then
        MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
        return
    end

    MP.hSendChatMessage(-1, "Restarting flood!")

    MP.CancelEventTimer("ET_Update")
    M.options.enabled = false
    M.options.oceanLevel = M.initialLevel
    setWaterLevel(M.initialLevel)

    M.commands["start"](pid);
end

M.commands["resetVehicles"] = function(pid)
    C.resetVehicles()
end

M.commands["level"] = function(pid, level)
    level = tonumber(level) or nil
    if not level then
        MP.hSendChatMessage(pid, "Invalid level")
        return
    end

    if not M.isOceanValid then
        MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
        return
    end

    M.options.oceanLevel = level
    M.initialLevel = level
    setWaterLevel(level)
    MP.hSendChatMessage(pid, "Set water level to " .. level)
end

M.commands["speed"] = function(pid, speed)
    speed = tonumber(speed) or nil
    if not speed then
        MP.hSendChatMessage(pid, "Invalid speed")
        return
    end

    if speed < 0.0 then
        MP.hSendChatMessage(pid, "Speed can't be negative, setting to 0.0")
        speed = 0.0
    end

    -- Do I limit the max? Hmmm, not sure 🤔

    M.options.floodSpeed = speed
    MP.hSendChatMessage(pid, "Set flood speed to " .. speed)
end

M.commands["limit"] = function(pid, limit)
    limit = tonumber(limit) or nil
    if not limit then
        MP.hSendChatMessage(pid, "Invalid limit")
        return
    end

    M.options.limit = limit
    MP.hSendChatMessage(pid, "Set flood limit to " .. limit)
end

M.commands["limitEnabled"] = function(pid, enabled)
    if not enabled then
        MP.hSendChatMessage(pid, "Invalid value")
        return
    end

    if string.lower(enabled) == "true" or enabled == "1" then
        enabled = true
    elseif string.lower(enabled) == "false" or enabled == "0" then
        enabled = false
    else
        MP.hSendChatMessage(pid, "Please use true/false or 1/0")
        return
    end

    M.options.limitEnabled = enabled
    MP.hSendChatMessage(pid, tostring(enabled and "Enabled" or "Disabled") .. " flood limit")
end

M.commands["resetAt"] = function(pid, level)
    level = tonumber(level) or nil
    if not level then
        MP.hSendChatMessage(pid, "Invalid level")
        return
    end

    M.options.resetAt = level
    MP.hSendChatMessage(pid, "Set reset level to " .. level)
end

M.commands["rainAmount"] = function(pid, amount)
    amount = tonumber(amount) or nil
    if not amount then
        MP.hSendChatMessage(pid, "Invalid amount")
        return
    end

    M.options.rainAmount = amount
    MP.hSendChatMessage(pid, "Set rain amount to " .. amount)
    MP.TriggerClientEvent(-1, "E_SetRainAmount", tostring(amount))
    if M.options.rainVolume == -1 then -- Update the volume if it's set to auto
        MP.TriggerClientEvent(-1, "E_SetRainVolume", tostring(M.options.rainVolume))
    end
end

M.commands["rainVolume"] = function(pid, volume)
    volume = tonumber(volume) or nil
    if not volume then
        MP.hSendChatMessage(pid, "Invalid volume")
        return
    end

    M.options.rainVolume = volume
    MP.hSendChatMessage(pid, "Set rain volume to " .. volume)
    MP.TriggerClientEvent(-1, "E_SetRainVolume", tostring(volume))
end

M.commands["floodWithRain"] = function(pid, enabled)
    if not enabled then
        MP.hSendChatMessage(pid, "Invalid value")
        return
    end

    if string.lower(enabled) == "true" or enabled == "1" then
        enabled = true
    elseif string.lower(enabled) == "false" or enabled == "0" then
        enabled = false
    else
        MP.hSendChatMessage(pid, "Please use true/false or 1/0")
        return
    end

    M.options.floodWithRain = enabled
    MP.hSendChatMessage(pid, tostring(enabled and "Enabled" or "Disabled") .. " flooding with rain")
end

M.commands["decrease"] = function(pid, enabled)
    if not enabled then
        MP.hSendChatMessage(pid, "Invalid value")
        return
    end

    if string.lower(enabled) == "true" or enabled == "1" then
        enabled = true
    elseif string.lower(enabled) == "false" or enabled == "0" then
        enabled = false
    else
        MP.hSendChatMessage(pid, "Please use true/false or 1/0")
        return
    end

    if M.options.floodWithRain and M.options.rainAmount > 0.0 and enabled then
        MP.hSendChatMessage(pid, "What? You can't flood with rain and decrease at the same time!. Well, you can but I won't let you")
        return
    end

    M.options.decrease = enabled
    MP.hSendChatMessage(pid, "Set flood decrease to " .. tostring(enabled))
end

M.commands["printSettings"] = function(pid)
    for k, v in pairs(M.options) do
        MP.hSendChatMessage(pid, k .. ": " .. tostring(v))
    end
end

function E_RequestResetToRoad(pid, ...)
    if not isFloodOrCountdownStarted then
        return
    end

    if M.countdown.started then
        return
    end

    local playerState = getPlayerState(pid)
    local respawnedCount = playerState.respawnedCount


    if not M.options.enabled then
        return
    end

    if respawnedCount >= M.mapConfig.respawnLimit then
        MP.hSendChatMessage(pid, "Out of respawns")
        return
    end

    MP.TriggerClientEvent(pid, "E_ResetToRoad", Util.JsonEncode(M.mapConfig.destination.pos))
    
    MP.hSendChatMessage(pid, "Vehicle reset to road")

    incrementPlayerRespawnedCount(pid)
end

MP.RegisterEvent("ET_FreezeVehicles", "T_FreezeVehicles")

MP.RegisterEvent("onInit", "onInit")
MP.RegisterEvent("onVehicleSpawn", "onVehicleSpawn")
MP.RegisterEvent("onVehicleReset", "onVehicleReset")
MP.RegisterEvent("onVehicleEdited", "onVehicleEdited")
MP.RegisterEvent("onVehicleDeleted", "onVehicleDeleted")
MP.RegisterEvent("onPlayerJoin", "onPlayerJoin")
MP.RegisterEvent("onPLayerDisconnect", "onPLayerDisconnect")
MP.RegisterEvent("E_OnInitiliaze", "E_OnInitialize")
MP.RegisterEvent("ET_Update", "T_Update")
MP.RegisterEvent("ET_Countdown", "T_Countdown")
MP.CreateEventTimer("ET_Update", 25)

-- Server events
MP.RegisterEvent("E_RequestResetToRoad", "E_RequestResetToRoad")

return M