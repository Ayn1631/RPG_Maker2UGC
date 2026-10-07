-- Build-time action catalog. The published Lua never reopens project files.
return function(deps)
 local Actions,serialize=deps['runtime.rpg.action_resolver'],deps['build.serialize'];local M={}
 local function fail(reason)error({severity='error',code='E_ACTION_PROGRAM',reason=reason},0)end
 local function inspect(value,arrays)
  local active,nodes={},0
  local function walk(v,depth)
   nodes=nodes+1;if nodes>1000000 or depth>64 then fail('Action data budget exceeded')end
   local kind=type(v)
   if kind=='number'then if v~=v or v < -9007199254740991 or v > 9007199254740991 then fail('Invalid action number')end
   elseif kind=='table'then
    if getmetatable(v)~=nil or active[v]then fail('Action data must be plain and acyclic')end
    active[v]=true;local count,high,strings=0,0,false
    for k,x in next,v do
     if type(k)=='number'then
      if k%1~=0 or k<1 or k>9007199254740991 then fail('Invalid action data key')end
      count=count+1;high=math.max(high,k)
     elseif type(k)=='string'then strings=true else fail('Invalid action data key')end
     walk(x,depth+1)
    end
    if arrays and count>0 and (strings or count~=high)then fail('Action arrays must be dense')end
    active[v]=nil
   elseif kind~='string'and kind~='boolean'then fail('Executable or unsupported action data')end
  end
  walk(value,0);return nodes
 end
 function M.compile(definitions,commonEvents)
  local inputNodes=inspect(definitions,true)+inspect(commonEvents,true)
  if inputNodes>1000000 then fail('Action input budget exceeded')end
  local catalog=Actions.prepare(definitions,definitions.profile,{commonEvents=commonEvents})
  local stats={inputNodes=inputNodes,catalogNodes=inspect(catalog,false),items=0,skills=0}
  for _ in pairs(catalog.actionsByKind.item)do stats.items=stats.items+1 end
  for _ in pairs(catalog.actionsByKind.skill)do stats.skills=stats.skills+1 end
  local source="-- Offline action program.\nreturn function(deps)\n local catalog="..serialize.literal(catalog).."\n local actions=deps['runtime.rpg.action_resolver'].fromCompiledCatalog(catalog)\n return {kind='r2u.action-program',schemaVersion=1,catalogVersion=1,profile="..serialize.literal(catalog.profile)..",actions=actions}\nend\n"
  stats.bytes=#source;if #source>16777216 then fail('Generated action source exceeds budget')end
  return {kind='r2u.action-program',schemaVersion=1,catalogVersion=1,profile=catalog.profile,moduleId='generated.action_program',dependencies={'runtime.rpg.action_resolver'},source=source,stats=stats}
 end
 return M
end
