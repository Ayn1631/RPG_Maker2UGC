-- Database data compiler only; metadata/effects/enemy records are not programs.
return function(deps)
 local json,diagnostic,formula=deps['contracts.json'],deps['contracts.diagnostic'],deps['contracts.formula']
 local M={};local SAFE=9007199254740991
 local arrayMeta,objectMeta=getmetatable(json.array()),getmetatable(json.object())
 local names={'Actors','Classes','Skills','Items','Weapons','Armors','States','Enemies','Troops','CommonEvents'}
 local outputNames={Actors='actors',Classes='classes',Skills='skills',Items='items',Weapons='weapons',Armors='armors',States='states',Enemies='enemies',Troops='troops'}
 function M.compile(data)
  local diagnostics={};local file,path='source-index','$';local budget=0
  local function fail(reason,code,p)diagnostic.raise(code or 'E_RPG_SOURCE',reason,{file=file,jsonPath=p or path})end
  local function check(ok,reason,code,p)if not ok then fail(reason,code,p)end end
  local function plain(v)
   check(type(v)=='table' and not rawequal(v,json.null),'Expected a data table')
   local mt=getmetatable(v)
   check(mt==nil or ((rawequal(mt,arrayMeta) or rawequal(mt,objectMeta)) and next(mt)==nil and getmetatable(mt)==nil),'Untrusted or polluted JSON metatable')
  end
  local function finite(v)check(type(v)=='number' and v==v and v~=math.huge and v~=-math.huge,'Expected a finite number');return v*1.0 end
  local function int(v,lo,hi)finite(v);check(v%1==0 and v>=lo and v<=(hi or SAFE),'Integer outside supported range');return v end
  local function stringValue(v)check(type(v)=='string','Expected a string');return v end
  local function bool(v)check(type(v)=='boolean','Expected a boolean');return v end
  local function dense(v)
   plain(v);local count,highest=0,0
   for key in next,v do int(key,1);count=count+1;if key>highest then highest=key end end
   check(count==highest,'Array must be dense; use source null for empty ID slots');return count
  end
  local active={}
  local function copy(v,depth,keepNull)
   budget=budget+1;check(budget<=1000000 and depth<=64,'Source metadata exceeds data budget','E_RPG_BUDGET')
   if rawequal(v,json.null)then return keepNull and json.null or {kind='r2u.source-null'}end
   local kind=type(v)
   if kind=='string' or kind=='boolean'then return v elseif kind=='number'then return finite(v)end
   plain(v);check(not active[v],'Circular source data');active[v]=true;local out={};local count,highest,strings=0,0,false
   for key,value in next,v do
    check(type(key)=='string' or (type(key)=='number' and key>=1 and key<=SAFE and key%1==0),'Invalid source data key')
    if type(key)=='number'then count=count+1;highest=math.max(highest,key)else strings=true end
    local old=path;path=path..(type(key)=='number' and ('['..string.format('%.0f',key-1)..']') or ('.'..key));out[key]=copy(value,depth+1,keepNull);path=old
   end
   check(count==0 or (not strings and count==highest),'Mixed or sparse source container')
   active[v]=nil;return out
  end
  local function compile()
   plain(data);local mv=data.engineProfile=='mv-turn'
   check(mv or data.engineProfile=='mz-turn' or data.engineProfile=='mz-tpb-active' or data.engineProfile=='mz-tpb-wait','Unsupported RPG engine profile','E_RPG_PROFILE','$.engineProfile')
   check(data.sourceVersion==(mv and '1.5.1' or '1.10.0') or not mv and data.sourceVersion=='1.9.0' and data.visuGameplay~=nil,'Requires reviewed MV/MZ source version','E_RPG_PROFILE','$.sourceVersion');plain(data.database)
   local records,byId,presence={},{},{}
   for _,name in ipairs(names)do
    file='data/'..name..'.json';path='$';records[name]={};byId[name]={}
    local envelope=rawget(data.database,name);presence[name]=envelope~=nil
    if envelope~=nil then
     plain(envelope);local values=copy(rawget(envelope,'records'),0,true);local n=dense(values)
     if n>0 then check(rawequal(values[1],json.null),'Database slot zero must be null')end
     for i=2,n do
      local value=values[i];path='$['..(i-1)..']'
      if not rawequal(value,json.null)then plain(value);check(value.id==i-1,'Record ID must match source array slot','E_RPG_ID',path..'.id');int(value.id,1)
       records[name][#records[name]+1]=value;byId[name][value.id]=value
      end
     end
    end
   end
   local system=false;file='data/System.json';path='$'
   if data.database.System~=nil then plain(data.database.System);system=copy(data.database.System.records,0,true);plain(system)end
   presence.System=system~=false
   local function ref(name,id,zero)
    int(id,zero and 0 or 1);if zero and id==0 then return end
    check(byId[name][id]~=nil,'Missing '..name..' reference','E_RPG_REFERENCE');return byId[name][id]
   end
   local function dictionary(name,id,zero)
    int(id,zero and 0 or 1);check(system~=false and system[name]~=nil,'Missing System '..name,'E_RPG_REFERENCE')
    local n=dense(system[name]);check(id<n and type(system[name][id+1])=='string','Invalid System '..name..' ID','E_RPG_REFERENCE')
   end
   local function meta(record,handled)
    local used={};for key in handled:gmatch('%S+')do used[key]=true end
    local fields={};for key,value in pairs(record)do if not used[key]then fields[key]=copy(value,0,false)end end
    return {file=file,jsonPath=path,nonExecutable=true,unhandledFields=fields}
   end
   local function at(suffix,fn)
    local old=path;path=path..suffix;local value=fn();path=old;return value
   end
   local function traits(values)
    local n=dense(values);local out={}
    for i=1,n do out[i]=at('['..(i-1)..']',function()
     local v=values[i];plain(v);local code=at('.code',function()
      local c=int(v.code,1);check(not mv or c~=35,'MV 1.5.1 has no attack-skill trait','E_RPG_UNSUPPORTED');return c
     end)
     local id=at('.dataId',function()local id=int(v.dataId,0)
     if code==11 or code==31 then dictionary('elements',id,true)
     elseif code==12 or code==21 then int(id,0,7)
     elseif code==22 or code==23 then int(id,0,9)
     elseif code==13 or code==14 or code==32 then ref('States',id)
     elseif code==35 or code==43 or code==44 then ref('Skills',id)
     elseif code==41 or code==42 then dictionary('skillTypes',id)
     elseif code==51 then dictionary('weaponTypes',id)
     elseif code==52 then dictionary('armorTypes',id)
     elseif code==53 or code==54 then dictionary('equipTypes',id)
     elseif code==55 then int(id,0,1)
     elseif code==62 or code==63 then int(id,0,3)
     elseif code==64 then int(id,0,5)
     elseif code==33 or code==34 or code==61 then int(id,0,0)
     else fail('Unsupported trait feature code','E_RPG_UNSUPPORTED',path:sub(1,-8)..'.code')end
     return id end)
     local value=at('.value',function()return finite(v.value)end)
     for key in pairs(v)do check(key=='code' or key=='dataId' or key=='value','Unknown trait field','E_RPG_UNSUPPORTED')end
     return {code=code,dataId=id,value=value}
    end)end
    return out
   end
   local function effects(values)
    local n=dense(values);local out={}
    for i=1,n do out[i]=at('['..(i-1)..']',function()
     local v=values[i];plain(v);local code=at('.code',function()return int(v.code,1)end)
     local id=at('.dataId',function()local id=int(v.dataId,0)
     if code==11 or code==12 or code==13 or code==41 then int(id,0,0)
     elseif code==21 then ref('States',id,true)
     elseif code==22 then ref('States',id)
     elseif code==31 or code==32 or code==33 or code==34 or code==42 then int(id,0,7)
     elseif code==43 then ref('Skills',id)
     elseif code==44 then ref('CommonEvents',id)
     else fail('Unsupported effect code','E_RPG_UNSUPPORTED',path:sub(1,-8)..'.code')end;return id end)
     local v1=at('.value1',function()local n=finite(v.value1);if code==31 or code==32 then int(n,0)end;return n end)
     local v2=at('.value2',function()return finite(v.value2)end)
     for key in pairs(v)do check(key=='code' or key=='dataId' or key=='value1' or key=='value2','Unknown effect field','E_RPG_UNSUPPORTED')end
     return {code=code,dataId=id,value1=v1,value2=v2}
    end)end
    return out
   end
   local function numbers(values,count,minimum)
    check(dense(values)==count,'Unexpected numeric array length');local out={};for i=1,count do out[i]=at('['..(i-1)..']',function()return int(values[i],minimum)end)end;return out
   end
   local result={kind='r2u.rpg-data',schemaVersion=1,profile=mv and 'mv-1.5.1' or 'mz-1.10.0',engineProfile=data.engineProfile,sourceVersion=data.sourceVersion,system=false,presence=presence,
    capabilities={actorGrowthData=true,traitData=true,damageFormulaData=true,effectsData=true,enemyRuleData=true,effectsExecution=false,enemyAI=false,troopEvents=false,stateLifecycle=false,battleRuntime=false,sourceExtensions=false},
    incomplete={'effectsExecution','enemyAI','troopEvents','stateLifecycle','battleRuntime','sourceExtensions'}}
   for name,key in pairs(outputNames)do result[key]={}end
   for _,name in ipairs({'Classes','Actors','Skills','Items','Weapons','Armors','States','Enemies','Troops'})do if outputNames[name]then
    file='data/'..name..'.json'
    for _,v in ipairs(records[name])do
     path='$['..string.format('%.0f',v.id)..']';local out={id=v.id,name=at('.name',function()return stringValue(v.name)end)};local handled='id name'
     if v.visu~=nil then check(data.visuGameplay~=nil,'Visu metadata requires the explicit adapter');out.visu=copy(v.visu,0,false);handled=handled..' visu'end
     if name=='Actors' or name=='Classes' or name=='Weapons' or name=='Armors' or name=='States' or name=='Enemies'then
      out.traits=at('.traits',function()return traits(v.traits)end);handled=handled..' traits'
     end
     if name=='Actors'then
      out.classId=at('.classId',function()ref('Classes',v.classId);return v.classId end)
      out.initialLevel=at('.initialLevel',function()return int(v.initialLevel,1,99)end)
      out.maxLevel=at('.maxLevel',function()return int(v.maxLevel,out.initialLevel,99)end)
      out.equips=at('.equips',function()
       local n=dense(v.equips);local outEquips={};check(system~=false and system.equipTypes~=nil,'Missing equipment slot dictionary','E_RPG_REFERENCE');local slotCount=dense(system.equipTypes)-1
       check(n==slotCount,'Initial equipment count must match System slots')
       local slotType=0;local class=byId.Classes[v.classId]
       for _,owner in ipairs({v,class})do for _,tr in ipairs(owner.traits)do if tr.code==55 then int(tr.dataId,0,1);slotType=math.max(slotType,tr.dataId)end end end
       for i=1,n do outEquips[i]=at('['..(i-1)..']',function()local id=int(v.equips[i],0);local weapon=i==1 or (i==2 and slotType==1);ref(weapon and 'Weapons' or 'Armors',id,true);return id end)end
       return outEquips
      end)
      handled=handled..' classId initialLevel maxLevel equips'
     elseif name=='Classes'then
      out.expParams=at('.expParams',function()check(dense(v.expParams)==4,'EXP requires four parameters');local outExp={};for i=1,4 do outExp[i]=at('['..(i-1)..']',function()local n=finite(v.expParams[i]);check(n>=0 and n<=SAFE and (i~=4 or n>0),'Invalid EXP parameter');return n end)end;return outExp end)
      out.params=at('.params',function()check(dense(v.params)==8,'Class requires eight curves');local curves={};for i=1,8 do curves[i]=at('['..(i-1)..']',function()return numbers(v.params[i],100,0)end)end;return curves end)
      out.learnings=at('.learnings',function()local learn={};for i=1,dense(v.learnings)do learn[i]=at('['..(i-1)..']',function()local l=v.learnings[i];plain(l);local skillId=at('.skillId',function()ref('Skills',l.skillId);return l.skillId end);return {level=at('.level',function()return int(l.level,1,99)end),skillId=skillId,sourceMeta=meta(l,'level skillId')}end)end;return learn end)
      handled=handled..' expParams params learnings'
     elseif name=='Weapons' or name=='Armors'then
      out.params=at('.params',function()return numbers(v.params,8,-SAFE)end)
      out.etypeId=at('.etypeId',function()dictionary('equipTypes',v.etypeId);return v.etypeId end)
      local key=name=='Weapons' and 'wtypeId' or 'atypeId';out[key]=at('.'..key,function()dictionary(name=='Weapons' and 'weaponTypes' or 'armorTypes',v[key],true);return v[key]end)
      out.price=at('.price',function()return int(v.price,0)end);handled=handled..' params etypeId price '..key
      if name=='Weapons'then out.animationId=at('.animationId',function()return int(v.animationId,0)end);handled=handled..' animationId'end
     elseif name=='Enemies'then
      out.params=at('.params',function()return numbers(v.params,8,0)end)
      out.exp=at('.exp',function()return int(v.exp,0)end);out.gold=at('.gold',function()return int(v.gold,0)end)
      out.actions=at('.actions',function()
       local actions={}
       for i=1,dense(v.actions)do actions[i]=at('['..(i-1)..']',function()
        local a=v.actions[i];plain(a);local r={}
        r.skillId=at('.skillId',function()ref('Skills',a.skillId);return a.skillId end)
        r.rating=at('.rating',function()return int(a.rating,0)end)
        r.conditionType=at('.conditionType',function()int(a.conditionType,0);check(a.conditionType<=6,'Unsupported enemy condition type','E_RPG_UNSUPPORTED');return a.conditionType end)
        r.conditionParam1=at('.conditionParam1',function()
         local p=finite(a.conditionParam1);local c=r.conditionType
         if c==1 or c==5 then int(p,0)
         elseif c==2 or c==3 then check(p>=0 and p<=1,'Enemy ratio bound must be 0..1')
         elseif c==4 then ref('States',p)
         elseif c==6 then dictionary('switches',p)end;return p
        end)
        r.conditionParam2=at('.conditionParam2',function()
         local p=finite(a.conditionParam2);if r.conditionType==1 then int(p,0)elseif r.conditionType==2 or r.conditionType==3 then check(p>=0 and p<=1,'Enemy ratio bound must be 0..1')end;return p
        end)
        r.sourceMeta=meta(a,'skillId rating conditionType conditionParam1 conditionParam2');return r
       end)end
       return actions
      end)
      out.dropItems=at('.dropItems',function()
       local drops={}
       for i=1,dense(v.dropItems)do drops[i]=at('['..(i-1)..']',function()
        local d=v.dropItems[i];plain(d);local kind=at('.kind',function()return int(d.kind,0,3)end)
        local id=at('.dataId',function()if kind>0 then ref(({'Items','Weapons','Armors'})[kind],d.dataId)else int(d.dataId,0)end;return d.dataId end)
        local denominator=at('.denominator',function()return int(d.denominator,kind>0 and 1 or 0)end)
        return {kind=kind,dataId=id,denominator=denominator,sourceMeta=meta(d,'kind dataId denominator')}
       end)end
       return drops
      end)
      handled=handled..' params exp gold actions dropItems'
     elseif name=='Troops'then
      out.members=at('.members',function()
       local members={};for i=1,dense(v.members)do members[i]=at('['..(i-1)..']',function()
        local m=v.members[i];plain(m)
        return {enemyId=at('.enemyId',function()ref('Enemies',m.enemyId);return m.enemyId end),
         x=at('.x',function()return int(m.x,-SAFE)end),y=at('.y',function()return int(m.y,-SAFE)end),
         hidden=at('.hidden',function()return bool(m.hidden)end),sourceMeta=meta(m,'enemyId x y hidden')}
       end)end;return members
      end)
      handled=handled..' members'
     elseif name=='States'then
      out.priority=at('.priority',function()return int(v.priority,0)end)
      out.restriction=at('.restriction',function()return int(v.restriction,0,4)end)
      out.minTurns=at('.minTurns',function()return int(v.minTurns,0)end)
      out.maxTurns=at('.maxTurns',function()
       local maximum=int(v.maxTurns,0)
       check(1.0+math.max(maximum*1.0-out.minTurns,0)<=2147483647,'State duration variance exceeds the supported RNG range')
       return maximum
      end)
      out.stepsToRemove=at('.stepsToRemove',function()return int(v.stepsToRemove,0)end)
      out.removeByRestriction=at('.removeByRestriction',function()return bool(v.removeByRestriction)end)
      handled=handled..' priority restriction minTurns maxTurns stepsToRemove removeByRestriction'
     elseif name=='Skills' or name=='Items'then
      out.damage=at('.damage',function()
       local damage=v.damage;plain(damage);local dt=at('.type',function()return int(damage.type,0,6)end)
       local element=at('.elementId',function()int(damage.elementId,-1);if damage.elementId~=-1 then dictionary('elements',damage.elementId,true)end;return damage.elementId end)
       local origin={file=file,jsonPath=path..'.formula'};origin[name=='Skills' and 'skillId' or 'itemId']=v.id
       local ast=formula.compile(damage.formula,origin)
       for key in pairs(damage)do check(key=='type' or key=='elementId' or key=='critical' or key=='variance' or key=='formula','Unknown damage field','E_RPG_UNSUPPORTED')end
       return {type=dt,elementId=element,critical=at('.critical',function()return bool(damage.critical)end),variance=at('.variance',function()return int(damage.variance,0,100)end),formulaAST=ast}
      end)
      out.effects=at('.effects',function()return effects(v.effects)end)
      for key,range in pairs({scope={0,14},hitType={0,2},successRate={0,100},repeats={1,SAFE},speed={-SAFE,SAFE},tpGain={0,SAFE},occasion={0,3}})do out[key]=at('.'..key,function()
       local n=int(v[key],range[1],range[2]);if mv and key=='scope'then check(n<=11,'MV 1.5.1 has no MZ scope 12..14','E_RPG_UNSUPPORTED')end;return n
      end)end
      handled=handled..' damage effects scope hitType successRate repeats speed tpGain occasion'
      if name=='Skills'then
       for _,key in ipairs({'mpCost','tpCost'})do out[key]=at('.'..key,function()return int(v[key],0)end)end
       out.stypeId=at('.stypeId',function()dictionary('skillTypes',v.stypeId,true);return v.stypeId end)
       for _,key in ipairs({'requiredWtypeId1','requiredWtypeId2'})do out[key]=at('.'..key,function()dictionary('weaponTypes',v[key],true);return v[key]end)end
       handled=handled..' mpCost tpCost stypeId requiredWtypeId1 requiredWtypeId2'
      else out.itypeId=at('.itypeId',function()return int(v.itypeId,1,4)end);out.consumable=at('.consumable',function()return bool(v.consumable)end);out.price=at('.price',function()return int(v.price,0)end);handled=handled..' itypeId consumable price'end
     end
     out.sourceMeta=meta(v,handled);result[outputNames[name]][#result[outputNames[name]]+1]=out
    end
   end end
   file='data/System.json';path='$'
   if system~=false then
    local out={};local handled=''
    for _,key in ipairs({'elements','skillTypes','weaponTypes','armorTypes','equipTypes','switches'})do
     out[key]=at('.'..key,function()local a={};for i=1,dense(system[key])do a[i]=at('['..(i-1)..']',function()return stringValue(system[key][i])end)end;check(#a>=1,'System dictionary requires zero slot');return a end);handled=handled..' '..key
    end
    out.partyMembers=at('.partyMembers',function()local a={};for i=1,dense(system.partyMembers)do a[i]=at('['..(i-1)..']',function()ref('Actors',system.partyMembers[i]);return system.partyMembers[i]end)end;return a end)
    if mv then at('.battleSystem',function()check(rawget(system,'battleSystem')==nil,'MV 1.5.1 has no System battleSystem; foreign battle configuration is unsupported','E_RPG_UNSUPPORTED')end)
    else out.battleSystem=at('.battleSystem',function()return int(system.battleSystem,0,2)end)end
    handled=handled..' partyMembers battleSystem'
    for _,key in ipairs({'optExtraExp','optSlipDeath','optFloorDeath','optDisplayTp','optSideView'})do out[key]=at('.'..key,function()return bool(system[key])end);handled=handled..' '..key end
    out.sourceMeta=meta(system,handled);result.system=out
   end
   return result
  end
  local ok,value=pcall(compile)
  if ok then return {ok=true,rpg=value,diagnostics=diagnostics}end
  if diagnostic.is(value)then diagnostics[1]=value;return {ok=false,diagnostics=diagnostics}end
  error(value,0)
 end
 return M
end
