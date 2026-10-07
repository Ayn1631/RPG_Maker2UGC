-- Offline validated actor catalog -> private portable factory, never bytecode.
return function(deps)
 local Actors,serialize,MapEffects=deps['runtime.rpg.actors'],deps['build.serialize'],deps['runtime.rpg.map_effects'];local M={};local SAFE=9007199254740991
 local function fail(code,reason,path)error({severity='error',code=code,reason=reason,jsonPath=path},0)end
 local function inspect(value,denseContainers)
  local active,nodes={},0
  local function walk(v,depth,path)
   nodes=nodes+1
   if nodes>1000000 or depth>64 then fail('E_RPG_BUDGET','Source metadata exceeds data budget',path)end
   local kind=type(v)
   if kind=='number'then
    if v~=v or v==math.huge or v==-math.huge or v < -SAFE or v > SAFE then fail('E_ACTOR_NUMBER','Number outside finite supported range',path)end
   elseif kind~='string' and kind~='boolean' and kind~='table'then fail('E_ACTOR_SHAPE','Executable or unsupported source value',path)
   elseif kind=='table'then
    if getmetatable(v)~=nil then fail('E_ACTOR_SHAPE','Actor IR requires plain tables',path)end
    if active[v]then fail('E_ACTOR_SHAPE','Circular source data',path)end
    active[v]=true;local count,highest,strings=0,0,false
    for key,x in next,v do
     if type(key)=='number'then
      if key~=key or key%1~=0 or key<1 or key>SAFE then fail('E_ACTOR_SHAPE','Invalid source data key',path)end
      count=count+1;highest=math.max(highest,key)
     elseif type(key)=='string'then strings=true else fail('E_ACTOR_SHAPE','Invalid source data key',path)end
     walk(x,depth+1,path..(type(key)=='number' and ('['..string.format('%.0f',key-1)..']') or ('.'..key)))
    end
    if denseContainers and count>0 and (strings or count~=highest)then fail('E_ACTOR_SHAPE','Mixed or sparse source container',path)end
    active[v]=nil
   end
  end
  walk(value,0,'$');return nodes
 end
 function M.compile(normalizedRpg)
  -- Validate even discarded metadata. Never interpolate JSON strings as code.
  if type(normalizedRpg)~='table' or getmetatable(normalizedRpg)~=nil then fail('E_ACTOR_SHAPE','Actor IR requires plain tables','$')end
  local inputNodes=inspect(normalizedRpg,true)
  local catalog,rules=Actors.prepare(normalizedRpg,normalizedRpg.profile)
  local mapEffectsCatalog=MapEffects.prepare(normalizedRpg)
  -- Only compilation consumes default growth. Raw prepare keeps its historical
  -- deferred initial/EXP errors and all instances still compute Party resources.
  catalog.catalogVersion=2;catalog.growthSeedsById={}
  for _,id in ipairs(catalog.actorIds)do catalog.growthSeedsById[id]=rules.initial(id)end
  local stats={inputNodes=inputNodes,catalogNodes=inspect(catalog,false),actors=#catalog.actorIds,growthSeeds=#catalog.actorIds,classes=0,weapons=0,armors=0,skills=0,states=0}
  for _,name in ipairs({'classes','weapons','armors','skills','states'})do for _ in pairs(catalog[name..'ById'])do stats[name]=stats[name]+1 end end
  local source="-- Offline validated private actor program.\nreturn function(deps)\n local actors=deps['runtime.rpg.actors']\n local catalog="..serialize.literal(catalog).."\n local prepared=actors.fromCompiledCatalog(catalog)\n local mapEffects=deps['runtime.rpg.map_effects'].fromCompiledCatalog("..serialize.literal(mapEffectsCatalog)..")\n return {kind='r2u.actor-program',schemaVersion=1,catalogVersion=2,profile="..serialize.literal(catalog.profile)..",mapEffects=mapEffects,newActors=function(party,options)return prepared.newActors(party,options)end}\nend\n"
  stats.bytes=#source
  if stats.bytes>16777216 then fail('E_RPG_BUDGET','Generated actor program exceeds data budget','$')end
  return {kind='r2u.actor-program',schemaVersion=1,catalogVersion=2,profile=catalog.profile,moduleId='generated.actor_program',dependencies={'runtime.rpg.actors','runtime.rpg.map_effects'},source=source,stats=stats}
 end
 return M
end
