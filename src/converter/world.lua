-- Normalizes the world data used by the map runtime; source objects remain read-only.
return function(deps)
    local json, diagnostic = deps["contracts.json"], deps["contracts.diagnostic"]
    local movement=deps['converter.movement']
    local M = {}
    local function integer(value)
        return type(value)=="number" and value==value and value>=-9007199254740991
            and value<=9007199254740991 and value%1==0
    end
    local function object(value) return type(value)=="table" and value~=json.null and not json.is_array(value) end
    local function copy(value)
        if type(value)~="table" or value==json.null then return value end
        local result=json.is_array(value) and json.array() or json.object()
        for key,item in pairs(value) do result[key]=copy(item) end
        return result
    end
    function M.compile(data)
        local diagnostics=json.array()
        local world=json.object({maps=json.array(),tilesets=json.object(),definitions=json.object(),commonEvents=json.array()})
        local maps, definitions = {}, {}
        local sequenceOnly={};for _,id in ipairs(data.visuGameplay and data.visuGameplay.sequenceCommonEventIds or {})do sequenceOnly[id]=true end
        local movementOptions=data.visuWorld and {compileScript=function(text,source)
            if text~='Balloon: Sleep'then diagnostic.raise('E_MOVE_ROUTE_SCRIPT','Unreviewed Visu movement script',source)end
            return{name='visu_balloon',balloonId=10}
        end}or nil
        local function check(ok,reason,file,path,code)
            if not ok then diagnostic.raise(code or "E_WORLD_SOURCE",reason,{file=file,jsonPath=path}) end
        end
        local function attempt(fn)
            local ok,reason=pcall(fn)
            if not ok then
                if diagnostic.is(reason) then diagnostics[#diagnostics+1]=reason
                else error(reason,0) end
            end
        end
        local database=type(data)=="table" and data.database
        if type(database)~="table" or type(data.eventPrograms)~="table" then
            return {ok=false,diagnostics=json.array({diagnostic.new("E_WORLD_SOURCE","An event package is required")})}
        end
        local system=database.System and database.System.records
        local function record(name,id,file,path)
            local values=database[name] and database[name].records
            local value=type(values)=="table" and integer(id) and id>=1 and values[id+1]
            check(object(value) and value.id==id,"Missing "..name.." reference: "..tostring(id),file,path,"E_WORLD_REFERENCE")
            return value
        end
        local function state_id(kind,id,file,path)
            local values=system and system[kind]
            check(integer(id) and id>=1 and json.is_array(values) and id<#values,"Invalid "..kind.." id",file,path,"E_WORLD_REFERENCE")
        end
        -- Fresh actors have no states. Initial slot layout is actor/class traits;
        -- equipment traits then participate in native monotone release-to-fixed-point.
        local function initial_equipment(actor)
            local file,path="data/Actors.json","$["..actor.id.."]"
            check(json.is_array(system.equipTypes) and #system.equipTypes>=1,
                "System equipTypes must be an array","data/System.json","$.equipTypes")
            for slot,name in ipairs(system.equipTypes) do
                check(type(name)=="string","Equipment type name must be a string","data/System.json","$.equipTypes["..(slot-1).."]")
            end
            check(integer(actor.classId) and actor.classId>=1,"Invalid actor classId",file,path..".classId")
            local class=record("Classes",actor.classId,file,path..".classId")
            local cached={}
            local function traits(value,source_file,source_path)
                if cached[value] then return end
                check(json.is_array(value.traits),"Initial equipment requires a traits array",source_file,source_path..".traits")
                for index,trait in ipairs(value.traits) do
                    local location=source_path..".traits["..(index-1).."]"
                    check(object(trait) and integer(trait.code) and trait.code>=0 and integer(trait.dataId) and trait.dataId>=0,
                        "Invalid equipment trait",source_file,location)
                    if trait.code==55 then
                        check(trait.dataId==0 or trait.dataId==1,"Custom equipment slot types need an adapter",source_file,location,"E_WORLD_UNSUPPORTED")
                    end
                end
                cached[value]=true
            end
            traits(actor,file,path); traits(class,"data/Classes.json","$["..class.id.."]")
            check(json.is_array(actor.equips),"Actor equips must be an array",file,path..".equips")
            local count=#system.equipTypes-1
            local equipment,records=json.array(),{}
            for slot=1,count do equipment[slot]=false end
            local function all_traits()
                local out={}
                for _,owner in ipairs({actor,class}) do for _,trait in ipairs(owner.traits) do out[#out+1]=trait end end
                for slot=1,count do
                    local value=records[slot]
                    if value then for _,trait in ipairs(value.traits) do out[#out+1]=trait end end
                end
                return out
            end
            local function slots()
                local slot_type=0
                for _,trait in ipairs(all_traits()) do if trait.code==55 then slot_type=math.max(slot_type,trait.dataId) end end
                local result={}; for slot=1,count do result[slot]=slot end
                if count>=2 and slot_type==1 then result[2]=1 end
                return result
            end
            local initial_slots=slots()
            for slot,id in ipairs(actor.equips) do
                check(integer(id) and id>=0,"Initial equipment ID must be nonnegative",file,path..".equips["..(slot-1).."]")
                if slot<=count and id>0 then
                    local kind=initial_slots[slot]==1 and "weapon" or "armor"
                    local name=kind=="weapon" and "Weapons" or "Armors"
                    local value=record(name,id,file,path..".equips["..(slot-1).."]")
                    traits(value,"data/"..name..".json","$["..id.."]")
                    local key=kind=="weapon" and "wtypeId" or "atypeId"
                    check(integer(value[key]) and value[key]>=1,"Equipment type must be positive",
                        "data/"..name..".json","$["..id.."]."..key)
                    check(integer(value.etypeId) and value.etypeId>=1,"Equipment slot type must be positive",
                        "data/"..name..".json","$["..id.."].etypeId")
                    records[slot]=value; equipment[slot]=json.object({kind=kind,id=id})
                end
            end
            while true do
                local current_slots=slots(); local changed=false
                for slot=1,count do
                    local value=records[slot]
                    if value then
                        local kind=equipment[slot].kind
                        local permitted,sealed=false,false
                        local code=kind=="weapon" and 51 or 52
                        local type_id=kind=="weapon" and value.wtypeId or value.atypeId
                        -- Re-read traits after each preceding removal, as canEquip does.
                        for _,trait in ipairs(all_traits()) do
                            if trait.code==code and trait.dataId==type_id then permitted=true end
                            if trait.code==54 and trait.dataId==value.etypeId then sealed=true end
                        end
                        if not permitted or sealed or value.etypeId~=current_slots[slot] then
                            equipment[slot]=false; records[slot]=nil; changed=true
                        end
                    end
                end
                if not changed then break end
            end
            return json.object({actorId=actor.id,slots=equipment})
        end
        for _,pair in ipairs({{"Items","items"},{"Weapons","weapons"},{"Armors","armors"},{"Actors","actors"}}) do
            attempt(function()
                local name,key=pair[1],pair[2]
                local records=database[name] and database[name].records
                check(json.is_array(records),name.." must provide records","data/"..name..".json","$")
                local values=json.array(); world.definitions[key]=values; definitions[key]={}
                for slot,value in ipairs(records) do
                    if value~=json.null then
                        local path="$["..(slot-1).."]"
                        check(object(value) and value.id==slot-1 and slot>1,"Invalid record id","data/"..name..".json",path)
                        check(type(value.name)=="string","Record name must be a string","data/"..name..".json",path..".name")
                        if key~="actors" then
                            check(integer(value.price) and value.price>=0,"Item price must be nonnegative","data/"..name..".json",path..".price")
                            if key=="items" then
                                check(type(value.consumable)=="boolean" and integer(value.itypeId) and value.itypeId>=1 and value.itypeId<=4,
                                    "Item requires consumable and itypeId","data/"..name..".json",path)
                            else
                                check(integer(value.etypeId) and value.etypeId>=1,"Equipment requires a positive etypeId","data/"..name..".json",path..".etypeId")
                            end
                        end
                        values[#values+1]=copy(value); definitions[key][value.id]=true
                    end
                end
            end)
        end
        local usedTilesets={}
        for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do if ins.op=='tileset'then usedTilesets[ins.id]=true end end end
        for _,map in ipairs(data.maps or {})do if object(map.settings) and integer(map.settings.tilesetId) and map.settings.tilesetId>=1 then usedTilesets[map.settings.tilesetId]=true end end
        for id in pairs(usedTilesets)do attempt(function()
            local set=record('Tilesets',id,'data/Tilesets.json','$['..id..']')
            check(json.is_array(set.flags),'Tileset flags are missing','data/Tilesets.json','$['..id..'].flags')
            for slot,flag in ipairs(set.flags)do check(integer(flag) and flag>=0 and flag<=0x7fff,'Invalid tileset flag','data/Tilesets.json','$['..id..'].flags['..(slot-1)..']')end
            world.tilesets[string.format('%.0f',id)]=copy(set.flags)
        end)end
        for _,map in ipairs(data.maps or {}) do
            attempt(function()
                local file=map.sourceLocation.file
                local settings=map.settings
                check(object(settings),"Map settings are missing",file,"$")
                local tileset=record("Tilesets",settings.tilesetId,file,"$.tilesetId")
                check(json.is_array(tileset.flags),"Tileset flags are missing","data/Tilesets.json","$["..tileset.id.."].flags")
                for slot,flag in ipairs(tileset.flags) do
                    check(integer(flag) and flag>=0 and flag<=0x7fff,"Tileset flag outside standard MV/MZ bit range",
                        "data/Tilesets.json","$["..tileset.id.."].flags["..(slot-1).."]")
                end
                for slot=1,4*map.width*map.height do
                    local tile=map.tiles[slot]
                    check(integer(tile) and tile>=0 and tileset.flags[tile+1]~=nil,"Tile has no tileset flag",file,"$.data["..(slot-1).."]","E_WORLD_REFERENCE")
                end
                for slot=4*map.width*map.height+1,6*map.width*map.height do
                    local value=map.tiles[slot]
                    local shadow=slot<=5*map.width*map.height
                    check(integer(value) and value>=0 and value<=(shadow and 15 or 255),"Invalid shadow bits or region id",file,"$.data["..(slot-1).."]")
                end
                check(integer(settings.scrollType) and settings.scrollType>=0 and settings.scrollType<=3,"Invalid scrollType",file,"$.scrollType")
                check(type(settings.disableDashing)=="boolean","Map disableDashing must be boolean",file,"$.disableDashing")
                if settings.parallaxName~=nil then check(type(settings.parallaxName)=='string','Invalid parallax name',file,'$.parallaxName')end
                for _,field in ipairs({'parallaxLoopX','parallaxLoopY'})do if settings[field]~=nil then check(type(settings[field])=='boolean','Invalid parallax loop flag',file,'$.'..field)end end
                for _,field in ipairs({'parallaxSx','parallaxSy'})do if settings[field]~=nil then check(integer(settings[field]) and math.abs(settings[field])<=32768,'Invalid parallax speed',file,'$.'..field)end end
                if settings.encounterList~=nil then
                    check(json.is_array(settings.encounterList),'Encounter list must be an array',file,'$.encounterList')
                    check(integer(settings.encounterStep) and settings.encounterStep>=0 and settings.encounterStep<=2147483647,'Invalid encounter step',file,'$.encounterStep')
                    local weight=0
                    for i,encounter in ipairs(settings.encounterList)do
                        local ep='$.encounterList['..(i-1)..']'
                        check(object(encounter),'Encounter must be an object',file,ep)
                        record('Troops',encounter.troopId,file,ep..'.troopId')
                        check(integer(encounter.weight) and encounter.weight>=0 and encounter.weight<=2147483647,'Invalid encounter weight',file,ep..'.weight')
                        weight=weight+encounter.weight;check(weight<=2147483647,'Encounter total weight exceeds RNG range',file,ep)
                        check(json.is_array(encounter.regionSet),'Encounter regions must be an array',file,ep..'.regionSet')
                        for _,region in ipairs(encounter.regionSet)do check(integer(region)and region>=0 and region<=255,'Invalid encounter region',file,ep..'.regionSet')end
                    end
                end
                local output=json.object({id=map.id,width=map.width,height=map.height,tilesetId=tileset.id,
                    scrollType=settings.scrollType,tiles=copy(map.tiles),flags=copy(tileset.flags),events=json.array(),settings=copy(settings)})
                for slot,event in ipairs(map.events) do
                    if event~=json.null then
                        local path="$.events["..(slot-1).."]"
                        check(integer(event.x) and event.x>=0 and event.x<map.width and integer(event.y) and event.y>=0 and event.y<map.height,
                            "Event coordinates outside map",file,path)
                        local normalized=json.object({id=event.id,name=event.name or "",x=event.x,y=event.y,pages=json.array()})
                        for number,page in ipairs(event.pages) do
                            local page_path=path..".pages["..(number-1).."]"
                            local c=page.conditions
                            check(object(c),"Missing page conditions",file,page_path..".conditions")
                            for _,key in ipairs({"switch1","switch2","variable","selfSwitch","item","actor"}) do
                                check(type(c[key.."Valid"])=="boolean","Condition enabled flag must be boolean",file,page_path..".conditions."..key.."Valid")
                            end
                            if c.switch1Valid then state_id("switches",c.switch1Id,file,page_path) end
                            if c.switch2Valid then state_id("switches",c.switch2Id,file,page_path) end
                            if c.variableValid then
                                state_id("variables",c.variableId,file,page_path)
                                check(integer(c.variableValue),"Variable threshold must be a safe integer",file,page_path)
                            end
                            if c.selfSwitchValid then check(c.selfSwitchCh=="A" or c.selfSwitchCh=="B" or c.selfSwitchCh=="C" or c.selfSwitchCh=="D","Invalid self switch",file,page_path) end
                            if c.itemValid then record("Items",c.itemId,file,page_path) end
                            if c.actorValid then record("Actors",c.actorId,file,page_path) end
                            check(integer(page.trigger) and page.trigger>=0 and page.trigger<=4,"Invalid page trigger",file,page_path)
                            check(integer(page.priorityType) and page.priorityType>=0 and page.priorityType<=2,"Invalid page priority",file,page_path)
                            check(type(page.through)=="boolean","Page through must be boolean",file,page_path)
                            check(type(page.directionFix)=="boolean","Page directionFix must be boolean",file,page_path..".directionFix")
                            local image=page.image
                            check(object(image),"Page image must be an object",file,page_path..".image")
                            check(integer(image.tileId) and image.tileId>=0,"Event tile id must be a nonnegative integer",file,page_path..".image.tileId")
                            check(tileset.flags[image.tileId+1]~=nil,
                                "Event tile has no tileset flag",file,page_path..".image.tileId","E_WORLD_REFERENCE")
                            for id,flags in pairs(world.tilesets)do
                                check(flags[image.tileId+1]~=nil,"Event tile has no flag in switchable tileset "..id,file,page_path..".image.tileId","E_WORLD_REFERENCE")
                            end
                            check(image.direction==2 or image.direction==4 or image.direction==6 or image.direction==8,
                                "Image direction must be cardinal",file,page_path..".image.direction")
                            check(integer(image.pattern) and image.pattern>=0 and image.pattern<=2,"Invalid image pattern",file,page_path..".image.pattern")
                            check(integer(image.characterIndex) and image.characterIndex>=0 and image.characterIndex<=7 and type(image.characterName)=="string",
                                "Invalid character image",file,page_path..".image")
                            check(integer(page.moveSpeed) and page.moveSpeed>=1 and page.moveSpeed<=6,"Invalid move speed",file,page_path..".moveSpeed")
                            check(integer(page.moveFrequency) and page.moveFrequency>=1 and page.moveFrequency<=5,"Invalid move frequency",file,page_path..".moveFrequency")
                            check(integer(page.moveType) and page.moveType>=0 and page.moveType<=3,"Invalid autonomous movement type",file,page_path..".moveType")
                            local route=page.moveType==3 and movement.compile(page.moveRoute,{file=file,jsonPath=page_path..'.moveRoute'},movementOptions) or nil
                            for _,key in ipairs({'walkAnime','stepAnime'})do check(page[key]==nil or type(page[key])=='boolean','Page '..key..' must be boolean',file,page_path..'.'..key)end
                            local programId="map:"..map.id..":event:"..event.id..":page:"..number
                            check(data.eventPrograms[programId]~=nil,"Page program is missing",file,page_path,"E_WORLD_REFERENCE")
                            normalized.pages[#normalized.pages+1]=json.object({conditions=copy(c),programId=programId,
                                image=copy(page.image),trigger=page.trigger,priorityType=page.priorityType,through=page.through,
                                directionFix=page.directionFix,moveSpeed=page.moveSpeed,moveFrequency=page.moveFrequency,moveType=page.moveType,
                                walkAnime=page.walkAnime,stepAnime=page.stepAnime,moveRoute=route,visuHitbox=copy(page.visuHitbox)})
                        end
                        output.events[#output.events+1]=normalized
                    end
                end
                world.maps[#world.maps+1]=output; maps[map.id]=output
            end)
        end
        attempt(function()
            local values=database.CommonEvents.records
            for slot,event in ipairs(values) do
                if event~=json.null and not sequenceOnly[event.id] then
                    local path="$["..(slot-1).."]"
                    check(integer(event.trigger) and event.trigger>=0 and event.trigger<=2,"Invalid common trigger","data/CommonEvents.json",path)
                    if event.trigger~=0 then state_id("switches",event.switchId,"data/CommonEvents.json",path) end
                    world.commonEvents[#world.commonEvents+1]=json.object({id=event.id,trigger=event.trigger,
                        switchId=event.switchId,programId="common:"..event.id})
                end
            end
        end)
        attempt(function()
            check(object(system),"Missing System","data/System.json","$")
            local start=maps[system.startMapId]
            check(start~=nil,"Missing start map","data/System.json","$.startMapId","E_WORLD_REFERENCE")
            check(integer(system.startX) and system.startX>=0 and system.startX<start.width
                and integer(system.startY) and system.startY>=0 and system.startY<start.height,"Invalid start coordinates","data/System.json","$")
            check(json.is_array(system.partyMembers),"Missing partyMembers","data/System.json","$.partyMembers")
            local members,seen=json.array(),{}
            for _,id in ipairs(system.partyMembers) do
                record("Actors",id,"data/System.json","$.partyMembers")
                check(not seen[id],"Duplicate initial actor","data/System.json","$.partyMembers")
                members[#members+1]=id; seen[id]=true
            end
            world.start=json.object({mapId=system.startMapId,x=system.startX,y=system.startY,direction=2})
            world.playerTransparent=system.optTransparent==true
            world.followersVisible=system.optFollowers~=false
            world.vehicles=json.object()
            for _,kind in ipairs({'boat','ship','airship'})do
                local vehicle=system[kind]
                if vehicle~=nil then
                    local path='$.'..kind
                    check(object(vehicle)and integer(vehicle.startMapId)and vehicle.startMapId>=0,'Invalid vehicle map','data/System.json',path)
                    check(integer(vehicle.startX)and integer(vehicle.startY),'Invalid vehicle position','data/System.json',path)
                    if vehicle.startMapId>0 then
                        local target=maps[vehicle.startMapId];check(target~=nil,'Missing vehicle map','data/System.json',path..'.startMapId','E_WORLD_REFERENCE')
                        check(vehicle.startX>=0 and vehicle.startX<target.width and vehicle.startY>=0 and vehicle.startY<target.height,'Vehicle position outside map','data/System.json',path)
                    end
                    check(type(vehicle.characterName)=='string'and integer(vehicle.characterIndex)and vehicle.characterIndex>=0 and vehicle.characterIndex<=7,'Invalid vehicle image','data/System.json',path)
                    world.vehicles[kind]=copy(vehicle)
                end
            end
            local equipment=json.array()
            for _,actor in ipairs(world.definitions.actors or {}) do equipment[#equipment+1]=initial_equipment(actor) end
            world.party=json.object({members=members,initialEquipment=equipment})
        end)
        table.sort(diagnostics,function(a,b) return (a.file or "")..(a.jsonPath or "")..a.code < (b.file or "")..(b.jsonPath or "")..b.code end)
        if #diagnostics>0 then return {ok=false,diagnostics=diagnostics} end
        return {ok=true,world=world,diagnostics=diagnostics}
    end
    return M
end
