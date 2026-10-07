-- Pure MV 1.5.1 / MZ 1.10 actor parameter/progression candidates. Party owns equipment.
return function(deps)
  local T=deps["runtime.rpg.traits"]
  local M={}
  local SAFE=9007199254740991
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
  local function num(v,min,max,whole)
    if not finite(v) or v<(min or -SAFE) or v>(max or SAFE) or whole and v%1~=0 then fail("E_ACTOR_NUMBER","Number outside finite supported range") end
    return v*1.0
  end
  local function id(v) num(v,1,SAFE,true);return v end
  local function plain(v)
    if type(v)~="table" or getmetatable(v)~=nil then fail("E_ACTOR_SHAPE","Actor IR requires plain tables") end
  end
  local function dense(v,length)
    plain(v);local count,highest=0,0
    for k in next,v do
      if not finite(k) or k%1~=0 or k<1 or k>SAFE then fail("E_ACTOR_SHAPE","Actor array keys must be positive safe integers") end
      count=count+1;if k>highest then highest=k end
    end
    if count~=highest or length and count~=length then fail("E_ACTOR_SHAPE","Expected dense actor array of the required length") end
    return count
  end
  local function array(v)
    local out={};for i,item in ipairs(v) do out[i]=item end;return out
  end
  local function round(v)
    if not finite(v) then fail("E_ACTOR_NUMBER","Nonfinite actor calculation") end
    if v==0 then return v end
    local base=math.floor(v);if v-base>=0.5 then base=base+1.0 end
    if base==0 and v<0 then return -0.0 end
    return num(base,nil,nil,true)
  end
  local function traitCall(fn,...)
    local ok,result=pcall(fn,...)
    if not ok then
      local code=type(result)=="table" and result.code=="E_TRAITS_NUMBER" and "E_ACTOR_NUMBER" or "E_ACTOR_SHAPE"
      fail(code,type(result)=="table" and result.reason or "Invalid actor traits")
    end
    return result
  end
  function M.prepare(definitions,profile)
    plain(definitions)
    local mv=profile=="mv-1.5.1"
    if not mv and profile~="mz-1.10.0" or definitions.profile~=profile or definitions.schemaVersion~=1 then fail("E_ACTOR_PROFILE","Only schema 1 / MV 1.5.1 or MZ 1.10.0 is verified") end
    local catalogs={}
    for _,name in ipairs({"actors","classes","weapons","armors","skills","states"}) do
      dense(definitions[name]);catalogs[name]={}
      for _,record in ipairs(definitions[name]) do
        plain(record);id(record.id)
        if catalogs[name][record.id] then fail("E_ACTOR_REFERENCE","Duplicate source definition") end
        catalogs[name][record.id]=record
      end
    end
    local function ref(name,key)
      id(key);local v=catalogs[name][key]
      if not v then fail("E_ACTOR_REFERENCE","Missing "..name.." reference") end
      return v
    end
    local function traits(v)
      dense(v)
      local copy=traitCall(T.new,{{traits=v}}).allTraits()
      for _,tr in ipairs(copy) do if tr.code==43 then ref("skills",tr.dataId) end end
      return copy
    end
    for _,name in ipairs({"actors","classes","weapons","armors","states"}) do
      for key,source in pairs(catalogs[name]) do
        local r={id=key,traits=traits(source.traits)}
        if name=="actors" then
          r.classId=id(source.classId);ref("classes",r.classId)
          r.maxLevel=num(source.maxLevel,1,99,true);r.initialLevel=num(source.initialLevel,1,r.maxLevel,true)
        elseif name=="classes" then
          dense(source.expParams,4);r.expParams={}
          for i,v in ipairs(source.expParams) do r.expParams[i]=num(v,0) end
          if r.expParams[4]==0 then fail("E_ACTOR_NUMBER","Experience acc_b must be positive") end
          dense(source.params,8);r.params={}
          for p,row in ipairs(source.params) do
            dense(row,100);r.params[p]={}
            for level,v in ipairs(row) do r.params[p][level]=num(v,0,SAFE,true) end
          end
          dense(source.learnings);r.learnings={}
          for _,learning in ipairs(source.learnings) do
            plain(learning);local level=num(learning.level,1,99,true);ref("skills",learning.skillId)
            r.learnings[#r.learnings+1]={level=level,skillId=learning.skillId}
          end
        elseif name=="weapons" or name=="armors" then
          dense(source.params,8);r.params={}
          for p,v in ipairs(source.params) do r.params[p]=num(v,nil,nil,true) end
        end
        catalogs[name][key]=r
      end
    end
    -- Skill identity only; no caller records are retained.
    for key in pairs(catalogs.skills) do catalogs.skills[key]={id=key} end
    return {kind='r2u.actor-catalog',schemaVersion=1,catalogVersion=1,profile=profile,
      actorsById=catalogs.actors,classesById=catalogs.classes,weaponsById=catalogs.weapons,
      armorsById=catalogs.armors,skillsById=catalogs.skills,statesById=catalogs.states}
  end
  -- Internal generated-program ABI. The converter owns validation and projection;
  -- binding only selects already prepared maps, without scanning source records.
  function M.fromCompiledCatalog(catalog)
    plain(catalog)
    local profile=catalog.profile;local mv=profile=='mv-1.5.1'
    if catalog.kind~='r2u.actor-catalog' or catalog.schemaVersion~=1 or catalog.catalogVersion~=1 and catalog.catalogVersion~=2 or
      not mv and profile~='mz-1.10.0' then fail('E_ACTOR_PROFILE','Invalid compiled actor catalog ABI') end
    local catalogs={actors=catalog.actorsById,classes=catalog.classesById,weapons=catalog.weaponsById,
      armors=catalog.armorsById,skills=catalog.skillsById,states=catalog.statesById}
    plain(catalogs.actors);plain(catalogs.classes);plain(catalogs.weapons)
    plain(catalogs.armors);plain(catalogs.skills);plain(catalogs.states)
    local function ref(name,key)
      id(key);local v=catalogs[name][key]
      if not v then fail('E_ACTOR_REFERENCE','Missing '..name..' reference') end
      return v
    end
    local R={}
    function R.expForLevel(classId,level)
      local c=ref("classes",classId);level=num(level,1,SAFE,true)
      local p=c.expParams
      local value=(p[1]*(level-1.0)^(0.9+p[3]/250.0)*level*(level+1.0))/(6.0+level^2.0/50.0/p[4])+(level-1.0)*p[2]
      return round(value)
    end
    local function validate(state)
      plain(state);local a=ref("actors",state.actorId);ref("classes",state.classId)
      num(state.level,1,a.maxLevel,true);dense(state.expByClass);dense(state.learnedSkills)
      local seen,current={}
      for _,entry in ipairs(state.expByClass) do
        plain(entry);ref("classes",entry.classId);num(entry.total,0,SAFE,true)
        if seen[entry.classId] then fail("E_ACTOR_SHAPE","Duplicate class experience") end
        seen[entry.classId]=true;if entry.classId==state.classId then current=entry.total end
      end
      if current==nil then fail("E_ACTOR_SHAPE","Current class experience is required") end
      seen={}
      for _,skill in ipairs(state.learnedSkills) do
        ref("skills",skill);if seen[skill] then fail("E_ACTOR_SHAPE","Duplicate learned skill") end;seen[skill]=true
      end
      return a
    end
    local function stateCopy(state)
      local out={actorId=state.actorId,classId=state.classId,level=state.level,learnedSkills=array(state.learnedSkills),expByClass={}}
      for i,entry in ipairs(state.expByClass) do out.expByClass[i]={classId=entry.classId,total=entry.total} end
      return out
    end
    local function learn(skills,key)
      for _,known in ipairs(skills) do if known==key then return end end
      skills[#skills+1]=key;table.sort(skills)
    end
    function R.initial(actorId)
      local a=ref("actors",actorId);local state={actorId=actorId,classId=a.classId,level=a.initialLevel,
        expByClass={{classId=a.classId,total=R.expForLevel(a.classId,a.initialLevel)}},learnedSkills={}}
      for _,entry in ipairs(ref("classes",a.classId).learnings) do if entry.level<=a.initialLevel then learn(state.learnedSkills,entry.skillId) end end
      return state
    end
    local function experience(state,classId,total)
      for _,entry in ipairs(state.expByClass) do
        if entry.classId==classId then if total~=nil then entry.total=total end;return entry.total end
      end
      if total~=nil then state.expByClass[#state.expByClass+1]={classId=classId,total=total} end
      return total or 0
    end
    local function transition(original,candidate,total)
      local oldExp=experience(original,original.classId);local a=ref("actors",candidate.actorId)
      experience(candidate,candidate.classId,total>0 and total or 0.0)
      total=experience(candidate,candidate.classId);local c=ref("classes",candidate.classId)
      while candidate.level<a.maxLevel and total>=R.expForLevel(candidate.classId,candidate.level+1.0) do
        candidate.level=candidate.level+1.0
        for _,entry in ipairs(c.learnings) do if entry.level==candidate.level then learn(candidate.learnedSkills,entry.skillId) end end
      end
      while candidate.level>1 and total<R.expForLevel(candidate.classId,candidate.level) do candidate.level=candidate.level-1.0 end
      local known={};for _,skill in ipairs(original.learnedSkills) do known[skill]=true end
      local added={};for _,skill in ipairs(candidate.learnedSkills) do if not known[skill] then added[#added+1]=skill end end
      return {state=candidate,delta={levelFrom=original.level,levelTo=candidate.level,classFrom=original.classId,classTo=candidate.classId,
        expFrom=oldExp,expTo=total,learnedSkillsAdded=added}}
    end
    function R.changeExp(state,total) validate(state);num(total,nil,nil,true);return transition(state,stateCopy(state),total*1.0) end
    function R.changeLevel(state,level)
      local a=validate(state);level=num(level,nil,nil,true);level=math.max(1.0,math.min(a.maxLevel,level))
      return transition(state,stateCopy(state),R.expForLevel(state.classId,level))
    end
    function R.changeClass(state,classId,keepExp)
      validate(state);ref("classes",classId)
      if type(keepExp)~="boolean" then fail("E_ACTOR_SHAPE","keepExp must be boolean") end
      local candidate=stateCopy(state)
      if keepExp then experience(candidate,classId,experience(state,state.classId)) end
      candidate.classId=classId
      -- MV does not reset the level before changeExp; only actual levelUp calls
      -- learn target-class skills. MZ rebuilds target-class levels from zero.
      if not mv then candidate.level=0 end
      return transition(state,candidate,experience(candidate,classId))
    end
    function R.progression(state)
      local a=validate(state);local current=experience(state,state.classId);local maximum=state.level==a.maxLevel
      local nextExp=not maximum and R.expForLevel(state.classId,state.level+1.0) or false
      return {currentExp=current,maxLevel=a.maxLevel,isMaxLevel=maximum,nextLevelExp=nextExp,
        expRemaining=maximum and 0 or num(nextExp-current,nil,nil,true)}
    end
    local function context(state,ctx)
      validate(state);plain(ctx);dense(ctx.permanent,8);dense(ctx.buffs,8);dense(ctx.equipment);dense(ctx.stateIds)
      num(ctx.hp,0,SAFE,true);num(ctx.mp,nil,SAFE,true)
      for _,v in ipairs(ctx.permanent) do num(v,nil,nil,true) end
      for _,v in ipairs(ctx.buffs) do num(v,-2,2,true) end
      local sources={{traits=ref("actors",state.actorId).traits},{traits=ref("classes",state.classId).traits}}
      local equipment={}
      for _,entry in ipairs(ctx.equipment) do
        if entry~=false then
          plain(entry)
          if entry.kind~="weapon" and entry.kind~="armor" then fail("E_ACTOR_SHAPE","Invalid equipment kind") end
          local r=ref(entry.kind=="weapon" and "weapons" or "armors",entry.id)
          equipment[#equipment+1]=r;sources[#sources+1]={traits=r.traits}
        end
      end
      local seen={}
      for _,key in ipairs(ctx.stateIds) do
        local r=ref("states",key);if seen[key] then fail("E_ACTOR_SHAPE","Duplicate state ID") end
        seen[key]=true
      end
      -- Native Game_BattlerBase.traitObjects supplies states before Actor/Class/equips.
      local ordered={};for _,key in ipairs(ctx.stateIds) do ordered[#ordered+1]={traits=ref("states",key).traits} end
      for _,source in ipairs(sources) do ordered[#ordered+1]=source end
      return traitCall(T.new,ordered),equipment
    end
    local function skills(state,tr)
      local out,seen={},{}
      for _,key in ipairs(state.learnedSkills) do out[#out+1]=key;seen[key]=true end
      for _,key in ipairs(tr.addedSkills()) do ref("skills",key);if not seen[key] then out[#out+1]=key;seen[key]=true end end
      return out
    end
    function R.skills(state,ctx) local tr=context(state,ctx);return skills(state,tr) end
    function R.stats(state,ctx)
      local tr,equipment=context(state,ctx);local c=ref("classes",state.classId)
      local out={base={},plus={},basePlus={},rates={},buffRates={},params={},xparams={},sparams={}}
      for p=1,8 do
        local base=c.params[p][state.level+1];local plus=ctx.permanent[p]*1.0
        for _,item in ipairs(equipment) do plus=plus+item.params[p] end
        num(plus,nil,nil,true)
        local combined=base+plus;if not mv then combined=math.max(0.0,combined)end;num(combined,nil,SAFE,true);local rate=traitCall(tr.paramRate,p-1)
        local buff=ctx.buffs[p]*0.25+1.0
        -- Source multiplication association affects Math.round at half values.
        local value=mv and combined*(rate*buff)or combined*rate*buff
        if not finite(value) then fail("E_ACTOR_NUMBER","Nonfinite actor parameter") end
        out.base[p],out.plus[p],out.basePlus[p],out.rates[p],out.buffRates[p]=base,plus,combined,rate,buff
        local minimum=mv and (p==2 and 0.0 or 1.0)or (p==1 and 1.0 or 0.0)
        value=math.max(minimum,value)
        if mv then value=math.min(p<=2 and 9999.0 or 999.0,value)end
        out.params[p]=round(value)
      end
      for p=1,10 do out.xparams[p]=traitCall(tr.xparam,p-1);out.sparams[p]=traitCall(tr.sparam,p-1) end
      out.hpRate=ctx.hp/out.params[1];out.mpRate=out.params[2]>0 and ctx.mp/out.params[2] or 0.0
      out.skills=skills(state,tr)
      return out
    end
    return R
  end
  function M.new(definitions,profile)return M.fromCompiledCatalog(M.prepare(definitions,profile))end
  return M
end
