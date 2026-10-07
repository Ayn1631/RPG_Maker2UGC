-- Resolve names and host indices once, while the source project is available.
return function(deps)
 local D,json=deps['contracts.diagnostic'],deps['contracts.json'];local M={}
 local function fail(reason,source)D.raise('E_AUDIO_BINDING',reason,source)end
 local function number(v,lo,hi)return type(v)=='number' and v==v and v%1==0 and v>=lo and v<=hi end
 function M.compile(data,bindings)
  local catalog={kind='r2u.audio-catalog',schemaVersion=1,enabled=bindings~=nil,maps={},signals={bgm='R2U_BGM',bgs='R2U_BGS',me='R2U_ME',se='R2U_SE'}}
  if bindings~=nil then
   if type(bindings)~='table'then fail('audioBindings must be a table')end
   for key in pairs(bindings)do if key~='signals' and key~='uiFeedback' and not catalog.signals[key]then fail('Unknown audioBindings field '..tostring(key))end end
   for channel,name in pairs(bindings.signals or {})do
    if not catalog.signals[channel] or type(name)~='string' or name=='' or #name>128 then fail('Invalid audio signal name')end
    catalog.signals[channel]=name
   end
  end
  local unresolved=json.array();local seen={}
  local function cue(channel,source,location)
   if type(source)~='table' or type(source.name)~='string' then fail('Expected RPG Maker audio object',location)end
   for _,key in ipairs({'volume','pitch','pan'})do
    local lo=key=='pan' and -100 or key=='pitch' and 50 or 0
    local hi=key=='pitch' and 150 or 100
    if not number(source[key],lo,hi)then fail('Invalid audio '..key,location)end
   end
   local index,audioId=0,nil
   if source.name~=''then
    local entry=bindings and bindings[channel] and bindings[channel][source.name]
    index=type(entry)=='table' and entry.index or entry
    if type(entry)=='table' and entry.audioId~=nil then
     if channel~='se' or not number(entry.audioId,1,2147483647)then fail('audioId requires a positive SE resource ID',location)end
     audioId=entry.audioId
    end
    if catalog.enabled and not number(index,1,2147483647)then fail('Bind '..channel..'/'..source.name..' to an integer index in audioBindings',location)end
    if not catalog.enabled then
     index=0;local key=channel..'/'..source.name
     if not seen[key]then unresolved[#unresolved+1]=key;seen[key]=true end
    end
   end
   return {index=index,audioId=audioId,name=source.name,volume=source.volume,pitch=source.pitch,pan=source.pan}
  end
  local battle=false
  if data.visuGameplay then
   for _,skill in ipairs(data.database.Skills.records)do if skill~=json.null and skill.visu then
    for _,command in ipairs(skill.visu.sequence or {})do if command.command=='sound' then
     command.args[1]=cue('se',command.args[1],command.source)
    end end
   end end
   for _,animation in ipairs(data.database.Animations.records)do if animation~=json.null then
    for _,timing in ipairs(animation.soundTimings or {})do
     local available=timing.se and bindings and bindings.se and bindings.se[timing.se.name]
     if available or timing.se and timing.se.name==''then timing.se=cue('se',timing.se,{file='data/Animations.json',jsonPath='$['..animation.id..'].soundTimings'})end
    end
   end end
  end
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
   if ins.op=='battle'then battle=true end
   if ins.op=='audio' and ins.cue then ins.cue=cue(ins.channel,ins.cue,ins.source)end
   if ins.op=='vehicle_bgm'then ins.cue=cue('bgm',ins.cue,ins.source)end
   if ins.op=='move_route' then for _,command in ipairs(ins.route.list)do if command.cue then command.cue=cue('se',command.cue,ins.source)end end end
  end end
  for _,map in ipairs(data.maps or {})do
   local item={};local settings=map.settings or map
   if settings.encounterList and #settings.encounterList>0 then battle=true end
   for _,event in ipairs(map.events or {})do if type(event)=='table' then for _,page in ipairs(event.pages or {})do
    for _,command in ipairs(page.moveRoute and page.moveRoute.list or {})do
     if command.code==44 then command.parameters[1]=cue('se',command.parameters[1],{file=string.format('data/Map%03d.json',map.id)})end
    end
   end end end
   if settings.autoplayBgm then item.bgm=cue('bgm',settings.bgm,{file=string.format('data/Map%03d.json',map.id),jsonPath='$.bgm'})end
   if settings.autoplayBgs then item.bgs=cue('bgs',settings.bgs,{file=string.format('data/Map%03d.json',map.id),jsonPath='$.bgs'})end
   catalog.maps[tostring(map.id)]=item
  end
  local system=data.database.System.records
  catalog.systemSounds={}
  for name,index in pairs({cursor=0,ok=1,cancel=2,buzzer=3,equip=4,shop=21,useItem=22,useSkill=23})do
   if system.sounds and system.sounds[index+1]then
    catalog.systemSounds[name]=cue('se',system.sounds[index+1],{file='data/System.json',jsonPath='$.sounds['..index..']'})
   end
  end
  for _,kind in ipairs({'boat','ship','airship'})do
   if type(system[kind])=='table' and system[kind].bgm then system[kind].bgm=cue('bgm',system[kind].bgm,{file='data/System.json',jsonPath='$.'..kind..'.bgm'})end
  end
  if system.titleBgm then catalog.titleBgm=cue('bgm',system.titleBgm,{file='data/System.json',jsonPath='$.titleBgm'})end
  if battle then
   for name,index in pairs({battleStart=7,escape=8,enemyAttack=9,enemyDamage=10,enemyCollapse=11,bossCollapse1=12,bossCollapse2=13,
    actorDamage=14,actorCollapse=15,recovery=16,miss=17,evasion=18,magicEvasion=19,reflection=20})do
    if system.sounds and system.sounds[index+1]then
     catalog.systemSounds[name]=cue('se',system.sounds[index+1],{file='data/System.json',jsonPath='$.sounds['..index..']'})
    end
   end
   for field,channel in pairs({battleBgm='bgm',victoryMe='me',defeatMe='me'})do
    if system[field]then catalog[field]=cue(channel,system[field],{file='data/System.json',jsonPath='$.'..field})end
   end
  end
  -- Explicit additional host UI sounds, separate from source music/SE mappings.
  for name,id in pairs(bindings and bindings.uiFeedback or{})do
   if not ({cursor=true,ok=true,cancel=true,buzzer=true})[name]or not number(id,1,2147483647)then fail('Invalid explicit UI feedback binding')end
   catalog.systemSounds[name]={name='ui:'..name,index=id,audioId=id,volume=45,pitch=100,pan=0}
  end
  table.sort(unresolved);catalog.unbound=unresolved
  return catalog
 end
 return M
end
