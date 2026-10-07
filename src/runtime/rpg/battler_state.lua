-- Common MV 1.5.1 / MZ 1.10.0 Base/Battler operation candidates.
-- Trusted adapters own Actor/Enemy specifics; turn/battle/walk scheduling is separate.
return function(deps)
 local RNG=deps['runtime.core.rng'];local M={};local SAFE=9007199254740991
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function shape(reason)fail('E_BATTLER_SHAPE',reason)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then shape('Expected a plain table')end end
 local function number(v,lo,hi)
  if type(v)~='number' or v~=v or v%1~=0 or v<(lo or -SAFE) or v>(hi or SAFE)then fail('E_BATTLER_NUMBER','Expected finite safe integer in supported range')end;return v*1.0
 end
 local function dense(v,n)
  plain(v);local count,highest=0,0;for k in next,v do
   if type(k)~='number' or k%1~=0 or k<1 or k>SAFE then shape('Array keys must be positive safe integers')end
   count=count+1;highest=math.max(highest,k)
  end;if count~=highest or n and count~=n then shape('Invalid dense array length')end;return count
 end
 local function fields(v,allowed)plain(v);for k in next,v do if not allowed[k]then shape('Unknown field')end end end
 local function copy(v,seen,depth)
  local kind=type(v);if kind~='table'then
   if kind~='number' and kind~='string' and kind~='boolean' and kind~='nil'then shape('Executable values are not state data')end;return v
  end
  plain(v);seen=seen or {};depth=depth or 0;if seen[v] or depth>64 then shape('Cyclic or deeply nested state')end
  seen[v]=true;local out={};for k,x in next,v do if type(k)~='string' and type(k)~='number'then shape('Unsupported state key')end;out[k]=copy(x,seen,depth+1)end;seen[v]=nil;return out
 end
 local function z()return{0,0,0,0,0,0,0,0}end
 local function has(list,id)for _,x in ipairs(list)do if x==id then return true end end;return false end
 local function push(list,id)if not has(list,id)then list[#list+1]=id end end
 local operations={refresh={},recoverAll={},gainHp={value=true},gainMp={value=true},gainTp={value=true},gainSilentTp={value=true},addParam={paramId=true,value=true},addState={stateId=true},removeState={stateId=true},addBuff={paramId=true,turns=true},addDebuff={paramId=true,turns=true},removeBuff={paramId=true}}
 function M.prepare(definitions)
  fields(definitions,{profile=true,states=true})
  local mv=definitions.profile=='mv-1.5.1'
  if not mv and definitions.profile~='mz-1.10.0'then fail('E_BATTLER_PROFILE','Only mv-1.5.1 and mz-1.10.0 operations are implemented')end
  dense(definitions.states);local states={}
  for _,source in ipairs(definitions.states)do
   plain(source);local id=number(source.id,1);if states[id]then fail('E_BATTLER_REFERENCE','Duplicate state ID')end
   local s={visu=source.visu~=nil or nil,id=id,priority=number(source.priority,0),restriction=number(source.restriction,0,4),minTurns=number(source.minTurns,0),maxTurns=number(source.maxTurns,0),stepsToRemove=number(source.stepsToRemove,0),removeByRestriction=source.removeByRestriction}
   if type(s.removeByRestriction)~='boolean'then shape('State removal flag required')end
   if 1.0+math.max(s.maxTurns-s.minTurns,0.0)>2147483647 then fail('E_BATTLER_NUMBER','State variance exceeds RNG range')end
   states[id]=s
  end
  if not states[1]then fail('E_BATTLER_REFERENCE','Death state 1 required')end
  return states
 end
 -- The private generated Actor catalog already contains validated lifecycle data.
 function M.fromCompiledCatalog(catalog)
  plain(catalog);local mv=catalog.profile=='mv-1.5.1'
  if catalog.kind~='r2u.actor-catalog' or catalog.schemaVersion~=1 or catalog.catalogVersion~=1 and catalog.catalogVersion~=2 or
   not mv and catalog.profile~='mz-1.10.0'then fail('E_BATTLER_PROFILE','Invalid compiled actor catalog ABI')end
  local states=catalog.statesById;plain(states)
  local function ref(id)number(id,1);if not states[id]then fail('E_BATTLER_REFERENCE','Missing state ID')end;return states[id]end
  local function sort(ids)table.sort(ids,function(a,b)local x,y=ref(a),ref(b);return x.priority~=y.priority and x.priority>y.priority or x.priority==y.priority and a<b end)end
  local function validate(state,kind)
   plain(state);if state.equipment~=nil then shape('Party alone owns equipment')end
   -- paySkillCost bypasses setters and may leave signed MP/TP. Refresh below
   -- owns normalization; validation must preserve the native pending state.
   number(state.hp,0);number(state.mp);number(state.tp)
   if state.visuImmortal~=nil and type(state.visuImmortal)~='boolean'then shape('Invalid sequence immortality')end
   dense(state.permanent,8);dense(state.buffs,8);dense(state.buffTurns,8)
   for i=1,8 do number(state.permanent[i]);number(state.buffs[i],-2,2);number(state.buffTurns[i],0)end
   dense(state.stateIds);local ids=copy(state.stateIds);local seen={};sort(ids)
   for i,id in ipairs(state.stateIds)do ref(id);if seen[id] or ids[i]~=id then shape('State IDs must be unique and priority ordered')end;seen[id]=true end
   local function counts(name,key)
    dense(state[name]);local found={};for _,r in ipairs(state[name])do fields(r,{stateId=true,[key]=true});ref(r.stateId);number(r[key],0);if found[r.stateId]then shape('Duplicate counter')end;found[r.stateId]=true end
    for _,id in ipairs(state.stateIds)do if not found[id]then shape('Missing active state counter')end end
   end
   counts('stateTurns','turns');if kind=='actor'then counts('stateSteps','steps')elseif state.stateSteps~=nil then shape('Enemy has no Actor state-step storage')end
  end
  local B={}
  function B.validateState(state,kind)
   if kind~='actor' and kind~='enemy'then shape('State kind must be Actor or Enemy')end
   validate(state,kind);return copy(state)
  end
  function B.apply(input,operation,adapter,rngState,context)
   plain(operation);local allowed=operations[operation.op]
   if not allowed then fail('E_BATTLER_UNSUPPORTED','Operation is not implemented')end
   local keys={op=true};for k in pairs(allowed)do keys[k]=true end;fields(operation,keys)
   for key in pairs(allowed)do if operation[key]==nil then shape('Required operation field missing')end end
   plain(adapter);if adapter.kind~='actor' and adapter.kind~='enemy'then fail('E_BATTLER_ADAPTER','Adapter kind must be Actor or Enemy')end
   for _,name in ipairs({'traits','stats','isAppeared','beforeRefresh'})do if type(adapter[name])~='function'then fail('E_BATTLER_ADAPTER','Required adapter method missing')end end
   local removed={}
   if context~=nil then
    if not mv then shape('Persistent removed-state context is MV-only')end
    fields(context,{removedStates=true});dense(context.removedStates);local seen={}
    for _,id in ipairs(context.removedStates)do ref(id);if seen[id]then shape('Duplicate persistent removed state')end;seen[id]=true;removed[#removed+1]=id end
   end
   validate(input,adapter.kind);local s=copy(input);local rng=RNG.restore(rngState)
   -- MV's native result carries this add-state gate through menu refreshes.
   -- This is its proven narrow projection, not a complete shared ActionResult.
   local result={hpAffected=false,hpDamage=0,mpDamage=0,tpDamage=0,addedStates={},removedStates=removed,addedBuffs={},addedDebuffs={},removedBuffs={}}
   local hooks={};local refreshCalls=0
   local function appeared()
    local v=adapter.isAppeared(s);if type(v)~='boolean'then fail('E_BATTLER_ADAPTER','isAppeared must return boolean')end;return v
   end
   local function query()
    local tr=adapter.traits(s);if type(tr)~='table' or type(tr.isStateResist)~='function' or type(tr.stateResistSet)~='function'then fail('E_BATTLER_ADAPTER','Invalid traits query')end;return tr
   end
   local function params()
    local stats=adapter.stats(s);plain(stats);dense(stats.params,8)
    for i,v in ipairs(stats.params)do number(v,i==1 and 1 or 0)end;return stats.params
   end
   local function alive()return appeared() and not has(s.stateIds,1)end
   local function restriction()local value=0;for _,id in ipairs(s.stateIds)do value=math.max(value,ref(id).restriction)end;return value end
   local function restricted()return appeared() and restriction()>0 end
   local function clearStates()s.stateIds={};s.stateTurns={};if adapter.kind=='actor'then s.stateSteps={}end end
   local function erase(id)
    for i=#s.stateIds,1,-1 do if s.stateIds[i]==id then table.remove(s.stateIds,i)end end
    for _,name in ipairs(adapter.kind=='actor' and {'stateTurns','stateSteps'} or {'stateTurns'})do for i=#s[name],1,-1 do if s[name][i].stateId==id then table.remove(s[name],i)end end end
   end
   local function count(name,key,id,value)
    for _,r in ipairs(s[name])do if r.stateId==id then r[key]=value;return end end;s[name][#s[name]+1]={stateId=id,[key]=value}
   end
   local refresh,addState,removeState
   function removeState(id)
    if has(s.stateIds,id)then if id==1 and s.hp==0 then s.hp=1.0 end;erase(id);refresh();push(result.removedStates,id)end
   end
   function addState(id)
    local def=ref(id)
    if alive() and not (id==1 and s.visuImmortal) and not query().isStateResist(id) and (not mv or not has(result.removedStates,id)) and not (def.removeByRestriction and restricted())then
     if not has(s.stateIds,id)then
      if id==1 then s.hp=0.0;clearStates();s.buffs=z();s.buffTurns=z()end
      local wasRestricted=restricted();s.stateIds[#s.stateIds+1]=id;sort(s.stateIds)
      if not wasRestricted and restricted()then
       if not mv then hooks[#hooks+1]={op='clearTpbChargeTime'}end;hooks[#hooks+1]={op='clearActions'}
       for _,key in ipairs(copy(s.stateIds))do if ref(key).removeByRestriction then removeState(key)end end
      end
      refresh()
     end
     local duration=number(def.minTurns+rng.nextInt(1.0+math.max(def.maxTurns-def.minTurns,0.0),'battler:state:'..string.format('%.0f',id)..':duration'),0)
     if def.visu then for _,old in ipairs(s.stateTurns)do if old.stateId==id then duration=math.max(duration,old.turns)end end;duration=math.min(99,duration)end
     count('stateTurns','turns',id,duration);if adapter.kind=='actor'then count('stateSteps','steps',id,def.stepsToRemove)end
     push(result.addedStates,id)
    end
   end
   function refresh()
    refreshCalls=refreshCalls+1;if refreshCalls>64 then fail('E_BATTLER_BUDGET','Refresh recursion exceeds supported budget')end
    adapter.beforeRefresh(s)
    local immune=query().stateResistSet();dense(immune);for _,id in ipairs(immune)do erase(id)end
    local p=params();s.hp=math.max(0.0,math.min(s.hp,p[1]));s.mp=math.max(0.0,math.min(s.mp,p[2]));s.tp=math.max(0.0,math.min(s.tp,100.0))
    if s.hp==0 then addState(1)else removeState(1)end
   end
   local op=operation.op
   if op=='refresh'then refresh()
   elseif op=='recoverAll'then clearStates();local p=params();s.hp,s.mp=p[1],p[2]
   elseif op=='gainHp' or op=='gainMp' or op=='gainTp' or op=='gainSilentTp'then
    local value=number(operation.value);local field=op=='gainHp' and 'hp' or op=='gainMp' and 'mp' or 'tp'
    if op=='gainHp'then result.hpAffected=true;result.hpDamage=-value elseif op=='gainMp'then result.mpDamage=-value elseif op=='gainTp'then result.tpDamage=-value end
    s[field]=number(s[field]*1.0+value);refresh()
   elseif op=='addParam'then local p=number(operation.paramId,0,7)+1;local value=number(operation.value);s.permanent[p]=number(s.permanent[p]*1.0+value);refresh()
   elseif op=='addState'then addState(number(operation.stateId,1))
   elseif op=='removeState'then local id=number(operation.stateId,1);ref(id);removeState(id)
   else
    local p=number(operation.paramId,0,7)+1
    if op=='removeBuff'then
     if alive() and s.buffs[p]~=0 then s.buffs[p]=0;s.buffTurns[p]=0;push(result.removedBuffs,p-1);refresh()end
    else
     local turns=number(operation.turns,0);if states[1].visu then turns=math.min(99,turns)end
     if alive()then
      local sign=op=='addBuff' and 1 or -1;s.buffs[p]=math.max(-2,math.min(2,s.buffs[p]+sign))
      if s.buffs[p]*sign>0 then s.buffTurns[p]=math.max(s.buffTurns[p],turns)end
      push(op=='addBuff' and result.addedBuffs or result.addedDebuffs,p-1);refresh()
     end
    end
   end
   return{state=s,result=result,hooks=hooks,rngState=rng.snapshot()}
  end
  return B
 end
 function M.new(definitions)
  local states=M.prepare(definitions)
  return M.fromCompiledCatalog({kind='r2u.actor-catalog',schemaVersion=1,catalogVersion=1,profile=definitions.profile,statesById=states})
 end
 return M
end
