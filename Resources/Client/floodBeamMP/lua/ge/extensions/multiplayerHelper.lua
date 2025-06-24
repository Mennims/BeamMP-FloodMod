local M = {}

-- Vehicle helpers

local function resetVehicle()
    local veh = be:getPlayerVehicle(0)
    if veh then
        veh:reset()
    end
end

local function resetVehicleToPos(pos)
    local veh = be:getPlayerVehicle(0)

    if veh and pos then
        destination = vec3(pos.x, pos.y, pos.z)
        veh:setPosition(destination)
    end
end

local function resetVehicleToPosRot(pos, rot)
    local veh = be:getPlayerVehicle(0)

    if veh and pos and rot then
        veh:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
    end
end

local function teleportVehicleToLastRoad(resetVehicle, destinationPos)
    local veh = be:getPlayerVehicle(0)

    if veh then
        local destination = nil;

        if destinationPos then
            destination = vec3(destinationPos.x, destinationPos.y, destinationPos.z)
        end

        spawn.teleportToLastRoad(veh,
            { resetVehicle = resetVehicle, destinationPos = destination })
    end
end

local function setVehicleFreeze(freeze)
    local veh = be:getPlayerVehicle(0)
    if veh then
        if freeze then
            veh:queueLuaCommand('controller.setFreeze(1)')
        else
            veh:queueLuaCommand('controller.setFreeze(0)')
        end
    end
end

local function setVehicleRecoveryEnabled(enabled)
    if enabled then
        core_recoveryPrompt.setDefaultsForFreeroam()
    else
        core_recoveryPrompt.deactivateAllButtons()
        core_recoveryPrompt.setActive(not enabled)
    end
end

local function setDynamicCollisionEnabled(enabled)
    be:setDynamicCollisionEnabled(enabled)
end

local function enterVehicle(id)
    local unicycle = be:getPlayerVehicle(0)
    if unicycle and unicycle:getJBeamFilename() == "unicycle" then
        be.nodeGrabber:clearVehicleFixedNodes(unicycle:getId())
        unicycle:setActive(0)
    end

    local veh = be:getObjectByID(id)
    if veh then
        be:enterVehicle(0, veh)
    end
end

local function spawnDefaultVehicle()
    core_vehicles.spawnDefault()
end

-- General helpers

local function isTrue(value)
    if string.lower(value) == "true" or value == "1" then
        return true
    elseif string.lower(value) == "false" or value == "0" then
        return false
    else
        return value
    end
end

local function playCountdown()
    guihooks.trigger('ScenarioFlashMessage', {{3,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown1')", true},
        {2,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown2')", true},
        {1,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown3')", true},
        {"ui.scenarios.go", 1, "Engine.Audio.playOnce('AudioGui', 'event:UI_CountdownGo')", true}})
end

local function setUiLayout(layout)
    core_gamestate.setGameState(nil, layout, nil, nil)
end

-- Map helpers

local function getRoadDistance(posA, posB)
    -- Get the point-to-point path
    local route = map.getPointToPointPath(posA, posB)
    if not route or #route < 1 then return -1 end

    return map.getPathLen(route)
end

local function getRoadDistanceRemaining(destinationPos)
    local veh = be:getPlayerVehicle(0)
    if veh then
        local pos = veh:getPosition()
        return getRoadDistance(pos, destinationPos)
    end
end


M.resetVehicle = resetVehicle
M.resetVehicleToPos = resetVehicleToPos
M.resetVehicleToPosRot = resetVehicleToPosRot
M.teleportVehicleToLastRoad = teleportVehicleToLastRoad
M.setVehicleFreeze = setVehicleFreeze
M.setVehicleRecoveryEnabled = setVehicleRecoveryEnabled
M.setDynamicCollisionEnabled = setDynamicCollisionEnabled
M.enterVehicle = enterVehicle
M.isTrue = isTrue
M.playCountdown = playCountdown
M.setUiLayout = setUiLayout
M.spawnDefaultVehicle = spawnDefaultVehicle
M.getRoadDistance = getRoadDistance
M.getRoadDistanceRemaining = getRoadDistanceRemaining


return M
-- General helpers

local function isTrue(value)
    if string.lower(value) == "true" or value == "1" then
        return true
    elseif string.lower(value) == "false" or value == "0" then
        return false
    else
        return value
    end
end

local function playCountdown()
    guihooks.trigger('ScenarioFlashMessage', {{3,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown1')", true},
        {2,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown2')", true},
        {1,1, "Engine.Audio.playOnce('AudioGui', 'event:UI_Countdown3')", true},
        {"ui.scenarios.go", 1, "Engine.Audio.playOnce('AudioGui', 'event:UI_CountdownGo')", true}})
end

local function setUiLayout(layout)
    core_gamestate.setGameState(nil, layout, nil, nil)
end

M.resetVehicle = resetVehicle
M.resetVehicleToPos = resetVehicleToPos
M.resetVehicleToPosRot = resetVehicleToPosRot
M.teleportVehicleToLastRoad = teleportVehicleToLastRoad
M.setVehicleFreeze = setVehicleFreeze
M.setVehicleRecoveryEnabled = setVehicleRecoveryEnabled
M.setDynamicCollisionEnabled = setDynamicCollisionEnabled
M.enterVehicle = enterVehicle
M.isTrue = isTrue
M.playCountdown = playCountdown
M.setUiLayout = setUiLayout
M.spawnDefaultVehicle = spawnDefaultVehicle

return M
