-- MV/MZ action applicability/probability only. Returned work is pending, not executed.
return function(deps)
 local M={};local rng=deps['runtime.core.rng'];local SAFE=9007199254740991
 local function validators(origin)
  local function fail(code,reason,path)
   local err={severity='error',code=code,reason=reason,path=path,profile='mz-1.10.0'}
   for key,value in pairs(origin)do err[key]=value end;error(err,0)
  end
  local function plain(value,path)
   if type(value)~='table' or getmetatable(value)~=nil then fail('E_ACTION_SHAPE','Expected a plain table',path)end
  end
  local function shape(value,required,optional,path)
   plain(value,path);local keys={}
   for key in required:gmatch('%S+')do keys[key]=true;if rawget(value,key)==nil then fail('E_ACTION_SHAPE','Missing required field',path..'.'..key)end end
   for key in (optional or ''):gmatch('%S+')do keys[key]=true end
   for key in next,value do if not keys[key]then fail('E_ACTION_SHAPE','Unknown field',path)end end
  end
  local function number(value,path)
   if type(value)~='number' or value~=value or value==math.huge or value==-math.huge then fail('E_ACTION_NUMBER','Expected a finite number',path)end
   return value*1.0
  end
  local function integer(value,lo,hi,path)
   value=number(value,path);if value%1~=0 or value<lo or value>hi then fail('E_ACTION_NUMBER','Integer outside supported range',path)end;return value
  end
  local function boolean(value,path)if type(value)~='boolean'then fail('E_ACTION_SHAPE','Expected boolean',path)end end
  local function dense(value,path,length)
   plain(value,path);local count,highest=0,0
   for key in next,value do integer(key,1,100000,path);count=count+1;if key>highest then highest=key end end
   if count~=highest or (length and count~=length)then fail('E_ACTION_SHAPE','Expected a dense array of the required length',path)end
   return count
  end
  return {fail=fail,plain=plain,shape=shape,number=number,integer=integer,boolean=boolean,dense=dense}
 end
 local function validate(q,withRandom)
  local origin={};local v=validators(origin)
  v.plain(q,'request')
  if q.origin~=nil then
   v.shape(q.origin,'','file jsonPath skillId itemId','origin')
   for _,key in ipairs({'file','jsonPath','skillId','itemId'})do
    local value=rawget(q.origin,key)
    if value~=nil then
     if key=='file' or key=='jsonPath'then if type(value)~='string'then v.fail('E_ACTION_SHAPE','Origin text must be a string','origin.'..key)end
     else v.integer(value,1,SAFE,'origin.'..key)end
     origin[key]=value
    end
   end
  end
  v.shape(q,withRandom and 'profile inBattle action subject target rngState' or 'profile inBattle action target','origin','request')
  if q.profile~='mz-1.10.0' and q.profile~='mv-1.5.1'then v.fail('E_ACTION_PROFILE','Unsupported action gate profile','profile')end
  v.boolean(q.inBattle,'inBattle');local a=q.action
  v.shape(a,'scope hitType successRate damage effects','visuAccuracy','action')
  if a.visuAccuracy then v.shape(a.visuAccuracy,'boost isItem','','action.visuAccuracy');v.boolean(a.visuAccuracy.boost,'action.visuAccuracy.boost');v.boolean(a.visuAccuracy.isItem,'action.visuAccuracy.isItem')end
  v.integer(a.scope,0,q.profile=='mv-1.5.1'and 11 or 14,'action.scope');v.integer(a.hitType,0,2,'action.hitType');v.integer(a.successRate,0,100,'action.successRate')
  v.shape(a.damage,'type critical','','action.damage');v.integer(a.damage.type,0,6,'action.damage.type');v.boolean(a.damage.critical,'action.damage.critical')
  for i=1,v.dense(a.effects,'action.effects')do
   local e=a.effects[i];local p='action.effects['..i..']';v.shape(e,'code dataId value1 value2','',p)
   local code=v.integer(e.code,1,SAFE,p..'.code');v.number(e.value1,p..'.value1');v.number(e.value2,p..'.value2')
   if code==11 or code==12 or code==13 or code==41 then v.integer(e.dataId,0,0,p..'.dataId')
   elseif code==21 then v.integer(e.dataId,0,SAFE,p..'.dataId')
   elseif code==22 or code==43 or code==44 then v.integer(e.dataId,1,SAFE,p..'.dataId')
   elseif code==31 or code==32 or code==33 or code==34 or code==42 then v.integer(e.dataId,0,7,p..'.dataId')
   else v.fail('E_ACTION_SHAPE','Unsupported standard effect code',p..'.code')end
   if code==31 or code==32 then v.integer(e.value1,0,SAFE,p..'.value1')end
  end
  local t=q.target
  v.shape(t,'hidden isActor hp mhp mp mmp stateIds buffs learnedSkills'..(withRandom and ' eva mev cev' or ''),withRandom and '' or 'eva mev cev','target')
  v.boolean(t.hidden,'target.hidden');v.boolean(t.isActor,'target.isActor')
  -- Native equipment loss can leave resources above maxima until a later gain/refresh.
  v.integer(t.mhp,0,SAFE,'target.mhp');v.integer(t.mmp,0,SAFE,'target.mmp');v.integer(t.hp,0,SAFE,'target.hp');v.integer(t.mp,-SAFE,SAFE,'target.mp')
  for _,key in ipairs({'eva','mev','cev'})do if t[key]~=nil then v.number(t[key],'target.'..key)end end
  v.dense(t.buffs,'target.buffs',8);for i=1,8 do v.integer(t.buffs[i],-2,2,'target.buffs')end
  local function ids(values,path)
   local set={};for i=1,v.dense(values,path)do local id=v.integer(values[i],1,SAFE,path);if set[id]then v.fail('E_ACTION_SHAPE','Duplicate ID',path)end;set[id]=true end;return set
  end
  local states=ids(t.stateIds,'target.stateIds');local learned=ids(t.learnedSkills,'target.learnedSkills')
  if withRandom then v.shape(q.subject,'hit cri','isActor','subject');if q.subject.isActor~=nil or a.visuAccuracy then v.boolean(q.subject.isActor,'subject.isActor')end;v.number(q.subject.hit,'subject.hit');v.number(q.subject.cri,'subject.cri');v.plain(q.rngState,'rngState')end
  return v,states,learned
 end
 local function applicable(q,states,learned)
  local a,t=q.action,q.target;local scope=a.scope
  if q.profile=='mv-1.5.1'then
   if ((scope==9 or scope==10)~=(not t.hidden and states[1]==true))then return false end
  elseif (scope>=1 and scope<=8) or scope==11 or scope==14 then
   if t.hidden or states[1]then return false end
  elseif scope==9 or scope==10 then
   if t.hidden or not states[1]then return false end
  end
  if q.inBattle or q.profile=='mv-1.5.1'and scope>=1 and scope<=6 then return true end
  if a.damage.type==3 and t.hp<t.mhp then return true end
  if a.damage.type==4 and t.mp<t.mmp then return true end
  for _,e in ipairs(a.effects)do
   local code,id=e.code,e.dataId;local yes
   if code==11 then yes=t.hp<t.mhp or e.value1<0 or e.value2<0
   elseif code==12 then yes=t.mp<t.mmp or e.value1<0 or e.value2<0
   elseif code==21 then yes=not states[id]
   elseif code==22 then yes=states[id]==true
   elseif code==31 then yes=t.buffs[id+1]~=2
   elseif code==32 then yes=t.buffs[id+1]~=-2
   elseif code==33 then yes=t.buffs[id+1]>0
   elseif code==34 then yes=t.buffs[id+1]<0
   elseif code==43 then yes=t.isActor and not learned[id]
   else yes=true end
   if yes then return true end
  end
  return false
 end
 function M.testApply(q)
  local _,states,learned=validate(q,false);return applicable(q,states,learned)
 end
 function M.resolve(q)
  local v,states,learned=validate(q,true);local random=rng.restore(q.rngState)
  local a,t=q.action,q.target;local draws={}
  local out={used=applicable(q,states,learned),missed=false,evaded=false,criticalRolled=false,physical=a.hitType==1,drain=a.damage.type==5 or a.damage.type==6}
  local function draw(purpose,threshold,miss)
   threshold=v.number(threshold,purpose);local unit=random.nextUnit(purpose)
   local passed;if miss then passed=unit>=threshold else passed=unit<threshold end
   draws[#draws+1]={purpose=purpose,unit=unit,threshold=threshold,passed=passed,index=random.lastDraw().index};return passed
  end
  if out.used then
   local hit=a.successRate*.01;if out.physical then hit=v.number(hit*q.subject.hit,'hitRate')end
   if a.visuAccuracy then
    local boost=a.visuAccuracy.boost
    local userHit=boost and a.visuAccuracy.isItem and 1 or out.physical and (q.subject.hit+(boost and q.subject.isActor and .05 or 0))or 1
    local evade=0
    if q.subject.isActor~=t.isActor then evade=out.physical and (t.eva-(boost and not t.isActor and .05 or 0))or a.hitType==2 and t.mev or 0 end
    hit=v.number(a.successRate*.01*(userHit-evade),'visuHitRate')
   end
   out.missed=draw('action.hit',hit,true)
  end
  -- Native apply samples evade even when used is false.
  if not out.missed then local evade=a.visuAccuracy and 0 or a.hitType==1 and t.eva or (a.hitType==2 and t.mev or 0.0);out.evaded=draw('action.evade',evade,false)end
  out.isHit=out.used and not out.missed and not out.evaded
  out.damagePending=out.isHit and a.damage.type>0;out.effectsPending=out.isHit
  if out.damagePending then
   local critical=0.0
   if a.damage.critical then critical=v.number(q.subject.cri*v.number(1.0-t.cev,'criticalComplement'),'criticalRate')end
   out.criticalRolled=draw('action.critical',critical,false)
  end
  out.draws=draws;out.drawsUsed=#draws;out.rngState=random.snapshot();return out
 end
 return M
end
