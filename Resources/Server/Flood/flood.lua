require("multiplayer")
local C = require("libs/client")
local U = require("libs/utils")
local L = require("libs/leaderboard")
local Weather = require("libs/weather")

-- Templates
local playerTemplate = {
    name = "", -- Player name
    vehicle = "",
    status = "spectating", -- Whether player is spectating or in game. spectating|inGame
    dead = false, -- Player is dead
    previouslyDead = false, -- Previous death status (for tracking death status changes)
    respawnedCount = 0, -- Times the player has respawned
    totalVehicles = 0, -- Total vehicles the player has spawned, excluding unicycles
    vehiclePower = 0, -- Vehicle engine power in kW
    announcedAsWinner = false, -- Whether this player has been announced as a winner this round
    hasWon = false, -- Whether this player has won (first to finish)
    hasFinished = false, -- Whether this player has finished the track (completed it)
    finishTime = 0, -- When the player finished (0 if not finished)
    roundComplete = false -- Whether this player's round is complete (won, finished, or died)
}

local vehicleTemplate = {
    positionRaw = nil, -- Fetched from getPositionRaw
    config = nil -- JSON config
}

-- Flood Status Constants (Game server best practices)
local FLOOD_STATUS = {
    STOPPED = "stopped",           -- No flood active, waiting for players/vehicles
    AUTO_START_COUNTDOWN = "auto_countdown", -- Auto-start countdown active (45s)
    ROUND_COUNTDOWN = "countdown", -- Round countdown active (5s before flood starts)
    ACTIVE = "active"              -- Flood is actively rising during round
}

-- Centralized Flood State System
local FloodState = {
    status = FLOOD_STATUS.STOPPED,
    speed = 0, -- m/s
    level = 0, -- Current water level
    lastUpdate = 0 -- Timestamp of last state change
}

local function sendFloodStateUpdate(pid)
    local floodStateJson = Util.JsonEncode({
        status = FloodState.status,
        speed = FloodState.speed,
        level = FloodState.level,
        lastUpdate = FloodState.lastUpdate
    })

    if pid then
        -- Send to specific player
        MP.TriggerClientEvent(pid, "E_FloodStateUpdate", floodStateJson)
    else
        -- Send to all players
        MP.TriggerClientEvent(-1, "E_FloodStateUpdate", floodStateJson)
    end
end

-- Function to update flood state and broadcast to clients
local function setFloodState(newStatus, newSpeed, newLevel)
    local changed = false
    local previousStatus = FloodState.status
    
    if newStatus and FloodState.status ~= newStatus then
        FloodState.status = newStatus
        changed = true
    end
    
    if newSpeed and FloodState.speed ~= newSpeed then
        FloodState.speed = newSpeed
        changed = true
    end
    
    if newLevel and FloodState.level ~= newLevel then
        FloodState.level = newLevel
        changed = true
    end
    
    if changed then
        FloodState.lastUpdate = U.getCurrentTimeMs()
        
        -- Handle weather changes based on flood state transitions
        if newStatus and newStatus ~= previousStatus then
            if newStatus == FLOOD_STATUS.ROUND_COUNTDOWN and WeatherSync then
                WeatherSync:onFloodStart()
            elseif newStatus == FLOOD_STATUS.AUTO_START_COUNTDOWN and WeatherSync then
                WeatherSync:onFloodStart()
            elseif newStatus == FLOOD_STATUS.STOPPED and (previousStatus == FLOOD_STATUS.ACTIVE or previousStatus == FLOOD_STATUS.ROUND_COUNTDOWN or previousStatus == FLOOD_STATUS.AUTO_START_COUNTDOWN) and WeatherSync then
                WeatherSync:onFloodEnd()
            end
        end
        
        -- Broadcast flood state to all clients using centralized function
        sendFloodStateUpdate()
        print("Flood state updated: " .. FloodState.status .. " | Speed: " .. FloodState.speed .. "m/s | Level: " .. FloodState.level)
    end
end

local M = {}

M.mapConfig = Util.JsonDecode(io.open("Resources/Server/Flood/config/map.json"):read("*all"))

