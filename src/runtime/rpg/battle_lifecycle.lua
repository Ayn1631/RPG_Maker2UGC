-- MV/MZ source lifecycle order, operating only on a caller's revocable candidates.
return function(deps)
 local RNG=deps['runtime.core.rng'];local M={};local SAFE=9007199254740991
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function shape(why)fail('E_LIFECYCLE_SHAPE',why)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then shape('Expected plain data table')end end
 local function number(v,lo,hi,integer)
  if type(v)~='number' or v~=v or v<(lo or -SAFE) or v>(hi or SAFE) or integer~=false and v%1~=0 then fail('E_LIFECYCLE_NUMBER','Invalid finite supported number')end;return v*1.0
 end
 local function dense(v,n)
  plain(v);local count,max=0,0;for k in next,v do number(k,1);count=count+1;max=math.max(max,k)end
  if count~=max or n and count~=n then shape('Expected dense array')end;return count
 end
 local function fields(v,allowed)plain(v);for k in next,v do if not allowed[k]then shape('Unknown field')end end end
 local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in next,v do o[k]=copy(x)end;return o end
 local function metadata(row,name)
  local v=row[name]
  if v==nil and row.sourceMeta~=nil then
   plain(row.sourceMeta);local unhandled=row.sourceMeta.unhandledFields
   if unhandled~=nil then plain(unhandled);v=unhandled[name]end
  end;return v
 end
 function M.prepare(definitions,profile)
  plain(definitions);if profile~='mz-1.10.0' and profile~='mv-1.5.1'or definitions.profile~=nil and definitions.profile~=profile then fail('E_LIFECYCLE_PROFILE','Requires MV 1.5.1 or MZ 1.10.0 lifecycle')end
  dense(definitions.states);plain(definitions.system);local states={}
  for _,row in ipairs(definitions.states)do
   plain(row);local id=number(row.id,1);if states[id]then fail('E_LIFECYCLE_REFERENCE','Duplicate state')end
   local timing=number(metadata(row,'autoRemovalTiming'),0,2);local battle=metadata(row,'removeAtBattleEnd')
   if type(battle)~='boolean'then shape('Battle state removal flag required')end
   states[id]={visu=row.visu~=nil or nil,id=id,autoRemovalTiming=timing,removeAtBattleEnd=battle}
  end
  if not states[1]then fail('E_LIFECYCLE_REFERENCE','Death state 1 required')end
  local slip=metadata(definitions.system,'optSlipDeath');if type(slip)~='boolean'then shape('Slip death flag required')end
  return{kind='r2u.battle-lifecycle-catalog',schemaVersion=1,catalogVersion=1,profile=profile,statesById=states,optSlipDeath=slip}
 end
 function M.fromCompiledCatalog(catalog)
  plain(catalog);if catalog.kind~='r2u.battle-lifecycle-catalog' or catalog.schemaVersion~=1 or catalog.catalogVersion~=1 or (catalog.profile~='mz-1.10.0' and catalog.profile~='mv-1.5.1')then fail('E_LIFECYCLE_PROFILE','Invalid lifecycle catalog ABI')end
  plain(catalog.statesById);if type(catalog.optSlipDeath)~='boolean'then shape('Slip death flag required')end
  local states=catalog.statesById;local mv=catalog.profile=='mv-1.5.1';local B={}
  local function ref(id)number(id,1);local s=states[id];if not s then fail('E_LIFECYCLE_REFERENCE','Missing lifecycle state')end;return s end
  function B.apply(request,ctx)
   fields(request,{phase=true,ref=true,rngState=true,advantageous=true,tpbRelativeSpeed=true,forcedTurn=true})
   if request.forcedTurn~=nil and (not mv or request.phase~='turnEnd'or type(request.forcedTurn)~='boolean')then shape('forcedTurn is an MV turn-end boolean')end
   local phase=request.phase;if phase~='battleStart' and phase~='actionsEnd' and phase~='turnEnd' and phase~='battleEnd' and phase~='removeBattleStates'then fail('E_LIFECYCLE_PHASE','Unsupported lifecycle phase')end
   fields(request.ref,{kind=true,id=true,battleId=true,troopSlot=true,enemyId=true})
   if request.ref.kind~='actor' and request.ref.kind~='enemy'then fail('E_LIFECYCLE_REFERENCE','Battler reference required')end
   if phase=='battleStart'then
    if type(request.advantageous)~='boolean'then shape('Advantageous flag required')end
    number(request.tpbRelativeSpeed,0,SAFE,false)
   elseif request.advantageous~=nil or request.tpbRelativeSpeed~=nil then shape('Battle-start fields outside battle start')end
   plain(ctx);for _,key in ipairs({'query','apply','setTurns','appear'})do if type(ctx[key])~='function'then shape('Candidate context method required')end end
   local rng=RNG.restore(request.rngState);local hooks={};local result={hpAffected=false,hpDamage=0,mpDamage=0,tpDamage=0,addedStates={},removedStates={},addedBuffs={},addedDebuffs={},removedBuffs={}}
   local sourceTpb
   local function hook(op,data)local h=data or {};h.op=op;hooks[#hooks+1]=h end
   local function append(rows)for _,h in ipairs(rows or {})do
    hooks[#hooks+1]=copy(h)
    if sourceTpb and h.op=='clearTpbChargeTime'then sourceTpb.state='charging';sourceTpb.chargeTime=0.0 end
   end end
   local function query()
    local q=ctx.query(request.ref);plain(q);dense(q.stateIds);dense(q.stateTurns);dense(q.buffs,8);dense(q.buffTurns,8)
    for _,id in ipairs(q.stateIds)do ref(id)end;return q
   end
   local function apply(op)
    local out=ctx.apply(request.ref,op,rng.snapshot());rng=RNG.restore(out.rngState);append(out.hooks)
    local r=out.result;if r then
     if r.hpAffected then result.hpAffected=true;result.hpDamage=r.hpDamage end
     if op.op=='gainMp'then result.mpDamage=r.mpDamage end
     if op.op=='gainTp'then result.tpDamage=r.tpDamage end
     for _,key in ipairs({'addedStates','removedStates','addedBuffs','addedDebuffs','removedBuffs'})do for _,id in ipairs(r[key] or {})do local exists=false;for _,v in ipairs(result[key])do if v==id then exists=true end end;if not exists then result[key][#result[key]+1]=id end end end
    end
   end
   local function turns(q,id)for _,r in ipairs(q.stateTurns)do if r.stateId==id then return r.turns end end end
   local function removeStates(timing,battle)
    local ids=copy(query().stateIds)
    for _,id in ipairs(ids)do local s=ref(id);if battle and s.removeAtBattleEnd or not battle and s.autoRemovalTiming==timing and turns(query(),id)==0 then apply({op='removeState',stateId=id})end end
   end
   local function removeBuffs(all)
    for p=0,7 do if all or query().buffTurns[p+1]==0 then apply({op='removeBuff',paramId=p})end end
   end
   if phase=='battleStart'then
    local q=query();hook('setActionState',{value='undecided'});hook('clearMotion')
    if not mv then
    local charge=request.advantageous and 1.0 or request.tpbRelativeSpeed*rng.nextUnit('battle:start:tpbChargeTime')*.5
    if not q.hidden and q.restriction>0 then charge=0.0 end
    sourceTpb={state='charging',chargeTime=charge,turnEnd=false,turnCount=0,idleTime=0}
    hook('initTpbChargeTime',{state='charging',chargeTime=charge});hook('initTpbTurn',{turnEnd=false,turnCount=0,idleTime=0})
    end
    if not q.traits.isPreserveTp()then local tp=rng.nextInt(25,'battle:start:tp');apply({op='gainSilentTp',value=tp-query().tp})end
   elseif phase=='removeBattleStates'then removeStates(nil,true)
   else
    hook('clearResult')
    if phase=='actionsEnd'then if states[1].visu then local q=query();local st=copy(q.stateTurns);for _,r in ipairs(st)do local def=ref(r.stateId);if def.visu and def.autoRemovalTiming==1 and r.turns>0 then r.turns=r.turns-1 end end;ctx.setTurns(request.ref,{stateTurns=st,buffTurns=copy(q.buffTurns)})end;removeStates(1,false);removeBuffs(false)
    elseif phase=='turnEnd'then
     local q=query();local alive=not q.hidden;for _,id in ipairs(q.stateIds)do if id==1 then alive=false end end
     if alive then
      local value=math.max(math.floor(q.params[1]*q.xparams[8]),-(catalog.optSlipDeath and q.hp or math.max(q.hp-1,0)))
      if value~=0 then apply({op='gainHp',value=value})end
      q=query();value=math.floor(q.params[2]*q.xparams[9]);if value~=0 then apply({op='gainMp',value=value})end
      q=query();apply({op='gainSilentTp',value=math.floor(100*q.xparams[10])})
     end
     q=query();local active={};for _,id in ipairs(q.stateIds)do active[id]=true end
     local st,bt=copy(q.stateTurns),copy(q.buffTurns)
     if not (mv and request.forcedTurn)then
     for _,r in ipairs(st)do if active[r.stateId] and r.turns>0 and not(ref(r.stateId).visu and ref(r.stateId).autoRemovalTiming==1)then r.turns=r.turns-1 end end
     for i,v in ipairs(bt)do if v>0 then bt[i]=v-1 end end
     end;ctx.setTurns(request.ref,{stateTurns=st,buffTurns=bt});removeStates(2,false)
    else
     removeStates(nil,true);removeBuffs(true);hook('clearActions')
     local q=query();if not q.traits.isPreserveTp()then apply({op='gainSilentTp',value=-q.tp})end
     local out=ctx.appear(request.ref);if out then append(out.hooks)else hook('appear')end
    end
   end
   return{ok=true,hooks=hooks,result=result,rngState=rng.snapshot(),sourceTpb=sourceTpb}
  end
  function B.removeBattleStates(request,ctx)
   fields(request,{ref=true,rngState=true})
   return B.apply({phase='removeBattleStates',ref=request.ref,rngState=request.rngState},ctx)
  end
  return B
 end
 function M.new(definitions,profile)return M.fromCompiledCatalog(M.prepare(definitions,profile))end
 return M
end
