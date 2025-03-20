local M = {}

local function resetVehicles()
    MP.TriggerClientEvent(-1, "E_ResetVehicle", "")
end

local function setVehicleFreeze(freeze)
    if freeze then
        MP.TriggerClientEvent(-1, "E_SetVehicleFreeze", "true")
    else
        MP.TriggerClientEvent(-1, "E_SetVehicleFreeze", "false")
    end
end

local function setVehicleRecoveryEnabled(enabled)
    if enabled then
        MP.TriggerClientEvent(-1, "E_SetVehicleRecoveryEnabled", "true")
    else
        MP.TriggerClientEvent(-1, "E_SetVehicleRecoveryEnabled", "false")
    end
end

local function setDynamicCollisionEnabled(enabled)
    if enabled then
        MP.TriggerClientEvent(-1, "E_SetDynamicCollisionEnabled", "true")
    else
        MP.TriggerClientEvent(-1, "E_SetDynamicCollisionEnabled", "false")
    end
end

local function enterVehicle(playerId, vehicleId)
    MP.TriggerClientEvent(playerId, "E_EnterVehicle", tostring(vehicleId))
end

M.resetVehicles = resetVehicles
M.setVehicleFreeze = setVehicleFreeze
M.setVehicleRecoveryEnabled = setVehicleRecoveryEnabled
M.setDynamicCollisionEnabled = setDynamicCollisionEnabled
M.enterVehicle = enterVehicle

return M
