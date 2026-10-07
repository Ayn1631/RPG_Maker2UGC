return function(deps)
  local json = deps["contracts.json"]
  local diagnostic = deps["contracts.diagnostic"]
  local sha256 = deps["build.sha256"]
  local profiles = { ["mv-turn"] = "js/rpg_core.js", ["mz-turn"] = "js/rmmz_core.js",
    ["mz-tpb-active"] = "js/rmmz_core.js", ["mz-tpb-wait"] = "js/rmmz_core.js" }
  local names = { "System", "MapInfos", "Actors", "Classes", "Skills", "Items",
    "Weapons", "Armors", "Enemies", "Troops", "States", "Tilesets", "CommonEvents", "Animations" }
  -- These are converter resource guards, not RPG Maker or target-platform limits.
  local maxBytes, maxItems, maxMaps, maxTiles = 16 * 1024 * 1024, 1000000, 4096, 1000000
  local function object(value)
    return type(value) == "table" and value ~= json.null and not json.is_array(value)
  end
  local function integer(value)
    return type(value) == "number" and math.tointeger(value) ~= nil
  end
  -- A conservative lexical recognizer, not a JS evaluator or general JS parser.
  -- Only one top-level Utils.RPGMAKER_VERSION = "literal"; is accepted.
  local function core_version(source)
    local tokens, position, braces, parens = {}, 1, 0, 0
    local function push(kind, value, escaped)
      tokens[#tokens + 1] = {kind=kind, value=value, escaped=escaped, braces=braces, parens=parens}
    end
    local regex_prefix = { ["="]=true, ["("]=true, ["["]=true, [","]=true,
      [":"]=true, ["!"]=true, ["?"]=true, ["return"]=true, ["&&"]=true, ["||"]=true }
    while position <= #source do
      local character = source:sub(position, position)
      local pair = source:sub(position, position + 1)
      if character:match("%s") then position = position + 1
      elseif pair == "//" then position = source:find("\n", position + 2, true) or (#source + 1)
      elseif pair == "/*" then
        local finish = source:find("*/", position + 2, true)
        if not finish then return nil end
        position = finish + 2
      elseif character == '"' or character == "'" or character == "`" then
        local quote, start, escaped, closed = character, position + 1, false, false
        position = position + 1
        while position <= #source do
          local current = source:sub(position, position)
          if current == "\\" then escaped = true; position = position + 2
          elseif current == quote then closed = true; break
          else position = position + 1 end
        end
        if not closed then return nil end
        push(quote == "`" and "template" or "string", source:sub(start, position - 1), escaped)
        position = position + 1
      elseif character == "/" and (not tokens[#tokens] or regex_prefix[tokens[#tokens].value]) then
        local in_class, closed = false, false
        position = position + 1
        while position <= #source do
          local current = source:sub(position, position)
          if current == "\\" then position = position + 2
          elseif current == "[" then in_class = true; position = position + 1
          elseif current == "]" then in_class = false; position = position + 1
          elseif current == "/" and not in_class then closed = true; position = position + 1; break
          elseif current == "\n" or current == "\r" then return nil
          else position = position + 1 end
        end
        if not closed then return nil end
        while source:sub(position, position):match("[A-Za-z]") do position = position + 1 end
        push("regex", "<regex>")
      elseif character:match("[A-Za-z_$]") then
        local word = source:sub(position):match("^[A-Za-z_$][A-Za-z0-9_$]*")
        push("identifier", word); position = position + #word
      else
        if pair == "&&" or pair == "||" then push("punctuation", pair); position = position + 2
        else
          push("punctuation", character)
          if character == "{" then braces = braces + 1 elseif character == "}" then braces = braces - 1 end
          if character == "(" then parens = parens + 1 elseif character == ")" then parens = parens - 1 end
          if braces < 0 or parens < 0 then return nil end
          position = position + 1
        end
      end
    end
    local result
    for index, token in ipairs(tokens) do
      local dot, member, assignment, literal, ending = table.unpack(tokens, index + 1, index + 5)
      if token.kind == "identifier" and token.value == "Utils" and dot and dot.value == "."
        and member and member.value == "RPGMAKER_VERSION" and assignment and assignment.value == "=" then
        local previous = tokens[index - 1]
        if result or token.braces ~= 0 or token.parens ~= 0
          or (previous and previous.value ~= ";" and previous.value ~= "}")
          or not literal or literal.kind ~= "string" or literal.escaped or literal.value == ""
          or not ending or ending.value ~= ";" then return nil end
        result = literal.value
      end
    end
    if braces ~= 0 or parens ~= 0 then return nil end
    return result
  end
  local function inspect(config, options)
    local diagnostics, inputs, cached = {}, {}, {}
    local function add(code, reason, file, path)
      diagnostics[#diagnostics + 1] = diagnostic.new(code, reason, { file = file, jsonPath = path })
    end
    local function finish(package)
      table.sort(diagnostics, function(a, b)
        for _, key in ipairs({ "file", "jsonPath", "code", "reason" }) do
          local av, bv = a[key] or "", b[key] or ""
          if av ~= bv then return av < bv end
        end
        return false
      end)
      table.sort(inputs, function(a, b) return a.path < b.path end)
      if package then
        package.contentId = sha256.hex(json.encode(json.array(inputs)))
      end
      local ok = true
      for _, item in ipairs(diagnostics) do if item.severity == "error" then ok = false end end
      return { ok = ok, package = package, diagnostics = diagnostics, inputs = inputs }
    end
    if type(config) ~= "table" or type(config.gameId) ~= "string" or config.gameId == ""
      or not profiles[config.engineProfile] or (config.sourceVersion ~= nil
      and (type(config.sourceVersion) ~= "string" or config.sourceVersion == "")) then
      add("E_CONFIG", "gameId, supported engineProfile, and optional nonempty sourceVersion are required")
      return finish(nil)
    end
    if type(options) ~= "table" or type(options.read) ~= "function" then
      add("E_CONFIG", "options.read(relativePath) is required")
      return finish(nil)
    end
    local function read(path)
      if cached[path] then return cached[path].bytes end
      local success, bytes, reason = pcall(options.read, path)
      cached[path] = {}
      if not success or type(bytes) ~= "string" then
        add("E_INPUT_READ", "Cannot read input: " .. tostring(success and (reason or "no bytes returned") or bytes), path)
        return nil
      end
      inputs[#inputs + 1] = { path = path, sha256 = sha256.hex(bytes), bytes = #bytes }
      if #bytes > maxBytes then
        add("E_SOURCE_SHAPE", "Input exceeds converter maxBytes guard (16777216)", path)
        return nil
      end
      cached[path].bytes = bytes
      return bytes
    end
    local function decode(bytes, path)
      local success, value = pcall(json.decode, bytes, { file = path, maxBytes = maxBytes,
        maxDepth = 128, maxItems = maxItems, maxStringBytes = 8 * 1024 * 1024 })
      if success then return value end
      if diagnostic.is(value) then
        if not value.file then value.file = path end
        diagnostics[#diagnostics + 1] = value
      else
        add("E_SOURCE_SHAPE", "JSON decoder failed: " .. tostring(value), path)
      end
      return nil
    end
    local package = json.object({ kind = "r2u.source-index", schemaVersion = 1, stage = "T0",
      gameId = config.gameId, engineProfile = config.engineProfile, sourceVersion = json.null,
      capabilities = json.object({ playable = false, publishable = false, assetsConverted = false }),
      database = json.object(), maps = json.array(), plugins = json.array(), extensionsLock = json.array() })
    local mapIds, seenMaps = {}, {}
    local function records(value, file, code, prefix)
      local seen, count = {}, 0
      for slot, record in ipairs(value) do
        if record ~= json.null then
          count = count + 1
          local path = (prefix or "$") .. "[" .. (slot - 1) .. "]"
          if not object(record) then
            add(code or "E_SOURCE_SHAPE", "Record must be an object or null", file, path)
          else
            if not integer(record.id) or record.id ~= slot - 1 then
              add("E_SOURCE_ID", "Record id must equal its zero-based source array slot", file, path .. ".id")
            end
            if record.id ~= nil then
              if seen[record.id] then add("E_SOURCE_ID", "Duplicate record id", file, path .. ".id") end
              seen[record.id] = true
            end
          end
        end
      end
      return count
    end
    for _, name in ipairs(names) do
      local file = "data/" .. name .. ".json"
      local bytes = read(file)
      local value = bytes and decode(bytes, file)
      if value ~= nil then
        if name == "System" then
          if not object(value) then add("E_SOURCE_SHAPE", "System must be an object", file, "$")
          else package.database[name] = json.object({ count = 1, records = value }) end
        elseif not json.is_array(value) then
          add("E_SOURCE_SHAPE", name .. " must be an array", file, "$")
        else
          package.database[name] = json.object({ count = records(value, file), records = value })
          if name == "MapInfos" then
            for slot, record in ipairs(value) do
              if object(record) and integer(record.id) and record.id > 0 and not seenMaps[record.id] then
                seenMaps[record.id] = true
                mapIds[#mapIds + 1] = record.id
              elseif object(record) and (not integer(record.id) or record.id <= 0) then
                add("E_SOURCE_ID", "Map id must be a positive integer", file, "$[" .. (slot - 1) .. "].id")
              end
            end
          end
        end
      end
    end
    table.sort(mapIds)
    if #mapIds > maxMaps then
      add("E_MAP_SHAPE", "Map count exceeds converter maxMaps guard (4096)", "data/MapInfos.json", "$")
    end
    for index = 1, math.min(#mapIds, maxMaps) do
      local id = mapIds[index]
      local file = string.format("data/Map%03d.json", id)
      local bytes = read(file)
      local map = bytes and decode(bytes, file)
      if map ~= nil then
        if not object(map) then add("E_MAP_SHAPE", "Map must be an object", file, "$")
        else
          local validSize = integer(map.width) and integer(map.height) and map.width > 0 and map.height > 0
          if not validSize then add("E_MAP_SHAPE", "Map dimensions must be positive integers", file, "$")
          elseif map.width > math.floor(maxTiles / 6 / map.height) then
            validSize = false
            add("E_MAP_SHAPE", "Map exceeds converter maxTiles guard (1000000)", file, "$.data")
          end
          if not json.is_array(map.data) then add("E_MAP_SHAPE", "Map data must be an array", file, "$.data")
          else
            if validSize and #map.data ~= 6 * map.width * map.height then
              add("E_MAP_SHAPE", "Map data length must equal 6 * width * height", file, "$.data")
            end
            for slot, tile in ipairs(map.data) do
              if not integer(tile) or tile < 0 then
                add("E_MAP_SHAPE", "Map data must contain nonnegative integers", file, "$.data[" .. (slot - 1) .. "]")
              end
            end
          end
          if not json.is_array(map.events) then add("E_MAP_SHAPE", "Map events must be an array", file, "$.events")
          else records(map.events, file, "E_MAP_SHAPE", "$.events") end
          local settings=json.object()
          for key,value in pairs(map) do
            if key~="data" and key~="events" and key~="width" and key~="height" then settings[key]=value end
          end
          package.maps[#package.maps + 1] = json.object({ id = id, width = map.width or json.null,
            height = map.height or json.null, tiles = map.data or json.null, events = map.events or json.null,
            settings = settings,
            sourceLocation = json.object({ file = file }) })
        end
      end
    end
    local pluginsFile = "js/plugins.js"
    local pluginBytes = read(pluginsFile)
    if pluginBytes then
      local source = pluginBytes:gsub("^%s*", "")
      while source:sub(1, 2) == "//" do
        local newline = source:find("\n", 1, true)
        source = newline and source:sub(newline + 1):gsub("^%s*", "") or ""
      end
      local literal = source:match("^var%s+%$plugins%s*=%s*(.-)%s*;%s*$")
      if not literal or literal:sub(1, 1) ~= "[" then
        add("E_PLUGINS_FORMAT", "Expected static var $plugins = JSON array; with only leading line comments", pluginsFile, "$")
      else
        local plugins = decode(literal, pluginsFile)
        if plugins == nil then
          add("E_PLUGINS_FORMAT", "Plugin initializer must be a static JSON array", pluginsFile, "$")
        else
          if not json.is_array(plugins) then add("E_PLUGINS_FORMAT", "Plugin list must be an array", pluginsFile, "$")
          else
            package.plugins = plugins
            for slot, plugin in ipairs(plugins) do
              local path = "$[" .. (slot - 1) .. "]"
              if not object(plugin) or type(plugin.name) ~= "string" or plugin.name == ""
                or type(plugin.status) ~= "boolean" or not object(plugin.parameters) then
                add("E_PLUGINS_FORMAT", "Plugin must have name string, status boolean, and parameters object", pluginsFile, path)
              end
              if object(plugin) and plugin.status == true then
                if not options.extensions or not options.extensions.acceptPlugin(plugin,read)then
                  add("E_PLUGIN_UNSUPPORTED", "No implemented adapter for enabled plugin " .. tostring(plugin.name), pluginsFile, path)
                end
              end
            end
          end
        end
      end
    end
    local coreFile = profiles[config.engineProfile]
    local core = read(coreFile)
    local sourceVersion = core and core_version(core)
    if not sourceVersion then
      add("E_SOURCE_VERSION", "Expected one top-level Utils.RPGMAKER_VERSION = quoted literal; assignment; dynamic or ambiguous versions are unsupported", coreFile)
    else
      package.sourceVersion = sourceVersion
      if config.sourceVersion and config.sourceVersion ~= sourceVersion then
        add("E_SOURCE_VERSION", "Configured sourceVersion differs from core literal " .. sourceVersion, coreFile)
      end
    end
    if options.extensions then
      package.extensions,package.extensionsLock=options.extensions.loadData(read,package)
      for _,input in ipairs(options.extensions.inputs())do inputs[#inputs+1]=input end
    end
    return finish(package)
  end
  return { inspect = inspect, coreVersion = core_version }
end
