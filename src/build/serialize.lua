return function(deps)
    local json, diagnostic = deps["contracts.json"], deps["contracts.diagnostic"]
    local array_mt, object_mt = getmetatable(json.array()), getmetatable(json.object())
    local keywords = { ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,["end"]=true,["false"]=true,["for"]=true,["function"]=true,["goto"]=true,["if"]=true,["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,["until"]=true,["while"]=true }
    local function fail(reason) diagnostic.raise("E_SERIALIZE", reason) end
    local function string_literal(s)
        local out = { '"' }
        for i = 1, #s do
            local b = s:byte(i)
            if b == 34 then out[#out+1] = '\\"'
            elseif b == 92 then out[#out+1] = '\\\\'
            elseif b < 32 or b > 126 then out[#out+1] = string.format("\\%03d", b)
            else out[#out+1] = string.char(b) end
        end
        out[#out+1] = '"'
        return table.concat(out)
    end
    local function key_less(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        if type(a) == "number" then return a < b end
        for i = 1, math.min(#a, #b) do
            local x,y = a:byte(i),b:byte(i)
            if x ~= y then return x < y end
        end
        return #a < #b
    end
    local function literal(value, options)
        if options ~= nil and type(options) ~= "table" then fail("Options must be a table") end
        options = options or {}
        local symbol = options.nullSymbol
        if symbol == nil then symbol = "__r2u_null" end
        if type(symbol) ~= "string" or not symbol:match("^[A-Za-z_][A-Za-z0-9_]*$") or keywords[symbol] then fail("nullSymbol must be a single Lua identifier") end
        local references=options.tableReferences
        local referenceSymbol=options.referenceSymbol or '__r2u_art'
        if references and (type(references)~='table' or type(referenceSymbol)~='string' or not referenceSymbol:match('^[A-Za-z_][A-Za-z0-9_]*$') or keywords[referenceSymbol])then fail('Invalid static table reference options')end
        local active = {}
        local emit
        emit = function(v)
            if rawequal(v, json.null) then return symbol end
            if references and type(v)=='table' and references[v] then
                local id=references[v]
                if type(id)~='number' or id<1 or id%1~=0 then fail('Invalid static table reference index')end
                return referenceSymbol..'['..string.format('%.0f',id)..']'
            end
            local kind = type(v)
            if kind == "string" then return string_literal(v)
            elseif kind == "boolean" then return tostring(v)
            elseif kind == "number" then
                if v ~= v or v == math.huge or v == -math.huge then fail("Non-finite number") end
                if math.type(v) == "integer" then
                    -- The bare minimum integer parses as a float in Lua 5.3.
                    if v == math.mininteger then return "(" .. tostring(math.mininteger + 1) .. "-1)" end
                    return tostring(v)
                end
                -- Fengari's format loses the sign of IEEE negative zero.
                if v == 0 and 1 / v < 0 then return "-0.0" end
                local result = string.format("%.17g", v):gsub(",", ".")
                if not result:find("[.eE]") then result = result .. ".0" end
                return result
            elseif kind ~= "table" then fail("Unsupported value: " .. kind) end
            local mt = getmetatable(v)
            if mt ~= nil and not rawequal(mt, array_mt) and not rawequal(mt, object_mt) then fail("Unsupported metatable") end
            if active[v] then fail("Circular table") end
            active[v] = true
            local keys, out = {}, {}
            for k in next, v do
                if type(k) ~= "string" and (type(k) ~= "number" or k ~= k or k == math.huge or k == -math.huge or k % 1 ~= 0) then fail("Only string and integer keys are supported") end
                keys[#keys+1] = k
            end
            table.sort(keys, key_less)
            local sequence=1
            for i,k in ipairs(keys) do
                local prefix
                if options.compact and type(k)=='number' and k==sequence then
                    prefix='';sequence=sequence+1
                elseif options.compact and type(k)=='string' and k:match('^[A-Za-z_][A-Za-z0-9_]*$') and not keywords[k] then
                    prefix=k..'='
                else prefix='['..emit(k)..']=' end
                out[i]=prefix..emit(v[k])
            end
            active[v] = nil
            return "{" .. table.concat(out, ",") .. "}"
        end
        return emit(value)
    end
    return { literal = literal }
end
