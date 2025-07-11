local MH = require "ge.extensions.multiplayerHelper"

local M = {}

local allWater = {}
local ocean = nil
local calledOnInit = false -- For calling "E_OnInitialize" only once when BeamMP's experimental "Disable lua reloading when bla bla bla" is enabled

M.collisionState = {
    isRoundActive = false,
    disableCollisionsOnReset = true -- Set to true to disable collisions when someone resets during round
}

M.setCollisionType = function(collisionType)
    -- Ensure BJI extension is loaded
    if not extensions.BJI then
        log("W", "floodBeamMP", "BJI extension not loaded, cannot control collisions")
        return false
    end
    
    -- Access the scenario manager and set collision type
    if BJIScenario and BJIScenario.setFloodCollisionType then
        BJIScenario.setFloodCollisionType(collisionType)
        log("I", "floodBeamMP", "Collision type set to: " .. tostring(collisionType))
        return true
    else
        log("W", "floodBeamMP", "BJIScenario not available, cannot control collisions")
        return false
    end
end

M.enableCollisions = function()
    return M.setCollisionType(1) -- BJICollisions.TYPES.FORCED
end

M.disableCollisions = function()
    return M.setCollisionType(2) -- BJICollisions.TYPES.DISABLED
end

M.enableGhostCollisions = function()
    return M.setCollisionType(3) -- BJICollisions.TYPES.GHOSTS
end

M.resetToDefaultCollisions = function()
    return M.setCollisionType(nil) -- Use default behavior (GHOSTS)
end

local function findObject(objectName, className)
    local obj = scenetree.findObject(objectName)
    if obj then return obj end
    if not className then return nil end

    local objects = scenetree.findClassObjects(className)
    for _, name in pairs(objects) do
        local object = scenetree.findObject(name)
        if string.find(name, objectName) then return object end
    end

    return
end

local function tableToMatrix(tbl)
    local mat = MatrixF(true)
    mat:setColumn(0, tbl.c0)
    mat:setColumn(1, tbl.c1)
    mat:setColumn(2, tbl.c2)
    mat:setColumn(3, tbl.c3)
    return mat
end

local hiddenWater = {}

local function getWaterLevel()
    if not ocean then return nil end
    return ocean.position:getColumn(3).z
end

local function getAllWater()
    local water = {}
    local toSearch = {
        "River",
        "WaterBlock"
    }

    for _, name in pairs(toSearch) do
        local objects = scenetree.findClassObjects(name)
        for _, id in pairs(objects) do
            if not tonumber(id) then
                local source = scenetree.findObject(id)
                if source then
                    table.insert(water, source)
                end
            else
                local source = scenetree.findObjectById(tonumber(id))
                if source then
                    table.insert(water, source)
                end
            end
        end
    end

    return water
end

local function handleWaterSources()
    local height = getWaterLevel()

    for id, water in pairs(allWater) do
        local waterHeight = water.position:getColumn(3).z
        if M.hideCoveredWater and not hiddenWater[id] and waterHeight < height then
            water.isRenderEnabled = false
            hiddenWater[id] = true
        elseif waterHeight > height and hiddenWater[id] then
            water.isRenderEnabled = true
            hiddenWater[id] = false
        elseif not M.hideCoveredWater and hiddenWater[id] then
            water.isRenderEnabled = true
            hiddenWater[id] = false
        end
    end
end

-- State management
M.state = {
  roadDistance = nil,
  lastSentTime = 0,
  sendInterval = 250, -- ms between updates to server
  destinationPos = vec3(634.2406616, 3175.344971, 1227.2677), -- Default destination
  roundStartTime = 0, -- Track when current round started
  vehiclePower = nil, -- Track vehicle engine power
  floodSpeed = 0, -- Track current flood speed in m/s
  floodState = {
    status = "stopped",
    speed = 0,
    level = 0,
    lastUpdate = 0
  }
}

