-- Actor state authority. Party alone owns membership, inventory and equipment.
return function(deps)
 local Rules,Traits,Rng,Battler=deps['runtime.rpg.actor_rules'],deps['runtime.rpg.traits'],deps['runtime.core.rng'],deps['runtime.rpg.battler_state']
 local M={};local SAFE=9007199254740991
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_ACTOR_STATE_SHAPE','Expected plain actor-state table')end end
 local function number(v,lo,hi)
  if type(v)~='number' or v~=v or v%1~=0 or v<(lo or -SAFE) or v>(hi or SAFE)then fail('E_ACTOR_STATE_NUMBER','Invalid finite safe integer')end;return v*1.0
 end
 local function dense(v,n)
  plain(v);local count,max=0,0
  for k in next,v do if type(k)~='number' or k%1~=0 or k<1 or k>SAFE then fail('E_ACTOR_STATE_SHAPE','Expected dense array')end;count=count+1;max=math.max(max,k)end
  if count~=max or n and count~=n then fail('E_ACTOR_STATE_SHAPE','Invalid array length or gap')end;return count
 end
 local function copy(v,seen,depth)
  if type(v)~='table'then return v end;plain(v);seen=seen or {};depth=depth or 0
  if seen[v] or depth>64 then fail('E_ACTOR_STATE_SHAPE','Cyclic or deeply nested data')end;seen[v]=true
  local out={};for k,x in next,v do out[k]=copy(x,seen,depth+1)end;seen[v]=nil;return out
 end
 local function fields(v,allowed)plain(v);for key in next,v do if not allowed[key]then fail('E_ACTOR_STATE_SHAPE','Unknown actor-state field')end end end
 local function z()return{0,0,0,0,0,0,0,0}end
 local function has(list,id)for _,v in ipairs(list)do if v==id then return true end end;return false end
 local function stateError(why)fail('E_ACTOR_STATE_STATE',why)end
 local function rawOptions(options)
  plain(options);local party=options.party
  if type(party)~='table' or type(party.snapshot)~='function' or type(party.transaction)~='function'then fail('E_ACTOR_STATE_SHAPE','Party instance with transaction is required')end
  fields(options,{party=true,profile=true,state=true});local profile=options.profile
  return party,profile
 end
 function M.prepare(definitions,profile)
  local catalog=Rules.prepare(definitions,profile);local rules=Rules.fromCompiledCatalog(catalog);local defs={}
  for _,kind in ipairs({'actors','classes','weapons','armors','states'})do defs[kind]={};for _,r in ipairs(definitions[kind])do defs[kind][r.id]=copy(r)end end
  plain(definitions.system);dense(definitions.system.equipTypes);local slotCount=#definitions.system.equipTypes-1
  if slotCount<1 then fail('E_ACTOR_STATE_SHAPE','System equipment slots required')end
  for _,kind in ipairs({'weapons','armors'})do for _,r in pairs(defs[kind])do number(r.etypeId,1,slotCount);number(r[kind=='weapons' and 'wtypeId' or 'atypeId'],0)end end
  for _,s in pairs(defs.states)do
   s.priority=number(s.priority,0);s.restriction=number(s.restriction,0,4);s.minTurns=number(s.minTurns,0);s.maxTurns=number(s.maxTurns,0);s.stepsToRemove=number(s.stepsToRemove,0)
   if 1.0+math.max(s.maxTurns-s.minTurns,0.0)>2147483647 then fail('E_ACTOR_STATE_NUMBER','State duration variance exceeds RNG range')end
   if type(s.removeByRestriction)~='boolean'then fail('E_ACTOR_STATE_SHAPE','State removal flag required')end
  end
  if not defs.states[1]then fail('E_ACTOR_STATE_REFERENCE','Death state 1 required')end
  local battler=Battler.new({profile=profile,states=definitions.states})
  -- Preserve the raw constructor's full-record copy checks above before dropping
  -- metadata. All consumers bind these same narrow records after preparation.
  for _,kind in ipairs({'weapons','armors'})do for id,r in pairs(defs[kind])do
   local prepared=catalog[kind..'ById'][id];prepared.etypeId=r.etypeId
   prepared[kind=='weapons' and 'wtypeId' or 'atypeId']=r[kind=='weapons' and 'wtypeId' or 'atypeId']
   if kind=='weapons'then
    local value=r.animationId
    if value==nil and r.sourceMeta then value=(r.sourceMeta.unhandledFields or {}).animationId end
    prepared.animationId=number(value or 0,0)
   end
  end end
  for id,r in pairs(defs.states)do local prepared=catalog.statesById[id];prepared.visu=r.visu~=nil or nil
   for _,name in ipairs({'priority','restriction','minTurns','maxTurns','stepsToRemove','removeByRestriction'})do prepared[name]=r[name]end
  end
  for id,r in pairs(defs.classes)do if r.visu and r.visu.battleCommands then catalog.classesById[id].visuBattleCommands=copy(r.visu.battleCommands)end end
  catalog.skillTypeNames=copy(definitions.system.skillTypes or {})
  catalog.actorIds={};catalog.initialEquipIds={}
  for _,a in ipairs(definitions.actors)do
   catalog.actorIds[#catalog.actorIds+1]=a.id
   if a.equips~=nil then
    dense(a.equips,slotCount);local ids={};for i,id in ipairs(a.equips)do ids[i]=number(id,0)end
    catalog.initialEquipIds[a.id]=ids
   end
  end
  catalog.slotCount=slotCount;local meta=definitions.system.sourceMeta and definitions.system.sourceMeta.unhandledFields or {};if meta.visuEquipSlots then catalog.visuEquipSlots=copy(meta.visuEquipSlots)end;if meta.visuCore then catalog.visuCore=copy(meta.visuCore)end
  return catalog,rules,battler
 end
 local function instance(catalog,rules,battler,party,options)
  local profile=catalog.profile;local mv=profile=='mv-1.5.1';local slotCount=catalog.slotCount
  local defs={actors=catalog.actorsById,classes=catalog.classesById,weapons=catalog.weaponsById,
   armors=catalog.armorsById,states=catalog.statesById,skills=catalog.skillsById}
  local function ref(kind,id)number(id,1);local r=defs[kind][id];if not r then fail('E_ACTOR_STATE_REFERENCE','Missing '..kind..' source ID')end;return r end
  local function context(s,p)
   local equipment=p.snapshot().equipment[s.actorId] or {}
   return{equipment=equipment,permanent=s.permanent,buffs=s.buffs,stateIds=s.stateIds,hp=s.hp,mp=s.mp}
  end
  local function traits(s,p)
   local sources={};for _,id in ipairs(s.stateIds)do sources[#sources+1]={traits=ref('states',id).traits}end
   sources[#sources+1]={traits=ref('actors',s.actorId).traits};sources[#sources+1]={traits=ref('classes',s.classId).traits}
   for _,e in ipairs(context(s,p).equipment)do if e~=false then sources[#sources+1]={traits=ref(e.kind=='weapon' and 'weapons' or 'armors',e.id).traits}end end
   return Traits.new(sources)
  end
  local function ordered(ids)
   local out=copy(ids);table.sort(out,function(a,b)local x,y=ref('states',a),ref('states',b);return x.priority~=y.priority and x.priority>y.priority or x.priority==y.priority and a<b end);return out
  end
  local function equipmentLegal(s,p,release,forcing)
   for _=1,slotCount+1 do
    local slots={};for i=1,slotCount do slots[i]=catalog.visuEquipSlots and catalog.visuEquipSlots[i]or i end;if slotCount>=2 and traits(s,p).isDualWield()then slots[2]=1 end
    local equipment=context(s,p).equipment;local changed=false
    for i,e in ipairs(equipment)do if e~=false then
     local r=ref(e.kind=='weapon' and 'weapons' or 'armors',e.id);local tr=traits(s,p)
     local allowed=e.kind=='weapon' and tr.isEquipWtypeOk(r.wtypeId) or e.kind=='armor' and tr.isEquipAtypeOk(r.atypeId)
     if not allowed or tr.isEquipTypeSealed(r.etypeId) or r.etypeId~=slots[i]then
      if not release then stateError('Equipment snapshot is not native refresh-consistent')end
      if forcing then p.setEquipment(s.actorId,i,false)else p.releaseEquipment(s.actorId,i)end;changed=true
     end
    end end
    if not changed then return end
   end
   stateError('Equipment release did not converge')
  end
  local function counters(s,name,field)
   dense(s[name]);local seen={}
   for _,e in ipairs(s[name])do fields(e,{stateId=true,[field]=true});ref('states',e.stateId);number(e[field],0);if seen[e.stateId]then stateError('Duplicate state counter reference')end;seen[e.stateId]=true end
   for _,id in ipairs(s.stateIds)do if not seen[id]then stateError('Missing active state counter')end end
  end
  local function validate(s,p)
   fields(s,{actorId=true,classId=true,level=true,expByClass=true,learnedSkills=true,hp=true,mp=true,tp=true,permanent=true,buffs=true,buffTurns=true,stateIds=true,stateTurns=true,stateSteps=true,removedStates=mv or nil,visuImmortal=true})
   if mv then
    dense(s.removedStates);local seen={}
    for _,id in ipairs(s.removedStates)do ref('states',id);if seen[id]then stateError('Duplicate persistent removed state')end;seen[id]=true end
   end
   dense(s.expByClass);for _,entry in ipairs(s.expByClass)do fields(entry,{classId=true,total=true})end
   ref('actors',s.actorId);rules.skills(s,context(s,p));dense(s.permanent,8);dense(s.buffs,8);dense(s.buffTurns,8)
   number(s.hp,0);number(s.mp);number(s.tp,nil,100)
   for i=1,8 do number(s.permanent[i]);number(s.buffs[i],-2,2);number(s.buffTurns[i],0)end
   dense(s.stateIds);local sort=ordered(s.stateIds);for i,id in ipairs(s.stateIds)do if id~=sort[i]then stateError('State order is not native priority/id order')end end
   counters(s,'stateTurns','turns');counters(s,'stateSteps','steps')
   -- Native gainItem/recoverAll can leave pre-refresh resources, states and slots.
   -- Restore validates data, never silently refreshes or consumes random draws.
   rules.stats(s,context(s,p))
  end
  local data={};local sequence=catalog.actorIds
  if options.state~=nil then
   local snapshot=options.state;fields(snapshot,{schemaVersion=true,profile=true,actors=true})
   if snapshot.schemaVersion~=1 or snapshot.profile~=profile then fail('E_ACTOR_STATE_SHAPE','Snapshot profile/schema mismatch')end
   dense(snapshot.actors,#sequence)
   for _,s in ipairs(snapshot.actors)do validate(s,party);if data[s.actorId]then stateError('Duplicate actor snapshot')end;data[s.actorId]=copy(s)end
   for _,id in ipairs(sequence)do if not data[id]then stateError('Missing actor snapshot')end end
  else
   for _,id in ipairs(sequence)do
    local s
    if catalog.catalogVersion==2 then
     local seed=catalog.growthSeedsById[id]
     fields(seed,{actorId=true,classId=true,level=true,expByClass=true,learnedSkills=true})
     local actor=ref('actors',id)
     if seed.actorId~=id or seed.classId~=actor.classId or seed.level~=actor.initialLevel then stateError('Invalid compiled growth seed identity')end
     s=copy(seed)
    else s=rules.initial(id)end
    s.hp,s.mp,s.tp=0,0,0;s.permanent=z();s.buffs=z();s.buffTurns=z();s.stateIds={};s.stateTurns={};s.stateSteps={};if mv then s.removedStates={}end
    equipmentLegal(s,party,false);local stats=rules.stats(s,context(s,party));s.hp,s.mp=stats.params[1],stats.params[2];data[id]=s
   end
  end
  local busy=false;local A={}
  local function view(s,p)
   local slots={};for i=1,slotCount do slots[i]=catalog.visuEquipSlots and catalog.visuEquipSlots[i]or i end;if slotCount>=2 and traits(s,p).isDualWield()then slots[2]=1 end
   return{state=copy(s),stats=rules.stats(s,context(s,p)),skills=rules.skills(s,context(s,p)),equipment=copy(context(s,p).equipment),equipmentSlots=slots,preserveTp=traits(s,p).isPreserveTp()}
  end
  function A.snapshot()local result={schemaVersion=1,profile=profile,actors={}};for _,id in ipairs(sequence)do result.actors[#result.actors+1]=copy(data[id])end;return result end
  function A.getActor(id)ref('actors',id);return view(data[id],party)end
  function A.hasActor(id)return type(id)=='number' and id==id and id%1==0 and id>=1 and id<=SAFE and catalog.actorsById[id]~=nil end
  function A.progression(id)ref('actors',id);return rules.progression(data[id])end
  function A.meetsCondition(id,test,value,name)
   if not A.hasActor(id)then return false end
   local s=data[id]
   if test==1 then return name==value
   elseif test==2 then return s.classId==value
   elseif test==3 then return has(s.learnedSkills,value)
   elseif test==4 or test==5 then
    local kind=test==4 and 'weapon' or 'armor'
    for _,item in ipairs(context(s,party).equipment)do if item~=false and item.kind==kind and item.id==value then return true end end
    return false
   elseif test==6 then return has(s.stateIds,value)end
   fail('E_ACTOR_STATE_UNSUPPORTED','Unknown actor condition')
  end
  local function applyShared(s,p,operation,random)
   local adapter={kind='actor',isAppeared=function()return true end,
    traits=function(candidate)return traits(candidate,p)end,
    beforeRefresh=function(candidate)equipmentLegal(candidate,p,true)end,
    stats=function(candidate)
     local c=context(candidate,p)
     -- Only params are consumed before the source setter clamps pending resources.
     c.hp,c.mp=0,0
     return{params=rules.stats(candidate,c).params}
    end}
   local result=battler.apply(s,operation,adapter,random.state,mv and {removedStates=s.removedStates} or nil)
   if mv then result.state.removedStates=copy(result.result.removedStates)end
   random.state=result.rngState
   return result.state
  end
  local function transaction(rngState,callback)
   if busy then fail('E_ACTOR_STATE_REENTRY','Actors mutation is not reentrant')end
   local rng={state=Rng.restore(rngState).snapshot()};busy=true
   local ok,committed,prepared=pcall(party.transaction,function(p)
    local candidates=copy(data);local result=callback(candidates,p,rng)
    result.rngState=copy(rng.state);return result.ok~=false,{data=candidates,result=result}
   end)
   busy=false;if not ok then error(committed,0)end
   if not committed then return prepared.result end
   data=prepared.data;return prepared.result
  end
  local function levelUpRecovery(s,p,previousLevel,changingClass)
   local core=catalog.visuCore
   if not core or changingClass or s.level<=previousLevel then return end
   local stats=rules.stats(s,context(s,p));if core.LevelUpFullHp then s.hp=stats.params[1]end;if core.LevelUpFullMp then s.mp=stats.params[2]end
  end
  local function actorCommand(command,candidates,p,rng)
   plain(command);local op=command.op
   local schemas={setup={},recoverAll={},changeExp={total=true},changeLevel={level=true},changeClass={classId=true,keepExp=true},learnSkill={skillId=true},forgetSkill={skillId=true},gainHp={value=true,allowDeath=true},gainMp={value=true},gainTp={value=true},addState={stateId=true},removeState={stateId=true},addParam={paramId=true,value=true}}
   local schema=schemas[op];if not schema then fail('E_ACTOR_STATE_UNSUPPORTED','Actor command is not implemented')end
   local allowed={op=true,actorId=true};for k in pairs(schema)do allowed[k]=true end;fields(command,allowed)
   ref('actors',command.actorId)
    local s=candidates[command.actorId];local delta
    if op=='setup'then
     local ids=catalog.initialEquipIds and catalog.initialEquipIds[command.actorId]
     if not ids then fail('E_ACTOR_STATE_SHAPE','Actor setup requires compiled initial equipment IDs')end
     local seed=catalog.catalogVersion==2 and copy(catalog.growthSeedsById[command.actorId]) or rules.initial(command.actorId)
     for _,key in ipairs({'classId','level','expByClass','learnedSkills'})do s[key]=seed[key]end
     -- Native chooses slot kinds before replacing equipment, using current states
     -- and old equipment together with the reset class. Initial items are granted
     -- directly; discarded items never enter party inventory.
     local dual=slotCount>=2 and traits(s,p).isDualWield();local slots={}
     for i=1,slotCount do
      local kind=(i==1 or i==2 and dual)and 'weapon' or 'armor';local id=ids[i]
      slots[i]=id>0 and defs[kind=='weapon' and 'weapons' or 'armors'][id] and {kind=kind,id=id} or false
     end
     p.replaceEquipment(s.actorId,slots);equipmentLegal(s,p,true,true)
     s=applyShared(s,p,{op='refresh'},rng);s.permanent=z();s=applyShared(s,p,{op='recoverAll'},rng)
    elseif op=='recoverAll'then
     s=applyShared(s,p,{op='recoverAll'},rng)
    elseif op=='learnSkill' or op=='forgetSkill'then
     ref('skills',command.skillId)
     if op=='learnSkill'then if not has(s.learnedSkills,command.skillId)then s.learnedSkills[#s.learnedSkills+1]=command.skillId;table.sort(s.learnedSkills)end
     else for i=#s.learnedSkills,1,-1 do if s.learnedSkills[i]==command.skillId then table.remove(s.learnedSkills,i)end end end
    elseif op=='gainHp' or op=='gainMp' or op=='gainTp' or op=='addState' or op=='removeState' or op=='addParam'then
     local operation={op=op,value=command.value,stateId=command.stateId,paramId=command.paramId}
     if op=='gainHp'then
      if type(command.allowDeath)~='boolean'then fail('E_ACTOR_STATE_SHAPE','HP change needs allowDeath')end
      number(command.value)
      if s.hp==0 then operation=nil elseif not command.allowDeath and s.hp+command.value<=0 then operation.value=1-s.hp end
     end
     if operation then s=applyShared(s,p,operation,rng)end
     if mv and (op=='addState' or op=='removeState')then s.removedStates={}end
    else
     local previousLevel=s.level;local change=op=='changeExp' and rules.changeExp(s,command.total) or op=='changeClass' and rules.changeClass(s,command.classId,command.keepExp) or rules.changeLevel(s,command.level)
     for _,key in ipairs({'classId','level','expByClass','learnedSkills'})do s[key]=change.state[key]end;delta=change.delta;levelUpRecovery(s,p,previousLevel,op=='changeClass');s=applyShared(s,p,{op='refresh'},rng)
    end
    candidates[command.actorId]=s
    return{ok=true,delta=delta,actor=view(s,p)}
  end
  function A.command(command,rngState)
   return transaction(rngState,function(candidates,p,rng)return actorCommand(command,candidates,p,rng)end)
  end
  function A.learnSkills(actorIds,skillIds)
   if busy then fail('E_ACTOR_STATE_REENTRY','Actors mutation is not reentrant')end
   -- Native learnSkill only changes the learned-ID set. Bulk event adapters
   -- must not pay for a party transaction and a complete derived actor view
   -- for every actor/skill pair. Validate everything before committing any set.
   dense(actorIds);dense(skillIds)
   local ids,selected={},{}
   for _,id in ipairs(actorIds)do ref('actors',id);if not selected[id]then selected[id]=true;ids[#ids+1]=id end end
   for _,id in ipairs(skillIds)do ref('skills',id)end
   local pending,changed={},0
   for _,id in ipairs(ids)do
    local skills,known={},{}
    for _,skill in ipairs(data[id].learnedSkills)do skills[#skills+1]=skill;known[skill]=true end
    local count=#skills
    for _,skill in ipairs(skillIds)do if not known[skill]then known[skill]=true;skills[#skills+1]=skill end end
    if #skills>count then table.sort(skills);pending[id]=skills;changed=changed+1 end
   end
   for id,skills in pairs(pending)do data[id].learnedSkills=skills end
   return{ok=true,changedActors=changed}
  end
  function A.gainItem(kind,id,amount,includeEquip,rngState)
   return transaction(rngState,function(candidates,p,rng)
    local before=p.snapshot();local quantity=p.gainItem(kind,id,amount,includeEquip);local after=p.snapshot();local deltas={}
    for _,actorId in ipairs(sequence)do
     local changed=false;local old,new=before.equipment[actorId] or {},after.equipment[actorId] or {}
     for slot,item in ipairs(old)do local x=new[slot];if item~=false and (x==false or not x or x.kind~=item.kind or x.id~=item.id)then changed=true end end
     if changed then deltas[#deltas+1]={actorId=actorId,actor=view(candidates[actorId],p)}end
    end
    return{ok=true,quantity=quantity,actorDeltas=deltas}
   end)
  end
  local function gainBattleExp(candidates,p,rng,actorId,baseExp,options)
   ref('actors',actorId);number(baseExp,0);fields(options,{isBattleMember=true,optExtraExp=true})
   if type(options.isBattleMember)~='boolean' or type(options.optExtraExp)~='boolean'then fail('E_ACTOR_STATE_SHAPE','Battle EXP flags required')end
    local s=candidates[actorId]
    local rate=rules.stats(s,context(s,p)).sparams[10]*(options.isBattleMember and 1 or options.optExtraExp and 1 or 0)
    local value=baseExp*rate
    if value~=value or value < -SAFE or value > SAFE then fail('E_ACTOR_STATE_NUMBER','Battle EXP exceeds supported range')end
    local gained=math.floor(value);if value-gained>=.5 then gained=gained+1 end
    local total=number(rules.progression(s).currentExp+gained)
    local previousLevel=s.level;local change=rules.changeExp(s,total)
    for _,key in ipairs({'classId','level','expByClass','learnedSkills'})do s[key]=change.state[key]end
    levelUpRecovery(s,p,previousLevel,false);s=applyShared(s,p,{op='refresh'},rng);candidates[actorId]=s
    return{ok=true,gainedExp=gained,delta=change.delta,actor=view(s,p)}
  end
  function A.gainBattleExp(actorId,baseExp,options,rngState)
   return transaction(rngState,function(candidates,p,rng)return gainBattleExp(candidates,p,rng,actorId,baseExp,options)end)
  end
  -- Action contexts expose isolated queries and revocable candidate operations.
  local function actionOutput(value,seen,depth,budget)
   local kind=type(value)
   if kind~='table'then
    if kind=='number'then if value~=value or value==math.huge or value==-math.huge then fail('E_ACTOR_STATE_SHAPE','Nonfinite action output')end
    elseif kind~='nil'and kind~='string'and kind~='boolean'then fail('E_ACTOR_STATE_SHAPE','Executable action output')end
    return value
   end
   plain(value);seen=seen or {};depth=depth or 0;budget=budget or {left=100000}
   if seen[value]or depth>64 then fail('E_ACTOR_STATE_SHAPE','Cyclic or deeply nested action output')end
   seen[value]=true;local out={};for key,v in next,value do
    if type(key)=='number'then number(key)elseif type(key)~='string'then fail('E_ACTOR_STATE_SHAPE','Invalid action output key')end
    budget.left=budget.left-1;if budget.left<0 then fail('E_ACTOR_STATE_SHAPE','Action output budget exceeded')end
    out[key]=actionOutput(v,seen,depth+1,budget)
   end;seen[value]=nil;return out
  end
  local function actionQuery(s,p,check)
   check();local v=view(s,p);local tr=traits(s,p);local wrapped={}
   for name,fn in pairs(tr)do wrapped[name]=function(...)check();return fn(...)end end
   local restriction=0;for _,id in ipairs(s.stateIds)do restriction=math.max(restriction,ref('states',id).restriction)end
   local weaponTypes,attackAnimations={},{};for _,e in ipairs(v.equipment)do if e~=false and e.kind=='weapon'then
    local weapon=ref('weapons',e.id);weaponTypes[#weaponTypes+1]=weapon.wtypeId
    if #attackAnimations<2 then attackAnimations[#attackAnimations+1]=weapon.animationId or 0 end
   end end
   if #weaponTypes==0 then attackAnimations[1]=1 end
   local f={hp=s.hp,mp=s.mp,tp=s.tp,level=s.level};local names={'mhp','mmp','atk','def','mat','mdf','agi','luk'}
   for i,name in ipairs(names)do f[name]=v.stats.params[i]end
   names={'hit','eva','cri','cev','mev','mrf','cnt','hrg','mrg','trg'};for i,name in ipairs(names)do f[name]=v.stats.xparams[i]end
   names={'tgr','grd','rec','pha','mcr','tcr','pdr','mdr','fdr','exr'};for i,name in ipairs(names)do f[name]=v.stats.sparams[i]end
   return{kind='actor',classId=s.classId,visuBattleCommands=copy(ref('classes',s.classId).visuBattleCommands),skillTypeNames=catalog.skillTypeNames and copy(catalog.skillTypeNames),hidden=false,hp=s.hp,mp=s.mp,tp=s.tp,stateIds=copy(s.stateIds),stateTurns=copy(s.stateTurns),stateSteps=copy(s.stateSteps),buffs=copy(s.buffs),buffTurns=copy(s.buffTurns),learnedSkills=copy(s.learnedSkills),
    skills=copy(v.skills),params=copy(v.stats.params),xparams=copy(v.stats.xparams),sparams=copy(v.stats.sparams),traits=wrapped,
    formula=f,restriction=restriction,weaponTypes=weaponTypes,attackAnimations=attackAnimations,guard=tr.isGuard(restriction<4)}
  end
  local function actionLookup(all,r)
   fields(r,{kind=true,id=true});if r.kind~='actor'then fail('E_ACTOR_STATE_REFERENCE','Actor action reference required')end
   ref('actors',r.id);return all[r.id]
  end
  function A.actionContext()
   return{query=function(r)return actionQuery(actionLookup(data,r),party,function()end)end,
    gold=function()return party.gold()end,count=function(kind,id)return party.count(kind,id)end,members=function()return party.members()end}
  end
  local eventEquip
  function A.actionTransaction(rngState,callback)
   if type(callback)~='function'then fail('E_ACTOR_STATE_SHAPE','Action callback required')end
   return transaction(rngState,function(all,p,random)
    local active=true;local function check()if not active then fail('E_ACTOR_STATE_CLOSED','Action candidate is closed')end end
    local function advance(value)
     local nextState=Rng.restore(value).snapshot();local previous=random.state
     if nextState.algorithm~=previous.algorithm or nextState.draws<previous.draws then fail('E_ACTOR_STATE_RNG','Action RNG moved backwards or changed algorithm')end
     if previous.algorithm=='r2u-fixed-v1'then
      if #nextState.values~=#previous.values then fail('E_ACTOR_STATE_RNG','Action fixed stream changed')end
      for i,v in ipairs(previous.values)do if nextState.values[i]~=v then fail('E_ACTOR_STATE_RNG','Action fixed stream changed')end end
     else
      local distance=nextState.draws-previous.draws;if distance>100000 then fail('E_ACTOR_STATE_RNG','Action RNG advance exceeds supported bound')end
      local expected=Rng.restore(previous);for _=1,distance do expected.nextUnit('actor:action:continuity')end
      if expected.snapshot().state~=nextState.state then fail('E_ACTOR_STATE_RNG','Action RNG stream changed')end
     end
     random.state=nextState;return copy(nextState)
    end
    local ctx={}
    function ctx.query(r)check();return actionQuery(actionLookup(all,r),p,check)end
    function ctx.members()check();return p.members()end
    function ctx.count(kind,id)check();return p.count(kind,id)end
    function ctx.consumeItem(id)check();return p.consumeItem(id)end
    function ctx.gold()check();return p.gold()end
    function ctx.setVisuImmortal(r,value)check();if type(value)~='boolean'then fail('E_ACTOR_STATE_SHAPE','Immortality must be boolean')end;actionLookup(all,r).visuImmortal=value end
    function ctx.gainGold(amount)check();return p.gainGold(amount)end
    function ctx.gainItem(kind,id,amount,includeEquip)check();return p.gainItem(kind,id,amount,includeEquip==nil and false or includeEquip)end
    function ctx.partyMember(id,remove)
     check();ref('actors',id);if type(remove)~='boolean'then fail('E_ACTOR_STATE_SHAPE','Party removal flag required')end
     if remove then return p.removeActor(id)else return p.addActor(id)end
    end
    function ctx.actorCommand(command,nextRng)
     check();advance(nextRng);local out=actorCommand(command,all,p,random);out.rngState=copy(random.state);return out
    end
    function ctx.progression(r)check();return rules.progression(actionLookup(all,r))end
    function ctx.gainBattleExp(r,baseExp,options,nextRng)
     check();actionLookup(all,r);advance(nextRng)
     local result=gainBattleExp(all,p,random,r.id,baseExp,options);result.rngState=copy(random.state);return result
    end
    function ctx.setTurns(r,turns)
     check();local s=actionLookup(all,r);fields(turns,{stateTurns=true,buffTurns=true})
     local candidate={stateIds=s.stateIds,stateTurns=copy(turns.stateTurns)}
     counters(candidate,'stateTurns','turns');dense(turns.buffTurns,8)
     for _,value in ipairs(turns.buffTurns)do number(value,0)end
     s.stateTurns=candidate.stateTurns;s.buffTurns=copy(turns.buffTurns)
    end
    function ctx.appear(r)
     check();actionLookup(all,r)
     -- Battle owns Actor hidden/escaped state and consumes this after commit.
     return{hooks={{op='appear'}}}
    end
    function ctx.eventEquip(actorId,slot,itemId,nextRng)
     check();ref('actors',actorId);advance(nextRng)
     all[actorId]=eventEquip(all[actorId],p,slot,itemId,random)
     return{rngState=copy(random.state)}
    end
    function ctx.setStateSteps(r,steps)
     check();local s=actionLookup(all,r);fields(steps,{stateSteps=true})
     local candidate={stateIds=s.stateIds,stateSteps=copy(steps.stateSteps)};counters(candidate,'stateSteps','steps')
     s.stateSteps=candidate.stateSteps
    end
    function ctx.paySkillCost(r,mp,tp,nextRng,forcing)
     check();local s=actionLookup(all,r);number(mp,0);number(tp,0)
     if forcing~=nil and type(forcing)~='boolean'then fail('E_ACTOR_STATE_SHAPE','Forcing must be boolean')end
     if not forcing and (s.mp<mp or s.tp<tp)then fail('E_ACTOR_STATE_COST','Insufficient skill resources')end
     -- Native useItem subtracts directly; forced actions can leave debt until
     -- a later native setter/refresh. Validate before changing the candidate.
     local nextMp,nextTp=number(s.mp*1.0-mp),number(s.tp*1.0-tp,nil,100)
     advance(nextRng);s.mp,s.tp=nextMp,nextTp;return copy(random.state)
    end
    function ctx.apply(r,operation,nextRng)
     check();local s=actionLookup(all,r);local adapter={kind='actor',isAppeared=function()return true end,
      traits=function(candidate)return traits(candidate,p)end,beforeRefresh=function(candidate)equipmentLegal(candidate,p,true)end,
      stats=function(candidate)local c=context(candidate,p);c.hp,c.mp=0,0;return{params=rules.stats(candidate,c).params}end}
     local out=battler.apply(s,operation,adapter,advance(nextRng));all[r.id]=out.state;advance(out.rngState)
     return{result=copy(out.result),hooks=copy(out.hooks),rngState=copy(out.rngState)}
    end
    function ctx.learnSkill(r,id)
     check();local s=actionLookup(all,r);number(id,1);if not catalog.skillsById[id]then fail('E_ACTOR_STATE_REFERENCE','Missing learned skill')end
     if not has(s.learnedSkills,id)then s.learnedSkills[#s.learnedSkills+1]=id;table.sort(s.learnedSkills)end
    end
    function ctx.escape(r,inBattle,nextRng)
     check();local s=actionLookup(all,r);if inBattle~=false then fail('E_ACTOR_STATE_UNSUPPORTED','Battle escape is not implemented')end
     local rng=advance(nextRng);s.stateIds={};s.stateTurns={};s.stateSteps={}
     return{hooks={{op='clearActions'},{op='playEscape'}},rngState=rng}
    end
    local ok,result=pcall(callback,ctx);active=false;if not ok then error(result,0)end
    plain(result);if type(result.ok)~='boolean'then fail('E_ACTOR_STATE_SHAPE','Action callback must return ok boolean')end
    if result.rngState~=nil then advance(result.rngState)end
    for _,id in ipairs(sequence)do validate(all[id],p)end
    return actionOutput(result)
   end)
  end
  local function key(item)
   if item==false then return false end
   fields(item,{kind=true,id=true})
   if item.kind~='weapon' and item.kind~='armor'then fail('E_ACTOR_STATE_SHAPE','Equipment must be a weapon, armor or false')end
   ref(item.kind=='weapon'and 'weapons'or 'armors',item.id)
   return{kind=item.kind,id=item.id}
  end
  local function equipSlots(s,p)
   local slots={};for i=1,slotCount do slots[i]=catalog.visuEquipSlots and catalog.visuEquipSlots[i]or i end;if slotCount>=2 and traits(s,p).isDualWield()then slots[2]=1 end;return slots
  end
  local function checkSlot(s,p,slot)
   slot=number(slot,1,slotCount)
   if context(s,p).equipment[slot]==nil then fail('E_ACTOR_STATE_REFERENCE','Equipment slot does not exist')end
   return slot
  end
  local function changeable(s,p,slot)
   local tr=traits(s,p);local etype=equipSlots(s,p)[slot]
   return not tr.isEquipTypeLocked(etype)and not tr.isEquipTypeSealed(etype)
  end
  local function canEquip(s,p,item)
   if item==false then return true end
   local r=ref(item.kind=='weapon'and 'weapons'or 'armors',item.id);local tr=traits(s,p)
   return not tr.isEquipTypeSealed(r.etypeId)and (item.kind=='weapon'and tr.isEquipWtypeOk(r.wtypeId)or item.kind=='armor'and tr.isEquipAtypeOk(r.atypeId))
  end
  local function candidates(s,p,slot)
   local out={};local etype=equipSlots(s,p)[slot]
   for _,kind in ipairs({'weapon','armor'})do
    local ids={};for id,r in pairs(defs[kind=='weapon'and 'weapons'or 'armors'])do if r.etypeId==etype and p.count(kind,id)>0 then ids[#ids+1]=id end end;table.sort(ids)
    for _,id in ipairs(ids)do local item={kind=kind,id=id};if canEquip(s,p,item)then out[#out+1]=item end end
   end
   out[#out+1]=false;return out
  end
  function A.equipState(actorId)
   ref('actors',actorId);local s=data[actorId];local slots={};for i=1,slotCount do checkSlot(s,party,i);slots[i]=changeable(s,party,i)end
   return{actor=view(s,party),changeableSlots=slots}
  end
  function A.equipCandidates(actorId,slot)
   ref('actors',actorId);local s=data[actorId];slot=checkSlot(s,party,slot);return candidates(s,party,slot)
  end
  function A.previewEquip(actorId,slot,item,rngState)
   ref('actors',actorId);local s=data[actorId];slot=checkSlot(s,party,slot);item=key(item)
   if busy then fail('E_ACTOR_STATE_REENTRY','Actors mutation is not reentrant')end
   local random={state=Rng.restore(rngState).snapshot()};busy=true
   local ok,_,prepared=pcall(party.transaction,function(p)
    local candidate=copy(s);p.setEquipment(actorId,slot,item);equipmentLegal(candidate,p,true,true)
    candidate=applyShared(candidate,p,{op='refresh'},random)
    return false,{actor=view(candidate,p),rngState=copy(random.state)}
   end)
   busy=false;if not ok then error(_,0)end;return prepared
  end
  local function nativeChange(s,p,slot,item,random)
   local old=context(s,p).equipment[slot]
   if not p.tradeEquipment(item,old)then return s,false end
   local r=item~=false and ref(item.kind=='weapon'and 'weapons'or 'armors',item.id)
   if item==false or r.etypeId==equipSlots(s,p)[slot]then
    p.setEquipment(s.actorId,slot,item);s=applyShared(s,p,{op='refresh'},random);return s,true
   end
   return s,false
  end
  local function bestItem(s,p,slot)
   local best,score=false,-1000.0
   for _,item in ipairs(candidates(s,p,slot))do if item~=false then
    local r=ref(item.kind=='weapon'and 'weapons'or 'armors',item.id);local performance=0.0
    for _,value in ipairs(r.params)do performance=performance+value*1.0;number(performance)end
    if performance>score then best,score=item,performance end
   end end;return best
  end
  eventEquip=function(s,p,slot,itemId,random)
   slot=checkSlot(s,p,slot);number(itemId,0)
   local kind=equipSlots(s,p)[slot]==1 and 'weapon' or 'armor'
   local record=defs[kind=='weapon' and 'weapons' or 'armors'][itemId]
   local item=record and {kind=kind,id=itemId} or false
   return nativeChange(s,p,slot,item,random)
  end
  function A.eventEquip(actorId,slot,itemId,rngState)
   ref('actors',actorId)
   return transaction(rngState,function(all,p,random)
    all[actorId]=eventEquip(all[actorId],p,slot,itemId,random)
    return{ok=true,actor=view(all[actorId],p)}
   end)
  end
  function A.equipmentCommand(command,rngState)
   fields(command,{action=true,actorId=true,slot=true,item=true});local action=command.action
   if action~='change'and action~='clear'and action~='optimize'then fail('E_ACTOR_STATE_UNSUPPORTED','Equipment menu action is not implemented')end
   if action~='change'and (command.slot~=nil or command.item~=nil)then fail('E_ACTOR_STATE_SHAPE','Clear/optimize have no slot or item field')end
   ref('actors',command.actorId);local slot,item
   if action=='change'then slot=checkSlot(data[command.actorId],party,command.slot);item=key(command.item)end
   return transaction(rngState,function(all,p,random)
    local s=all[command.actorId]
    if not p.hasActor(command.actorId)then return{ok=false,reason='member'}end
    if action=='change'then
     local reason
     if not changeable(s,p,slot)then reason='locked'
     elseif item~=false and ref(item.kind=='weapon'and 'weapons'or 'armors',item.id).etypeId~=equipSlots(s,p)[slot]then reason='etype'
     elseif not canEquip(s,p,item)then reason='permission'
     elseif item~=false and p.count(item.kind,item.id)<1 then reason='inventory'end
     if reason then return{ok=false,reason=reason}end
     s=nativeChange(s,p,slot,item,random)
    else
     for i=1,slotCount do checkSlot(s,p,i);if changeable(s,p,i)then s=nativeChange(s,p,i,false,random)end end
     if action=='optimize'then for i=1,slotCount do if changeable(s,p,i)then s=nativeChange(s,p,i,bestItem(s,p,i),random)end end end
    end
    all[command.actorId]=s;return{ok=true,actor=view(s,p)}
   end)
  end
  return A
 end
 function M.new(definitions,options)
  local party,profile=rawOptions(options)
  local catalog,rules,battler=M.prepare(definitions,profile)
  return instance(catalog,rules,battler,party,options)
 end
 function M.fromCompiledCatalog(catalog)
  plain(catalog)
  if catalog.kind~='r2u.actor-catalog' or catalog.schemaVersion~=1 or catalog.catalogVersion~=2 or
   catalog.profile~='mv-1.5.1' and catalog.profile~='mz-1.10.0'then fail('E_ACTOR_PROFILE','Invalid compiled actor catalog ABI')end
  plain(catalog.actorIds);plain(catalog.growthSeedsById);number(catalog.slotCount,1)
  local rules=Rules.fromCompiledCatalog(catalog);local battler=Battler.fromCompiledCatalog(catalog)
  return {newActors=function(party,options)
   if options==nil then options={}end;fields(options,{state=true})
   if type(party)~='table' or type(party.snapshot)~='function' or type(party.transaction)~='function'then fail('E_ACTOR_STATE_SHAPE','Party instance with transaction is required')end
   return instance(catalog,rules,battler,party,options)
  end}
 end
 return M
end
