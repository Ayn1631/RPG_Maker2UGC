return function(deps)
    local diagnostic = deps["contracts.diagnostic"]
    local json = deps["contracts.json"]
    local inspector = deps["converter.inspect"]
    local extensionRegistry=deps['sdk.registry']
    local events = deps["converter.events"]
    local audioCompiler = deps['converter.audio']
    local mapProgram=deps['converter.map_program']
    local resourceCompiler=deps['converter.resources']
    local world = deps["converter.world"]
    local rpg = deps["converter.rpg"]
    local ui = deps["converter.ui"]
    local uiSkin = deps["converter.ui_skin"]
    local uiArt = deps["converter.ui_art"]
    local uiFont = deps["converter.ui_font"]
    local uiTexts, fontFace, fallbackFace = deps['converter.ui_texts'], deps['converter.font_face'], deps['converter.font_fallback_face']
    local sourceText = deps['runtime.ui.source_text']
    local fontProgram = deps['converter.font_program']
    local actorProgram = deps['converter.actor_program']
    local partyProgram = deps['converter.party_program']
    local actionProgram = deps['converter.action_program']
    local enemyProgram,battleProgram = deps['converter.enemy_program'],deps['converter.battle_program']
    local uiLayout = deps["runtime.ui.rpg_layout"]
    local numberText = deps["runtime.ui.number_text"]
    local worldRuntime = deps["runtime.world.session"]
    local bundle = deps["build.bundle"]
    local files = deps["build.files"]
    local deploy = deps["build.deploy"]
    local projectInit=deps["build.project_init"]
    local verifier=deps["build.verify"]
    local releaseCheck=deps["build.release_check"]
    local sha256 = deps["build.sha256"]
    local M = { version = "0.5.0-ui-dev" }

    local function absolute(path)
        return path:match("^%a:[/\\]") ~= nil or path:match("^[/\\]") ~= nil
    end
    local function parse(args)
        local options = { command = args[1] }
        if not options.command or options.command == "--help" or options.command == "help" then
            options.command = "help"
            return options
        end
        if options.command ~= 'export-primitives' and options.command ~= "release-check" and options.command ~= "verify" and options.command ~= "init" and options.command ~= "inspect" and options.command ~= "build" and options.command ~= "deploy" and options.command ~= 'export-tiles' and options.command~='export-characters' then
            diagnostic.raise("E_CLI", "Available commands: init, inspect, build, deploy, verify, release-check, export-tiles, export-characters, export-primitives; use --help")
        end
        local index = 2
        while index <= #args do
            local flag = args[index]
            if flag == "--project" and options.command~="init" and not options.project then
                index = index + 1
                options.project = args[index]
                if not options.project or options.project:sub(1, 2) == "--" then
                    diagnostic.raise("E_CLI", "--project requires a path")
                end
            elseif options.command=='init' and ({['--source']='source',['--game-id']='gameId',['--profile']='profile',['--bindings']='bindings'})[flag] then
                local key=({['--source']='source',['--game-id']='gameId',['--profile']='profile',['--bindings']='bindings'})[flag]
                if options[key]then diagnostic.raise('E_CLI','Repeated argument: '..flag)end
                index=index+1;options[key]=args[index]
                if not options[key] or options[key]:sub(1,2)=='--'then diagnostic.raise('E_CLI',flag..' requires a value')end
            elseif options.command=='verify' and ({['--suite']='suite',['--case']='case',['--trace']='trace'})[flag]then
                local key=({['--suite']='suite',['--case']='case',['--trace']='trace'})[flag]
                if options[key]then diagnostic.raise('E_CLI','Repeated argument: '..flag)end
                index=index+1;options[key]=args[index]
                if not options[key] or options[key]=='' or options[key]:sub(1,2)=='--'then diagnostic.raise('E_CLI',flag..' requires a value')end
            elseif flag=='--target' and (options.command=='deploy' or options.command=='release-check') and not options.target then
                index=index+1;options.target=args[index]
                if not options.target or options.target:sub(1,2)=='--'then diagnostic.raise('E_CLI','--target requires a Lua file path')end
            elseif flag=='--evidence' and options.command=='release-check' and not options.evidence then
                index=index+1;options.evidence=args[index]
                if not options.evidence or options.evidence:sub(1,2)=='--'then diagnostic.raise('E_CLI','--evidence requires a path')end
            elseif flag == "--json" and not options.json then
                options.json = true
            elseif flag=='--tile-bindings' and not options.tileBindings and (options.command=='inspect' or options.command=='build' or options.command=='deploy') then
                index=index+1;options.tileBindings=args[index]
                if not options.tileBindings or options.tileBindings:sub(1,2)=='--'then diagnostic.raise('E_CLI','--tile-bindings requires a completed tile manifest')end
            elseif flag=='--character-bindings' and not options.characterBindings and (options.command=='inspect' or options.command=='build' or options.command=='deploy')then
                index=index+1;options.characterBindings=args[index]
                if not options.characterBindings or options.characterBindings:sub(1,2)=='--'then diagnostic.raise('E_CLI','--character-bindings requires a completed character manifest')end
            else
                diagnostic.raise("E_CLI", "Unknown or repeated argument: " .. tostring(flag))
            end
            index = index + 1
        end
        if options.command=='init'then
            if not options.source or not options.gameId then diagnostic.raise('E_CLI','init requires --source and --game-id')end
        elseif not options.project then diagnostic.raise("E_CLI", "--project is required") end
        if options.command=='verify' and (not options.suite and not options.trace or options.case and not options.suite)then diagnostic.raise('E_CLI','verify requires --suite or --trace; --case requires --suite')end
        if options.command=="deploy" and not options.target then diagnostic.raise("E_CLI","deploy requires --target")end
        return options
    end

    local function project_config(path)
        local chunk, reason = loadfile(path, "t", {})
        if not chunk then diagnostic.raise("E_CONFIG", tostring(reason), { file = path }) end
        local ok, config = pcall(chunk)
        if not ok or type(config) ~= "table" then
            diagnostic.raise("E_CONFIG", "Project must return a configuration table", { file = path })
        end
        local allowed = { uiPerformance=true, uiTemplateCatalog=true, displayLocale=true, gameAdapter=true, primitiveArt=true, gameId = true, sourceRoot = true, engineProfile = true, sourceVersion = true, eventPreview = true, worldPreview = true, fontBindings = true, audioBindings = true, assetBindings = true, extensions=true }
        for key in pairs(config) do
            if not allowed[key] then diagnostic.raise("E_CONFIG", "Unsupported configuration key: " .. tostring(key), { file = path }) end
        end
        if config.uiPerformance~=nil then
            local settings=config.uiPerformance
            local function reject(message)diagnostic.raise('E_CONFIG','uiPerformance: '..message,{file=path})end
            if type(settings)~='table'then reject('expected a table')end
            for key,value in pairs(settings)do
                if key=='overlay'then
                    if type(value)~='boolean'then reject('overlay must be boolean')end
                elseif key=='poolCapacity' or key=='poolIdleFrames'then
                    local low,high=key=='poolCapacity'and 0 or 1,key=='poolCapacity'and 2048 or 36000
                    if type(value)~='number'or value~=value or value%1~=0 or value<low or value>high then
                        reject(key..' must be an integer in '..low..'..'..high)
                    end
                else reject('unsupported key '..tostring(key))end
            end
        end
        if config.displayLocale~=nil and (config.gameAdapter~='visu' or config.displayLocale~='zh-CN')then
            diagnostic.raise('E_CONFIG','displayLocale currently supports zh-CN for the reviewed Visu sample only',{file=path})
        end
        if type(config.gameId) ~= "string" or not config.gameId:match("^[a-z][a-z0-9_-]*$")
            or #config.gameId > 64 or config.gameId:match("^com[1-9]$") or config.gameId:match("^lpt[1-9]$")
            or ({ con = true, prn = true, aux = true, nul = true })[config.gameId] then
            diagnostic.raise("E_CONFIG", "gameId must be a portable lowercase name (1-64 characters)", { file = path })
        end
        if type(config.sourceRoot) ~= "string" or config.sourceRoot == "" or config.sourceRoot:find("[%z\r\n]") then
            diagnostic.raise("E_CONFIG", "sourceRoot must be a nonempty directory path", { file = path })
        end
        if config.eventPreview~=nil and config.worldPreview~=nil then
            diagnostic.raise("E_CONFIG","Choose eventPreview or worldPreview",{file=path})
        end
        if config.eventPreview ~= nil or config.worldPreview ~= nil then
            local preview = config.eventPreview or config.worldPreview
            if type(preview) ~= "table" or (config.eventPreview and (type(preview.programId) ~= "string" or preview.programId == "")) then
                diagnostic.raise("E_CONFIG", "Preview requires valid template bindings", { file = path })
            end
            for key in pairs(preview) do
                local nativeKey=config.worldPreview and ({presentation=true,imageTemplate=true,cursorTemplate=true,containerTemplate=true,whiteImageId=true,windowPattern=true,renderMode=true,artTemplates=true})[key]
                if not nativeKey and (key ~= "programId" or not config.eventPreview) and (key ~= "actors" or not config.worldPreview) and key ~= "textTemplate" and key ~= "buttonTemplate" then
                    diagnostic.raise("E_CONFIG", "Unsupported preview key: " .. tostring(key), { file = path })
                end
            end
            if config.worldPreview and preview.actors~=nil and type(preview.actors)~="boolean" then
                diagnostic.raise("E_CONFIG", "worldPreview.actors must be a boolean", {file=path})
            end
            if config.worldPreview and preview.presentation~=nil and preview.presentation~='rpg-maker' and preview.presentation~='diagnostic' then
                diagnostic.raise('E_CONFIG','worldPreview.presentation must be rpg-maker or diagnostic',{file=path})
            end
            if config.worldPreview and preview.presentation=='rpg-maker' then
                if preview.renderMode==nil then preview.renderMode='platform' end
                if preview.renderMode~='platform' and preview.renderMode~='source' then
                    diagnostic.raise('E_CONFIG','renderMode must be platform or source',{file=path})
                end
                if preview.renderMode=='platform' then
                    if preview.windowPattern~=nil and preview.windowPattern~='simple' then diagnostic.raise('E_CONFIG','Platform windowPattern must be simple',{file=path})end
                    local valid,value=pcall(uiArt.validateTemplates,preview.artTemplates)
                    if not valid then diagnostic.raise('E_CONFIG',diagnostic.is(value) and value.reason or 'Invalid artTemplates',{file=path})end
                    preview.artTemplates=value
                elseif preview.artTemplates~=nil then diagnostic.raise('E_CONFIG','artTemplates requires platform renderMode',{file=path})
                elseif preview.windowPattern~=nil and preview.windowPattern~='source' and preview.windowPattern~='geometry' then
                    diagnostic.raise('E_CONFIG','Source windowPattern must be source or geometry',{file=path})
                end
                if preview.windowPattern=='geometry' and config.engineProfile~='mz-turn' then
                    diagnostic.raise('E_CONFIG','Geometry window pattern is an experimental MZ-only option',{file=path})
                end
                for _,key in ipairs({'containerTemplate','imageTemplate','cursorTemplate','whiteImageId'})do
                    local value=preview[key]
                    if type(value)~='number' or value%1~=0 or value<1 or value>2147483647 then diagnostic.raise('E_CONFIG','Native UI requires positive '..key..' binding',{file=path})end
                end
            elseif preview.imageTemplate~=nil or preview.cursorTemplate~=nil or preview.containerTemplate~=nil or preview.whiteImageId~=nil or preview.windowPattern~=nil or preview.renderMode~=nil or preview.artTemplates~=nil then
                diagnostic.raise('E_CONFIG','Image/cursor bindings require rpg-maker presentation',{file=path})
            end
            for _, key in ipairs({"textTemplate", "buttonTemplate"}) do
                local value = preview[key]
                if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 2147483647 then
                    diagnostic.raise("E_CONFIG", "preview." .. key .. " must be a positive template index", { file = path })
                end
            end
        end
        local parent = path:gsub("\\", "/"):match("^(.*)/") or "."
        if config.uiTemplateCatalog~=nil then
            if not files.relative(config.uiTemplateCatalog)then diagnostic.raise('E_CONFIG','uiTemplateCatalog must be a contained project-relative JSON path',{file=path})end
            config.uiTemplateCatalog=parent..'/'..config.uiTemplateCatalog
        end
        if not absolute(config.sourceRoot) then config.sourceRoot = parent .. "/" .. config.sourceRoot end
        if config.primitiveArt then
            local a=config.primitiveArt
            if type(a)~='table' or not files.relative(a.path) then diagnostic.raise('E_CONFIG','primitiveArt.path must be a contained project-relative Lua library')end
            for k in pairs(a)do if k~='path' and k~='sourceRoot' and k~='detail' and k~='tileCategories' and k~='mode'then diagnostic.raise('E_CONFIG','Unknown primitiveArt field '..tostring(k))end end
            if a.mode~=nil and a.mode~='composed' and a.mode~='sampled'then diagnostic.raise('E_CONFIG','primitiveArt.mode must be composed or sampled')end
            if not config.worldPreview or config.worldPreview.presentation~='rpg-maker' or config.worldPreview.renderMode=='source'then diagnostic.raise('E_CONFIG','Primitive artwork requires platform world presentation')end
            if a.sourceRoot~=nil then if type(a.sourceRoot)~='string'then diagnostic.raise('E_CONFIG','primitiveArt.sourceRoot must be a path')end;if not absolute(a.sourceRoot)then a.sourceRoot=parent..'/'..a.sourceRoot end end
            a.relative,a.projectRoot,a.path=a.path,parent,parent..'/'..a.path
        end
        if config.extensions then
            if type(config.extensions)~='table'then diagnostic.raise('E_CONFIG','extensions must be a list')end
            for _,entry in ipairs(config.extensions)do
                if type(entry)~='table' or type(entry.path)~='string'then diagnostic.raise('E_CONFIG','Extension path required')end
                if not absolute(entry.path)then entry.path=parent..'/'..entry.path end
            end
        end
        if config.fontBindings~=nil then
            local function reject(why)diagnostic.raise('E_CONFIG',why,{file=path})end
            if not config.worldPreview or config.worldPreview.presentation~='rpg-maker' or type(config.fontBindings)~='table' then reject('fontBindings requires rpg-maker presentation')end
            for k in pairs(config.fontBindings)do if k~='main'and k~='fallbacks'then reject('Unknown fontBindings field')end end
            local function binding(b)
                if type(b)~='table'then reject('Expected a font file binding')end
                for k in pairs(b)do if not ({path=true,location=true,scripts=true,license=true,licenseUrl=true})[k]then reject('Unknown font binding field')end end
                if type(b.path)~='string'or #b.path<1 or #b.path>4096 or b.path:find('[%z\r\n]')then reject('Expected a bounded font file path')end
                if not absolute(b.path)then b.path=parent..'/'..b.path end
                for _,k in ipairs({'license','licenseUrl'})do if b[k]~=nil and (type(b[k])~='string'or #b[k]>4096)then reject('Expected bounded font license metadata')end end
                local function tag(v)return type(v)=='string'and v:match('^[%g ][%g ][%g ][%g ]$')end
                if b.location~=nil then
                    if type(b.location)~='table'then reject('Font location must be an axis table')end
                    local count=0;for axis,value in pairs(b.location)do
                        if not tag(axis)or type(value)~='number'or value~=value or value< -32768 or value>=32768 then reject('Font axes need OpenType tags and finite design coordinates')end
                        count=count+1;if count>16 then reject('At most sixteen font axes are supported')end
                    end
                    if count==0 then reject('Variable font location requires explicit axis coordinates')end
                end
                if b.scripts~=nil then
                    if type(b.scripts)~='table'then reject('Font scripts must be an array')end
                    local count,high,seen=0,0,{};for k,value in pairs(b.scripts)do
                        if type(k)~='number'or k%1~=0 or k<1 or k>32 or not tag(value)or seen[value]then reject('Font scripts need unique OpenType tags in a dense array')end
                        seen[value]=true;count=count+1;high=math.max(high,k)
                    end
                    if count==0 or count~=high then reject('Font scripts need a nonempty dense array')end
                end
            end
            if config.fontBindings.main~=nil then binding(config.fontBindings.main)end
            local fs=config.fontBindings.fallbacks
            if fs~=nil then
                if type(fs)~='table'then reject('Expected fallback font array')end
                local count,high=0,0;for k in pairs(fs)do if type(k)~='number'or k%1~=0 or k<1 or k>8 then reject('Expected up to eight ordered fallback fonts')end;count=count+1;high=math.max(high,k)end
                if count~=high then reject('Fallback font array contains gaps')end
                for _,b in ipairs(fs)do binding(b)end
            end
        end
        return config
    end

    local function tool_identity(root)
        local records = {}
        local manifest = assert(loadfile(root .. "/tools/module_manifest.lua", "t", {}))()
        local paths = { "tools/bootstrap.lua", "tools/module_manifest.lua", "tools/r2u.lua" }
        for _, item in ipairs(manifest) do paths[#paths + 1] = "src/" .. item.id:gsub("%.", "/") .. ".lua" end
        table.sort(paths)
        for _, path in ipairs(paths) do
            local bytes, reason = files.read(root .. "/" .. path)
            if not bytes then diagnostic.raise("E_TOOL_READ", tostring(reason), { file = path }) end
            records[#records + 1] = { path = path, sha256 = sha256.hex(bytes:gsub("\r\n", "\n")) }
        end
        return { toolVersion = M.version, toolchain = json.array(records) }, manifest
    end

    local function runtime_manifest(definitions, generatedFont, generatedActor, generatedParty, generatedAction, generatedEnemy, generatedBattle, generatedMap, generatedExtension)
        local by_id, selected, modules = {}, {}, {}
        for _, item in ipairs(definitions) do by_id[item.id] = item end
        local function inject(owner,id,path,dependencies)
            by_id[id]={id=id,path=path,dependencies=dependencies}
            local original=by_id[owner];local joined={}
            for _,dependency in ipairs(original.dependencies)do joined[#joined+1]=dependency end
            joined[#joined+1]=id
            by_id[owner]={id=owner,dependencies=joined}
        end
        if generatedFont then
            inject('platform.ugc.rpg_preview','generated.ui_fonts',generatedFont.path,{'runtime.ui.source_text'})
        end
        if generatedActor then
            inject('runtime.world.session','generated.actor_program',generatedActor.path,generatedActor.dependencies)
        end
        if generatedParty then
            inject('runtime.world.session','generated.party_program',generatedParty.path,{'runtime.rpg.party'})
        end
        if generatedAction then
            inject('runtime.world.session','generated.action_program',generatedAction.path,{'runtime.rpg.action_resolver'})
        end
        if generatedEnemy then inject('runtime.world.session','generated.enemy_program',generatedEnemy.path,generatedEnemy.dependencies) end
        if generatedBattle then inject('runtime.world.session','generated.battle_program',generatedBattle.path,generatedBattle.dependencies) end
        if generatedMap then inject('runtime.world.session','generated.map_program',generatedMap.path,generatedMap.dependencies) end
        if generatedExtension then
            for _,item in ipairs(generatedExtension.modules)do by_id[item.id]=item end
            inject('runtime.world.session',generatedExtension.moduleId,generatedExtension.path,generatedExtension.dependencies)
        end
        local function include(id)
            if selected[id] then return end
            local definition = by_id[id]
            if not definition then diagnostic.raise("E_MODULE_MISSING", "Missing runtime module: " .. id) end
            selected[id] = true
            for _, dependency in ipairs(definition.dependencies) do include(dependency) end
            modules[#modules + 1] = { id = id, path = definition.path or "src/" .. id:gsub("%.", "/") .. ".lua",
                dependencies = definition.dependencies }
        end
        include("runtime.entry")
        return { entry = "runtime.entry", modules = modules }
    end

    local function world_execution(raw,program,party,action,battle)
        -- Only this explicit native execution contract may omit raw source data.
        -- The offline package and its nested World definitions stay untouched.
        local out={};for k,v in pairs(raw)do out[k]=v end
        out.database,out.maps,out.rpg=nil,nil,nil
        out.executionProjection={kind='r2u.actor-world-execution',schemaVersion=2,profile=program.profile}
        out.rpgInitialization='precompiled'
        out.rpgProgram={kind=program.kind,schemaVersion=program.schemaVersion,catalogVersion=program.catalogVersion,
            profile=program.profile,moduleId=program.moduleId}
        out.partyInitialization='precompiled'
        out.partyProgram={kind=party.kind,schemaVersion=party.schemaVersion,catalogVersion=party.catalogVersion,
            profile=party.profile,moduleId=party.moduleId}
        if action then
            out.actionInitialization='precompiled'
            out.actionProgram={kind=action.kind,schemaVersion=action.schemaVersion,catalogVersion=action.catalogVersion,
                profile=action.profile,moduleId=action.moduleId}
        end
        if battle then
            out.battleInitialization='precompiled'
            out.battleProgram={kind=battle.kind,schemaVersion=battle.schemaVersion,catalogVersion=battle.catalogVersion,
                profile=battle.profile,moduleId=battle.moduleId}
        end
        out.world={};for k,v in pairs(raw.world)do out.world[k]=v end
        out.world.definitions={};for k,v in pairs(raw.world.definitions)do out.world.definitions[k]=v end
        local fields={actors={'id'},items={'id','name','price','consumable','itypeId'},
            weapons={'id','name','price','etypeId','wtypeId','params'},armors={'id','name','price','etypeId','atypeId','params'}}
        for kind,keys in pairs(fields)do
            local records=json.array();out.world.definitions[kind]=records
            for _,source in ipairs(raw.world.definitions[kind])do
                local record={};for _,key in ipairs(keys)do record[key]=source[key]end
                records[#records+1]=record
            end
        end
        return out
    end

    function M.run(args, root)
        root = (root or "."):gsub("\\", "/"):gsub("/+$", "")
        local ok, result, code = pcall(function()
            local options = parse(args)
            if options.command == "help" then return { ok = true, command = "help", toolVersion = M.version }, 0 end
            if options.command=='init'then
                local bindings
                if options.bindings then bindings=project_config(absolute(options.bindings) and options.bindings or root..'/'..options.bindings)end
                return projectInit.create(root,options,bindings),0
            end
            local project_path = absolute(options.project) and options.project or root .. "/" .. options.project
            local config = project_config(project_path)
            if options.command=="verify"then return verifier.run(root,config,options)end
            if options.command=="release-check"then return releaseCheck.run(root,config,options)end
            local deployment=options.command=="deploy" and deploy.prepare(root,options.target,config.gameId) or nil
            local extensions=extensionRegistry.new(config.extensions,{read=files.read,profile=config.engineProfile})
            if config.gameAdapter then
                local adapter=config.gameAdapter=='aurora' and 'converter.aurora' or config.gameAdapter=='visu' and 'converter.visu'
                if not adapter then diagnostic.raise('E_CONFIG','Unknown gameAdapter: '..tostring(config.gameAdapter))end
                extensions=deps[adapter].wrap(extensions,config,root)
            end
            local inspected = inspector.inspect(config, {
                read = function(path) return files.read(files.join(config.sourceRoot, path)) end,
                extensions=extensions,
            })
            local report = {
                ok = inspected.ok, command = options.command, toolVersion = M.version, stage = "M1a",
                playable = false, publishable = false, gameId = config.gameId,
                diagnostics = json.array(inspected.diagnostics), inputs = json.array(inspected.inputs),
                package = inspected.package,
            }
            if not inspected.ok then return report, 1 end
            local compiled = events.compile(inspected.package,extensions)
            local generatedFont,generatedActor,generatedParty,generatedAction,generatedEnemy,generatedBattle,generatedMap
            report.ok, report.package = compiled.ok, compiled.package
            report.diagnostics = json.array(compiled.diagnostics)
            if not compiled.ok then return report, 1 end
            if options.command=='export-primitives' then
                local exported=deps['converter.primitive_art'].export(compiled.package,config)
                for key,value in pairs(exported)do report[key]=value end
                report.stage='offline-primitive-art';report.package=nil;return report,0
            end
            if (options.command=='build' or options.command=='inspect' or options.command=='deploy') and (not config.worldPreview or config.worldPreview.presentation~='rpg-maker') then
                for _,p in pairs(compiled.package.eventPrograms)do for _,ins in ipairs(p.instructions)do
                    if ins.op=='video'then diagnostic.raise('E_VIDEO_CONTEXT','Video replacements require RPG Maker world presentation',ins.source)end
                end end
            end
            if options.command=='export-tiles' or options.command=='export-characters' then
                local exporter=options.command=='export-tiles' and 'converter.tile_export' or 'converter.character_export'
                local exported=deps[exporter].export(compiled.package,config,root)
                for key,value in pairs(exported)do report[key]=value end
                report.stage=options.command=='export-tiles' and 'offline-tile-export' or 'offline-character-export';report.package=nil
                return report,0
            end
            if options.tileBindings then
                if not config.worldPreview then diagnostic.raise('E_TILE_BINDINGS','Tile bindings require worldPreview')end
                local path=absolute(options.tileBindings) and options.tileBindings or root..'/'..options.tileBindings
                local bytes,reason=files.read(path)
                if not bytes then diagnostic.raise('E_TILE_BINDINGS',tostring(reason),{file=path})end
                config.assetBindings=deps['converter.tile_export'].bind(json.decode(bytes),config.assetBindings)
                inspected.inputs[#inspected.inputs+1]={path=path,bytes=#bytes,sha256=sha256.hex(bytes)}
            end
            if options.characterBindings then
                if not config.worldPreview then diagnostic.raise('E_CHARACTER_BINDINGS','Character bindings require worldPreview')end
                local path=absolute(options.characterBindings) and options.characterBindings or root..'/'..options.characterBindings
                local bytes,reason=files.read(path)
                if not bytes then diagnostic.raise('E_CHARACTER_BINDINGS',tostring(reason),{file=path})end
                config.assetBindings=deps['converter.character_export'].bind(json.decode(bytes),config.assetBindings)
                inspected.inputs[#inspected.inputs+1]={path=path,bytes=#bytes,sha256=sha256.hex(bytes)}
            end
            if extensions.count()>0 and (not config.worldPreview or config.worldPreview.presentation~='rpg-maker')then diagnostic.raise('E_EXTENSION_CONTEXT','Extensions require RPG Maker world presentation')end
            local generatedExtension=extensions.generate('generated/'..config.gameId)
            if generatedExtension then generatedExtension.path='generated/'..config.gameId..'/extension-program.lua' end
            compiled.package.audio=audioCompiler.compile(compiled.package,config.audioBindings)
            if #compiled.package.audio.unbound>0 then
                report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_AUDIO_UNBOUND',reason='Audio is disabled until audioBindings is supplied: '..table.concat(compiled.package.audio.unbound,', ')}
            end
            if config.eventPreview then
                if not compiled.package.eventPrograms[config.eventPreview.programId] then
                    diagnostic.raise("E_CONFIG", "eventPreview references a missing event program", { file = project_path })
                end
                compiled.package.eventPreview = json.object(config.eventPreview)
            end
            if config.worldPreview then
                compiled.package.resources=resourceCompiler.compile(compiled.package,config.assetBindings,config.worldPreview.artTemplates)
                if #compiled.package.resources.unboundBushCharacters>0 then
                    report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_CHARACTER_BUSH_UNBOUND',reason='These character templates have no upper/lower bush frames: '..table.concat(compiled.package.resources.unboundBushCharacters,', ')}
                end
                if #compiled.package.resources.videoReplacements>0 then
                    report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_VIDEO_TEMPLATE_REPLACEMENT',reason='Explicit full-screen template sequences replace source video; no movie decoding or embedded movie audio: '..table.concat(compiled.package.resources.videoReplacements,', ')}
                end
                if config.worldPreview.presentation=='rpg-maker' then
                    local function sourceBytes(relative)
                        local bytes,reason=files.read(files.join(config.sourceRoot,relative))
                        if not bytes then diagnostic.raise('E_UI_ASSET_READ',tostring(reason),{file=relative})end
                        inspected.inputs[#inspected.inputs+1]={path=relative,bytes=#bytes,sha256=sha256.hex(bytes)}
                        return bytes
                    end
                    local platformMode=config.worldPreview.renderMode=='platform'
                    local opts={includePresentation=true,hostFont=platformMode,extensions=extensions}
                    if not platformMode and config.engineProfile=='mv-turn' then opts.mvFontCss=sourceBytes('fonts/gamefont.css')end
                    local normalized=ui.compile(inspected.package,opts)
                    for _,entry in ipairs(normalized.diagnostics)do report.diagnostics[#report.diagnostics+1]=entry end
                    if not normalized.ok then report.ok=false;return report,1 end
                    compiled.package.ui=normalized.ui
                    uiLayout.new(normalized.ui,function()return 0 end)
                    local skinPath=normalized.ui.window.skinPath
                    local success,skin=pcall(platformMode and uiSkin.compilePlatform or uiSkin.compile,sourceBytes(skinPath),normalized.ui)
                    if not success then
                        if diagnostic.is(skin)then skin.file=skinPath end
                        error(skin,0)
                    end
                    compiled.package.uiSkin=skin
                    if platformMode then
                        compiled.package.uiArt=uiArt.compilePlatform(normalized.ui,config.worldPreview.artTemplates)
                        if config.primitiveArt then
                            local path=config.primitiveArt.path;local bytes,reason=files.read(path)
                            if not bytes then diagnostic.raise('E_PRIMITIVE_ART',tostring(reason),{file=path})end
                            local chunk,err=load(bytes,'@'..path,'t',{});if not chunk then diagnostic.raise('E_PRIMITIVE_ART',err,{file=path})end
                            local library=chunk()
                            deps['converter.primitive_art'].apply(compiled.package,library)
                            if config.gameAdapter=='aurora'then report.assetAudit=deps['converter.aurora'].assets(compiled.package,library)end
                            inspected.inputs[#inspected.inputs+1]={path=path,bytes=#bytes,sha256=sha256.hex(bytes)}
                            report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_PRIMITIVE_ART_STYLE',reason='Explicit source-mapped primitive library; terrain geometry is static.'}
                        end
                        deps['converter.primitive_art'].validateResources(compiled.package)
                        normalized.ui.capabilities.mainFontImported=false;normalized.ui.capabilities.numberFontImported=false
                        compiled.package.uiRendering={renderMode='platform',mainFont='host',numberFont='host',windowPattern='simple',windowPatternApproximation=true,
                            sourcePixelDataPreserved=false,pixelFaithfulRender=false,fontHintingApplied=false,fontMetrics='host-approximation'}
                        report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_UI_PLATFORM_APPROXIMATION',reason='Platform text uses host fonts and approximate metrics; simplified window colors and UI art templates preserve layout without source pixel fidelity.'}
                    else
                    local patternMode=config.worldPreview.windowPattern or 'source'
                    if patternMode=='geometry' then
                        if not skin.patternGeometry then diagnostic.raise('E_UI_PATTERN_UNSUPPORTED','Source window pattern does not match the experimental geometry pattern',{file=skinPath})end
                        report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_UI_PATTERN_APPROXIMATION',file=skinPath,reason='Continuous diagonal strips approximate the source pixel pattern; raster edges differ. This is not lossless rendering.'}
                    end
                    compiled.package.uiRendering={renderMode='source',windowPattern=patternMode,windowPatternApproximation=patternMode=='geometry',sourcePixelDataPreserved=true,pixelFaithfulRender=false}
                    report.uiRendering=compiled.package.uiRendering
                    local artwork=uiArt.compile(config.sourceRoot,normalized.ui)
                    compiled.package.uiArt=artwork
                    for _,input in ipairs(artwork.sources) do
                        inspected.inputs[#inspected.inputs+1]={path=input.path,bytes=input.bytes,sha256=input.sha256}
                    end
                    local fontPath
                    if normalized.ui.profile=='mz-1.10.0' then
                        for _,asset in ipairs(normalized.ui.fonts.assets)do if asset.family=='rmmz-numberfont'then fontPath=asset.path end end
                    end
                    if fontPath then
                        local digits={};for cp=48,57 do digits[#digits+1]=cp end
                        compiled.package.uiFonts={gauge=uiFont.compile(sourceBytes(fontPath),{file=fontPath},digits)}
                        local gaugeFont=numberText.new(compiled.package.uiFonts.gauge)
                        -- Reject unsupported glyph/style budgets before exporting a
                        -- package that would fail while opening its first menu.
                        for digit=0,9 do gaugeFont.render(tostring(digit),{fontSize=normalized.ui.window.fontSize-6,lineHeight=24,width=128,strokeWidth=2})end
                        normalized.ui.capabilities.numberFontImported=true
                        compiled.package.uiRendering.numberFont='source-outline'
                        report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_UI_FONT_UNHINTED',file=fontPath,reason='Gauge digits use source outlines and advances. TrueType hinting and browser rasterization remain different.'}
                    else
                        normalized.ui.capabilities.numberFontImported=false
                        compiled.package.uiRendering.numberFont='host-provisional'
                        report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_UI_NUMBER_FONT_MAIN',reason='No dedicated number font is declared; gauge values use the imported main font chain.'}
                    end
                    compiled.package.uiRendering.fontHintingApplied=false
                    local demand=uiTexts.collect(normalized.ui,compiled.package.eventPrograms)
                    local bindings=config.fontBindings or {};local mainPath
                    local family=normalized.ui.profile=='mz-1.10.0'and 'rmmz-mainfont' or normalized.ui.fonts.mainFace
                    for _,asset in ipairs(normalized.ui.fonts.assets)do if asset.family==family then mainPath=asset.path end end
                    if not mainPath and not bindings.main then diagnostic.raise('E_UI_MAIN_FONT','Source UI main font needs an explicit file binding for '..normalized.ui.fonts.mainFace)end
                    local function compileFace(binding,cps,sourcePath)
                        local bytes,file
                        if sourcePath then bytes=sourceBytes(sourcePath);file=sourcePath
                        else
                            file=binding.path;local why;bytes,why=files.read(file)
                            if not bytes then diagnostic.raise('E_UI_ASSET_READ',tostring(why),{file=file})end
                            inspected.inputs[#inspected.inputs+1]={path=file,bytes=#bytes,sha256=sha256.hex(bytes),role='font-binding'}
                        end
                        local request={codepoints=cps,scripts=binding and binding.scripts or {'DFLT','latn','hani','kana'}}
                        local face
                        if binding and binding.location then request.location=binding.location;face=fallbackFace.compile(bytes,{file=file},request)
                        else face=fontFace.compile(bytes,{file=file},request)end
                        if binding then face.source.license=binding.license;face.source.licenseUrl=binding.licenseUrl end
                        return face
                    end
                    local main=compileFace(bindings.main,demand.codepoints,not bindings.main and mainPath or nil)
                    local chain,missing={},main.missing;if #main.mappings>0 then chain[1]=main end
                    for _,binding in ipairs(bindings.fallbacks or {})do
                        if #missing>0 then local face=compileFace(binding,missing);missing=face.missing;if #face.mappings>0 then chain[#chain+1]=face end end
                    end
                    if #missing>0 then diagnostic.raise('E_UI_FONT_COVERAGE','Source main font chain lacks '..#missing..' static characters; bind fallback files explicitly (first U+'..string.format('%04X',missing[1])..')',{file=main.source.file})end
                    local preflight=sourceText.new(chain)
                    for _,entry in ipairs(demand.texts)do
                        for line in (entry.text..'\n'):gmatch('(.-)\n')do preflight.measure(line,normalized.ui.window.fontSize)end
                    end
                    generatedFont=fontProgram.compile(chain)
                    generatedFont.path='generated/'..config.gameId..'/ui-fonts.lua'
                    compiled.package.uiFonts=compiled.package.uiFonts or {};compiled.package.uiFonts.main=chain
                    compiled.package.uiTextDemand=demand
                    normalized.ui.capabilities.mainFontImported=true
                    compiled.package.uiRendering.mainFont='source-outline';compiled.package.uiRendering.staticTextCoverage=true
                    compiled.package.uiRendering.mainFontInitialization='raw'
                    compiled.package.uiRendering.dynamicInputCovered=false;compiled.package.uiRendering.mainFontFaces=#chain
                    if not compiled.package.uiFonts.gauge then compiled.package.uiRendering.numberFont='source-main' end
                    report.diagnostics[#report.diagnostics+1]={severity='warning',code='W_UI_MAIN_FONT_UNHINTED',file=main.source.file,reason='Main UI uses imported source outlines and shared advances; any needed fallback comes from an explicit file binding. Hinting, browser rasterization and complete Unicode shaping are not implemented.'}
                    end
                    report.uiRendering=compiled.package.uiRendering
                    table.sort(inspected.inputs,function(a,b)return a.path<b.path end)
                end
                if config.worldPreview.actors then
                    local normalized=rpg.compile(compiled.package)
                    if not normalized.ok then report.ok=false;report.diagnostics=json.array(normalized.diagnostics);return report,1 end
                    compiled.package.rpg=normalized.rpg
                    compiled.package.capabilities.actorStateExecution=true
                end
                local normalized=world.compile(compiled.package)
                if not normalized.ok then report.ok=false; report.diagnostics=normalized.diagnostics; return report,1 end
                compiled.package.world=normalized.world
                generatedMap=mapProgram.compile(normalized.world)
                generatedMap.path='generated/'..config.gameId..'/map-program.lua'
                compiled.package.worldPreview=json.object(config.worldPreview)
                compiled.package.stage="M1b"
                compiled.package.capabilities.worldExecution=true
                if compiled.package.rpg then
                    -- Same pure initializer as the bundled runtime; reject missing
                    -- runtime contracts and invalid initial stats before any write.
                    local preflight=worldRuntime.new(compiled.package)
                    preflight.close()
                    if config.worldPreview.presentation=='rpg-maker' then
                        local presentation=compiled.package.ui and compiled.package.ui.presentationDefs
                        if type(presentation)~='table' or type(compiled.package.ui.equipmentTypes)~='table' then
                            diagnostic.raise('E_UI_PRESENTATION','Actor precompilation requires complete native presentation data')
                        end
                        for _,kind in ipairs({'actors','classes','weapons','armors','items'})do
                            if type(presentation[kind])~='table' then diagnostic.raise('E_UI_PRESENTATION','Missing native '..kind..' presentation data')end
                        end
                        generatedActor=actorProgram.compile(compiled.package.rpg)
                        generatedActor.path='generated/'..config.gameId..'/actor-program.lua'
                        generatedParty=partyProgram.compile(compiled.package.world.definitions,generatedActor.profile)
                        generatedParty.path='generated/'..config.gameId..'/party-program.lua'
                        if generatedActor.profile=='mz-1.10.0' or generatedActor.profile=='mv-1.5.1' then
                            local common={}
                            for _,event in ipairs(compiled.package.world.commonEvents)do
                                common[#common+1]={id=event.id,programId=event.programId}
                            end
                            generatedAction=actionProgram.compile(compiled.package.rpg,common)
                            generatedAction.path='generated/'..config.gameId..'/action-program.lua'
                            local hasBattle=false
                            for _,map in ipairs(compiled.package.world.maps)do
                                if map.settings.encounterList and #map.settings.encounterList>0 then hasBattle=true;break end
                            end
                            for _,event in pairs(compiled.package.eventPrograms)do for _,ins in ipairs(event.instructions)do
                                if ins.op=='battle'then hasBattle=true end
                            end end
                            if hasBattle then
                                generatedBattle=battleProgram.compile(compiled.package.rpg,compiled.package.eventPrograms)
                                generatedBattle.path='generated/'..config.gameId..'/battle-program.lua'
                                generatedEnemy=enemyProgram.compile(compiled.package.rpg)
                                generatedEnemy.path='generated/'..config.gameId..'/enemy-program.lua'
                            end
                        end
                    end
                end
            else
                local core={nop=true,["return"]=true,jump=true,branch=true,switches=true,variables=true,self_switch=true,wait=true,call=true,dialogue=true}
                for _,program in pairs(compiled.package.eventPrograms) do
                    for _,instruction in ipairs(program.instructions) do
                        local condition=instruction.condition
                        if not core[instruction.op] or (condition and condition.kind~="switch" and condition.kind~="variable" and condition.kind~="self_switch") then
                            diagnostic.raise("E_EVENT_CONTEXT_REQUIRED","This event requires worldPreview and a normalized world",instruction.source)
                        end
                    end
                end
            end
            for _,event in pairs(compiled.package.eventPrograms)do for _,ins in ipairs(event.instructions)do
                if ins.op=='battle' and not generatedBattle then diagnostic.raise('E_BATTLE_UNSUPPORTED','Battle requires precompiled RPG Maker presentation',ins.source)end
            end end
            if config.worldPreview or config.eventPreview then
                local path=config.uiTemplateCatalog or root..'/assets/client-ui-templates.json'
                local bytes,reason=files.read(path)
                if not bytes then diagnostic.raise('E_UI_TEMPLATE_CATALOG',tostring(reason),{file=path})end
                compiled.package.uiTemplates=deps['converter.ui_templates'].compile(compiled.package,json.decode(bytes))
                if config.uiPerformance then compiled.package.uiPerformance=json.object(config.uiPerformance)end
                inspected.inputs[#inspected.inputs+1]={path=path,bytes=#bytes,sha256=sha256.hex(bytes),role='client-ui-template-catalog'}
            end
            report.stage=compiled.package.stage
            if options.command == "inspect" then return report, 0 end
            local identity, definitions = tool_identity(root)
            -- Keep raw font inputs in the offline audit package only. The executable
            -- owns a private generated bank, never a second public mutable copy.
            local executablePackage=generatedActor and world_execution(compiled.package,generatedActor,generatedParty,generatedAction,generatedBattle) or compiled.package
            if config.gameAdapter=='aurora'then
                local projected={};for k,v in pairs(executablePackage)do if k~='database'and k~='maps'then projected[k]=v end end
                executablePackage=projected
            end
            if generatedMap then
                local projected={};for k,v in pairs(executablePackage)do projected[k]=v end;executablePackage=projected
                local projectedWorld={};for k,v in pairs(executablePackage.world)do if k~='maps' and k~='tilesets'then projectedWorld[k]=v end end
                executablePackage.world=projectedWorld
                executablePackage.mapInitialization='precompiled'
                executablePackage.mapProgram={kind=generatedMap.kind,schemaVersion=1,moduleId=generatedMap.moduleId}
            end
            if generatedFont then
                local projected={};for k,v in pairs(executablePackage)do projected[k]=v end;executablePackage=projected
                executablePackage.uiFonts={}
                for k,v in pairs(compiled.package.uiFonts) do if k~='main' then executablePackage.uiFonts[k]=v end end
                executablePackage.uiFonts.mainProgram={kind='r2u.font-program',schemaVersion=1,moduleId='generated.ui_fonts'}
                executablePackage.uiRendering={}
                for k,v in pairs(compiled.package.uiRendering) do executablePackage.uiRendering[k]=v end
                executablePackage.uiRendering.mainFontInitialization='precompiled'
            end
            report.uiRendering=executablePackage.uiRendering
            if generatedExtension then
                local projected={};for k,v in pairs(executablePackage)do projected[k]=v end;executablePackage=projected
                executablePackage.extensionInitialization='precompiled'
                executablePackage.extensionProgram={kind='r2u.extension-program',schemaVersion=1,moduleId=generatedExtension.moduleId}
            end
            local assembled = bundle.build(runtime_manifest(definitions,generatedFont,generatedActor,generatedParty,generatedAction,generatedEnemy,generatedBattle,generatedMap,generatedExtension), {
                read = function(path)
                    if generatedFont and path==generatedFont.path then return generatedFont.source end
                    if generatedActor and path==generatedActor.path then return generatedActor.source end
                    if generatedParty and path==generatedParty.path then return generatedParty.source end
                    if generatedAction and path==generatedAction.path then return generatedAction.source end
                    if generatedEnemy and path==generatedEnemy.path then return generatedEnemy.source end
                    if generatedBattle and path==generatedBattle.path then return generatedBattle.source end
                    if generatedMap and path==generatedMap.path then return generatedMap.source end
                    if generatedExtension then
                        if path==generatedExtension.path then return generatedExtension.source end
                        if generatedExtension.sources[path]then return generatedExtension.sources[path]end
                    end
                    return files.read(files.join(root, path))
                end,
                package = executablePackage, identity = identity,
            })
            local generated = "generated/" .. config.gameId .. "/"
            local dist = "dist/" .. config.gameId .. "/"
            report.buildId, report.sha256, report.output = assembled.buildId, assembled.sha256, dist .. "levelScript.lua"
            report.sourceMap, report.order = json.array(assembled.sourceMap), json.array(assembled.order)
            local precompilation
            if generatedFont or generatedActor or generatedParty or generatedAction or generatedMap then
                precompilation={}
                if generatedMap then precompilation.maps={moduleId=generatedMap.moduleId,path=generatedMap.path,sha256=sha256.hex(generatedMap.source),stats=generatedMap.stats}end
                if generatedFont then precompilation.mainFont={moduleId=generatedFont.moduleId,path=generatedFont.path,
                    sha256=sha256.hex(generatedFont.source),stats=generatedFont.stats}end
                if generatedActor then precompilation.actorRules={moduleId=generatedActor.moduleId,path=generatedActor.path,
                    sha256=sha256.hex(generatedActor.source),stats=generatedActor.stats}end
                if generatedParty then precompilation.party={moduleId=generatedParty.moduleId,path=generatedParty.path,
                    sha256=sha256.hex(generatedParty.source),stats=generatedParty.stats}end
                if generatedAction then precompilation.actions={moduleId=generatedAction.moduleId,path=generatedAction.path,
                    sha256=sha256.hex(generatedAction.source),stats=generatedAction.stats}end
                if generatedEnemy then precompilation.enemies={moduleId=generatedEnemy.moduleId,path=generatedEnemy.path,
                    sha256=sha256.hex(generatedEnemy.source),stats=generatedEnemy.stats}end
                if generatedBattle then precompilation.battle={moduleId=generatedBattle.moduleId,path=generatedBattle.path,
                    sha256=sha256.hex(generatedBattle.source),stats=generatedBattle.stats}end
            end
            local build_record = {
                stage = compiled.package.stage, artifactKind = config.worldPreview and "world-development-bundle" or "event-development-bundle", toolVersion = M.version,
                gameId = config.gameId, buildId = assembled.buildId, sha256 = assembled.sha256,
                engineProfile=config.engineProfile,sourceVersion=compiled.package.sourceVersion,diagnostics=json.array(report.diagnostics),
                playable = false, publishable = false, bytes = #assembled.source,
                sourceInputs = json.array(inspected.inputs), modules = json.array(assembled.order),
                uiRendering = executablePackage.uiRendering,
                precompilation = precompilation,
                rpgInitialization = executablePackage.rpgInitialization,
                partyInitialization = executablePackage.partyInitialization,
                actionInitialization = executablePackage.actionInitialization,
                battleInitialization = executablePackage.battleInitialization,
                extensionInitialization = executablePackage.extensionInitialization,
                extensionsLock = executablePackage.extensionsLock,
                executionProjection = executablePackage.executionProjection,
                validation = { lua53Syntax = "passed", eventCompile = "passed",
                    rpgDataCompile = compiled.package.rpg and "passed" or "not_run",
                    actionProgram = generatedAction and "passed" or "not_run",
                    enemyProgram = generatedEnemy and "passed" or "not_run",
                    battleProgram = generatedBattle and "passed" or "not_run",
                    uiDataCompile = compiled.package.ui and "passed" or "not_run",
                    uiSkinCompile = compiled.package.uiSkin and "passed" or "not_run",
                    uiArtCompile = compiled.package.uiArt and "passed" or "not_run",
                    uiArtTemplateBindings = compiled.package.uiArt and compiled.package.uiArt.renderMode=='platform' and "passed" or "not_run",
                    uiNumberFontCompile = compiled.package.uiFonts and compiled.package.uiFonts.gauge and "passed" or "not_run",
                    uiMainFontCompile = compiled.package.uiFonts and compiled.package.uiFonts.main and "passed" or "not_run",
                    uiMainFontProgram = generatedFont and "passed" or "not_run",
                    actorProgram = generatedActor and "passed" or "not_run",
                    partyProgram = generatedParty and "passed" or "not_run",
                    ugcRuntime = "not_run", rpgMakerPlaytest = "not_run" },
            }
            local items = {
                { path = root .. "/" .. generated .. "package.json", bytes = json.encode(compiled.package) .. "\n" },
                { path = root .. "/" .. generated .. "inputs.json", bytes = json.encode(json.array(inspected.inputs)) .. "\n" },
                { path = root .. "/" .. dist .. "reports/source-map.json", bytes = json.encode(json.array(assembled.sourceMap)) .. "\n" },
                { path = root .. "/" .. dist .. "reports/build.json", bytes = json.encode(build_record) .. "\n" },
                -- Install the executable file last; rollback on ordinary reported failures.
                { path = root .. "/" .. report.output, bytes = assembled.source },
            }
            if generatedFont then table.insert(items,#items,{path=root..'/'..generatedFont.path,bytes=generatedFont.source}) end
            if generatedActor then table.insert(items,#items,{path=root..'/'..generatedActor.path,bytes=generatedActor.source}) end
            if generatedParty then table.insert(items,#items,{path=root..'/'..generatedParty.path,bytes=generatedParty.source}) end
            if generatedAction then table.insert(items,#items,{path=root..'/'..generatedAction.path,bytes=generatedAction.source}) end
            if generatedEnemy then table.insert(items,#items,{path=root..'/'..generatedEnemy.path,bytes=generatedEnemy.source}) end
            if generatedBattle then table.insert(items,#items,{path=root..'/'..generatedBattle.path,bytes=generatedBattle.source}) end
            if generatedMap then table.insert(items,#items,{path=root..'/'..generatedMap.path,bytes=generatedMap.source}) end
            if generatedExtension then
                table.insert(items,#items,{path=root..'/'..generatedExtension.path,bytes=generatedExtension.source})
                local mapped=json.array()
                for _,row in ipairs(generatedExtension.sourceMap)do
                    for _,span in ipairs(assembled.sourceMap)do if span.moduleId==row.moduleId then
                        mapped[#mapped+1]={moduleId=row.moduleId,modulePath=row.path,moduleLine=row.line,bundleLine=span.startLine+row.line-1,file=row.file,jsonPath=row.jsonPath};break
                    end end
                end
                table.insert(items,#items,{path=root..'/'..dist..'reports/extension-source-map.json',bytes=json.encode(mapped)})
                table.insert(items,#items,{path=root..'/'..generated..'extension-lock.json',bytes=json.encode(compiled.package.extensionsLock)})
                for path,bytes in pairs(generatedExtension.sources)do table.insert(items,#items,{path=root..'/'..path,bytes=bytes})end
            end
            -- Output names are compiler-owned relative paths, never source paths.
            -- LuaFileSystem is already used by the offline asset exporters. Hosts
            -- without it can still build into explicitly prepared directories.
            local canCreate=pcall(require,'lfs')
            if canCreate then
                local directories={}
                for _,item in ipairs(items)do
                    local relative=item.path:sub(#root+2);local directory=relative:match('^(.*)/[^/]+$')
                    if directory and not directories[directory]then files.mkdirs(root,directory);directories[directory]=true end
                end
            end
            report.cleanupNotes = json.array(files.commit(items))
            if deployment then
                local receipt,notes=deploy.install(deployment,assembled.source,{buildId=assembled.buildId,sha256=assembled.sha256})
                report.deployment=receipt
                for _,note in ipairs(notes)do report.cleanupNotes[#report.cleanupNotes+1]=note end
            end
            return report, 0
        end)
        if not ok then
            local err = diagnostic.is(result) and result
                or diagnostic.new("E_INTERNAL", tostring(result))
            return { ok = false, stage = "M1a", playable = false, publishable = false,
                diagnostics = json.array({ err }) }, 1
        end
        return result, code
    end

    return M
end
