-- Native onPlayerWalk order over Actors' existing revocable candidates.
return function(deps)
 local Lifecycle,Rng=deps['runtime.rpg.battle_lifecycle'],deps['runtime.core.rng'];local M={}
 local function fail(reason)error({severity='error',code='E_MAP_EFFECTS',reason=reason},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('Expected plain map-effect data')end end
 local function integer(v)return type(v)=='number'and v==v and v>=0 and v<=9007199254740991 and v%1==0 end
 local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
 local function metadata(row,key,default)
  local v=row[key];if v==nil and row.sourceMeta then plain(row.sourceMeta);local extra=row.sourceMeta.unhandledFields;if extra then plain(extra);v=extra[key]end end
  if v==nil then return default end;return v
 end
 function M.prepare(definitions)
  plain(definitions);plain(definitions.system);plain(definitions.states)
  local profile=definitions.profile;if profile~='mz-1.10.0'and profile~='mv-1.5.1'then fail('Unsupported map-effect profile')end
  local floorDeath=metadata(definitions.system,'optFloorDeath',false);local slipDeath=metadata(definitions.system,'optSlipDeath',false)
  if type(floorDeath)~='boolean'or type(slipDeath)~='boolean'then fail('Floor/slip death flags must be boolean')end
  local states,lifeStates={},{}
  for _,row in ipairs(definitions.states)do
   plain(row);if not integer(row.id)or row.id<1 or states[row.id]then fail('Invalid map-effect state id')end
   local walk=metadata(row,'removeByWalking',false);local timing=metadata(row,'autoRemovalTiming',0)
   local added,removed=metadata(row,'message1',''),metadata(row,'message4','')
   if type(walk)~='boolean'or not integer(timing)or timing>2 or type(added)~='string'or type(removed)~='string'then fail('Invalid map state removal/message metadata')end
   states[row.id]={id=row.id,removeByWalking=walk,message1=added,message4=removed}
   lifeStates[row.id]={id=row.id,autoRemovalTiming=timing,removeAtBattleEnd=false}
  end
  if not states[1]then fail('Death state 1 is required')end
  return{kind='r2u.map-effects-catalog',schemaVersion=1,profile=profile,optFloorDeath=floorDeath,statesById=states,
   lifecycle={kind='r2u.battle-lifecycle-catalog',schemaVersion=1,catalogVersion=1,profile=profile,optSlipDeath=slipDeath,statesById=lifeStates}}
 end
 function M.fromCompiledCatalog(catalog)
  plain(catalog);if catalog.kind~='r2u.map-effects-catalog'or catalog.schemaVersion~=1 or type(catalog.optFloorDeath)~='boolean'then fail('Invalid compiled map-effect catalog')end
  plain(catalog.statesById);local lifecycle=Lifecycle.fromCompiledCatalog(catalog.lifecycle);local states=catalog.statesById;local E={}
  local function state(id)local s=states[id];if not s then fail('Missing compiled map-effect state')end;return s end
  local function result()return{hpAffected=false,hpDamage=0,mpDamage=0,tpDamage=0,addedStates={},removedStates={},addedBuffs={},addedDebuffs={},removedBuffs={}}end
  local function merge(out,r)
   if not r then return end
   if r.hpAffected then out.hpAffected=true;out.hpDamage=r.hpDamage end
   for _,k in ipairs({'addedStates','removedStates','addedBuffs','addedDebuffs','removedBuffs'})do for _,id in ipairs(r[k]or {})do local found=false;for _,v in ipairs(out[k])do if v==id then found=true end end;if not found then out[k][#out[k]+1]=id end end end
  end
  function E.apply(request,ctx)
   plain(request);if not integer(request.steps)or type(request.normal)~='boolean'or type(request.onDamageFloor)~='boolean'then fail('Invalid onPlayerWalk request')end
   for _,method in ipairs({'members','query','apply','setStateSteps'})do if type(ctx[method])~='function'then fail('Map effects require an Actor candidate '..method)end end
   local rng=Rng.restore(request.rngState).snapshot();local out={ok=true,flash=false,messages={},actorResults={},allDead=false}
   local members=ctx.members()
   for _,id in ipairs(members)do
    local ref={kind='actor',id=id};local actorResult=result()
    local function query()return ctx.query(ref)end
    local function apply(operation)local r=ctx.apply(ref,operation,rng);rng=r.rngState;merge(actorResult,r.result);return r end
    if request.onDamageFloor then
     local q=query();local maximum=catalog.optFloorDeath and q.hp or math.max(q.hp-1,0)
     local damage=math.min(math.floor(10*q.sparams[9]),maximum)
     apply({op='gainHp',value=-damage});if damage>0 then out.flash=true end
    end
    if request.normal then
     if request.steps%20==0 then
      local turn=lifecycle.apply({phase='turnEnd',ref=ref,rngState=rng},ctx);rng=turn.rngState;actorResult=turn.result
      if actorResult.hpDamage>0 then out.flash=true end
     end
     local q=query();local walking=copy(q.stateIds)
     for _,stateId in ipairs(walking)do
      if state(stateId).removeByWalking then
       local nextSteps=copy(query().stateSteps);local expires=false
       for _,count in ipairs(nextSteps)do if count.stateId==stateId and count.steps>0 then count.steps=count.steps-1;expires=count.steps==0 end end
       ctx.setStateSteps(ref,{stateSteps=nextSteps})
       if expires then apply({op='removeState',stateId=stateId})end
      end
     end
     for _,pair in ipairs({{'addedStates','message1'},{'removedStates','message4'}})do
      for _,stateId in ipairs(actorResult[pair[1]])do local template=state(stateId)[pair[2]];if template~=''then out.messages[#out.messages+1]={actorId=id,stateId=stateId,template=template}end end
     end
    end
    out.actorResults[#out.actorResults+1]={actorId=id,result=actorResult}
   end
   if #members>0 then out.allDead=true;for _,id in ipairs(members)do local dead=false;for _,stateId in ipairs(ctx.query({kind='actor',id=id}).stateIds)do if stateId==1 then dead=true end end;if not dead then out.allDead=false end end end
   out.rngState=rng;return out
  end
  return E
 end
 function M.new(definitions)return M.fromCompiledCatalog(M.prepare(definitions))end
 return M
end