M.updateRoadDistance = function()
    if (M.state.destinationPos == nil) then
        return
    end

    local distance = MH.getRoadDistanceRemaining(M.state.destinationPos)
    
    -- Validate distance value
    if distance and type(distance) == "number" and distance == distance and distance ~= math.huge and distance ~= -math.huge then
        M.state.roadDistance = distance
    else
        -- Keep previous valid value or set to nil if invalid
        if distance then
            log("W", "updateRoadDistance", "Invalid distance value: " .. tostring(distance))
        end
        M.state.roadDistance = nil
    end
    
    return M.state.roadDistance
end

M.getVehiclePower = function()
    local vehicle = be:getPlayerVehicle(0)
    if not vehicle then return nil end
    
    -- Execute vehicle Lua that calls back to game engine Lua to set the power
    vehicle:queueLuaCommand([[
        if powertrain and powertrain.getDevice then
            local engine = powertrain.getDevice("mainEngine")
            if engine and engine.torqueData and engine.torqueData.maxPower then
                local power = math.floor(engine.torqueData.maxPower + 0.5)
                obj:queueGameEngineLua("extensions.floodBeamMP.setVehiclePower(" .. power .. ")")
            end
        end
    ]])
end

-- Function to be called from vehicle Lua via queueGameEngineLua
M.setVehiclePower = function(power)
    -- Validate power value
    if power and type(power) == "number" and power == power and power ~= math.huge and power ~= -math.huge and power > 0 then
        M.state.vehiclePower = power
    else
        if power then
            log("W", "setVehiclePower", "Invalid power value: " .. tostring(power))
        end
        -- Keep previous valid value or set to nil if invalid
        M.state.vehiclePower = nil
    end
end

M.sendStateToServer = function()
    -- Validate values before sending
    local roadDistance = M.state.roadDistance
    local vehiclePower = M.state.vehiclePower
    
    -- Ensure values are valid numbers or nil
    if roadDistance and (type(roadDistance) ~= "number" or roadDistance ~= roadDistance) then -- NaN check
        roadDistance = nil
    end
    
    if vehiclePower and (type(vehiclePower) ~= "number" or vehiclePower ~= vehiclePower) then -- NaN check
        vehiclePower = nil
    end
    
    local stateToSend = {
        roadDistance = roadDistance,
        vehiclePower = vehiclePower
    }
    
    -- Safely encode JSON
    local success, jsonString = pcall(jsonEncode, stateToSend)
    if success and jsonString then
        TriggerServerEvent("E_ClientStateUpdate", jsonString)
    else
        log("W", "sendStateToServer", "Failed to encode state: " .. tostring(jsonString))
    end
end

AddEventHandler("E_OnPlayerLoaded", function()
    allWater = getAllWater()
    ocean = findObject("Ocean", "WaterPlane")

    if calledOnInit then return end
    TriggerServerEvent("E_OnInitiliaze", tostring(getWaterLevel()))
    calledOnInit = true
end)

AddEventHandler("E_SetWaterLevel", function(level)
    level = tonumber(level) or nil
    if not level then log("W", "setWaterLevel", "level is nil") return end
    if not ocean then log("W", "setWaterLevel", "ocean is nil") return end
    local c3 = ocean.position:getColumn(3)
    ocean.position = tableToMatrix({
        c0 = ocean.position:getColumn(0),
        c1 = ocean.position:getColumn(1),
        c2 = ocean.position:getColumn(2),
        c3 = vec3(c3.x, c3.y, level)
    })

    handleWaterSources() -- Hides/Shows water sources depending on the ocean level
end)

AddEventHandler("E_ResetVehicle", function(args)
    log("W", "E_ResetVehicle", "Resetting vehicle")

    MH.resetVehicle()
end)

AddEventHandler("E_ResetVehicleToPos", function(destinationPos)
    destinationPos = jsonDecode(destinationPos)

    log("W", "E_ResetVehicleToPos", "Resetting vehicle to position")

    if destinationPos then
        MH.resetVehicleToPosRot(destinationPos.pos, destinationPos.rot)
    end
end)

AddEventHandler("E_SetVehicleFreeze", function(freeze)
    freeze = MH.isTrue(freeze)

    if freeze then
        log("W", "E_SetVehicleFreeze", "Freezing vehicle")
        MH.setVehicleFreeze(true)
    else
        log("W", "E_SetVehicleFreeze", "Unfreezing vehicle")
        MH.setVehicleFreeze(false)
    end
end)

