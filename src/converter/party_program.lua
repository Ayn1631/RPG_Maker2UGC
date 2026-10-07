-- Offline dense world definitions -> a private portable Party catalog factory.
return function(deps)
  local Party,serialize,json=deps['runtime.rpg.party'],deps['build.serialize'],deps['contracts.json']
  local M,SAFE={},9007199254740991
  local arrayMt,objectMt=getmetatable(json.array()),getmetatable(json.object())
  local pools={'items','weapons','armors','actors'}
  local fields={items={'id','name','price','consumable','itypeId'},weapons={'id','name','price','etypeId'},armors={'id','name','price','etypeId'},actors={'id'}}
  local function fail(code,reason,path) error({severity='error',code=code,reason=reason,jsonPath=path},0) end
  local function shape(reason,path) fail('E_PARTY_SHAPE',reason,path) end
  local function container(v,path)
    if type(v)~='table' or rawequal(v,json.null) then shape('Party IR requires a container',path) end
    local mt=getmetatable(v)
    if mt~=nil and (not (rawequal(mt,arrayMt) or rawequal(mt,objectMt)) or next(mt)~=nil or getmetatable(mt)~=nil) then shape('Unsupported source metatable',path) end
    return mt
  end
  local function inspect(value)
    local active,nodes={},0
    local function walk(v,depth,path)
      nodes=nodes+1
      if nodes>1000000 or depth>64 then fail('E_RPG_BUDGET','Source metadata exceeds data budget',path) end
      local kind=type(v)
      if kind=='number' then
        if v~=v or v < -SAFE or v > SAFE then fail('E_PARTY_NUMBER','Number outside finite supported range',path) end
      elseif kind=='table' then
        if rawequal(v,json.null) then
          if getmetatable(v)~=nil or next(v)~=nil then shape('Polluted JSON null',path) end
          return
        end
        local mt=container(v,path)
        if active[v] then shape('Circular source data',path) end
        active[v]=true
        local count,highest,strings=0,0,false
        for key,x in next,v do
          local suffix
          if type(key)=='number' then
            if key~=key or key%1~=0 or key<1 or key>SAFE then shape('Invalid source data key',path) end
            count=count+1;highest=math.max(highest,key);suffix='['..string.format('%.0f',key-1)..']'
          elseif type(key)=='string' then strings=true;suffix='.'..key
          else shape('Invalid source data key',path) end
          walk(x,depth+1,path..suffix)
        end
        if (count>0 and (strings or count~=highest)) or (rawequal(mt,arrayMt) and strings) or (rawequal(mt,objectMt) and count>0) then shape('Mixed or sparse source container',path) end
        active[v]=nil
      elseif kind~='string' and kind~='boolean' then shape('Executable or unsupported source value',path) end
    end
    walk(value,0,'$');return nodes
  end
  function M.compile(definitions,profile)
    container(definitions,'$')
    local inputNodes=inspect(definitions)
    if profile~='mv-1.5.1' and profile~='mz-1.10.0' then shape('Unsupported Party profile','$.profile') end
    local keyed,stats={},{inputNodes=inputNodes}
    for _,pool in ipairs(pools) do
      local entries=rawget(definitions,pool);container(entries,'$.'..pool)
      local count=0
      for key in next,entries do
        if type(key)~='number' then shape('Definition library must be dense','$.'..pool) end
        count=count+1
      end
      local target={};keyed[pool]=target;stats[pool]=count
      for i=1,count do
        local path='$.'..pool..'['..(i-1)..']'
        local record=rawget(entries,i);container(record,path)
        local id=rawget(record,'id')
        if type(id)~='number' or id~=id or id%1~=0 or id<1 or id>SAFE then fail('E_PARTY_NUMBER','ID must be a positive safe integer',path..'.id') end
        if target[id]~=nil then fail('E_PARTY_REFERENCE','Duplicate definition ID',path..'.id') end
        local copy={};for _,field in ipairs(fields[pool]) do copy[field]=rawget(record,field) end
        target[id]=copy
      end
    end
    local catalog=Party.prepare(keyed);catalog.profile=profile
    -- The generated ID maps are sparse keyed maps, so count nodes separately.
    local catalogCount=0
    local function catalogNodes(v)
      catalogCount=catalogCount+1
      if catalogCount>1000000 then fail('E_RPG_BUDGET','Party catalog exceeds data budget','$') end
      if type(v)=='table' then for _,x in next,v do catalogNodes(x) end end
    end
    catalogNodes(catalog);stats.catalogNodes=catalogCount
    local shop={item={},weapon={},armor={}}
    for kind,pool in pairs({item='items',weapon='weapons',armor='armors'})do
      for _,record in ipairs(definitions[pool])do
        local view={};for _,key in ipairs({'id','name','price','itypeId','etypeId','wtypeId','atypeId','params'})do view[key]=record[key]end
        shop[kind][record.id]=view
      end
    end
    local source="-- Offline validated private Party program.\nreturn function(deps)\n local party=deps['runtime.rpg.party']\n local catalog="..serialize.literal(catalog).."\n local prepared=party.fromCompiledCatalog(catalog)\n local shop="..serialize.literal(shop).."\n return {kind='r2u.party-program',schemaVersion=1,catalogVersion=1,profile="..serialize.literal(profile)..",newParty=function(options)return prepared.newParty(options)end,getShopDefinition=function(kind,id)return shop[kind] and shop[kind][id]end}\nend\n"
    stats.bytes=#source
    if stats.bytes>16777216 then fail('E_RPG_BUDGET','Generated Party program exceeds data budget','$') end
    return {kind='r2u.party-program',schemaVersion=1,catalogVersion=1,profile=profile,moduleId='generated.party_program',dependencies={'runtime.rpg.party'},source=source,stats=stats}
  end
  return M
end
