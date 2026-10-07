-- Pure MV/MZ enemy numbers, selection-stage actions and uncommitted loot candidates.
return function(deps)
 local M={};local T,RNG=deps['runtime.rpg.traits'],deps['runtime.core.rng'];local SAFE=9007199254740991;local LIMIT=100000
 local function fail(code,reason,path)error({severity='error',code=code,reason=reason,path=path,profile='mz-1.10.0'},0)end
 local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
 local function calculated(v,path)if not finite(v)then fail('E_ENEMY_NUMBER','Nonfinite intermediate calculation',path)end;return v*1.0 end
 local function num(v,lo,hi,whole,path)
  if not finite(v) or v<(lo or -SAFE) or v>(hi or SAFE) or (whole and v%1~=0)then fail('E_ENEMY_NUMBER','Number outside supported finite range',path)end;return v*1.0
 end
 local function plain(v,path)if type(v)~='table' or getmetatable(v)~=nil then fail('E_ENEMY_SHAPE','Expected a plain table',path)end end
 local function bool(v,path)if type(v)~='boolean'then fail('E_ENEMY_SHAPE','Expected boolean',path)end end
 local function dense(v,length,path)
  plain(v,path);local count,high=0,0;for k in next,v do num(k,1,LIMIT,true,path);count=count+1;high=math.max(high,k)end
  if count~=high or (length and length~=count)then fail('E_ENEMY_SHAPE','Expected a dense bounded array',path)end;return count
 end
 local function shape(v,required,optional,path)
  plain(v,path);local allowed={};for k in required:gmatch('%S+')do allowed[k]=true;if rawget(v,k)==nil then fail('E_ENEMY_SHAPE','Missing field',path..'.'..k)end end
  for k in (optional or ''):gmatch('%S+')do allowed[k]=true end;for k in next,v do if not allowed[k]then fail('E_ENEMY_SHAPE','Unknown field',path)end end
 end
 local function traitCall(fn,...)
  local ok,value=pcall(fn,...);if not ok then fail(type(value)=='table' and value.code=='E_TRAITS_NUMBER' and 'E_ENEMY_NUMBER' or 'E_ENEMY_SHAPE','Invalid trait data or arithmetic','traits')end;return value
 end
 local function round(v)
  num(v);if v==0 then return v end;local floor=math.floor(v);local r=v-floor<.5 and floor*1.0 or floor+1.0
  if r==0 and v<0 then r=-0.0 end;return num(r,nil,nil,true,'params')
 end
 function M.prepare(defs,profile)
  plain(defs,'definitions');if (profile~='mz-1.10.0' and profile~='mv-1.5.1') or defs.profile~=profile or defs.schemaVersion~=1 then fail('E_ENEMY_PROFILE','Requires schema 1 / MV 1.5.1 or MZ 1.10.0','profile')end
  local source,catalogs={},{}
  for _,name in ipairs({'enemies','states','skills','items','weapons','armors'})do
   dense(defs[name],nil,name);source[name]={};catalogs[name]={}
   for _,record in ipairs(defs[name])do plain(record,name);num(record.id,1,SAFE,true,name..'.id');if source[name][record.id]then fail('E_ENEMY_REFERENCE','Duplicate definition ID',name)end;source[name][record.id]=record end
  end
  local function ref(name,id)
   if not finite(id) or id%1~=0 or id<1 or id>SAFE or not source[name][id]then fail('E_ENEMY_REFERENCE','Missing '..name..' reference',name)end
   return catalogs[name][id] or source[name][id]
  end
  local switchCount=0
  if defs.system~=nil and defs.system~=false then
   plain(defs.system,'system');if defs.system.switches~=nil then switchCount=dense(defs.system.switches,nil,'system.switches')-1;for _,s in ipairs(defs.system.switches)do if type(s)~='string'then fail('E_ENEMY_SHAPE','Switch names must be strings','system.switches')end end end
  end
  local function switchId(id)num(id,1,SAFE,true,'switch');if id>switchCount then fail('E_ENEMY_REFERENCE','Missing switch definition','switch')end;return id end
  local traitCodes={};for code in ('11 12 13 14 21 22 23 31 32 33 34 35 41 42 43 44 51 52 53 54 55 61 62 63 64'):gmatch('%d+')do traitCodes[tonumber(code)]=true end
  local function traits(values)
   dense(values,nil,'traits');for _,value in ipairs(values)do shape(value,'code dataId value','','traits')end;local result=traitCall(T.new,{{traits=values}}).allTraits()
   for _,tr in ipairs(result)do
    local code,id=tr.code,tr.dataId;if not traitCodes[code]then fail('E_ENEMY_SHAPE','Unknown trait feature code','traits')end
    if code==13 or code==14 or code==32 then ref('states',id)
    elseif code==35 or code==43 or code==44 then ref('skills',id)
    elseif code==12 or code==21 then num(id,0,7,true,'traits.dataId')
    elseif code==22 or code==23 then num(id,0,9,true,'traits.dataId')
    elseif code==55 then num(id,0,1,true,'traits.dataId')
    elseif code==62 or code==63 then num(id,0,3,true,'traits.dataId')
    elseif code==64 then num(id,0,5,true,'traits.dataId')
    elseif code==33 or code==34 or code==61 then num(id,0,0,true,'traits.dataId')end
   end;return result
  end
  for id,s in pairs(source.skills)do catalogs.skills[id]={id=id,stypeId=num(s.stypeId,0,SAFE,true,'skill.stypeId'),mpCost=num(s.mpCost,0,SAFE,true,'skill.mpCost'),tpCost=num(s.tpCost,0,SAFE,true,'skill.tpCost'),occasion=num(s.occasion,0,3,true,'skill.occasion')}end
  for id,s in pairs(source.states)do catalogs.states[id]={id=id,restriction=num(s.restriction,0,4,true,'state.restriction'),traits=traits(s.traits)}end
  for id,s in pairs(source.enemies)do
   local e={id=id,params={},traits=traits(s.traits),exp=num(s.exp,0,SAFE,true,'enemy.exp'),gold=num(s.gold,0,SAFE,true,'enemy.gold'),actions={},dropItems={}}
   dense(s.params,8,'enemy.params');for i=1,8 do e.params[i]=num(s.params[i],0,SAFE,true,'enemy.params')end
   for i=1,dense(s.actions,nil,'enemy.actions')do
    local a=s.actions[i];shape(a,'skillId rating conditionType conditionParam1 conditionParam2','sourceMeta','enemy.action');local c=num(a.conditionType,0,SAFE,true,'conditionType');if c>6 then fail('E_ENEMY_SHAPE','Unsupported enemy condition','conditionType')end
    -- Unconsumed condition fields keep the converter's finite-number domain.
    -- Safe integer/rate/reference constraints apply only in their consuming branch.
    local p1,p2=calculated(a.conditionParam1,'conditionParam1'),calculated(a.conditionParam2,'conditionParam2');ref('skills',a.skillId)
    if c==1 then num(p1,0,SAFE,true,'conditionParam1');num(p2,0,SAFE,true,'conditionParam2')
    elseif c==2 or c==3 then num(p1,0,1,false,'conditionParam1');num(p2,0,1,false,'conditionParam2')
    elseif c==4 then ref('states',p1)
    elseif c==5 then num(p1,0,SAFE,true,'conditionParam1')
    elseif c==6 then switchId(p1)end
    e.actions[i]={skillId=a.skillId,rating=num(a.rating,0,SAFE,true,'rating'),conditionType=c,conditionParam1=p1,conditionParam2=p2}
   end
   for i=1,dense(s.dropItems,nil,'enemy.dropItems')do
    local d=s.dropItems[i];shape(d,'kind dataId denominator','sourceMeta','drop');local kind=num(d.kind,0,3,true,'drop.kind')
    if kind>0 then ref(({'items','weapons','armors'})[kind],d.dataId)else num(d.dataId,0,SAFE,true,'drop.dataId')end
    e.dropItems[i]={kind=kind,dataId=d.dataId,denominator=num(d.denominator,kind>0 and 1 or 0,SAFE,true,'drop.denominator')}
   end
   catalogs.enemies[id]=e
  end
  return {kind='r2u.enemy-rules-catalog',schemaVersion=1,catalogVersion=1,profile=profile,switchCount=switchCount,
   enemiesById=catalogs.enemies,statesById=catalogs.states,skillsById=catalogs.skills}
 end
 -- Compiled catalogs are private generated data. Detach once so caller aliases
 -- cannot change a prepared rule instance; queries never index raw definitions.
 local function detached(v,active,depth)
  if type(v)~='table'then
   if type(v)=='number'then calculated(v,'catalog')elseif type(v)~='string' and type(v)~='boolean' and type(v)~='nil'then fail('E_ENEMY_SHAPE','Executable compiled data','catalog')end;return v
  end
  plain(v,'catalog');active=active or {};depth=depth or 0
  if active[v] or depth>64 then fail('E_ENEMY_SHAPE','Cyclic or deeply nested compiled data','catalog')end
  active[v]=true;local out={};for k,x in next,v do if type(k)~='number' and type(k)~='string'then fail('E_ENEMY_SHAPE','Invalid compiled key','catalog')end;out[k]=detached(x,active,depth+1)end;active[v]=nil;return out
 end
 function M.fromCompiledCatalog(input)
  plain(input,'catalog')
  if (input.kind~='r2u.enemy-rules-catalog' and input.kind~='r2u.enemy-catalog') or input.schemaVersion~=1 or
   (input.catalogVersion~=1 and input.catalogVersion~=2) or (input.profile~='mz-1.10.0' and input.profile~='mv-1.5.1')then fail('E_ENEMY_PROFILE','Invalid compiled enemy catalog ABI','profile')end
  local catalog=detached(input);local mv=catalog.profile=='mv-1.5.1';local catalogs={enemies=catalog.enemiesById,states=catalog.statesById,skills=catalog.skillsById}
  for _,name in ipairs({'enemies','states','skills'})do plain(catalogs[name],name)end
  -- An empty raw switch-name array has count -1 after the index-zero slot.
  -- Preserve this historical prepare result; no positive ID can reference it.
  local switchCount=num(catalog.switchCount,-1,SAFE,true,'switchCount')
  local function switchId(id)num(id,1,SAFE,true,'switch');if id>switchCount then fail('E_ENEMY_REFERENCE','Missing switch definition','switch')end;return id end
  local function ref(name,id)
   if not finite(id) or id%1~=0 or id<1 or id>SAFE or not catalogs[name][id]then fail('E_ENEMY_REFERENCE','Missing '..name..' reference',name)end;return catalogs[name][id]
  end
  local function enemy(id)return ref('enemies',id)end
  local function context(id,c,selecting)
   shape(c,'hidden hp mp tp stateIds permanent buffs'..(selecting and ' inBattle turnCount partyHighestLevel switches' or ''),selecting and 'visu' or 'inBattle turnCount partyHighestLevel switches visu','context')
   bool(c.hidden,'hidden');num(c.hp,0,SAFE,true,'hp');num(c.mp,nil,SAFE,true,'mp');num(c.tp,nil,100,true,'tp');dense(c.permanent,8,'permanent');dense(c.buffs,8,'buffs')
   for i=1,8 do num(c.permanent[i],nil,nil,true,'permanent');num(c.buffs[i],-2,2,true,'buffs')end
   local e=enemy(id);local states,sources={},{};local restriction=0.0
   for i=1,dense(c.stateIds,nil,'stateIds')do local key=c.stateIds[i];local state=ref('states',key);if states[key]then fail('E_ENEMY_SHAPE','Duplicate state ID','stateIds')end;states[key]=true;sources[#sources+1]={traits=state.traits};restriction=math.max(restriction,state.restriction)end
   sources[#sources+1]={traits=e.traits};if c.visu then sources[#sources+1]={traits=c.visu.traits or {}}end;local tr=traitCall(T.new,sources);local switches={}
   if selecting then
    bool(c.inBattle,'inBattle');num(c.turnCount,0,SAFE,true,'turnCount');num(c.partyHighestLevel,0,SAFE,true,'partyHighestLevel')
    for i=1,dense(c.switches,nil,'switches')do local s=c.switches[i];shape(s,'id value','','switches');switchId(s.id);bool(s.value,'switch.value');if switches[s.id]~=nil then fail('E_ENEMY_SHAPE','Duplicate switch snapshot','switches')end;switches[s.id]=s.value end
    for _,a in ipairs(e.actions)do if a.conditionType==6 and switches[a.conditionParam1]==nil then fail('E_ENEMY_REFERENCE','Required switch snapshot missing','switches')end end
   end
   local out={base={},plus={},basePlus={},rates={},buffRates={},params={},xparams={},sparams={},restriction=restriction,canMove=not c.hidden and restriction<4}
   for p=1,8 do
    local base=e.params[p];local plus=c.permanent[p]*1.0;local combined=base+plus;if not mv then combined=math.max(0.0,combined)end;local rate=traitCall(tr.paramRate,p-1);local buff=c.buffs[p]*.25+1.0
    out.base[p],out.plus[p],out.basePlus[p],out.rates[p],out.buffRates[p]=base,plus,combined,rate,buff
    local value=calculated(mv and combined*(rate*buff)or combined*rate*buff,'params');local minimum=mv and (p==2 and 0 or 1)or(p==1 and 1 or 0)
    if mv then value=math.min(value,p==1 and 999999 or p==2 and 9999 or 999)end;out.params[p]=round(math.max(minimum,value))
   end
   for p=1,10 do out.xparams[p]=traitCall(tr.xparam,p-1);out.sparams[p]=traitCall(tr.sparam,p-1)end
   out.hpRate=c.hp/out.params[1];out.mpRate=out.params[2]>0 and c.mp/out.params[2] or 0.0
   return out,tr,e,states,switches
  end
  local R={}
  function R.stats(id,c)return (context(id,c,false))end
  function R.selectActions(id,c,rngState)
   local stats,tr,e,states,switches=context(id,c,true);local random=RNG.restore(rngState);local draws={}
   local out={phase='selection',actionCount=0,actionSlots={},validActionIndices={},weightedCandidates={},ratingZero=false}
   local function finish()out.draws=draws;out.drawsUsed=#draws;out.rngState=random.snapshot();return out end
   if not stats.canMove then return finish()end
   local count=1.0
   for i,p in ipairs(tr.actionPlusSet())do local purpose='enemy.actionPlus.'..i;local unit=random.nextUnit(purpose);local yes=unit<p;draws[#draws+1]={purpose=purpose,unit=unit,threshold=p,passed=yes,index=random.lastDraw().index};if yes then count=count+1.0 end end
   if count>LIMIT then fail('E_ENEMY_BUDGET','Action count exceeds supported bound','actionCount')end;out.actionCount=count;for i=1,count do out.actionSlots[i]=false end
   local function condition(a)
    local k,p1,p2=a.conditionType,a.conditionParam1,a.conditionParam2
    if k==1 then local n=c.turnCount*1.0;return p2==0 and n==p1 or p2~=0 and n>0 and n>=p1 and math.fmod(n,p2)==math.fmod(p1,p2)
    elseif k==2 then return stats.hpRate>=p1 and stats.hpRate<=p2
    elseif k==3 then return stats.mpRate>=p1 and stats.mpRate<=p2
    elseif k==4 then return states[p1]==true
    elseif k==5 then return c.partyHighestLevel>=p1
    elseif k==6 then return switches[p1]end;return true
   end
   local function usable(a)
    local skill=catalogs.skills[a.skillId];local occasion=skill.occasion
    if not (occasion==0 or (c.inBattle and occasion==1) or (not c.inBattle and occasion==2))then return false end
    if c.tp<skill.tpCost then return false end
    local cost=math.floor(calculated(skill.mpCost*stats.sparams[5],'mpCost'))
    return c.mp>=cost and not tr.isSkillSealed(skill.id) and not tr.isSkillTypeSealed(skill.stypeId)
   end
   local maximum
   for i,a in ipairs(e.actions)do if condition(a) and usable(a)then out.validActionIndices[#out.validActionIndices+1]=i;maximum=maximum and math.max(maximum,a.rating) or a.rating end end
   if maximum==nil then return finish()end
   out.ratingZero=maximum-3.0;local total=0.0
   for _,i in ipairs(out.validActionIndices)do local a=e.actions[i];if a.rating>out.ratingZero then local weight=a.rating-out.ratingZero;total=(total+a.rating)-out.ratingZero;out.weightedCandidates[#out.weightedCandidates+1]={sourceActionIndex=i,skillId=a.skillId,rating=a.rating,weight=weight}end end
   num(total,1,2147483647,true,'ratingWeight')
   for slot=1,count do
    local purpose='enemy.rating.'..slot;local value=random.nextInt(total,purpose);local last=random.lastDraw();draws[#draws+1]={purpose=purpose,unit=last.unit,index=last.index,upper=total,result=value}
    for _,candidate in ipairs(out.weightedCandidates)do value=value-candidate.weight;if value<0 then out.actionSlots[slot]={skillId=candidate.skillId,sourceActionIndex=candidate.sourceActionIndex,rating=candidate.rating};break end end
   end
   return finish()
  end
  function R.rollDrops(id,c,rngState)
   shape(c,'dropItemDouble','visu','dropsContext');bool(c.dropItemDouble,'dropItemDouble');local e=enemy(id);local random=RNG.restore(rngState);local rate=c.dropItemDouble and 2.0 or 1.0
   local v=c.visu or {};rate=rate*(v.rewardDrop or 1);local out={items={},baseExp=math.floor(e.exp*(v.rewardExp or 1)),baseGold=math.floor(e.gold*(v.rewardGold or 1)),draws={}}
   for i,d in ipairs(e.dropItems)do if d.kind>0 then
    local purpose='enemy.drop.'..i;local unit=random.nextUnit(purpose);local yes=unit*d.denominator<rate
    out.draws[#out.draws+1]={purpose=purpose,unit=unit,index=random.lastDraw().index,denominator=d.denominator,rate=rate,passed=yes}
    if yes then out.items[#out.items+1]={kind=({'item','weapon','armor'})[d.kind],id=d.dataId,sourceDropIndex=i}end
   end end
   out.drawsUsed=#out.draws;out.rngState=random.snapshot();return out
  end
  return R
 end
 function M.new(defs,profile)return M.fromCompiledCatalog(M.prepare(defs,profile))end
 return M
end
