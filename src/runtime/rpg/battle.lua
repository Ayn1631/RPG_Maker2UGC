-- A prepared-factory MV turn / MZ turn and TPB coordinator. Each stage publishes all
-- authority roots together; candidate callbacks never receive a live root.
return function(deps)
 local RNG,Targets,Auto=deps['runtime.core.rng'],deps['runtime.rpg.battle_targets'],deps['runtime.rpg.auto_battle'];local M={}
 local SAFE=9007199254740991
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_BATTLE_SHAPE','Expected plain table')end end
 local function number(v,lo,hi)if type(v)~='number'or v~=v or v%1~=0 or v<(lo or 0)or v>(hi or SAFE)then fail('E_BATTLE_NUMBER','Expected supported integer')end;return v*1.0 end
 local function copy(v,seen,depth,budget)
  local kind=type(v);if kind~='table'then
   if kind=='number'and(v~=v or v==math.huge or v==-math.huge or v < -SAFE or v > SAFE)then fail('E_BATTLE_SHAPE','Nonfinite or unsupported state number')end
   if kind~='nil'and kind~='number'and kind~='boolean'and kind~='string'then fail('E_BATTLE_SHAPE','Executable state data')end;return v
  end
  plain(v);seen=seen or {};depth=depth or 0;budget=budget or {left=100000}
  if seen[v]or depth>64 then fail('E_BATTLE_SHAPE','Cyclic or deeply nested state')end;seen[v]=true;local out={}
  for k,x in next,v do if type(k)~='string'and type(k)~='number'then fail('E_BATTLE_SHAPE','Invalid state key')end
   budget.left=budget.left-1;if budget.left<0 then fail('E_BATTLE_BUDGET','State data budget exceeded')end;out[k]=copy(x,seen,depth+1,budget)
  end;seen[v]=nil;return out
 end
 local function dense(v,max)plain(v);local n,high=0,0;for k in next,v do number(k,1,max or 10000);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_BATTLE_SHAPE','Expected dense array')end;return n end
 local function has(list,value)for _,v in ipairs(list)do if v==value then return true end end;return false end
 local function directClassSkill(q,id)for _,command in ipairs(q.visuBattleCommands or {})do if command.command=='skill_direct'and command.id==id then return true end end;return false end
 local function key(r)return r.kind=='actor'and('actor:'..string.format('%.0f',r.id))or('enemy:'..r.battleId..':'..string.format('%.0f',r.troopSlot))end
 local function same(a,b)return a and b and key(a)==key(b)end
 local function dead(q)return has(q.stateIds,1)end
 local function movable(q)return not q.hidden and q.restriction<4 end
 local phases={start=true,input=true,turn=true,action=true,turnEnd=true,battleEnd=true,aborting=true}
 function M.new(o)
  plain(o);for _,field in ipairs({'actorProgram','partyProgram','enemyProgram','actions','lifecycle'})do plain(o[field])end
  for _,name in ipairs({'canEscape','canLose','preemptive','surprise','visuAlwaysEscape'})do if o[name]~=nil and type(o[name])~='boolean'then fail('E_BATTLE_SHAPE','Expected boolean '..name)end end
  if type(o.battleId)~='string'or #o.battleId<1 or #o.battleId>128 then fail('E_BATTLE_REFERENCE','Invalid battle ID')end
  number(o.troopId,1);local maxMembers=number(o.maxBattleMembers or 4,1,1000)
  local AP,PP,EP,Actions,Life=o.actorProgram,o.partyProgram,o.enemyProgram,o.actions,o.lifecycle
  local profile=o.profile or 'mz-1.10.0';local mv=profile=='mv-1.5.1';if not mv and profile~='mz-1.10.0'then fail('E_BATTLE_PROFILE','Unsupported battle profile')end
  local battleSystem=number(o.battleSystem or 0,0,2);if mv and battleSystem~=0 then fail('E_BATTLE_PROFILE','MV has no TPB battle system')end
  local tpb=battleSystem>0
  local function mainPhase(phase)return phase=='turn'or phase=='action'or phase=='turnEnd'end
  if type(AP.newActors)~='function'or type(PP.newParty)~='function'or type(EP.newEnemies)~='function'then fail('E_BATTLE_CAPABILITY','Prepared factories required')end
  for _,name in ipairs({'describe','canUse','pay','applyPreparedTarget','applyGlobal'})do if type(Actions[name])~='function'then fail('E_BATTLE_CAPABILITY','Missing prepared action '..name)end end
  if type(Life.apply)~='function'then fail('E_BATTLE_CAPABILITY','Prepared lifecycle required')end
  local restored=o.state and copy(o.state);local state
  if restored then
   if restored.schemaVersion~=1 or restored.profile~=profile or (restored.battleSystem or 0)~=battleSystem or restored.battleId~=o.battleId or restored.troopId~=o.troopId then fail('E_BATTLE_SNAPSHOT','Battle snapshot identity mismatch')end
   state=restored.state;plain(state);if not phases[state.phase]then fail('E_BATTLE_SNAPSHOT','Unknown phase')end
   number(state.revision);number(state.turnCount);number(state.sequence);plain(state.hidden);plain(state.slots);dense(state.order);dense(state.inputs);dense(state.targets)
  else state={phase='start',revision=0,turnCount=0,sequence=0,hidden={},slots={},order={},inputs={},inputIndex=1,targets={},subject=false,current=false,reflectionTarget=false,preemptive=o.preemptive or false,surprise=o.surprise or false,escapeRatio=0,settled=false,outcome=false}end
  local random=RNG.restore(restored and restored.rngState or o.rngState).snapshot()
  local party=PP.newParty({state=restored and restored.partyState or o.partyState})
  local actors=AP.newActors(party,{state=restored and restored.actorsState or o.actorsState})
  local enemies=EP.newEnemies({battleId=o.battleId,troopId=o.troopId,state=restored and restored.enemiesState or o.enemiesState})
  if not restored and enemies.initializeVisu then random=enemies.initializeVisu(random)end
  local switches,variables=copy(restored and restored.switches or o.switches or {}),copy(restored and restored.variables or o.variables or {})
  if not restored then
   local counts,letters={},{};state.enemyNames={};local full={'Ａ','Ｂ','Ｃ','Ｄ','Ｅ','Ｆ','Ｇ','Ｈ','Ｉ','Ｊ','Ｋ','Ｌ','Ｍ','Ｎ','Ｏ','Ｐ','Ｑ','Ｒ','Ｓ','Ｔ','Ｕ','Ｖ','Ｗ','Ｘ','Ｙ','Ｚ'}
   for _,row in ipairs(enemies.snapshot().enemies)do local r={kind='enemy',battleId=o.battleId,troopSlot=row.troopSlot};local v=enemies.getEnemy(r);local name=v.originalName
    if not row.hidden and not has(row.stateIds,1)then local n=counts[name]or 0;letters[row.troopSlot]=o.isCJK and full[n%26+1]or(' '..string.char(65+n%26));counts[name]=n+1 end
   end
   for _,row in ipairs(enemies.snapshot().enemies)do local r={kind='enemy',battleId=o.battleId,troopSlot=row.troopSlot};local name=enemies.getEnemy(r).originalName;state.enemyNames[key(r)]=name..((counts[name]or 0)>=2 and(letters[row.troopSlot]or '')or '')end
   state.enemyNameCounts=counts;state.enemyLetters=letters
  end
  state.forced=state.forced or false;state.lastTarget=state.lastTarget or {};state.tpb=state.tpb or {};state.forcedTurn=state.forcedTurn or false
  state.lastActionData=state.lastActionData or copy(o.lastActionData or {0,0,0,0,0,0})
  if dense(state.lastActionData,6)~=6 then fail('E_BATTLE_SHAPE','Last action data requires six entries')end
  for _,value in ipairs(state.lastActionData)do number(value,0)end
  local busy=false;local cached;local latest={};local B={}
  local tpbClockModel;local endUnchanged=false
  local function actorRefs(p,s)local out={};s=s or state;for i,id in ipairs(p.members())do if i>maxMembers then break end;local r={kind='actor',id=id};if not s.hidden[key(r)]then out[#out+1]=r end end;return out end
  local function enemyRefs(e)local out={};for _,row in ipairs(e.snapshot().enemies)do out[#out+1]={kind='enemy',battleId=o.battleId,troopSlot=row.troopSlot}end;return out end
  local function refs(p,e,s)local out=actorRefs(p,s);for _,r in ipairs(enemyRefs(e))do out[#out+1]=r end;return out end
  local function reference(r,p,e)
   plain(r);if r.kind=='actor'then number(r.id,1);if not actors.hasActor(r.id)then fail('E_BATTLE_REFERENCE','Unknown database Actor')end
   elseif r.kind=='enemy'then if r.battleId~=o.battleId then fail('E_BATTLE_REFERENCE','Cross-battle enemy')end;number(r.troopSlot,1);e.getEnemy(r)
   else fail('E_BATTLE_REFERENCE','Invalid battler reference')end;return r
  end
  if restored then
   plain(state.lastTarget);plain(state.enemyNameCounts);plain(state.enemyLetters);plain(state.tpb)
   if type(state.forcedTurn)~='boolean'then fail('E_BATTLE_SNAPSHOT','Invalid forced-turn flag')end
   if tpb then for _,r in ipairs(refs(party,enemies,state))do
    local t=state.tpb[key(r)];plain(t);if not ({charging=true,charged=true,casting=true,ready=true,acting=true})[t.state]or type(t.turnEnd)~='boolean'then fail('E_BATTLE_SNAPSHOT','Invalid TPB state')end
    number(t.turnCount);for _,field in ipairs({'chargeTime','castTime','idleTime'})do local v=t[field];if type(v)~='number'or v~=v or v < (field=='chargeTime'and -SAFE or 0)or v>SAFE then fail('E_BATTLE_SNAPSHOT','Invalid TPB time')end end
   end end
   if state.forced~=false then reference(state.forced,party,enemies)end
   for k,v in pairs(state.lastTarget)do if type(k)~='string'then fail('E_BATTLE_SNAPSHOT','Invalid last-target key')end;number(v,-1,10000)end
  end
  local function context(ac,ec,s,p,e)
   if o.damagePolicy~=nil and type(o.damagePolicy)~='function'then fail('E_BATTLE_SHAPE','Expected damage policy function')end
   local ctx={gold=ac.gold,count=ac.count,members=ac.members,consumeItem=ac.consumeItem,learnSkill=ac.learnSkill,gainGold=ac.gainGold,gainItem=ac.gainItem,gainBattleExp=ac.gainBattleExp,actorCommand=ac.actorCommand,eventEquip=ac.eventEquip,progression=ac.progression,partyMember=ac.partyMember,canEscape=function()return o.canEscape or false end}
   function ctx.setVisuImmortal(r,value)return(r.kind=='actor'and ac or ec).setVisuImmortal(r,value)end
   ctx.damagePolicy=o.damagePolicy
   function ctx.isBattleMember(r)reference(r,p,e);if r.kind=='enemy'then return true end;for _,x in ipairs(actorRefs({members=ac.members},s))do if same(r,x)then return true end end;return false end
   function ctx.query(r)
    reference(r,p,e);local q=(r.kind=='actor'and ac or ec).query(r)
    if r.kind=='actor'then q.hidden=s.hidden[key(r)]or false;q.guard=q.traits.isGuard(movable(q))end;return q
   end
   local function hooks(r,list)for _,h in ipairs(list or {})do if h.op=='clearActions'then s.slots[key(r)]={}elseif tpb and h.op=='clearTpbChargeTime'and s.tpb[key(r)]then s.tpb[key(r)].state='charging';s.tpb[key(r)].chargeTime=0 end end end
   function ctx.apply(r,op,rng)local out=(r.kind=='actor'and ac or ec).apply(r,op,rng);hooks(r,out.hooks);return out end
   function ctx.transformEnemy(r,id,rng)local out=ec.transform(r,id,rng);hooks(r,out.hooks);return out end
   function ctx.selectEnemyActions(r,c,rng)return ec.selectActions(r,c,rng)end
   function ctx.paySkillCost(r,...)return(r.kind=='actor'and ac or ec).paySkillCost(r,...)end
   function ctx.setTurns(r,...)return(r.kind=='actor'and ac or ec).setTurns(r,...)end
   function ctx.appear(r)if r.kind=='actor'then s.hidden[key(r)]=nil end;return(r.kind=='actor'and ac or ec).appear(r)end
   function ctx.escape(r,inBattle,rng)
    if r.kind=='actor'then if inBattle then s.hidden[key(r)]=true end;local out=ac.escape(r,false,rng);hooks(r,out.hooks);return out end
    local out=ec.escape(r,inBattle,rng);hooks(r,out.hooks);return out
   end
   return ctx
  end
  local function uniqueEnemyNames(s,ctx,e)
   local counts,letters=s.enemyNameCounts,s.enemyLetters;plain(counts);plain(letters)
   local full={'Ａ','Ｂ','Ｃ','Ｄ','Ｅ','Ｆ','Ｇ','Ｈ','Ｉ','Ｊ','Ｋ','Ｌ','Ｍ','Ｎ','Ｏ','Ｐ','Ｑ','Ｒ','Ｓ','Ｔ','Ｕ','Ｖ','Ｗ','Ｘ','Ｙ','Ｚ'}
   for _,r in ipairs(enemyRefs(e))do local q=ctx.query(r);local name=ctx.query(r).originalName
    if not q.hidden and not dead(q)and not letters[r.troopSlot]then local n=counts[name]or 0;letters[r.troopSlot]=o.isCJK and full[n%26+1]or(' '..string.char(65+n%26));counts[name]=n+1 end
   end
   for _,r in ipairs(enemyRefs(e))do local name=ctx.query(r).originalName;s.enemyNames[key(r)]=name..((counts[name]or 0)>=2 and(letters[r.troopSlot]or '')or '')end
  end
  local function readContext(s,p,a,e)return context(a.actionContext(),e.actionContext(),s,p,e)end
  local function unitSnapshots(ctx,s,p,e,withActions)
   local out={};for side,list in ipairs({actorRefs(p,s),enemyRefs(e)})do out[side]={};for _,r in ipairs(list)do local q=ctx.query(r)
    local entry={ref=copy(r),hidden=q.hidden,dead=dead(q),tgr=q.sparams[1],agi=q.params[7],attackSpeed=q.traits.attackSpeed(),attackTimesAdd=q.traits.attackTimesAdd(),confusionLevel=q.restriction>=1 and q.restriction<=3 and q.restriction or 0}
    if withActions then entry.actions={};for _,a in ipairs(s.slots[key(r)]or {})do
     if a==false then entry.actions[#entry.actions+1]={speed=0,isAttack=false,itemPresent=false}
     else local meta=Actions.describe(a.actionRef);entry.actions[#entry.actions+1]={speed=meta.speed,isAttack=a.isAttack,itemPresent=true}end
    end end;out[side][#out[side]+1]=entry
   end end;return out[1],out[2]
  end
  local function record(s,rows,kind,data)s.sequence=s.sequence+1;local row=copy(data or {});row.kind=kind;row.sequence=s.sequence;row.revision=s.revision+1;rows[#rows+1]=row end
  local function collapse(s,rows,r,ctx)
   local q=ctx.query(r);record(s,rows,'collapse',{targetRef=r,targetCollapseType=q.traits.collapseType(),targetEnemyId=q.enemyId})
  end
  local function lifecycle(phase,r,ctx,s,rng,rows,extra)
   local req={phase=phase,ref=r,rngState=rng};if mv and phase=='turnEnd'then req.forcedTurn=s.forcedTurn end;for k,v in pairs(extra or {})do req[k]=v end
   local out=Life.apply(req,ctx);if not out.ok then fail('E_BATTLE_LIFECYCLE','Lifecycle rejected stage')end
   if tpb and out.sourceTpb then s.tpb[key(r)]=copy(out.sourceTpb);s.tpb[key(r)].castTime=0 end
   for _,h in ipairs(out.hooks or {})do if h.op=='clearActions'then s.slots[key(r)]={}elseif tpb and h.op=='clearTpbChargeTime'and s.tpb[key(r)]then s.tpb[key(r)].state='charging';s.tpb[key(r)].chargeTime=0 end end
   record(s,rows,'lifecycle',{phase=phase,battlerRef=r,hooks=out.hooks,result=out.result,sourceTpb=out.sourceTpb})
   if phase=='turnEnd' or phase=='actionsEnd'then
    for _,id in ipairs(out.result.addedStates or {})do if id==1 then collapse(s,rows,r,ctx)end end
   end
   return out.rngState
  end
  local function transact(fn)
   if busy then fail('E_BATTLE_REENTRY','Battle operation is not reentrant')end;busy=true
   local ok,value=pcall(function()
    local s=copy(state);local p=PP.newParty({state=party.snapshot()});local a=AP.newActors(p,{state=actors.snapshot()});local e=EP.newEnemies({battleId=o.battleId,troopId=o.troopId,state=enemies.snapshot()});local rows={}
    local out=a.actionTransaction(random,function(ac)return e.actionTransaction(random,function(ec)
     local ctx=context(ac,ec,s,p,e);local nextRng=fn(s,ctx,p,a,e,copy(random),rows)
     return{ok=true,rngState=nextRng}
    end)end)
    -- Validate every detached output before publishing any authority root.
    local nextState=copy(s);local nextRng=RNG.restore(out.rngState).snapshot();local nextRows=copy(rows)
    nextState.revision=nextState.revision+1
    number(nextState.revision)
    a.snapshot();p.snapshot();e.snapshot()
    state,random,party,actors,enemies,latest,cached=nextState,nextRng,p,a,e,nextRows,nil
    tpbClockModel=nil;endUnchanged=false
    return{ok=true,records=copy(nextRows)}
   end);busy=false;if not ok then error(value,0)end;return value
  end
  local function startTurn(s,ctx,p,e,rng,rows)
   s.turnCount=s.turnCount+1;s.phase='turn';s.subject=false;s.current=false;s.targets={};s.inputs={}
   local ps,ts=unitSnapshots(ctx,s,p,e,true);local out=Targets.makeActionOrders({battleId=o.battleId,party=ps,troop=ts,preemptive=s.preemptive,surprise=s.surprise,rngState=rng,allowRandomSpeed=not o.visuGameplay})
   s.order=out.order;record(s,rows,'turnStart',{turnCount=s.turnCount,order=out.order,speeds=out.speeds});return out.rngState
  end
  local function input(s,ctx,p,a,e,rng,rows)
   s.phase='input';s.slots={};s.inputs={};s.inputIndex=1;local rr=RNG.restore(rng)
   for _,r in ipairs(actorRefs(p,s))do local q=ctx.query(r);local slots={};s.slots[key(r)]=slots
    if movable(q)then
     local count=1;for _,chance in ipairs(q.traits.actionPlusSet())do if rr.nextUnit('battle.actor.actionPlus')<chance then count=count+1 end end
     if count>1000 then fail('E_BATTLE_BUDGET','Actor action count exceeds stage budget')end
     if q.traits.isAutoBattle()then
      local automatic=Auto.select({battleId=o.battleId,subjectRef=r,actionCount=count,partyRefs=actorRefs(p,s),troopRefs=enemyRefs(e),rngState=rr.snapshot(),variables=variables},ctx,Actions)
      s.slots[key(r)]=automatic.actionSlots;rr=RNG.restore(automatic.rngState)
     else for slot=1,count do
      if q.restriction>0 then slots[slot]={actionRef={kind='skill',id=q.traits.attackSkillId()},targetIndex=-1,isAttack=true,forcing=false}
      else slots[slot]=false;s.inputs[#s.inputs+1]={actorRef=copy(r),actionSlot=slot}end
     end end
    end
   end
   rng=rr.snapshot();local highest=0;for _,r in ipairs(actorRefs(p,s))do highest=math.max(highest,a.getActor(r.id).state.level)end
   for _,r in ipairs(enemyRefs(e))do local ai=e.selectActions(r,{inBattle=true,turnCount=s.turnCount+1,partyHighestLevel=highest,switches=switches},rng);rng=ai.rngState;s.slots[key(r)]={}
    for i,slot in ipairs(ai.actionSlots)do s.slots[key(r)][i]=slot and {actionRef={kind='skill',id=slot.skillId},targetIndex=-1,isAttack=slot.skillId==ctx.query(r).traits.attackSkillId(),forcing=false}or false end
   end
   record(s,rows,'inputStart',{slots=s.inputs})
   if s.surprise or #s.inputs==0 then return startTurn(s,ctx,p,e,rng,rows)end;return rng
  end
  local function removeBattleStates(ctx,p,rng,s,rows)
   if type(Life.removeBattleStates)~='function'then fail('E_BATTLE_CAPABILITY','Missing reward-order battle state removal')end
   for _,r in ipairs(actorRefs(p,s))do local out=Life.removeBattleStates({ref=r,rngState=rng},ctx);if not out.ok then fail('E_BATTLE_LIFECYCLE','Battle state removal failed')end;rng=out.rngState;record(s,rows,'battleStatesRemoved',{battlerRef=r,hooks=out.hooks})end;return rng
  end
  local function finish(s,ctx,p,a,e,rng,rows,code)
   if s.settled then fail('E_BATTLE_SETTLED','Battle rewards already settled')end
   local rewards={exp=0,gold=0,items={},actors={}}
   if code==0 or code==1 then rng=removeBattleStates(ctx,p,rng,s,rows)end
   if code==0 then
    local doubleGold,doubleDrop=false,false;for _,r in ipairs(actorRefs(p,s))do local q=ctx.query(r);if not q.hidden then doubleGold=doubleGold or q.traits.partyAbility(4);doubleDrop=doubleDrop or q.traits.partyAbility(5)end end
    for _,r in ipairs(enemyRefs(e))do if dead(ctx.query(r))then local drops=e.rollDrops(r,{dropItemDouble=doubleDrop},rng);rng=drops.rngState;rewards.exp=rewards.exp+drops.baseExp;rewards.gold=rewards.gold+drops.baseGold;for _,v in ipairs(drops.items)do rewards.items[#rewards.items+1]={kind=v.kind,id=v.id}end end end
    if doubleGold then rewards.gold=rewards.gold*2 end
    -- Party and Actor reward capabilities mutate the same nested candidate.
    if type(ctx.gainGold)~='function'or type(ctx.gainItem)~='function'or type(ctx.gainBattleExp)~='function'then fail('E_BATTLE_CAPABILITY','Missing atomic reward capabilities')end
    for _,id in ipairs(p.members())do local r={kind='actor',id=id};local out=ctx.gainBattleExp(r,rewards.exp,{isBattleMember=ctx.isBattleMember(r),optExtraExp=o.optExtraExp~=false},rng);rng=out.rngState;rewards.actors[#rewards.actors+1]=out end
    ctx.gainGold(rewards.gold);for _,v in ipairs(rewards.items)do ctx.gainItem(v.kind,v.id,1)end
   end
   if code==2 and o.canLose then for _,r in ipairs(actorRefs(p,s))do local q=ctx.query(r);if dead(q)then local x=ctx.apply(r,{op='gainHp',value=1-q.hp},rng);rng=x.rngState end end end
   -- Scene termination invokes Party.onBattleEnd for all members; Troop has
   -- no onBattleEnd call in the source scene termination path.
   for _,id in ipairs(p.members())do rng=lifecycle('battleEnd',{kind='actor',id=id},ctx,s,rng,rows)end
   s.phase='battleEnd';s.settled=true;s.subject=false;s.current=false;s.targets={};s.order={};s.inputs={}
   s.forced=false
   s.outcome={code=code,rewards=rewards,escaped=code==1 and not s.aborted,aborted=s.aborted==true,gameover=code==2 and not o.canLose or false}
   record(s,rows,'battleEnd',s.outcome);return rng
  end
  local function endCode(s,ctx,p,e)
   if mv and #p.members()==0 then return 1 end
   local ps=actorRefs(p,s);local appeared,alive=0,0;for _,r in ipairs(ps)do local q=ctx.query(r);if not q.hidden then appeared=appeared+1;if not dead(q)then alive=alive+1 end end end
   if alive==0 then local escaped=false;for i,id in ipairs(p.members())do if i>maxMembers then break end;escaped=escaped or s.hidden[key({kind='actor',id=id})]or false end
    return escaped and 1 or 2
   end
   local enemyAlive=0;for _,r in ipairs(enemyRefs(e))do local q=ctx.query(r);if not q.hidden and not dead(q)then enemyAlive=enemyAlive+1 end end
   if enemyAlive==0 then return 0 end;return nil
  end
  local function checkEnd(s,ctx,p,a,e,rng,rows)
   local code=endCode(s,ctx,p,e);if code~=nil then return finish(s,ctx,p,a,e,rng,rows,code),true end;return rng,false
  end
  local function invoke(s,ctx,p,e,rng,rows,target)
   local subject=s.subject;local q=ctx.query(target);local meta=Actions.describe(s.current.actionRef);local rr=RNG.restore(rng)
   local counter=rr.nextUnit('battle.invoke.counter')<(meta.hitType==1 and movable(q)and q.xparams[7]or 0)
   local reflection=false;if not counter then reflection=rr.nextUnit('battle.invoke.reflection')<(meta.hitType==2 and q.xparams[6]or 0)end
   local actionRef,from,to,reaction=s.current.actionRef,subject,target,'normal'
   if counter then reaction='counter';from=target;to=subject;actionRef={kind='skill',id=q.traits.attackSkillId()}
   elseif reflection then reaction='reflection';s.reflectionTarget=copy(target);to=subject
   elseif meta.hitType~=0 and not q.hidden and not dead(q)and q.hp<q.params[1]/4 then
    local unit=target.kind=='actor'and actorRefs(p,s)or enemyRefs(e)
    for _,r in ipairs(unit)do local x=ctx.query(r);if not same(r,target)and x.traits.isSubstitute(movable(x))then to=r;reaction='substitute';break end end
   end
   local req={actionRef=actionRef,subjectRef=from,targetRef=to,inBattle=true,rngState=rr.snapshot(),variables=variables}
   if s.visuSequence and not counter then req.forcedElements=s.visuSequence.elements end
   if not counter and s.reflectionTarget then req.reflectionTargetRef=s.reflectionTarget end
   local out=Actions.applyPreparedTarget(req,ctx);if not out.ok then fail('E_BATTLE_ACTION','Target application failed')end
   if not mv then s.lastActionData[to.kind=='actor' and 5 or 6]=to.kind=='actor' and to.id or to.troopSlot end
   local unit=target.kind=='actor'and actorRefs(p,s)or enemyRefs(e);local index=-1;for i,r in ipairs(unit)do if same(r,target)then index=i-1;break end end;s.lastTarget[key(subject)]=index
   local after=ctx.query(to)
   record(s,rows,'actionResult',{actionRef=actionRef,subjectRef=reflection and target or from,formulaSubjectRef=from,targetRef=to,originalTargetRef=target,reaction=reaction,result=out.result,hooks=out.hooks,
    targetDead=dead(after),targetCollapseType=after.traits.collapseType(),targetEnemyId=after.enemyId});return out.rngState
  end
  local function subjectSnapshot(r,ctx)
   local q=ctx.query(r);return{ref=copy(r),hidden=q.hidden,dead=dead(q),tgr=q.sparams[1],agi=q.params[7],attackSpeed=q.traits.attackSpeed(),attackTimesAdd=q.traits.attackTimesAdd(),confusionLevel=q.restriction>=1 and q.restriction<=3 and q.restriction or 0}
  end
  local function startAction(s,ctx,p,e,rng,rows,r,current)
   local meta=Actions.describe(current.actionRef);local ps,ts=unitSnapshots(ctx,s,p,e,false)
   local request={battleId=o.battleId,subject=r,party=ps,troop=ts,action={scope=meta.scope,repeats=meta.repeats,isAttack=current.isAttack,targetIndex=current.targetIndex,forcing=current.forcing},rngState=rng}
   if current.forcing and r.kind=='actor'and not ctx.isBattleMember(r)then request.subjectSnapshot=subjectSnapshot(r,ctx)end
   local out=Targets.makeTargets(request);rng=out.rngState
   local paid=Actions.pay({actionRef=current.actionRef,subjectRef=r,inBattle=true,rngState=rng,forcing=current.forcing},ctx);if not paid.ok then fail('E_BATTLE_ACTION','Prepared action payment failed')end;rng=paid.rngState
   local globals={};for _,v in ipairs(Actions.applyGlobal(current.actionRef))do globals[#globals+1]=v.commonEventId end
   if not mv then
    s.lastActionData[current.actionRef.kind=='skill' and 1 or 2]=current.actionRef.id
    s.lastActionData[r.kind=='actor' and 3 or 4]=r.kind=='actor' and r.id or r.troopSlot
   end
   local animations={};local animationId=meta.animationId or 0
   if animationId<0 and r.kind=='actor'then
    for i,id in ipairs(ctx.query(r).attackAnimations or {})do if id>0 then animations[#animations+1]={id=id,mirror=i==2}end end
   elseif animationId>0 then animations[1]={id=animationId,mirror=false}end
   s.visuSequence=meta.visuSequence and {pc=1,targets=copy(out.targets),wait=0,immortal={}}or nil
   s.current=current;s.targets=out.targets;s.reflectionTarget=false;s.phase='action';record(s,rows,'actionStart',{subjectRef=r,actionRef=current.actionRef,actionName=meta.name,animationId=animationId,animations=animations,enemyAttack=animationId<0 and r.kind=='enemy',targets=out.targets,cost=paid.cost,commonEvents=globals,visuSequence=s.visuSequence~=nil});return rng
  end
  -- Each sequence step executes inside the same candidate transaction as native
  -- actions. Target multiplicity is preserved; presentation never applies damage.
  local function sequenceStep(s,ctx,p,e,rng,rows,clock)
   local seq=s.visuSequence
   if seq.wait>0 then seq.wait=math.max(0,seq.wait-(clock.frames or 1));return rng,false end
   local function targets(names,unique)
    local list,seen={},{};local function add(r)if r and(not unique or not seen[key(r)])then list[#list+1]=r;seen[key(r)]=true end end
    for _,name in ipairs(names or {})do
     if name=='user'then add(s.subject)
     elseif name=='all targets'then for _,r in ipairs(seq.targets)do add(r)end
     elseif name=='current target'then add(seq.targets[1])
     elseif name=='not focus'then for _,r in ipairs(refs(p,e,s))do local focus=same(r,s.subject);for _,t in ipairs(seq.targets)do focus=focus or same(r,t)end;if not focus then add(r)end end
     else fail('E_VISU_TARGET','Unsupported target selector '..tostring(name))end
    end;return list
   end
   local function immortal(list,value)
    for _,r in ipairs(list)do ctx.setVisuImmortal(r,value);seq.immortal[key(r)]=value and copy(r)or nil
     if not value then local out=ctx.apply(r,{op='refresh'},rng);rng=out.rngState;if dead(ctx.query(r))then collapse(s,rows,r,ctx)end end
    end
   end
   local instruction=Actions.visuSequenceStep(s.current.actionRef,seq.pc)
   if not instruction then local all={};for _,r in pairs(seq.immortal)do all[#all+1]=r end;immortal(all,false);s.visuSequence=nil;s.targets={};return rng,true end
   seq.pc=seq.pc+1;local cmd,args=instruction.command,instruction.args
   if cmd=='wait'then seq.wait=number(args.frames,0)
   elseif cmd=='ActSeq_Set_SetupAction'then if args.ApplyImmortal then local list=targets({'user','all targets'},true);immortal(list,true)end
   elseif cmd=='ActSeq_Set_FinishAction'then if args.ApplyImmortal then immortal(targets({'user','all targets'},true),false)end
   elseif cmd=='ActSeq_Mechanics_Immortal'then immortal(targets(args.Targets,true),args.Immortal)
   elseif cmd=='ActSeq_Mechanics_ActionEffect'then
    for _,r in ipairs(targets(args.Targets,false))do rng=invoke(s,ctx,p,e,rng,rows,r)end
   elseif cmd=='ActSeq_Element_ForceElements'then seq.elements=copy(args.Elements)
   elseif cmd=='ActSeq_Element_Clear'then seq.elements=nil
   elseif cmd=='ActSeq_Mechanics_HpMpTp'then
    for _,r in ipairs(targets(args.Targets,true))do local q=ctx.query(r);for i,name in ipairs({'HP','MP','TP'})do local amount=math.floor((args[name..'_Rate']or 0)*(i<3 and q.params[i]or 100)+(args[name..'_Flat']or 0));if amount~=0 then
     local out=ctx.apply(r,{op=({'gainHp','gainMp','gainTp'})[i],value=amount},rng);rng=out.rngState;record(s,rows,'visuResource',{targetRef=r,resource=name,amount=amount,result=out.result,showPopup=args.ShowPopup})
    end end end
   elseif cmd=='ActSeq_Mechanics_AddBuffDebuff'then
    local ids={MHP=0,MMP=1,ATK=2,DEF=3,MAT=4,MDF=5,AGI=6,LUK=7}
    for _,r in ipairs(targets(args.Targets,true))do for _,field in ipairs({'Buffs','Debuffs'})do for _,name in ipairs(args[field])do local id=ids[name];if not id then fail('E_VISU_BUFF','Unknown buff parameter')end;local out=ctx.apply(r,{op=field=='Buffs'and'addBuff'or'addDebuff',paramId=id,turns=number(args.Turns,0)},rng);rng=out.rngState end end end
   end
   -- Every source operation is visible to the presentation adapter, including
   -- typed expression ASTs and explicit simplified-effect identifiers.
   record(s,rows,'visuSequence',{command=cmd,args=args,subjectRef=s.subject,targets=targets(args.Targets or args.Targets1 or {'all targets'},true),allTargets=seq.targets,source=instruction.source})
   if cmd=='ActSeq_Impact_TimeStop'then seq.wait=math.ceil(args.ms*60/1000)
   elseif type(args.Duration)=='number'then for k,v in pairs(args)do if k:match('^WaitFor')and v==true then seq.wait=math.max(seq.wait,args.Duration)end end end
   return rng,false
  end
  -- TPB clocks use the source 60/240 frame reference times. Input belongs to
  -- charged Actors; action order is ready FIFO rather than a speed sort.
  local function tpbCanInput(s,ctx,p)
   for _,r in ipairs(actorRefs(p,s))do local q=ctx.query(r);local t=s.tpb[key(r)]
    if t and t.state=='charged'and movable(q)and q.restriction==0 and not q.traits.isAutoBattle()then return true end
   end;return false
  end
  local function tpbInputs(s,ctx,p)
   local previous=s.inputs[s.inputIndex];local list={}
   for _,r in ipairs(actorRefs(p,s))do local q=ctx.query(r);local t=s.tpb[key(r)]
    if t and t.state=='charged'and movable(q)and q.restriction==0 and not q.traits.isAutoBattle()then
     for slot,value in ipairs(s.slots[key(r)]or {})do if value==false then list[#list+1]={actorRef=copy(r),actionSlot=slot}end end
    end
   end
   s.inputs=list;s.inputIndex=1
   if previous then for i,item in ipairs(list)do if same(item.actorRef,previous.actorRef)and item.actionSlot==previous.actionSlot then s.inputIndex=i;break end end end
  end
  local function tpbMakeActions(s,ctx,p,a,e,rng,r)
   local q=ctx.query(r);local slots={};s.slots[key(r)]=slots
   if r.kind=='enemy'then
    local highest=0;for _,ar in ipairs(actorRefs(p,s))do highest=math.max(highest,a.getActor(ar.id).state.level)end
    local ai=ctx.selectEnemyActions(r,{inBattle=true,turnCount=s.tpb[key(r)].turnCount,partyHighestLevel=highest,switches=switches},rng);rng=ai.rngState
    for i,slot in ipairs(ai.actionSlots)do slots[i]=slot and {actionRef={kind='skill',id=slot.skillId},targetIndex=-1,isAttack=slot.skillId==q.traits.attackSkillId(),forcing=false}or false end
   elseif movable(q)then
    local rr=RNG.restore(rng);local count=1;for _,chance in ipairs(q.traits.actionPlusSet())do if rr.nextUnit('battle.actor.actionPlus')<chance then count=count+1 end end
    if count>1000 then fail('E_BATTLE_BUDGET','Actor action count exceeds stage budget')end;rng=rr.snapshot()
    if q.traits.isAutoBattle()then local automatic=Auto.select({battleId=o.battleId,subjectRef=r,actionCount=count,partyRefs=actorRefs(p,s),troopRefs=enemyRefs(e),rngState=rng,variables=variables},ctx,Actions);s.slots[key(r)]=automatic.actionSlots;rng=automatic.rngState
    else for slot=1,count do slots[slot]=q.restriction>0 and {actionRef={kind='skill',id=q.traits.attackSkillId()},targetIndex=-1,isAttack=true,forcing=false}or false end end
   end
   local t=s.tpb[key(r)]
   if r.kind=='enemy'or not movable(q)or q.restriction>0 or q.traits.isAutoBattle()then t.state='casting';t.castTime=0 end
   return rng
  end
  local function tpbUpdate(s,ctx,p,a,e,rng,rows)
   local members=refs(p,e,s);local base=0
   for _,r in ipairs(actorRefs(p,s))do base=math.max(base,math.sqrt(a.getActor(r.id).stats.basePlus[7])+1)end
   for _,r in ipairs(members)do local q=ctx.query(r);local t=s.tpb[key(r)]
    if not t then fail('E_BATTLE_SNAPSHOT','Missing TPB battler clock')end
    local speed=math.sqrt(q.params[7])+1;local acceleration=base==0 and 0 or speed/base/(battleSystem==1 and 240 or 60)
    if movable(q)then
     if t.state=='charging'then
      t.chargeTime=math.min(1,t.chargeTime+acceleration)
      if t.chargeTime>=1 and (battleSystem==1 or not tpbCanInput(s,ctx,p))then t.state='charged';t.turnEnd=true;t.idleTime=0 end
     end
     if t.state=='casting'then
      local delay=0;for _,slot in ipairs(s.slots[key(r)]or {})do if slot and (slot.forcing or Actions.canUse({actionRef=slot.actionRef,subjectRef=r,inBattle=true},ctx).ok)then delay=delay+math.max(0,-Actions.describe(slot.actionRef).speed)end end
      local required=math.sqrt(delay)/speed;t.castTime=t.castTime+acceleration
      if t.castTime>=required then t.castTime=required;t.state='ready' end
     end
     if t.state=='charged'and not t.turnEnd and q.traits.isAutoBattle()then rng=tpbMakeActions(s,ctx,p,a,e,rng,r)end
    end
    if not q.hidden and not dead(q)and (not movable(q)or t.state=='charged')then t.idleTime=t.idleTime+acceleration end
   end
   for _,r in ipairs(members)do local t=s.tpb[key(r)]
    if t.turnEnd then
     rng=lifecycle('turnEnd',r,ctx,s,rng,rows);t.turnEnd=false;t.turnCount=t.turnCount+1;t.idleTime=0
     if #(s.slots[key(r)]or {})==0 then rng=tpbMakeActions(s,ctx,p,a,e,rng,r)end
    elseif t.state=='ready'then t.state='acting';s.order[#s.order+1]=copy(r);record(s,rows,'tpbReady',{subjectRef=r})
    elseif t.idleTime>=1 then rng=lifecycle('actionsEnd',r,ctx,s,rng,rows);t.turnEnd=true;t.idleTime=0 end
   end
   tpbInputs(s,ctx,p)
   local maximum=0;for _,r in ipairs(enemyRefs(e))do maximum=math.max(maximum,s.tpb[key(r)].turnCount)end
   if maximum>s.turnCount then s.phase='turnEnd';s.preemptive=false;s.surprise=false;record(s,rows,'turnEnd',{turnCount=s.turnCount})end
   return rng
  end
  local function endActions(s,ctx,r,rng,rows)
   rng=lifecycle('actionsEnd',r,ctx,s,rng,rows)
   if tpb then local t=s.tpb[key(r)];t.state='charging';t.chargeTime=0 end
   return rng
  end
  local function advance(s,ctx,p,a,e,rng,rows,clock)
   if s.phase=='battleEnd'or s.phase=='input'then return rng end
   if s.phase=='aborting'then return finish(s,ctx,p,a,e,rng,rows,1)end
   local ended;if s.phase~='action'then rng,ended=checkEnd(s,ctx,p,a,e,rng,rows);if ended then return rng end end
   if s.phase=='start'then if tpb then s.phase='turn';return rng end;return input(s,ctx,p,a,e,rng,rows)
   elseif s.phase=='turnEnd'then
    if tpb then s.turnCount=s.turnCount+1;s.phase='turn';record(s,rows,'turnStart',{turnCount=s.turnCount});return rng end
    if not mv then for _,r in ipairs(refs(p,e,s))do rng=lifecycle('turnEnd',r,ctx,s,rng,rows)end end;s.forcedTurn=false;s.phase='start';return rng
   elseif s.phase=='action'then
    if s.visuSequence then local complete;rng,complete=sequenceStep(s,ctx,p,e,rng,rows,clock);if not complete then return rng end end
    local target=table.remove(s.targets,1);if target then return invoke(s,ctx,p,e,rng,rows,target)end
    record(s,rows,'actionEnd',{subjectRef=s.subject});s.phase='turn';s.current=false;s.reflectionTarget=false
    if not mv and #(s.slots[key(s.subject)]or {})==0 then rng=endActions(s,ctx,s.subject,rng,rows);s.subject=false end;return rng
   elseif s.phase=='turn'then
    if tpb then
     -- The host gate can pause time, but cannot keep a wait-mode batch
     -- running after this authority has made an actor ready for input.
     local active=clock.timeActive~=false and (battleSystem==1 or not tpbCanInput(s,ctx,p))
     if active then for _=1,clock.frames do rng=tpbUpdate(s,ctx,p,a,e,rng,rows);if s.phase~='turn'or #s.order>0 or battleSystem==2 and tpbCanInput(s,ctx,p)then break end end end
    end
    if not s.subject then while #s.order>0 do local r=table.remove(s.order,1);local q=ctx.query(r);if ctx.isBattleMember(r)and not q.hidden and not dead(q)then s.subject=r;break end end end
    if not s.subject then if tpb then return rng end;s.phase='turnEnd';s.preemptive=false;s.surprise=false;record(s,rows,'turnEnd',{turnCount=s.turnCount});if mv then for _,member in ipairs(refs(p,e,s))do rng=lifecycle('turnEnd',member,ctx,s,rng,rows)end;s.forcedTurn=false end;return rng end
    local r=s.subject;local slots=s.slots[key(r)]or {};local current=table.remove(slots,1)
    if current==nil then rng=endActions(s,ctx,r,rng,rows);s.subject=false;return rng end
    if current==false then record(s,rows,'actionSkipped',{subjectRef=r,reason='empty'});return rng end
    local q=ctx.query(r);if q.restriction>=1 and q.restriction<=3 and not current.forcing then current.actionRef={kind='skill',id=q.traits.attackSkillId()};current.isAttack=true end
    local usable=Actions.canUse({actionRef=current.actionRef,subjectRef=r,inBattle=true},ctx)
    if not usable.ok then record(s,rows,'actionSkipped',{subjectRef=r,reason=usable.reason});return rng end
    return startAction(s,ctx,p,e,rng,rows,r,current)
   end
   fail('E_BATTLE_PHASE','Unknown battle phase')
  end
  function B.isTpb()return tpb end
  function B.eventRandom(upper)
   if busy then fail('E_BATTLE_REENTRY','Cannot draw event randomness during a stage')end
   local rng=RNG.restore(random);local value=rng.nextInt(upper,'event.variable');random=rng.snapshot();return value
  end
  function B.gameData(value)
   local kind,id,field=value.type,value.id,value.field
   if kind==8 then return state.lastActionData[id+1] or 0
   elseif kind<=2 then return party.count(({'item','weapon','armor'})[kind+1],id)
   elseif kind==6 then return party.members()[id+1] or 0
   elseif kind==7 and value.id==1 then return #party.members()
   elseif kind==7 and value.id==2 then return party.gold()
   elseif kind==3 then
    if not actors.hasActor(id)then return 0 end
    local actor=actors.getActor(id)
    if field==0 then return actor.state.level elseif field==1 then return actors.progression(id).currentExp
    elseif field==2 then return actor.state.hp elseif field==3 then return actor.state.mp elseif field==12 then return actor.state.tp end
    return actor.stats.params[field-3] or 0
   elseif kind==4 then
    local ref=enemyRefs(enemies)[id+1];if not ref then return 0 end
    local q=readContext(state,party,actors,enemies).query(ref)
    if field==0 then return q.hp elseif field==1 then return q.mp elseif field==10 then return q.tp end
    return q.params[field-1] or 0
   elseif kind==5 then return 0 end
   fail('E_BATTLE_EVENT_OPERAND','Unknown battle data operand')
  end
  function B.extensionOperations(operations)
   plain(operations);dense(operations,128)
   return transact(function(s,ctx,p,a,e,rng)
    for _,op in ipairs(operations)do
     plain(op);number(op.amount,-2147483647,2147483647)
     if op.kind=='gold'then ctx.gainGold(op.amount)
     elseif op.kind=='inventory'then number(op.id,1);if not ({item=true,weapon=true,armor=true})[op.itemKind]then fail('E_EXTENSION_RUNTIME','Invalid inventory kind')end;ctx.gainItem(op.itemKind,op.id,op.amount,false)
     else fail('E_EXTENSION_RUNTIME','Unsupported extension operation')end
    end
    return rng
   end)
  end
  function B.abort()
   if state.settled then return{ok=true,records={}}end
   return transact(function(s,ctx,p,a,e,rng,rows)
    s.phase='aborting';s.aborted=true;record(s,rows,'battleAbort',{reason='timer'});return rng
   end)
  end
  function B.eventPhase()return state.phase,state.turnCount end
  function B.eventBattler(kind,id)
   number(id,kind=='actor'and 1 or 0)
   local r;if kind=='actor'then if not actors.hasActor(id)then return nil end;r={kind='actor',id=id}
   elseif kind=='enemy'then r=enemyRefs(enemies)[id+1];if not r then return nil end
   else fail('E_BATTLE_REFERENCE','Unknown event battler kind')end
   local q=readContext(state,party,actors,enemies).query(r);return{hp=q.hp,mhp=q.params[1]}
  end
  function B.eventCondition(c)
   plain(c)
   if c.kind=='inventory'then return party.hasItem(c.itemKind,c.id,c.includeEquip)
   elseif c.kind=='enemy'then
    local r=enemyRefs(enemies)[c.index+1];if not r then return false end
    local q=readContext(state,party,actors,enemies).query(r)
    if c.stateId then for _,id in ipairs(q.stateIds)do if id==c.stateId then return true end end;return false end
    return not q.hidden and not dead(q)
   elseif c.kind=='actor'then
    if c.test then return actors.meetsCondition(c.id,c.test,c.value,(o.actorNames or {})[c.id])end
    return party.hasActor(c.id)
   elseif c.kind=='gold'then number(c.comparison,0,2);number(c.value,0);local gold=party.gold();if c.comparison==0 then return gold>=c.value elseif c.comparison==1 then return gold<=c.value else return gold<c.value end end
   fail('E_BATTLE_EVENT_CONDITION','Unknown battle domain condition')
  end
  function B.isActionForced()
   if not state.forced or state.settled then return false end
   return endCode(state,readContext(state,party,actors,enemies),party,enemies)==nil
  end
  function B.processForcedAction()
   if not B.isActionForced()then return{ok=true,records={}}end
   if state.phase~='start'and state.phase~='turn'and state.phase~='turnEnd'then fail('E_BATTLE_PHASE','Forced action requires event phase')end
   return transact(function(s,ctx,p,a,e,rng,rows)
    if s.subject and not mv then rng=endActions(s,ctx,s.subject,rng,rows)end
    local r=s.forced;s.subject=r;s.forced=false;if mv then s.forcedTurn=true end
    local slots=s.slots[key(r)]or {};local current=slots[1]
    if not current then fail('E_BATTLE_FORCED_EMPTY','Pending forced battler has no action')end
    rng=startAction(s,ctx,p,e,rng,rows,r,current);table.remove(slots,1);return rng
   end)
  end
  function B.checkBattleEnd()
   if state.visuSequence then return{ended=false,records={}}end
   if state.settled then return{ended=true,records={}}end
   if endUnchanged then return{ended=false,records={}}end
   local code=endCode(state,readContext(state,party,actors,enemies),party,enemies)
   if code==nil then endUnchanged=true;return{ended=false,records={}}end
   local out=transact(function(s,ctx,p,a,e,rng,rows)return finish(s,ctx,p,a,e,rng,rows,code)end);out.ended=true;return out
  end
  local eventFields={
   enemy_hp='enemyIndex operation operand allowDeath',enemy_mp='enemyIndex operation operand',enemy_tp='enemyIndex operation operand',
   enemy_state='enemyIndex operation stateId',enemy_recover='enemyIndex',enemy_transform='enemyIndex enemyId',enemy_appear='enemyIndex',enemy_animation='enemyIndex animationId allEnemies',
   force_action='battlerType battlerId skillId targetIndex',abort_battle='',gold='operation operand',inventory='itemKind id operation operand includeEquip',
   party_member='id remove',actor_recover='actorMode actorSelector',actor_exp='actorMode actorSelector operation operand showLevelUp',actor_level='actorMode actorSelector operation operand showLevelUp',
   change_equipment='actorId slot itemId',actor_hp='actorMode actorSelector operation operand allowDeath',actor_mp='actorMode actorSelector operation operand',actor_tp='actorMode actorSelector operation operand',
   actor_state='actorMode actorSelector operation stateId',actor_param='actorMode actorSelector operation operand paramId',actor_skill='actorMode actorSelector operation skillId',actor_class='actorMode actorSelector classId keepExp'
  }
  function B.eventCommand(ins,story)
   plain(ins);local fields=eventFields[ins.op];if not fields then fail('E_BATTLE_EVENT_UNSUPPORTED','Unsupported battle event command')end
   local allowed={op=true,source=true};for name in fields:gmatch('%S+')do allowed[name]=true;if ins[name]==nil then fail('E_BATTLE_EVENT_SHAPE','Missing '..name)end end
   if ins.op=='enemy_animation'then allowed.asset=true end
   if ins.op=='party_member'then allowed.initialize=true;if ins.initialize~=nil and type(ins.initialize)~='boolean'then fail('E_BATTLE_EVENT_SHAPE','Invalid actor initialize flag')end end
   for name in pairs(ins)do if not allowed[name]then fail('E_BATTLE_EVENT_SHAPE','Unknown event command field')end end
   if state.settled then fail('E_BATTLE_SETTLED','Cannot mutate a settled battle')end
   if state.phase~='start'and state.phase~='turn'and state.phase~='turnEnd'and state.phase~='aborting'then fail('E_BATTLE_PHASE','Event command requires interpreter phase')end
   local function boolean(v)if type(v)~='boolean'then fail('E_BATTLE_EVENT_SHAPE','Expected event boolean')end;return v end
   local value
   if ins.operand then
    plain(ins.operand);for k in pairs(ins.operand)do if k~='kind'and k~='value'then fail('E_BATTLE_EVENT_SHAPE','Unknown operand field')end end
    if ins.operand.kind~='constant'and ins.operand.kind~='variable'then fail('E_BATTLE_EVENT_SHAPE','Unknown operand kind')end
    number(ins.operand.value,ins.operand.kind=='variable'and 1 or -SAFE);number(ins.operation,0,1)
    if type(story)~='table'or type(story.readOperand)~='function'then fail('E_BATTLE_CAPABILITY','Story operand reader required')end
    value=number(story.readOperand(ins.operand),-SAFE);if ins.operation==1 then value=-value end
   end
   if ins.enemyIndex~=nil then number(ins.enemyIndex,-1,10000)end
   if ins.op=='enemy_hp'then boolean(ins.allowDeath)
   elseif ins.op=='enemy_state'then number(ins.operation,0,1);number(ins.stateId,1)
   elseif ins.op=='enemy_transform'then number(ins.enemyId,1)
   elseif ins.op=='enemy_animation'then number(ins.animationId,1);boolean(ins.allEnemies)
   elseif ins.op=='force_action'then number(ins.battlerType,0,1);number(ins.battlerId,ins.battlerType==0 and -1 or 0);number(ins.skillId,1);number(ins.targetIndex,-2,10000);Actions.describe({kind='skill',id=ins.skillId})
   elseif ins.op=='inventory'then number(ins.id,1);boolean(ins.includeEquip)
   elseif ins.op=='party_member'then number(ins.id,1);boolean(ins.remove)
   elseif ins.op=='change_equipment'then number(ins.actorId,1);number(ins.slot,1);number(ins.itemId,0)
   elseif ins.op:match('^actor_')then
    number(ins.actorMode,0,1);number(ins.actorSelector,ins.actorMode==0 and 0 or 1)
    if (ins.op=='actor_exp' or ins.op=='actor_level')and type(ins.showLevelUp)~='boolean'then fail('E_BATTLE_EVENT_SHAPE','Invalid show level up option')end
    if ins.op=='actor_hp'then boolean(ins.allowDeath)
    elseif ins.op=='actor_state'then number(ins.operation,0,1);number(ins.stateId,1)
    elseif ins.op=='actor_skill'then number(ins.operation,0,1);number(ins.skillId,1)
    elseif ins.op=='actor_param'then number(ins.paramId,0,7)
    elseif ins.op=='actor_class'then number(ins.classId,1);boolean(ins.keepExp)end
   end
   local wait=false
   local out=transact(function(s,ctx,p,a,e,rng,rows)
    local function enemiesSelected(index)local list=enemyRefs(e);if index==-1 then return list end;return list[index+1]and{list[index+1]}or {}end
    if ins.op=='force_action'then
     local selected
     if ins.battlerType==0 then selected=enemiesSelected(ins.battlerId)
     elseif ins.battlerId==0 then selected=actorRefs(p,s)
     elseif a.hasActor(ins.battlerId)then selected={{kind='actor',id=ins.battlerId}}else selected={}end
     for _,r in ipairs(selected)do local q=ctx.query(r);if not dead(q)then
      wait=true;s.slots[key(r)]={};local index=ins.targetIndex;local valid=true;local meta=Actions.describe({kind='skill',id=ins.skillId})
      if index==-2 then index=s.lastTarget[key(r)]or 0
      elseif index==-1 then
       local ps,ts=unitSnapshots(ctx,s,p,e,false);local request={battleId=o.battleId,subject=r,party=ps,troop=ts,action={scope=meta.scope,repeats=meta.repeats,isAttack=ins.skillId==q.traits.attackSkillId(),targetIndex=-1,forcing=true},rngState=rng}
       if r.kind=='actor'and not ctx.isBattleMember(r)then request.subjectSnapshot=subjectSnapshot(r,ctx)end
       local choice=Targets.decideRandomTarget(request);rng=choice.rngState;index=choice.targetIndex;valid=index~=false
      end
      if valid then
       s.slots[key(r)][1]={actionRef={kind='skill',id=ins.skillId},targetIndex=index,isAttack=ins.skillId==q.traits.attackSkillId(),forcing=true};s.forced=copy(r)
       for i=#s.order,1,-1 do if same(s.order[i],r)then table.remove(s.order,i)end end
      end
      record(s,rows,'actionForced',{subjectRef=r,skillId=ins.skillId,targetIndex=index,scheduled=valid})
     end end
    elseif ins.op=='abort_battle'then s.phase='aborting';s.aborted=true;record(s,rows,'battleAbort')
    elseif ins.op=='change_equipment'then rng=ctx.eventEquip(ins.actorId,ins.slot,ins.itemId,rng).rngState
    elseif ins.op=='gold'then ctx.gainGold(value)
    elseif ins.op=='inventory'then ctx.gainItem(ins.itemKind,ins.id,value,ins.includeEquip)
    elseif ins.op=='party_member'then
     local r={kind='actor',id=ins.id};local before=ctx.isBattleMember(r)
     if not ins.remove and ins.initialize then
      rng=ctx.actorCommand({op='setup',actorId=ins.id},rng).rngState
      record(s,rows,'actorSetup',{actorId=ins.id})
     end
     local changed=ctx.partyMember(ins.id,ins.remove)
     if not mv and changed and ins.remove and before then
      rng=lifecycle('battleEnd',r,ctx,s,rng,rows)
      if same(s.forced,r)then s.forced=false;record(s,rows,'forcedActionCancelled',{subjectRef=r,reason='actorRemoved'})end
     elseif not mv and changed and not ins.remove and ctx.isBattleMember(r)then
      local base=0;for _,member in ipairs(actorRefs({members=ctx.members},s))do base=math.max(base,mv and 0 or math.sqrt(a.getActor(member.id).stats.basePlus[7])+1)end
      local relative=mv and 0 or base==0 and -0.0 or(math.sqrt(ctx.query(r).params[7])+1)/base
      rng=lifecycle('battleStart',r,ctx,s,rng,rows,{advantageous=false,tpbRelativeSpeed=relative})
     end
    elseif ins.op:match('^actor_')then
     local id=ins.actorMode==0 and ins.actorSelector or story.getVariable(ins.actorSelector);number(id,0)
     local selected={};if id==0 then for _,r in ipairs(actorRefs(p,s))do selected[#selected+1]=r.id end else selected={id}end
     for _,actorId in ipairs(selected)do if a.hasActor(actorId)then
      local r={kind='actor',id=actorId};local command={op='recoverAll',actorId=actorId}
      if ins.op=='actor_exp'then command.op='changeExp';command.total=number(ctx.progression(r).currentExp+value*1.0,-SAFE)
      elseif ins.op=='actor_level'then command.op='changeLevel';command.level=number(ctx.query(r).formula.level+value*1.0,-SAFE)
      elseif ins.op=='actor_class'then command.op='changeClass';command.classId=ins.classId;command.keepExp=ins.keepExp
      elseif ins.op=='actor_skill'then command.op=ins.operation==0 and 'learnSkill' or 'forgetSkill';command.skillId=ins.skillId
      end
      local operation;local q=ctx.query(r)
      if ins.op=='actor_hp'then if not dead(q)then operation={op='gainHp',value=not ins.allowDeath and q.hp+value<=0 and 1-q.hp or value}end
      elseif ins.op=='actor_mp' or ins.op=='actor_tp'then operation={op=ins.op=='actor_mp' and 'gainMp' or 'gainTp',value=value}
      elseif ins.op=='actor_state'then operation={op=ins.operation==0 and 'addState' or 'removeState',stateId=ins.stateId}
      elseif ins.op=='actor_param'then operation={op='addParam',paramId=ins.paramId,value=value}end
      if operation then local result=ctx.apply(r,operation,rng);rng=result.rngState
       if (ins.op=='actor_hp' or ins.op=='actor_state')and not dead(q)and dead(ctx.query(r))then collapse(s,rows,r,ctx)end
      elseif ins.op~='actor_hp'then
       local result=ctx.actorCommand(command,rng);rng=result.rngState
       if ins.showLevelUp and result.delta and result.delta.levelTo>result.delta.levelFrom then
        record(s,rows,'actorGrowth',{actorId=actorId,delta=copy(result.delta)})
       end
      end
     end end
    else
     local selected=enemiesSelected(ins.op=='enemy_animation'and ins.allEnemies and -1 or ins.enemyIndex)
     for _,r in ipairs(selected)do
      local q=ctx.query(r);local operation
      if ins.op=='enemy_hp'then if not q.hidden and not dead(q)then operation={op='gainHp',value=not ins.allowDeath and q.hp+value<=0 and 1-q.hp or value}end
      elseif ins.op=='enemy_mp'then operation={op='gainMp',value=value}
      elseif ins.op=='enemy_tp'then operation={op='gainTp',value=value}
      elseif ins.op=='enemy_state'then operation={op=ins.operation==0 and 'addState'or 'removeState',stateId=ins.stateId}
      elseif ins.op=='enemy_recover'then operation={op='recoverAll'}
      elseif ins.op=='enemy_transform'then
       local pending=#(s.slots[key(r)]or {})>0;local old=q.originalName;local transformed=ctx.transformEnemy(r,ins.enemyId,rng);rng=transformed.rngState
       if old~=ctx.query(r).originalName then s.enemyLetters[r.troopSlot]=nil end
       if pending then
        local highest=0;for _,actor in ipairs(actorRefs(p,s))do highest=math.max(highest,a.getActor(actor.id).state.level)end
        local ai=ctx.selectEnemyActions(r,{inBattle=true,turnCount=tpb and s.tpb[key(r)].turnCount or s.turnCount+1,partyHighestLevel=highest,switches=switches},rng);rng=ai.rngState;s.slots[key(r)]={}
        for i,slot in ipairs(ai.actionSlots)do s.slots[key(r)][i]=slot and {actionRef={kind='skill',id=slot.skillId},targetIndex=-1,isAttack=slot.skillId==ctx.query(r).traits.attackSkillId(),forcing=false}or false end
       end
       uniqueEnemyNames(s,ctx,e);record(s,rows,'enemyTransform',{targetRef=r,enemyId=ins.enemyId})
      elseif ins.op=='enemy_appear'then ctx.appear(r);uniqueEnemyNames(s,ctx,e)
      elseif ins.op=='enemy_animation'and not q.hidden and not dead(q)then record(s,rows,'animation',{targetRef=r,animationId=ins.animationId})end
      if operation then local applied=ctx.apply(r,operation,rng);rng=applied.rngState
       if (ins.op=='enemy_hp' or ins.op=='enemy_state')and not dead(q)and dead(ctx.query(r))then collapse(s,rows,r,ctx)end
      end
     end
    end
    record(s,rows,'eventCommand',{op=ins.op});return rng
   end)
   out.waitForAction=wait;return out
  end
  function B.snapshot()return{schemaVersion=1,profile=profile,battleSystem=battleSystem,battleId=o.battleId,troopId=o.troopId,state=copy(state),partyState=party.snapshot(),actorsState=actors.snapshot(),enemiesState=enemies.snapshot(),rngState=copy(random),switches=copy(switches),variables=copy(variables)}end
  function B.result()if not state.settled then return nil end;local out=copy(state.outcome);out.partyState=party.snapshot();out.actorsState=actors.snapshot();out.rngState=copy(random);out.lastActionData=copy(state.lastActionData);return out end
  function B.setContext(c)if busy then fail('E_BATTLE_REENTRY','Cannot update context during a stage')end;plain(c);local sw,va=copy(c.switches or switches),copy(c.variables or variables);switches,variables=sw,va;cached=nil;tpbClockModel=nil end
  function B.view()
   if cached then return copy(cached)end
   local ctx=readContext(state,party,actors,enemies);local v={battleId=o.battleId,revision=state.revision,phase=state.phase,corePhase=state.phase,battleSystem=battleSystem,tpb=tpb,turnCount=state.turnCount,canEscape=o.canEscape or false,canLose=o.canLose or false,party={},troop={},input=false,commands={},skills={},skillTypes={},items={},targets={},records=copy(latest),result=state.settled and copy(state.outcome)or false}
   for side,list in ipairs({actorRefs(party),enemyRefs(enemies)})do for index,r in ipairs(list)do local q=ctx.query(r);local name
    if r.kind=='enemy'then name=state.enemyNames[key(r)] else name=type(actors.name)=='function'and actors.name(r.id)or(o.actorNames and o.actorNames[r.id])or('Actor '..string.format('%.0f',r.id))end
    local row={ref=copy(r),index=index-1,name=name,hp=q.hp,mp=q.mp,tp=q.tp,mhp=q.params[1],mmp=q.params[2],hidden=q.hidden,dead=dead(q),stateIds=copy(q.stateIds),buffs=copy(q.buffs)}
    if r.kind=='enemy'then local es=enemies.getEnemy(r).state;row.enemyId=es.enemyId;row.x=es.x;row.y=es.y;row.visu=copy(es.visu)end
    if tpb then row.tpb=copy(state.tpb[key(r)])end
    local listOut=side==1 and v.party or v.troop;listOut[#listOut+1]=row;v.targets[#v.targets+1]=copy(row)
   end end
   local inp=(state.phase=='input'or tpb and mainPhase(state.phase))and state.inputs[state.inputIndex]
   if inp and tpb then local q=ctx.query(inp.actorRef);local clock=state.tpb[key(inp.actorRef)];if not clock or clock.state~='charged'or not movable(q)or q.restriction~=0 or q.traits.isAutoBattle()then inp=false end end
   if inp then
    if tpb then v.phase='input'end
    v.input=copy(inp);v.input.slots=#(state.slots[key(inp.actorRef)]or {});local q=ctx.query(inp.actorRef)
    v.input.attackScope=Actions.describe({kind='skill',id=q.traits.attackSkillId()}).scope;v.input.guardScope=Actions.describe({kind='skill',id=2}).scope
    v.input.canPrevious=tpb and inp.actionSlot>1 or state.inputIndex>1
    v.skillTypes=q.traits.addedSkillTypes();table.sort(v.skillTypes)
    for _,id in ipairs(q.skills)do local ref={kind='skill',id=id};local meta=Actions.describe(ref);local can=Actions.canUse({actionRef=ref,subjectRef=inp.actorRef,inBattle=true},ctx);meta.enabled=can.ok;meta.reason=can.reason;meta.cost=can.cost;v.skills[#v.skills+1]=meta end
    local inv=party.snapshot().inventory.item;local ids={};for id,count in pairs(inv)do if count>0 then ids[#ids+1]=id end end;table.sort(ids)
    for _,id in ipairs(ids)do local ref={kind='item',id=id};local meta=Actions.describe(ref);local can=Actions.canUse({actionRef=ref,subjectRef=inp.actorRef,inBattle=true},ctx);meta.enabled=can.ok;meta.reason=can.reason;meta.count=inv[id];v.items[#v.items+1]=meta end
    for _,command in ipairs({'attack','guard','skill','item','escape'})do local enabled=true;if command=='escape'then enabled=o.canEscape or false elseif command=='attack'or command=='guard'then enabled=Actions.canUse({actionRef={kind='skill',id=command=='attack'and q.traits.attackSkillId()or 2},subjectRef=inp.actorRef,inBattle=true},ctx).ok end;v.commands[#v.commands+1]={command=command,enabled=enabled}end
    if q.visuBattleCommands then
     v.visuCommands={}
     for _,definition in ipairs(q.visuBattleCommands)do
      if definition.command=='skills'then
       for _,id in ipairs(v.skillTypes)do local label=q.skillTypeNames and q.skillTypeNames[id+1];if not label then fail('E_VISU_BATTLE_COMMAND','Missing source skill-type label')end
        v.visuCommands[#v.visuCommands+1]={command='skill',stypeId=id,label=label,enabled=not q.traits.isSkillTypeSealed(id)}
       end
      else
       local row=copy(definition);row.enabled=true
       if row.command=='skill_direct'or row.command=='attack'or row.command=='guard'then
        local ref={kind='skill',id=row.command=='attack'and q.traits.attackSkillId()or row.command=='guard'and 2 or row.id}
        local meta=Actions.describe(ref);local can=Actions.canUse({actionRef=ref,subjectRef=inp.actorRef,inBattle=true},ctx)
        row.id=ref.id;row.scope=meta.scope;row.enabled=can.ok;row.reason=can.reason;row.cost=can.cost;row.description=meta.description
        if row.command=='skill_direct'then row.label=meta.commandText or meta.name end
       elseif row.command=='escape'then row.enabled=o.canEscape or false
       elseif row.command~='item'and row.command~='party'then fail('E_VISU_BATTLE_COMMAND','Unknown compiled class command')end
       v.visuCommands[#v.visuCommands+1]=row
      end
     end
    end
   end
   cached=copy(v);return v
  end
  function B.submit(c)
   plain(c);local allowed={battleId=true,revision=true,command=true,actorRef=true,actionSlot=true,id=true,targetIndex=true};for k in next,c do if not allowed[k]then fail('E_BATTLE_INPUT','Unknown input field')end end
   if c.battleId~=o.battleId or c.revision~=state.revision then fail('E_BATTLE_TOKEN','Stale or cross-battle input token')end
   if state.phase~='input'and not(tpb and mainPhase(state.phase))then fail('E_BATTLE_PHASE','Battle is not accepting input')end
   local inp=state.inputs[state.inputIndex];if not inp or tpb and not B.view().input then fail('E_BATTLE_PHASE','No input slot')end
   if c.actorRef and not same(reference(c.actorRef,party,enemies),inp.actorRef)or c.actionSlot and c.actionSlot~=inp.actionSlot then fail('E_BATTLE_INPUT','Input belongs to another action slot')end
   if c.command~='attack'and c.command~='guard'and c.command~='skill'and c.command~='skill_direct'and c.command~='item'and c.command~='escape'and c.command~='cancel'then fail('E_BATTLE_INPUT','Unknown command')end
   local out=transact(function(s,ctx,p,a,e,rng,rows)
    if c.command=='cancel'then
     if tpb then
      if inp.actionSlot<=1 then fail('E_BATTLE_INPUT','Already at first input slot')end
      s.slots[key(inp.actorRef)][inp.actionSlot-1]=false;tpbInputs(s,ctx,p)
      for i,item in ipairs(s.inputs)do if same(item.actorRef,inp.actorRef)and item.actionSlot==inp.actionSlot-1 then s.inputIndex=i;break end end
      record(s,rows,'inputCancel',{subjectRef=inp.actorRef,actionSlot=inp.actionSlot-1});return rng
     end
     if s.inputIndex<=1 then fail('E_BATTLE_INPUT','Already at first input slot')end;s.inputIndex=s.inputIndex-1;local previous=s.inputs[s.inputIndex];s.slots[key(previous.actorRef)][previous.actionSlot]=false
     record(s,rows,'inputCancel',{subjectRef=previous.actorRef,actionSlot=previous.actionSlot});return rng
    end
    if c.command=='escape'then
     if not o.canEscape then fail('E_BATTLE_INPUT','Escape is disabled')end;local rr=RNG.restore(rng);local success=o.visuAlwaysEscape or s.preemptive or rr.nextUnit('battle.escape')<s.escapeRatio;rng=rr.snapshot()
     record(s,rows,'escape',{success=success,ratio=s.escapeRatio})
     if success then return finish(s,ctx,p,a,e,rng,rows,1)end
     s.escapeRatio=s.escapeRatio+.1;for _,r in ipairs(actorRefs(p,s))do s.slots[key(r)]={};if tpb then local t=s.tpb[key(r)];t.state='charging';t.chargeTime=t.chargeTime-1 end end
     if tpb then s.inputs={};s.inputIndex=1;return rng end;return startTurn(s,ctx,p,e,rng,rows)
    end
    local q=ctx.query(inp.actorRef);local ref={kind=c.command=='item'and 'item'or 'skill',id=c.command=='attack'and q.traits.attackSkillId()or c.command=='guard'and 2 or number(c.id,1)}
    local direct=directClassSkill(q,ref.id)
    if c.command=='skill_direct'and not direct then fail('E_BATTLE_INPUT','Direct skill is not declared by the current class')end
    if c.command=='skill'and not has(q.skills,ref.id)and not direct then fail('E_BATTLE_INPUT','Skill is not known')end
    local can=Actions.canUse({actionRef=ref,subjectRef=inp.actorRef,inBattle=true},ctx);if not can.ok then fail('E_BATTLE_INPUT','Action unavailable: '..tostring(can.reason))end
    local targetIndex=number(c.targetIndex==nil and -1 or c.targetIndex,-1,10000)
    s.slots[key(inp.actorRef)][inp.actionSlot]={actionRef=ref,targetIndex=targetIndex,isAttack=ref.kind=='skill'and ref.id==q.traits.attackSkillId(),forcing=false}
    record(s,rows,'input',{subjectRef=inp.actorRef,actionSlot=inp.actionSlot,actionRef=ref,targetIndex=targetIndex});s.inputIndex=s.inputIndex+1
    if tpb then
     local finished=true;for _,slot in ipairs(s.slots[key(inp.actorRef)])do if slot==false then finished=false end end
     if finished then local t=s.tpb[key(inp.actorRef)];t.state='casting';t.castTime=0 end
     tpbInputs(s,ctx,p);return rng
    end
    if s.inputIndex>#s.inputs then return startTurn(s,ctx,p,e,rng,rows)end;return rng
   end);out.view=B.view();out.result=B.result();return out
  end
  -- Between TPB boundaries only clocks change. Cache detached rule values
  -- until the next authority transaction; never rebuild battlers for these ticks.
  local function clockOnly(clock)
   if not tpb or state.phase~='turn' or state.subject or #state.order>0 or state.forced then return false end
   if busy then fail('E_BATTLE_REENTRY','Battle operation is not reentrant')end;busy=true
   local ok,result=pcall(function()
    if not tpbClockModel then
     local ctx=readContext(state,party,actors,enemies)
     if not endUnchanged and endCode(state,ctx,party,enemies)~=nil then return false end
     local base=0;for _,r in ipairs(actorRefs(party,state))do base=math.max(base,math.sqrt(actors.getActor(r.id).stats.basePlus[7])+1)end
     local model={}
     for _,r in ipairs(refs(party,enemies,state))do
      local q=ctx.query(r);local k=key(r);local t=state.tpb[k];local speed=math.sqrt(q.params[7])+1
      if not t then fail('E_BATTLE_SNAPSHOT','Missing TPB battler clock')end
      local automatic=q.traits.isAutoBattle()
      local row={key=k,movable=movable(q),alive=not q.hidden and not dead(q),automatic=automatic,
       input=r.kind=='actor' and movable(q) and q.restriction==0 and not automatic,
       acceleration=base==0 and 0 or speed/base/(battleSystem==1 and 240 or 60)}
      if t.state=='casting'then
       local delay=0;for _,slot in ipairs(state.slots[k] or {})do
        if slot and (slot.forcing or Actions.canUse({actionRef=slot.actionRef,subjectRef=r,inBattle=true},ctx).ok)then delay=delay+math.max(0,-Actions.describe(slot.actionRef).speed)end
       end
       row.castRequired=math.sqrt(delay)/speed
      end
      if r.kind=='enemy' and t.turnCount>state.turnCount then return false end
      model[#model+1]=row
     end
     tpbClockModel=model;endUnchanged=true
    end
    local input=false;for _,row in ipairs(tpbClockModel)do if row.input and state.tpb[row.key].state=='charged'then input=true;break end end
    local active=clock.timeActive~=false and (battleSystem==1 or not input)
    local changes={}
    if active and clock.frames>0 then
     for _,row in ipairs(tpbClockModel)do
      local t=state.tpb[row.key];local charge,cast,idle=t.chargeTime,t.castTime,t.idleTime
      if t.turnEnd or t.state=='ready' or row.movable and t.state=='charged' and row.automatic then return false end
      if row.movable then
       if t.state=='charging'then
        charge=math.min(1,charge+row.acceleration)
        if charge>=1 and (battleSystem==1 or not input)then return false end
       elseif t.state=='casting'then
        cast=cast+row.acceleration;if not row.castRequired or cast>=row.castRequired then return false end
       end
      end
      if row.alive and (not row.movable or t.state=='charged')then idle=idle+row.acceleration end
      if idle>=1 then return false end
      changes[#changes+1]={clock=t,charge=charge,cast=cast,idle=idle}
     end
    end
    local revision=number(state.revision+1)
    -- No callbacks after this point; publish only after every clock was checked.
    for _,change in ipairs(changes)do local t=change.clock;t.chargeTime,t.castTime,t.idleTime=change.charge,change.cast,change.idle end
    state.revision=revision;latest={};cached=nil
    return true
   end)
   busy=false;if not ok then error(result,0)end;return result
  end
  function B.isVisuSequence()return state.visuSequence~=nil end
  function B.advance(budget,clock)
   clock=copy(clock or {});for k in pairs(clock)do if k~='frames'and k~='timeActive'then fail('E_BATTLE_SHAPE','Unknown battle clock field')end end
   clock.frames=number(clock.frames==nil and 1 or clock.frames,0,1);if clock.timeActive~=nil and type(clock.timeActive)~='boolean'then fail('E_BATTLE_SHAPE','Invalid timeActive flag')end
   budget=number(budget==nil and 1 or budget,0,1000);local rows={}
   for _=1,budget do if state.phase=='input'or state.phase=='battleEnd'then break end
    if not clockOnly(clock)then local out=transact(function(s,ctx,p,a,e,rng,records)return advance(s,ctx,p,a,e,rng,records,clock)end);for _,row in ipairs(out.records)do rows[#rows+1]=row end end
    clock.frames=0
   end
   return{ok=true,records=rows}
  end
  function B.step(budget,clock)
   local out=B.advance(budget,clock);out.view=B.view();out.result=B.result();return out
  end
  if not restored then
   transact(function(s,ctx,p,a,e,rng,rows)
    local ps,ts=unitSnapshots(ctx,s,p,e,false);local function agility(list)local sum=0;for _,v in ipairs(list)do sum=sum+v.agi end;return math.max(1,sum/math.max(1,#list))end
    s.escapeRatio=.5*agility(ps)/agility(ts)
    -- Unit.onBattleStart sets _inBattle only after iterating members: Party
    -- therefore starts its reserves too, before input uses battleMembers.
    local allActors={};for _,id in ipairs(p.members())do allActors[#allActors+1]={kind='actor',id=id}end
    for side,list in ipairs({allActors,enemyRefs(e)})do for _,r in ipairs(list)do
     local base=0;for _,ar in ipairs(side==1 and allActors or actorRefs(p,s))do base=math.max(base,mv and 0 or math.sqrt(a.getActor(ar.id).stats.basePlus[7])+1)end
     -- Native Math.max(...[]) is -Infinity; finite speed / -Infinity is -0.
     local relative=mv and 0 or base==0 and -0.0 or (math.sqrt(ctx.query(r).params[7])+1)/base
     rng=lifecycle('battleStart',r,ctx,s,rng,rows,{advantageous=side==1 and s.preemptive or side==2 and s.surprise,tpbRelativeSpeed=relative})
    end end
    return rng
   end)
  end
  return B
 end
 return M
end
