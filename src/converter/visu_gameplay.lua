-- Source-scoped VisuStella data/sequence lowering. No JavaScript is evaluated.
return function(deps)
 local J,D=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function fail(s)D.raise('E_VISU_GAMEPLAY',s)end
 local function trim(s)return s:match('^%s*(.-)%s*$')end
 local function cp(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=cp(x)end;return t end
 local function num(v)local n=tonumber(v);if not n or n~=n or math.abs(n)>10000000 then fail('Invalid bounded number '..tostring(v))end;return n end
 local function decode(v)if type(v)~='string'then fail('Expected encoded parameter')end;local ok,r=pcall(J.decode,v);if not ok then fail('Invalid parameter JSON')end;return r end
 local expressions={['Graphics.width']='width',['Graphics.height']='height',['$subject.battler().x']='subjectX',['$subject.battler().y']='subjectY',['$target.battler().x']='targetX',['$target.battler().y']='targetY',['BattleManager._target.battler().height']='targetHeight'}
 -- A tiny arithmetic grammar; the resulting AST is data, never executable Lua.
 function M.expression(source)
  if source:find('@',1,true)then fail('Unsupported expression '..source)end
  if tonumber(source)then return num(source)end
  local s=source;for text,symbol in pairs(expressions)do s=s:gsub(text:gsub('([^%w])','%%%1'),'@'..symbol)end
  local pos=1;local parse
  local function space()local _,e=s:find('^%s*',pos);pos=(e or pos-1)+1 end
  local function atom()space();local c=s:sub(pos,pos)
   if c=='+'or c=='-'then pos=pos+1;return{op=c=='+'and'positive'or'negative',value=atom()}end
   if c=='('then pos=pos+1;local v=parse();space();if s:sub(pos,pos)~=')'then fail('Unclosed expression '..source)end;pos=pos+1;return v end
   local name=s:match('^@([A-Za-z]+)',pos);if name then pos=pos+#name+1;return{symbol=name}end
   local n=s:match('^%d*%.?%d+',pos);if n then pos=pos+#n;return num(n)end;fail('Unsupported expression '..source)
  end
  local function product()local a=atom();while true do space();local op=s:sub(pos,pos);if op~='*'and op~='/'then return a end;pos=pos+1;a={op=op,left=a,right=atom()}end end
  function parse()local a=product();while true do space();local op=s:sub(pos,pos);if op~='+'and op~='-'then return a end;pos=pos+1;a={op=op,left=a,right=product()}end end
  local out=parse();space();if pos<=#s then fail('Unsupported expression '..source)end;return out
 end
 local commandNames={}
 for s in ('Set_SetupAction Set_FinishAction Mechanics_ActionEffect Mechanics_Immortal Mechanics_HpMpTp Mechanics_AddBuffDebuff Element_ForceElements Element_Clear Animation_ActionAnimation Animation_ShowAnimation Animation_WaitForAnimation Animation_PlayAtCoordinate Movement_Jump Movement_MoveToTarget Movement_Opacity Movement_FaceDirection Movement_MoveBy Movement_MoveToPoint Movement_Float Movement_Spin Motion_MotionType Motion_PerformAction Motion_FreezeMotionFrame Motion_ClearFreezeFrame BattleLog_UI BattleLog_Clear Impact_MotionTrailCreate Impact_MotionTrailRemove Impact_ShockwaveEachTargets Impact_Oversaturate Impact_TimeStop Impact_TimeScale Impact_ZoomBlurPoint Impact_ColorBreak Impact_BlueRedInvert Projectile_Animation'):gmatch('%S+')do commandNames['ActSeq_'..s]=true end
 local commandFields={
  ['ActSeq_Animation_ActionAnimation']='Mirror Targets WaitForAnimation',
  ['ActSeq_Animation_PlayAtCoordinate']='AnimationID Mirror Mute WaitComplete pointX pointY',
  ['ActSeq_Animation_ShowAnimation']='AnimationID Mirror Targets WaitForAnimation',
  ['ActSeq_BattleLog_UI']='ShowHide',
  ['ActSeq_Element_ForceElements']='Elements',
  ['ActSeq_Impact_BlueRedInvert']='Enable',
  ['ActSeq_Impact_ColorBreak']='Duration EasingType Intensity',
  ['ActSeq_Impact_MotionTrailCreate']='Targets delay duration hue opacityStart tone',
  ['ActSeq_Impact_MotionTrailRemove']='Targets',
  ['ActSeq_Impact_Oversaturate']='Enable',
  ['ActSeq_Impact_ShockwaveEachTargets']='Amp Duration OffsetX OffsetY TargetLocation Targets Wave',
  ['ActSeq_Impact_TimeScale']='Scale',
  ['ActSeq_Impact_TimeStop']='ms',
  ['ActSeq_Impact_ZoomBlurPoint']='Duration EasingType Radius Strength X Y',
  ['ActSeq_Mechanics_ActionEffect']='Targets',
  ['ActSeq_Mechanics_AddBuffDebuff']='Buffs Debuffs Targets Turns',
  ['ActSeq_Mechanics_HpMpTp']='HP_Flat HP_Rate MP_Flat MP_Rate ShowPopup TP_Flat TP_Rate Targets',
  ['ActSeq_Mechanics_Immortal']='Immortal Targets',
  ['ActSeq_Motion_ClearFreezeFrame']='Targets',
  ['ActSeq_Motion_FreezeMotionFrame']='Frame MotionType ShowWeapon Targets',
  ['ActSeq_Motion_MotionType']='MotionType ShowWeapon Targets',
  ['ActSeq_Motion_PerformAction']='Targets',
  ['ActSeq_Movement_FaceDirection']='Direction Targets',
  ['ActSeq_Movement_Float']='Duration EasingType Height Targets WaitForFloat',
  ['ActSeq_Movement_Jump']='Duration Height Targets WaitForJump',
  ['ActSeq_Movement_MoveBy']='DistanceAdjust DistanceX DistanceY Duration EasingType FaceDirection MotionType Targets WaitForMovement',
  ['ActSeq_Movement_MoveToPoint']='Destination Duration EasingType FaceDirection MotionType OffsetAdjust OffsetX OffsetY Targets WaitForMovement',
  ['ActSeq_Movement_MoveToTarget']='Duration EasingType FaceDirection MeleeDistance MotionType OffsetAdjust OffsetX OffsetY TargetLocation Targets1 Targets2 WaitForMovement',
  ['ActSeq_Movement_Opacity']='Duration EasingType Opacity Targets WaitForOpacity',
  ['ActSeq_Movement_Spin']='Angle Duration EasingType RevertAngle Targets WaitForSpin',
  ['ActSeq_Projectile_Animation']='AnimationID Duration Extra Goal Start WaitForAnimation WaitForProjectile',
  ['ActSeq_Set_FinishAction']='ActionEnd ApplyImmortal ClearBattleLog WaitForEffect WaitForMovement WaitForNewLine',
  ['ActSeq_Set_SetupAction']='ActionStart ApplyImmortal CastAnimation DisplayAction WaitForAnimation WaitForMovement',
 }
 local function arguments(raw)
  local out={};for key,value in pairs(raw)do
   local name,kind=key:match('^([^:]+):(.+)$')
   if name then
    if kind=='str'then out[name]=value
    elseif kind=='num'then out[name]=num(value)
    elseif kind=='eval'then
     if value=='true'or value=='false'then out[name]=value=='true'
     elseif value:match('^%s*%[')then out[name]=cp(decode(value))
     else out[name]=M.expression(value)end
    elseif kind=='arraystr'or kind=='arraynum'then out[name]=cp(decode(value));if kind=='arraynum'then for i,v in ipairs(out[name])do out[name][i]=num(v)end end
    elseif kind=='struct'then out[name]=arguments(decode(value))
    else fail('Unsupported parameter type '..key)end
   elseif value~=''and raw[key..':eval']==nil and raw[key..':num']==nil and raw[key..':str']==nil and raw[key..':arraystr']==nil and raw[key..':arraynum']==nil then fail('Unrecognized command field '..key)end
  end;return out
 end
 function M.compileSequence(event,enabled)
  local out={};local stack={};local active=true
  for slot,c in ipairs(event.list)do local code,p=c.code,c.parameters
   if code==111 then
    if p[1]~=12 or p[2]~='Imported.VisuMZ_3_ActSeqProjectiles'then fail('Unsupported sequence branch at CommonEvents['..event.id..'].list['..(slot-1)..']')end
    local condition=enabled and enabled.VisuMZ_3_ActSeqProjectiles or false
    stack[#stack+1]={parent=active,condition=condition};active=active and condition
   elseif code==411 then local top=stack[#stack];if not top then fail('Orphan sequence else')end;active=top.parent and not top.condition
   elseif code==412 then local top=table.remove(stack);if not top then fail('Orphan sequence branch end')end;active=top.parent
   elseif active then
    local row={source={commonEventId=event.id,commandIndex=slot-1}}
    if code==357 then
     if p[1]~='VisuMZ_1_BattleCore'or not commandNames[p[2]]then fail('Unsupported sequence command '..tostring(p[1])..'.'..tostring(p[2]))end
     row.command=p[2];row.args=arguments(p[4]);local fields={};for field in (commandFields[p[2]]or ''):gmatch('%S+')do fields[field]=true end;for field in pairs(row.args)do if not fields[field]then fail('Unknown '..p[2]..' argument '..field)end end;out[#out+1]=row
    elseif code==230 then row.command='wait';row.args={frames=num(p[1])};out[#out+1]=row
    elseif code==223 or code==224 or code==225 or code==250 then row.command=({[223]='screenTone',[224]='screenFlash',[225]='screenShake',[250]='sound'})[code];row.args=cp(p);out[#out+1]=row
    elseif code~=0 and code~=108 and code~=408 and code~=657 then fail('Unsupported native sequence command '..code)end
   end
  end
  if #stack>0 then fail('Unclosed sequence condition')end;return out
 end
 function M.prepare(index,plugins)
  if index.visuGameplay then fail('Visu gameplay already prepared')end
  local db=index.database;local slotTypes={};local byName={};for i,name in ipairs(db.System.records.equipTypes)do if i>1 then byName[name]=byName[name]or i-1;slotTypes[i-1]=byName[name]end end;db.System.records.visuEquipSlots=slotTypes;db.System.records.visuGameplay=true;local summary={sequenceCommonEventIds={},skills=0,actorTraitSets=0,passiveStates=0,randomEnemies=0};local keys={};local cache={}
  local function rows(name)return assert(db[name],name).records end
  local qol=decode(assert(plugins.VisuMZ_0_CoreEngine['QoL:struct']))
  local core={}
  for _,name in ipairs({'EscapeAlways','LevelUpFullHp','LevelUpFullMp','ImprovedAccuracySystem','AccuracyBoost'})do
   local value=qol[name..':eval'];if value~='true'and value~='false'then fail('Unsupported CoreEngine QoL expression '..name..': '..tostring(value))end;core[name]=value=='true'
  end
  db.System.records.visuCore=core
  local mechanics=decode(assert(plugins.VisuMZ_1_BattleCore['Mechanics:struct']))
  local bases,seen={},{};summary.baseTroopPages=0
  for _,value in ipairs(decode(mechanics['BaseTroopIDs:arraynum']))do
   local id=num(value);if id%1~=0 or id<1 or seen[id]then fail('Invalid or duplicated BaseTroop ID '..tostring(value))end;seen[id]=true
   local troop=rows('Troops')[id+1];if not troop or troop==J.null then fail('Missing BaseTroop ID '..id)end
   bases[#bases+1]={id=id,pages=J.decode(J.encode(troop.pages))}
  end
  -- Source BattleCore concatenates base pages AFTER each troop's own pages.
  -- Snapshot the bases first so several base troops cannot clone clones.
  for _,troop in ipairs(rows('Troops'))do if troop~=J.null then
   if troop.visuBaseTroopSources then fail('BaseTroop pages already normalized')end
   troop.visuBaseTroopSources=J.array()
   for _,base in ipairs(bases)do if base.id~=troop.id then for sourcePage,page in ipairs(base.pages)do
    troop.visuBaseTroopSources[#troop.visuBaseTroopSources+1]={pageIndex=#troop.pages,sourceTroopId=base.id,sourcePageIndex=sourcePage-1}
    troop.pages[#troop.pages+1]=J.decode(J.encode(page));summary.baseTroopPages=summary.baseTroopPages+1
   end end end
  end end
  local function lookup(name,key)
   local found;for _,r in ipairs(rows(name))do if r~=J.null and (r.id==tonumber(key)or r.name:lower()==trim(key):lower())then if found then fail('Ambiguous '..name..' reference '..key)end;found=r end end
   if not found then fail('Missing '..name..' reference '..key)end;return found
  end
  for _,r in ipairs(rows('CommonEvents'))do if r~=J.null then for key in r.name:gmatch('%[([^%]]+)%]')do if keys[key]then fail('Duplicate common event key '..key)end;keys[key]=r.id end end end
  local function sequence(id)
   if not cache[id]then local e=rows('CommonEvents')[id+1];if not e or e==J.null then fail('Missing sequence common event '..id)end;cache[id]=M.compileSequence(e,plugins);summary.sequenceCommonEventIds[#summary.sequenceCommonEventIds+1]=id end;return cache[id]
  end
  local es=assert(plugins.VisuMZ_1_ElementStatusCore,'ElementStatusCore parameters required');local groups={};local groupOrder={'Element','SubElement','Gender','Race','Nature','Alignment','Blessing','Curse','Zodiac','Variant'}
  for _,group in ipairs(groupOrder)do local raw=decode(es[group..':struct']);local def=decode(raw['Default:struct']);local entries={[def['Name:str']:lower()]=def}
   for _,encoded in ipairs(decode(raw['List:arraystruct']))do local v=decode(encoded);entries[v['Name:str']:lower()]=v end;groups[group]={entries=entries,default=def,raw=raw}
   if raw['RandomizeActor:eval']~='false'or raw['RandomizeEnemy:eval']~='false'then fail('Global randomized trait sets need explicit per-instance support')end
  end
  local function addTrait(r,code,id,value)r.traits[#r.traits+1]={code=code,dataId=id,value=value}end
  local function passive(r,id,visu)
   if visu.passiveIds[id]then return end;local state=lookup('States',tostring(id));if state.restriction~=0 then fail('Restricting passive state requires runtime lifecycle support: '..id)end
   visu.passiveIds[id]=true;for _,tr in ipairs(state.traits)do r.traits[#r.traits+1]=cp(tr)end;summary.passiveStates=summary.passiveStates+1
  end
  local function traitSet(r,group,name,visu)
   local settings=groups[group];if not settings then fail('Unknown trait set group '..group)end
   local row=name and settings.entries[trim(name):lower()]or settings.default;if not row then fail('Unknown '..group..' trait set '..tostring(name))end
   visu.traitSets[group]=row['Name:str'];visu.traitLabels=visu.traitLabels or {};visu.traitLabels[group]=row['FmtText:str'];visu.rewardExp=(visu.rewardExp or 1)*num(row['EXPRate:num']);visu.rewardGold=(visu.rewardGold or 1)*num(row['GoldRate:num']);visu.rewardDrop=(visu.rewardDrop or 1)*num(row['DropRate:num'])
   for _,entry in ipairs({{'ElementRate',11,'Element'},{'Params',21,'Param'},{'XParams',22,'XParam'},{'SParams',23,'SParam'}})do
    local parameters=decode(row[entry[1]..':struct']);local fieldNames={};for key in pairs(parameters)do fieldNames[#fieldNames+1]=key end;table.sort(fieldNames);for _,key in ipairs(fieldNames)do local value=parameters[key];local id=key:match('^'..entry[3]..'(%d+):num$');if not id then fail('Unknown trait parameter '..key)end;local n=num(value);if n~=(entry[2]==22 and 0 or 1)then addTrait(r,entry[2],tonumber(id),n)end end
   end
   for _,entry in ipairs({{'Wtypes',51},{'Atypes',52}})do for _,id in ipairs(decode(row[entry[1]..':arraynum']))do addTrait(r,entry[2],num(id),1)end end
   for _,id in ipairs(decode(row['PassiveStates:arraynum']))do passive(r,num(id),visu)end
  end
  for _,name in ipairs({'Actors','Classes','Weapons','Armors','Enemies','States','Skills','Items'})do for _,r in ipairs(rows(name))do if r~=J.null then
   local note=r.note or '';r.visuSourceNote=note;local v={};local isUnit=name=='Actors'or name=='Enemies'
   if name=='Actors'and #r.equips<#db.System.records.equipTypes-1 then r.visuSourceEquips=cp(r.equips);for i=#r.equips+1,#db.System.records.equipTypes-1 do r.equips[i]=0 end end
   if isUnit then
    v.traitSets={};v.passiveIds={};local explicit={}
    note=note:gsub('<Trait Sets>(.-)</Trait Sets>',function(body)for line in body:gmatch('[^\r\n]+')do local group,value=line:match('^%s*([%w]+):%s*(.-)%s*$');if not group then fail('Malformed Trait Sets line '..line)end;explicit[group]=value end;return''end)
    for _,group in ipairs(groupOrder)do note=note:gsub('<'..group..':%s*([^>]+)>',function(value)explicit[group]=value;return''end);traitSet(r,group,explicit[group],v)end
    note=note:gsub('<Passive State:%s*([^>]+)>',function(value)passive(r,lookup('States',value).id,v);return''end)
    if name=='Actors'then summary.actorTraitSets=summary.actorTraitSets+1 end
    v.passiveStateIds={};for id in pairs(v.passiveIds)do v.passiveStateIds[#v.passiveStateIds+1]=id end;table.sort(v.passiveStateIds);v.passiveIds=nil
    -- Dynamic enemy traits are expanded into candidate data; selection belongs to the battle RNG.
    v.randomTraits={}
    for _,group in ipairs(groupOrder)do note=note:gsub('<Random '..group..'>(.-)</Random '..group..'>',function(body)
     local candidates={};for line in body:gmatch('[^\r\n]+')do local value,weight=line:match('^%s*(.-):%s*([%d%.]+)%s*$');if not value then fail('Malformed randomized trait '..line)end
      local candidate={traits={},visu={traitSets={},passiveIds={}}};traitSet(candidate,group,value,candidate.visu);candidate.weight=num(weight);candidate.name=trim(value);candidate.visu.passiveIds=nil;candidates[#candidates+1]=candidate
     end;v.randomTraits[#v.randomTraits+1]={group=group,candidates=candidates};summary.randomEnemies=summary.randomEnemies+1;return''end)end
    note=note:gsub('<Element Absorb:%s*([^>]+)>',function(value)
     v.absorbElements=v.absorbElements or {};for part in value:gmatch('[^,]+')do local found;for i,label in ipairs(db.System.records.elements)do if label:gsub('\\[Ii]%[%d+%]',''):lower()==trim(part):lower()or i-1==tonumber(part)then found=i-1;break end end;if not found then fail('Unknown absorb element '..part)end;v.absorbElements[#v.absorbElements+1]=found end;return''end)
    note=note:gsub('<Swap Enemies>(.-)</Swap Enemies>',function(body)v.swapEnemies={};for line in body:gmatch('[^\r\n]+')do local enemy,weight=line:match('^%s*(.-):%s*([%d%.]+)%s*$');if not enemy then fail('Malformed swap enemy')end;v.swapEnemies[#v.swapEnemies+1]={id=lookup('Enemies',enemy).id,weight=num(weight)}end;return''end)
   end
   if name=='Skills'or name=='Items'then
    v.accuracy={improved=core.ImprovedAccuracySystem,boost=core.AccuracyBoost}
    local events={};local custom=note:find('<Custom Action Sequence>',1,true)~=nil
    note=note:gsub('<Common Event Key:%s*([^>]+)>',function(key)local id=keys[trim(key)];if not id then fail('Missing common event key '..key)end;events[#events+1]=id;custom=true;return''end)
    if custom then
     local fromEffects={};for _,effect in ipairs(r.effects)do if effect.code==44 then fromEffects[#fromEffects+1]=effect.dataId end end;for _,id in ipairs(events)do fromEffects[#fromEffects+1]=id end
     v.sequence={};v.commonEventIds=fromEffects;for _,id in ipairs(fromEffects)do for _,op in ipairs(sequence(id))do v.sequence[#v.sequence+1]=cp(op)end end
     local remaining={};for _,effect in ipairs(r.effects)do if effect.code~=44 then remaining[#remaining+1]=effect end end;r.effects=J.array(remaining);summary.skills=summary.skills+1
    end
    note=note:gsub('<Custom Action Sequence>','')
    v.costs={};note=note:gsub('<(HP) Cost:%s*(%d+)%%>',function(_,n)v.costs.hpRate=num(n)/100;return''end)
    note=note:gsub('<Gold Cost:%s*(%d+)>',function(n)v.costs.gold=num(n);return''end)
    note=note:gsub('<Potion Cost:%s*(%d+)>',function(n)v.costs.item={id=7,amount=num(n)};return''end)
   end
   -- Explicit UI records remain available to layout conversion.
   for _,tag in ipairs({'Command Text','Battle Portrait','Menu Portrait','Male Battler Hue','Color'})do note=note:gsub('<'..tag..':%s*([^>]+)>',function(value)v[tag]=value;return''end)end
   for _,tag in ipairs({'Battle Commands','Biography','Sideview Battlers'})do note=note:gsub('<'..tag..'>(.-)</'..tag..'>',function(body)v[tag]=body;return''end)end
   if name=='Classes'and v['Battle Commands']then
    v.battleCommands={};local standard={Attack='attack',Skills='skills',Guard='guard',Item='item',Party='party',Escape='escape'}
    for line in v['Battle Commands']:gmatch('[^\r\n]+')do line=trim(line);if line~=''then
     local command=standard[line]
     if command then v.battleCommands[#v.battleCommands+1]={command=command,label=line}
     else
      local skillName=line:match('^Skill:%s*(.-)%s*$');if not skillName or skillName==''then fail('Unknown battle command in Classes['..r.id..']: '..line)end
      local found;for _,skill in ipairs(rows('Skills'))do if skill~=J.null and skill.name==skillName then if found then fail('Ambiguous direct battle skill '..skillName)end;found=skill end end
      if not found then fail('Missing exact direct battle skill '..skillName)end
      v.battleCommands[#v.battleCommands+1]={command='skill_direct',id=found.id,label=found.name}
     end
    end end
   end
   if name=='States'then note=note:gsub('<(Negative) State>',function(x)v.stateCategory=x;return''end):gsub('<(Positive) State>',function(x)v.stateCategory=x;return''end)end
   if note:find('<[^>]*>')then fail('Unclaimed gameplay note in '..name..'['..r.id..']: '..note)end
   r.note=note;r.visu=v
  end end end
  table.sort(summary.sequenceCommonEventIds);index.visuGameplay=summary;return summary
 end
 return M
end
