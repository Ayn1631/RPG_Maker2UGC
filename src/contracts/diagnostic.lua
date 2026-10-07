return function()
    local M = {}

    function M.new(code, reason, location)
        assert(type(code) == "string" and type(reason) == "string", "invalid diagnostic")
        local result = { severity = "error", code = code, reason = reason }
        for _, key in ipairs({ "file", "jsonPath", "offset", "hint", "moduleId" }) do
            if location and location[key] ~= nil then result[key] = location[key] end
        end
        return result
    end

    function M.raise(code, reason, location)
        error(M.new(code, reason, location), 0)
    end

    function M.is(value)
        return type(value) == "table" and type(value.code) == "string"
            and type(value.reason) == "string" and value.severity == "error"
    end

    return M
end
