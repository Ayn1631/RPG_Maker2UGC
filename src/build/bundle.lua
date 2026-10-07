-- Static bundler for trusted, controlled Lua 5.3 factory modules.
return function(deps)
    local diagnostic = deps["contracts.diagnostic"]
    local serialize = deps["build.serialize"]
    local sha256 = deps["build.sha256"]
    local callbacks = {"OnInit", "OnStart", "OnEnable", "OnDisable", "OnUpdate", "OnLevelUpdate", "OnDestroy"}
    -- Terrain frame geometry is immutable; placement and live control state are
    -- owned by each plan/map view. Intern only these frames, never game state.
    local function terrainConstants(package)
        local groups,seen={},{}
        if type(package)~='table'then return {},{}end
        local resources=package.resources or {}
        if type(resources)~='table'then return {},{}end
        for _,sets in pairs(resources.primitiveChunks or {})do for _,plans in pairs(sets)do for _,plan in ipairs(plans)do
            local frame=plan.frame
            if frame and not seen[frame]then
                seen[frame]=true
                local text=serialize.literal(frame,{compact=true})
                local group=groups[text] or {};groups[text]=group;group[#group+1]=frame
            end
        end end end
        local keys={};for text,frames in pairs(groups)do if #frames>1 then keys[#keys+1]=text end end
        table.sort(keys)
        local references={}
        for id,text in ipairs(keys)do for _,frame in ipairs(groups[text])do references[frame]=id end end
        return keys,references
    end
    local forbidden = {
        require=true, package=true, io=true, os=true, load=true, loadfile=true,
        dofile=true, coroutine=true, debug=true, _G=true, _ENV=true,
    }

    local function fail(code, reason, path)
        diagnostic.raise(code, reason, path and {file=path} or nil)
    end

    local function errorReason(value)
        if diagnostic.is(value) then return value.code .. ": " .. value.reason end
        return tostring(value)
    end

    local function array(value, label, path)
        if type(value) ~= "table" then fail("E_MANIFEST", label .. " must be an array", path) end
        local count, maximum = 0, 0
        for key in pairs(value) do
            if type(key) ~= "number" or math.type(key) ~= "integer" or key < 1 then
                fail("E_MANIFEST", label .. " has an invalid array key", path)
            end
            count = count + 1
            if key > maximum then maximum = key end
        end
        if count ~= maximum then fail("E_MANIFEST", label .. " has a hole", path) end
        return maximum
    end

    local function validId(id)
        if type(id) ~= "string" or id == "" or id:sub(1,1) == "." or id:sub(-1) == "." or id:find("..",1,true) then return false end
        for segment in id:gmatch("[^.]+") do
            if not segment:match("^[A-Za-z_][A-Za-z0-9_]*$") then return false end
        end
        return true
    end

    local function relativePath(path)
        if type(path) ~= "string" or path == "" or path:find("\0",1,true) then
            fail("E_MANIFEST", "module path must be a nonempty relative path", type(path)=="string" and path or nil)
        end
        local normalized = path:gsub("\\", "/")
        if normalized:sub(1,1) == "/" or normalized:find(":",1,true) then
            fail("E_MANIFEST", "absolute paths and drive/stream prefixes are forbidden", path)
        end
        local parts = {}
        for part in normalized:gmatch("[^/]+") do
            if part == ".." then fail("E_MANIFEST", "module path may not contain '..'", path) end
            if part ~= "." then parts[#parts+1] = part end
        end
        if #parts == 0 then fail("E_MANIFEST", "module path must name a file", path) end
        return table.concat(parts, "/")
    end

    -- Lexical checks deliberately inspect direct identifiers, not strings or comments.
    -- This is not an isolation boundary against malicious/indirect Lua accesses.
    local function checkApis(source, path)
        local i, size, previous, beforePrevious = 1, #source, nil, nil
        local function longEnd(at)
            local equals = source:sub(at):match("^%[(=*)%[")
            if equals == nil then return nil end
            local close = "]" .. equals .. "]"
            local finish = source:find(close, at + #equals + 2, true)
            return finish and finish + #close or size + 1
        end
        local function token(value, at)
            if forbidden[value] or (value == "dump" and previous == "." and beforePrevious == "string") then
                local _, lines = source:sub(1,at-1):gsub("\n", "")
                fail("E_MODULE_API", "forbidden direct API '" .. (value == "dump" and "string.dump" or value) .. "' at line " .. (lines+1), path)
            end
            beforePrevious, previous = previous, value
        end
        while i <= size do
            local ch = source:sub(i,i)
            if ch:match("%s") then
                i = i + 1
            elseif source:sub(i,i+1) == "--" then
                local finish = longEnd(i+2)
                i = finish or (source:find("\n",i+2,true) or size+1)
            elseif ch == "'" or ch == '"' then
                local quote = ch
                token("<string>", i)
                i = i + 1
                while i <= size do
                    ch = source:sub(i,i)
                    if ch == "\\" then i = i + 2
                    elseif ch == quote then i = i + 1; break
                    else i = i + 1 end
                end
            elseif ch == "[" and longEnd(i) then
                token("<string>", i)
                i = longEnd(i)
            elseif ch:match("[A-Za-z_]") then
                local finish = i + 1
                while source:sub(finish,finish):match("[A-Za-z0-9_]") do finish = finish + 1 end
                token(source:sub(i,finish-1), i)
                i = finish
            else
                token(ch, i)
                i = i + 1
            end
        end
    end

    -- One static definition is used for preflight and emitted verbatim. No input
    -- data is compiled here, and the generated file contains no dynamic loader.
    local environmentSource = [=[local function __r2u_environment()
    local function readonly(values, label, resolve)
        return setmetatable({}, {
            __index=function(_, key)
                local value = values[key]
                if value == nil and resolve then
                    value = resolve(key)
                    if value ~= nil then values[key] = value end
                end
                if value == nil then
                    error({severity="error",code="E_MODULE_GLOBAL",reason="Unavailable " .. label .. ": " .. tostring(key)}, 0)
                end
                return value
            end,
            __newindex=function(_, key)
                error({severity="error",code="E_MODULE_GLOBAL",reason="Cannot write " .. label .. ": " .. tostring(key)}, 0)
            end,
            __pairs=function() return next, values, nil end,
            __metatable=false,
        })
    end
    local function library(original, excluded, constants)
        local values = {}
        for key, value in pairs(original or {}) do
            if not (excluded and excluded[key]) then values[key] = value end
        end
        -- Some UGC hosts omit standard math constants. Supply exact Lua 5.3
        -- values inside our wrapper without modifying the host library.
        for key, value in pairs(constants or {}) do
            if values[key] == nil then values[key] = value end
        end
        -- Host libraries may expose callable fields through __index without
        -- enumerating them in pairs. Resolve once, cache locally, never write
        -- to the host or permit excluded fields through this path.
        return readonly(values, "standard library field", function(key)
            if original and not (excluded and excluded[key]) then return original[key] end
        end)
    end
    return readonly({
        assert=assert,error=error,ipairs=ipairs,next=next,pairs=pairs,pcall=pcall,xpcall=xpcall,
        select=select,tonumber=tonumber,tostring=tostring,type=type,rawequal=rawequal,
        rawget=rawget,rawset=rawset,getmetatable=getmetatable,setmetatable=setmetatable,
        math=library(math,{random=true,randomseed=true},{huge=1.0/0.0,pi=3.141592653589793}),
        string=library(string,{dump=true}),
        table=library(table),utf8=library(utf8),_VERSION="Lua 5.3",
    }, "module global")
end]=]
    local environment = assert(load(environmentSource .. "\nreturn __r2u_environment",
        "@r2u-environment", "t"))()

    local function instantiate(source,path,arguments)
        checkApis(source,path)
        local chunk,syntax=load(source,'@'..path,'t',environment())
        if not chunk then fail('E_MODULE_SYNTAX',syntax,path)end
        local ok,factory=pcall(chunk)
        if not ok then fail('E_MODULE_FORMAT','module initialization failed: '..errorReason(factory),path)end
        if type(factory)~='function'then fail('E_MODULE_FORMAT','module chunk must return a factory function',path)end
        local assembled,result=pcall(factory,arguments or {})
        if not assembled then fail('E_MODULE_FORMAT','factory failed: '..errorReason(result),path)end
        if type(result)~='table' or getmetatable(result)~=nil then fail('E_MODULE_FORMAT','factory must return a plain exports table without a metatable',path)end
        return result
    end
    local function build(manifest, options)
        if type(manifest) ~= "table" or not validId(manifest.entry) then
            fail("E_MANIFEST", "manifest.entry must be a dotted module identifier")
        end
        if type(options) ~= "table" or type(options.read) ~= "function" then
            fail("E_MANIFEST", "options.read must be a build-time reader")
        end
        -- User's deployment ceiling: 20 decimal MB, conservatively below 20 MiB.
        local limit = options.maxBytes == nil and 20000000 or options.maxBytes
        if type(limit) ~= "number" or math.type(limit) ~= "integer" or limit < 1 then
            fail("E_MANIFEST", "maxBytes must be a positive integer")
        end
        local byId, ids = {}, {}
        for index = 1, array(manifest.modules, "manifest.modules") do
            local record = manifest.modules[index]
            if type(record) ~= "table" or not validId(record.id) then
                fail("E_MANIFEST", "module " .. index .. " has an invalid identifier")
            end
            local path = relativePath(record.path)
            if byId[record.id] then fail("E_MODULE_DUPLICATE", "duplicate module '" .. record.id .. "'", path) end
            local dependencies, seen = {}, {}
            local input = record.dependencies == nil and {} or record.dependencies
            for depIndex = 1, array(input, "dependencies of " .. record.id, path) do
                local id = input[depIndex]
                if not validId(id) then fail("E_MANIFEST", "invalid dependency identifier", path) end
                if seen[id] then fail("E_MODULE_DUPLICATE", "duplicate dependency '" .. id .. "'", path) end
                seen[id] = true
                dependencies[#dependencies+1] = id
            end
            table.sort(dependencies)
            byId[record.id] = {id=record.id, path=path, dependencies=dependencies}
            ids[#ids+1] = record.id
        end
        table.sort(ids)
        if not byId[manifest.entry] then fail("E_MODULE_MISSING", "entry module '" .. manifest.entry .. "' is missing") end
        for _, id in ipairs(ids) do
            for _, dependency in ipairs(byId[id].dependencies) do
                if not byId[dependency] then
                    fail("E_MODULE_MISSING", "module '" .. id .. "' declares missing dependency '" .. dependency .. "'", byId[id].path)
                end
            end
        end

        -- Choose the smallest id from the ready set after each individual step.
        local order, emitted = {}, {}
        while #order < #ids do
            local chosen
            for _, id in ipairs(ids) do
                if not emitted[id] then
                    local ready = true
                    for _, dependency in ipairs(byId[id].dependencies) do
                        if not emitted[dependency] then ready = false; break end
                    end
                    if ready then chosen = id; break end
                end
            end
            if not chosen then
                local pending = {}
                for _, id in ipairs(ids) do if not emitted[id] then pending[#pending+1] = id end end
                fail("E_MODULE_CYCLE", "dependency cycle among: " .. table.concat(pending, ", "), byId[pending[1]].path)
            end
            emitted[chosen] = true
            order[#order+1] = chosen
        end

        local exports, identityModules, total = {}, {}, 0
        for _, id in ipairs(order) do
            local record = byId[id]
            local ok, source, reason = pcall(options.read, record.path)
            if not ok or type(source) ~= "string" then
                fail("E_MODULE_READ", "could not read '" .. id .. "': " .. errorReason(ok and (reason or "reader did not return bytes") or source), record.path)
            end
            source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
            total = total + #source
            if total > limit then fail("E_BUNDLE_LIMIT", "normalized module input exceeds maxBytes", record.path) end
            local arguments = {}
            for _, dependency in ipairs(record.dependencies) do arguments[dependency] = exports[dependency] end
            local result=instantiate(source,record.path,arguments)
            exports[id], record.source = result, source
        end
        local entry = exports[manifest.entry]
        for _, name in ipairs(callbacks) do
            if entry[name] ~= nil and type(entry[name]) ~= "function" then
                fail("E_MODULE_FORMAT", "entry callback '" .. name .. "' must be a function", byId[manifest.entry].path)
            end
        end
        if entry.configure ~= nil and type(entry.configure) ~= "function" then
            fail("E_MODULE_FORMAT", "entry.configure must be a function", byId[manifest.entry].path)
        end
        if entry.attachHost ~= nil and type(entry.attachHost) ~= "function" then
            fail("E_MODULE_FORMAT", "entry.attachHost must be a function", byId[manifest.entry].path)
        end
        for _, id in ipairs(ids) do
            local record = byId[id]
            identityModules[#identityModules+1] = {id=id,path=record.path,dependencies=record.dependencies,sha256=sha256.hex(record.source)}
        end
        local embedded = options.package == nil and {} or options.package
        local externalIdentity = options.identity == nil and {} or options.identity
        -- Lua table-constructor shorthand preserves types and sparse indices;
        -- it avoids repeating quoted property names for every geometric part.
        local terrain,references=terrainConstants(embedded)
        local packageLiteral = serialize.literal(embedded,{compact=true,tableReferences=references})
        local buildId = sha256.hex(serialize.literal({entry=manifest.entry,modules=identityModules,package=embedded,identity=externalIdentity}))
        local lines, line, sourceMap = {}, 1, {}
        local function emit(text)
            if text:sub(-1) ~= "\n" then text = text .. "\n" end
            lines[#lines+1] = text
            local _, count = text:gsub("\n", "")
            line = line + count
        end
        emit("-- RPG_Maker2UGC static development bundle; platform playability requires separate verification.")
        emit("local __r2u_null = {}")
        if #terrain>0 then emit('local __r2u_art = {'..table.concat(terrain,',')..'}')end
        emit("local __r2u_package = " .. packageLiteral)
        emit("local __r2u_factories, __r2u_modules = {}, {}")
        emit(environmentSource)
        for _, id in ipairs(order) do
            local record = byId[id]
            emit("__r2u_factories[" .. serialize.literal(id) .. "] = (function()")
            emit("local _ENV = __r2u_environment()")
            local start = line
            emit(record.source)
            sourceMap[#sourceMap+1] = {moduleId=id,path=record.path,startLine=start,endLine=line-1}
            emit("end)()")
        end
        for _, id in ipairs(order) do
            local record, arguments = byId[id], {}
            for _, dependency in ipairs(record.dependencies) do
                local key = serialize.literal(dependency)
                arguments[#arguments+1] = "[" .. key .. "]=__r2u_modules[" .. key .. "]"
            end
            local key = serialize.literal(id)
            emit("__r2u_modules[" .. key .. "] = __r2u_factories[" .. key .. "]({" .. table.concat(arguments,",") .. "})")
        end
        emit("local __r2u_entry = __r2u_modules[" .. serialize.literal(manifest.entry) .. "]")
        emit("local __r2u_buildId = " .. serialize.literal(buildId))
        emit("if __r2u_entry.configure ~= nil then __r2u_entry.configure(__r2u_package, __r2u_buildId) end")
        for _, name in ipairs(callbacks) do
            if name == "OnInit" and entry.attachHost then
                emit("function OnInit(...)")
                emit("__r2u_entry.attachHost({game=game,script=script,Enum=Enum,Color=Color,logError=printerr or print,traceback=debug and debug.traceback,clock=__r2u_package.uiPerformance and __r2u_package.uiPerformance.overlay and os and os.clock})")
                emit("if __r2u_entry.OnInit then return __r2u_entry.OnInit(...) end")
                emit("end")
            else
                emit("if __r2u_entry." .. name .. " ~= nil then " .. name .. " = __r2u_entry." .. name .. " end")
            end
        end
        emit("return {entry=__r2u_entry, package=__r2u_package, null=__r2u_null, buildId=__r2u_buildId}")
        local source = table.concat(lines)
        if #source > limit then fail("E_BUNDLE_LIMIT", "generated source bytes="..#source.." exceeds maxBytes="..limit, byId[manifest.entry].path) end
        local compiled, syntax = load(source, "@levelScript.lua", "t", environment())
        if not compiled then fail("E_MODULE_SYNTAX", "generated source failed compilation: " .. syntax) end
        return {source=source,buildId=buildId,sha256=sha256.hex(source),order=order,sourceMap=sourceMap}
    end

    return {build=build,instantiate=instantiate}
end
