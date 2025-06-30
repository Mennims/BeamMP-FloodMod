local M = {}
local U = require("libs/utils")

-- File paths
local LEADERBOARD_DATA_FILE = "Resources/Server/Flood/data/leaderboard.json"

-- Leaderboard state
M.state = {
    currentRound = {},
    dailyRecords = {},
    weeklyRecords = {},
    lastUpdateTime = 0,
    updateInterval = 1000, -- Send updates every 1 second
}

-- Templates for leaderboard entries
local currentRoundEntryTemplate = {
    playerId = "",
    name = "",
    vehicleName = "", -- TODO: Need to implement vehicle name retrieval
    enginePower = 0, -- Vehicle engine power in kW (received from client)
    currentDistanceToDestination = 999999, -- Current road distance remaining to destination
    trackLength = 0, -- Total track length from map config
    distanceTraveled = 0, -- Distance traveled from start (trackLength - currentDistanceToDestination)
    bestDistanceTraveled = 0, -- Best (furthest) distance traveled achieved this round
    progressPercent = 0,
    resetsUsed = 0,
    position = 1, -- Current leaderboard position
    isAlive = true,
    timeAlive = 0, -- Time alive in seconds
    spawnTime = 0, -- When the player spawned/started this round
    deathTime = 0, -- When the player died (0 if still alive)
    lastUpdate = 0 -- Timestamp of last update
}

local historicalEntryTemplate = {
    playerId = "",
    name = "",
    vehicleName = "",
    enginePower = 0,
    finalDistanceTraveled = 0, -- Final distance traveled when round ended
    trackLength = 0, -- Total track length
    progressPercent = 0,
    resetsUsed = 0,
    floodSpeed = 0,
    roundDuration = 0, -- Duration of the round in seconds
    timeAlive = 0, -- Time the player was alive in seconds
    timestamp = 0, -- When the round ended
    position = 1 -- Final position in that round
}

