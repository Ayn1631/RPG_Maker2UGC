-- Pure MZ trait aggregation over normalized plain runtime IR; no actor state.
return function(deps)
  local M={}
  local SAFE=9007199254740991
  local C={TRAIT_ELEMENT_RATE=11,TRAIT_DEBUFF_RATE=12,TRAIT_STATE_RATE=13,TRAIT_STATE_RESIST=14,
    TRAIT_PARAM=21,TRAIT_XPARAM=22,TRAIT_SPARAM=23,TRAIT_ATTACK_ELEMENT=31,TRAIT_ATTACK_STATE=32,
    TRAIT_ATTACK_SPEED=33,TRAIT_ATTACK_TIMES=34,TRAIT_ATTACK_SKILL=35,TRAIT_STYPE_ADD=41,TRAIT_STYPE_SEAL=42,
    TRAIT_SKILL_ADD=43,TRAIT_SKILL_SEAL=44,TRAIT_EQUIP_WTYPE=51,TRAIT_EQUIP_ATYPE=52,
    TRAIT_EQUIP_LOCK=53,TRAIT_EQUIP_SEAL=54,TRAIT_SLOT_TYPE=55,TRAIT_ACTION_PLUS=61,
    TRAIT_SPECIAL_FLAG=62,TRAIT_COLLAPSE_TYPE=63,TRAIT_PARTY_ABILITY=64,
    FLAG_ID_AUTO_BATTLE=0,FLAG_ID_GUARD=1,FLAG_ID_SUBSTITUTE=2,FLAG_ID_PRESERVE_TP=3}
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function integer(v) return type(v)=="number" and v==v and v>=0 and v<=SAFE and v%1==0 end
  local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
  local function plain(v)
    if type(v)~="table" or getmetatable(v)~=nil then fail("E_TRAITS_SHAPE","Trait IR requires plain tables") end
  end
  local function dense(v)
    plain(v); local count,highest=0,0
    for key in next,v do
      if not integer(key) or key<1 then fail("E_TRAITS_SHAPE","Trait lists must be dense arrays") end
      count=count+1; if key>highest then highest=key end
    end
    if count~=highest then fail("E_TRAITS_SHAPE","Trait lists must be dense arrays") end
    return count
  end
  local function traitCopy(tr) return {code=tr.code,dataId=tr.dataId,value=tr.value} end
  local function argument(v,max,positive)
    if not integer(v) or positive and v==0 or max and v>max then fail("E_TRAITS_ARGUMENT","Invalid trait query integer") end
    return v
  end
  function M.constants()
    local out={}; for key,value in pairs(C) do out[key]=value end; return out
  end
  function M.new(sources)
    dense(sources)
    local all={}
    for _,source in ipairs(sources) do
      plain(source); dense(source.traits)
      for _,tr in ipairs(source.traits) do
        plain(tr)
        if tr.code==nil or tr.dataId==nil or tr.value==nil then fail("E_TRAITS_SHAPE","Trait requires code, dataId and value") end
        if not integer(tr.code) or tr.code<1 or not integer(tr.dataId) or not finite(tr.value) then
          fail("E_TRAITS_NUMBER","Trait requires safe integer IDs and a finite value")
        end
        all[#all+1]={code=tr.code,dataId=tr.dataId,value=tr.value*1.0}
      end
    end
    local S={}
    local function list(code,id,values)
      local out={}
      for _,tr in ipairs(all) do
        if (code==nil or tr.code==code) and (id==nil or tr.dataId==id) then
          out[#out+1]=values and tr.dataId or traitCopy(tr)
        end
      end
      return out
    end
    local function reduce(code,id,product)
      local value=product and 1.0 or 0.0
      for _,tr in ipairs(all) do
        if tr.code==code and (id==nil or tr.dataId==id) then
          if product then value=value*tr.value else value=value+tr.value end
          if not finite(value) then fail("E_TRAITS_NUMBER","Trait aggregation produced a nonfinite result") end
        end
      end
      return value
    end
    local function includes(code,id)
      argument(id)
      for _,tr in ipairs(all) do if tr.code==code and tr.dataId==id then return true end end
      return false
    end
    local function maximum(code,default)
      local value
      for _,tr in ipairs(all) do if tr.code==code and (value==nil or tr.dataId>value) then value=tr.dataId end end
      return value==nil and default or value
    end
    function S.allTraits() return list() end
    function S.traits(code) argument(code,nil,true); return list(code) end
    function S.traitsWithId(code,id) argument(code,nil,true); argument(id); return list(code,id) end
    function S.traitsPi(code,id) argument(code,nil,true); argument(id); return reduce(code,id,true) end
    function S.traitsSum(code,id) argument(code,nil,true); argument(id); return reduce(code,id,false) end
    function S.traitsSumAll(code) argument(code,nil,true); return reduce(code,nil,false) end
    function S.traitsSet(code) argument(code,nil,true); return list(code,nil,true) end
    function S.paramRate(id) argument(id,7); return reduce(C.TRAIT_PARAM,id,true) end
    function S.xparam(id) argument(id,9); return reduce(C.TRAIT_XPARAM,id,false) end
    function S.sparam(id) argument(id,9); return reduce(C.TRAIT_SPARAM,id,true) end
    function S.elementRate(id) argument(id); return reduce(C.TRAIT_ELEMENT_RATE,id,true) end
    function S.debuffRate(id) argument(id,7); return reduce(C.TRAIT_DEBUFF_RATE,id,true) end
    function S.stateRate(id) argument(id); return reduce(C.TRAIT_STATE_RATE,id,true) end
    function S.stateResistSet() return list(C.TRAIT_STATE_RESIST,nil,true) end
    function S.isStateResist(id) return includes(C.TRAIT_STATE_RESIST,id) end
    function S.attackElements() return list(C.TRAIT_ATTACK_ELEMENT,nil,true) end
    function S.attackStates() return list(C.TRAIT_ATTACK_STATE,nil,true) end
    function S.attackStatesRate(id) argument(id); return reduce(C.TRAIT_ATTACK_STATE,id,false) end
    function S.attackSpeed() return reduce(C.TRAIT_ATTACK_SPEED,nil,false) end
    function S.attackTimesAdd() return math.max(reduce(C.TRAIT_ATTACK_TIMES,nil,false),0) end
    function S.attackSkillId() return maximum(C.TRAIT_ATTACK_SKILL,1) end
    function S.addedSkillTypes() return list(C.TRAIT_STYPE_ADD,nil,true) end
    function S.isSkillTypeSealed(id) return includes(C.TRAIT_STYPE_SEAL,id) end
    function S.addedSkills() return list(C.TRAIT_SKILL_ADD,nil,true) end
    function S.isSkillSealed(id) return includes(C.TRAIT_SKILL_SEAL,id) end
    function S.isEquipWtypeOk(id) return includes(C.TRAIT_EQUIP_WTYPE,id) end
    function S.isEquipAtypeOk(id) return includes(C.TRAIT_EQUIP_ATYPE,id) end
    function S.isEquipTypeLocked(id) return includes(C.TRAIT_EQUIP_LOCK,id) end
    function S.isEquipTypeSealed(id) return includes(C.TRAIT_EQUIP_SEAL,id) end
    function S.slotType() return maximum(C.TRAIT_SLOT_TYPE,0) end
    function S.isDualWield() return S.slotType()==1 end
    function S.actionPlusSet()
      local out={}; for _,tr in ipairs(all) do if tr.code==C.TRAIT_ACTION_PLUS then out[#out+1]=tr.value end end; return out
    end
    function S.specialFlag(id) return includes(C.TRAIT_SPECIAL_FLAG,id) end
    function S.collapseType() return maximum(C.TRAIT_COLLAPSE_TYPE,0) end
    function S.partyAbility(id) return includes(C.TRAIT_PARTY_ABILITY,id) end
    function S.isAutoBattle() return includes(C.TRAIT_SPECIAL_FLAG,C.FLAG_ID_AUTO_BATTLE) end
    function S.isPreserveTp() return includes(C.TRAIT_SPECIAL_FLAG,C.FLAG_ID_PRESERVE_TP) end
    local function movable(flag,canMove)
      if type(canMove)~="boolean" then fail("E_TRAITS_ARGUMENT","canMove must be an explicit boolean") end
      return includes(C.TRAIT_SPECIAL_FLAG,flag) and canMove
    end
    function S.isGuard(canMove) return movable(C.FLAG_ID_GUARD,canMove) end
    function S.isSubstitute(canMove) return movable(C.FLAG_ID_SUBSTITUTE,canMove) end
    return S
  end
  return M
end