M.options = {
    oceanLevel = M.mapConfig.floodOptions.oceanLevel,
    floodSpeed = M.mapConfig.floodOptions.floodSpeed, -- Now in meters per second
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
M.initialLevel = M.mapConfig.floodOptions.oceanLevel
M.commands = {}

M.countdown = {
    started = false,
    count = 5,
    currentCount = 0
}

M.autoStartCountdown = {
    started = false,
    count = 45,
    currentCount = 0
}

M.state = {
    floodStartQueued = false,
    players = {},
    clientStates = {}, -- Store client state updates here
    roundStartTime = 0, -- Track when the current round started (countdown end time in milliseconds)
    hasWinner = false -- Track if someone has already won this round
}

local invalidCount = 0

local function isValidPlayer(pid)
    if not pid then return false end
    
    local players = MP.GetPlayers()
    for validPid, _ in pairs(players) do
        if validPid == pid then
            return true
        end
    end
    return false
end

local function setWaterLevel(level)
    if not M.isOceanValid then
        print("setWaterLevel: ocean is nil")
        return
    end

    MP.TriggerClientEvent(-1, "E_SetWaterLevel", tostring(level))
end

local function isFloodOrCountdownStarted()
    return M.options.enabled or M.countdown.started
end

local function getPlayerState(pid)
    if M.state.players[pid] ~= nil then
        return M.state.players[pid]
    else
        return false
    end
end

local function updatePlayerStateVehicle(pid)
    -- Check if player is still valid before making API calls
    if not isValidPlayer(pid) then
        print("Warning: Player " .. tostring(pid) .. " is no longer valid, skipping vehicle update")
        return
    end

    local playerVehicles = MP.GetPlayerVehicles(pid);
    local playerState = getPlayerState(pid);
    local totalVehicles = 0 -- Excluding unicycles

    if not playerState then
        print("Warning: playerState is nil for player " .. tostring(pid))
        return
    end

    if playerVehicles then
        for vehicleId, vehicleConfigRaw in pairs(playerVehicles) do
            if not vehicleConfigRaw or type(vehicleConfigRaw) ~= "string" then
                print("Warning: invalid vehicleConfigRaw for player " .. tostring(pid) .. " vehicle " .. tostring(vehicleId))
                goto continue
            end

            local start = string.find(vehicleConfigRaw, "{")
            if not start then
                print("Warning: no JSON start found in vehicleConfigRaw for player " .. tostring(pid))
                goto continue
            end

            local formattedVehicleConfig = string.sub(vehicleConfigRaw, start, -1)
            
            local success, vehicleConfig = pcall(Util.JsonDecode, formattedVehicleConfig)
            if not success or not vehicleConfig then
                print("Warning: failed to decode vehicle config for player " .. tostring(pid) .. ": " .. tostring(vehicleConfig))
                goto continue
            end

            if vehicleConfig.jbm and vehicleConfig.jbm ~= "unicycle" then
                totalVehicles = totalVehicles + 1
                playerState.vehicle.config = vehicleConfig;
                -- Double-check player is still valid before getting position
                if isValidPlayer(pid) then
                    playerState.vehicle.positionRaw = MP.GetPositionRaw(pid, vehicleId)
                else
                    print("Warning: Player " .. tostring(pid) .. " disconnected during vehicle processing")
                    return
                end
                break
            end

            ::continue::
        end
    end

    playerState.totalVehicles = totalVehicles

    return {
        totalVehicles = totalVehicles
    }
end

local function beginFlood()
    MP.hSendChatMessage(-1, "^2^oThe water has begun to rise...")

    M.state.floodStartQueued = false
    M.options.enabled = true;
    M.countdown.currentCount = 0;

    MP.CreateEventTimer("ET_Update", 25)
    
    -- Start fast current round leaderboard updates during race
    MP.CreateEventTimer("ET_LeaderboardCurrentRound", 250)

    C.setVehicleFreeze(false)

    -- Clear previous round leaderboard data
    L.clearCurrentRound()
    
    M.state.roundStartTime = U.getCurrentTimeMs()

    -- Notify clients that round has started (send as string to preserve precision)
    MP.TriggerClientEvent(-1, "E_RoundStarted", tostring(M.state.roundStartTime))
    
    -- Update flood state to ACTIVE
    setFloodState(FLOOD_STATUS.ACTIVE, M.options.floodSpeed, M.options.oceanLevel)

    MP.TriggerClientEvent(-1, "E_EnableGhostCollisions", "")
end

local function startCountdown()
    MP.hSendChatMessage(-1, "^2^oFlood is beginning...")

    M.countdown.started = true;
    MP.CreateEventTimer("ET_Countdown", 1000)
    
    -- Update flood state to ROUND_COUNTDOWN
    setFloodState(FLOOD_STATUS.ROUND_COUNTDOWN, M.options.floodSpeed, M.options.oceanLevel)
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
    
    -- Update flood state to STOPPED when countdown is reset
    setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, M.options.oceanLevel)
end

local function startAutoStartCountdown()    
    MP.hSendChatMessage(-1, "^2^oFlood will start in " .. M.autoStartCountdown.count .. " seconds...")

    if isFloodOrCountdownStarted() then
        return
    end

    if M.autoStartCountdown.started then
        return
    end

    M.autoStartCountdown.started = true;
    U.setTimeout(function()
        MP.hSendChatMessage(-1, "If you get disconnected please reconnect immediately. The server periodically restarts.")
        MP.hSendChatMessage(-1, "Join Discord! Click the Discord icon in the Sea Level meter and paste the URL in a browser.")
        MP.hSendChatMessage(-1, "If you have any issues please RESTART BEAM.NG (close and reopen the game)")
    end, 5000)

    MP.CreateEventTimer("ET_AutoStartCountdown", 1000)
    
    -- Update flood state to AUTO_START_COUNTDOWN
    setFloodState(FLOOD_STATUS.AUTO_START_COUNTDOWN, M.options.floodSpeed, M.options.oceanLevel)
end

local function autoStartCountdownComplete()
    MP.CancelEventTimer("ET_AutoStartCountdown")
    M.autoStartCountdown.started = false;
    print("Auto start countdown complete")

    M.commands["start"]()
end

local function resetAutoStartCountdown()
    MP.CancelEventTimer("ET_AutoStartCountdown")
    M.autoStartCountdown.currentCount = 0;
    M.autoStartCountdown.started = false;
    
    -- Update flood state to STOPPED when auto countdown is reset
    setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, M.options.oceanLevel)
end

