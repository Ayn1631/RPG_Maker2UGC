-- MV/MZ finite damage math and numeric settlement; no mutation or battle hooks.
return function(deps)
 local M={};local formula=deps['contracts.formula'];local rng=deps['runtime.core.rng']
 local SAFE=9007199254740991
 local function fail(code,reason,path)error({severity='error',code=code,reason=reason,path=path,profile='mz-1.10.0'},0)end
 local function finite(v,path)
  if type(v)~='number' or v~=v or v==math.huge or v==-math.huge then fail('E_DAMAGE_NUMBER','Expected a finite number',path)end
  return v*1.0
 end
 local function integer(v,lo,hi,path)
  v=finite(v,path);if v%1~=0 or v<lo or v>hi then fail('E_DAMAGE_NUMBER','Integer outside supported range',path)end;return v
 end
 local function plain(v,path)
  if type(v)~='table' or getmetatable(v)~=nil then fail('E_DAMAGE_SHAPE','Expected a plain table',path)end
 end
 local function shape(v,keys,path)
  plain(v,path);local allowed={};for key in keys:gmatch('%S+')do allowed[key]=true;if rawget(v,key)==nil then fail('E_DAMAGE_SHAPE','Missing required field',path..'.'..key)end end
  for key in next,v do if not allowed[key]then fail('E_DAMAGE_SHAPE','Unknown field',path)end end
 end
 local function boolean(v,path)if type(v)~='boolean'then fail('E_DAMAGE_SHAPE','Expected boolean',path)end;return v end
 local function profile(v)if v~='mz-1.10.0' and v~='mv-1.5.1'then fail('E_DAMAGE_PROFILE','Unsupported damage profile','profile')end end
 local function kind(v)if type(v)~='number' or v%1~=0 or v<1 or v>6 then fail('E_DAMAGE_SHAPE','Damage type must be 1..6','type')end;return v end
 local function array(v,path)
  plain(v,path);local count=0;for key in next,v do integer(key,1,SAFE,path);count=count+1 end
  for i=1,count do if rawget(v,i)==nil then fail('E_DAMAGE_SHAPE','Array must be dense',path)end end;return count
 end
 local function round(v)
  if v==0 then return v end
  if v<0 and v>=-.5 then return -0.0 end
  local floor=math.floor(v);return v-floor<.5 and floor*1.0 or (floor+1.0)
 end
 function M.calculate(q)
  shape(q,'profile damage hitType critical context target attackElements rngState'..(q.visuCriticalBonus~=nil and ' visuCriticalBonus'or ''),'request');profile(q.profile)
  shape(q.damage,'type elementId variance formulaAST','damage');local dt=kind(q.damage.type)
  local hit=integer(q.hitType,0,2,'hitType');boolean(q.critical,'critical')
  local element=integer(q.damage.elementId,-1,SAFE,'damage.elementId');local variance=integer(q.damage.variance,0,100,'damage.variance')
  plain(q.context,'context');plain(q.rngState,'rngState')
  local target=q.target;shape(target,'pdr mdr rec grd guard elementRates','target')
  for _,key in ipairs({'pdr','mdr','rec','grd'})do finite(target[key],'target.'..key)end
  boolean(target.guard,'target.guard');plain(target.elementRates,'target.elementRates')
  for id,rate in next,target.elementRates do integer(id,0,SAFE,'target.elementRates');finite(rate,'target.elementRates')end
  local count=array(q.attackElements,'attackElements');for i=1,count do integer(q.attackElements[i],1,SAFE,'attackElements')end
  local function rate(id)
   local value=rawget(target.elementRates,id);if value==nil then fail('E_DAMAGE_SHAPE','Missing target element rate','target.elementRates')end;return value*1.0
  end
  local elementRate
  if element==-1 then
   elementRate=1.0
   if count>0 then elementRate=rate(q.attackElements[1]);for i=2,count do
    local nextRate=rate(q.attackElements[i])
    if nextRate>elementRate or (nextRate==0 and elementRate==0 and 1/nextRate==math.huge)then elementRate=nextRate end
   end end
  else elementRate=rate(element)end
  local random=rng.restore(q.rngState)
  local raw=formula.evaluate(q.damage.formulaAST,q.context)
  -- JS Math.max(-0, 0) is +0; sign is applied afterwards.
  local base=(raw>0 and raw or 0.0)*((dt==3 or dt==4) and -1.0 or 1.0)
  local value=finite(base*elementRate,'element')
  if hit==1 then value=finite(value*target.pdr,'physical')end
  if hit==2 then value=finite(value*target.mdr,'magical')end
  if base<0 then value=finite(value*target.rec,'recovery')end
  local afterRates=value
  if q.critical then value=finite(q.visuCriticalBonus~=nil and value*2.0+finite(q.visuCriticalBonus,'visuCriticalBonus')or value*3.0,'critical')end
  local afterCritical=value
  local amplitude=math.floor(math.max(finite(math.abs(value)*variance,'variance')/100.0,0))
  if amplitude>2147483646 then fail('E_DAMAGE_RANGE','Variance amplitude exceeds supported RNG integer bound','variance')end
  local first=random.nextInt(amplitude+1,'damage.variance.first')
  local second=random.nextInt(amplitude+1,'damage.variance.second')
  local offset=first*1.0+second-amplitude
  value=finite(value>=0 and value+offset or value-offset,'variance')
  local afterVariance=value
  if value>0 and target.guard then value=finite(value/finite(2.0*target.grd,'guard'),'guard')end
  local nominal=finite(round(value),'round')
  integer(nominal,-SAFE,SAFE,'nominal')
  return {base=base,elementRate=elementRate,afterRates=afterRates,afterCritical=afterCritical,amplitude=amplitude,
   varianceOffset=offset,afterVariance=afterVariance,afterGuard=value,nominal=nominal,drawsUsed=2,rngState=random.snapshot()}
 end
 local function resources(v,path)
  shape(v,'hp mp mhp mmp',path);local result={}
  result.mhp=integer(v.mhp,0,SAFE,path..'.mhp');result.mmp=integer(v.mmp,0,SAFE,path..'.mmp')
  result.hp=integer(v.hp,0,SAFE,path..'.hp');result.mp=integer(v.mp,-SAFE,SAFE,path..'.mp')
  return result
 end
 local function copy(v)return {hp=v.hp,mp=v.mp,mhp=v.mhp,mmp=v.mmp}end
 local function jsmin(a,b)
  if a==0 and b==0 then return (1/a==-math.huge or 1/b==-math.huge) and -0.0 or 0.0 end
  return math.min(a,b)
 end
 local function jsmax(a,b)
  if a==0 and b==0 then return (1/a==math.huge or 1/b==math.huge) and 0.0 or -0.0 end
  return math.max(a,b)
 end
 local function clamp(v,max)return jsmin(jsmax(v,0.0),max)end
 local function refreshResources(v)
  -- Numeric part of the native refresh called by either gainHp or gainMp.
  v.hp=clamp(v.hp,v.mhp);v.mp=clamp(v.mp,v.mmp)
 end
 function M.settle(q)
  shape(q,'profile type value target user sameEntity','settlement');profile(q.profile);local dt=kind(q.type)
  local nominal=integer(q.value,-SAFE,SAFE,'value');boolean(q.sameEntity,'sameEntity')
  local target=resources(q.target,'target');local user=resources(q.user,'user')
  if q.sameEntity then
   for _,key in ipairs({'hp','mp','mhp','mmp'})do if target[key]~=user[key]then fail('E_DAMAGE_SHAPE','Same entity snapshots must match','sameEntity')end end
   user=target
  end
  local beforeTarget=copy(target);local beforeUser=copy(user)
  local hp=dt==1 or dt==3 or dt==5;local drain=dt==5 or dt==6;local field=hp and 'hp' or 'mp'
  local applied=nominal
  if (hp and drain) or (not hp and dt~=4) then applied=jsmin(target[field],applied)end
  target[field]=target[field]-applied;refreshResources(target)
  local drainGain=0;local actualDrainGain=0
  if drain then
   drainGain=applied;local prior=user[field];user[field]=user[field]+applied;refreshResources(user);actualDrainGain=user[field]-prior
  end
  return {nominal=nominal,applied=applied,targetAfter=copy(target),userAfter=copy(user),
   targetDelta={hp=target.hp-beforeTarget.hp,mp=target.mp-beforeTarget.mp},userDelta={hp=user.hp-beforeUser.hp,mp=user.mp-beforeUser.mp},
   drainGain=drainGain,actualDrainGain=actualDrainGain,sourceSuccess=hp or applied~=0,onDamageValue=hp and applied>0 and applied or 0}
 end
 return M
end
