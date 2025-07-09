local M = {}

local function updateGFX(dt)
    local data = {}
    data.vehID = obj:getID()
    data.pos = obj:getCenterPosition()
    obj:queueGameEngineLua("multiplayerHelper.onVehicleData(" .. string.format("%q", lpack.encode(data)) .. ")")
end

M.setCollision = setCollision
M.updateGFX = updateGFX

return M
