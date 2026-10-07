-- Source-ID inventory and transactions only; actor traits/effects belong upstairs.
return function()
  local M = {}
  local candidateToken = {}
  local SAFE = 9007199254740991
  local pools = {item="items",weapon="weapons",armor="armors"}
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function shape(reason) fail("E_PARTY_SHAPE",reason) end
  local function plain(value,label)
    if type(value)~="table" or getmetatable(value)~=nil then shape(label .. " must be a plain table") end
    return value
  end
  local function number(value,label,min,max)
    if type(value)~="number" or value~=value or value%1~=0 or value < (min or -SAFE) or value > (max or SAFE) then
      fail("E_PARTY_NUMBER",label .. " must be a finite safe integer in range")
    end
    return value
  end
  local function id(value) return number(value,"ID",1) end
  local function list(value,label)
    plain(value,label)
    local count,highest=0,0
    for key in next,value do
      if type(key)~="number" or key%1~=0 or key<1 or key>SAFE then shape(label .. " must be a dense list") end
      count=count+1; if key>highest then highest=key end
    end
    if count~=highest then shape(label .. " must be a dense list") end
    return count
  end
  local function boolean(value,label,default)
    if value==nil then return default end
    if type(value)~="boolean" then shape(label .. " must be boolean") end
    return value
  end
  local function copy_item(item)
    if item==false then return false end
    return {kind=item.kind,id=item.id}
  end
  local function clamp(value,maximum) return math.max(0,math.min(maximum,value)) end

  local function configuration(options,compiled)
    if options==nil then options={} end
    plain(options,"options")
    if compiled then
      for key in next,options do
        if key~="state" and key~="maxItems" and key~="maxGold" and key~="equipmentPolicy" then shape("Unknown compiled Party option") end
      end
    end
    local maxItems=options.maxItems; if maxItems==nil then maxItems=99 end
    local maxGold=options.maxGold; if maxGold==nil then maxGold=99999999 end
    number(maxItems,"maxItems",0); number(maxGold,"maxGold",0)
    local policy=options.equipmentPolicy
    if policy~=nil and type(policy)~="function" then fail("E_PARTY_POLICY","equipmentPolicy must be a function") end
    return options,maxItems,maxGold,policy
  end
  function M.prepare(definitions)
    plain(definitions,"definitions")
    -- Copy the fields consumed by this module. No caller-owned record is retained.
    local catalog={kind="r2u.party-catalog",schemaVersion=1,catalogVersion=1,itemsById={},weaponsById={},armorsById={},actorsById={}}
    for kind,pool in pairs({item="items",weapon="weapons",armor="armors",actor="actors"}) do
      local entries=plain(definitions[pool],pool)
      for key,record in next,entries do
        id(key); plain(record,"definition")
        id(record.id)
        if record.id~=key then fail("E_PARTY_REFERENCE","Definition ID disagrees with its source key") end
        local copied={id=key}
        if kind~="actor" then
          if type(record.name)~="string" then shape("Definition name must be a string") end
          copied.name=record.name; copied.price=number(record.price,"price")
          if kind=="item" then
            if type(record.consumable)~="boolean" then shape("consumable must be boolean") end
            copied.consumable=record.consumable; copied.itypeId=id(record.itypeId)
          else copied.etypeId=id(record.etypeId) end
        end
        catalog[pool.."ById"][key]=copied
      end
    end
    return catalog
  end
  local instance
  instance=function(catalog,options,maxItems,maxGold,policy,internalToken)
    local catalogs={item=catalog.itemsById,weapon=catalog.weaponsById,armor=catalog.armorsById,actor=catalog.actorsById}
    local function reference(kind,key)
      if kind~="actor" and pools[kind]==nil then shape("Unknown inventory kind") end
      id(key)
      local record=catalogs[kind][key]
      if not record then fail("E_PARTY_REFERENCE","Unknown " .. kind .. " definition") end
      return record
    end
    local function commodity(kind,key)
      if pools[kind]==nil then shape("Unknown inventory kind") end
      return reference(kind,key)
    end
    local function equipment_item(value)
      if value==false then return false end
      plain(value,"equipment item")
      if value.kind~="weapon" and value.kind~="armor" then shape("Equipment must be weapon or armor") end
      reference(value.kind,value.id)
      return {kind=value.kind,id=value.id}
    end
    local data={gold=0,inventory={item={},weapon={},armor={}},members={},equipment={}}
    local initial=options.state
    if initial==nil then initial={} end
    plain(initial,"state")
    if initial.gold~=nil then data.gold=number(initial.gold,"gold",0,maxGold) end
    if initial.inventory~=nil then
      plain(initial.inventory,"inventory")
      for kind,entries in next,initial.inventory do
        if pools[kind]==nil then shape("Unknown inventory category") end
        plain(entries,"inventory category")
        for key,amount in next,entries do
          reference(kind,key); number(amount,"inventory quantity",0,maxItems)
          if amount>0 then data.inventory[kind][key]=amount end
        end
      end
    end
    if initial.members~=nil then
      list(initial.members,"members")
      local seen={}
      for _,key in ipairs(initial.members) do
        reference("actor",key)
        if not seen[key] then seen[key]=true; data.members[#data.members+1]=key end
      end
    end
    if initial.equipment~=nil then
      plain(initial.equipment,"equipment")
      for actor,slots in next,initial.equipment do
        reference("actor",actor); list(slots,"equipment slots")
        local copied={}
        for i,value in ipairs(slots) do copied[i]=equipment_item(value) end
        data.equipment[actor]=copied
      end
    end
    local P={}
    local inPolicy,inTransaction=false,false
    local function writable()
      if inPolicy then fail("E_PARTY_POLICY","equipmentPolicy cannot mutate the party") end
      if inTransaction then fail("E_PARTY_TRANSACTION","Transaction callback cannot mutate the original party") end
    end
    local function member_index(actor)
      for i,key in ipairs(data.members) do if key==actor then return i end end
    end
    local function stock(kind,key) return data.inventory[kind][key] or 0 end
    local function put(kind,key,amount)
      if amount==0 then data.inventory[kind][key]=nil else data.inventory[kind][key]=amount end
    end
    local function match(item,kind,key) return item~=false and item.kind==kind and item.id==key end
    local function snapshot()
      local result={gold=data.gold,inventory={item={},weapon={},armor={}},members={},equipment={}}
      for kind,entries in pairs(data.inventory) do for key,amount in next,entries do result.inventory[kind][key]=amount end end
      for i,key in ipairs(data.members) do result.members[i]=key end
      for actor,slots in next,data.equipment do
        local copied={}; for i,item in ipairs(slots) do copied[i]=copy_item(item) end
        result.equipment[actor]=copied
      end
      return result
    end
    P.snapshot=snapshot
    function P.transaction(callback)
      writable()
      if type(callback)~="function" then fail("E_PARTY_TRANSACTION","Transaction requires a callback") end
      local candidate=instance(catalog,{state=snapshot()},maxItems,maxGold,policy,candidateToken)
      local candidateSnapshot=candidate.snapshot
      inTransaction=true
      local ok,commit,value=pcall(callback,candidate)
      inTransaction=false
      if not ok then
        if type(commit)=="table" and getmetatable(commit)==nil and type(rawget(commit,"code"))=="string"
          and type(rawget(commit,"reason"))=="string" and rawget(commit,"severity")=="error" then error(commit,0) end
        fail("E_PARTY_TRANSACTION","Transaction callback failed")
      end
      if type(commit)~="boolean" then fail("E_PARTY_TRANSACTION","Transaction callback must return a boolean decision") end
      if commit then data=candidateSnapshot() end
      return commit,value
    end
    function P.gold() return data.gold end
    function P.count(kind,key) commodity(kind,key); return stock(kind,key) end
    function P.hasActor(actor) reference("actor",actor); return member_index(actor)~=nil end
    function P.members()
      local copied={}; for i,key in ipairs(data.members) do copied[i]=key end; return copied
    end
    function P.hasItem(kind,key,includeEquip)
      commodity(kind,key); includeEquip=boolean(includeEquip,"includeEquip",false)
      if stock(kind,key)>0 then return true end
      if includeEquip then
        for _,actor in ipairs(data.members) do
          for _,item in ipairs(data.equipment[actor] or {}) do if match(item,kind,key) then return true end end
        end
      end
      return false
    end
    function P.gainGold(amount)
      writable(); number(amount,"gold amount")
      local old=data.gold; data.gold=clamp(old+0.0+amount,maxGold)
      return data.gold-old
    end
    function P.gainItem(kind,key,amount,includeEquip)
      writable(); commodity(kind,key); number(amount,"item amount")
      includeEquip=boolean(includeEquip,"includeEquip",false)
      local old=stock(kind,key)
      local total=old+0.0+amount
      local inventory=clamp(total,maxItems)
      local discarded=0
      if includeEquip and total<0 then
        local needed=-total
        for _,actor in ipairs(data.members) do
          for slot,item in ipairs(data.equipment[actor] or {}) do
            if discarded<needed and match(item,kind,key) then
              data.equipment[actor][slot]=false; discarded=discarded+1
            end
          end
        end
      end
      put(kind,key,inventory)
      return inventory-old-discarded
    end
    function P.consumeItem(key)
      writable(); local record=reference("item",key)
      local amount=stock("item",key); if amount<1 then return false end
      if record.consumable then put("item",key,amount-1) end
      return true
    end
    function P.addActor(actor)
      writable(); reference("actor",actor)
      if member_index(actor) then return false end
      data.members[#data.members+1]=actor; return true
    end
    function P.removeActor(actor)
      writable(); reference("actor",actor)
      local i=member_index(actor); if not i then return false end
      table.remove(data.members,i); return true
    end
    function P.swapMembers(first,second)
      writable(); number(first,"member index",1); number(second,"member index",1)
      if first>#data.members or second>#data.members then fail("E_PARTY_REFERENCE","Member index is out of range") end
      data.members[first],data.members[second]=data.members[second],data.members[first]
    end
    -- Low-level refresh operation, not a player equipment choice. The actor
    -- coordinator invokes it on a transaction candidate before committing stats.
    function P.releaseEquipment(actor,slot)
      writable(); reference("actor",actor); number(slot,"equipment slot",1)
      local slots=data.equipment[actor]
      if not slots or slots[slot]==nil then fail("E_PARTY_REFERENCE","Equipment slot does not exist") end
      local item=slots[slot]
      if item==false then return false end
      local result=copy_item(item)
      put(item.kind,item.id,clamp(stock(item.kind,item.id)+1.0,maxItems))
      slots[slot]=false
      return result
    end
    local function candidateWritable()
      writable()
      if not rawequal(internalToken,candidateToken) then fail("E_PARTY_TRANSACTION","Low-level equipment operations require a transaction candidate") end
    end
    local function narrowEquipment(value)
      if value~=false then
        plain(value,"equipment item")
        for key in next,value do if key~="kind" and key~="id" then shape("Unknown equipment item field") end end
      end
      return equipment_item(value)
    end
    -- Actor coordinator owns all legality/refresh rules. Source trade deliberately
    -- returns old stock at cap before deducting new stock, even for the same item.
    function P.tradeEquipment(newItem,oldItem)
      candidateWritable()
      local incoming,old=narrowEquipment(newItem),narrowEquipment(oldItem)
      if incoming~=false and stock(incoming.kind,incoming.id)<1 then return false end
      if old~=false then put(old.kind,old.id,clamp(stock(old.kind,old.id)+1.0,maxItems)) end
      if incoming~=false then put(incoming.kind,incoming.id,stock(incoming.kind,incoming.id)-1.0) end
      return true
    end
    function P.replaceEquipment(actor,items)
      candidateWritable();reference("actor",actor);list(items,"equipment slots")
      local slots={};for i,item in ipairs(items)do slots[i]=narrowEquipment(item)end
      data.equipment[actor]=slots
    end
    function P.setEquipment(actor,slot,item)
      candidateWritable();reference("actor",actor);number(slot,"equipment slot",1)
      local slots=data.equipment[actor]
      if not slots or slots[slot]==nil then fail("E_PARTY_REFERENCE","Equipment slot does not exist") end
      local incoming=narrowEquipment(item);local old=copy_item(slots[slot]);slots[slot]=incoming;return old
    end
    function P.equip(actor,slot,newItem)
      writable(); reference("actor",actor); number(slot,"equipment slot",1)
      if not member_index(actor) then fail("E_PARTY_REFERENCE","Actor must be a party member") end
      local slots=data.equipment[actor]
      if not slots or slots[slot]==nil then fail("E_PARTY_REFERENCE","Equipment slot does not exist") end
      local incoming=equipment_item(newItem)
      if not policy then fail("E_PARTY_POLICY","Equipment requires an explicit equipmentPolicy") end
      local current=slots[slot]
      inPolicy=true
      local ok,allowed=pcall(policy,actor,slot,copy_item(incoming),copy_item(current),snapshot())
      inPolicy=false
      if not ok or type(allowed)~="boolean" then fail("E_PARTY_POLICY","equipmentPolicy must complete with a boolean") end
      if not allowed then return false,"policy" end
      if (incoming==false and current==false) or (incoming~=false and match(current,incoming.kind,incoming.id)) then return true end
      if incoming~=false and stock(incoming.kind,incoming.id)<1 then return false,"inventory" end
      if current~=false and stock(current.kind,current.id)>=maxItems then return false,"capacity" end
      -- All checks complete. There is no callback or fallible validation after this point.
      if current~=false then put(current.kind,current.id,stock(current.kind,current.id)+1.0) end
      if incoming~=false then put(incoming.kind,incoming.id,stock(incoming.kind,incoming.id)-1) end
      slots[slot]=incoming
      return true
    end
    local function quantity(value) return number(value,"transaction quantity",1) end
    local function product(first,second)
      local result=(first+0.0)*second
      if result>SAFE then fail("E_PARTY_NUMBER","Transaction product exceeds the safe integer range") end
      return result
    end
    function P.buy(kind,key,amount,unitPrice)
      writable(); local record=commodity(kind,key); quantity(amount)
      if unitPrice==nil then unitPrice=record.price end
      number(unitPrice,"unit price",0)
      local cost=product(amount,unitPrice)
      local nextStock=stock(kind,key)+0.0+amount
      if data.gold<cost then return false,"funds" end
      if nextStock>maxItems then return false,"capacity" end
      data.gold=data.gold-cost; put(kind,key,nextStock)
      return true
    end
    function P.sell(kind,key,amount,sellOptions)
      writable(); local record=commodity(kind,key); quantity(amount)
      if sellOptions==nil then sellOptions={} end
      plain(sellOptions,"sell options")
      local only=boolean(sellOptions.purchaseOnly,"purchaseOnly",false)
      if only then return false,"purchase_only" end
      if record.price<=0 then return false,"price" end
      local unitPrice=sellOptions.unitPrice
      if unitPrice==nil then unitPrice=math.floor(record.price/2)end
      number(unitPrice,'unit price',0)
      local revenue=product(amount,unitPrice)
      local current=stock(kind,key)
      if current<amount then return false,"inventory" end
      local nextGold=clamp(data.gold+0.0+revenue,maxGold)
      put(kind,key,current-amount); data.gold=nextGold
      return true
    end
    return P
  end
  function M.new(definitions,options,internalToken)
    plain(definitions,"definitions")
    local maxItems,maxGold,policy
    options,maxItems,maxGold,policy=configuration(options,false)
    return instance(M.prepare(definitions),options,maxItems,maxGold,policy,internalToken)
  end
  function M.fromCompiledCatalog(catalog)
    plain(catalog,"catalog")
    if rawget(catalog,"kind")~="r2u.party-catalog" or rawget(catalog,"schemaVersion")~=1 or rawget(catalog,"catalogVersion")~=1 then shape("Unsupported Party catalog header") end
    local profile=rawget(catalog,"profile")
    if profile~="mv-1.5.1" and profile~="mz-1.10.0" then shape("Unsupported Party catalog profile") end
    for _,pool in ipairs({"items","weapons","armors","actors"}) do plain(rawget(catalog,pool.."ById"),pool.."ById") end
    return {newParty=function(options)
      local maxItems,maxGold,policy
      options,maxItems,maxGold,policy=configuration(options,true)
      return instance(catalog,options,maxItems,maxGold,policy)
    end}
  end
  return M
end