local function updatePlayersStatesVehicles()
    for pid, playerState in pairs(M.state.players) do
        updatePlayerStateVehicle(pid)
        -- playerState.totalVehicles = totalVehicles

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
    if not pid then
        print("Warning: updatePlayerState called with nil pid")
        return
    end
    
    createPlayerState(pid)

    local playerState = getPlayerState(pid)
    if not playerState then
        print("Warning: failed to create player state for " .. tostring(pid))
        return
    end

    playerState.name = MP.GetPlayerName(pid) or "Unknown";
    playerState.id = pid;

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

local function setPlayerStatus(pid, status)
    M.state.players[pid].status = status
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
            -- Validate player is still connected before processing
            if not isValidPlayer(pid) then
                print("Warning: Player " .. tostring(pid) .. " disconnected during vehicle reset, skipping")
                goto continue
            end
            
            local randomIndex = math.random(1, #positions)
            local posIndex = positions[randomIndex]
            table.remove(positions, randomIndex)

            updatePlayerStateVehicle(pid)

            if playerState.vehicle and playerState.vehicle.config and playerState.vehicle.config.vid then
                print("Entering vehicle " .. playerState.vehicle.config.vid)
                C.enterVehicle(pid, playerState.vehicle.config.vid)
            end

            local startPos = M.mapConfig.startPositions[posIndex]
            if startPos then
                MP.TriggerClientEvent(pid, "E_ResetVehicleToPos", Util.JsonEncode(startPos))
            end
        end
        ::continue::
    end
end

local function ensureVehiclesAreAboveWaterLine()
    local someoneDied = false
    local playersRemaining = 0
    
    for pid, playerState in pairs(M.state.players) do
        -- Validate player is still connected before accessing their data
        if not isValidPlayer(pid) then
            print("Warning: Player " .. tostring(pid) .. " disconnected, removing from water check")
            M.state.players[pid] = nil
            M.state.clientStates[pid] = nil
            L.removeCurrentRoundPlayer(pid)
            goto continue
        end
        
        if playerState.vehicle and playerState.vehicle.positionRaw and playerState.vehicle.positionRaw.pos then
            if playerState.status == "inGame" then
                if playerState.vehicle.positionRaw.pos[3] < M.options.oceanLevel - 4 and not playerState.dead then
                    playerState.dead = true
                    playerState.roundComplete = true -- Mark as round complete when dying
                    -- Record death time with millisecond precision
                    playerState.deathTime = U.getCurrentTimeMs()
                    print("Player " .. pid .. " is dead")
                    MP.hSendChatMessage(-1, "^4" .. MP.GetPlayerName(pid) .. " ^r^3^l^o died...")
                    someoneDied = true
                end

                if not playerState.dead then
                    playersRemaining = playersRemaining + 1
                end
            end
        end
        ::continue::
    end

    if someoneDied then
        someoneDied = false
        MP.hSendChatMessage(-1, "^4 Players remaining:^l" .. playersRemaining)
    end
end



local function getPlayerRankings()
    -- Get rankings from leaderboard system
    local currentRound = L.getCurrentRoundLeaderboard()
    local rankings = {}
    
    for i, entry in ipairs(currentRound) do
        if M.state.players[entry.playerId] and M.state.players[entry.playerId].status == "inGame" then
            table.insert(rankings, {
                pid = entry.playerId,
                name = entry.name,
                distanceTraveled = entry.bestDistanceTraveled or 0,
                dead = not entry.isAlive  -- entry.isAlive = true means alive, so dead = false when alive
            })
        end
    end
    
    return rankings
end

local function handlePlayerFinishing(finishers)
    if not finishers or #finishers == 0 then return end
    
    -- Get current time with millisecond precision
    local currentTime = U.getCurrentTimeMs()
    
    for _, finisher in ipairs(finishers) do
        local playerState = getPlayerState(finisher.pid)
        if playerState and not playerState.hasFinished then
            playerState.hasFinished = true
            playerState.finishTime = currentTime
            playerState.roundComplete = true
            
            -- First player to finish wins
            if not M.state.hasWinner then
                M.state.hasWinner = true
                playerState.hasWon = true
                MP.hSendChatMessage(-1, "^6^o^l" .. finisher.name .. " ^r^6^l^ohas WON the race!")
                
                -- Send winner event to client to stop their timer
                MP.TriggerClientEvent(finisher.pid, "E_PlayerWon", tostring(currentTime))
                MP.TriggerClientEvent(-1, "E_PlayerFinished", Util.JsonEncode({
                    playerId = finisher.pid,
                    name = finisher.name,
                    isWinner = true,
                    finishTime = currentTime
                }))
            else
                -- Subsequent finishers
                MP.hSendChatMessage(-1, "^2^o^l" .. finisher.name .. " ^r^2^l^ohas finished the race!")
                
                -- Send finish event to client to stop their timer
                MP.TriggerClientEvent(finisher.pid, "E_PlayerFinished", Util.JsonEncode({
                    playerId = finisher.pid,
                    name = finisher.name,
                    isWinner = false,
                    finishTime = currentTime
                }))
            end
        end
    end
end

local function checkIfRoundShouldEnd()
    if M.state.floodStartQueued then return end
    
    local totalPlayers = 0
    local completedPlayers = 0
    
    for pid, playerState in pairs(M.state.players) do
        if playerState.status == "inGame" then
            totalPlayers = totalPlayers + 1
            if playerState.roundComplete then
                completedPlayers = completedPlayers + 1
            end
        end
    end
    
    -- Only end round if all players have completed (won, finished, or died)
    if totalPlayers > 0 and completedPlayers >= totalPlayers then
        MP.hSendChatMessage(-1, "^6^oStarting next round in 10 seconds...")
        
        M.state.floodStartQueued = true
        U.setTimeout(function()
            -- Save round results before stopping (calculate duration in milliseconds)
            local currentTime = U.getCurrentTimeMs()
            local roundDuration = currentTime - M.state.roundStartTime
            L.saveRoundResults(roundDuration, M.options.floodSpeed)
            
            M.commands["stop"]("")
            startAutoStartCountdown()
        end, 10000)
    end
end



local function checkForNoVehicles()
    local vehiclesSpawned = false
    for pid, playerState in pairs(M.state.players) do
        if not isValidPlayer(pid) then
            print("Warning: Player " .. tostring(pid) .. " disconnected, removing from vehicle check")
            M.state.players[pid] = nil
            M.state.clientStates[pid] = nil
            L.removeCurrentRoundPlayer(pid)
            goto continue
        end
        
        if playerState and playerState.totalVehicles and playerState.totalVehicles > 0 then
            vehiclesSpawned = true
            break
        end
        ::continue::
    end

    return not vehiclesSpawned
end

local function stopFloodWhenNoVehicles()
    if checkForNoVehicles() then
        MP.hSendChatMessage(-1, "^4^lNo vehicles found, stopping flood")
        M.commands["stop"]("")
    end
end

function updateDestinationForClients(destinationPos)
    if not destinationPos then return end
    
    MP.TriggerClientEvent(-1, "E_SetDestinationPos", Util.JsonEncode(destinationPos))
    print("Destination position updated for all clients")
end

local function welcomePlayer(pid)
    MP.hSendChatMessage(pid, "^eWelcome to the flood! Flood will start automatically.")
    MP.hSendChatMessage(pid, "Kindly reconnect if you experience any issues, or if the leaderboard is not visible. Bug fixes in progress.")
    MP.hSendChatMessage(pid, "Use ^2/flood_start^r to start the flood early.")
    MP.hSendChatMessage(pid, "Use ^2/flood_stop^r to stop the flood.")
    -- MP.hSendChatMessage(pid, "Use ^2/flood_restart^r to restart the flood.")
    -- MP.hSendChatMessage(pid, "Use ^b/flood_reset^r to reset the flood.")
    -- MP.hSendChatMessage(pid, "Use ^b/flood_level^r to set the flood level.")
    MP.hSendChatMessage(pid, "Use ^b/flood_speed^r to set the flood speed.")
    MP.hSendChatMessage(pid, "Use ^b/flood_weather^r to change weather presets.")
end

local function prepareFlood()
    print("Preparing flood")

    MP.TriggerClientEvent(-1, "E_DisableCollisions", "")
    resetPlayersRespawnedCount()
    resetAutoStartCountdown()
    resetCountdown()

    -- Reset winner state
    M.state.hasWinner = false

    for pid, playerState in pairs(M.state.players) do
        -- Update player vehicle count before round starts
        updatePlayerStateVehicle(pid)
        
        setPlayerDead(pid, false)
        playerState.previouslyDead = false -- Reset death tracking for new round
        playerState.announcedAsWinner = false -- Reset winner announcement for new round
        playerState.hasWon = false -- Reset win state
        playerState.hasFinished = false -- Reset finish state
        playerState.finishTime = 0 -- Reset finish time
        playerState.roundComplete = false -- Reset round completion state
        if playerState.totalVehicles > 0 then
            setPlayerStatus(pid, "inGame")
            print("Player " .. tostring(pid) .. " (" .. (playerState.name or "Unknown") .. ") set to inGame with " .. playerState.totalVehicles .. " vehicles")
        else
            setPlayerStatus(pid, "spectating")
            print("Player " .. tostring(pid) .. " (" .. (playerState.name or "Unknown") .. ") set to spectating - no vehicles")
            MP.hSendChatMessage(pid, "^3You are spectating this round because you don't have a vehicle. Spawn a vehicle to participate in the next round!")
        end
    end

    if M.mapConfig.destination and M.mapConfig.destination.pos then
        updateDestinationForClients(M.mapConfig.destination.pos)
    end
    
    setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, M.options.oceanLevel)

    U.setTimeout(function()
        C.setVehicleFreeze(true)
        C.setVehicleRecoveryEnabled(false)
        resetVehiclesToStartPositions()
        U.setTimeout(startCountdown, 1000)
    end, 250)
