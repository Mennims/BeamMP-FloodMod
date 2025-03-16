local M = {}

local function resetVehicles()
    MP.hSendChatMessage(-1, "Resetting vehicles!")
    MP.TriggerClientEvent(-1, "E_ResetVehicle", "")
end

local function setVehicleFreeze(freeze)
    if freeze then
        MP.hSendChatMessage(-1, "Freezing vehicles!")
        MP.TriggerClientEvent(-1, "E_SetVehicleFreeze", "true")
    else
        MP.hSendChatMessage(-1, "Unfreezing vehicles!")
        MP.TriggerClientEvent(-1, "E_SetVehicleFreeze", "false")
    end
end

local function setVehicleRecoveryEnabled(enabled)
    if enabled then
        MP.hSendChatMessage(-1, "Enabling vehicle recovery!")
        MP.TriggerClientEvent(-1, "E_SetVehicleRecoveryEnabled", "true")
    else
        MP.hSendChatMessage(-1, "Disabling vehicle recovery!")
        MP.TriggerClientEvent(-1, "E_SetVehicleRecoveryEnabled", "false")
    end
end

M.resetVehicles = resetVehicles
M.setVehicleFreeze = setVehicleFreeze
M.setVehicleRecoveryEnabled = setVehicleRecoveryEnabled

return M
