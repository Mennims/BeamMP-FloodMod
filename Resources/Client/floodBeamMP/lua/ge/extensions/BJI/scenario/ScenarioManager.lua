-- COLLISION MANAGER MODIFICATION: Minimal ScenarioManager for CollisionsManager functionality only
local M = {
    _name = "BJIScenario",
    TYPES = {},
    solo = {},
    multi = {},
    CurrentScenario = nil,
    scenarii = {},
    
    -- FLOOD MOD INTEGRATION: Add collision override system
    floodCollisionOverride = nil, -- nil = use default, otherwise use this value
}

-- FLOOD MOD INTEGRATION: Function to set collision type from flood mod
local function setFloodCollisionType(collisionType)
    -- collisionType should be one of: BJICollisions.TYPES.FORCED, DISABLED, or GHOSTS
    -- or nil to use default behavior
    M.floodCollisionOverride = collisionType
    LogInfo(svar("Flood collision type set to: {1}", { collisionType or "default" }), "BJIScenario")
end

-- COLLISION MANAGER MODIFICATION: Enhanced to support flood mod collision control
local function getCollisionsType(ctxt)
    -- FLOOD MOD INTEGRATION: Check if flood mod has overridden collision type
    if M.floodCollisionOverride ~= nil then
        return M.floodCollisionOverride
    end
    
    -- For minimal CollisionsManager functionality, default to GHOSTS type
    -- This allows collision ghosting behavior to work
    return BJICollisions.TYPES.GHOSTS
end

-- COLLISION MANAGER MODIFICATION: Minimal initialization
local function init()
    M.TYPES.FREEROAM = "FREEROAM"
    M.CurrentScenario = M.TYPES.FREEROAM
    LogInfo("Minimal ScenarioManager initialized for CollisionsManager", "BJIScenario")
end

-- Initialize immediately for CollisionsManager
init()

-- COLLISION MANAGER MODIFICATION: Only expose the getCollisionsType function needed by CollisionsManager
M.getCollisionsType = getCollisionsType

-- FLOOD MOD INTEGRATION: Expose collision control function
M.setFloodCollisionType = setFloodCollisionType

-- COMMENTED OUT: All other scenario functionality not needed for CollisionsManager
-- Uncomment sections below if you need additional scenario functionality later

--[[
local function _curr()
    return M.scenarii[M.CurrentScenario] or {}
end

local function registerSoloScenario(type, module)
    M.TYPES[type] = type
    M.scenarii[type] = module
    if not tincludes(M.solo, type, true) then
        table.insert(M.solo, type)
    end
end

local function registerMultiScenario(type, module)
    M.TYPES[type] = type
    M.scenarii[type] = module
    if not tincludes(M.multi, type, true) then
        table.insert(M.multi, type)
    end
end

-- Full scenario system initialization
local function init()
    M.TYPES.FREEROAM = "FREEROAM"
    M.scenarii[M.TYPES.FREEROAM] = require("ge/extensions/BJI/scenario/ScenarioFreeroam")

    registerSoloScenario("VEHICLE_DELIVERY", require("ge/extensions/BJI/scenario/ScenarioVehicleDelivery"))
    registerSoloScenario("PACKAGE_DELIVERY", require("ge/extensions/BJI/scenario/ScenarioPackageDelivery"))
    registerSoloScenario("BUS_MISSION", require("ge/extensions/BJI/scenario/ScenarioBusMission"))
    registerSoloScenario("RACE_SOLO", require("ge/extensions/BJI/scenario/ScenarioRaceSolo"))

    registerMultiScenario("RACE_MULTI", require("ge/extensions/BJI/scenario/ScenarioRaceMulti"))
    registerMultiScenario("SPEED", require("ge/extensions/BJI/scenario/ScenarioSpeed"))
    registerSoloScenario("DELIVERY_MULTI", require("ge/extensions/BJI/scenario/ScenarioDeliveryMulti"))
    registerMultiScenario("HUNTER", require("ge/extensions/BJI/scenario/ScenarioHunter"))
    registerMultiScenario("DERBY", require("ge/extensions/BJI/scenario/ScenarioDerby"))
    --registerSoloScenario("TAG_DUO", require("ge/extensions/BJI/scenario/ScenarioTagDuo"))

    M.CurrentScenario = M.TYPES.FREEROAM
    if _curr().onLoad then
        _curr().onLoad()
    end
end
BJIAsync.task(
    function()
        return BJICache.areBaseCachesFirstLoaded() and
            BJICache.isFirstLoaded(BJICache.CACHES.MAP) and
            BJICache.isFirstLoaded(BJICache.CACHES.BJC)
    end,
    init, "BJIScenarioInit"
)

-- All the vehicle event handlers and other functionality...
-- [Previous implementation would go here]
--]]

RegisterBJIManager(M)
return M
