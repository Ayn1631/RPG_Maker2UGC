-- Shared diagnostic contract used by the converter and runtime: callers can
-- inspect the same structured error shape instead of parsing message text.
return function()
    local M = {}

    -- Build an error value and copy only the location fields understood by the contract.
    function M.new(code, reason, location)
        assert(type(code) == "string" and type(reason) == "string", "invalid diagnostic")
        local result = { severity = "error", code = code, reason = reason }
        for _, key in ipairs({ "file", "jsonPath", "offset", "hint", "moduleId" }) do
            if location and location[key] ~= nil then result[key] = location[key] end
        end
        return result
    end

    -- Raise the structured value without adding a traceback wrapper to its payload.
    function M.raise(code, reason, location)
        error(M.new(code, reason, location), 0)
    end

    -- Recognize diagnostics crossing pcall boundaries before normalizing unknown errors.
    function M.is(value)
        return type(value) == "table" and type(value.code) == "string"
            and type(value.reason) == "string" and value.severity == "error"
    end

    return M
end
