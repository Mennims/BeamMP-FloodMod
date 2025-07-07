local M = {}

function M.getCurrentTimeMs()
    return math.floor(os.time() * 1000) + (os.clock() % 1) * 1000
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function setTimeout(func, delay, precise)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local str = ""
    for i = 1, 10 do
        local rand = math.random(1, #chars)
        str = str .. string.sub(chars, rand, rand)
    end

    local eventTimerName = "ET_" .. str

    _G["T_" .. str] = function()
        func()
        MP.CancelEventTimer(eventTimerName)
        _G["T_" .. str] = nil
    end

    -- Can't unregister event, may cause memory leaks
    MP.RegisterEvent(eventTimerName, "T_" .. str)

    if precise then 
        MP.CreateEventTimer(eventTimerName, delay, MP.CallStrategy.Precise)
    else
        MP.CreateEventTimer(eventTimerName, delay)
    end
end

M.deepcopy = deepcopy
M.setTimeout = setTimeout

return M