end

-- BeamMP events

function onPlayerJoin(pid)
    -- Add error handling wrapper
    local success, err = pcall(function()
        if not pid then
            print("Error: onPlayerJoin called with nil pid")
            return
        end
        
        print("Player " .. tostring(pid) .. " joining...")
        
        C.setUiLayout(pid, "flood v0.20")

        U.setTimeout(function()
            C.setUiLayout(pid, "flood v0.20")
            welcomePlayer(pid)
        end, 3000)

        local eventSuccess = MP.TriggerClientEvent(pid, "E_OnPlayerLoaded", "")
        if eventSuccess then
            print("Successfully sent \"E_OnPlayerLoaded\" to " .. pid)
        else
            print("Failed to send \"E_OnPlayerLoaded\" to " .. pid)
        end
        
        if M.mapConfig and M.mapConfig.destination and M.mapConfig.destination.pos then
            MP.TriggerClientEvent(pid, "E_SetDestinationPos", Util.JsonEncode(M.mapConfig.destination.pos))
        end
        
        -- Sync rain & volume
        if M.options.rainAmount > 0.0 then
            MP.TriggerClientEvent(pid, "E_SetRainAmount", tostring(M.options.rainAmount))
        end

        if M.options.rainVolume > 0.0 then
            MP.TriggerClientEvent(pid, "E_SetRainVolume", tostring(M.options.rainVolume))
        end
        
        -- Send current flood state to new player using centralized function
        sendFloodStateUpdate(pid)
        
        -- Sync weather to new player
        if WeatherSync then
            WeatherSync:recalcServerTimeOfDay()
            WeatherSync:syncTimeOfDay()
        end
        
        updatePlayerState(pid)
        
        U.setTimeout(function()
            -- Update player state but do not add to leaderboard if round is active
            updatePlayerState(pid)
            local playerState = getPlayerState(pid)
            
            if M.options.enabled and M.state.roundStartTime > 0 then
                -- Round is active - set player as spectating (they can watch but not compete)
                if playerState then
                    setPlayerStatus(pid, "spectating")
                end
            else
                -- No active round - player can be set to inGame if they have vehicles
                if playerState and playerState.totalVehicles > 0 then
                    setPlayerStatus(pid, "inGame")
                end
            end
            
            -- Send round start time if round is active (for UI timer display)
            if M.state.roundStartTime > 0 then
                MP.TriggerClientEvent(pid, "E_RoundStarted", tostring(M.state.roundStartTime))
            end
        end, 2000)
    end)

    U.setTimeout(function()
        local playerState = getPlayerState(pid)
        if playerState and playerState.totalVehicles == 0 then
            C.spawnDefaultVehicle(pid)
        end
    end, 6000)
    
    if not success then
        print("Error in onPlayerJoin for player " .. tostring(pid) .. ": " .. tostring(err))
    end
