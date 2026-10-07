-- MV/MZ item effects. ctx owns the encompassing uncommitted transaction.
return function(deps)
 local RNG=deps['runtime.core.rng'];local M={};local SAFE,LIMIT=9007199254740991,100000
 local arrays={'addedStates','removedStates','addedBuffs','addedDebuffs','removedBuffs'}
 local function fail(code,reason)error({severity='error',code=code,reason=reason,profile='mz-1.10.0'},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_EFFECT_SHAPE','Expected plain table')end end
 local function fields(v,required,optional)
  plain(v);local allowed={};for k in required:gmatch('%S+')do allowed[k]=true;if rawget(v,k)==nil then fail('E_EFFECT_SHAPE','Missing required field')end end
  for k in (optional or ''):gmatch('%S+')do allowed[k]=true end;for k in next,v do if not allowed[k]then fail('E_EFFECT_SHAPE','Unknown field')end end
 end
 local function finite(v)if type(v)~='number' or v~=v or v==math.huge or v==-math.huge then fail('E_EFFECT_NUMBER','Expected finite number')end;return v*1.0 end
 local function integer(v,lo,hi)v=finite(v);if v%1~=0 or v<(lo or -SAFE)or v>(hi or SAFE)then fail('E_EFFECT_NUMBER','Integer outside supported safe range')end;return v end
 local function dense(v,n)plain(v);local count,high=0,0;for k in next,v do integer(k,1,LIMIT);count=count+1;high=math.max(high,k)end;if high~=count or n and n~=count then fail('E_EFFECT_SHAPE','Expected bounded dense array')end;return count end
 local function copy(v,seen,depth,budget)
  if type(v)~='table'then local k=type(v);if k=='number'then return finite(v)end;if k~='nil'and k~='string'and k~='boolean'then fail('E_EFFECT_SHAPE','Executable output value')end;return v end
  plain(v);seen=seen or {};depth=depth or 0;budget=budget or {left=LIMIT};if seen[v]or depth>32 then fail('E_EFFECT_SHAPE','Cyclic or deeply nested output')end;seen[v]=true;local out={};for k,x in next,v do budget.left=budget.left-1;if budget.left<0 then fail('E_EFFECT_BUDGET','Output copy budget exceeded')end;if type(k)=='number'then integer(k)elseif type(k)~='string'then fail('E_EFFECT_SHAPE','Invalid output key')end;out[k]=copy(x,seen,depth+1,budget)end;seen[v]=nil;return out
 end
 local function actionRef(r)fields(r,'kind id');if r.kind~='skill'and r.kind~='item'then fail('E_EFFECT_REFERENCE','Unknown action kind')end;return{kind=r.kind,id=integer(r.id,1)}end
 local function battlerRef(r)
  plain(r);if r.kind=='actor'then fields(r,'kind id');return{kind=r.kind,id=integer(r.id,1)}
  elseif r.kind=='enemy'then fields(r,'kind battleId troopSlot');if type(r.battleId)~='string'or #r.battleId<1 or #r.battleId>128 then fail('E_EFFECT_SHAPE','battleId must be a nonempty string of at most 128 bytes')end;return{kind=r.kind,battleId=r.battleId,troopSlot=integer(r.troopSlot,1)}end
  fail('E_EFFECT_REFERENCE','Unknown battler kind')
 end
 local function result()return{success=false,hpAffected=false,hpDamage=0,mpDamage=0,tpDamage=0,addedStates={},removedStates={},addedBuffs={},addedDebuffs={},removedBuffs={}}end
 local function push(list,id)for _,x in ipairs(list)do if x==id then return end end;list[#list+1]=id end
 function M.prepare(defs,profile,options)
  plain(defs);if (profile~='mz-1.10.0' and profile~='mv-1.5.1')or defs.profile~=profile or defs.schemaVersion~=1 then fail('E_EFFECT_PROFILE','Requires schema 1 / MV 1.5.1 or MZ 1.10.0')end
  options=options or {commonEvents={}};fields(options,'commonEvents');local common,states,skillIds={},{},{}
  for _,entry in ipairs((function()dense(options.commonEvents);return options.commonEvents end)())do plain(entry);local id=integer(entry.id,1);if common[id]or type(entry.programId)~='string'or #entry.programId==0 then fail('E_EFFECT_REFERENCE','Invalid common event program index')end;common[id]=entry.programId end
  dense(defs.states);for _,s in ipairs(defs.states)do plain(s);local id=integer(s.id,1);if states[id]then fail('E_EFFECT_REFERENCE','Duplicate state ID')end;states[id]=true end
  dense(defs.skills);for _,s in ipairs(defs.skills)do plain(s);local id=integer(s.id,1);if skillIds[id]then fail('E_EFFECT_REFERENCE','Duplicate skill ID')end;skillIds[id]=true end
  local catalogs={skill={},item={}};local codes={[11]=true,[12]=true,[13]=true,[21]=true,[22]=true,[31]=true,[32]=true,[33]=true,[34]=true,[41]=true,[42]=true,[43]=true,[44]=true}
  for _,kind in ipairs({'skill','item'})do
   local records=kind=='skill'and defs.skills or defs.items;dense(records)
   for _,s in ipairs(records)do
    plain(s);local id=integer(s.id,1);if catalogs[kind][id]then fail('E_EFFECT_REFERENCE','Duplicate action ID')end
    local a={id=id,kind=kind,hitType=integer(s.hitType,0,2),tpGain=finite(s.tpGain),effects={}}
    for i=1,dense(s.effects)do
     local v=s.effects[i];fields(v,'code dataId value1 value2');local e={code=integer(v.code,1),dataId=integer(v.dataId,0),value1=finite(v.value1),value2=finite(v.value2)}
     local code,key=e.code,e.dataId;if not codes[code]then fail('E_EFFECT_UNSUPPORTED','Unknown effect code')end
     if code==21 or code==22 then if not (code==21 and key==0)and not states[key]then fail('E_EFFECT_REFERENCE','Missing effect state')end
     elseif code>=31 and code<=34 or code==42 then integer(key,0,7)
     elseif code==43 then if not skillIds[key]then fail('E_EFFECT_REFERENCE','Missing learned skill')end
     elseif code==44 then if not common[key]then fail('E_EFFECT_REFERENCE','Missing executable common event index')end
     else integer(key,0,0)end
     if code==31 or code==32 then integer(e.value1,0)end;a.effects[i]=e
    end;catalogs[kind][id]=a
   end
  end
  return {kind='r2u.effects-catalog',schemaVersion=1,catalogVersion=1,profile=profile,actionsByKind=catalogs,statesById=states,commonEventsById=common}
 end
 function M.fromCompiledCatalog(catalog)
  fields(catalog,'kind schemaVersion catalogVersion profile actionsByKind statesById commonEventsById')
  if catalog.kind~='r2u.effects-catalog' or catalog.schemaVersion~=1 or catalog.catalogVersion~=1 or (catalog.profile~='mz-1.10.0' and catalog.profile~='mv-1.5.1') then fail('E_EFFECT_PROFILE','Invalid compiled effects catalog ABI')end
  local catalogs,states,common=catalog.actionsByKind,catalog.statesById,catalog.commonEventsById
  plain(catalogs);plain(catalogs.skill);plain(catalogs.item);plain(states);plain(common)
  local E={}
  local function action(r)local ref=actionRef(r);local a=catalogs[ref.kind][ref.id];if not a then fail('E_EFFECT_REFERENCE','Missing action')end;return a end
  local function run(request,ctx,userOnly)
   fields(request,userOnly and 'actionRef subjectRef rngState'or'actionRef subjectRef targetRef inBattle rngState');plain(ctx)
   if type(ctx.query)~='function'or type(ctx.apply)~='function'then fail('E_EFFECT_CAPABILITY','query/apply candidate capabilities required')end
   local a=action(request.actionRef);local subject=battlerRef(request.subjectRef);local target=userOnly and subject or battlerRef(request.targetRef)
   if not userOnly and type(request.inBattle)~='boolean'then fail('E_EFFECT_SHAPE','Explicit inBattle required')end
   local random=RNG.restore(request.rngState);local rngState=random.snapshot();local initialDraws=rngState.draws;local copiedRandomValues=rngState.values and #rngState.values*2 or 0
   local out={effectLogs={},resultDelta=result(),resultWrites={},actualDelta={},hooks={},draws={}}
   local effectIndex,work=0,0
   local function spend()work=work+1;if work>LIMIT then fail('E_EFFECT_BUDGET','Effect execution budget exceeded')end end
   local function randomCopyCost(count)copiedRandomValues=copiedRandomValues+count;if copiedRandomValues>1000000 then fail('E_EFFECT_BUDGET','Random snapshot copy budget exceeded')end end
   local function snapshot()randomCopyCost(rngState.values and #rngState.values*2 or 0);rngState=random.snapshot();return copy(rngState)end
   local function call(fn,...)
    local ok,v=pcall(fn,...);if ok then return v end
    if type(v)=='table'and getmetatable(v)==nil and type(rawget(v,'code'))=='string'and type(rawget(v,'reason'))=='string'and rawget(v,'severity')=='error'then
     local d={severity='error',code=v.code,reason=v.reason,effectIndex=effectIndex,actionRef={kind=a.kind,id=a.id}};for _,k in ipairs({'path','file','jsonPath','profile'})do if type(rawget(v,k))=='string'then d[k]=v[k]end end;error(d,0)
    end
    error({severity='error',code='E_EFFECT_CONTEXT',reason='Candidate callback failed',effectIndex=effectIndex,actionRef={kind=a.kind,id=a.id}},0)
   end
   local function query(ref)
    spend();local q=call(ctx.query,copy(ref));plain(q);if q.kind~=ref.kind then fail('E_EFFECT_SHAPE','Candidate kind does not match reference')end
    integer(q.hp,0);integer(q.mp);integer(q.tp);dense(q.params,8);dense(q.buffs,8)
    for i=1,8 do integer(q.params[i],i==1 and 1 or 0);integer(q.buffs[i],-2,2)end
    plain(q.traits);for _,name in ipairs({'sparam','stateRate','debuffRate','attackStates','attackStatesRate'})do if type(q.traits[name])~='function'then fail('E_EFFECT_CAPABILITY','Required trait query missing')end end
    return q
   end
   local function tr(q,name,id)return finite(call(q.traits[name],id))end
   local function luck()local s,t=query(subject),query(target);return finite(math.max(finite(1.0+finite(s.params[8]*1.0-t.params[8])*.001),0.0))end
   local function probability(chance,purpose)
    spend();chance=finite(chance);local unit=random.nextUnit(purpose);out.draws[#out.draws+1]=random.lastDraw();out.draws[#out.draws].threshold=chance;return unit<chance
   end
   local function merge(r,operation,ref)
    fields(r,'result hooks rngState','state');local value=r.result
    fields(value,'hpAffected hpDamage mpDamage tpDamage addedStates removedStates addedBuffs addedDebuffs removedBuffs')
    if type(value.hpAffected)~='boolean'then fail('E_EFFECT_SHAPE','Invalid result flag')end;integer(value.hpDamage);integer(value.mpDamage);integer(value.tpDamage)
    local field=operation.op=='gainHp'and 'hpDamage'or operation.op=='gainMp'and 'mpDamage'or operation.op=='gainTp'and 'tpDamage'
    if field then out.resultDelta[field]=value[field];out.resultWrites[field]=true;if field=='hpDamage'then out.resultDelta.hpAffected=value.hpAffected;out.resultWrites.hpAffected=true end end
    for _,name in ipairs(arrays)do dense(value[name]);for _,id in ipairs(value[name])do local stateField=name=='addedStates'or name=='removedStates';integer(id,stateField and 1 or 0,stateField and SAFE or 7);if stateField and not states[id]then fail('E_EFFECT_REFERENCE','Result references missing state')end;push(out.resultDelta[name],id)end end
    dense(r.hooks);for _,hook in ipairs(r.hooks)do local h=copy(hook);plain(h);h.battlerRef=copy(ref);out.hooks[#out.hooks+1]=h end
    local nextRandom=RNG.restore(r.rngState);local nextState=nextRandom.snapshot();randomCopyCost(nextState.values and #nextState.values*2 or 0);if nextState.draws<rngState.draws or nextState.algorithm~=rngState.algorithm then fail('E_EFFECT_CONTEXT','Candidate RNG moved backwards or changed algorithm')end;rngState=nextState;random=nextRandom
   end
   local log
   local function apply(op)
    spend();log.operations[#log.operations+1]=copy(op);merge(call(ctx.apply,copy(target),copy(op),snapshot()),op,target)
   end
   local function success()out.resultDelta.success=true;out.resultWrites.success=true;log.success=true end
   local function floor(v)v=finite(v);return integer(v==0 and v or math.floor(v)*1.0)end
   query(subject);local initial=query(target);local before={hp=initial.hp,mp=initial.mp,tp=initial.tp}
   -- Capability failure is detected before any effect callback or random draw.
   if not userOnly then for _,e in ipairs(a.effects)do
    if e.code==41 and type(ctx.escape)~='function'then fail('E_EFFECT_CAPABILITY','escape candidate capability required')end
    if e.code==43 and target.kind=='actor'and type(ctx.learnSkill)~='function'then fail('E_EFFECT_CAPABILITY','learnSkill candidate capability required')end
   end end
   if userOnly then
    log={phase='user',operations={},success=false};out.effectLogs[1]=log
    local value=floor(finite(a.tpGain*tr(query(subject),'sparam',5)));apply({op='gainSilentTp',value=value})
   else
    for i,e in ipairs(a.effects)do
     spend();effectIndex=i;log={effectIndex=i,code=e.code,dataId=e.dataId,operations={},success=false};out.effectLogs[#out.effectLogs+1]=log
     local code,id=e.code,e.dataId
     if code==11 or code==12 then
      local q=query(target);local v=finite(finite(finite(q.params[code==11 and 1 or 2]*1.0*e.value1)+e.value2)*tr(q,'sparam',2))
      if a.kind=='item'then v=finite(v*tr(query(subject),'sparam',3))end;v=floor(v)
      if v~=0 then apply({op=code==11 and 'gainHp'or 'gainMp',value=v});success()end
     elseif code==13 then local v=floor(e.value1);if v~=0 then apply({op='gainTp',value=v});success()end
     elseif code==21 then
      local ids={id};if id==0 then ids=call(query(subject).traits.attackStates);dense(ids);local captured={};for j,x in ipairs(ids)do integer(x,1);if not states[x]then fail('E_EFFECT_REFERENCE','Missing attack state')end;captured[j]=x end;ids=captured end
      for _,stateId in ipairs(ids)do
       local chance=e.value1
       if id==0 or a.hitType~=0 then chance=finite(chance*tr(query(target),'stateRate',stateId));if id==0 then chance=finite(chance*tr(query(subject),'attackStatesRate',stateId))end;chance=finite(chance*luck())end
       if probability(chance,'effects:add-state')then apply({op='addState',stateId=stateId});success()end
      end
     elseif code==22 then if probability(e.value1,'effects:remove-state')then apply({op='removeState',stateId=id});success()end
     elseif code==31 then apply({op='addBuff',paramId=id,turns=e.value1});success()
     elseif code==32 then if probability(finite(tr(query(target),'debuffRate',id)*luck()),'effects:add-debuff')then apply({op='addDebuff',paramId=id,turns=e.value1});success()end
     elseif code==33 or code==34 then local stage=query(target).buffs[id+1];if code==33 and stage>0 or code==34 and stage<0 then apply({op='removeBuff',paramId=id});success()end
     elseif code==41 then
      local r=call(ctx.escape,copy(target),request.inBattle,snapshot());fields(r,'hooks rngState');local empty=result();empty.success=nil;merge({hooks=r.hooks,rngState=r.rngState,result=empty},{op='escape'},target);log.operations[#log.operations+1]={op='escape',inBattle=request.inBattle};success()
     elseif code==42 then apply({op='addParam',paramId=id,value=floor(e.value1)});success()
     elseif code==43 then if target.kind=='actor'then call(ctx.learnSkill,copy(target),id);log.operations[#log.operations+1]={op='learnSkill',skillId=id};success()end
     end
    end
   end
   local after=query(target);for _,key in ipairs({'hp','mp','tp'})do out.actualDelta[key]=integer(after[key]*1.0-before[key])end
   out.rngState=snapshot();out.drawsUsed=integer(rngState.draws-initialDraws,0);return out
  end
  function E.applyTarget(request,ctx)return run(request,ctx,false)end
  function E.applyUser(request,ctx)return run(request,ctx,true)end
  function E.applyGlobal(ref)local a=action(ref);local out={};for _,e in ipairs(a.effects)do if e.code==44 then if catalog.profile=='mv-1.5.1'then out={}end;out[#out+1]={commonEventId=e.dataId,programId=common[e.dataId]}end end;return out end
  return E
 end
 function M.new(defs,profile,options)return M.fromCompiledCatalog(M.prepare(defs,profile,options))end
 return M
end
