-- MV/MZ action candidates. The owner commits battler/party/RNG changes together.
return function(deps)
 local Gate,Damage,Effects,RNG,Formula=deps['runtime.rpg.action_gate'],deps['runtime.rpg.damage'],deps['runtime.rpg.effects'],deps['runtime.core.rng'],deps['contracts.formula']
 local M={};local SAFE,LIMIT=9007199254740991,100000
 local function fail(code,why)error({severity='error',code=code,reason=why,profile='mz-1.10.0'},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_RESOLVER_SHAPE','Expected plain table')end end
 local function fields(v,required,optional)
  plain(v);local keys={};for k in required:gmatch('%S+')do keys[k]=true;if rawget(v,k)==nil then fail('E_RESOLVER_SHAPE','Missing '..k)end end
  for k in (optional or ''):gmatch('%S+')do keys[k]=true end;for k in next,v do if not keys[k]then fail('E_RESOLVER_SHAPE','Unknown field')end end
 end
 local function finite(v)if type(v)~='number'or v~=v or v==math.huge or v==-math.huge then fail('E_RESOLVER_NUMBER','Expected finite number')end;return v*1.0 end
 local function int(v,lo,hi)v=finite(v);if v%1~=0 or v<(lo or -SAFE)or v>(hi or SAFE)then fail('E_RESOLVER_NUMBER','Integer outside supported range')end;return v end
 local function dense(v)plain(v);local n,h=0,0;for k in next,v do int(k,1,LIMIT);n=n+1;h=math.max(h,k)end;if n~=h then fail('E_RESOLVER_SHAPE','Expected dense array')end;return n end
 local function copy(v,seen,depth,budget)
  if type(v)~='table'then if type(v)=='number'then return finite(v)end;if type(v)~='string'and type(v)~='boolean'and v~=nil then fail('E_RESOLVER_SHAPE','Executable data')end;return v end
  plain(v);seen=seen or {};depth=depth or 0;budget=budget or {left=LIMIT};if seen[v]or depth>64 then fail('E_RESOLVER_SHAPE','Cyclic data')end;seen[v]=true;local o={}
  for k,x in next,v do if type(k)=='number'then int(k)elseif type(k)~='string'then fail('E_RESOLVER_SHAPE','Invalid key')end;budget.left=budget.left-1;if budget.left<0 then fail('E_RESOLVER_BUDGET','Copy budget exceeded')end;o[k]=copy(x,seen,depth+1,budget)end;seen[v]=nil;return o
 end
 local function ref(r,action)
  plain(r)
  if action then fields(r,'kind id');if r.kind~='item'and r.kind~='skill'then fail('E_RESOLVER_REFERENCE','Action kind required')end;return{kind=r.kind,id=int(r.id,1)}end
  if r.kind=='actor'then fields(r,'kind id');return{kind=r.kind,id=int(r.id,1)}end
  if r.kind=='enemy'then fields(r,'kind battleId troopSlot');if type(r.battleId)~='string'or #r.battleId<1 or #r.battleId>128 then fail('E_RESOLVER_REFERENCE','Invalid battleId')end;return{kind=r.kind,battleId=r.battleId,troopSlot=int(r.troopSlot,1)}end
  fail('E_RESOLVER_REFERENCE','Battler kind required')
 end
 local function sameEntity(a,b)return a.kind==b.kind and (a.kind=='actor'and a.id==b.id or a.kind=='enemy'and a.battleId==b.battleId and a.troopSlot==b.troopSlot)end
 local function battleFlag(v)if type(v)~='boolean'then fail('E_RESOLVER_SHAPE','Explicit inBattle required')end end
 local function text(v,default)if v==nil then return default end;if type(v)~='string'then fail('E_RESOLVER_SHAPE','Expected metadata string')end;return v end
 local function numberDefault(v,default)if v==nil then return default end;return v end
 local function member(list,id)for _,x in ipairs(list)do if x==id then return true end end;return false end
 local function gateAction(a)local accuracy=a.visu and a.visu.accuracy;return{scope=a.scope,hitType=a.hitType,successRate=a.successRate,damage={type=a.damage.type,critical=a.damage.critical},effects=a.effects,
  visuAccuracy=accuracy and accuracy.improved and {boost=accuracy.boost,isItem=a.kind=='item'}or nil}end
 local function gateTarget(q)
  return{hidden=q.hidden,isActor=q.kind=='actor',hp=q.hp,mhp=q.params[1],mp=q.mp,mmp=q.params[2],stateIds=q.stateIds,buffs=q.buffs,learnedSkills=q.learnedSkills,
   eva=q.xparams[2],mev=q.xparams[5],cev=q.xparams[4]}
 end
 function M.prepare(defs,profile,options)
  plain(defs);defs=copy(defs,nil,nil,{left=1000000});if (profile~='mz-1.10.0' and profile~='mv-1.5.1')or defs.profile~=profile or defs.schemaVersion~=1 then fail('E_RESOLVER_PROFILE','MV/MZ schema 1 required')end
  local effects=Effects.prepare(defs,profile,options);local actions={item={},skill={}};local damageStates={}
  for _,s in ipairs(defs.states)do
   local metadata=s.sourceMeta and s.sourceMeta.unhandledFields or {};plain(metadata)
   local remove=s.removeByDamage;if remove==nil then remove=metadata.removeByDamage end;if remove==nil then remove=false end
   if type(remove)~='boolean'then fail('E_RESOLVER_SHAPE','Invalid removeByDamage')end
   local chance=s.chanceByDamage;if chance==nil then chance=metadata.chanceByDamage end;if chance==nil then chance=0 end
   damageStates[s.id]={removeByDamage=remove,chanceByDamage=int(chance,0,100)}
  end
  for _,kind in ipairs({'item','skill'})do for _,s in ipairs(kind=='item'and defs.items or defs.skills)do
   local metadata=s.sourceMeta and s.sourceMeta.unhandledFields or {};plain(metadata)
   local function meta(key)local value=s[key];if value==nil then value=metadata[key]end;return value end
   local a={kind=kind,id=int(s.id,1),animationId=int(numberDefault(meta('animationId'),0),-1),scope=int(s.scope,0,profile=='mv-1.5.1'and 11 or 14),hitType=int(s.hitType,0,2),successRate=int(s.successRate,0,100),
    speed=int(numberDefault(meta('speed'),0)),name=text(meta('name'),''),iconIndex=int(numberDefault(meta('iconIndex'),0),0),description=text(meta('description'),''),
    repeats=int(s.repeats,1,LIMIT),occasion=int(s.occasion,0,3),tpGain=int(s.tpGain,0),effects=copy(effects.actionsByKind[kind][s.id].effects)}
   fields(s.damage,'type elementId variance critical formulaAST');if type(s.damage.critical)~='boolean'then fail('E_RESOLVER_SHAPE','Invalid critical')end
   plain(s.damage.formulaAST);local ast=Formula.compile(s.damage.formulaAST.source,s.damage.formulaAST.origin)
   a.damage={type=int(s.damage.type,0,6),elementId=int(s.damage.elementId,-1),variance=int(s.damage.variance,0,100),critical=s.damage.critical,formulaAST=ast}
   if kind=='item'then if type(s.consumable)~='boolean'then fail('E_RESOLVER_SHAPE','Invalid consumable')end;a.consumable=s.consumable
   else a.mpCost=int(s.mpCost,0);a.tpCost=int(s.tpCost,0);a.stypeId=int(s.stypeId,0);a.requiredWtypeId1=int(s.requiredWtypeId1,0);a.requiredWtypeId2=int(s.requiredWtypeId2,0)end
   if s.visu then a.visu=copy(s.visu)end
   actions[kind][a.id]=a
  end end
  return{kind='r2u.action-catalog',schemaVersion=1,catalogVersion=1,profile=profile,actionsByKind=actions,effectsCatalog=effects,damageStatesById=damageStates}
 end
 function M.fromCompiledCatalog(catalog)
  fields(catalog,'kind schemaVersion catalogVersion profile actionsByKind effectsCatalog damageStatesById')
  if catalog.kind~='r2u.action-catalog'or catalog.schemaVersion~=1 or catalog.catalogVersion~=1 or (catalog.profile~='mz-1.10.0' and catalog.profile~='mv-1.5.1')then fail('E_RESOLVER_PROFILE','Invalid compiled action ABI')end
  plain(catalog.actionsByKind);plain(catalog.actionsByKind.item);plain(catalog.actionsByKind.skill);plain(catalog.damageStatesById)
  local effects=Effects.fromCompiledCatalog(catalog.effectsCatalog);local R={}
  local function action(r)local key=ref(r,true);local a=catalog.actionsByKind[key.kind][key.id];if not a then fail('E_RESOLVER_REFERENCE','Missing action ID')end;return a end
  local function context(ctx,names)
   plain(ctx);for name in names:gmatch('%S+')do if type(ctx[name])~='function'then fail('E_RESOLVER_CAPABILITY','Missing candidate '..name)end end
  end
  local function menu(inBattle)battleFlag(inBattle);if inBattle then fail('E_RESOLVER_UNSUPPORTED','Use prepared target API for battle scheduling')end end
  function R.describe(r)local a=action(r);return{kind=a.kind,id=a.id,scope=a.scope,animationId=a.animationId or 0,repeats=a.repeats,occasion=a.occasion,speed=a.speed,name=a.name,iconIndex=a.iconIndex,description=a.description,hitType=a.hitType,stypeId=a.stypeId or 0,mpCost=a.mpCost or 0,tpCost=a.tpCost or 0,visuSequence=a.visu and a.visu.sequence~=nil or false,visuCosts=a.visu and copy(a.visu.costs),commandText=a.visu and a.visu['Command Text']}end
  function R.visuSequenceStep(r,pc)local a=action(r);int(pc,1);return a.visu and a.visu.sequence and copy(a.visu.sequence[pc])end
  function R.canApply(q,ctx)
   fields(q,'actionRef targetRef inBattle');battleFlag(q.inBattle);context(ctx,'query');local a=action(q.actionRef);local target=ctx.query(ref(q.targetRef,false))
   return Gate.testApply({profile=catalog.profile,inBattle=q.inBattle,action=gateAction(a),target=gateTarget(target)})
  end
  function R.canUse(q,ctx)
   fields(q,'actionRef subjectRef inBattle');battleFlag(q.inBattle);context(ctx,'query');local a=action(q.actionRef);local subject=ref(q.subjectRef,false);local s=ctx.query(subject)
   local cost={mp=0,tp=0,item=0};local function no(reason)return{ok=false,reason=reason,cost=cost}end
   -- Display cost is independent of usability (occasion, life state, seal,
   -- resources). Payment remains gated by the successful result below.
   if a.kind=='skill'then cost.mp=int(math.floor(finite(a.mpCost*s.sparams[5])),0);cost.tp=a.tpCost end
   if a.visu and a.visu.costs then local v=a.visu.costs;cost.hp=math.ceil(s.params[1]*(v.hpRate or 0));cost.gold=v.gold or 0;cost.potion=subject.kind=='actor'and v.item and v.item.amount or 0;cost.potionId=v.item and v.item.id or 7 end
   if q.inBattle then context(ctx,'isBattleMember');if not ctx.isBattleMember(subject)then return no('subject')end
   else context(ctx,'members');local members=ctx.members();dense(members);if subject.kind~='actor'or not member(members,subject.id)then return no('subject')end end
   if q.inBattle and subject.kind=='actor'then for _,effect in ipairs(a.effects)do if effect.code==41 then context(ctx,'canEscape');local allowed=ctx.canEscape();if type(allowed)~='boolean'then fail('E_RESOLVER_SHAPE','canEscape must return boolean')end;if not allowed then return no('escape')end;break end end end
   if s.hidden or s.restriction>=4 then return no('subject')end
   if a.occasion~=0 and a.occasion~=(q.inBattle and 1 or 2)then return no('occasion')end
   if not q.inBattle and a.scope>=1 and a.scope<=6 then return no('scope')end
   if a.kind=='item'then context(ctx,'count');cost.item=a.consumable and 1 or 0;if ctx.count('item',a.id)<1 then return no('inventory')end
   else
    if s.traits.isSkillSealed(a.id)or s.traits.isSkillTypeSealed(a.stypeId)then return no('seal')end
    if subject.kind=='actor'and (a.requiredWtypeId1~=0 or a.requiredWtypeId2~=0)then if not (a.requiredWtypeId1>0 and member(s.weaponTypes,a.requiredWtypeId1))and not (a.requiredWtypeId2>0 and member(s.weaponTypes,a.requiredWtypeId2))then return no('weapon')end end
    if s.mp<cost.mp or s.tp<cost.tp or cost.hp and cost.hp>0 and s.hp<=cost.hp then return no('resources')end
    if (cost.gold or 0)>0 then context(ctx,'gold');if ctx.gold()<cost.gold then return no('gold')end end
    if (cost.potion or 0)>0 then context(ctx,'count');if ctx.count('item',cost.potionId)<cost.potion then return no('inventory')end end
   end
   return{ok=true,cost=cost}
  end
  function R.pay(q,ctx)
   fields(q,'actionRef subjectRef inBattle rngState','forcing');battleFlag(q.inBattle);if q.forcing~=nil then battleFlag(q.forcing)end;local a=action(q.actionRef);local subject=ref(q.subjectRef,false)
   local rng=RNG.restore(q.rngState).snapshot();local usable
   if q.forcing then
    if not q.inBattle or a.kind~='skill'then fail('E_RESOLVER_UNSUPPORTED','Forced payment requires a battle skill')end
    context(ctx,'query');local s=ctx.query(subject);plain(s);plain(s.sparams)
    usable={ok=true,cost={mp=int(math.floor(finite(a.mpCost*finite(s.sparams[5]))),0),tp=a.tpCost,item=0}}
   else usable=R.canUse({actionRef=q.actionRef,subjectRef=subject,inBattle=q.inBattle},ctx)end
   if not usable.ok then usable.rngState=rng;return usable end
   if q.forcing and a.visu and a.visu.costs then local v=a.visu.costs;usable.cost.hp=math.ceil(ctx.query(subject).params[1]*(v.hpRate or 0));usable.cost.gold=v.gold or 0;usable.cost.potion=subject.kind=='actor'and v.item and v.item.amount or 0;usable.cost.potionId=v.item and v.item.id or 7 end
   if a.kind=='item'then context(ctx,'consumeItem');if not ctx.consumeItem(a.id)then return{ok=false,reason='inventory',cost=usable.cost,rngState=rng}end
   else context(ctx,'paySkillCost');rng=ctx.paySkillCost(subject,usable.cost.mp,usable.cost.tp,rng,q.forcing==true);rng=RNG.restore(rng).snapshot()end
   if (usable.cost.hp or 0)>0 then context(ctx,'apply');local out=ctx.apply(subject,{op='gainHp',value=-usable.cost.hp},rng);rng=out.rngState end
   if (usable.cost.gold or 0)>0 then context(ctx,'gainGold');ctx.gainGold(-usable.cost.gold)end
   if (usable.cost.potion or 0)>0 then context(ctx,'gainItem');ctx.gainItem('item',usable.cost.potionId,-usable.cost.potion,false)end
   return{ok=true,cost=copy(usable.cost),rngState=copy(rng)}
  end
  function R.applyGlobal(actionRef)return effects.applyGlobal(actionRef)end
  local function damageValue(a,s,t,variables,rng,critical)
   local elements=s.traits.attackElements();local rates={};local elementId=a.damage.elementId
   if a.visu then local list=elementId>=0 and {elementId}or elements;local rate,sign=1,1;for _,id in ipairs(list)do rate=rate*t.traits.elementRate(id);if a.damage.type~=3 and a.damage.type~=4 and member(t.absorbElements or {},id)then sign=-1 end end;rates[0]=rate*sign;elementId=0
   elseif elementId>=0 then rates[elementId]=t.traits.elementRate(elementId)else for _,id in ipairs(elements)do rates[id]=t.traits.elementRate(id)end end
   return Damage.calculate({profile=catalog.profile,damage={type=a.damage.type,elementId=elementId,variance=a.damage.variance,formulaAST=a.damage.formulaAST},hitType=a.hitType,critical=critical,
    visuCriticalBonus=a.visu and s.params[8]*s.xparams[3]or nil,context={a=s.formula,b=t.formula,v=variables},target={pdr=t.sparams[7],mdr=t.sparams[8],rec=t.sparams[3],grd=t.sparams[2],guard=t.guard,elementRates=rates},attackElements=elements,rngState=rng})
  end
  -- Native Game_Action.evaluate is a read-only estimate, not an action apply.
  -- Its all-target non-HP score is JS NaN; keep that comparison semantics in
  -- a finite, serializable result instead of converting it to a zero score.
  function R.evaluate(q,ctx)
   fields(q,'battleId actionRef subjectRef inBattle partyRefs troopRefs rngState','variables targetIndex');battleFlag(q.inBattle)
   if not q.inBattle then fail('E_RESOLVER_UNSUPPORTED','Battle evaluation requires inBattle=true')end
   if type(q.battleId)~='string'or #q.battleId<1 or #q.battleId>128 then fail('E_RESOLVER_REFERENCE','Invalid battle ID')end
   context(ctx,'query');local a=action(q.actionRef);local subject=ref(q.subjectRef,false)
   local rng=RNG.restore(q.rngState).snapshot();local initial=rng.draws;local variables=copy(q.variables or {});plain(variables)
   for id,value in next,variables do int(id,1);if type(value)~='boolean'then finite(value)end end
   local pn,tn=dense(q.partyRefs),dense(q.troopRefs);if pn+tn>1000 then fail('E_RESOLVER_BUDGET','Evaluation member budget exceeded')end
   local units,seen,subjectIndex={{},{}},{},nil
   for side,list in ipairs({q.partyRefs,q.troopRefs})do for i,r in ipairs(list)do
    local v=ref(r,false);if v.kind~=(side==1 and 'actor'or 'enemy')or v.kind=='enemy'and v.battleId~=q.battleId then fail('E_RESOLVER_REFERENCE','Evaluation unit reference mismatch')end
    local key=v.kind..':'..string.format('%.0f',v.id or v.troopSlot);if seen[key]then fail('E_RESOLVER_REFERENCE','Duplicate evaluation member')end;seen[key]=true
    units[side][i]={ref=v,index=i-1};if sameEntity(v,subject)then subjectIndex=i-1 end
   end end
   if subjectIndex==nil then fail('E_RESOLVER_REFERENCE','Evaluation subject is outside units')end
   local s=ctx.query(subject);local usable=R.canUse({actionRef=q.actionRef,subjectRef=subject,inBattle=true},ctx)
   local value,nan,targetIndex=0.0,false,int(q.targetIndex==nil and -1 or q.targetIndex,-1,LIMIT)
   local opponent=a.scope>=1 and a.scope<=6 or a.scope==14
   local all=a.scope==2 or a.scope==8 or a.scope==10 or a.scope==13 or a.scope==14
   local hp=a.damage.type==1 or a.damage.type==3 or a.damage.type==5
   local friends=units[subject.kind=='actor'and 1 or 2];local opponents=units[subject.kind=='actor'and 2 or 1]
   local candidates={}
   if usable.ok then
    if a.scope==11 then candidates[1]={ref=subject,index=subjectIndex}
    else for _,entry in ipairs(opponent and opponents or friends)do local t=ctx.query(entry.ref);local dead=member(t.stateIds,1);local wantsDead=not opponent and (a.scope==9 or a.scope==10)
     if not t.hidden and dead==wantsDead then candidates[#candidates+1]=entry end
    end end
   end
   for _,entry in ipairs(candidates)do
    if hp then local t=ctx.query(entry.ref);local d=damageValue(a,s,t,variables,rng,false);rng=d.rngState
     if ctx.damagePolicy then d.nominal=int(ctx.damagePolicy(subject.kind,d.nominal),-SAFE,SAFE)end
     local score=finite(opponent and d.nominal/math.max(t.hp,1)or math.min(-d.nominal,t.params[1]-t.hp)/t.params[1])
     if all then value=finite(value+score)elseif score>value then value=score;targetIndex=entry.index end
    elseif all then nan=true end
   end
   local isAttack=a.kind=='skill'and a.id==s.traits.attackSkillId()
   local repeats=int(math.floor(finite(a.repeats+(isAttack and s.traits.attackTimesAdd()or 0))),0)
   if not nan then value=finite(value*repeats);if value>0 then local random=RNG.restore(rng);value=finite(value+random.nextUnit('battle.auto.evaluate'));rng=random.snapshot()end end
   if nan then value=false end
   return{ok=true,value=value,notANumber=nan,targetIndex=targetIndex,rngState=copy(rng),drawsUsed=int(rng.draws-initial,0)}
  end
  local function singleTarget(q,ctx)
   fields(q,'actionRef subjectRef targetRef inBattle rngState','variables reflectionTargetRef forcedElements');battleFlag(q.inBattle);context(ctx,'query apply')
   local a=action(q.actionRef);if q.forcedElements then if #q.forcedElements~=1 then fail('E_VISU_GAMEPLAY','Source-scoped forced elements require one element')end;a=copy(a);a.damage.elementId=int(q.forcedElements[1],0)end;local subject=ref(q.subjectRef,false);local target=ref(q.targetRef,false)
   local reflectionTarget;if q.reflectionTargetRef~=nil then reflectionTarget=ref(q.reflectionTargetRef,false)end;if reflectionTarget then ctx.query(reflectionTarget)end
   local rng=RNG.restore(q.rngState).snapshot();local initial=rng.draws;local variables=copy(q.variables or {});plain(variables)
   for id,value in next,variables do int(id,1);if type(value)~='boolean'then finite(value)end end
   local out={ok=true,hooks={}}
   local function hooks(list,r)for _,h in ipairs(list)do local v=copy(h);v.battlerRef=copy(r);out.hooks[#out.hooks+1]=v end end
   local function add(list,id)if not member(list,id)then list[#list+1]=id end end
    local s,t=ctx.query(subject),ctx.query(target);local before={hp=t.hp,mp=t.mp,tp=t.tp}
    local g=Gate.resolve({profile=catalog.profile,inBattle=q.inBattle,action=gateAction(a),subject={isActor=s.kind=='actor',hit=s.xparams[1],cri=s.xparams[3]*(a.visu and 2^(s.buffs[8]or 0)or 1)},target=gateTarget(t),rngState=rng});rng=g.rngState
    local r={targetRef=copy(target),used=g.used,missed=g.missed,evaded=g.evaded,physical=g.physical,drain=g.drain,critical=g.criticalRolled,gateDraws=copy(g.draws),
     success=false,hpAffected=false,hpDamage=0,mpDamage=0,tpDamage=0,addedStates={},removedStates={},addedBuffs={},addedDebuffs={},removedBuffs={},drainActual=0,effectLogs={}}
    local function merge(b)for _,name in ipairs({'addedStates','removedStates','addedBuffs','addedDebuffs','removedBuffs'})do for _,id in ipairs(b[name])do add(r[name],id)end end end
    local function apply(to,op)local x=ctx.apply(to,op,rng);rng=x.rngState;hooks(x.hooks,to);if sameEntity(to,target)then merge(x.result)
     local field=op.op=='gainHp'and 'hpDamage'or op.op=='gainMp'and 'mpDamage'or op.op=='gainTp'and 'tpDamage'
     if field then r[field]=x.result[field];if field=='hpDamage'then r.hpAffected=x.result.hpAffected end end
    end;return x.result end
    if g.damagePending then
     local d=damageValue(a,s,t,variables,rng,g.criticalRolled);rng=d.rngState
     if ctx.damagePolicy then d.nominal=int(ctx.damagePolicy(subject.kind,d.nominal),-SAFE,SAFE)end
     if d.nominal==0 then r.critical=false end
     local hp=a.damage.type==1 or a.damage.type==3 or a.damage.type==5;local drain=a.damage.type==5 or a.damage.type==6;local value=d.nominal
     if drain or not hp and a.damage.type~=4 then value=math.min(hp and t.hp or t.mp,value)end
     r.success=hp or value~=0;local b=apply(target,{op=hp and 'gainHp'or 'gainMp',value=-value});r.hpAffected=b.hpAffected;r[hp and 'hpDamage'or 'mpDamage']=value
     if hp and value>0 then
      local current=ctx.query(target);local captured=copy(current.stateIds)
      for _,id in ipairs(captured)do local state=catalog.damageStatesById[id];if state.removeByDamage then local random=RNG.restore(rng);local roll=random.nextInt(100,'action:onDamage:state');rng=random.snapshot();if roll<state.chanceByDamage then apply(target,{op='removeState',stateId=id})end end end
      current=ctx.query(target);apply(target,{op='gainSilentTp',value=int(math.floor(finite(50*value/current.params[1]*current.sparams[6])),0)})
     end
     if drain then local gainTarget=reflectionTarget or subject;local u=ctx.query(gainTarget);apply(gainTarget,{op=hp and 'gainHp'or 'gainMp',value=value});local after=ctx.query(gainTarget);r.drainActual=(hp and after.hp-u.hp or after.mp-u.mp)end
    end
    if g.effectsPending then
     local e=effects.applyTarget({actionRef=q.actionRef,subjectRef=subject,targetRef=target,inBattle=q.inBattle,rngState=rng},ctx);rng=e.rngState
     for name in pairs(e.resultWrites)do r[name]=e.resultDelta[name]end;merge(e.resultDelta);r.effectLogs=copy(e.effectLogs);for _,h in ipairs(e.hooks)do out.hooks[#out.hooks+1]=copy(h)end
     local u=effects.applyUser({actionRef=q.actionRef,subjectRef=subject,rngState=rng},ctx);rng=u.rngState;for _,h in ipairs(u.hooks)do out.hooks[#out.hooks+1]=copy(h)end
    end
    local after=ctx.query(target);r.actualDelta={hp=after.hp-before.hp,mp=after.mp-before.mp,tp=after.tp-before.tp};out.result=r
   out.rngState=copy(rng);out.drawsUsed=int(rng.draws-initial,0);return out
  end
  function R.applyPreparedTarget(q,ctx)return singleTarget(q,ctx)end
  function R.resolve(q,ctx)
   fields(q,'actionRef subjectRef targetRefs inBattle rngState','variables');menu(q.inBattle);context(ctx,'query count members consumeItem apply')
   local a=action(q.actionRef);local subject=ref(q.subjectRef,false);if subject.kind~='actor'then fail('E_RESOLVER_UNSUPPORTED','Menu actor required')end;local targets=copy(q.targetRefs);local count=dense(targets)
   if count*math.max(#a.effects,1)>LIMIT then fail('E_RESOLVER_BUDGET','Action target/effect budget exceeded')end
   local rng=RNG.restore(q.rngState).snapshot();local initial=rng.draws;local variables=copy(q.variables or {});plain(variables)
   for id,value in next,variables do int(id,1);if type(value)~='boolean'then finite(value)end end
   local usable=R.canUse({actionRef=q.actionRef,subjectRef=subject,inBattle=false},ctx)
   if not usable.ok then usable.rngState=rng;return usable end
   local members=ctx.members();local base={};local one=a.scope==7 or a.scope==9 or a.scope==11 or a.scope==12
   if a.scope==0 then if count~=0 then fail('E_RESOLVER_TARGET','No-target action requires empty targets')end
   else
    if one then if count~=a.repeats then fail('E_RESOLVER_TARGET','Single target repeat count mismatch')end;base[1]=ref(targets[1],false).id
    else for _,id in ipairs(members)do base[#base+1]=id end end
    if #base*a.repeats~=count then fail('E_RESOLVER_TARGET','All-target repeat count mismatch')end
    for i,id in ipairs(base)do
     if not member(members,id)or a.scope==11 and id~=subject.id then fail('E_RESOLVER_TARGET','Invalid friendly target')end
     ctx.query({kind='actor',id=id}) -- Authority validation; Gate owns life applicability.
     for j=1,a.repeats do local r=ref(targets[(i-1)*a.repeats+j],false);if r.kind~='actor'or r.id~=id then fail('E_RESOLVER_TARGET','Target sequence mismatch')end end
    end
   end
   if count==0 and a.scope~=0 then return{ok=false,reason='target',cost=usable.cost,rngState=rng}end
   local applicable=a.scope==0;for _,r in ipairs(targets)do if R.canApply({actionRef=q.actionRef,targetRef=r,inBattle=false},ctx)then applicable=true end end
   if not applicable then return{ok=false,reason='applicability',cost=usable.cost,rngState=rng}end
   local paid=R.pay({actionRef=q.actionRef,subjectRef=subject,inBattle=false,rngState=rng},ctx);if not paid.ok then return paid end;rng=paid.rngState
   local out={ok=true,cost=copy(usable.cost),targetResults={},hooks={},commonEvents={}}
   for index,target in ipairs(targets)do
    local applied=singleTarget({actionRef=q.actionRef,subjectRef=subject,targetRef=target,inBattle=false,rngState=rng,variables=variables},ctx);rng=applied.rngState
    applied.result.index=index;out.targetResults[#out.targetResults+1]=applied.result;for _,h in ipairs(applied.hooks)do out.hooks[#out.hooks+1]=h end
   end
   out.commonEvents=effects.applyGlobal(q.actionRef);out.rngState=copy(rng);out.drawsUsed=int(rng.draws-initial,0);return out
  end
  return R
 end
 function M.new(defs,profile,options)return M.fromCompiledCatalog(M.prepare(defs,profile,options))end
 return M
end
