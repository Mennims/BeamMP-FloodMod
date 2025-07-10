-- COLLISION MANAGER MODIFICATION: Minimal VehicleManager for CollisionsManager functionality only
local M = {
    _name = "BJIVeh",
    -- COMMENTED OUT: Base functions not needed for CollisionsManager
    -- baseFunctions = {},
}

-- COLLISION MANAGER MODIFICATION: Core functions needed by CollisionsManager

-- Function to initialize current player ID from multiplayer data
local function initializeCurrentPlayerID()
    if not MPVehicleGE then return end
    
    -- Try to get player ID from any local vehicle
    local mpVehs = MPVehicleGE.getVehicles()
    for _, v in pairs(mpVehs) do
        if v.isLocal and v.ownerID then
            local playerID = tonumber(v.ownerID)
            if playerID and playerID ~= BJIContext.User.playerID then
                BJIContext.User.playerID = playerID
                LogInfo(svar("Initialized player ID: {1}", { playerID }), "BJIVeh")
                return playerID
        end
    end
end

    -- If no local vehicles found, player ID remains 0 (default)
    return BJIContext.User.playerID
end

local function getMPVehicles()
    local vehs = {}
    if not MPVehicleGE then return vehs end
    local mpVehs = MPVehicleGE.getVehicles()
    for _, v in pairs(mpVehs) do
        table.insert(vehs, {
            gameVehicleID = v.gameVehicleID,
            isDeleted = v.isDeleted,
            isLocal = v.isLocal,
            isSpawned = v.isSpawned,
            jbeam = v.jbeam,
            ownerID = v.ownerID,
            ownerName = v.ownerName,
            remoteVehID = v.remoteVehID,
            serverVehicleID = v.serverVehicleID,
            serverVehicleString = v.serverVehicleString,
            spectators = v.spectators,
        })
    end
    return vehs
end

local function getCurrentVehicle()
    return be:getPlayerVehicle(0)
end

local function getVehicleObject(gameVehID)
    gameVehID = tonumber(gameVehID)
    if not gameVehID then
        return
    end
    local veh = be:getObjectByID(gameVehID)
    if not veh then
        local vehs = M.getMPVehicles()
        for _, v in pairs(vehs) do
            if v.remoteVehID == gameVehID then
                return be:getObjectByID(v.gameVehicleID)
            end
        end
    end
    return veh or nil
end

local function getRemoteVehID(gameVehID)
    local vehs = M.getMPVehicles()
    for _, v in pairs(vehs) do
        if v.gameVehicleID == gameVehID and v.remoteVehID ~= -1 then
            return v.remoteVehID
        end
    end
    return nil
end

local function getGameVehIDByRemoteVehID(remoteVehID)
    local vehs = M.getMPVehicles()
    for _, v in pairs(vehs) do
        if v.remoteVehID == remoteVehID then
            return v.gameVehicleID
        end
    end
    return nil
end

local function getVehOwnerID(gameVehID)
    local vehs = M.getMPVehicles()
    for _, v in pairs(vehs) do
        if v.gameVehicleID == gameVehID or v.remoteVehID == gameVehID then
            return tonumber(v.ownerID)
        end
    end
    return nil
end

-- COLLISION MANAGER FIX: Enhanced isVehicleOwn with fallback methods
local function isVehicleOwn(gameVehID)
    -- Initialize player ID if not already done
    if BJIContext.User.playerID == 0 then
        initializeCurrentPlayerID()
    end
    
    -- Method 1: Check using player ID (primary method)
    local ownerID = getVehOwnerID(gameVehID)
    if ownerID and BJIContext.User.playerID ~= 0 then
        return ownerID == BJIContext.User.playerID
    end
    
    -- Method 2: Fallback - check if vehicle is local (for BeamMP)
    local vehs = M.getMPVehicles()
    for _, v in pairs(vehs) do
        if v.gameVehicleID == gameVehID then
            return v.isLocal == true
    end
end

    -- Method 3: Final fallback - check if it's the current player vehicle
    local currentVeh = getCurrentVehicle()
    if currentVeh then
        return currentVeh:getID() == gameVehID
    end
    
    return false
end

local function getPositionRotation(veh)
    if not veh then return end
    local pos = veh:getPosition()
    local rot = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())
    return {
        pos = vec3(pos),
        rot = quat(rot)
    }
end

local function isUnicycle(gameVehID)
    local veh = getVehicleObject(gameVehID)
    if not veh then return false end
    return veh.jbeam and veh.jbeam == "unicycle" or false
end

-- COLLISION MANAGER MODIFICATION: Auto-initialize player ID on load
local function onLoad()
    -- Initialize player ID when VehicleManager loads
    BJIAsync.delayTask(function()
        initializeCurrentPlayerID()
    end, 50, "BJIVehInitPlayerID")
end

-- COLLISION MANAGER MODIFICATION: Vehicle event handlers to maintain player ID
local function onVehicleSpawned(gameVehID)
    -- Check if this might be our vehicle and update player ID if needed
    BJIAsync.delayTask(function()
        if BJIContext.User.playerID == 0 then
            initializeCurrentPlayerID()
        end
    end, 50, "BJIVehCheckPlayerIDSpawn")
end

local function onVehicleDestroyed(gameVehID)
    -- If player ID becomes invalid after vehicle destruction, reinitialize
    BJIAsync.delayTask(function()
        local currentVeh = getCurrentVehicle()
        if not currentVeh and BJIContext.User.playerID ~= 0 then
            -- Lost current vehicle, but might have others - recheck player ID
            initializeCurrentPlayerID()
        end
    end, 500, "BJIVehCheckPlayerIDDestroy")
end

-- COLLISION MANAGER MODIFICATION: Periodic verification of player ID
local function slowTick(ctxt)
    -- Periodically verify player ID is still correct (every few seconds)
    if BJIContext.User.playerID == 0 then
        initializeCurrentPlayerID()
    end
end

-- COLLISION MANAGER MODIFICATION: Only expose functions needed by CollisionsManager
M.getMPVehicles = getMPVehicles
M.getCurrentVehicle = getCurrentVehicle
M.getVehicleObject = getVehicleObject
M.getRemoteVehID = getRemoteVehID
M.getGameVehIDByRemoteVehID = getGameVehIDByRemoteVehID
M.getVehOwnerID = getVehOwnerID
M.isVehicleOwn = isVehicleOwn
M.getPositionRotation = getPositionRotation
M.isUnicycle = isUnicycle
M.initializeCurrentPlayerID = initializeCurrentPlayerID
M.onLoad = onLoad
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleDestroyed = onVehicleDestroyed
M.slowTick = slowTick

-- COMMENTED OUT: All other vehicle functionality not needed for CollisionsManager
-- Uncomment sections below if you need additional vehicle functionality later

--[[
Original VehicleManager implementation with 1200+ lines of functionality including:
- Vehicle spawning, deletion, replacement
- Vehicle configuration management
- Vehicle physics controls (freeze, engine, lights)
- Vehicle painting and customization
- Teleportation and positioning
- Energy and damage management
- And many other features...

The complete implementation can be found in the original file backup.
To restore full functionality, uncomment this section and the respective function exports at the bottom.
--]]

RegisterBJIManager(M)
return M