AddEventHandler("E_ResetToRoad", function(destinationPosJson)
    log("W", "E_ResetToRoad", "Resetting vehicle to road")

    local destinationPos = jsonDecode(destinationPosJson)

    MH.teleportVehicleToLastRoad(true, destinationPos)
end)

AddEventHandler("E_SetVehicleRecoveryEnabled", function(enabled)
    enabled = MH.isTrue(enabled)

    if enabled then
        log("W", "E_SetVehicleRecoveryEnabled", "Enabling vehicle recovery")
    else
        log("W", "E_SetVehicleRecoveryEnabled", "Disabling vehicle recovery")
    end

    MH.setVehicleRecoveryEnabled(enabled)
end)

AddEventHandler("E_SetDynamicCollisionEnabled", function(enabled)
    enabled = MH.isTrue(enabled)

    if enabled then
        log("W", "E_SetDynamicCollisionEnabled", "Enabling dynamic collision")
    else
        log("W", "E_SetDynamicCollisionEnabled", "Disabling dynamic collision")
    end

    MH.setDynamicCollisionEnabled(enabled)
end)

AddEventHandler("E_EnterVehicle", function(vehicleId)
    vehicleId = tonumber(vehicleId)

    if vehicleId then
        log("W", "E_EnterVehicle", "Entering vehicle " .. vehicleId)
        MH.enterVehicle(vehicleId)
    else
        log("W", "E_EnterVehicle", "Invalid vehicle id")
    end
end)

AddEventHandler("E_SpawnDefaultVehicle", function()
    log("W", "E_SpawnDefaultVehicle", "Spawning default vehicle")
    MH.spawnDefaultVehicle()
end)

AddEventHandler("E_PlayCountdown", function()
    log("W", "E_PlayCountdown", "Playing countdown")
    MH.playCountdown()
end)

AddEventHandler("E_SetUiLayout", function(layout)
    if layout then
        log("W", "E_SetUiLayout", "Setting ui layout to " .. layout)
        MH.setUiLayout(layout)
    end
end)

AddEventHandler("E_SetRainVolume", function(volume)
    local volume = tonumber(volume) or 0
    if not volume then
        log("W", "E_SetRainVolume", "Invalid data: " .. tostring(data))
        return
    end

    local rainObj = findObject("rain_coverage", "Precipitation")
    if not rainObj then
        log("W", "E_SetRainVolume", "rain_coverage not found")
        return
    end

    local soundObj = findObject("rain_sound")
    if soundObj then
        soundObj:delete()
    end

    if volume == -1 then -- Automatic
        volume = rainObj.numDrops / 100
    end

    soundObj = createObject("SFXEmitter")
    soundObj.scale = Point3F(100, 100, 100)
    soundObj.fileName = String('/art/sound/environment/amb_rain_medium.ogg')
    soundObj.playOnAdd = true
    soundObj.isLooping = true
    soundObj.volume = volume
    soundObj.isStreaming = true
    soundObj.is3D = false
    soundObj:registerObject('rain_sound')
end)

AddEventHandler("E_SetRainAmount", function(amount)
    amount = tonumber(amount) or 0
    local rainObj = findObject("rain_coverage", "Precipitation")
    if not rainObj then -- Create the rain object
        rainObj = createObject("Precipitation")
        rainObj.dataBlock = scenetree.findObject("rain_medium")
        rainObj.splashSize = 0
        rainObj.splashMS = 0
        rainObj.animateSplashes = 0
        rainObj.boxWidth = 16.0
        rainObj.boxHeight = 10.0
        rainObj.dropSize = 1.0
        rainObj.doCollision = true
        rainObj.hitVehicles = true
        rainObj.rotateWithCamVel = true
        rainObj.followCam = true
        rainObj.useWind = true
        rainObj.minSpeed = 0.4
        rainObj.maxSpeed = 0.5
        rainObj.minMass = 4
        rainObj.masMass = 5
        rainObj:registerObject('rain_coverage')
    end

    rainObj.numDrops = amount
end)

