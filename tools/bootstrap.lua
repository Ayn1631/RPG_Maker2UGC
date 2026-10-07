-- Desktop only: file loading is not copied into a UGC bundle.
-- Return a dependency-aware module loader rooted at this checkout.
return function(root)
    assert(_VERSION == "Lua 5.3", "R2U requires Lua 5.3; found " .. tostring(_VERSION))
    root = (root or "."):gsub("\\", "/"):gsub("/+$", "") .. "/"
    local definitions, cache, visiting = {}, {}, {}
    for _, item in ipairs(assert(loadfile(root .. "tools/module_manifest.lua", "t", {}))()) do
        assert(not definitions[item.id], "duplicate desktop module: " .. item.id)
        definitions[item.id] = item
    end
    -- Resolve dependencies depth-first, memoize each module's exports, and reject dependency cycles.
    local function load_module(id)
        if cache[id] then return cache[id] end
        local item = assert(definitions[id], "unknown desktop module: " .. tostring(id))
        assert(not visiting[id], "desktop module cycle: " .. id)
        visiting[id] = true
        local deps = {}
        for _, dependency in ipairs(item.dependencies) do deps[dependency] = load_module(dependency) end
        local path = root .. "src/" .. id:gsub("%.", "/") .. ".lua"
        local chunk = assert(loadfile(path, "t", _G))
        local factory = chunk()
        assert(type(factory) == "function", "module must return a factory: " .. path)
        local exports = factory(deps)
        assert(type(exports) == "table", "factory must return a table: " .. path)
        cache[id], visiting[id] = exports, nil
        return exports
    end
    return load_module
end