end

function onPlayerDisconnect(pid)
    deletePlayerState(pid)
    M.state.clientStates[pid] = nil -- Clean up client state
    L.removeCurrentRoundPlayer(pid) -- Remove from leaderboard
end

function onVehicleSpawn(pid, vid, data)
    if MP.GetPlayerCount() >= 1 and not M.autoStartCountdown.started and not M.countdown.started and not M.options.enabled and not M.state.floodStartQueued then
        startAutoStartCountdown()
    end

    return 0
end

function onVehicleReset(pid, pName, data)
    updatePlayerState(pid)
    return true
end

function onVehicleEdited(pid, pName, data)
    updatePlayerState(pid)
    return 0
end

function onVehicleDeleted(pid, pName)
    updatePlayerState(pid)
    return true;
end

function onInit()
    MP.CancelEventTimer("ET_Update")
    MP.CancelEventTimer("ET_LeaderboardFull")
    MP.CancelEventTimer("ET_LeaderboardCurrentRound")
    MP.CancelEventTimer("ET_WeatherSync")
    
    -- Initialize leaderboard system
    L.initialize()
    
    -- Initialize weather system
    WeatherSync:init(M.mapConfig, function()
        -- Weather system initialized, start sync timer
        MP.CreateEventTimer("ET_WeatherSync", 1000)
        MP.RegisterEvent("ET_WeatherSync", "T_WeatherSync")
        print("[WEATHER] Weather sync system started")
    end)
    
    -- Start full leaderboard broadcasting timer (every 5 seconds always)
    MP.CreateEventTimer("ET_LeaderboardFull", 5000)
    
    -- Initialize flood state to STOPPED
    setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, M.options.oceanLevel)

    for pid, player in pairs(MP.GetPlayers()) do
        onPlayerJoin(pid)
    end
end

function T_Countdown()
    if (M.countdown.currentCount <= M.countdown.count) then
        local currentCount = M.countdown.count - M.countdown.currentCount

        if M.countdown.currentCount == M.countdown.count then
            countdownComplete()
        else
            if currentCount == 3 then
                C.playCountdown()
            end

            M.countdown.currentCount = M.countdown.currentCount + 1;
        end
    end
end

function T_AutoStartCountdown()
    if (M.autoStartCountdown.currentCount <= M.autoStartCountdown.count) then
        local currentCount = M.autoStartCountdown.count - M.autoStartCountdown.currentCount

        if M.autoStartCountdown.currentCount == M.autoStartCountdown.count then
            autoStartCountdownComplete()
        else
            M.autoStartCountdown.currentCount = M.autoStartCountdown.currentCount + 1;
        end
    end
end

function T_LeaderboardFull()
    -- Broadcast full leaderboard updates every 5 seconds always
    L.broadcastFullLeaderboardUpdate()
end

function T_LeaderboardCurrentRound()
    -- Broadcast current round updates every 250ms during race
    L.broadcastCurrentRoundUpdate()
end

function T_WeatherSync()
    -- Weather system tick for time progression
    if WeatherSync then
        WeatherSync:tick()
    end
end

