-- Battle wiring and event-page metadata are compiled once on the desktop.
return function(deps)
 local Lifecycle,serialize=deps['runtime.rpg.battle_lifecycle'],deps['build.serialize']
 local M={};local SAFE=9007199254740991
 local function fail(reason,source,code)
  local e={severity='error',code=code or 'E_BATTLE_UNSUPPORTED',reason=reason}
  for k,v in pairs(source or {})do e[k]=v end;error(e,0)
 end
 function M.compile(definitions,eventPrograms)
  if definitions.profile~='mz-1.10.0'and definitions.profile~='mv-1.5.1'then fail('Unsupported battle source profile')end
  local system=definitions.system.battleSystem or 0
  if type(system)~='number'or system%1~=0 or system<0 or system>2 or definitions.profile=='mv-1.5.1'and system~=0 then fail('Invalid battle system for source profile',{file='data/System.json',jsonPath='$.battleSystem'})end
  local troops,names,actorIds={},{},{}
  for _,troop in ipairs(definitions.troops)do troops[troop.id]=true end
  for _,actor in ipairs(definitions.actors)do names[actor.id]=actor.name;actorIds[actor.id]=true end
  local eventCatalog={kind='r2u.battle-event-catalog',schemaVersion=1,troopPagesById={}}
  local flags={'turnEnding','turnValid','enemyValid','actorValid','switchValid'}
  local conditionFields={turnEnding=true,turnValid=true,enemyValid=true,actorValid=true,switchValid=true,turnA=true,turnB=true,enemyIndex=true,enemyHp=true,actorId=true,actorHp=true,switchId=true}
  for _,troop in ipairs(definitions.troops)do
   local meta=troop.sourceMeta or {};local path=meta.jsonPath or ('$['..troop.id..']');local file=meta.file or 'data/Troops.json'
   local pages=meta.unhandledFields and meta.unhandledFields.pages
   if pages==nil then pages={}end
   local function check(ok,reason,suffix,code)if not ok then fail(reason,{file=file,jsonPath=path..suffix},code or 'E_BATTLE_EVENT_SHAPE')end end
   local function dense(v,suffix)
    check(type(v)=='table' and getmetatable(v)==nil,'Expected plain source page array',suffix)
    local count,high=0,0;for k in pairs(v)do check(type(k)=='number' and k%1==0 and k>=1 and k<=100000,'Invalid source page index',suffix);count=count+1;high=math.max(high,k)end
    check(count==high,'Sparse source page array',suffix);return count
   end
   local function number(v,lo,hi,whole,suffix)
    check(type(v)=='number' and v==v and v>=lo and v<=hi and (not whole or v%1==0),'Invalid source page number',suffix);return v
   end
   local out={};eventCatalog.troopPagesById[troop.id]=out
   for i=1,dense(pages,'.pages')do
    local page=pages[i];local pp='.pages['..(i-1)..']'
    check(type(page)=='table' and getmetatable(page)==nil,'Source battle page must be plain',pp)
    local c=page.conditions;check(type(c)=='table' and getmetatable(c)==nil,'Source battle conditions must be plain',pp..'.conditions')
    for key in pairs(c)do
     check(type(key)=='string','Source battle condition keys must be text',pp..'.conditions')
     check(conditionFields[key]==true,'Unknown source battle condition',pp..'.conditions.'..key)
    end
    local conditions={};for _,key in ipairs(flags)do check(type(c[key])=='boolean','Source condition flag must be boolean',pp..'.conditions.'..key);conditions[key]=c[key]end
    for _,key in ipairs({'turnA','turnB','enemyIndex','actorId','switchId'})do conditions[key]=number(c[key],0,SAFE,true,pp..'.conditions.'..key)end
    for _,key in ipairs({'enemyHp','actorHp'})do conditions[key]=number(c[key],0,100,false,pp..'.conditions.'..key)end
    if c.enemyValid then check(type(troop.members)=='table' and c.enemyIndex<#troop.members,'Battle condition enemy index is outside the source troop',pp..'.conditions.enemyIndex','E_BATTLE_EVENT_REFERENCE')end
    if c.actorValid then check(actorIds[c.actorId]==true,'Battle condition Actor does not exist',pp..'.conditions.actorId','E_BATTLE_EVENT_REFERENCE')end
    if c.switchValid then
     local switches=definitions.system.switches
     check(type(switches)=='table' and c.switchId>=1 and c.switchId<#switches,'Battle condition switch does not exist',pp..'.conditions.switchId','E_BATTLE_EVENT_REFERENCE')
    end
    local span=number(page.span,0,2,true,pp..'.span');local programId='troop:'..string.format('%.0f',troop.id)..':page:'..i
    local program=eventPrograms[programId]
    check(type(program)=='table' and type(program.context)=='table' and program.context.troopId==troop.id and program.context.page==i,'Compiled troop page program is missing or belongs to another page',pp..'.list','E_BATTLE_EVENT_REFERENCE')
    out[i]={programId=programId,span=span,conditions=conditions}
   end
  end
  -- Reject orphaned compiled page programs instead of silently dropping their
  -- source conditions when constructing the runtime catalog.
  for id,program in pairs(eventPrograms)do local ctx=program.context
   if ctx and ctx.troopId then
    local pages=eventCatalog.troopPagesById[ctx.troopId];local page=pages and pages[ctx.page]
    if not page or page.programId~=id then
     local ins=type(program.instructions)=='table' and program.instructions[1]
     fail('Compiled troop program has no source battle page',ins and ins.source,'E_BATTLE_EVENT_REFERENCE')
    end
   end
  end
  local catalog=Lifecycle.prepare(definitions,definitions.profile)
  local metadata=definitions.system.sourceMeta and definitions.system.sourceMeta.unhandledFields or {}
  local locale=definitions.system.locale or metadata.locale or ''
  local sourceMeta=definitions.system.sourceMeta and definitions.system.sourceMeta.unhandledFields or {};local config={visuAlwaysEscape=sourceMeta.visuCore and sourceMeta.visuCore.EscapeAlways or nil,visuGameplay=sourceMeta.visuGameplay or nil,profile=definitions.profile,battleSystem=definitions.system.battleSystem or 0,actorNames=names,optExtraExp=definitions.system.optExtraExp,maxBattleMembers=4,
   isCJK=locale:match('^ja')~=nil or locale:match('^zh')~=nil or locale:match('^ko')~=nil}
  local dependencies={'runtime.rpg.battle','runtime.rpg.battle_events','runtime.rpg.battle_lifecycle','generated.actor_program','generated.party_program','generated.enemy_program','generated.action_program'}
  local source="-- Offline battle program; only mutable state is created at runtime.\nreturn function(deps)\n local lifecycle=deps['runtime.rpg.battle_lifecycle'].fromCompiledCatalog("..serialize.literal(catalog)..")\n local controller=deps['runtime.rpg.battle_events'].fromCompiledCatalog("..serialize.literal(eventCatalog)..")\n local config="..serialize.literal(config).."\n local troops="..serialize.literal(troops).."\n return {kind='r2u.battle-program',schemaVersion=1,catalogVersion=1,profile="..serialize.literal(definitions.profile)..",\n hasTroop=function(id)return troops[id]==true end,\n troopAgility=function(id)return deps['generated.enemy_program'].troopAgility(id)end,\n newBattle=function(options)\n  local request={};for k,v in pairs(options)do request[k]=v end\n  for k,v in pairs(config)do request[k]=v end\n  if options.battleSystem~=nil then request.battleSystem=options.battleSystem end\n  request.actorProgram=deps['generated.actor_program'];request.partyProgram=deps['generated.party_program']\n  request.enemyProgram=deps['generated.enemy_program'];request.actions=deps['generated.action_program'].actions;request.lifecycle=lifecycle\n  local core=deps['runtime.rpg.battle'].new(request)\n  return controller.new(core,{battleId=options.battleId,troopId=options.troopId,eventPrograms=options.eventPrograms,ui=options.ui,stateStore=options.stateStore,audio=options.audio,presentation=options.presentation,actorName=options.actorName,timer=options.timer,accessCommand=options.accessCommand,gameData=options.gameData,actorText=options.actorText,resetActorPresentation=options.resetActorPresentation,mapCommand=options.mapCommand,worldCondition=options.worldCondition,extensionCommand=options.extensionCommand,state=options.state and options.state.eventRuntime})\n end}\nend\n"
  return{kind='r2u.battle-program',schemaVersion=1,catalogVersion=1,profile=definitions.profile,
   moduleId='generated.battle_program',dependencies=dependencies,source=source,stats={bytes=#source}}
 end
 return M
end
