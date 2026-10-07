-- Offline validated enemy catalog -> private portable factory, never bytecode.
return function(deps)
 local Enemies,serialize=deps['runtime.rpg.enemies'],deps['build.serialize'];local M={};local SAFE=9007199254740991
 local function fail(code,reason,path)error({severity='error',code=code,reason=reason,jsonPath=path},0)end
 local function inspect(value,denseContainers)
  local active,nodes={},0
  local function walk(v,depth,path)
   nodes=nodes+1
   if nodes>1000000 or depth>64 then fail('E_RPG_BUDGET','Source metadata exceeds data budget',path)end
   local kind=type(v)
   -- Ignored action condition parameters retain the converter finite-number
   -- domain, including finite values outside safe53. Consumers validate ranges.
   if kind=='number'then if v~=v or v==math.huge or v==-math.huge then fail('E_ENEMY_NUMBER','Nonfinite source number',path)end
   elseif kind~='string' and kind~='boolean' and kind~='table'then fail('E_ENEMY_SHAPE','Executable or unsupported source value',path)
   elseif kind=='table'then
    if getmetatable(v)~=nil then fail('E_ENEMY_SHAPE','Enemy IR requires plain tables',path)end
    if active[v]then fail('E_ENEMY_SHAPE','Circular source data',path)end
    active[v]=true;local count,highest,strings=0,0,false
    for key,x in next,v do
     if type(key)=='number'then
      if key~=key or key%1~=0 or key<1 or key>SAFE then fail('E_ENEMY_SHAPE','Invalid source data key',path)end
      count=count+1;highest=math.max(highest,key)
     elseif type(key)=='string'then strings=true else fail('E_ENEMY_SHAPE','Invalid source data key',path)end
     walk(x,depth+1,path..(type(key)=='number' and ('['..string.format('%.0f',key-1)..']') or ('.'..key)))
    end
    if denseContainers and count>0 and (strings or count~=highest)then fail('E_ENEMY_SHAPE','Mixed or sparse source container',path)end
    active[v]=nil
   end
  end
  walk(value,0,'$');return nodes
 end
 function M.compile(normalizedRpg)
  if type(normalizedRpg)~='table' or getmetatable(normalizedRpg)~=nil then fail('E_ENEMY_SHAPE','Enemy IR requires plain tables','$')end
  local inputNodes=inspect(normalizedRpg,true)
  local catalog,rules=Enemies.prepare(normalizedRpg,normalizedRpg.profile)
  catalog.catalogVersion=2;catalog.initialResourcesById={};local initialAgilityById={};local troopAgilityById={}
  local zeros={0,0,0,0,0,0,0,0}
  local stats={inputNodes=inputNodes,enemies=0,troops=0,states=0,skills=0}
  for id in pairs(catalog.enemiesById)do
   local initial=rules.stats(id,{hidden=false,hp=0,mp=0,tp=0,stateIds={},permanent=zeros,buffs=zeros})
   catalog.initialResourcesById[id]={hp=initial.params[1],mp=initial.params[2]};initialAgilityById[id]=initial.params[7];stats.enemies=stats.enemies+1
  end
  for id,troop in pairs(catalog.troopsById)do
   local sum=0;for _,member in ipairs(troop.members)do sum=sum+initialAgilityById[member.enemyId]end
   troopAgilityById[id]=math.max(1,sum/math.max(1,#troop.members));stats.troops=stats.troops+1
  end
  for _ in pairs(catalog.statesById)do stats.states=stats.states+1 end
  for _ in pairs(catalog.skillsById)do stats.skills=stats.skills+1 end
  stats.catalogNodes=inspect(catalog,false)
  local source="-- Offline validated private enemy program.\nreturn function(deps)\n local enemies=deps['runtime.rpg.enemies']\n local catalog="..serialize.literal(catalog).."\n local prepared=enemies.fromCompiledCatalog(catalog)\n local troopAgility="..serialize.literal(troopAgilityById).."\n return {kind='r2u.enemy-program',schemaVersion=1,catalogVersion=2,profile="..serialize.literal(catalog.profile)..",troopAgility=function(id)if not troopAgility[id]then error({code='E_ENEMY_STATE_REFERENCE',reason='Missing troop'},0)end;return troopAgility[id]end,newEnemies=function(options)return prepared.newEnemies(options)end}\nend\n"
  stats.bytes=#source
  if stats.bytes>16777216 then fail('E_RPG_BUDGET','Generated enemy program exceeds data budget','$')end
  return {kind='r2u.enemy-program',schemaVersion=1,catalogVersion=2,profile=catalog.profile,moduleId='generated.enemy_program',dependencies={'runtime.rpg.enemies'},source=source,stats=stats}
 end
 return M
end