function T_Update()
    if not M.isOceanValid or not M.options.enabled then return end

    local level = M.options.oceanLevel
    -- Convert meters per second to meters per 25ms update (floodSpeed is in m/s)
    local changeAmount = M.options.floodSpeed * 0.025
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
    
    -- Update leaderboard data (for alive players + one final update for newly dead players)
    for pid, playerState in pairs(M.state.players) do
        if playerState and playerState.status == "inGame" then
            -- Validate player is still connected before updating leaderboard
            if not isValidPlayer(pid) then
                print("Warning: Player " .. tostring(pid) .. " disconnected, removing from current round")
                M.state.players[pid] = nil
                M.state.clientStates[pid] = nil
                L.removeCurrentRoundPlayer(pid)
                goto continue
            end
            
            -- Check if we need to send an update for this player
            local shouldUpdate = false
            
            if not playerState.dead then
                -- Always update alive players
                shouldUpdate = true
            else
                -- For dead players, only update if they just died (death status changed)
                if not playerState.previouslyDead then
                    -- Player just died, send one final update
                    shouldUpdate = true
                    playerState.previouslyDead = true -- Mark as previously dead to prevent further updates
                end
            end
            
            if shouldUpdate then
                -- Initialize client state if not exists
                if not M.state.clientStates[pid] then
                    M.state.clientStates[pid] = {}
                end
                L.updateCurrentRoundPlayer(pid, playerState, M.state.clientStates[pid], M.mapConfig, M.state.roundStartTime)
            end
        end
        ::continue::
    end
    
    -- Check for finishers (players who reached the destination)
    local finishers = {}
    local currentRound = L.getCurrentRoundLeaderboard()
    local trackLength = M.mapConfig.totalDistance or 13099
    
    for _, entry in ipairs(currentRound) do
        if entry.bestDistanceTraveled >= trackLength and entry.isAlive then
            local playerState = getPlayerState(entry.playerId)
            if playerState and playerState.status == "inGame" and not playerState.hasFinished then
                table.insert(finishers, {
                    pid = entry.playerId,
                    name = entry.name,
                    distanceTraveled = entry.bestDistanceTraveled
                })
            end
        end
    end
    
    -- Handle players finishing the race
    handlePlayerFinishing(finishers)
    
    -- Check if round should end (all players completed)
    checkIfRoundShouldEnd()
    stopFloodWhenNoVehicles()
end

function E_OnInitialize(pid, waterLevel)
    waterLevel = tonumber(waterLevel) or nil

    print("E_OnInitialize: waterLevel for player " .. MP.GetPlayerName(pid) .. " is " .. waterLevel)

    -- Make sure the level has an ocean, we use "invalidCount" to make sure it's not just 1 player that doesn't have an ocean
    if not waterLevel and invalidCount < 2 then
        print("E_OnInitialize: waterLevel for player " .. MP.GetPlayerName(pid) .. " is nil")
        invalidCount = invalidCount + 1
        return
    elseif not waterLevel and invalidCount >= 2 then
        print("This map doesn't have an ocean, disabling flood")
        return
    end

    M.isOceanValid = true
    if M.initialLevel == 0.0 then
        print("Setting initial water level to " .. waterLevel)
        M.initialLevel = waterLevel -- We sadly have to rely on the client 😅🔫
        M.options.oceanLevel = waterLevel
        
        -- Update flood state with the real water level
        setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, waterLevel)
    end

    C.spawnDefaultVehicle(pid)
    
    -- Add delay to ensure vehicle spawn is complete before updating player state
    U.setTimeout(function()
        updatePlayerState(pid)
        
        if MP.GetPlayerCount() >= 1 and not M.autoStartCountdown.started and not M.countdown.started and not M.options.enabled then
            startAutoStartCountdown()
        end
    end, 2000)
end

M.commands["start"] = function(pid)
    if checkForNoVehicles() then
        MP.hSendChatMessage(-1, "^4^lNo vehicles found, flood will start automatically when a vehicle spawns")
        return
    end

    if pid then
        if not M.isOceanValid then
            MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
            return
        end

        if isFloodOrCountdownStarted() then
            MP.hSendChatMessage(pid, "Flood has already started")
            return
        end
    end
    
    if M.options.oceanLevel == 0.0 then
        M.options.oceanLevel = M.initialLevel
    end

    prepareFlood()
end

M.commands["stop"] = function(pid)
    MP.CancelEventTimer("ET_Update")
    MP.CancelEventTimer("ET_LeaderboardCurrentRound") -- Stop fast current round updates
    resetPlayersRespawnedCount()
    resetAutoStartCountdown()
    resetCountdown();

    -- Notify clients that round has ended (with millisecond precision)
    local currentTime = U.getCurrentTimeMs()
    MP.TriggerClientEvent(-1, "E_RoundEnded", tostring(currentTime))

    U.setTimeout(function()
        C.setVehicleRecoveryEnabled(true)
        resetVehiclesToStartPositions()
        MP.TriggerClientEvent(-1, "E_EnableCollisions", "")
    end, 250)

    M.state.floodStartQueued = false
    M.options.enabled = false
    M.options.oceanLevel = M.initialLevel
    setWaterLevel(M.initialLevel)

    -- Update flood state to STOPPED
    setFloodState(FLOOD_STATUS.STOPPED, M.options.floodSpeed, M.initialLevel)

    for pid, playerState in pairs(M.state.players) do
        setPlayerDead(pid, false)
        setPlayerStatus(pid, "spectating")
    end
end

M.commands["reset"] = function(pid)
    if not M.isOceanValid then
        MP.hSendChatMessage(pid, "This map doesn't have an ocean, unable to flood")
        return
    end

    M.commands["stop"](pid);

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

    M.commands["stop"](pid);


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
    -- Update flood state with new speed
    setFloodState(nil, speed, nil)
    MP.hSendChatMessage(pid, "Set flood speed to " .. speed .. " m/s")
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

