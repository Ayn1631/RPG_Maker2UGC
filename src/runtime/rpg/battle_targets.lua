-- Pure MZ 1.10.0 target decisions and turn-order speed draws.
-- Caller supplies current unit snapshots; this module never mutates authority.
return function(deps)
 local M={};local RNG=deps['runtime.core.rng'];local SAFE=9007199254740991;local LIMIT=100000
 local function fail(code,reason,path)error({severity='error',code=code,reason=reason,path=path,profile='mz-1.10.0'},0)end
 local function number(v,lo,hi,whole,path)
  if type(v)~='number' or v~=v or v==math.huge or v==-math.huge or v<(lo or -SAFE) or v>(hi or SAFE) or (whole and v%1~=0)then fail('E_BATTLE_TARGET_NUMBER','Expected a finite number in supported range',path)end
  return v*1.0
 end
 local function shape(v,required,optional,path)
  if type(v)~='table' or getmetatable(v)~=nil then fail('E_BATTLE_TARGET_SHAPE','Expected a plain table',path)end
  local allowed={};for key in required:gmatch('%S+')do allowed[key]=true;if rawget(v,key)==nil then fail('E_BATTLE_TARGET_SHAPE','Missing field '..key,path)end end
  for key in (optional or ''):gmatch('%S+')do allowed[key]=true end
  for key in next,v do if not allowed[key]then fail('E_BATTLE_TARGET_SHAPE','Unknown field',path)end end
 end
 local function boolean(v,path)if type(v)~='boolean'then fail('E_BATTLE_TARGET_SHAPE','Expected boolean',path)end;return v end
 local function dense(v,path)
  if type(v)~='table' or getmetatable(v)~=nil then fail('E_BATTLE_TARGET_SHAPE','Expected plain dense array',path)end
  local count,high=0,0;for key in next,v do number(key,1,LIMIT,true,path);count=count+1;high=math.max(high,key)end
  if count~=high then fail('E_BATTLE_TARGET_SHAPE','Array contains a gap',path)end;return count
 end
 local function battleId(v)if type(v)~='string' or #v<1 or #v>128 then fail('E_BATTLE_TARGET_REFERENCE','Invalid battle ID','battleId')end;return v end
 local function reference(v,id)
  if type(v)~='table' or getmetatable(v)~=nil then fail('E_BATTLE_TARGET_REFERENCE','Expected plain battler reference','ref')end
  if v.kind=='actor'then shape(v,'kind id','','ref');return{kind='actor',id=number(v.id,1,SAFE,true,'ref.id')}
  elseif v.kind=='enemy'then shape(v,'kind battleId troopSlot','','ref');battleId(v.battleId);if v.battleId~=id then fail('E_BATTLE_TARGET_REFERENCE','Cross-battle enemy reference','ref.battleId')end
   return{kind='enemy',battleId=id,troopSlot=number(v.troopSlot,1,LIMIT,true,'ref.troopSlot')}
  end;fail('E_BATTLE_TARGET_REFERENCE','Unknown battler reference kind','ref.kind')
 end
 local function key(r)return r.kind=='actor' and 'actor:'..string.format('%.0f',r.id) or 'enemy:'..r.battleId..':'..string.format('%.0f',r.troopSlot)end
 local function budget(v)
  local out={members=1000,targets=10000,draws=10000,actions=10000}
  if v~=nil then shape(v,'','members targets draws actions','budget');for k,x in next,v do out[k]=number(x,0,LIMIT,true,'budget.'..k)end end
  return out
 end
 local function bounded(n,max,path)if n>max then fail('E_BATTLE_TARGET_BUDGET','Operation budget exceeded',path)end end
 local function member(v,id,withActions)
  shape(v,'ref hidden dead tgr agi attackSpeed attackTimesAdd confusionLevel',withActions and 'actions' or '', 'member')
  local r={ref=reference(v.ref,id),hidden=boolean(v.hidden,'hidden'),dead=boolean(v.dead,'dead'),tgr=number(v.tgr,nil,nil,false,'tgr'),
   agi=number(v.agi,0,8589934568,false,'agi'),attackSpeed=number(v.attackSpeed,nil,nil,false,'attackSpeed'),
   attackTimesAdd=number(v.attackTimesAdd,0,SAFE,false,'attackTimesAdd'),confusionLevel=number(v.confusionLevel,0,3,true,'confusionLevel')}
  if withActions then dense(v.actions,'actions');r.actions=v.actions end;return r
 end
 local function units(party,troop,id,b,withActions)
  local pn,tn=dense(party,'party'),dense(troop,'troop');bounded(pn+tn,b.members,'members')
  local p,t,byRef={},{},{}
  for side,list in ipairs({party,troop})do
   for i,v in ipairs(list)do local s=member(v,id,withActions);if (side==1 and s.ref.kind~='actor')or(side==2 and s.ref.kind~='enemy')then fail('E_BATTLE_TARGET_REFERENCE','Battler belongs to wrong unit','member.ref')end
    local k=key(s.ref);if byRef[k]then fail('E_BATTLE_TARGET_REFERENCE','Duplicate battler reference','member.ref')end;byRef[k]=s;(side==1 and p or t)[i]=s
   end
  end;return p,t,byRef
 end
 local function cursor(state,b)
  local rng=RNG.restore(state);local start=rng.snapshot().draws;local used=0
  local function draw(upper,purpose)
   bounded(used+1,b.draws,'draws');local v=upper and rng.nextInt(upper,purpose)or rng.nextUnit(purpose);used=used+1;return v
  end
  return draw,function()local saved=rng.snapshot();return saved,saved.draws-start end
 end
 local function alive(s)return not s.hidden and not s.dead end
 local function dead(s)return not s.hidden and s.dead end
 local function filtered(unit,predicate)local out={};for _,s in ipairs(unit)do if predicate(s)then out[#out+1]=s end end;return out end
 local function randomTarget(unit,draw)
  local members=filtered(unit,alive);local sum=0.0;for _,s in ipairs(members)do sum=number(sum+s.tgr,nil,nil,false,'tgrSum')end
  local remaining=number(draw(nil,'battle.target.tgr')*sum,nil,nil,false,'tgrRand');local target
  -- Source continues subtracting after selection, including zero/negative TGR.
  for _,s in ipairs(members)do remaining=number(remaining-s.tgr,nil,nil,false,'tgrRand');if remaining<=0 and not target then target=s end end
  return target
 end
 local function smooth(unit,index,predicate)
  local chosen=unit[math.max(0,index)+1];if chosen and predicate(chosen)then return chosen end
  for _,s in ipairs(unit)do if predicate(s)then return s end end
 end
 local function targetAction(v)
  shape(v,'scope repeats isAttack targetIndex forcing','','action')
  return{scope=number(v.scope,0,14,true,'action.scope'),repeats=number(v.repeats,0,SAFE,false,'action.repeats'),
   isAttack=boolean(v.isAttack,'action.isAttack'),targetIndex=number(v.targetIndex,-1,LIMIT,true,'action.targetIndex'),forcing=boolean(v.forcing,'action.forcing')}
 end
 local function targetContext(request)
  shape(request,'battleId subject party troop action rngState','budget subjectSnapshot','request');local id=battleId(request.battleId);local b=budget(request.budget)
  local p,t,byRef=units(request.party,request.troop,id,b,false);local ref=reference(request.subject,id);local subject=byRef[key(ref)];local a=targetAction(request.action)
  if request.subjectSnapshot~=nil then
   if not a.forcing then fail('E_BATTLE_TARGET_REFERENCE','External subject snapshot requires forcing','subjectSnapshot')end
   local supplied=member(request.subjectSnapshot,id,false)
   if key(supplied.ref)~=key(ref)then fail('E_BATTLE_TARGET_REFERENCE','Subject snapshot reference mismatch','subjectSnapshot.ref')end
   if subject then for k,v in pairs(subject)do if k~='ref'and supplied[k]~=v then fail('E_BATTLE_TARGET_REFERENCE','Subject snapshot differs from unit member','subjectSnapshot.'..k)end end
   else
    if ref.kind~='actor'then fail('E_BATTLE_TARGET_REFERENCE','Only an actor can be outside battle units','subjectSnapshot.ref')end
    bounded(#p+#t+1,b.members,'members');subject=supplied
   end
  end
  if not subject then fail('E_BATTLE_TARGET_REFERENCE','Subject is not a unit member','subject')end
  return id,b,p,t,ref,subject,a
 end
 function M.makeTargets(request)
  local id,b,p,t,ref,subject,a=targetContext(request);local repeats=math.floor(number(a.repeats+(a.isAttack and subject.attackTimesAdd or 0.0),0,SAFE,false,'repeats'))
  local draw,finish=cursor(request.rngState,b);local friends=ref.kind=='actor' and p or t;local opponents=ref.kind=='actor' and t or p;local base={}
  local function push(s)if s then base[#base+1]=s end end
  local function all(list)for _,s in ipairs(list)do push(s)end end
  local scope,index=a.scope,a.targetIndex
  if not a.forcing and not subject.hidden and subject.confusionLevel>0 then
   local level=subject.confusionLevel;local unit
   if level==1 then unit=opponents elseif level==2 then unit=draw(2,'battle.target.confusionSide')==0 and opponents or friends else unit=friends end
   push(randomTarget(unit,draw))
  elseif scope==14 then all(filtered(opponents,alive));all(filtered(friends,alive))
  elseif scope>=1 and scope<=6 then
   if scope>=3 then for _=1,scope-2 do push(randomTarget(opponents,draw))end
   elseif scope==1 then if index<0 then push(randomTarget(opponents,draw))else push(smooth(opponents,index,alive))end
   else all(filtered(opponents,alive))end
  elseif scope>=7 and scope<=13 then
   if scope==11 then push(subject)
   elseif scope==9 then push(smooth(friends,index,dead))
   elseif scope==10 then all(filtered(friends,dead))
   elseif scope==7 then if index<0 then push(randomTarget(friends,draw))else push(smooth(friends,index,alive))end
   elseif scope==8 then all(filtered(friends,alive))
   elseif scope==12 then push(friends[index+1])
   else all(friends)end
  end
  -- Force floating multiplication before budgeting: texlua integer overflow must
  -- never turn an enormous repeat count into a small/negative allocation size.
  bounded(#base*(repeats*1.0),b.targets,'targets');local targets={}
  for _,s in ipairs(base)do for _=1,repeats do targets[#targets+1]=reference(s.ref,id)end end
  local state,used=finish();return{targets=targets,rngState=state,drawsUsed=used}
 end
 -- Native decideRandomTarget chooses one index even for all/random/user scopes.
 -- An absent target clears the action; false preserves that distinction from 0.
 function M.decideRandomTarget(request)
  local _,b,p,t,ref,_,a=targetContext(request);local draw,finish=cursor(request.rngState,b)
  local friends=ref.kind=='actor'and p or t;local opponents=ref.kind=='actor'and t or p;local unit,target
  if a.scope==9 or a.scope==10 then
   unit=friends;local choices=filtered(unit,dead);if #choices>0 then target=choices[draw(#choices,'battle.target.dead')+1]end
  else unit=a.scope>=7 and a.scope<=13 and friends or opponents;target=randomTarget(unit,draw)end
  local index=false;if target then for i,s in ipairs(unit)do if s==target then index=i-1;break end end end
  local state,used=finish();return{targetIndex=index,rngState=state,drawsUsed=used}
 end
 local function speedAction(v)
  shape(v,'speed isAttack','itemPresent','action');local present=v.itemPresent==nil and true or boolean(v.itemPresent,'action.itemPresent')
  if not present and v.isAttack then fail('E_BATTLE_TARGET_SHAPE','Missing item cannot be an attack','action')end
  return{speed=number(v.speed,nil,nil,false,'action.speed'),isAttack=boolean(v.isAttack,'action.isAttack'),itemPresent=present}
 end
 local function speed(subject,action,draw)
  local upper=math.floor(5.0+subject.agi/4.0);number(upper,1,2147483647,true,'speed.upper')
  local value=number(subject.agi+draw(upper,'battle.action.speed'),nil,nil,false,'speed')
  if action.itemPresent then value=number(value+action.speed,nil,nil,false,'speed')end
  if action.isAttack then value=number(value+subject.attackSpeed,nil,nil,false,'speed')end;return value
 end
 function M.actionSpeed(request)
  shape(request,'battleId subject action rngState','budget','request');local id=battleId(request.battleId);local b=budget(request.budget)
  local s=member(request.subject,id,false);bounded(1,b.actions,'actions');bounded(1,b.members,'members');local a=speedAction(request.action);local draw,finish=cursor(request.rngState,b);local value=speed(s,a,draw)
  local state,used=finish();return{speed=value,rngState=state,drawsUsed=used}
 end
 local function battlerSpeed(s,actions,draw)
  local value;for _,a in ipairs(actions)do local n=speed(s,a,draw);value=value and math.min(value,n)or n end
  -- Native Math.min(...[]) || 0 is +Infinity, not zero. Tag it for finite snapshots.
  if value==nil then return false,true end;return value,false
 end
 function M.makeSpeed(request)
  shape(request,'battleId subject actions rngState','budget','request');local id=battleId(request.battleId);local b=budget(request.budget)
  local s=member(request.subject,id,false);bounded(1,b.members,'members');bounded(dense(request.actions,'actions'),b.actions,'actions');local actions={};for i,a in ipairs(request.actions)do actions[i]=speedAction(a)end
  local draw,finish=cursor(request.rngState,b);local value,empty=battlerSpeed(s,actions,draw);local state,used=finish()
  return{speed=value,emptyActions=empty,rngState=state,drawsUsed=used}
 end
 function M.makeActionOrders(request)
  shape(request,'battleId party troop preemptive surprise rngState','budget allowRandomSpeed','request');local id=battleId(request.battleId);local b=budget(request.budget)
  boolean(request.preemptive,'preemptive');boolean(request.surprise,'surprise');local p,t=units(request.party,request.troop,id,b,true)
  local candidates,actions={},{};local count=0
  for side,list in ipairs({p,t})do for _,s in ipairs(list)do
   local prepared={};count=count+#s.actions;bounded(count,b.actions,'actions');for i,a in ipairs(s.actions)do prepared[i]=speedAction(a)end
   if (side==1 and not request.surprise)or(side==2 and not request.preemptive)then candidates[#candidates+1]=s;actions[#actions+1]=prepared end
  end end
  local draw,finish=cursor(request.rngState,b);if request.allowRandomSpeed~=nil then boolean(request.allowRandomSpeed,'allowRandomSpeed');if not request.allowRandomSpeed then draw=function()return 0 end end end;local speeds,sorted={},{}
  for i,s in ipairs(candidates)do local value,empty=battlerSpeed(s,actions[i],draw);local entry={ref=reference(s.ref,id),speed=value,emptyActions=empty};speeds[i]=entry;sorted[i]={entry=entry,index=i}end
  table.sort(sorted,function(a,c)
   local av,cv=a.entry,c.entry;if av.emptyActions~=cv.emptyActions then return av.emptyActions end
   if not av.emptyActions and av.speed~=cv.speed then return av.speed>cv.speed end;return a.index<c.index
  end)
  local order={};for i,s in ipairs(sorted)do order[i]=reference(s.entry.ref,id)end;local state,used=finish()
  return{order=order,speeds=speeds,rngState=state,drawsUsed=used}
 end
 return M
end
