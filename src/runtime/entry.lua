-- Event sessions are executable offline; a UGC world/UI adapter is still required.
return function(deps)
    local events = deps["runtime.world.events"]
    local event_preview = deps["platform.ugc.event_preview"]
    local world_preview = deps["platform.ugc.world_preview"]
    local rpg_preview = deps["platform.ugc.rpg_preview"]
    local world = deps["runtime.world.session"]
    local presentationModule=deps['runtime.presentation']
    local audioModule,audioPlatform=deps['runtime.audio'],deps['platform.ugc.audio']
    local lifecycleModule=deps['platform.ugc.ui_lifecycle']
    local package_data, build_id, host, preview, started, pending
    local audio,uiLifecycle,performance
    local M = {}

    function M.configure(data, identity)
        if type(data) ~= "table" or data.kind ~= "r2u.event-package" or data.schemaVersion ~= 1
            or (data.stage ~= "M1a" and data.stage ~= "M1b") or type(data.capabilities) ~= "table"
            or data.capabilities.playable ~= false or data.capabilities.publishable ~= false
            or data.capabilities.eventExecution ~= true or type(data.eventPrograms) ~= "table"
            or type(identity) ~= "string" then
            error({ severity = "error", code = "E_RUNTIME_CONFIG", reason = "Invalid M1a event package" }, 0)
        end
        package_data, build_id = data, identity
    end

    function M.attachHost(context) host = context;uiLifecycle=nil end

    function M.OnInit()
        if not package_data then
            error({ severity = "error", code = "E_RUNTIME_CONFIG", reason = "Event package is not configured" }, 0)
        end
        return build_id
    end

    function M.createSession(options)
        M.OnInit()
        if package_data.audio then
            options=options or {};local nextOptions={};for k,v in pairs(options)do nextOptions[k]=v end;options=nextOptions
            if not audio then audio=audioModule.new(package_data.audio,host and audioPlatform.emitter(host) or function()end)end
            local handlers={};for k,v in pairs(options.commandHandlers or {})do handlers[k]=v end
            handlers.audio=audio.command;options.commandHandlers=handlers
        end
        return events.new(package_data, options)
    end
    function M.createWorld(options)
        M.OnInit()
        if package_data.audio then
            options=options or {};local nextOptions={};for k,v in pairs(options)do nextOptions[k]=v end;options=nextOptions
            if not audio then audio=audioModule.new(package_data.audio,host and audioPlatform.emitter(host) or function()end)end
            options.audio=options.audio or audio
        end
        options=options or {}
        if package_data.visuWorld and not options.signal then options.signal=function(name,value)
            if not host or not host.game or type(host.game.ServerSignal)~='function'then
                error({code='E_VISU_SIGNAL',reason='UGC ServerSignal is required for '..name},0)
            end
            local signal=host.game.ServerSignal(name);signal:AddString(value);signal:SendSignal()
        end end
        options.presentation=options.presentation or presentationModule.new(package_data.resources or {},options.audio)
        return world.new(package_data,options)
    end

    function M.OnStart()
        M.OnInit()
        if preview or pending then return end
        if not host or not host.game or not host.Enum or not host.Color or not host.script
            or not host.script.object or type(host.script.EnableUpdate)~='function' then
            error({severity='error',code='E_PLATFORM_NOT_CONFIGURED',reason='UI requires a host with an update lifecycle'},0)
        end
        if not uiLifecycle then uiLifecycle=lifecycleModule.new(host,package_data.uiTemplates,package_data.uiPerformance);host=uiLifecycle.host end
        uiLifecycle.setEnabled(true)
        -- Every exported preview mode allocates exclusively inside OnUpdate.
        local ok,reason=pcall(function()host.script:EnableUpdate(true)end)
        if not ok then
            pcall(function()host.script:EnableUpdate(false)end)
            error(reason,0)
        end
        pending=true
        started = true
    end

    function M.OnUpdate(dt)
        if not uiLifecycle then return end
        uiLifecycle.beginFrame()
        local clock=package_data.uiPerformance and package_data.uiPerformance.overlay and host.clock
        local before=clock and clock()
        local ok,result=pcall(function()
            if audio then audio.tick(dt or 0)end
            if pending then
                pending=false
                if package_data.worldPreview and package_data.worldPreview.presentation=='rpg-maker'then
                    preview=rpg_preview.open(host,package_data,build_id,M.createWorld)
                elseif package_data.worldPreview then preview=world_preview.open(host,package_data,build_id,M.createWorld)
                else preview=event_preview.open(host,package_data,build_id,M.createSession)end
                if package_data.uiPerformance and package_data.uiPerformance.overlay then
                    local binding=package_data.worldPreview or package_data.eventPreview
                    performance=deps['platform.ugc.ui_performance'].open(host,binding.textTemplate,uiLifecycle)
                end
            end
            if preview then preview.update(dt)end
            -- Same allowance as any renderer flush earlier in this host frame.
            -- This also drains cleanup after a preview has been closed.
            uiLifecycle.flush()
            if performance then performance.update(dt,before and math.max(0,clock()-before))end
        end)
        if not ok then
            -- A deferred native setter/clone can fail after preview.open has
            -- returned. Retire that preview too; preserve the original error.
            if preview then pcall(preview.close,true);preview=nil end
            if performance then pcall(performance.close);performance=nil end
            if audio then pcall(audio.close);audio=nil end
            uiLifecycle.setEnabled(false)
            if host and host.script and host.script.alive then pcall(function()host.script:EnableUpdate(false)end)end
        end
        uiLifecycle.endFrame()
        if not ok then error(result,0)end
    end
    function M.uiControlStats()return uiLifecycle and uiLifecycle.stats() or nil end
    function M.uiPerformanceStats()return performance and performance.stats() or nil end

    local function cancelPending()
        if not pending then return end
        pending=false
        if host and host.script and host.script.alive then host.script:EnableUpdate(false)end
    end

    function M.OnDisable()
        cancelPending()
        if preview then preview.close(true); preview = nil end
        if performance then performance.close();performance=nil end
        if uiLifecycle then uiLifecycle.setEnabled(false)end
        if audio then audio.close();audio=nil end
    end

    function M.OnEnable()
        if started and not preview then M.OnStart() end
    end

    function M.OnDestroy()
        cancelPending()
        if preview then preview.close(false); preview = nil end
        if performance then performance.close(false);performance=nil end
        if uiLifecycle then uiLifecycle.setEnabled(false)end
        if audio then audio.close();audio=nil end
        -- The engine owns destroying its script root. Never bulk-destroy an
        -- exported UI subtree from OnDestroy outside the frame allowance.
        started, host,uiLifecycle = false,nil,nil
    end

    return M
end