M.commands["debug"] = function(pid, pos)
    pos = tonumber(pos) or nil
    if not pos then
        MP.hSendChatMessage(pid, "Invalid position")
        return
    end

    local startPos = M.mapConfig.startPositions[pos]
    if startPos then
        MP.TriggerClientEvent(pid, "E_ResetVehicleToPos", Util.JsonEncode(startPos))
    end
end

function E_RequestResetToRoad(pid, ...)
    if not isFloodOrCountdownStarted() then
        return
    end

    local playerState = getPlayerState(pid)
    local respawnedCount = playerState.respawnedCount


    if not M.options.enabled then
        return
    end

    if playerState.dead then
        MP.hSendChatMessage(pid, "^4^lYou are dead, you can't respawn")
        return
    end

    if respawnedCount >= M.mapConfig.respawnLimit then
        MP.hSendChatMessage(pid, "^4^lOut of respawns")
        return
    end

    MP.TriggerClientEvent(pid, "E_ResetToRoad", Util.JsonEncode(M.mapConfig.destination.pos))
    
    MP.hSendChatMessage(pid, "^2Vehicle reset to road (^4^l" .. respawnedCount + 1 .. "^r/^2^l" .. M.mapConfig.respawnLimit .. "^r^2) resets used")

    incrementPlayerRespawnedCount(pid)
end

function E_ClientStateUpdate(pid, stateJson)
    local success, clientState = pcall(Util.JsonDecode, stateJson)
    if not success or not clientState or type(clientState) ~= "table" then
        print("Warning: Invalid client state JSON from player " .. tostring(pid) .. ": " .. tostring(stateJson))
        return
    end
    
    M.state.clientStates[pid] = clientState
    
    -- Update player state with vehicle power if available
    local playerState = getPlayerState(pid)
    if playerState and clientState.vehiclePower and type(clientState.vehiclePower) == "number" then
        playerState.vehiclePower = clientState.vehiclePower
    end
    
    -- Distance tracking is now handled by the leaderboard system
end


