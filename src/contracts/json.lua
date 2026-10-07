return function(deps)
    local diagnostic = deps["contracts.diagnostic"]
    local array_mt, object_mt = {}, {}
    local null = {}
    local M = { null = null }

    local function fail(code, reason, offset, file)
        diagnostic.raise(code, reason, { offset = offset or 1, file = file })
    end

    local function byte_less(a, b)
        for i = 1, math.min(#a, #b) do
            local x, y = a:byte(i), b:byte(i)
            if x ~= y then return x < y end
        end
        return #a < #b
    end

    -- Lua 5.3's UTF-8 library also accepts surrogate code points; JSON must not.
    local function invalid_utf8(s)
        local i = 1
        while i <= #s do
            local b, n, low, high = s:byte(i), 0, 128, 191
            if b < 128 then n = 1
            elseif b >= 194 and b <= 223 then n = 2
            elseif b >= 224 and b <= 239 then
                n = 3
                if b == 224 then low = 160 elseif b == 237 then high = 159 end
            elseif b >= 240 and b <= 244 then
                n = 4
                if b == 240 then low = 144 elseif b == 244 then high = 143 end
            else return i end
            if n > 1 then
                local second = s:byte(i + 1)
                if not second or second < low or second > high then return i end
                for j = i + 2, i + n - 1 do
                    local next_byte = s:byte(j)
                    if not next_byte or next_byte < 128 or next_byte > 191 then return i end
                end
            end
            i = i + n
        end
    end

    local function mark(t, mt)
        if t == nil then t = {} end
        if type(t) ~= "table" or rawequal(t, null) then fail("E_JSON_ENCODE", "JSON container must be a table") end
        local old = getmetatable(t)
        if old ~= nil and not rawequal(old, array_mt) and not rawequal(old, object_mt) then fail("E_JSON_ENCODE", "Unsupported metatable") end
        return setmetatable(t, mt)
    end
    function M.array(t) return mark(t, array_mt) end
    function M.object(t) return mark(t, object_mt) end

    local function array_size(t)
        local count, highest = 0, 0
        for k in next, t do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k == math.huge then return nil end
            count = count + 1
            if k > highest then highest = k end
        end
        if count ~= highest then return nil end
        return count
    end
    function M.is_array(value)
        if type(value) ~= "table" or rawequal(value, null) then return false end
        local mt = getmetatable(value)
        if rawequal(mt, array_mt) then return true end
        if mt ~= nil then return false end
        local size = array_size(value)
        return size ~= nil and size > 0
    end

    function M.decode(text, options)
        if options ~= nil and type(options) ~= "table" then fail("E_JSON_SYNTAX", "JSON options must be a table") end
        options = options or {}
        local file = options.file
        if type(text) ~= "string" then fail("E_JSON_SYNTAX", "JSON input must be a string", 1, file) end
        local defaults = { maxBytes = 16777216, maxDepth = 128, maxItems = 1000000, maxStringBytes = 8388608 }
        local limits = {}
        for key, default in pairs(defaults) do
            local value = options[key]
            if value == nil then value = default end
            if type(value) ~= "number" or value < 0 or value % 1 ~= 0 or value == math.huge then
                fail("E_JSON_LIMIT", "Invalid " .. key, 1, file)
            end
            limits[key] = value
        end
        if #text > limits.maxBytes then fail("E_JSON_LIMIT", "JSON exceeds maxBytes", 1, file) end
        local pos, items = 1, 0
        local function syntax(reason, at) fail("E_JSON_SYNTAX", reason, at or pos, file) end
        local function limit(reason, at) fail("E_JSON_LIMIT", reason, at or pos, file) end
        local function whitespace()
            while true do
                local b = text:byte(pos)
                if b == 32 or b == 9 or b == 10 or b == 13 then pos = pos + 1 else return end
            end
        end
        local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
        local function hex4()
            local s = text:sub(pos, pos + 3)
            if #s ~= 4 or s:find("[^0-9a-fA-F]") then syntax("Invalid Unicode escape") end
            pos = pos + 4
            return tonumber(s, 16)
        end
        local function string_value()
            local start = pos
            pos = pos + 1
            local chunks, length, raw_start = {}, 0, pos
            local function append(s)
                length = length + #s
                if length > limits.maxStringBytes then limit("JSON string exceeds maxStringBytes", start) end
                chunks[#chunks + 1] = s
            end
            while pos <= #text do
                local b = text:byte(pos)
                if b == 34 or b == 92 then
                    local raw = text:sub(raw_start, pos - 1)
                    local bad = invalid_utf8(raw)
                    if bad then syntax("Invalid UTF-8", raw_start + bad - 1) end
                    append(raw)
                    if b == 34 then pos = pos + 1; return table.concat(chunks) end
                    pos = pos + 1
                    local escape = text:sub(pos, pos)
                    pos = pos + 1
                    if escapes[escape] then append(escapes[escape])
                    elseif escape == "u" then
                        local cp = hex4()
                        if cp >= 55296 and cp <= 56319 then
                            if text:sub(pos, pos + 1) ~= "\\u" then syntax("Missing low surrogate") end
                            pos = pos + 2
                            local low = hex4()
                            if low < 56320 or low > 57343 then syntax("Invalid low surrogate", pos - 4) end
                            cp = 65536 + (cp - 55296) * 1024 + low - 56320
                        elseif cp >= 56320 and cp <= 57343 then syntax("Isolated low surrogate", pos - 4) end
                        append(utf8.char(cp))
                    else syntax("Invalid string escape", pos - 1) end
                    raw_start = pos
                elseif b < 32 then syntax("Unescaped control character")
                else
                    pos = pos + 1
                    if length + pos - raw_start > limits.maxStringBytes then limit("JSON string exceeds maxStringBytes", start) end
                end
            end
            syntax("Unterminated string", start)
        end
        local function digit(b) return b and b >= 48 and b <= 57 end
        local function number_value()
            local start = pos
            if text:byte(pos) == 45 then pos = pos + 1 end
            if text:byte(pos) == 48 then pos = pos + 1
            elseif digit(text:byte(pos)) and text:byte(pos) ~= 48 then
                repeat pos = pos + 1 until not digit(text:byte(pos))
            else syntax("Invalid number") end
            if text:byte(pos) == 46 then
                pos = pos + 1
                if not digit(text:byte(pos)) then syntax("Missing fractional digits") end
                repeat pos = pos + 1 until not digit(text:byte(pos))
            end
            local b = text:byte(pos)
            if b == 69 or b == 101 then
                pos = pos + 1
                b = text:byte(pos)
                if b == 43 or b == 45 then pos = pos + 1 end
                if not digit(text:byte(pos)) then syntax("Missing exponent digits") end
                repeat pos = pos + 1 until not digit(text:byte(pos))
            end
            local value = tonumber(text:sub(start, pos - 1))
            if not value or value ~= value or value == math.huge or value == -math.huge then syntax("Non-finite number", start) end
            return value
        end
        local parse
        local function add_item()
            items = items + 1
            if items > limits.maxItems then limit("JSON exceeds maxItems") end
        end
        parse = function(depth)
            whitespace()
            local c = text:sub(pos, pos)
            if c == '"' then return string_value()
            elseif c == "[" or c == "{" then
                depth = depth + 1
                if depth > limits.maxDepth then limit("JSON exceeds maxDepth") end
                local is_array = c == "["
                local result = is_array and M.array() or M.object()
                local close = is_array and "]" or "}"
                pos = pos + 1; whitespace()
                if text:sub(pos, pos) == close then pos = pos + 1; return result end
                local index = 0
                while true do
                    local key
                    if is_array then index = index + 1; key = index
                    else
                        if text:sub(pos, pos) ~= '"' then syntax("Expected object key") end
                        local key_pos = pos
                        key = string_value()
                        if rawget(result, key) ~= nil then syntax("Duplicate object key", key_pos) end
                        whitespace()
                        if text:sub(pos, pos) ~= ":" then syntax("Expected colon") end
                        pos = pos + 1
                    end
                    add_item()
                    result[key] = parse(depth)
                    whitespace()
                    c = text:sub(pos, pos)
                    if c == close then pos = pos + 1; return result end
                    if c ~= "," then syntax("Expected comma or closing delimiter") end
                    pos = pos + 1; whitespace()
                    if text:sub(pos, pos) == close then syntax("Trailing comma") end
                end
            elseif c == "-" or digit(text:byte(pos)) then return number_value()
            else
                for token, value in pairs({ ["true"] = true, ["false"] = false, ["null"] = null }) do
                    if text:sub(pos, pos + #token - 1) == token then pos = pos + #token; return value end
                end
                syntax("Expected JSON value")
            end
        end
        local result = parse(0)
        whitespace()
        if pos <= #text then syntax("Trailing content") end
        return result
    end

    function M.encode(value)
        local active = {}
        local function bad(reason) fail("E_JSON_ENCODE", reason) end
        local function quote(s)
            if invalid_utf8(s) then bad("Invalid UTF-8 string") end
            return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
                if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' end
                return string.format("\\u%04x", c:byte())
            end) .. '"'
        end
        local encode
        encode = function(v)
            if rawequal(v, null) then return "null" end
            local kind = type(v)
            if kind == "string" then return quote(v)
            elseif kind == "boolean" then return tostring(v)
            elseif kind == "number" then
                if v ~= v or v == math.huge or v == -math.huge then bad("Non-finite number") end
                if math.type(v) == "integer" then return tostring(v) end
                return (string.format("%.17g", v):gsub(",", "."))
            elseif kind ~= "table" then bad("Unsupported JSON value: " .. kind) end
            local mt = getmetatable(v)
            if mt ~= nil and not rawequal(mt, array_mt) and not rawequal(mt, object_mt) then bad("Unsupported metatable") end
            if active[v] then bad("Circular JSON value") end
            active[v] = true
            local output = {}
            local size = array_size(v)
            local as_array = rawequal(mt, array_mt) or (mt == nil and size and size > 0)
            if as_array then
                if not size then bad("Array must have dense positive integer keys") end
                for i = 1, size do output[i] = encode(v[i]) end
            else
                local keys = {}
                for k in next, v do
                    if type(k) ~= "string" then bad("Object keys must be strings") end
                    keys[#keys + 1] = k
                end
                table.sort(keys, byte_less)
                for i, key in ipairs(keys) do output[i] = quote(key) .. ":" .. encode(v[key]) end
            end
            active[v] = nil
            return (as_array and "[" or "{") .. table.concat(output, ",") .. (as_array and "]" or "}")
        end
        return encode(value)
    end
    return M
end
