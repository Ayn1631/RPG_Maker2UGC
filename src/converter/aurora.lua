-- Explicit adapter for the reviewed Aurora plugin revision. No JS evaluation,
-- fuzzy name mapping, disabled plugins or ignored event scripts.
return function(deps)
 local J,F,D=deps['contracts.json'],deps['build.files'],deps['contracts.diagnostic'];local M={}
 local function fail(reason)D.raise('E_AURORA_ADAPTER',reason)end
 local signatures={boss=0,center=1,elite=1,ending=0,gift=1,gym=1,home=0,lab=0,leagueGate=0,leaveLeague=0,legend=1,puzzle=2,rival=1,say=2,shop=0,terminal=0,towerTalk=0,trainer=1,travel={3,4},villain=1}
 function M.wrap(base,config,root)
  if config.gameAdapter~='aurora'then fail('Unknown game adapter')end
  local enabled={};local out={};for k,v in pairs(base)do out[k]=v end
  local function source(path)return assert(F.read(config.sourceRoot..'/'..path))end
  function out.acceptPlugin(plugin,read)
   if plugin.name~='Aurora' and plugin.name~='AuroraCore'then return base.acceptPlugin(plugin,read)end
   if enabled[plugin.name] or next(plugin.parameters or{})then fail('Duplicate plugin or unexpected Aurora parameters')end
   if plugin.name=='Aurora' and not enabled.AuroraCore then fail('Aurora must load after AuroraCore')end
   local reviewed=assert(F.read(root..'/extensions/game.aurora/reviewed/'..plugin.name..'.js'))
   if read('js/plugins/'..plugin.name..'.js')~=reviewed then fail(plugin.name..' differs from the reviewed implementation; update its Lua port before compiling')end
   enabled[plugin.name]=true;return true
  end
  function out.standardUI(name)return enabled[name]or base.standardUI(name)end
  function out.loadData(read,index)
   if not enabled.Aurora or not enabled.AuroraCore then fail('Both Aurora plugins must remain enabled')end
   local declarations,lock=base.loadData(read,index)
   local raw=J.decode(read('data/Aurora.json'));local prepared=J.decode(assert(F.read(root..'/projects/pokemon-aurora/data.json')))
   local chart=prepared.typeChart;prepared.typeChart=nil
   if J.encode(raw)~=J.encode(prepared)then fail('Prepared Aurora data is stale; regenerate from the source project')end
   raw.typeChart=assert(chart);raw.speciesIds=J.array();raw.locations={}
   for id in pairs(raw.species)do raw.speciesIds[#raw.speciesIds+1]=assert(tonumber(id))end;table.sort(raw.speciesIds)
   for _,id in ipairs(raw.speciesIds)do
    local places=J.array();local mapIds={};for k in pairs(raw.maps)do mapIds[#mapIds+1]=tonumber(k)end;table.sort(mapIds)
    for _,mapId in ipairs(mapIds)do local map=raw.maps[tostring(mapId)];for _,v in ipairs(map.pool or{})do if v==id then places[#places+1]=map.name;break end end end
    for _,sid in ipairs(raw.speciesIds)do local sp=raw.species[tostring(sid)];if sp.evolve==id then places[#places+1]=sp.name..'进化';break end end
    if id==134 or id==135 or id==136 then places[#places+1]='研究所：Lv.25伊布选择进化'end
    if id==249 then places[#places+1]='归潮塔'elseif id==150 or id==151 then places[#places+1]='冠军纪念庭（通关后）'end
    raw.locations[tostring(id)]=#places>0 and table.concat(places,'、')or'升级进化或特定训练家'
   end
   local cue=config.audioBindings and config.audioBindings.bgm and config.audioBindings.bgm.Battle
   if type(cue)~='number'or cue%1~=0 or cue<1 then fail('Battle requires an explicit BGM signal index')end
   raw.battleCue={name='Battle',index=cue,volume=35,pitch=100,pan=0}
   raw.eventLabels={}
   for _,map in ipairs(index.maps)do local labels={};raw.eventLabels[tostring(map.id)]=labels
    for _,event in ipairs(map.events)do if event~=J.null then local n=event.name
     if n:find('中心',1,true)or n:find('商店',1,true)or n:match('道馆$')or n:find('研究所',1,true)or n:find('入口',1,true)or n:match('基地$')then labels[tostring(event.id)]=n end
    end end
   end
   index.aurora=raw
   return declarations,lock
  end
  function out.script(text,kind)
   if kind~='command'then return base.script(text,kind)end
   if text=="$gameSelfSwitches.setValue([$gameMap.mapId(),this._eventId,'A'],true);"then return{extensionId='game.aurora',contractVersion=1,command='selfSwitchA',args=J.array()}end
   local method,body=text:match('^%s*Aurora%.([A-Za-z]+)%((.*)%)%s*;?%s*$')
   if not method then return base.script(text,kind)end
   local signature=signatures[method];if not signature then fail('Unsupported Aurora method '..method)end
   local ok,args=pcall(J.decode,'['..body..']');if not ok then fail('Aurora arguments must be explicit JSON literals: '..text)end
   if type(signature)=='number'and #args~=signature or type(signature)=='table'and #args~=signature[1]and #args~=signature[2]then fail('Wrong argument count: '..text)end
   for i,v in ipairs(args)do
    local stringArg=method=='gift'or method=='trainer'or method=='say'and i==1
    if stringArg then if type(v)~='string'then fail('Expected string: '..text)end
    elseif method=='say'and i==2 then
     if type(v)~='string'and not J.is_array(v)then fail('Expected dialogue text')end
     if type(v)=='table'then for _,line in ipairs(v)do if type(line)~='string'then fail('Dialogue lines must be strings')end end end
    elseif type(v)~='number'or v%1~=0 then fail('Expected integer: '..text)end
   end
   return{extensionId='game.aurora',contractVersion=1,command=method,args=args}
  end
  return out
 end
 function M.assets(data,library)
  local A=deps['assets.primitive_art'];local audit={species=0,models=0,exportedModels=0,tiles=0,characterFrames=0,backgrounds=0,scriptCalls=0}
  local function use(category,key,identity)
   local f=library[category]and library[category][key];if not f or f.sourceIdentity~=identity then fail('Exact asset identity missing/mismatched: '..category..'/'..key..' -> '..identity)end
   A.validate(f);return f
  end
  local art={species={},backgrounds={}}
  for _,id in ipairs(data.aurora.speciesIds)do
   local tiers={};art.species[tostring(id)]=tiers;audit.species=audit.species+1
   for _,tier in ipairs({'detail','map','portrait'})do
    local key=string.format('AuroraPokemon%03d',id)..(tier=='detail'and''or'__'..tier)
    local frame=use('pictures',key,'img/pokemon/'..id..'.png');audit.models=audit.models+1
    -- Source overworld uses Heroes characters, not creature map models.
    if tier~='map'then tiers[tier]=frame;audit.exportedModels=audit.exportedModels+1 end
   end
  end
  for _,name in ipairs({'Grass','Sea','Cave','Gym','Snow','Temple'})do art.backgrounds[name]=use('battlebacks1',name,'battlebacks1/'..name..'.png');audit.backgrounds=audit.backgrounds+1 end
  art.title=use('pictures','AuroraTitle','titles1/Aurora.png')
  for set,defs in pairs(data.resources.tiles)do for id,def in pairs(defs)do if tonumber(id)>0 then
   local tileset=data.database.Tilesets.records[tonumber(set)+1]
   if tonumber(id)>=256 or tileset.tilesetNames[6]~='Aurora_B'then fail('Unreviewed tileset slot/tile '..set..':'..id)end
   use('tiles',set..':'..id,'Aurora_B:'..id);audit.tiles=audit.tiles+1
  end end end
  for _,reference in ipairs(deps['converter.character_export'].collect(data))do
   local key=reference.key
   local character=library.characters[key];if not character or not(key:match('^Heroes:[0-7]$')or key=='$Lugia:0')then fail('Unknown character sheet/index '..key)end
   for i,f in ipairs(character.frames)do
    local dir=({2,4,6,8})[math.floor((i-1)/3)+1];if f.sourceIdentity~=key..':direction'..dir..':pattern'..(i-1)%3 then fail('Character direction/pattern mismatch '..key)end
    A.validate(f);audit.characterFrames=audit.characterFrames+1
   end
   if key=='$Lugia:0'then
    for i=2,12 do if J.encode(character.frames[1].rects)~=J.encode(character.frames[i].rects)or J.encode(character.frames[1].palette)~=J.encode(character.frames[i].palette)then fail('Reviewed static Lugia frames differ')end end
    data.resources.characters[key].staticPrimitive=true
   end
  end
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do if ins.op=='extension'and ins.extensionId=='game.aurora'then audit.scriptCalls=audit.scriptCalls+1 end end end
  data.auroraArt=art;data.auroraAssetAudit=audit
  -- An absent match is always an error; there is no inferred asset fallback.
  return audit
 end
 return M
end