AddEventHandler("E_SetDestinationPos", function(posJson)
    local pos = jsonDecode(posJson)
    if pos and pos.x and pos.y and pos.z then
        M.state.destinationPos = vec3(pos.x, pos.y, pos.z)
        log("I", "floodBeamMP", "Destination position updated")
    else
        log("W", "floodBeamMP", "Invalid destination position received")
    end
end)

AddEventHandler("E_LeaderboardUpdate", function(leaderboardData)
    guihooks.trigger('LeaderboardUpdate', leaderboardData)
end)

AddEventHandler("E_LeaderboardCurrentRoundUpdate", function(leaderboardData)
    guihooks.trigger('LeaderboardCurrentRoundUpdate', leaderboardData)
end)

AddEventHandler("E_RoundStarted", function(startTimeStr)
    M.state.roundStartTime = tonumber(startTimeStr)
    log("I", "floodBeamMP", "Round started at: " .. M.state.roundStartTime)
    
    M.collisionState.isRoundActive = true
    
    guihooks.trigger('RoundStarted', M.state.roundStartTime)
end)

AddEventHandler("E_RoundEnded", function(endTimeStr)
    local endTime = tonumber(endTimeStr)
    log("I", "floodBeamMP", "Round ended at: " .. endTime)
    
    
    guihooks.trigger('RoundEnded', endTime)
end)

AddEventHandler("E_FloodStateUpdate", function(floodStateJson)
    local success, floodState = pcall(jsonDecode, floodStateJson)
    if success and floodState then
        M.state.floodState = floodState
        -- Also update the legacy floodSpeed for backward compatibility
        M.state.floodSpeed = floodState.speed or 0
        
        -- Trigger UI update
        guihooks.trigger('FloodStateUpdate', floodState)
        
        log("I", "floodBeamMP", "Flood state updated: " .. (floodState.status or "unknown") .. 
            " | Speed: " .. (floodState.speed or 0) .. "m/s")
    else
        log("W", "floodBeamMP", "Failed to decode flood state: " .. tostring(floodStateJson))
    end
end)

AddEventHandler("E_PlayerWon", function(finishTimeStr)
    local finishTime = tonumber(finishTimeStr)
    log("I", "floodBeamMP", "Player won at: " .. finishTime)
    
    -- Send win event to UI to stop timer (as milliseconds)
    guihooks.trigger('PlayerWon', finishTime)
end)

AddEventHandler("E_PlayerFinished", function(finishDataJson)
    local finishData = jsonDecode(finishDataJson)
    if finishData then
        log("I", "floodBeamMP", "Player finished: " .. (finishData.name or "Unknown"))
        
        -- Send finish event to UI
        guihooks.trigger('PlayerFinished', finishData)
    end
end)

AddEventHandler("E_SetCollisionType", function(collisionTypeStr)
    local collisionType = tonumber(collisionTypeStr)
    if collisionType then
        M.setCollisionType(collisionType)
    else
        log("W", "floodBeamMP", "Invalid collision type received: " .. tostring(collisionTypeStr))
    end
end)

AddEventHandler("E_EnableCollisions", function()
    M.enableCollisions()
end)

AddEventHandler("E_DisableCollisions", function()
    M.disableCollisions()
end)

AddEventHandler("E_EnableGhostCollisions", function()
    M.enableGhostCollisions()
end)

-- Hooks

function trackVehReset()
    log("W", "E_TrackVehReset", "Tracking vehicle reset")
    TriggerServerEvent("E_RequestResetToRoad", "")
end

M.trackVehReset = trackVehReset

function onUpdate(dtReal, dtSim, dtRaw)
    -- Convert dtSim to milliseconds
    local dtMs = dtSim * 1000
    
    MH.onUpdate(dtSim, dtRaw)
    
    M.updateRoadDistance()
    
    -- Check for vehicle power periodically (less frequently than road distance)
    if M.state.lastSentTime % 1000 < dtMs then -- Every ~1 second
        M.getVehiclePower()
    end
    
    M.state.lastSentTime = M.state.lastSentTime + dtMs
    if M.state.lastSentTime >= M.state.sendInterval then
        M.sendStateToServer()
        M.state.lastSentTime = M.state.lastSentTime - M.state.sendInterval
    end
end

M.hideCoveredWater = hideCoveredWater
M.onUpdate = onUpdate

return M