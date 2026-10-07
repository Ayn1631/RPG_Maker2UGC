-- Owns the current map, shared story/party state and source event triggers.
return function(deps)
    local mapModule,pagesModule=deps["runtime.world.map"],deps["runtime.world.pages"]
    local eventModule,stateModule=deps["runtime.world.events"],deps["runtime.core.state"]
    local partyModule=deps["runtime.rpg.party"]
    local actorsModule,rngModule=deps["runtime.rpg.actors"],deps["runtime.core.rng"]
    local movementModule=deps['runtime.world.movement']
    local mapEffectsModule=deps['runtime.rpg.map_effects']
    local dialogueModule=deps['runtime.ui.dialogue']
    local M={};local sessionSerial=0
    local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
    local function copy(value)
        if type(value)~="table" then return value end
        local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
    end
    local function integer(value) return type(value)=="number" and value==value and value>=-9007199254740991 and value<=9007199254740991 and value%1==0 end
    local function active(task) return task and (task.status=="RUNNING" or task.status=="WAITING") end
    local function actorProgram(data)
        local initialization,descriptor,projection=rawget(data,"rpgInitialization"),rawget(data,"rpgProgram"),rawget(data,"executionProjection")
        if initialization==nil and descriptor==nil and projection==nil
            and rawget(data,"partyInitialization")==nil and rawget(data,"partyProgram")==nil then return nil end
        local function reject(reason) fail("E_WORLD_ACTOR_PROGRAM",reason) end
        local function plain(value,name)
            if type(value)~="table" or getmetatable(value)~=nil then reject(name.." must be a plain table") end
        end
        local function header(value,allowed,name)
            plain(value,name)
            for key in next,value do
                if type(key)~="string" then reject("Invalid "..name.." field key") end
                if not allowed[key] then reject("Unknown "..name.." field: "..key) end
            end
        end
        plain(data,"Marked package")
        header(descriptor,{kind=true,schemaVersion=true,catalogVersion=true,profile=true,moduleId=true},"Actor descriptor")
        if descriptor.kind~="r2u.actor-program" or descriptor.schemaVersion~=1 or descriptor.catalogVersion~=2
            or descriptor.moduleId~="generated.actor_program" then reject("Unsupported Actor descriptor header") end
        local profile=descriptor.profile
        if profile~="mv-1.5.1" and profile~="mz-1.10.0" then reject("Unsupported Actor profile") end
        if initialization~="precompiled" then reject("Actor initialization must be precompiled") end
        header(projection,{kind=true,schemaVersion=true,profile=true},"Execution projection")
        if projection.kind~="r2u.actor-world-execution" or (projection.schemaVersion~=1 and projection.schemaVersion~=2)
            or projection.profile~=profile then reject("Invalid execution projection header") end
        local service=deps["generated.actor_program"]
        plain(service,"Actor program service")
        if service.kind~=descriptor.kind or service.schemaVersion~=1 or service.catalogVersion~=2
            or service.profile~=profile or type(service.newActors)~="function" then reject("Invalid Actor program service header or factory") end
        local ui=rawget(data,"ui");plain(ui,"Native UI")
        if rawget(ui,"profile")~=profile then reject("Native UI profile differs from Actor program") end
        local presentation=rawget(ui,"presentationDefs");plain(presentation,"Native presentation definitions")
        for _,name in ipairs({"actors","classes","items","weapons","armors"}) do plain(rawget(presentation,name),"Presentation "..name) end
        plain(rawget(ui,"equipmentTypes"),"Source equipment types")
        local rpg=rawget(data,"rpg")
        if rpg~=nil then plain(rpg,"Raw RPG data");if rawget(rpg,"profile")~=profile then reject("Raw RPG profile differs from Actor program") end end
        return service
    end
    local function partyProgram(data,actorService)
        if not actorService then return nil end
        local initialization,descriptor=rawget(data,"partyInitialization"),rawget(data,"partyProgram")
        local function reject(reason) fail("E_WORLD_PARTY_PROGRAM",reason) end
        if data.executionProjection.schemaVersion==1 then
            if initialization~=nil or descriptor~=nil then reject("Party programs require execution projection 2") end
            return nil
        end
        local function plain(value,name)
            if type(value)~="table" or getmetatable(value)~=nil then reject(name.." must be a plain table") end
        end
        plain(descriptor,"Party descriptor")
        local allowed={kind=true,schemaVersion=true,catalogVersion=true,profile=true,moduleId=true}
        for key in next,descriptor do
            if type(key)~="string" or not allowed[key] then reject("Unknown Party descriptor field") end
        end
        if initialization~="precompiled" or descriptor.kind~="r2u.party-program" or descriptor.schemaVersion~=1
            or descriptor.catalogVersion~=1 or descriptor.moduleId~="generated.party_program"
            or descriptor.profile~=actorService.profile then reject("Unsupported Party descriptor header") end
        local service=deps["generated.party_program"]
        plain(service,"Party program service")
        if service.kind~=descriptor.kind or service.schemaVersion~=1 or service.catalogVersion~=1
            or service.profile~=descriptor.profile or type(service.newParty)~="function" then reject("Invalid Party program service header or factory") end
        return service
    end
    local function actionProgram(data,actor,party)
        local marker,descriptor=rawget(data,'actionInitialization'),rawget(data,'actionProgram')
        if marker==nil and descriptor==nil then return nil end
        local function reject(reason) fail('E_WORLD_ACTION_PROGRAM',reason) end
        if not actor or not party or (actor.profile~='mv-1.5.1' and actor.profile~='mz-1.10.0') or marker~='precompiled' then reject('Actions require supported Actor and Party programs') end
        if type(descriptor)~='table' or getmetatable(descriptor)~=nil then reject('Action descriptor must be plain') end
        local allowed={kind=true,schemaVersion=true,catalogVersion=true,profile=true,moduleId=true}
        for k in next,descriptor do if not allowed[k]then reject('Unknown action descriptor field')end end
        if descriptor.kind~='r2u.action-program' or descriptor.schemaVersion~=1 or descriptor.catalogVersion~=1
            or descriptor.profile~=actor.profile or descriptor.moduleId~='generated.action_program' then reject('Invalid action descriptor')end
        local service=deps['generated.action_program']
        if type(service)~='table' or getmetatable(service)~=nil or service.kind~=descriptor.kind or service.schemaVersion~=1
            or service.catalogVersion~=1 or service.profile~=descriptor.profile or type(service.actions)~='table'
            or getmetatable(service.actions)~=nil then reject('Invalid action service')end
        for _,method in ipairs({'canUse','canApply','resolve','describe'})do
            if type(service.actions[method])~='function'then reject('Missing action method: '..method)end
        end
        return service.actions
    end
    function M.new(data,options)
        options=options or {}
        if type(data)~="table" then fail("E_WORLD_PACKAGE","Normalized world is required") end
        local marked=rawget(data,"rpgInitialization")~=nil or rawget(data,"rpgProgram")~=nil or rawget(data,"executionProjection")~=nil
            or rawget(data,"partyInitialization")~=nil or rawget(data,"partyProgram")~=nil
            or rawget(data,'actionInitialization')~=nil or rawget(data,'actionProgram')~=nil
        local world=rawget(data,"world")
        if not marked then world=data.world end
        if type(world)~="table" then fail("E_WORLD_PACKAGE","Normalized world is required") end
        local program=actorProgram(data)
        local partyService=partyProgram(data,program)
        local actions=actionProgram(data,program,partyService)
        local battleService
        if rawget(data,'battleInitialization')~=nil or rawget(data,'battleProgram')~=nil then
            local descriptor=rawget(data,'battleProgram');battleService=deps['generated.battle_program']
            local function reject()fail('E_WORLD_BATTLE_PROGRAM','Invalid precompiled battle program contract')end
            if data.battleInitialization~='precompiled' or not program or not partyService or not actions
                or type(descriptor)~='table' or getmetatable(descriptor)~=nil then reject()end
            for key in pairs(descriptor)do if key~='kind' and key~='schemaVersion' and key~='catalogVersion' and key~='profile' and key~='moduleId'then reject()end end
            if descriptor.kind~='r2u.battle-program' or descriptor.schemaVersion~=1 or descriptor.catalogVersion~=1
                or descriptor.profile~=program.profile or descriptor.moduleId~='generated.battle_program' then reject()end
            if type(battleService)~='table' or getmetatable(battleService)~=nil or battleService.kind~=descriptor.kind
                or battleService.schemaVersion~=1 or battleService.catalogVersion~=1 or battleService.profile~=descriptor.profile
                or type(battleService.newBattle)~='function' or type(battleService.hasTroop)~='function'then reject()end
        end
        local definitions
        if not partyService then
            definitions={}
            for _,kind in ipairs({"items","weapons","armors","actors"}) do
                definitions[kind]={}
                for _,record in ipairs(world.definitions[kind]) do definitions[kind][record.id]=copy(record) end
            end
        end
        local story=stateModule.new(options.story)
        local timer=deps['runtime.core.timer'].new(data.engineProfile)
        if options.presentation and options.presentation.bindStory then options.presentation.bindStory(story)end
        local partyState=copy(options.party or world.party)
        if not options.party and partyState.initialEquipment then
            partyState.equipment={}
            for _,record in ipairs(partyState.initialEquipment) do partyState.equipment[record.actorId]=record.slots end
            partyState.initialEquipment=nil
        end
        local party
        if partyService then party=partyService.newParty({state=partyState,equipmentPolicy=options.equipmentPolicy})
        else party=partyModule.new(definitions,{state=partyState,equipmentPolicy=options.equipmentPolicy}) end
        local actors,rngState
        if program or data.rpg then
            rngState=rngModule.restore(options.rngState or rngModule.new(1).snapshot()).snapshot()
            if program then actors=program.newActors(party,{state=options.actors})
            else actors=actorsModule.new(data.rpg,{party=party,profile=data.rpg.profile,state=options.actors}) end
        elseif options.actors then fail("E_WORLD_ACTORS","Actor state requires compiled RPG data") end
        local mapEffects
        if program then mapEffects=program.mapEffects
        elseif actors and data.rpg and mapEffectsModule then mapEffects=mapEffectsModule.new(data.rpg)end
        local screenWidth=data.ui and data.ui.screen and data.ui.screen.width or 816
        local screenHeight=data.ui and data.ui.screen and data.ui.screen.height or 624
        local tileSize=data.resources and data.resources.tileSize or 48
        local mapService
        if data.mapInitialization~=nil or data.mapProgram~=nil then
            local descriptor=data.mapProgram;mapService=deps['generated.map_program']
            if data.mapInitialization~='precompiled' or type(descriptor)~='table' or descriptor.kind~='r2u.map-program'
                or descriptor.schemaVersion~=1 or descriptor.moduleId~='generated.map_program'
                or type(mapService)~='table' or type(mapService.get)~='function' or type(mapService.newMap)~='function'then
                fail('E_WORLD_MAP_PROGRAM','Invalid compiled map service')
            end
        end
        local maps={};if not mapService then for _,definition in ipairs(world.maps)do maps[definition.id]=copy(definition)end end
        sessionSerial=sessionSerial+1;if sessionSerial>9007199254740991 then fail('E_WORLD_BATTLE_ID','World session identity exhausted')end
        local sessionId=sessionSerial;local battleSequence=0;local battle,battleOwner,gameOver
        local sceneRequest,sceneSequence=nil,0
        local actorNames,actorText,actorImages={},{},{};local titleActive=options.startAtTitle==true
        local battleCommandMemory={}
        local settings={alwaysDash=false,commandRemember=false,bgmVolume=100,bgsVolume=100,meVolume=100,seVolume=100}
        for name,value in pairs(options.settings or {})do
            if settings[name]==nil then fail('E_WORLD_SETTING','Unknown setting')end
            if name=='alwaysDash' or name=='commandRemember' then
                if type(value)~='boolean'then fail('E_WORLD_SETTING','Boolean setting required')end
            elseif not integer(value) or value<0 or value>100 then fail('E_WORLD_SETTING','Volume must be an integer from 0 to 100')end
            settings[name]=value
        end
        if options.audio then
            for _,channel in ipairs({'bgm','bgs','me','se'})do options.audio.setVolume(channel,settings[channel..'Volume'])end
        end
        local current,map,player,eventStates,mainTask,vm,movement,collides,camera,mapOptions
        local function covers(event,p,x,y)
            local h=p.visuHitbox
            if h then return x>=event.x-h.left and x<=event.x+h.right and y>=event.y-h.up and y<=event.y+h.down end
            return event.x==x and event.y==y
        end
        local windowTone=copy(data.ui and data.ui.window and data.ui.window.tone or {0,0,0,0})
        local lastActionData={0,0,0,0,0,0}
        local mapName={enabled=true,remaining=150,opacity=0,name=''}
        local battleBackground={name1='',name2=''}
        local visu
        local scrollWaits={}
        local followers,followersVisible,gathering={},world.followersVisible~=false,false
        local vehicles,vehiclePhase={},nil
        for _,kind in ipairs({'boat','ship','airship'})do
            local source=world.vehicles and world.vehicles[kind]or {}
            vehicles[kind]={kind=kind,mapId=source.startMapId or 0,x=source.startX or 0,y=source.startY or 0,
                realX=source.startX or 0,realY=source.startY or 0,direction=4,speed=kind=='boat'and 4 or kind=='ship'and 5 or 6,
                image={tileId=0,characterName=source.characterName or '',characterIndex=source.characterIndex or 0},bgm=copy(source.bgm),altitude=0,driving=false,walkAnime=false,stepAnime=false}
            if movementModule then movementModule.initialize(vehicles[kind])end
        end
        local encounterCount,encountersEnabled=nil,true
        local routeWaits,gatherWaits={},{}
        local commandSequence=0
        local mapMessage
        local parallelCommon,errors,steps={}, {},0
        local reservedCommon={}
        local itemInfoCache,actorQueryCache={},{}
        local function invalidateItems()itemInfoCache,actorQueryCache={},{}end
        local failedPrograms,reported,owners,closed={},{},{},false
        local S={}
        local extensionRuntime,extensionMessages=nil,{}
        local aurora,auroraWait,auroraTransfer
        local function pruneExtensionMessages()
            for i=#extensionMessages,1,-1 do
                local entry=extensionMessages[i]
                if not entry.alive(entry.token)then table.remove(extensionMessages,i)end
            end
        end
        if data.extensionInitialization~=nil then
            local descriptor=data.extensionProgram
            if data.extensionInitialization~='precompiled' or type(descriptor)~='table' or descriptor.kind~='r2u.extension-program' or descriptor.schemaVersion~=1 or descriptor.moduleId~='generated.extension_program'then fail('E_EXTENSION_RUNTIME','Invalid compiled extension descriptor')end
            extensionRuntime=deps['sdk.runtime'].new(deps['generated.extension_program'],data.extensions)
        end
        local transfer
        local playFrames,wins,escapes=0,0,0
        local access={menu=true,formation=true}
        local function accessCommand(ins)
            if access[ins.target]==nil or type(ins.enabled)~='boolean'then fail('E_WORLD_ACCESS','Invalid system access command')end
            access[ins.target]=ins.enabled;return{kind='continue'}
        end
        local function random(upper,purpose)
            local rng=rngModule.restore(rngState or options.rngState or rngModule.new(1).snapshot())
            local value=rng.nextInt(upper,purpose);rngState=rng.snapshot();return value
        end
        local function unitRandom(purpose)
            local rng=rngModule.restore(rngState or options.rngState or rngModule.new(1).snapshot())
            local value=rng.nextUnit(purpose);rngState=rng.snapshot();return value
        end
        local function resetEncounterCount()
            local list=current.settings and current.settings.encounterList
            if type(list)=='table'and #list>0 then
                local n=math.max(1,current.settings.encounterStep or 30)
                encounterCount=random(n,'world.encounter.count1')+random(n,'world.encounter.count2')+1
                if extensionRuntime then encounterCount=extensionRuntime.policy('world.encounterSteps',{mapId=current.id,baseSteps=encounterCount},encounterCount)end
            else encounterCount=nil end
        end
        local function encounterTroop()
            local list=current.settings and current.settings.encounterList or {};local selected,total={},0;local region=map.regionId(player.x,player.y)
            for _,e in ipairs(list)do
                local meets=#e.regionSet==0;for _,id in ipairs(e.regionSet)do if id==region then meets=true end end
                if meets and e.weight>0 then selected[#selected+1]=e;total=total+e.weight end
            end
            if total==0 then return 0 end
            local value=random(total,'world.encounter.troop')
            for _,e in ipairs(selected)do value=value-e.weight;if value<0 then return e.troopId end end
            return 0
        end
        local function partyAbility(id)
            if not actors or type(actors.actionContext)~='function'then return false end
            local ctx=actors.actionContext()
            for i,actorId in ipairs(party.members())do
                if i>4 then break end
                local q=ctx.query({kind='actor',id=actorId})
                if not q.hidden and q.traits.partyAbility(id)then return true end
            end
            return false
        end
        local function retire(id)
            vm.release(id); owners[id],reported[id]=nil,nil
        end
        local function cancel(id)
            vm.cancel(id); retire(id)
        end
        local function page(event) return event.page and event.definition.pages[event.page] or nil end
        local services={getSwitch=story.getSwitch,getVariable=story.getVariable,getSelfSwitch=story.getSelfSwitch,
            hasItem=function(...)return party.hasItem(...)end,hasActor=function(...)return party.hasActor(...)end}
        local function refreshCharacterBush(c)
            if not movementModule or not map then return end
            local image=c.image;local priority=1
            if c.id then local p=page(c);image=image or p and p.image;priority=p and p.priorityType or 0
            elseif c.kind=='airship' or c.mapId and c.mapId~=current.id then priority=0 end
            if not image then
                local id=c==player and party.members()[1] or c.actorId
                image=actorImages[id] or data.resources and data.resources.actorImages and data.resources.actorImages[tostring(id)]
                    or definitions and definitions.actors[id]
            end
            movementModule.refreshBush(c,map,image,priority,data.resources and data.resources.bushDepth or (data.engineProfile=='mv-turn' and 12 or tileSize/4))
        end
        local function refresh()
            for _,event in ipairs(eventStates) do
                local selected=pagesModule.select(event.definition,{mapId=current.id,eventId=event.id,erased=event.erased},services)
                if selected~=event.page then
                    if event.parallel then cancel(event.parallel); event.parallel=nil end
                    event.page=selected
                    local selectedPage=page(event)
                    if movementModule then movementModule.page(event,selectedPage)end
                    local direction=selectedPage and selectedPage.image and selectedPage.image.direction
                    if direction and direction~=event.originalDirection then
                        event.originalDirection,event.direction,event.savedDirection=direction,direction,nil
                    end
                end
                refreshCharacterBush(event)
            end
            if player then refreshCharacterBush(player)end
            for _,c in ipairs(followers)do refreshCharacterBush(c)end
            for _,c in pairs(vehicles)do refreshCharacterBush(c)end
        end
        local function byId(id)
            for _,event in ipairs(eventStates) do if event.id==id then return event end end
        end
        local function loadMap(id,x,y,direction,keepTask)
            local definition=mapService and mapService.get(id) or maps[id]
            if not definition then fail("E_WORLD_REFERENCE","Unknown transfer map: "..tostring(id)) end
            if not integer(x) or not integer(y) or x<0 or y<0 or x>=definition.width or y>=definition.height then
                fail("E_WORLD_POSITION","Transfer position outside target map")
            end
            if direction~=2 and direction~=4 and direction~=6 and direction~=8 then fail("E_WORLD_DIRECTION","Invalid player direction") end
            if options.audio and not titleActive then options.audio.map(id)end
            if current and current.id==id then
                player.x,player.y,player.realX,player.realY,player.direction,player.motion=x,y,x,y,direction,nil
                for _,f in ipairs(followers)do f.x,f.y,f.realX,f.realY,f.motion=x,y,x,y,nil end
                camera.center(player)
                mapName.remaining,mapName.opacity=150,0
                resetEncounterCount()
                refresh()
                return
            end
            if vm then
                for _,event in ipairs(eventStates or {}) do if event.parallel then cancel(event.parallel) end end
                for _,task in pairs(parallelCommon) do cancel(task) end
                if mainTask and mainTask~=keepTask then cancel(mainTask) end
            end
            current={};for k,v in pairs(definition)do current[k]=v end
            parallelCommon,mainTask={},keepTask
            mapName.name=current.settings and current.settings.displayName or '';mapName.remaining,mapName.opacity=150,0
            local explicit=current.settings and current.settings.specifyBattleback
            battleBackground={name1=explicit and current.settings.battleback1Name or '',name2=explicit and current.settings.battleback2Name or ''}
            eventStates={}
            for _,event in ipairs(current.events) do
                local state={id=event.id,definition=event,x=event.x,y=event.y,realX=event.x,realY=event.y,erased=false,direction=2}
                if movementModule then movementModule.initialize(state)end
                eventStates[#eventStates+1]=state
            end
            table.sort(eventStates,function(a,b) return a.id<b.id end)
            if player then player.x,player.y,player.realX,player.realY,player.direction,player.motion=x,y,x,y,direction,nil
            else
                player={x=x,y=y,realX=x,realY=y,direction=direction,speed=4,transparent=world.playerTransparent==true}
                if movementModule then movementModule.initialize(player)end
            end
            for _,f in ipairs(followers)do f.x,f.y,f.realX,f.realY,f.motion=x,y,x,y,nil end
            camera=deps['runtime.world.camera'].new(current,screenWidth,screenHeight,tileSize,player);scrollWaits={}
            mapOptions={
                tileEventsAt=function(tx,ty)
                    local tiles={}
                    for _,event in ipairs(eventStates) do
                        local p=page(event)
                        local image=event.image or p and p.image
                        local through=p and p.through;if movementModule then through=event.through end
                        if p and event.x==tx and event.y==ty and not through and image and (image.tileId or 0)>0 then
                            tiles[#tiles+1]=image.tileId
                        end
                    end
                    return tiles
                end,
                blocked=function(tx,ty,character)
                    for _,event in ipairs(eventStates) do
                        local p=page(event)
                        local through=p and p.through;if movementModule then through=event.through end
                        if p and event~=character and covers(event,p,tx,ty) and p.priorityType==1 and not through then return true end
                    end
                    for _,v in pairs(vehicles)do
                        if v.kind~='airship'and v.mapId==current.id and not v.driving and v.x==tx and v.y==ty then return true end
                    end
                    if character and character~=player and character.id and page(character) and page(character).priorityType==1 and not player.through then
                        if player.x==tx and player.y==ty then return true end
                        if followersVisible then for _,f in ipairs(followers)do if f.x==tx and f.y==ty then return true end end end
                    end
                    return false
                end,
            }
            map=mapService and mapService.newMap(id,mapOptions) or mapModule.new(current,mapOptions)
            collides=mapOptions.blocked
            if player.vehicleType then local v=vehicles[player.vehicleType];v.mapId,v.x,v.y,v.realX,v.realY=current.id,x,y,x,y end
            resetEncounterCount()
            refresh()
        end
        local function operand(ins)
            local value=story.readOperand(ins.operand)
            return ins.operation==1 and -value or value
        end
        local function done() return {kind="continue"} end
        local function character(id,context)
            if id==-1 then return player end
            if id==0 then return context and context.mapId==current.id and byId(context.eventId)end
            return byId(id)
        end
        local function commandToken(kind)
            commandSequence=commandSequence+1
            return string.format('%s:%.0f:%.0f',kind,sessionId,commandSequence)
        end
        local function syncFollowers()
            local members=party.members();local count=math.min(3,math.max(0,#members-1))
            for i=1,count do
                local f=followers[i]
                if not f then f={x=player.x,y=player.y,realX=player.x,realY=player.y,direction=player.direction,speed=player.speed,through=true};movementModule.initialize(f);followers[i]=f end
                f.actorId=members[i+1]
            end
            for i=#followers,count+1,-1 do followers[i]=nil end
        end
        local function vehicleToggle()
            if not movement or player.motion or vehiclePhase then return false end
            syncFollowers()
            local kind=player.vehicleType
            if kind then
                local v=vehicles[kind];local x,y,valid=map.step(player.x,player.y,player.direction)
                if kind=='airship'then
                    if not map.isAirshipLandOk(player.x,player.y)then return false end
                    for _,e in ipairs(eventStates)do if page(e)and e.x==player.x and e.y==player.y then return false end end
                    player.direction=2
                elseif not valid or not map.isPassable(x,y,10-player.direction)or collides(x,y,player)then return false end
                for _,f in ipairs(followers)do f.x,f.y,f.realX,f.realY,f.motion=player.x,player.y,player.x,player.y,nil end
                v.driving=false;v.direction=4;vehiclePhase='off';player.speed=4
                if kind~='airship'then
                    player.vehicleType=nil;player.transparent=false;local through=player.through;player.through=true;movement.move(player,player.direction);player.through=through
                end
                gathering=true;resetEncounterCount()
                if options.audio then options.audio.command({op='audio',action='replay_walking',channel='bgm'})end
                return true
            end
            local x,y=map.step(player.x,player.y,player.direction)
            local function present(k,tx,ty)local v=vehicles[k];return v.mapId==current.id and v.x==tx and v.y==ty end
            if present('airship',player.x,player.y)then kind='airship'
            elseif present('ship',x,y)then kind='ship'elseif present('boat',x,y)then kind='boat'else return false end
            player.vehicleType=kind;vehiclePhase='on';gathering=true
            local v=vehicles[kind]
            if kind~='airship'then local through=player.through;player.through=true;movement.move(player,player.direction);player.through=through end
            if options.audio then
                options.audio.command({op='audio',action='save_walking',channel='bgm'})
                if v.bgm then options.audio.command({op='audio',action='play',channel='bgm',cue=v.bgm})end
            end
            return true
        end
        local function startBattle(troopId,canEscape,canLose,taskId,initiative)
            if battle then return nil end
            if not battleService then fail('E_WORLD_BATTLE_PROGRAM','Encounters and battle events require a compiled battle program')end
            if not battleService.hasTroop(troopId)then return nil end
            local nextSequence=battleSequence+1;if nextSequence>9007199254740991 then fail('E_WORLD_BATTLE_ID','Battle identity exhausted')end
            local token=string.format('battle:%.0f:%.0f',sessionId,nextSequence)
            local preemptive,surprise=false,false
            if initiative then
                if type(battleService.troopAgility)~='function'then fail('E_WORLD_BATTLE_PROGRAM','Encounter initiative requires compiled troop agility')end
                local sum,count=0,0;local ctx=actors.actionContext()
                for i,actorId in ipairs(party.members())do
                    if i>4 then break end;local q=ctx.query({kind='actor',id=actorId})
                    if not q.hidden then sum=sum+q.params[7];count=count+1 end
                end
                local faster=sum/math.max(1,count)>=battleService.troopAgility(troopId)
                local rate=(faster and .05 or .03)*(partyAbility(3)and 4 or 1)
                preemptive=unitRandom('world.encounter.preemptive')<rate
                local surpriseDraw=unitRandom('world.encounter.surprise')
                surprise=not preemptive and not partyAbility(2)and surpriseDraw<(faster and .03 or .05)
            end
            local state=story.snapshot();local switches={}
            for id,value in pairs(state.switches)do switches[#switches+1]={id=id,value=value}end
            table.sort(switches,function(a,b)return a.id<b.id end)
            local nextBattle=battleService.newBattle({battleId=token,troopId=troopId,battleSystem=visu and visu.battleSystem(),partyState=party.snapshot(),actorsState=actors.snapshot(),lastActionData=lastActionData,worldCondition=function(c)return S.worldCondition(c)end,extensionCommand=function(...)return S.executeExtension(...)end,
                damagePolicy=extensionRuntime and function(kind,value)return extensionRuntime.policy('battle.damage',{subjectKind=kind,value=value},value)end,
                rngState=rngState,canEscape=canEscape,canLose=canLose,preemptive=preemptive,surprise=surprise,switches=switches,variables=state.variables,
                eventPrograms=data.eventPrograms,ui=data.ui,stateStore=story,audio=options.audio,presentation=options.presentation,actorName=S.getActorName,timer=timer,accessCommand=accessCommand,gameData=function(value,context)return S.gameData(value,context)end,actorText=function(ins)return S.changeActorText(ins)end,resetActorPresentation=function(id)return S.resetActorPresentation(id)end,mapCommand=function(ins,context)return S.mapCommand(ins,context,true)end})
            battle,battleSequence,battleOwner=nextBattle,nextSequence,{taskId=taskId,token=token,canLose=canLose,encounter=taskId==nil,background=copy(battleBackground)}
            if options.presentation and options.presentation.setBattle then options.presentation.setBattle(true)end
            if options.audio then options.audio.beginBattle()end
            return token
        end
        local function actorEvent(ins)
            if not actors then fail('E_WORLD_ACTORS','Actor events require compiled RPG data')end
            invalidateItems()
            local selected=ins.actorMode==0 and ins.actorSelector or story.getVariable(ins.actorSelector)
            local ids=selected==0 and party.members() or {selected}
            local delta=ins.operand and operand(ins) or 0
            local messages={}
            for _,id in ipairs(ids)do if actors.hasActor(id)then
                local command={op='recoverAll',actorId=id}
                if ins.op=='actor_exp'then command.op='changeExp';command.total=actors.progression(id).currentExp+delta*1.0
                elseif ins.op=='actor_level'then command.op='changeLevel';command.level=actors.getActor(id).state.level+delta*1.0
                elseif ins.op=='actor_class'then command.op='changeClass';command.classId=ins.classId;command.keepExp=ins.keepExp
                elseif ins.op=='actor_skill'then command.op=ins.operation==0 and 'learnSkill' or 'forgetSkill';command.skillId=ins.skillId
                elseif ins.op=='actor_state'then command.op=ins.operation==0 and 'addState' or 'removeState';command.stateId=ins.stateId
                elseif ins.op=='actor_param'then command.op='addParam';command.paramId=ins.paramId;command.value=delta
                elseif ins.op=='actor_hp' or ins.op=='actor_mp' or ins.op=='actor_tp'then
                    command.op=({actor_hp='gainHp',actor_mp='gainMp',actor_tp='gainTp'})[ins.op];command.value=delta;command.allowDeath=ins.allowDeath
                end
                local result=actors.command(command,rngState)
                if not result.ok then error(result.diagnostic or {code='E_WORLD_ACTOR_COMMAND',reason='Actor command failed'},0)end
                rngState=result.rngState
                if ins.showLevelUp then
                    local message=dialogueModule.growth(data.ui,id,result.delta,S.getActorName(id))
                    if message then messages[#messages+1]=message end
                end
            end end
            return {kind='continue',messages=messages}
        end
        if data.visuWorld then
            visu=deps['runtime.visu_world'].new(data.visuWorld,{
                variable=story.getVariable,randomInt=function(n)return random(n,'visu.treasure')end,
                signal=function(name,value)
                    if not options.signal then fail('E_VISU_SIGNAL','Missing host signal bridge: '..name)end
                    options.signal(name,value)
                end,
                gain=function(kind,id,amount)
                    invalidateItems();party.gainItem(kind,id,amount)
                    local collection=world.definitions[kind=='item' and 'items' or kind=='weapon' and 'weapons' or 'armors']
                    for _,r in ipairs(collection)do if r.id==id then visu.gained(r.name,amount);return end end
                    fail('E_VISU_WORLD','Missing gained object '..kind..':'..id)
                end,
                learn=function(ids)
                    if not actors then fail('E_WORLD_ACTORS','Actor events require compiled RPG data')end
                    local result=actors.learnSkills(party.members(),ids)
                    if result.changedActors>0 then invalidateItems()end
                end})
        end
        local handlers={
            visu_world=function(ins)if not visu then fail('E_VISU_WORLD','Visu adapter is not configured')end;return visu.execute(ins)end,
            extension=function(ins,context,taskId)return S.executeExtension(ins,context,taskId,
                function(token)return vm.resumeCommand(taskId,token)end,
                function(token)return vm.isCommandWaiting(taskId,token)end)end,
            scroll_map=function(ins,_,taskId)
                local started=not camera.isScrolling() and #scrollWaits==0
                if started then camera.start(ins)end
                if started and not ins.wait then return done()end
                local token=commandToken('scroll');scrollWaits[#scrollWaits+1]={instruction=ins,started=started,taskId=taskId,token=token}
                return{kind='wait',token=token}
            end,
            parallax=function(ins,context)return S.mapCommand(ins,context)end,
            location_info=function(ins,context)return S.mapCommand(ins,context)end,
            actor_image=function(ins,context)return S.mapCommand(ins,context)end,
            vehicle_image=function(ins,context)return S.mapCommand(ins,context)end,
            vehicle_bgm=function(ins,context)return S.mapCommand(ins,context)end,
            map_name=function(ins,context)return S.mapCommand(ins,context)end,
            tileset=function(ins,context)return S.mapCommand(ins,context)end,
            battle_background=function(ins,context)return S.mapCommand(ins,context)end,
            window_tone=function(ins,context)return S.mapCommand(ins,context)end,
            actor_text=function(ins)return S.changeActorText(ins)end,
            change_equipment=function(ins)
                if not actors then fail('E_WORLD_ACTORS','Equipment events require actor authority')end
                local result=actors.eventEquip(ins.actorId,ins.slot,ins.itemId,rngState)
                if result.ok then rngState=result.rngState;invalidateItems()end
                return done()
            end,
            open_menu=function(_,_,taskId)
                if sceneRequest then fail('E_WORLD_SCENE','A scene request is already active')end
                sceneSequence=sceneSequence+1;local token=string.format('menu:%.0f:%.0f',sessionId,sceneSequence)
                sceneRequest={kind='menu',token=token,taskId=taskId};return{kind='wait',token=token}
            end,
            timer=timer.command,
            access=accessCommand,
            encounters=function(ins)encountersEnabled=ins.enabled;resetEncounterCount();return done()end,
            vehicle_toggle=function()vehicleToggle();return done()end,
            vehicle_location=function(ins)
                local kind=({'boat','ship','airship'})[ins.vehicleType+1];local v=vehicles[kind]
                if not v then fail('E_WORLD_VEHICLE','Invalid vehicle type')end
                local id,x,y=ins.mapId,ins.x,ins.y
                if ins.mode==1 then id,x,y=story.getVariable(id),story.getVariable(x),story.getVariable(y)end
                local definition=mapService and mapService.get(id)or maps[id]
                if not definition or not integer(x)or not integer(y)or x<0 or y<0 or x>=definition.width or y>=definition.height then fail('E_WORLD_POSITION','Vehicle position outside map')end
                v.mapId,v.x,v.y,v.realX,v.realY=id,x,y,x,y
                return done()
            end,
            move_route=function(ins,context,taskId)
                if not movementModule then fail('E_WORLD_MOVEMENT','Movement module is unavailable')end
                refresh();local c=character(ins.characterId,context)
                if not c then return done()end
                movementModule.force(c,ins.route)
                if ins.route.wait then
                    local token=commandToken('route');routeWaits[#routeWaits+1]={character=c,taskId=taskId,token=token}
                    return{kind='wait',token=token}
                end
                return done()
            end,
            event_location=function(ins,context)
                local c=character(ins.eventId,context);if not c then return done()end
                local x,y=ins.x,ins.y
                if ins.mode==1 then x,y=story.getVariable(x),story.getVariable(y)
                elseif ins.mode==2 then
                    local other=character(x,context);if not other then return done()end
                    x,y=other.x,other.y;other.x,other.y,other.realX,other.realY,other.motion=c.x,c.y,c.x,c.y,nil
                end
                x,y=map.normalize(x,y);c.x,c.y,c.realX,c.realY,c.motion=x,y,x,y,nil;c.stopCount=0
                if ins.direction~=0 and not c.directionFix then c.direction=ins.direction end
                return done()
            end,
            transparency=function(ins)player.transparent=ins.transparent;return done()end,
            followers=function(ins)followersVisible=ins.visible;return done()end,
            gather_followers=function(_,_,taskId)
                if not movementModule then fail('E_WORLD_MOVEMENT','Movement module is unavailable')end
                syncFollowers();gathering=true
                local token=commandToken('gather');gatherWaits[#gatherWaits+1]={taskId=taskId,token=token}
                return{kind='wait',token=token}
            end,
            audio=function(ins)if options.audio then options.audio.command(ins)end;return done()end,
            name_input=function(ins,_,taskId)
                if sceneRequest then fail('E_WORLD_SCENE','A scene request is already active')end
                if not actors or not actors.hasActor(ins.actorId)then return done()end
                if not integer(ins.maxLength) or ins.maxLength<1 or ins.maxLength>16 then fail('E_WORLD_NAME','Invalid name input length')end
                sceneSequence=sceneSequence+1
                local token=string.format('name:%.0f:%.0f',sessionId,sceneSequence)
                sceneRequest={kind='name',token=token,actorId=ins.actorId,maxLength=ins.maxLength,name=S.getActorName(ins.actorId),taskId=taskId}
                return{kind='wait',token=token}
            end,
            game_over=function(_,_,taskId)
                gameOver=true;sceneSequence=sceneSequence+1
                local token=string.format('gameover:%.0f:%.0f',sessionId,sceneSequence)
                sceneRequest={kind='gameover',token=token,taskId=taskId};return{kind='wait',token=token}
            end,
            return_title=function(_,_,taskId)
                sceneSequence=sceneSequence+1;local token=string.format('title:%.0f:%.0f',sessionId,sceneSequence)
                sceneRequest={kind='title',token=token,taskId=taskId};return{kind='wait',token=token}
            end,
            shop=function(ins,_,taskId)
                if sceneRequest then fail('E_WORLD_SCENE','A scene request is already active')end
                sceneSequence=sceneSequence+1
                local token=string.format('shop:%.0f:%.0f',sessionId,sceneSequence)
                sceneRequest={kind='shop',token=token,goods=copy(ins.goods),purchaseOnly=ins.purchaseOnly==true,revision=0,taskId=taskId}
                return{kind='wait',token=token}
            end,
            battle=function(ins,_,taskId)
                local troopId=ins.troopOperand.kind=='encounter'and encounterTroop()or story.readOperand(ins.troopOperand)
                local token=startBattle(troopId,ins.canEscape,ins.canLose,taskId,false)
                if not token then return done()end
                return{kind='wait',token=token}
            end,
            actor_recover=actorEvent,actor_exp=actorEvent,actor_level=actorEvent,
            actor_hp=actorEvent,actor_mp=actorEvent,actor_tp=actorEvent,actor_state=actorEvent,actor_param=actorEvent,actor_skill=actorEvent,actor_class=actorEvent,
            gold=function(ins) party.gainGold(operand(ins)); return done() end,
            inventory=function(ins)
                invalidateItems()
                if actors then
                    local result=actors.gainItem(ins.itemKind,ins.id,operand(ins),ins.includeEquip,rngState)
                    if result.ok then rngState=result.rngState end
                else party.gainItem(ins.itemKind,ins.id,operand(ins),ins.includeEquip) end
                return done()
            end,
            party_member=function(ins)
                invalidateItems()
                if ins.remove then party.removeActor(ins.id)
                else
                    if ins.initialize then
                        local result=actors.command({op='setup',actorId=ins.id},rngState)
                        if not result.ok then error(result.diagnostic or {code='E_WORLD_ACTOR_COMMAND',reason='Actor setup failed'},0)end
                        rngState=result.rngState;S.resetActorPresentation(ins.id)
                    end
                    party.addActor(ins.id)
                end
                return done()
            end,
            erase_event=function(_,context)
                if context.mapId==current.id then
                    local event=byId(context.eventId)
                    if not event then fail("E_WORLD_CONTEXT","Erase requires a map event") end
                    event.erased=true
                end
                return done()
            end,
            transfer=function(ins,_,taskId)
                local id,x,y=ins.mapId,ins.x,ins.y
                if ins.mode==1 then id=story.getVariable(id); x=story.getVariable(x); y=story.getVariable(y) end
                local direction=ins.direction==0 and player.direction or ins.direction
                if ins.fade==2 then loadMap(id,x,y,direction,mainTask==taskId and taskId or nil);return done()end
                local definition=mapService and mapService.get(id)or maps[id]
                if not definition or not integer(x) or not integer(y) or x<0 or y<0 or x>=definition.width or y>=definition.height then fail('E_WORLD_POSITION','Transfer position outside target map')end
                local token=commandToken('transfer')
                transfer={mapId=id,x=x,y=y,direction=direction,white=ins.fade==1,remaining=24,phase='out',taskId=taskId,token=token}
                if options.presentation then options.presentation.command({op='screen',action='fade',brightness=0,white=transfer.white,duration=24,wait=false},{},taskId)end
                return{kind='wait',token=token}
            end,
        }
        for _,op in ipairs({'picture','screen','animation','balloon','video'})do
            if options.presentation then handlers[op]=function(ins,context,taskId)
                return options.presentation.command(ins,context,taskId,function(id,token)return vm.resumeCommand(id,token)end,
                    function(id,token)return vm.isCommandWaiting(id,token)end,
                    function()return vm.getMessage()==nil and mapMessage==nil and #extensionMessages==0 end)
            end end
        end
        function S.gameData(value,context)
            local kind,id,field=value.type,value.id,value.field
            if kind==8 then return battle and battle.gameData(value) or lastActionData[id+1] or 0
            elseif kind<=2 then return party.count(({'item','weapon','armor'})[kind+1],id)
            elseif kind==3 then
                if not actors or not actors.hasActor(id)then return 0 end
                local actor=actors.getActor(id)
                if field==0 then return actor.state.level elseif field==1 then return actors.progression(id).currentExp
                elseif field==2 then return actor.state.hp elseif field==3 then return actor.state.mp elseif field==12 then return actor.state.tp end
                return actor.stats.params[field-3] or 0
            elseif kind==4 then return 0
            elseif kind==5 then
                local c=character(id,context);if not c then return 0 end
                if field==0 then return c.x elseif field==1 then return c.y elseif field==2 then return c.direction end
                local x,y=camera.project(c.realX or c.x,c.realY or c.y)
                return math.floor((field==3 and (x+.5)*tileSize or (y+1)*tileSize-6-(c.jumpHeight or 0))+.5)
            elseif kind==6 then return party.members()[id+1] or 0
            elseif kind==7 then
                return ({current.id,#party.members(),party.gold(),steps,math.floor(playFrames/60),timer.snapshot().seconds,0,battleSequence,wins,escapes})[id+1] or 0
            end
            fail('E_EVENT_IR','Unknown game data operand')
        end
        local function extensionContext()
            return {query=function(kind,itemKind,id)
                if kind=='variable'then return story.getVariable(itemKind)end
                if kind=='switch'then return story.getSwitch(itemKind)end
                if kind=='gold'then return battle and battle.gameData({type=7,id=2}) or party.gold()end
                if kind=='inventory'then local kinds={item=0,weapon=1,armor=2};if kinds[itemKind]==nil then fail('E_EXTENSION_RUNTIME','Unknown item kind')end;return battle and battle.gameData({type=kinds[itemKind],id=id}) or party.count(itemKind,id)end
                fail('E_EXTENSION_RUNTIME','Unknown read-only query')
            end}
        end
        local function commitExtension(proposal)
            local operations=copy(proposal.operations)
            if #operations>0 then
                if battle then local out=battle.extensionOperations(operations);if not out.ok then error(out.diagnostic,0)end
                else party.transaction(function(candidate)
                    for _,op in ipairs(operations)do if op.kind=='gold'then candidate.gainGold(op.amount)else candidate.gainItem(op.itemKind,op.id,op.amount,false)end end
                    return true
                end)end
            end
            extensionRuntime.commit(proposal);invalidateItems();refresh()
        end
        function S.extensionMenus()return extensionRuntime and copy(extensionRuntime.menus()) or {}end
        function S.extensionMenuView(extensionId,menuId)
            if closed or not extensionRuntime then fail('E_EXTENSION_MENU','Extension menus unavailable')end
            return copy(extensionRuntime.menu(extensionId,menuId,extensionContext()))
        end
        function S.extensionMenuAction(request)
            if closed or battle or transfer or gameOver or not extensionRuntime then return{ok=false,reason='unavailable'}end
            local ins,reason=extensionRuntime.menuAction(request,extensionContext())
            if not ins then return{ok=false,reason=reason}end
            local proposal=extensionRuntime.prepare(ins,extensionContext())
            -- Menu actions must finish as domain transactions. Event-owned
            -- dialogue requires an interpreter and cannot be orphaned here.
            if proposal.message then return{ok=false,reason='dialogue-requires-event'}end
            commitExtension(proposal)
            return{ok=true}
        end
        function S.executeExtension(ins,context,taskId,resume,alive)
            if ins.extensionId=='game.aurora'then
                if not aurora then fail('E_AURORA_ADAPTER','Aurora runtime is missing')end
                if ins.command=='selfSwitchA'then story.setSelfSwitch(context,'A',true);refresh();return done()end
                aurora.invoke(ins.command,ins.args)
                if aurora.active()then
                    local token=commandToken('aurora');auroraWait={token=token,resume=resume,alive=alive}
                    return{kind='wait',token=token}
                end
                return done()
            end
            if not extensionRuntime then fail('E_EXTENSION_RUNTIME','Extension has no compiled runtime')end
            local proposal=extensionRuntime.prepare(ins,extensionContext())
            commitExtension(proposal)
            if proposal.message then
                local token=commandToken('extension');local message=copy(proposal.message)
                message.taskId,message.token,message.extension=taskId,token,true
                extensionMessages[#extensionMessages+1]={message=message,resume=resume,alive=alive,token=token}
                return{kind='wait',token=token}
            end
            return done()
        end
        function S.worldCondition(c)
            if c.kind=='visu_battle_test'then return options.battleTest==true
            elseif c.kind=='visu_literal'then return c.value==true
            elseif c.kind=='extension_query'then
                if not extensionRuntime then fail('E_EXTENSION_RUNTIME','Extension queries unavailable')end
                return extensionRuntime.query(c,extensionContext())
            elseif c.kind=='button'then
                if type(options.buttonInput)~='function'then fail('E_WORLD_INPUT','Logical input service is required for button conditions')end
                return options.buttonInput(c.button,c.mode)
            elseif c.kind=='vehicle'then
                if not integer(c.vehicleType) or c.vehicleType<0 or c.vehicleType>2 then fail('E_EVENT_IR','Invalid vehicle condition')end
                return player.vehicleType==({'boat','ship','airship'})[c.vehicleType+1]
            end
            fail('E_WORLD_CONDITION','Unknown world condition')
        end
        function S.mapCommand(ins,context,inBattle)
            if ins.op=='visu_world'then if not visu then fail('E_VISU_WORLD','Visu adapter is not configured')end;return visu.execute(ins)
            elseif ins.op=='window_tone'then windowTone=copy(ins.tone);return done()
            elseif ins.op=='map_name'then mapName.enabled=ins.enabled;return done()
            elseif ins.op=='battle_background'then battleBackground={name1=ins.name1,name2=ins.name2};return done()
            elseif ins.op=='tileset'then
                local flags=mapService and mapService.getTileset(ins.id) or world.tilesets and world.tilesets[string.format('%.0f',ins.id)]
                if not flags then fail('E_WORLD_TILESET','Missing compiled tileset')end
                current.tilesetId,current.flags=ins.id,flags
                map=mapService and mapService.newMap(current.id,mapOptions,ins.id) or mapModule.new(current,mapOptions)
                refresh();return done()
            end
            if ins.op=='actor_image'then
                if actors and actors.hasActor(ins.actorId)then actorImages[ins.actorId]={tileId=0,characterName=ins.characterName,characterIndex=ins.characterIndex,
                    faceName=ins.faceName,faceIndex=ins.faceIndex,battlerName=ins.battlerName,faceTemplateId=ins.faceTemplateId}end
                player.image=nil;for _,f in ipairs(followers)do f.image=nil end
                return done()
            elseif ins.op=='vehicle_image' or ins.op=='vehicle_bgm'then
                local v=vehicles[({'boat','ship','airship'})[ins.vehicleType+1]]
                if ins.op=='vehicle_image'then v.image={tileId=0,characterName=ins.characterName,characterIndex=ins.characterIndex}
                else v.bgm=copy(ins.cue)end
                return done()
            end
            if ins.op=='parallax'then camera.parallax(ins);return done()end
            if ins.op~='location_info'then fail('E_WORLD_COMMAND','Unknown map command')end
            local x,y=ins.x,ins.y
            if ins.mode==1 then x,y=story.getVariable(x),story.getVariable(y)
            elseif ins.mode==2 then
                local c=not inBattle and character(x,context);if not c then fail('E_WORLD_CHARACTER','Location query character is unavailable')end;x,y=c.x,c.y
            end
            local value=0
            if ins.kind==0 then value=map.terrainTag(x,y)
            elseif ins.kind==1 then for _,e in ipairs(eventStates)do if e.x==x and e.y==y then value=e.id;break end end
            elseif ins.kind>=2 and ins.kind<=5 then value=map.tile(x,y,ins.kind-2)
            else value=map.regionId(x,y)end
            story.applyVariables(ins.variableId,ins.variableId,0,{kind='constant',value=value});return done()
        end
        local function resolveOperand(value,context)
            if value.kind=='random'then return value.minimum+random(value.span,'event.variable')end
            if value.kind=='extension_query'then return S.worldCondition(value)end
            return S.gameData(value,context)
        end
        vm=eventModule.new(data,{stateStore=story,resolveOperand=resolveOperand,commandHandlers=handlers,conditionHandlers={
            visu_battle_test=function(c)return S.worldCondition(c)end,
            visu_literal=function(c)return S.worldCondition(c)end,
            extension_query=function(c)return S.worldCondition(c)end,
            button=function(c)return S.worldCondition(c)end,
            vehicle=function(c)return S.worldCondition(c)end,
            timer=function(c)return timer.test(c.seconds,c.comparison)end,
            enemy=function()return false end,
            direction=function(c,context)local target=character(c.characterId,context);return target~=nil and target.direction==c.direction end,
            inventory=function(c) return party.hasItem(c.itemKind,c.id,c.includeEquip) end,
            actor=function(c)
                if c.test then return actors and actors.meetsCondition(c.id,c.test,c.value,S.getActorName(c.id)) or false end
                return party.hasActor(c.id)
            end,
            gold=function(c)
                local gold=party.gold()
                if c.comparison==0 then return gold>=c.value elseif c.comparison==1 then return gold<=c.value end
                return gold<c.value
            end,
        },perTaskBudget=options.perTaskBudget,frameBudget=options.frameBudget,maxCallDepth=options.maxCallDepth,
            shouldYield=function()return battle~=nil or sceneRequest~=nil or mapMessage~=nil end})
        local start=options.start or world.start
        loadMap(start.mapId,start.x,start.y,start.direction or 2)
        if data.aurora then
            aurora=deps['runtime.aurora.game'].new(data.aurora,{mapId=function()return current.id end,
                transfer=function(id,x,y)auroraTransfer={id=id,x=x,y=y}end,
                random=function()return unitRandom('aurora')end,audio=options.audio})
        end
        function S.auroraView()return aurora and aurora.view()end
        function S.auroraInput(kind,value)return aurora and aurora.input(kind,value)or false end
        function S.auroraMenu()if not aurora then return false end;aurora.menu();return true end
        function S.auroraSnapshot()return aurora and aurora.snapshot()end
        local function startProgram(programId)
            local id=vm.start(programId); owners[id]=programId; return id
        end
        local function startEvent(event)
            local p=page(event)
            if not p or mainTask then return false end
            mainTask=startProgram(p.programId)
            if p.trigger<=2 then
                event.savedDirection=event.direction
                local dx,dy=player.x-event.x,player.y-event.y
                if (current.scrollType==2 or current.scrollType==3) and math.abs(dx)>current.width/2 then dx=dx+(dx<0 and current.width or -current.width) end
                if (current.scrollType==1 or current.scrollType==3) and math.abs(dy)>current.height/2 then dy=dy+(dy<0 and current.height or -current.height) end
                local fixed=p.directionFix;if movementModule then fixed=event.directionFix end
                if not fixed then
                    if math.abs(dx)>math.abs(dy) then event.direction=dx>0 and 6 or 4
                    elseif dy~=0 then event.direction=dy>0 and 2 or 8 end
                end
                event.lockedTask=mainTask
            end
            return true
        end
        local function at(x,y,normal,triggers)
            for _,event in ipairs(eventStates) do
                local p=page(event)
                if p and covers(event,p,x,y) and (p.priorityType==1)==normal and triggers[p.trigger] then
                    if startEvent(event) then return true end
                end
            end
            return false
        end
        if movementModule then
            movement=movementModule.new({map=function()return map end,definition=function()return current end,player=function()return player end,
                random=random,refreshBush=refreshCharacterBush,
                nearScreen=function(c)return movementModule.nearScreen(c,player,current,screenWidth,screenHeight,tileSize)end,
                followers=function(c)if c==player then syncFollowers();return followers end end,
                canPass=function(c,x,y,d)
                    if c~=player or not player.vehicleType then return nil end
                    local nx,ny,valid=map.step(x,y,d);if not valid then return false end
                    if c.through or player.vehicleType=='airship'then return true end
                    local pass=player.vehicleType=='boat'and map.isBoatPassable(nx,ny)or player.vehicleType=='ship'and map.isShipPassable(nx,ny)
                    return pass and not collides(nx,ny,c)
                end,
                switch=function(id,value)story.setSwitches(id,id,value)end,
                audio=options.audio and function(ins)options.audio.command(ins)end,
                extension=data.visuWorld and function(ins,c)
                    if ins.name~='visu_balloon' then fail('E_MOVE_ROUTE_SCRIPT','Unknown Visu movement operation')end
                    local asset=data.resources and data.resources.balloons and data.resources.balloons[tostring(ins.balloonId)]
                    if not asset or not options.presentation then fail('E_VISU_ASSET','Missing balloon '..ins.balloonId)end
                    options.presentation.command({op='balloon',balloonId=ins.balloonId,characterId=c.id,wait=false,asset=asset},{mapId=current.id,eventId=c.id},0)
                    return true
                end or options.movementExtension,
                beforeMove=function(c)
                    if c==player then
                        syncFollowers()
                        for i=#followers,1,-1 do
                            followers[i].speed=player.speed+(player.dashing and 1 or 0)
                            movement.chase(followers[i],i==1 and player or followers[i-1])
                        end
                    end
                end,
                touch=function(c,x,y)
                    if c==player then if player.vehicleType~='airship'and not S.isBusy()then at(x,y,true,{[1]=true,[2]=true})end
                    elseif c.id and x==player.x and y==player.y and not mainTask then
                        local p=page(c);if p and p.trigger==2 and p.priorityType==1 and (c.jumpHeight or 0)==0 then startEvent(c)end
                    end
                end,
                arrive=function(c)
                    if c==player then
                        local normal=not c.forcing and not c.vehicleType and not vehiclePhase
                        if normal then steps=steps+1 end
                        if mapEffects and not active(mainTask and vm.getTask(mainTask))and not mapMessage then
                            local effect=actors.actionTransaction(rngState,function(ctx)
                                return mapEffects.apply({steps=steps,normal=normal,onDamageFloor=c.vehicleType~='airship'and map.isDamageFloor(c.x,c.y),rngState=rngState},ctx)
                            end)
                            rngState=effect.rngState;invalidateItems()
                            if effect.flash and options.presentation then options.presentation.command({op='screen',action='flash',color={255,0,0,128},duration=8,wait=false},{mapId=current.id},0)end
                            if #effect.messages>0 then
                                local lines={};for _,message in ipairs(effect.messages)do lines[#lines+1]=message.template:gsub('%%1',function()return S.getActorName(message.actorId)end)end
                                mapMessage={taskId=0,token=commandToken('walk'),speaker='',lines=lines,background=0,position=2,faceName='',faceIndex=0}
                            end
                            if effect.allDead then gameOver=true end
                        end
                        if player.vehicleType~='airship'and not vehiclePhase then at(player.x,player.y,false,{[1]=true,[2]=true})end
                        if aurora and normal then aurora.step(map.regionId(c.x,c.y),active(mainTask and vm.getTask(mainTask))or vm.getMessage()~=nil)end
                        if encounterCount and encountersEnabled and c.vehicleType~='airship'and not c.forcing and not vehiclePhase and not partyAbility(1)then
                            local progress=map.isBush(c.x,c.y)and 2 or 1
                            if partyAbility(0)then progress=progress*.5 end
                            if c.vehicleType=='ship'then progress=progress*.5 end
                            encounterCount=encounterCount-progress
                        end
                    end
                end})
            syncFollowers()
        end
        function S.isBusy()
            pruneExtensionMessages()
            if aurora and aurora.active()or auroraTransfer then return true end
            if options.presentation and options.presentation.isVideoBusy and options.presentation.isVideoBusy()then return true end
            return transfer~=nil or battle~=nil or sceneRequest~=nil or mapMessage~=nil or #extensionMessages>0 or gameOver==true or gathering or vehiclePhase~=nil or player and player.forcing==true or #reservedCommon>0 or active(mainTask and vm.getTask(mainTask)) or vm.getMessage()~=nil
        end
        local settle
        function S.move(direction,dash)
            if direction~=2 and direction~=4 and direction~=6 and direction~=8 then fail("E_WORLD_DIRECTION","Invalid move direction") end
            if closed then return false,"closed" end
            settle()
            if S.isBusy() or player.motion then return false,"busy" end
            refresh()
            local dashing=not player.vehicleType and (settings.alwaysDash~= (dash==true)) and not (current.settings and current.settings.disableDashing)
            if movement then
                local moved=movement.move(player,direction,false,dashing)
                if moved then return true end
                return false,'blocked'
            end
            player.direction=direction
            local x,y,valid=map.step(player.x,player.y,direction)
            if not valid or not map.canPass(player.x,player.y,direction) then
                if valid then at(x,y,true,{[1]=true,[2]=true}) end
                return false,"blocked"
            end
            local dx=direction==6 and 1 or direction==4 and -1 or 0
            local dy=direction==2 and 1 or direction==8 and -1 or 0
            player.motion={fromX=player.x,fromY=player.y,dx=dx,dy=dy,elapsed=0,duration=256/2^(player.speed+(dashing and 1 or 0))}
            player.x,player.y=x,y
            return true
        end
        function S.confirm()
            if closed then return false end
            settle()
            if S.isBusy() or player.motion then return false end
            refresh()
            if vehicleToggle()then return true end
            if player.vehicleType=='airship'then return false end
            if at(player.x,player.y,false,{[0]=true}) then return true end
            local x,y,valid=map.step(player.x,player.y,player.direction)
            if not valid then return false end
            if at(x,y,true,{[0]=true}) then return true end
            if map.isCounter(x,y) then
                x,y,valid=map.step(x,y,player.direction)
                if valid then return at(x,y,true,{[0]=true}) end
            end
            return false
        end
        local function finished(id)
            local task=vm.getTask(id)
            if not active(task) then
                if task and task.status=="ERROR" and not reported[id] then
                    errors[#errors+1]=task.diagnostic; reported[id]=true; failedPrograms[owners[id]]=true
                end
                retire(id)
                return true
            end
            return false
        end
        settle=function()
            if mainTask and finished(mainTask) then mainTask=nil end
            for _,event in ipairs(eventStates) do
                if event.lockedTask and not active(vm.getTask(event.lockedTask)) then
                    local p=page(event)
                    local fixed=p and p.directionFix;if movementModule then fixed=event.directionFix end
                    if event.savedDirection and not fixed then event.direction=event.savedDirection end
                    event.lockedTask=nil
                end
            end
        end
        function S.advancePlaytime(frames)
            if not integer(frames) or frames<0 or playFrames+frames>9007199254740991 then fail('E_WORLD_TIME','Invalid play time')end
            if not closed and not titleActive then playFrames=playFrames+frames end
        end
        function S.showMapName()mapName.remaining=150 end
        function S.hideMapName()mapName.remaining,mapName.opacity=0,0 end
        function S.tick(frames,timeActive,appendBattleRecords)
            if not integer(frames) or frames<0 then fail("E_WORLD_TIME","Expected nonnegative logical frames") end
            if timeActive~=nil and type(timeActive)~='boolean'then fail('E_WORLD_TIME','Battle timeActive must be boolean')end
            if appendBattleRecords~=nil and type(appendBattleRecords)~='boolean'then fail('E_WORLD_TIME','Battle record accumulation must be boolean')end
            if closed then return 0 end
            if aurora then
                aurora.tick(frames)
                if aurora.active()then S.advancePlaytime(frames);return 0 end
                if auroraWait then
                    if auroraWait.alive(auroraWait.token)then auroraWait.resume(auroraWait.token)end
                    auroraWait=nil
                end
                if auroraTransfer then
                    local t=auroraTransfer;auroraTransfer=nil
                    transfer={mapId=t.id,x=t.x,y=t.y,direction=2,white=false,remaining=24,phase='out'}
                    if options.presentation then options.presentation.command({op='screen',action='fade',brightness=0,white=false,duration=24,wait=false},{},0)end
                end
            end
            S.advancePlaytime(frames)
            local function updateTimer(delta)
                if not gameOver and not titleActive and timer.tick(delta) and battle then
                    local out=battle.abort();if out.ok==false then error(out.diagnostic,0)end
                end
            end
            local tpb=battle and type(battle.isTpb)=='function' and battle.isTpb()
            if not tpb then updateTimer(frames)end
            while transfer and frames>0 do
                local consumed=math.min(frames,transfer.remaining)
                if options.presentation then options.presentation.tick(consumed)end
                frames=frames-consumed;transfer.remaining=transfer.remaining-consumed
                if transfer.remaining==0 then
                    if transfer.phase=='out'then
                        loadMap(transfer.mapId,transfer.x,transfer.y,transfer.direction,mainTask==transfer.taskId and transfer.taskId or nil)
                        transfer.phase,transfer.remaining='in',24
                        if options.presentation then options.presentation.command({op='screen',action='fade',brightness=255,white=transfer.white,duration=24,wait=false},{},transfer.taskId)end
                    else
                        if transfer.taskId then vm.resumeCommand(transfer.taskId,transfer.token)end;transfer=nil
                    end
                end
            end
            if transfer then return 0 end
            if tpb then
                local delta=frames==0 and 0 or 1
                for frame=1,math.max(1,frames)do
                    updateTimer(delta)
                    if options.presentation then options.presentation.tick(delta)end
                    -- Input sampling may split one host frame into several
                    -- World ticks; retain their records until the UI projects.
                    local out=battle.advance(1,delta,timeActive,appendBattleRecords==true or frame>1)
                    if type(out)=='table'and out.ok==false then error(out.diagnostic or {severity='error',code='E_WORLD_BATTLE_EVENT',reason=out.reason or 'Battle event failed'},0)end
                end
                return 0
            end
            if options.presentation then options.presentation.tick(frames)end
            if gameOver then return 0 end
            if sceneRequest then return 0 end
            if battle then
                local out=battle.advance(1,frames,timeActive,appendBattleRecords)
                if type(out)=='table'and out.ok==false then error(out.diagnostic or {severity='error',code='E_WORLD_BATTLE_EVENT',reason=out.reason or 'Battle event failed'},0)end
                return 0
            end
            local shown=mapName.enabled and math.min(frames,mapName.remaining) or 0
            mapName.remaining=mapName.remaining-shown
            mapName.opacity=math.max(0,math.min(255,mapName.opacity+shown*16)-(frames-shown)*16)
            settle()
            if not mainTask and #reservedCommon>0 then mainTask=startProgram(table.remove(reservedCommon,1))end
            if movement then
                syncFollowers()
                for _=1,frames do
                    camera.tick()
                    movement.tick(player)
                    camera.follow(player)
                    for _,event in ipairs(eventStates)do movement.tick(event)end
                    for _,f in ipairs(followers)do
                        f.speed=player.speed+(player.dashing and 1 or 0);f.opacity=player.opacity;f.transparent=player.transparent
                        f.walkAnime,f.stepAnime=player.walkAnime,player.stepAnime
                        movement.tick(f)
                    end
                    if gathering then
                        for i=#followers,1,-1 do movement.chase(followers[i],i==1 and player or followers[i-1])end
                        local gathered=true
                        for _,f in ipairs(followers)do if f.motion or f.x~=player.x or f.y~=player.y then gathered=false end end
                        if gathered or not followersVisible then gathering=false end
                    end
                    if vehiclePhase=='on'and not gathering and not player.motion then
                        local v=vehicles[player.vehicleType];v.driving=true;player.speed=v.speed;player.transparent=true
                        if v.kind~='airship'or v.altitude>=48 then vehiclePhase=nil end
                    elseif vehiclePhase=='off'and not gathering and not player.motion then
                        if player.vehicleType~='airship'or vehicles.airship.altitude<=0 then
                            player.vehicleType=nil;player.transparent=false;vehiclePhase=nil
                        end
                    end
                    for _,v in pairs(vehicles)do
                        if v.driving then
                            v.mapId,v.x,v.y,v.realX,v.realY,v.direction=current.id,player.x,player.y,player.realX,player.realY,player.direction
                        end
                        if v.kind=='airship'then v.altitude=math.max(0,math.min(48,v.altitude+(v.driving and 1 or -1)))end
                        v.walkAnime=v.driving;v.stepAnime=v.kind=='airship'and v.altitude==48 or v.kind~='airship'and v.driving
                        movement.tick(v)
                    end
                    refresh()
                end
                for i=#routeWaits,1,-1 do
                    local w=routeWaits[i]
                    if not active(vm.getTask(w.taskId))then table.remove(routeWaits,i)
                    elseif not w.character.forcing then vm.resumeCommand(w.taskId,w.token);table.remove(routeWaits,i)end
                end
                if not gathering then
                    for _,w in ipairs(gatherWaits)do vm.resumeCommand(w.taskId,w.token)end;gatherWaits={}
                end
            else
                for _=1,frames do camera.tick()end
              if player.motion then
                local motion=player.motion; motion.elapsed=math.min(motion.duration,motion.elapsed+frames)
                local progress=motion.elapsed/motion.duration
                player.realX=motion.fromX+motion.dx*progress; player.realY=motion.fromY+motion.dy*progress
                if progress==1 then
                    player.motion=nil; player.realX,player.realY=player.x,player.y; steps=steps+1
                    at(player.x,player.y,false,{[1]=true,[2]=true})
                end
              end
              camera.follow(player)
            end
            while not camera.isScrolling() and #scrollWaits>0 do
                local waiter=scrollWaits[1]
                if not active(vm.getTask(waiter.taskId))then table.remove(scrollWaits,1)
                else
                    if not waiter.started then camera.start(waiter.instruction);waiter.started=true end
                    if waiter.instruction.wait and camera.isScrolling()then break end
                    vm.resumeCommand(waiter.taskId,waiter.token);table.remove(scrollWaits,1)
                end
            end
            refresh()
            for _,event in ipairs(eventStates) do
                local p=page(event)
                if p and p.trigger==3 and not mainTask and not failedPrograms[p.programId] then startEvent(event) end
                if p and p.trigger==4 and (not event.parallel or finished(event.parallel)) and not failedPrograms[p.programId] then
                    event.parallel=startProgram(p.programId)
                end
            end
            for _,event in ipairs(world.commonEvents) do
                local task=parallelCommon[event.id]
                local enabled=event.trigger~=0 and story.getSwitch(event.switchId)
                if not enabled and task then cancel(task); parallelCommon[event.id]=nil
                elseif enabled and event.trigger==1 and not mainTask and not failedPrograms[event.programId] then mainTask=startProgram(event.programId)
                elseif enabled and event.trigger==2 and (not task or finished(task)) and not failedPrograms[event.programId] then parallelCommon[event.id]=startProgram(event.programId) end
            end
            local used=vm.tick(frames)
            -- Scene transition suspends the map, including parallel page
            -- replacement. Keep the interpreter alive for its battle result.
            if not battle and not sceneRequest then refresh()end
            if not battle and not sceneRequest and encounterCount and encounterCount<=0 and not S.isBusy()and not player.motion then
                resetEncounterCount();local troopId=encounterTroop();if troopId>0 then startBattle(troopId,true,false,nil,true)end
            end
            return used
        end
        local baseNames
        function S.getActorName(id)
            if not baseNames then
                baseNames={};local pool=data.ui and data.ui.presentationDefs and data.ui.presentationDefs.actors or world.definitions.actors
                for _,record in ipairs(pool or {})do baseNames[record.id]=record.name or ''end
            end
            return actorNames[id] or baseNames[id] or ''
        end
        function S.resetActorPresentation(id)
            actorNames[id],actorText[id],actorImages[id]=nil,nil,nil
            player.image=nil;for _,f in ipairs(followers)do f.image=nil end
        end
        function S.changeActorText(ins)
            if not ({name=true,nickname=true,profile=true})[ins.field] or type(ins.value)~='string' or not utf8.len(ins.value)then fail('E_WORLD_ACTOR_TEXT','Invalid actor text')end
            if actors and actors.hasActor(ins.actorId) then
                if ins.field=='name'then actorNames[ins.actorId]=ins.value
                else actorText[ins.actorId]=actorText[ins.actorId] or {};actorText[ins.actorId][ins.field]=ins.value end
            end
            return done()
        end
        function S.actorPresentation(id,source)
            local result=copy(source);result.name=S.getActorName(id)
            for field,value in pairs(actorText[id] or {})do result[field]=value end
            for field,value in pairs(actorImages[id] or {})do result[field]=value end
            return result
        end
        function S.enterTitle()titleActive=true;if options.audio then options.audio.title()end end
        function S.leaveTitle()titleActive=false;if options.audio then options.audio.map(current.id)end end
        local function expandText(source)
            if visu then source=source:gsub('\\([Ll][Aa][Ss][Tt][Gg][Aa][Ii][Nn][Oo][Bb][Jj][Qq][Uu][Aa][Nn][Tt][Ii][Tt][Yy])',function(code)return visu.expand(code:upper())end)
                :gsub('\\([Ll][Aa][Ss][Tt][Gg][Aa][Ii][Nn][Oo][Bb][Jj])',function(code)return visu.expand(code:upper())end)end
            local out={};local position=1
            while position<=#source do
                local at=source:find('\\',position,true)
                if not at then out[#out+1]=source:sub(position);break end
                out[#out+1]=source:sub(position,at-1);local code=source:sub(at+1,at+1):upper()
                if code=='\\'then out[#out+1]='\\';position=at+2
                elseif code=='G'then out[#out+1]=data.ui and data.ui.currencyUnit or '';position=at+2
                elseif (code=='N' or code=='P' or code=='V') and source:sub(at+2,at+2)=='[' then
                    local digits=source:sub(at+2):match('^%[(%d+)%]')
                    if not digits then fail('E_WORLD_TEXT','Malformed dynamic text token')end
                    local id=tonumber(digits);local value
                    if code=='N'then value=S.getActorName(id)
                    elseif code=='P'then value=S.getActorName(party.members()[id])
                    else value=id==0 and 0 or story.getVariable(id);value=integer(value) and string.format('%.0f',value) or tostring(value)end
                    out[#out+1]=value;position=at+4+#digits
                elseif code=='C' or code=='I' or code=='F' or code=='P' then
                    local name=source:sub(at+1):match('^([%a]+)')
                    local supported=name and (name:upper()=='C' or name:upper()=='I' or name:upper()=='FS' or name:upper()=='PX' or name:upper()=='PY')
                    local digits=supported and source:sub(at+1+#name):match('^%[(%d+)%]')
                    if not digits then fail('E_WORLD_TEXT','Malformed style token')end
                    local nextPosition=at+1+#name+#digits+2;out[#out+1]=source:sub(at,nextPosition-1);position=nextPosition
                elseif code=='{' or code=='}' or code=='.' or code=='|' or code=='!' or code=='>' or code=='<' or code=='^' or code=='$'then
                    out[#out+1]=source:sub(at,at+1);position=at+2
                else fail('E_WORLD_TEXT','Unsupported text token: '..code)end
            end;return table.concat(out)
        end
        local projectedMessage,projectedMessageOwner
        function S.getMessage()
            pruneExtensionMessages()
            local message;if battle then message=battle.getMessage()else message=mapMessage and copy(mapMessage)or vm.getMessage()end
            if not message and extensionMessages[1]then message=copy(extensionMessages[1].message)end
            if not message then projectedMessage=nil;return nil end
            if projectedMessage and projectedMessageOwner==battle and projectedMessage.taskId==message.taskId and projectedMessage.token==message.token then return copy(projectedMessage)end
            message.sourceLines=copy(message.lines)
            if visu then visu.project(message)end
            if message.extension then
                projectedMessage,projectedMessageOwner=copy(message),battle;return message
            elseif not battle and mapMessage then
                message.flowTokens={}
                for i,line in ipairs(message.lines)do
                    if i>1 then message.flowTokens[#message.flowTokens+1]={kind='newline'}end
                    message.flowTokens[#message.flowTokens+1]={kind='text',value=line}
                end
            else for i,line in ipairs(message.lines)do message.lines[i]=expandText(line)end end
            if message.choices then for i,line in ipairs(message.choices)do message.choices[i]=expandText(line)end end
            local inlineStreams={message.speakerTokens or {}};for _,tokens in ipairs(message.choiceTokens or {})do inlineStreams[#inlineStreams+1]=tokens end
            for _,tokens in ipairs(inlineStreams)do for _,token in ipairs(tokens)do
                if token.kind=='dynamic' then
                    token.kind='text';token.value=expandText('\\'..token.code..'['..string.format('%.0f',token.value)..']');token.code=nil
                elseif token.kind=='currency' then token.kind='text';token.value=data.ui and data.ui.currencyUnit or ''end
            end end
            message.speaker=expandText(message.speaker or '');projectedMessage,projectedMessageOwner=copy(message),battle;return message
        end
        local function namedBattle(view)
            if not view then return nil end
            for _,name in ipairs({'party','targets'})do for _,record in ipairs(view[name] or {})do if record.ref and record.ref.kind=='actor'then record.name=S.getActorName(record.ref.id)end end end
            return view
        end
        function S.getBattle()return not closed and battle and namedBattle(battle.view()) or nil end
        function S.itemChoiceRows(itemType)
            local inventory=party.snapshot().inventory.item
            if battle then inventory=battle.snapshot().partyState.inventory.item end
            local rows={}
            for _,record in ipairs(world.definitions.items)do local count=inventory[record.id] or 0
                if record.itypeId==itemType and count>0 then rows[#rows+1]={id=record.id,count=count}end
            end
            table.sort(rows,function(a,b)return a.id<b.id end);return rows
        end
        function S.submitBattle(request)
            if closed or not battle then return{ok=false,reason=closed and 'closed' or 'no-battle'}end
            return battle.submit(request)
        end
        function S.finishBattle(request)
            if closed or not battle then return{ok=false,reason=closed and 'closed' or 'no-battle'}end
            local view=battle.view()
            if type(request)~='table' or request.battleId~=view.battleId or request.revision~=view.revision then return{ok=false,reason='stale'}end
            local result=battle.result();if not result then return{ok=false,reason='not-ended'}end
            local nextParty=partyService.newParty({state=result.partyState,equipmentPolicy=options.equipmentPolicy})
            local nextActors=program.newActors(nextParty,{state=result.actorsState})
            local nextRng=rngModule.restore(result.rngState).snapshot()
            local fatal=result.code==2 and not battleOwner.canLose
            if fatal then if battleOwner.taskId then vm.cancel(battleOwner.taskId)end
            elseif battleOwner.taskId and not vm.resumeBattle(battleOwner.taskId,battleOwner.token,result.code)then return{ok=false,reason='stale-event'}end
            party,actors,rngState=nextParty,nextActors,nextRng
            lastActionData=copy(result.lastActionData or lastActionData)
            if result.code==0 then wins=wins+1 elseif result.escaped then escapes=escapes+1 end
            battle,battleOwner=nil,nil;gameOver=fatal;invalidateItems();refresh()
            if options.presentation and options.presentation.setBattle then options.presentation.setBattle(false)end
            if options.audio then options.audio.endBattle(result)end
            return{ok=true,code=result.code,gameOver=fatal}
        end
        function S.respond(id,token,answer)
            if closed then return false end
            local current=S.getMessage()
            if current and current.extension then
                local entry=extensionMessages[1]
                if id~=current.taskId or token~=current.token or type(answer)~='table' or answer.kind~='confirm'then return false end
                if not entry.resume(entry.token)then return false end;table.remove(extensionMessages,1);return true
            end
            if not battle and mapMessage then
                if id~=mapMessage.taskId or token~=mapMessage.token or type(answer)~='table'or answer.kind~='confirm'then return false end
                mapMessage=nil;return true
            end
            local message;if battle then message=battle.getMessage()else message=vm.getMessage()end
            if message and message.taskId==id and message.token==token and message.itemChoice and type(answer)=='table' and answer.kind=='item' and answer.id~=0 then
                if not integer(answer.id) or answer.id<1 then return false end
                local found=false
                for _,record in ipairs(S.itemChoiceRows(message.itemChoice.itemType))do if record.id==answer.id then found=true;break end end
                if not found then return false end
            end
            if battle then return battle.respond(id,token,answer)end;return vm.respond(id,token,answer)
        end
        function S.getSettings()local out=copy(settings);out.audioAvailable=options.audio~=nil;return out end
        function S.playSystemSound(name)
            if closed or not options.audio then return false end
            options.audio.systemSound(name);return true
        end
        function S.itemCount(id)return party.count('item',id)end
        function S.setSetting(name,value)
            if closed then return{ok=false,reason='closed'}end
            if settings[name]==nil then return{ok=false,reason='setting'}end
            if name=='alwaysDash' or name=='commandRemember' then
                if type(value)~='boolean'then return{ok=false,reason='value'}end
            elseif not integer(value) or value<0 or value>100 then return{ok=false,reason='value'}end
            local channel=name:match('^(%l+)Volume$')
            if channel and options.audio then options.audio.setVolume(channel,value)end
            settings[name]=value
            if options.onSettingChanged then options.onSettingChanged(name,value,copy(settings))end
            return{ok=true}
        end
        function S.getSceneRequest()
            if closed or not sceneRequest then return nil end
            local out=copy(sceneRequest);out.taskId=nil;return out
        end
        function S.finishSceneRequest(token,answer)
            if closed or not sceneRequest or sceneRequest.token~=token then return{ok=false,reason='stale'}end
            local name
            if sceneRequest.kind=='name'then
                name=type(answer)=='table' and answer.name
                local length=type(name)=='string' and utf8.len(name)
                if not length or length<1 or length>sceneRequest.maxLength or name:find('[%z\1-\31]')then return{ok=false,reason='name'}end
            end
            if not vm.resumeCommand(sceneRequest.taskId,token)then return{ok=false,reason='stale-event'}end
            if name then actorNames[sceneRequest.actorId]=name end
            sceneRequest=nil;return{ok=true}
        end
        local shopDefinitions={item={},weapon={},armor={}}
        local shopLoaded={}
        local function shopDef(kind,id)
            if partyService and type(partyService.getShopDefinition)=='function'then return partyService.getShopDefinition(kind,id)end
            local pool=({item='items',weapon='weapons',armor='armors'})[kind]
            if not pool then return nil end
            if not shopLoaded[kind]then
                for _,record in ipairs(world.definitions[pool])do shopDefinitions[kind][record.id]=record end
                shopLoaded[kind]=true
            end
            return shopDefinitions[kind][id]
        end
        function S.shopComparison(token,kind,id,pageIndex)
            if closed or not sceneRequest or sceneRequest.token~=token then return nil end
            local def=shopDef(kind,id)
            if not actors or not def or kind=='item' then return{rows={},pageIndex=0,pageCount=0}end
            if not integer(pageIndex) or pageIndex<0 then fail('E_WORLD_SHOP','Invalid shop status page')end
            local members=party.members();local pages=math.ceil(#members/4)
            pageIndex=pages>0 and pageIndex%pages or 0
            local parameter=kind=='weapon' and 3 or 4;local rows={}
            local context=actors.actionContext()
            for position=pageIndex*4+1,math.min(#members,pageIndex*4+4)do
                local actorId=members[position];local view=actors.getActor(actorId);local tr=context.query({kind='actor',id=actorId}).traits
                local enabled=not tr.isEquipTypeSealed(def.etypeId) and (kind=='weapon' and tr.isEquipWtypeOk(def.wtypeId) or kind=='armor' and tr.isEquipAtypeOk(def.atypeId))
                local equipped,worst=nil,math.huge
                for slot,etype in ipairs(view.equipmentSlots)do
                    local item=view.equipment[slot]
                    if etype==def.etypeId and item and item~=false then
                        local value=shopDef(item.kind,item.id).params[parameter]
                        if value<worst then equipped,worst=copy(item),value end
                    end
                end
                rows[#rows+1]={actorId=actorId,enabled=enabled,equipped=equipped,delta=enabled and def.params[parameter]-(equipped and worst or 0) or nil}
            end
            return{rows=rows,pageIndex=pageIndex,pageCount=pages,paramId=parameter-1}
        end
        local function syncShopPolicy()
            if not sceneRequest or sceneRequest.kind~='shop'then return end
            local currentRevision=extensionRuntime and extensionRuntime.policyRevision('shop.price')or -1
            if sceneRequest.pricePolicyRevision~=nil and sceneRequest.pricePolicyRevision~=currentRevision then sceneRequest.revision=sceneRequest.revision+1 end
            sceneRequest.pricePolicyRevision=currentRevision
        end
        local function shopPrice(mode,kind,id,basePrice)
            if not integer(basePrice) or basePrice<0 then fail('E_WORLD_SHOP','Invalid shop price')end
            return extensionRuntime and extensionRuntime.policy('shop.price',{mode=mode,kind=kind,id=id,basePrice=basePrice},basePrice)or basePrice
        end
        function S.shopView(token)
            if closed or not sceneRequest or sceneRequest.token~=token then return nil end
            syncShopPolicy()
            local buy,sell={},{}
            for index,good in ipairs(sceneRequest.goods)do
                local def=shopDef(good.kind,good.id)
                if not def then fail('E_WORLD_SHOP','Unknown shop merchandise')end
                local price=shopPrice('buy',good.kind,good.id,good.price==nil and def.price or good.price)
                local count=party.count(good.kind,good.id)
                local maximum=math.max(0,math.min(99-count,price==0 and 99 or math.floor(party.gold()/price)))
                buy[#buy+1]={kind=good.kind,id=good.id,goodsIndex=index-1,price=price,count=count,maximum=maximum,enabled=maximum>0,quoteRevision=sceneRequest.revision}
            end
            local snap=party.snapshot()
            for _,kind in ipairs({'item','weapon','armor'})do
                local ids={};for id,count in pairs(snap.inventory[kind])do if count>0 then ids[#ids+1]=id end end;table.sort(ids)
                for _,id in ipairs(ids)do local def=shopDef(kind,id);local count=party.count(kind,id)
                    local price=shopPrice('sell',kind,id,math.floor(def.price/2))
                    sell[#sell+1]={kind=kind,id=id,itypeId=def.itypeId,price=price,count=count,maximum=count,enabled=not sceneRequest.purchaseOnly and def.price>0,quoteRevision=sceneRequest.revision}
                end
            end
            return{token=token,revision=sceneRequest.revision,purchaseOnly=sceneRequest.purchaseOnly,gold=party.gold(),buy=buy,sell=sell}
        end
        function S.shopTransaction(request)
            syncShopPolicy()
            if type(request)~='table' or not sceneRequest or request.token~=sceneRequest.token or request.revision~=sceneRequest.revision then return{ok=false,reason='stale'}end
            if not integer(request.quantity) or request.quantity<1 then return{ok=false,reason='quantity'}end
            local ok,reason
            if request.mode=='buy' then
                local good=integer(request.goodsIndex) and sceneRequest.goods[request.goodsIndex+1]
                if not good then return{ok=false,reason='goods'}end
                local def=shopDef(good.kind,good.id)
                local price=shopPrice('buy',good.kind,good.id,good.price==nil and def.price or good.price)
                ok,reason=party.buy(good.kind,good.id,request.quantity,price)
            elseif request.mode=='sell' then
                local def=shopDef(request.kind,request.id);if not def then return{ok=false,reason='item'}end
                local price=shopPrice('sell',request.kind,request.id,math.floor(def.price/2))
                ok,reason=party.sell(request.kind,request.id,request.quantity,{purchaseOnly=sceneRequest.purchaseOnly,unitPrice=price})
            else return{ok=false,reason='mode'}end
            if ok then sceneRequest.revision=sceneRequest.revision+1;invalidateItems();refresh()end
            return{ok=ok,reason=reason}
        end
        function S.getBattleCommandMemory(actorId)return copy(battleCommandMemory[actorId])end
        function S.setBattleCommandMemory(actorId,selection)
            if actors and actors.hasActor(actorId) and type(selection)=='table'then battleCommandMemory[actorId]=copy(selection)end
        end
        function S.mapData() return copy(current) end
        -- Internal renderers treat this compiled definition as immutable.
        function S.mapDefinition()return current end
        function S.getActor(id)
            if not actors then fail("E_WORLD_ACTORS","Actor queries require compiled RPG data") end
            return actors.getActor(id)
        end
        local function menuBusy()
            return (not (sceneRequest and sceneRequest.kind=='menu') and S.isBusy()) or player.motion
        end
        function S.swapPartyMembers(first,second)
            if closed then return {ok=false,reason='closed'} end
            settle()
            if menuBusy() then return {ok=false,reason='busy'} end
            local members=party.members()
            if not integer(first) or not integer(second) or first<0 or second<0 or first>=#members or second>=#members then
                fail('E_WORLD_FORMATION','Party position is outside the current party')
            end
            party.swapMembers(first+1,second+1)
            invalidateItems()
            return {ok=true}
        end
        function S.actorProgression(id)
            if not actors then fail("E_WORLD_ACTORS","Actor queries require compiled RPG data") end
            return actors.progression(id)
        end
        local function equipmentAuthority()
            if closed then fail("E_WORLD_CLOSED","World session is closed") end
            if not actors then fail("E_WORLD_ACTORS","Equipment requires compiled RPG data") end
        end
        function S.equipState(id) equipmentAuthority(); return actors.equipState(id) end
        function S.equipCandidates(id,slot) equipmentAuthority(); return actors.equipCandidates(id,slot) end
        function S.previewEquip(id,slot,item)
            equipmentAuthority()
            -- Preview returns a candidate RNG; it must never replace session RNG.
            return actors.previewEquip(id,slot,item,rngState)
        end
        function S.equipmentCommand(command)
            equipmentAuthority(); settle()
            if menuBusy() then return {ok=false,reason="busy"} end
            local result=actors.equipmentCommand(command,rngState)
            if result.ok then invalidateItems();rngState=copy(result.rngState); refresh() end
            return result
        end
        function S.actorCommand(command)
            if closed then fail("E_WORLD_CLOSED","World session is closed") end
            if not actors then fail("E_WORLD_ACTORS","Actor commands require compiled RPG data") end
            settle()
            if menuBusy() then return {ok=false,reason="busy"} end
            local result=actors.command(command,rngState)
            if result.ok then invalidateItems();rngState=copy(result.rngState) end
            return result
        end
        if actions then
            local readContext={members=function()return party.members()end,count=function(...)return party.count(...)end,query=function(ref)
                if not actorQueryCache[ref.id]then actorQueryCache[ref.id]=actors.actionContext().query(ref)end
                return actorQueryCache[ref.id]
            end}
            local function itemInfo(id,kind,userId)
                kind=kind or 'item'
                local ref={kind=kind,id=id};local spec=actions.describe(ref)
                local info={enabled=false,scope=spec.scope,repeats=spec.repeats,all=spec.scope==8 or spec.scope==10 or spec.scope==13 or spec.scope==14,
                    needsTarget=spec.scope~=0,targets={}}
                local best=-math.huge
                if kind=='skill'then
                    local found=false;for _,member in ipairs(readContext.members())do if member==userId then found=true end end
                    if not found then info.reason='no-user';return info end
                    local learned=false;for _,skill in ipairs(readContext.query({kind='actor',id=userId}).skills)do if skill==id then learned=true end end
                    if not learned then info.reason='not-learned';return info end
                    info.userId=userId
                else for _,member in ipairs(readContext.members())do
                    local q=readContext.query({kind='actor',id=member})
                    if not q.hidden and q.restriction<4 and q.sparams[4]>best then info.userId=member;best=q.sparams[4]end
                end end
                if not info.userId then info.reason='no-user';return info end
                local can=actions.canUse({actionRef=ref,subjectRef={kind='actor',id=info.userId},inBattle=false},readContext)
                info.cost=copy(can.cost)
                if not can.ok then info.reason=can.reason;return info end
                if spec.scope==0 then info.enabled=true;return info end
                if spec.scope<7 then info.reason='menu-scope';return info end
                for _,member in ipairs(readContext.members())do
                    if (spec.scope~=11 or member==info.userId) and actions.canApply({actionRef=ref,targetRef={kind='actor',id=member},inBattle=false},readContext) then
                        info.targets[#info.targets+1]=member
                    end
                end
                info.enabled=#info.targets>0
                if not info.enabled then info.reason='no-target'end
                return info
            end
            function S.itemUseInfo(id)
                if closed then return {enabled=false,reason='closed',scope=0,repeats=1,all=false,needsTarget=false,targets={}}end
                if not itemInfoCache[id]then itemInfoCache[id]=itemInfo(id)end
                return copy(itemInfoCache[id])
            end
            function S.skillUseInfo(actorId,id)return copy(itemInfo(id,'skill',actorId))end
            function S.skillMenu(actorId)
                local q=actors.actionContext().query({kind='actor',id=actorId})
                local types=q.traits.addedSkillTypes();table.sort(types)
                local skills={};for _,id in ipairs(q.skills)do local spec=actions.describe({kind='skill',id=id});spec.useInfo=itemInfo(id,'skill',actorId);skills[#skills+1]=spec end
                table.sort(skills,function(a,b)return a.id<b.id end)
                return{types=types,skills=skills}
            end
            local function useAction(id,targetId,kind,actorId)
                if closed then return {ok=false,reason='closed'}end
                settle();if menuBusy() then return {ok=false,reason='busy'}end
                kind=kind or 'item'
                local info=itemInfo(id,kind,actorId);if not info.enabled then return {ok=false,reason=info.reason}end
                local selected={}
                if info.needsTarget then
                    if info.all then
                        selected=readContext.members()
                    else
                        local wanted=info.scope==11 and info.userId or targetId
                        for _,actorId in ipairs(info.targets)do if actorId==wanted then selected[1]=actorId;break end end
                        if #selected==0 then return {ok=false,reason='invalid-target'}end
                    end
                end
                local targets={};for _,actorId in ipairs(selected)do for _=1,info.repeats do targets[#targets+1]={kind='actor',id=actorId}end end
                local result=actors.actionTransaction(rngState,function(ctx)
                    return actions.resolve({actionRef={kind=kind,id=id},subjectRef={kind='actor',id=info.userId},targetRefs=targets,
                        inBattle=false,rngState=rngState,variables=story.snapshot().variables},ctx)
                end)
                if result.ok then
                    if (program and program.profile or data.rpg.profile)~='mv-1.5.1' then
                        lastActionData[kind=='skill' and 1 or 2]=id;lastActionData[3]=info.userId
                        if #targets>0 then lastActionData[5]=targets[#targets].id end
                    end
                    invalidateItems()
                    rngState=copy(result.rngState)
                    for _,event in ipairs(result.commonEvents)do reservedCommon[#reservedCommon+1]=event.programId end
                    refresh()
                end
                return result
            end
            function S.useItem(id,targetId)return useAction(id,targetId,'item')end
            function S.useSkill(actorId,id,targetId)return useAction(id,targetId,'skill',actorId)end
        end
        function S.snapshot()
            local events={}
            for _,event in ipairs(eventStates) do
                local p=page(event)
                events[#events+1]={id=event.id,name=event.definition.name,x=event.x,y=event.y,page=event.page,
                    realX=event.realX or event.x,realY=event.realY or event.y,jumpHeight=event.jumpHeight,pattern=event.pattern==3 and 1 or event.pattern,
                    direction=event.direction,through=event.through==true or not movementModule and p and p.through or false,priorityType=p and p.priorityType,
                    image=copy(event.image or p and p.image),transparent=event.transparent==true,opacity=event.opacity,blendMode=event.blendMode,bushDepth=event.bushDepth or 0,
                    speed=event.speed,frequency=event.frequency,walkAnime=event.walkAnime,stepAnime=event.stepAnime,
                    forcing=event.forcing==true,routeIndex=event.routeIndex,erased=event.erased}
            end
            return {mapId=current.id,auroraHud=aurora and aurora.hud(),player=copy(player),events=events,party=party.snapshot(),story=story.snapshot(),steps=steps,
                timer=timer.snapshot(),access=copy(access),camera=camera.view(),actorImages=copy(actorImages),tilesetId=current.tilesetId,
                windowTone=copy(windowTone),mapName=copy(mapName),battleBackground=copy(battle and battleOwner.background or battleBackground),
                busy=S.isBusy(),errors=copy(errors),mainTask=mainTask and vm.getTask(mainTask),
                actors=actors and actors.snapshot(),rngState=rngState and copy(rngState),battle=battle and namedBattle(battle.view()),gameOver=gameOver or false,
                followers=copy(followers),followersVisible=followersVisible,gathering=gathering,
                vehicles=copy(vehicles),vehiclePhase=vehiclePhase,encounterCount=encounterCount,encountersEnabled=encountersEnabled,
                presentation=options.presentation and options.presentation.snapshot(),extensions=extensionRuntime and copy(extensionRuntime.snapshot()) or {}}
        end
        function S.close()
            if closed then return end
            closed=true;mapMessage=nil;extensionMessages={}
            if options.presentation and options.presentation.close then options.presentation.close()end
            if mainTask then vm.cancel(mainTask) end
            for _,event in ipairs(eventStates) do if event.parallel then cancel(event.parallel); event.parallel=nil end end
            for _,task in pairs(parallelCommon) do cancel(task) end
            parallelCommon={}
            reservedCommon={}
            battle,battleOwner,sceneRequest=nil,nil,nil
        end
        return S
    end
    return M
end