-- Initialize leaderboard data
local function initializeLeaderboardData()
    local file = io.open(LEADERBOARD_DATA_FILE, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        if content and content ~= "" then
            local success, data = pcall(Util.JsonDecode, content)
            if success and data then
                M.state.dailyRecords = data.dailyRecords or {}
                M.state.weeklyRecords = data.weeklyRecords or {}
                print("Loaded leaderboard data successfully")
                return
            end
        end
    end
    
    print("Initializing new leaderboard data file")
    M.state.dailyRecords = {}
    M.state.weeklyRecords = {}
    M.saveLeaderboardData()
end

-- Save leaderboard data to file
function M.saveLeaderboardData()
    local data = {
        dailyRecords = M.state.dailyRecords,
        weeklyRecords = M.state.weeklyRecords,
        lastSaved = os.time()
    }
    
    local success, jsonString = pcall(Util.JsonEncode, data)
    if not success then
        print("Error encoding leaderboard data: " .. tostring(jsonString))
        return false
    end
    
    local file = io.open(LEADERBOARD_DATA_FILE, "w")
    if file then
        file:write(jsonString)
        file:close()
        return true
    else
        print("Error saving leaderboard data to file")
        return false
    end
end

-- Clean old records (remove records older than specified days)
local function cleanOldRecords()
    local currentTime = os.time()
    local dailyThreshold = currentTime - (24 * 60 * 60) -- 24 hours
    local weeklyThreshold = currentTime - (7 * 24 * 60 * 60) -- 7 days
    
    -- Clean daily records
    local newDailyRecords = {}
    for _, record in pairs(M.state.dailyRecords) do
        if record.timestamp > dailyThreshold then
            table.insert(newDailyRecords, record)
        end
    end
    M.state.dailyRecords = newDailyRecords
    
    -- Clean weekly records  
    local newWeeklyRecords = {}
    for _, record in pairs(M.state.weeklyRecords) do
        if record.timestamp > weeklyThreshold then
            table.insert(newWeeklyRecords, record)
        end
    end
    M.state.weeklyRecords = newWeeklyRecords
end

-- Get track length from map config
local function getTrackLength(mapConfig)
    return mapConfig.totalDistance or 13098 -- Default fallback track length
end

-- Add or update a player in the current round leaderboard
function M.updateCurrentRoundPlayer(playerId, playerState, clientState, mapConfig, roundStartTime)
    if not playerId or not playerState then return end
    
    local currentTime = os.time()
    local entry = M.state.currentRound[playerId]
    local wasAlive = entry and entry.isAlive
    
    if not entry then
        entry = U.deepcopy(currentRoundEntryTemplate)
        entry.playerId = playerId
        entry.trackLength = getTrackLength(mapConfig)
        entry.spawnTime = roundStartTime or currentTime
        M.state.currentRound[playerId] = entry
    end
    
    -- Update basic info
    entry.name = playerState.name or ""
    local isAlive = not playerState.dead
    entry.isAlive = isAlive
    entry.resetsUsed = playerState.respawnedCount or 0
    entry.lastUpdate = currentTime
    
    -- Handle death time tracking
    if wasAlive and not isAlive and entry.deathTime == 0 then
        entry.deathTime = currentTime
    end
    
    -- Calculate time alive
    if isAlive then
        entry.timeAlive = currentTime - entry.spawnTime
    else
        -- Player is dead, use death time if available, otherwise current time
        local endTime = entry.deathTime > 0 and entry.deathTime or currentTime
        entry.timeAlive = endTime - entry.spawnTime
    end
    
    -- Update distance info
    if clientState and clientState.roadDistance then
        entry.currentDistanceToDestination = tonumber(clientState.roadDistance) or entry.currentDistanceToDestination
    end
    
    -- Player state backup is no longer needed since we handle distance tracking here
    
    -- Calculate distance traveled and progress percentage
    if entry.trackLength > 0 then
        -- Distance traveled = track length - distance remaining to destination
        entry.distanceTraveled = math.max(0, entry.trackLength - entry.currentDistanceToDestination)
        
        -- Update best distance traveled (furthest progress this round)
        if entry.distanceTraveled > entry.bestDistanceTraveled then
            entry.bestDistanceTraveled = entry.distanceTraveled
        end
        
        entry.progressPercent = math.max(0, math.min(100, (entry.bestDistanceTraveled / entry.trackLength) * 100))
    end
    
    -- Update vehicle info
    entry.vehicleName = M.getVehicleName(playerState.vehicle.config)
    entry.enginePower = playerState.vehiclePower or 0
end

-- Remove a player from current round leaderboard
function M.removeCurrentRoundPlayer(playerId)
    M.state.currentRound[playerId] = nil
end

-- Get current round leaderboard sorted by progress (best distance)
function M.getCurrentRoundLeaderboard()
    local leaderboard = {}
    
    for playerId, entry in pairs(M.state.currentRound) do
        table.insert(leaderboard, entry)
    end
    
    -- Sort by best distance traveled (descending = better progress)
    table.sort(leaderboard, function(a, b)
        -- Alive players always rank higher than dead players
        if a.isAlive ~= b.isAlive then
            return a.isAlive
        end
        
        -- Then sort by best distance traveled (farther = better)
        return (a.bestDistanceTraveled or 0) > (b.bestDistanceTraveled or 0)
    end)
    
    -- Update positions
    for i, entry in ipairs(leaderboard) do
        entry.position = i
    end
    
    return leaderboard
end

-- Save current round results to daily/weekly records
function M.saveRoundResults(roundDuration, floodSpeed)
    local leaderboard = M.getCurrentRoundLeaderboard()
    local currentTime = os.time()
    
    for _, entry in ipairs(leaderboard) do
        local historicalEntry = U.deepcopy(historicalEntryTemplate)
        
        -- Copy data from current round entry
        historicalEntry.playerId = entry.playerId
        historicalEntry.name = entry.name
        historicalEntry.vehicleName = entry.vehicleName
        historicalEntry.enginePower = entry.enginePower
        historicalEntry.finalDistanceTraveled = entry.bestDistanceTraveled -- Best distance traveled
        historicalEntry.trackLength = entry.trackLength
        historicalEntry.progressPercent = entry.progressPercent
        historicalEntry.resetsUsed = entry.resetsUsed
        historicalEntry.position = entry.position
        historicalEntry.roundDuration = roundDuration or 0
        historicalEntry.timeAlive = entry.timeAlive or 0
        historicalEntry.floodSpeed = floodSpeed or 0
        historicalEntry.timestamp = currentTime
        
        -- Add to daily records
        table.insert(M.state.dailyRecords, historicalEntry)
        
        -- Add to weekly records
        table.insert(M.state.weeklyRecords, historicalEntry)
    end
    
    -- Clean old records
    cleanOldRecords()
    
    -- Save to file
    M.saveLeaderboardData()
end

-- Clear current round data
function M.clearCurrentRound()
    M.state.currentRound = {}
end

-- Get daily leaderboard (best records from today)
function M.getDailyLeaderboard()
    local bestRecords = {}
    local playerBest = {}
    
    -- Find best record for each player today (best = furthest distance traveled)
    for _, record in ipairs(M.state.dailyRecords) do
        local currentBest = playerBest[record.playerId]
        if not currentBest or (record.finalDistanceTraveled or 0) > (currentBest.finalDistanceTraveled or 0) then
            playerBest[record.playerId] = record
        end
    end
    
    -- Convert to array and sort
    for _, record in pairs(playerBest) do
        table.insert(bestRecords, record)
    end
    
    table.sort(bestRecords, function(a, b)
        return (a.finalDistanceTraveled or 0) > (b.finalDistanceTraveled or 0)
    end)
    
    -- Update positions
    for i, record in ipairs(bestRecords) do
        record.position = i
    end
    
    return bestRecords
end

-- Get weekly leaderboard (best records from this week)
function M.getWeeklyLeaderboard()
    local bestRecords = {}
    local playerBest = {}
    
    -- Find best record for each player this week (best = furthest distance traveled)
    for _, record in ipairs(M.state.weeklyRecords) do
        local currentBest = playerBest[record.playerId]
        if not currentBest or (record.finalDistanceTraveled or 0) > (currentBest.finalDistanceTraveled or 0) then
            playerBest[record.playerId] = record
        end
    end
    
    -- Convert to array and sort
    for _, record in pairs(playerBest) do
        table.insert(bestRecords, record)
    end
    
    table.sort(bestRecords, function(a, b)
        return (a.finalDistanceTraveled or 0) > (b.finalDistanceTraveled or 0)
    end)
    
    -- Update positions
    for i, record in ipairs(bestRecords) do
        record.position = i
    end
    
    return bestRecords
end

-- Send leaderboard updates to clients
function M.sendLeaderboardUpdate(targetPlayerId)
    local currentTime = os.time()
    
    -- Only send updates at specified intervals
    if currentTime - M.state.lastUpdateTime < (M.state.updateInterval / 1000) then
        return
    end
    
    local data = {
        currentRound = M.getCurrentRoundLeaderboard(),
        dailyRecords = M.getDailyLeaderboard(),
        weeklyRecords = M.getWeeklyLeaderboard(),
        timestamp = currentTime
    }
    
    local jsonData = Util.JsonEncode(data)
    
    if targetPlayerId then
        MP.TriggerClientEvent(targetPlayerId, "E_LeaderboardUpdate", jsonData)
    else
        MP.TriggerClientEvent(-1, "E_LeaderboardUpdate", jsonData)
    end
    
    M.state.lastUpdateTime = currentTime
end

-- Initialize the leaderboard system
function M.initialize()
    initializeLeaderboardData()
    print("Leaderboard system initialized")
end

-- TODO: Implement these functions when vehicle data access is available
function M.getVehicleName(vehicleConfig)
    return vehicleConfig.jbm
end

function M.getEngineKW(vehicleConfig)
    -- Stub: Extract engine power from vehicle config  
    -- This would need to access engine specifications from the vehicle data
    return 0
end

return M 