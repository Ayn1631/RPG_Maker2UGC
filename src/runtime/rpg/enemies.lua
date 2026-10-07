-- Enemy instance authority for one battle. Battle owns queues and the RNG snapshot.
return function(deps)
 local Rules,Traits,Battler,Rng=deps['runtime.rpg.enemy_rules'],deps['runtime.rpg.traits'],deps['runtime.rpg.battler_state'],deps['runtime.core.rng']
 local M={};local SAFE=9007199254740991
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function shape(reason)fail('E_ENEMY_STATE_SHAPE',reason)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then shape('Expected plain enemy-state data')end end
 local function fields(v,allowed)plain(v);for k in next,v do if not allowed[k]then shape('Unknown enemy-state field')end end end
 local function num(v,lo,hi)
  if type(v)~='number' or v~=v or v%1~=0 or v<(lo or -SAFE) or v>(hi or SAFE)then fail('E_ENEMY_STATE_NUMBER','Expected finite safe integer')end;return v*1.0
 end
 local function dense(v,n)
  plain(v);local count,highest=0,0;for k in next,v do num(k,1,100000);count=count+1;highest=math.max(highest,k)end
  if count~=highest or n and count~=n then shape('Expected dense bounded array')end;return count
 end
 local function copy(v,seen,depth)
  local k=type(v);if k~='table'then
   if k=='number'then if v~=v or v==math.huge or v==-math.huge then shape('Nonfinite data')end
   elseif k~='nil' and k~='boolean' and k~='string'then shape('Executable value is not state data')end;return v
  end
  plain(v);seen=seen or {};depth=depth or 0;if seen[v] or depth>64 then shape('Cyclic or deeply nested data')end;seen[v]=true
  local out={};for key,x in next,v do if type(key)~='string' and type(key)~='number'then shape('Invalid data key')end;out[key]=copy(x,seen,depth+1)end;seen[v]=nil;return out
 end
 local function z()return{0,0,0,0,0,0,0,0}end
 local common={refresh=true,recoverAll=true,gainHp=true,gainMp=true,gainTp=true,gainSilentTp=true,addParam=true,addState=true,removeState=true,addBuff=true,addDebuff=true,removeBuff=true}
 local function rawOptions(options,compiled)
  fields(options,compiled and {battleId=true,troopId=true,state=true} or {profile=true,battleId=true,troopId=true,state=true})
  local battleId,troopId=options.battleId,num(options.troopId,1)
  if type(battleId)~='string' or #battleId<1 or #battleId>128 then shape('battleId must be a nonempty string of at most 128 bytes')end
  return battleId,troopId
 end
 local function validateTroop(troop,enemies)
  dense(troop.members);local out={id=troop.id,members={}}
  for i,m in ipairs(troop.members)do
   plain(m);num(m.enemyId,1);if not enemies[m.enemyId]then fail('E_ENEMY_STATE_REFERENCE','Missing enemy definition')end
   num(m.x);num(m.y);if type(m.hidden)~='boolean'then shape('Troop hidden flag must be boolean')end
   out.members[i]={enemyId=m.enemyId,x=m.x,y=m.y,hidden=m.hidden}
  end;return out
 end
 local function prepare(definitions,profile,selectedTroop)
  local catalog=Rules.prepare(definitions,profile);local rules=Rules.fromCompiledCatalog(catalog);local defs=copy(definitions)
  local enemies,states,troops={},{},{}
  for name,target in pairs({enemies=enemies,states=states,troops=troops})do
   dense(defs[name]);for _,r in ipairs(defs[name])do plain(r);num(r.id,1);if target[r.id]then fail('E_ENEMY_STATE_REFERENCE','Duplicate definition ID')end;target[r.id]=r end
  end
  for _,e in pairs(enemies)do if type(e.name)~='string'then shape('Enemy name must be a string')end end
  if selectedTroop then
   if not troops[selectedTroop]then fail('E_ENEMY_STATE_REFERENCE','Missing troop definition')end
   troops={[selectedTroop]=validateTroop(troops[selectedTroop],enemies)}
  else for id,troop in pairs(troops)do troops[id]=validateTroop(troop,enemies)end end
  local lifecycle=Battler.prepare({profile=profile,states=defs.states})
  local battler=Battler.fromCompiledCatalog({kind='r2u.actor-catalog',schemaVersion=1,catalogVersion=1,profile=profile,statesById=lifecycle})
  for id,state in pairs(lifecycle)do for key,value in pairs(state)do catalog.statesById[id][key]=value end end
  for id,enemy in pairs(enemies)do catalog.enemiesById[id].name=enemy.name;if enemy.visu then catalog.enemiesById[id].visu=copy(enemy.visu)end end
  catalog.kind='r2u.enemy-catalog';catalog.troopsById=troops
  return catalog,rules,battler
 end
 function M.prepare(definitions,profile)return prepare(definitions,profile)end
 local function instance(catalog,rules,battler,options,battleId,troopId)
  local profile=catalog.profile;local enemies,states=catalog.enemiesById,catalog.statesById
  local troop=catalog.troopsById[troopId];if not troop then fail('E_ENEMY_STATE_REFERENCE','Missing troop definition')end
  local function ref(slot)return{kind='enemy',battleId=battleId,troopSlot=slot}end
  local function context(s,paramsOnly)
   return{hidden=s.hidden,hp=paramsOnly and 0 or s.hp,mp=paramsOnly and 0 or s.mp,tp=paramsOnly and 0 or s.tp,stateIds=s.stateIds,permanent=s.permanent,buffs=s.buffs,visu=s.visu}
  end
  local function traits(s)
   local list={};for _,id in ipairs(s.stateIds)do list[#list+1]={traits=states[id].traits}end;list[#list+1]={traits=enemies[s.enemyId].traits};if s.visu then list[#list+1]={traits=s.visu.traits or {}}end;return Traits.new(list)
  end
  local adapter={kind='enemy',isAppeared=function(s)return not s.hidden end,beforeRefresh=function()end,traits=traits}
  -- Setter refresh can temporarily contain negative resources or TP > 100.
  -- Only params are consumed here; real resources stay on the evolving candidate.
  function adapter.stats(s)return{params=rules.stats(s.enemyId,context(s,true)).params}end
  local function validate(s,slot)
   fields(s,{troopSlot=true,enemyId=true,x=true,y=true,hidden=true,hp=true,mp=true,tp=true,permanent=true,buffs=true,buffTurns=true,stateIds=true,stateTurns=true,visuImmortal=true,visu=true})
   num(s.troopSlot,1);num(s.enemyId,1);num(s.x);num(s.y);num(s.tp,nil,100)
   if s.troopSlot~=slot or not enemies[s.enemyId] then fail('E_ENEMY_STATE_SNAPSHOT','Enemy snapshot does not match its source slot')end
   if type(s.hidden)~='boolean'then shape('Enemy hidden flag must be boolean')end
   local owned=battler.validateState(s,'enemy');rules.stats(owned.enemyId,context(owned));return owned
  end
  local data={}
  if options.state~=nil then
   local s=options.state;fields(s,{schemaVersion=true,profile=true,battleId=true,troopId=true,enemies=true})
   if s.schemaVersion~=1 or s.profile~=profile or s.battleId~=battleId or s.troopId~=troopId then fail('E_ENEMY_STATE_SNAPSHOT','Snapshot battle, troop, profile or schema mismatch')end
   dense(s.enemies,#troop.members);for slot,x in ipairs(s.enemies)do data[slot]=validate(x,slot)end
  else
   for slot,m in ipairs(troop.members)do
    local s={troopSlot=slot,enemyId=m.enemyId,x=m.x,y=m.y,hidden=m.hidden,hp=0,mp=0,tp=0,permanent=z(),buffs=z(),buffTurns=z(),stateIds={},stateTurns={}}
    if catalog.catalogVersion==2 then
     local resources=catalog.initialResourcesById[s.enemyId];s.hp,s.mp=resources.hp,resources.mp
    else local stats=rules.stats(s.enemyId,context(s));s.hp,s.mp=stats.params[1],stats.params[2]end
    data[slot]=s
   end
  end
  local function lookup(r)
   fields(r,{kind=true,battleId=true,troopSlot=true})
   if r.kind~='enemy' or r.battleId~=battleId or type(r.troopSlot)~='number' or not data[r.troopSlot]then fail('E_ENEMY_STATE_REFERENCE','Unknown or cross-battle enemy reference')end
   return r.troopSlot
  end
  local function displayName(s)local labels=s.visu and s.visu.traitLabels or {};local name=(labels.Variant or '')..' '..enemies[s.enemyId].name..(labels.Gender or '');return name:match('^%s*(.-)%s*$')end
  local function view(s)return{ref=ref(s.troopSlot),state=copy(s),originalName=displayName(s),stats=rules.stats(s.enemyId,context(s))}end
  local E={};local locked=false
  local function writable()if locked then fail('E_ENEMY_STATE_LOCKED','Live enemy writes are locked during an action candidate')end end
  function E.initializeVisu(rngState)
   writable();local rng=Rng.restore(rngState)
   local function pick(list,purpose)local sum=0;for _,v in ipairs(list)do sum=sum+v.weight end;if sum<=0 then shape('Invalid randomized trait weights')end;local roll=rng.nextUnit(purpose)*sum;for _,v in ipairs(list)do roll=roll-v.weight;if roll<0 then return v end end;return list[#list]end
   for slot,s in ipairs(data)do local def=enemies[s.enemyId];if def.visu and not s.visu then
    if def.visu.swapEnemies then local picked=pick(def.visu.swapEnemies,'visu.enemy.swap');s.enemyId=picked.id;def=enemies[s.enemyId]end
    local v={traits={},traitSets={},traitLabels=copy(def.visu and def.visu.traitLabels or {}),rewardExp=def.visu and def.visu.rewardExp or 1,rewardGold=def.visu and def.visu.rewardGold or 1,rewardDrop=def.visu and def.visu.rewardDrop or 1};s.visu=v
    if def.visu and def.visu['Sideview Battlers']then local names={};for name in def.visu['Sideview Battlers']:gmatch('[^\r\n]+')do name=name:match('^%s*(.-)%s*$');if name~=''then names[#names+1]=name end end;if #names==0 then shape('Empty sideview battler choice')end;v.sideviewBattler=names[rng.nextInt(#names,'visu.enemy.sideview')+1]end
    for _,group in ipairs(def.visu and def.visu.randomTraits or {})do local picked=pick(group.candidates,'visu.enemy.'..group.group);v.traitSets[group.group]=picked.name;v.traitLabels[group.group]=picked.visu.traitLabels[group.group];for _,tr in ipairs(picked.traits)do v.traits[#v.traits+1]=copy(tr)end;for _,k in ipairs({'rewardExp','rewardGold','rewardDrop'})do v[k]=v[k]*(picked.visu[k]or 1)end end
    if v.traitSets.Gender=='Male'and def.visu['Male Battler Hue']then v.battlerHue=tonumber(def.visu['Male Battler Hue'])end
    local stats=rules.stats(s.enemyId,context(s));s.hp,s.mp=stats.params[1],stats.params[2]
   end end;return rng.snapshot()
  end
  function E.snapshot()return{schemaVersion=1,profile=profile,battleId=battleId,troopId=troopId,enemies=copy(data)}end
  function E.getEnemy(r)return view(data[lookup(r)])end
  function E.command(r,operation,rngState)
   writable()
   local slot=lookup(r);plain(operation);local op=operation.op
   if not common[op] and op~='hide' and op~='appear' and op~='transform'then fail('E_ENEMY_STATE_UNSUPPORTED','Enemy operation is not implemented')end
   local prepared
   if op=='transform'then
    fields(operation,{op=true,enemyId=true});num(operation.enemyId,1);if not enemies[operation.enemyId]then fail('E_ENEMY_STATE_REFERENCE','Missing transform enemy')end
    local candidate=copy(data[slot]);candidate.enemyId=operation.enemyId;prepared=battler.apply(candidate,{op='refresh'},adapter,rngState)
   elseif op=='hide' or op=='appear'then
    fields(operation,{op=true});local candidate=copy(data[slot]);candidate.hidden=op=='hide'
    prepared={state=candidate,result=false,hooks={},rngState=Rng.restore(rngState).snapshot()}
   else prepared=battler.apply(data[slot],operation,adapter,rngState)end
   local candidate=validate(prepared.state,slot)
   local out={ok=true,enemy=view(candidate),result=prepared.result,hooks=prepared.hooks,rngState=prepared.rngState}
   data[slot]=candidate;return out
  end
  -- Queries detach data; their trait methods expose only the immutable trait
  -- snapshot. Candidate trait capabilities are revoked with their context.
  local function actionQuery(s,check)
   check();local stats=rules.stats(s.enemyId,context(s));local tr=traits(s);local wrapped={}
   for name,fn in pairs(tr)do wrapped[name]=function(...)check();return fn(...)end end
   local restriction=0;for _,id in ipairs(s.stateIds)do restriction=math.max(restriction,states[id].restriction)end
   local skills,seen={},{};for _,a in ipairs(enemies[s.enemyId].actions)do if not seen[a.skillId]then seen[a.skillId]=true;skills[#skills+1]=a.skillId end end
   -- Game_Enemy supplies no level property. Formula users of Enemy level
   -- must receive the existing missing-context diagnostic, not a made-up zero.
   local formula={hp=s.hp,mp=s.mp,tp=s.tp}
   for i,name in ipairs({'mhp','mmp','atk','def','mat','mdf','agi','luk'})do formula[name]=stats.params[i]end
   for i,name in ipairs({'hit','eva','cri','cev','mev','mrf','cnt','hrg','mrg','trg'})do formula[name]=stats.xparams[i]end
   for i,name in ipairs({'tgr','grd','rec','pha','mcr','tcr','pdr','mdr','fdr','exr'})do formula[name]=stats.sparams[i]end
   return{visu=copy(s.visu),absorbElements=copy(enemies[s.enemyId].visu and enemies[s.enemyId].visu.absorbElements or {}),kind='enemy',originalName=displayName(s),enemyId=s.enemyId,hidden=s.hidden,hp=s.hp,mp=s.mp,tp=s.tp,stateIds=copy(s.stateIds),stateTurns=copy(s.stateTurns),
    buffs=copy(s.buffs),buffTurns=copy(s.buffTurns),learnedSkills={},skills=skills,params=copy(stats.params),xparams=copy(stats.xparams),
    sparams=copy(stats.sparams),traits=wrapped,formula=formula,restriction=restriction,weaponTypes={},guard=tr.isGuard(not s.hidden and restriction<4)}
  end
  local function actionOutput(value,seen,depth,budget)
   if type(value)~='table'then return copy(value)end
   plain(value);seen=seen or {};depth=depth or 0;budget=budget or {left=100000}
   if seen[value]or depth>64 then shape('Cyclic or deeply nested action output')end
   seen[value]=true;local out={};for key,v in next,value do
    if type(key)=='number'then num(key)elseif type(key)~='string'then shape('Invalid action output key')end
    budget.left=budget.left-1;if budget.left<0 then shape('Action output budget exceeded')end
    out[key]=actionOutput(v,seen,depth+1,budget)
   end;seen[value]=nil;return out
  end
  function E.actionContext()
   return{query=function(r)return actionQuery(data[lookup(r)],function()end)end}
  end
  function E.actionTransaction(rngState,callback)
   writable();if type(callback)~='function'then shape('Action callback required')end
   local random=Rng.restore(rngState).snapshot();local all=copy(data);local active=true
   local function check()if not active then fail('E_ENEMY_STATE_CLOSED','Action candidate is closed')end end
   local function current(r)check();local slot=lookup(r);return all[slot],slot end
   local function advance(nextRng)
    local nextState=Rng.restore(nextRng).snapshot()
    if nextState.algorithm~=random.algorithm or nextState.draws<random.draws then fail('E_ENEMY_STATE_RNG','Action RNG moved backwards or changed algorithm')end
    if random.algorithm=='r2u-fixed-v1' then
     if #nextState.values~=#random.values then fail('E_ENEMY_STATE_RNG','Action fixed stream changed')end
     for i,value in ipairs(random.values)do if nextState.values[i]~=value then fail('E_ENEMY_STATE_RNG','Action fixed stream changed')end end
    else
     local distance=nextState.draws-random.draws;if distance>100000 then fail('E_ENEMY_STATE_RNG','Action RNG advance exceeds supported bound')end
     local expected=Rng.restore(random);for _=1,distance do expected.nextUnit('enemy:action:continuity')end
     if expected.snapshot().state~=nextState.state then fail('E_ENEMY_STATE_RNG','Action RNG stream changed')end
    end
    random=nextState;return copy(random)
   end
   local ctx={}
   function ctx.query(r)local s=current(r);return actionQuery(s,check)end
   function ctx.setVisuImmortal(r,value)if type(value)~='boolean'then shape('Immortality must be boolean')end;current(r).visuImmortal=value end
   function ctx.apply(r,operation,nextRng)
    local s,slot=current(r);local rng=advance(nextRng)
    local out=battler.apply(s,operation,adapter,rng);all[slot]=out.state;advance(out.rngState)
    return{result=copy(out.result),hooks=copy(out.hooks),rngState=copy(random)}
   end
   function ctx.transform(r,enemyId,nextRng)
    local s,slot=current(r);num(enemyId,1);if not enemies[enemyId]then fail('E_ENEMY_STATE_REFERENCE','Missing transform enemy')end
    local candidate=copy(s);candidate.enemyId=enemyId;local out=battler.apply(candidate,{op='refresh'},adapter,advance(nextRng));all[slot]=out.state;advance(out.rngState)
    return{result=copy(out.result),hooks=copy(out.hooks),rngState=copy(random)}
   end
   function ctx.selectActions(r,c,nextRng)
    local s=current(r);fields(c,{inBattle=true,turnCount=true,partyHighestLevel=true,switches=true});local input=copy(context(s));for k,v in pairs(c)do input[k]=copy(v)end
    local out=rules.selectActions(s.enemyId,input,advance(nextRng));advance(out.rngState);return copy(out)
   end
   function ctx.setTurns(r,turns)
    local s,slot=current(r);fields(turns,{stateTurns=true,buffTurns=true});local candidate=copy(s)
    candidate.stateTurns=copy(turns.stateTurns);candidate.buffTurns=copy(turns.buffTurns)
    all[slot]=validate(candidate,slot)
   end
   function ctx.appear(r)local s=current(r);s.hidden=false;return{hooks={{op='appear'}}}end
   function ctx.paySkillCost(r,mp,tp,nextRng,forcing)
    local s=current(r);num(mp,0);num(tp,0)
    if forcing~=nil and type(forcing)~='boolean'then shape('Forcing must be boolean')end
    if not forcing and (s.mp<mp or s.tp<tp)then fail('E_ENEMY_STATE_COST','Insufficient skill resources')end
    local nextMp,nextTp=num(s.mp*1.0-mp),num(s.tp*1.0-tp,nil,100)
    local rng=advance(nextRng);s.mp,s.tp=nextMp,nextTp;return rng
   end
   function ctx.escape(r,inBattle,nextRng)
    local s=current(r);if type(inBattle)~='boolean'then shape('Explicit inBattle required')end
    local rng=advance(nextRng);if inBattle then s.hidden=true end;s.stateIds={};s.stateTurns={}
    return{hooks={{op='clearActions'},{op='playEscape'}},rngState=rng}
   end
   locked=true;local ok,result=pcall(callback,ctx);active=false;locked=false
   if not ok then error(result,0)end
   plain(result);if type(result.ok)~='boolean'then shape('Action callback must return ok boolean')end
   if result.rngState~=nil then advance(result.rngState)end
   local out=actionOutput(result);out.rngState=copy(random)
   for slot,s in ipairs(all)do all[slot]=validate(s,slot)end
   if result.ok then data=all end;return out
  end
  -- Battle contributes only its own selection/reward inputs. Resource and
  -- trait authority remains this prepared Enemy instance.
  function E.selectActions(r,c,rngState)
   local s=data[lookup(r)];fields(c,{inBattle=true,turnCount=true,partyHighestLevel=true,switches=true})
   local input=copy(context(s));for key,v in next,c do input[key]=copy(v)end
   return copy(rules.selectActions(s.enemyId,input,rngState))
  end
  function E.rollDrops(r,c,rngState)
   local s=data[lookup(r)];local options=copy(c);options.visu=s.visu;return copy(rules.rollDrops(s.enemyId,options,rngState))
  end
  return E
 end
 function M.new(definitions,options)
  local battleId,troopId=rawOptions(options,false)
  local catalog,rules,battler=prepare(definitions,options.profile,troopId)
  return instance(catalog,rules,battler,options,battleId,troopId)
 end
 function M.fromCompiledCatalog(input)
  plain(input)
  if input.kind~='r2u.enemy-catalog' or input.schemaVersion~=1 or input.catalogVersion~=2 or (input.profile~='mz-1.10.0' and input.profile~='mv-1.5.1')then fail('E_ENEMY_PROFILE','Invalid compiled enemy catalog ABI')end
  local catalog=copy(input);plain(catalog.enemiesById);plain(catalog.statesById);plain(catalog.troopsById);plain(catalog.initialResourcesById)
  local rules=Rules.fromCompiledCatalog(catalog)
  -- Battler's current private ABI is shared with Actor; only lifecycle records
  -- are consumed. No raw state preparation occurs in this generated factory.
  local battler=Battler.fromCompiledCatalog({kind='r2u.actor-catalog',schemaVersion=1,catalogVersion=2,profile=catalog.profile,statesById=catalog.statesById})
  return {newEnemies=function(options)
   local battleId,troopId=rawOptions(options,true)
   return instance(catalog,rules,battler,options,battleId,troopId)
  end}
 end
 return M
end
