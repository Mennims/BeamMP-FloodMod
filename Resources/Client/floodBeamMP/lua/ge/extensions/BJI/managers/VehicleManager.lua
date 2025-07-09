-- COLLISION MANAGER MODIFICATION: Minimal VehicleManager for CollisionsManager functionality only
local M = {
    _name = "BJIVeh",
    -- COMMENTED OUT: Base functions not needed for CollisionsManager
    -- baseFunctions = {},
}

-- COLLISION MANAGER MODIFICATION: Core functions needed by CollisionsManager

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

local function isVehicleOwn(gameVehID)
    return getVehOwnerID(gameVehID) == BJIContext.User.playerID
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
