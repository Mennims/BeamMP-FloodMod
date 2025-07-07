local M = {}
local U = require("libs/utils")

-- File paths
local LEADERBOARD_DATA_FILE = "Resources/Server/Flood/data/leaderboard.json"

-- Leaderboard state
M.state = {
    currentRound = {},
    dailyRecords = {},
    weeklyRecords = {},
    lastCurrentRoundUpdate = 0,
    lastFullUpdate = 0,
    currentRoundInterval = 250, -- Send current round updates every 250ms during race
    fullLeaderboardInterval = 5000, -- Send full leaderboard every 5 seconds
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
    timeAlive = 0, -- Time alive in milliseconds
    spawnTime = 0, -- When the player spawned/started this round (in milliseconds)
    deathTime = 0, -- When the player died (0 if still alive, in milliseconds)
    lastUpdate = 0, -- Timestamp of last update
    hasWon = false, -- Whether this player won the race (first to finish)
    hasFinished = false, -- Whether this player finished the race (completed track)
    finishTime = 0 -- When the player finished (0 if not finished)
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
    roundDuration = 0, -- Duration of the round in milliseconds
    timeAlive = 0, -- Time the player was alive in milliseconds
    timestamp = 0, -- When the round ended
    position = 1, -- Final position in that round
    hasWon = false, -- Whether this player won the race (first to finish)
    hasFinished = false, -- Whether this player finished the race (completed track)
    finishTime = 0 -- When the player finished (0 if not finished)
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
    local currentTime = U.getCurrentTimeMs()
    local dailyThreshold = currentTime - (24 * 60 * 60 * 1000) -- 24 hours in milliseconds
    local weeklyThreshold = currentTime - (7 * 24 * 60 * 60 * 1000) -- 7 days in milliseconds
    
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

-- Compare two records for sorting (score-based ranking)
local function compareRecords(a, b)
    local scoreA = M.calculateScore(a)
    local scoreB = M.calculateScore(b)
    
    -- If scores are truly identical, use timestamp as tiebreaker (earlier record wins)
    if scoreA == scoreB then
        return (a.timestamp or 0) < (b.timestamp or 0)
    end
    
    return scoreA > scoreB
end

-- Get track length from map config
local function getTrackLength(mapConfig)
    return mapConfig.totalDistance or 13099 -- Default fallback track length
end

-- Add or update a player in the current round leaderboard
function M.updateCurrentRoundPlayer(playerId, playerState, clientState, mapConfig, roundStartTime)
    if not playerId or not playerState then return end
    
    -- Get current time with millisecond precision
    local currentTime = U.getCurrentTimeMs()
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
    
    -- Update winner/finish states
    if playerState.hasWon ~= nil then
        entry.hasWon = playerState.hasWon
    end
    if playerState.hasFinished ~= nil then
        entry.hasFinished = playerState.hasFinished
    end
    if playerState.finishTime and playerState.finishTime > 0 and entry.spawnTime and entry.spawnTime > 0 then
        -- Convert absolute finish time to duration (finish time - spawn time)
        entry.finishTime = playerState.finishTime - entry.spawnTime
    end
    
    -- Handle death time tracking with millisecond precision
    if wasAlive and not isAlive and entry.deathTime == 0 then
        entry.deathTime = playerState.deathTime or currentTime
    end
    
    -- Calculate time alive in milliseconds
    if isAlive then
        entry.timeAlive = currentTime - entry.spawnTime
    else
        -- Player is dead, use death time if available, otherwise current time
        local endTime = entry.deathTime > 0 and entry.deathTime or currentTime
        entry.timeAlive = endTime - entry.spawnTime
    end
    
    -- Update distance info
    if clientState and type(clientState) == "table" and clientState.roadDistance then
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
    if playerState.vehicle and playerState.vehicle.config then
        entry.vehicleName = M.getVehicleName(playerState.vehicle.config)
    else
        entry.vehicleName = "Unknown"
    end
    
    if playerState.vehiclePower then
        entry.enginePower = M.getEngineKW(playerState.vehiclePower)
    else
        entry.enginePower = 0
    end
end

-- Remove a player from current round leaderboard
function M.removeCurrentRoundPlayer(playerId)
    M.state.currentRound[playerId] = nil
end

-- Get current round leaderboard sorted by distance traveled
function M.getCurrentRoundLeaderboard()
    local leaderboard = {}
    
    for playerId, entry in pairs(M.state.currentRound) do
        table.insert(leaderboard, entry)
    end
    
    -- Sort by winner status, then finish status, then distance traveled
    table.sort(leaderboard, function(a, b)
        -- Winner always ranks first
        if a.hasWon and not b.hasWon then
            return true
        elseif not a.hasWon and b.hasWon then
            return false
        end
        
        -- If both or neither are winners, check finish status
        if a.hasFinished and not b.hasFinished then
            return true
        elseif not a.hasFinished and b.hasFinished then
            return false
        end
        
        -- If both have same finish status, sort by distance traveled
        local distanceA = a.bestDistanceTraveled or 0
        local distanceB = b.bestDistanceTraveled or 0
        
        -- If both finished, sort by finish time (earlier = better)
        if a.hasFinished and b.hasFinished and a.finishTime > 0 and b.finishTime > 0 then
            return a.finishTime < b.finishTime
        end
        
        -- Otherwise sort by distance (higher = better)
        return distanceA > distanceB
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
    -- Use millisecond precision for timestamp
    local currentTime = U.getCurrentTimeMs()
    
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
        historicalEntry.hasWon = entry.hasWon or false
        historicalEntry.hasFinished = entry.hasFinished or false
        -- Copy finish time (already a duration in current round entries)
        if entry.finishTime and entry.finishTime > 0 then
            historicalEntry.finishTime = entry.finishTime
        else
            historicalEntry.finishTime = 0
        end
        
        -- Add to daily records
        table.insert(M.state.dailyRecords, historicalEntry)
        
        -- Add to weekly records
        table.insert(M.state.weeklyRecords, historicalEntry)
    end
    
    -- Clean old records
    -- cleanOldRecords()
    
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
    
    -- Find best record for each player today (best = highest composite score)
    for _, record in ipairs(M.state.dailyRecords) do
        local currentBest = playerBest[record.name]
        if not currentBest then
            playerBest[record.name] = record
        else
            local currentScore = M.calculateScore(currentBest)
            local newScore = M.calculateScore(record)
            if newScore > currentScore then
                playerBest[record.name] = record
            end
        end
    end
    
    -- Convert to array and sort by composite score
    for _, record in pairs(playerBest) do
        table.insert(bestRecords, record)
    end
    
    table.sort(bestRecords, compareRecords)
    
    -- Create copies with updated positions to avoid mutating original records
    local rankedRecords = {}
    for i, record in ipairs(bestRecords) do
        local rankedRecord = U.deepcopy(record)
        rankedRecord.position = i
        table.insert(rankedRecords, rankedRecord)
    end
    
    return rankedRecords
end

-- Get weekly leaderboard (best records from this week)
function M.getWeeklyLeaderboard()
    local bestRecords = {}
    local playerBest = {}
    
    -- Find best record for each player this week (best = highest composite score)
    for _, record in ipairs(M.state.weeklyRecords) do
        local currentBest = playerBest[record.name]
        if not currentBest then
            playerBest[record.name] = record
        else
            local currentScore = M.calculateScore(currentBest)
            local newScore = M.calculateScore(record)
            if newScore > currentScore then
                playerBest[record.name] = record
            end
        end
    end
    
    -- Convert to array and sort by composite score
    for _, record in pairs(playerBest) do
        table.insert(bestRecords, record)
    end
    
    table.sort(bestRecords, compareRecords)
    
    -- Create copies with updated positions to avoid mutating original records
    local rankedRecords = {}
    for i, record in ipairs(bestRecords) do
        local rankedRecord = U.deepcopy(record)
        rankedRecord.position = i
        table.insert(rankedRecords, rankedRecord)
    end
    
    return rankedRecords
end

-- Send full leaderboard updates to clients (all tabs)
function M.sendFullLeaderboardUpdate(targetPlayerId)
    local currentTime = U.getCurrentTimeMs()
    
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
    
    M.state.lastFullUpdate = currentTime
end

-- Send only current round leaderboard updates (fast updates during race)
function M.sendCurrentRoundUpdate(targetPlayerId)
    local currentTime = os.time() * 1000 -- Use milliseconds for precise timing
    
    local data = {
        currentRound = M.getCurrentRoundLeaderboard(),
        timestamp = currentTime,
        currentRoundOnly = true -- Flag to indicate this is current round only
    }
    
    local jsonData = Util.JsonEncode(data)
    
    if targetPlayerId then
        MP.TriggerClientEvent(targetPlayerId, "E_LeaderboardCurrentRoundUpdate", jsonData)
    else
        MP.TriggerClientEvent(-1, "E_LeaderboardCurrentRoundUpdate", jsonData)
    end
    
    M.state.lastCurrentRoundUpdate = currentTime
end

-- Legacy function for compatibility - sends full update
function M.sendLeaderboardUpdate(targetPlayerId)
    M.sendFullLeaderboardUpdate(targetPlayerId)
end

-- Broadcast current round updates (250ms during race)
function M.broadcastCurrentRoundUpdate()
    local currentTime = os.time() * 1000
    if currentTime - M.state.lastCurrentRoundUpdate >= M.state.currentRoundInterval then
        M.sendCurrentRoundUpdate()
    end
end

-- Broadcast full leaderboard updates (5 seconds always)
function M.broadcastFullLeaderboardUpdate()
    local currentTime = os.time() * 1000
    if currentTime - M.state.lastFullUpdate >= M.state.fullLeaderboardInterval then
        M.sendFullLeaderboardUpdate()
    end
end

-- Calculate composite score for leaderboard ranking
-- Takes into account distance, completion time, and flood speed
function M.calculateScore(entry, roundFloodSpeed)
    local distance = entry.bestDistanceTraveled or entry.finalDistanceTraveled or 0
    local trackLength = entry.trackLength or 13099
    local floodSpeed = entry.floodSpeed or roundFloodSpeed
    
    -- For finished players, use finish time; for others, use time alive
    local timeForScoring = entry.timeAlive or 0
    if entry.hasFinished and entry.finishTime and entry.finishTime > 0 then
        timeForScoring = entry.finishTime
    end
    
    -- Convert milliseconds to seconds for scoring calculations
    local timeForScoringSeconds = timeForScoring / 1000
    
    -- Normalize values to 0-1 scale for fair weighting
    local distanceScore = math.min(1.0, distance / trackLength) -- 0-1 based on track completion
    
    -- Time score: LOWER time = HIGHER score (faster completion is better)
    -- Inverted scoring: 1.0 for instant completion, decreasing as time increases
    local maxTime = 900 -- 15 minutes reference time in seconds
    local timeScore = 1.0 - math.min(1.0, timeForScoringSeconds / maxTime) -- Inverted: lower time = higher score
    
    local floodSpeedMultiplier = math.max(0.5, math.min(2.0, floodSpeed / 2.2)) -- 0.5-2.0x based on flood speed (2.2 m/s reference)
    
    -- Weighted scoring formula
    -- Distance: 40% weight (primary factor)
    -- Time: 35% weight (speed bonus - lower time = higher score)
    -- Flood speed: 25% weight (difficulty multiplier)
    local baseScore = (distanceScore * 0.60) + (timeScore * 0.35)
    local finalScore = baseScore * (1.0 + (floodSpeedMultiplier - 1.0) * 0.25)
    
    -- Bonus for completing the track
    if distance >= trackLength * 0.95 then -- 95% completion bonus
        finalScore = finalScore * 1.1
    end
    
    -- Penalty for early death (if died within first 30 seconds)
    if timeForScoringSeconds < 30 and distance < trackLength * 0.1 then -- Only penalize if they didn't get far
        finalScore = finalScore * 0.8
    end

    -- Prevent players from cheating the leaderboard by using a higher flood speed
    if floodSpeed > 40 or distance <= 0 then
        finalScore = 0
    end

    -- Prevent players from cheating the leaderboard by teleporting to the end
    if timeForScoringSeconds < 240 and distance > trackLength * 0.7 then
        finalScore = 0
    end
    
    return finalScore
end

-- Migrate old data from seconds to milliseconds
function M.migrateToMilliseconds()
    local migrationCount = 0
    
    -- Migrate daily records
    for _, record in ipairs(M.state.dailyRecords) do
        -- Check if record needs migration (values under 1000000 are likely in seconds)
        if record.timeAlive and record.timeAlive < 1000000 then
            record.timeAlive = record.timeAlive * 1000
            migrationCount = migrationCount + 1
        end
        if record.finishTime and record.finishTime < 1000000 and record.finishTime > 0 then
            record.finishTime = record.finishTime * 1000
        end
        if record.roundDuration and record.roundDuration < 1000000 then
            record.roundDuration = record.roundDuration * 1000
        end
        -- Timestamps should remain as they are (already in milliseconds from os.time() * 1000)
    end
    
    -- Migrate weekly records
    for _, record in ipairs(M.state.weeklyRecords) do
        -- Check if record needs migration (values under 1000000 are likely in seconds)
        if record.timeAlive and record.timeAlive < 1000000 then
            record.timeAlive = record.timeAlive * 1000
            migrationCount = migrationCount + 1
        end
        if record.finishTime and record.finishTime < 1000000 and record.finishTime > 0 then
            record.finishTime = record.finishTime * 1000
        end
        if record.roundDuration and record.roundDuration < 1000000 then
            record.roundDuration = record.roundDuration * 1000
        end
    end
    
    if migrationCount > 0 then
        print("Migrated " .. migrationCount .. " records from seconds to milliseconds")
        M.saveLeaderboardData()
        return true
    else
        print("No records needed migration to milliseconds")
        return false
    end
end

-- Initialize the leaderboard system
function M.initialize()
    initializeLeaderboardData()
    -- M.migrateToMilliseconds()
    print("Leaderboard system initialized")
end

-- TODO: Implement these functions when vehicle data access is available
function M.getVehicleName(vehicleConfig)
    if not vehicleConfig or not vehicleConfig.jbm then
        return "Unknown"
    end
    return vehicleConfig.jbm
end

function M.getEngineKW(vehiclePowerHp)
    if not vehiclePowerHp or type(vehiclePowerHp) ~= "number" then
        return 0
    end
    return math.floor(vehiclePowerHp * 0.7457 + 0.5)
end

return M 