MP.RegisterEvent("onInit", "onInit")
MP.RegisterEvent("onVehicleSpawn", "onVehicleSpawn")
MP.RegisterEvent("onVehicleReset", "onVehicleReset")
MP.RegisterEvent("onVehicleEdited", "onVehicleEdited")
MP.RegisterEvent("onVehicleDeleted", "onVehicleDeleted")
MP.RegisterEvent("onPlayerJoin", "onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
MP.RegisterEvent("E_OnInitiliaze", "E_OnInitialize")
MP.RegisterEvent("ET_Update", "T_Update")
MP.RegisterEvent("ET_Countdown", "T_Countdown")
MP.RegisterEvent("ET_AutoStartCountdown", "T_AutoStartCountdown")
MP.RegisterEvent("ET_LeaderboardFull", "T_LeaderboardFull")
MP.RegisterEvent("ET_LeaderboardCurrentRound", "T_LeaderboardCurrentRound")

-- Server events
MP.RegisterEvent("E_RequestResetToRoad", "E_RequestResetToRoad")
MP.RegisterEvent("E_ClientStateUpdate", "E_ClientStateUpdate")

-- Add a command to show current rankings
M.commands["rankings"] = function(pid)
    local rankings = getPlayerRankings()
    MP.hSendChatMessage(pid, "^5^l===== FURTHEST DISTANCE TRAVELED =====")
    
    if #rankings == 0 then
        MP.hSendChatMessage(pid, "^3No players in game yet")
        return
    end
    
    for i, player in ipairs(rankings) do
        local status = player.dead and "^1[DEAD]" or "^2[ALIVE]"
        MP.hSendChatMessage(pid, "^5^l#" .. i .. ": " .. player.name .. " - " .. 
                            math.floor(player.distanceTraveled) .. "m traveled " .. status)
    end
end

-- Add command to send leaderboard update to specific player
M.commands["leaderboard"] = function(pid)
    L.sendLeaderboardUpdate(pid)
    MP.hSendChatMessage(pid, "^2Leaderboard updated!")
end

-- Add command to show leaderboard stats for debugging
M.commands["leaderboard_debug"] = function(pid)
    local currentRound = L.getCurrentRoundLeaderboard()
    local dailyCount = #L.getDailyLeaderboard()
    local weeklyCount = #L.getWeeklyLeaderboard()
    
    MP.hSendChatMessage(pid, "^5Leaderboard Debug:")
    MP.hSendChatMessage(pid, "^7Current round players: " .. #currentRound)
    MP.hSendChatMessage(pid, "^7Daily records: " .. dailyCount)
    MP.hSendChatMessage(pid, "^7Weekly records: " .. weeklyCount)
    
    if #currentRound > 0 then
        MP.hSendChatMessage(pid, "^7Top 3 current round:")
        for i = 1, math.min(3, #currentRound) do
            local entry = currentRound[i]
            MP.hSendChatMessage(pid, "^7  " .. i .. ". " .. entry.name .. " - " .. math.floor(entry.distanceTraveled or 0) .. "m traveled")
        end
    end
end

-- Add command to migrate leaderboard data to milliseconds
M.commands["migrate_milliseconds"] = function(pid)
    if pid then
        MP.hSendChatMessage(pid, "^5Migrating leaderboard data to millisecond precision...")
        local success = L.migrateToMilliseconds()
        if success then
            MP.hSendChatMessage(pid, "^2Migration completed successfully!")
        else
            MP.hSendChatMessage(pid, "^7No data needed migration.")
        end
    end
end

M.commands["collisions_forced"] = function(pid)
    MP.TriggerClientEvent(-1, "E_EnableCollisions", "")
    MP.hSendChatMessage(-1, "^6Collisions set to FORCED - vehicles will collide normally")
end

M.commands["collisions_disabled"] = function(pid)
    MP.TriggerClientEvent(-1, "E_DisableCollisions", "")
    MP.hSendChatMessage(-1, "^4Collisions DISABLED - vehicles pass through each other")
end

M.commands["collisions_ghosts"] = function(pid)
    MP.TriggerClientEvent(-1, "E_EnableGhostCollisions", "")
    MP.hSendChatMessage(-1, "^2Collisions set to GHOSTS - smart collision system enabled")
end

-- Debug command to test flood status
M.commands["flood_status"] = function(pid, status)
    if not status then
        MP.hSendChatMessage(pid, "^7Current flood status: ^2" .. FloodState.status)
        MP.hSendChatMessage(pid, "^7Speed: ^2" .. FloodState.speed .. "m/s")
        MP.hSendChatMessage(pid, "^7Level: ^2" .. FloodState.level)
        MP.hSendChatMessage(pid, "^7Available statuses: stopped, auto_countdown, countdown, active")
        return
    end
    
    local validStatuses = {
        stopped = FLOOD_STATUS.STOPPED,
        auto_countdown = FLOOD_STATUS.AUTO_START_COUNTDOWN,
        countdown = FLOOD_STATUS.ROUND_COUNTDOWN,
        active = FLOOD_STATUS.ACTIVE
    }
    
    if validStatuses[status] then
        setFloodState(validStatuses[status], M.options.floodSpeed, M.options.oceanLevel)
        MP.hSendChatMessage(pid, "^2Flood status set to: " .. status)
    else
        MP.hSendChatMessage(pid, "^4Invalid status. Use: stopped, auto_countdown, countdown, active")
    end
end

-- Debug command to manually send flood state update
M.commands["flood_sync"] = function(pid)
    if pid then
        sendFloodStateUpdate(pid)
        MP.hSendChatMessage(pid, "^2Flood state synced to your client")
    else
        sendFloodStateUpdate()
        MP.hSendChatMessage(-1, "^2Flood state synced to all clients")
    end
end

-- Weather-related commands
M.commands["weather"] = function(pid, presetName)
    if not WeatherSync then
        MP.hSendChatMessage(pid, "^4Weather system not initialized")
        return
    end
    
    if not presetName then
        -- Show current weather and available presets
        local current = WeatherSync:getCurrentPreset()
        MP.hSendChatMessage(pid, "^7Current weather preset: ^2" .. (current or "none"))
        
        local presets = WeatherSync:getAvailablePresets()
        if #presets > 0 then
            MP.hSendChatMessage(pid, "^7Available presets:")
            for _, preset in ipairs(presets) do
                MP.hSendChatMessage(pid, "^7  - ^2" .. preset.name .. "^7 (" .. preset.displayName .. ")")
            end
        else
            MP.hSendChatMessage(pid, "^7No weather presets available")
        end
        return
    end
    
    local success = WeatherSync:applyPreset(presetName, true) -- Mark as manual change
    if success then
        MP.hSendChatMessage(-1, "^6Weather changed to: " .. presetName .. " ^7(by " .. MP.GetPlayerName(pid) .. ")")
    else
        MP.hSendChatMessage(pid, "^4Failed to apply weather preset: " .. presetName)
    end
end

M.commands["weather_auto"] = function(pid, enabled)
    if not WeatherSync then
        MP.hSendChatMessage(pid, "^4Weather system not initialized")
        return
    end
    
    if not enabled then
        local autoEnabled = WeatherSync.weatherSettings.autoChangeWeather
        local manualOverride = WeatherSync:isManualOverride()
        MP.hSendChatMessage(pid, "^7Auto weather change is: ^2" .. (autoEnabled and "enabled" or "disabled"))
        MP.hSendChatMessage(pid, "^7Manual override active: ^2" .. (manualOverride and "yes" or "no"))
        MP.hSendChatMessage(pid, "^7Use: /flood_weather_auto true/false")
        MP.hSendChatMessage(pid, "^7Use: /flood_weather_auto reset to clear manual override")
        return
    end
    
    if string.lower(enabled) == "reset" then
        WeatherSync:clearManualOverride()
        MP.hSendChatMessage(pid, "^2Manual weather override cleared - auto weather will resume")
        return
    end
    
    if string.lower(enabled) == "true" or enabled == "1" then
        enabled = true
    elseif string.lower(enabled) == "false" or enabled == "0" then
        enabled = false
    else
        MP.hSendChatMessage(pid, "^4Please use true/false, 1/0, or reset")
        return
    end
    
    WeatherSync.weatherSettings.autoChangeWeather = enabled
    MP.hSendChatMessage(pid, "^2Auto weather change " .. (enabled and "enabled" or "disabled"))
end

-- Expose flood state functions for external use
M.getFloodState = function()
    return FloodState
end

M.sendFloodStateUpdate = sendFloodStateUpdate
M.buildFloodStateJson = buildFloodStateJson

return M