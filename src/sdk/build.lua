-- BuildAdapter emits only owned, statically linked modules and a typed plan.
return function(deps)
 local S,J,D,B=deps['sdk.schema'],deps['contracts.json'],deps['contracts.diagnostic'],deps['build.bundle'];local M={}
 local function fail(reason)D.raise('E_EXTENSION_BUILD',reason)end
 local function fields(v,allowed)
  if type(v)~='table' or v==J.null then fail('Expected build declaration')end
  for k in pairs(v)do if not allowed[k]then fail('Unknown build field '..tostring(k))end end
 end
 local function list(v,maximum)
  if type(v)~='table' or v==J.null then fail('Expected dense build list')end
  local n=0;for k in pairs(v)do if type(k)~='number' or k%1~=0 or k<1 or k>#v then fail('Expected dense build list')end;n=n+1 end
  if n~=#v or n>maximum then fail('Build list exceeds limit')end;return v
 end
 local function name(v)return type(v)=='string' and #v<=64 and v:match('^[a-z][a-z0-9_]*$')end
 local function optionalList(v,maximum)return list(v==nil and {} or v,maximum)end
 function M.compile(adapter,context,planSchema,prefix)
  local ok,result=pcall(adapter.compile,S.copy(context))
  if not ok then fail(type(result)=='table' and result.reason or tostring(result))end
  fields(result,{plan=true,modules=true,runtimeDependencies=true,sourceMap=true})
  local plan=S.check(planSchema,result.plan,context.refs)
  local ordered,byName,exports={}, {},{}
  local namespace='extension.'..context.extensionId..'.generated.';local bytes=0
  for _,row in ipairs(optionalList(result.modules,32))do
   fields(row,{name=true,source=true,dependencies=true})
   if not name(row.name) or byName[row.name]then fail('Invalid or duplicate generated module name')end
   if type(row.source)~='string' or #row.source>4*1024*1024 then fail('Missing or oversized generated source')end
   bytes=bytes+#row.source;if bytes>8*1024*1024 then fail('Generated extension modules exceed 8MiB')end
   local seen={};local dependencies={}
   for _,dependency in ipairs(optionalList(row.dependencies,32))do
    if not name(dependency) or seen[dependency]then fail('Invalid or duplicate generated dependency')end
    seen[dependency]=true;dependencies[#dependencies+1]=dependency
   end
   table.sort(dependencies)
   byName[row.name]={name=row.name,id=namespace..row.name,path=prefix..'/extension-'..context.extensionId..'-'..row.name..'.lua',source=row.source:gsub('\r\n','\n'):gsub('\r','\n'),localDependencies=dependencies}
  end
  local names={};for n in pairs(byName)do names[#names+1]=n end;table.sort(names)
  local visiting={}
  local function visit(n)
   if exports[namespace..n]then return end
   local row=byName[n];if not row then fail('Missing generated module '..n)end
   if visiting[n]then fail('Generated module dependency cycle at '..n)end;visiting[n]=true
   local arguments={};row.dependencies={}
   for _,dep in ipairs(row.localDependencies)do visit(dep);row.dependencies[#row.dependencies+1]=namespace..dep;arguments[namespace..dep]=exports[namespace..dep]end
   exports[row.id]=B.instantiate(row.source,row.path,arguments);visiting[n]=nil
   ordered[#ordered+1]=row
  end
  for _,n in ipairs(names)do visit(n)end
  local runtimeDependencies,arguments,seen={}, {},{}
  for _,n in ipairs(optionalList(result.runtimeDependencies,32))do
   if not name(n) or not byName[n] or seen[n]then fail('Invalid runtime generated dependency')end;seen[n]=true
   runtimeDependencies[#runtimeDependencies+1]=namespace..n;arguments[namespace..n]=exports[namespace..n]
  end
  table.sort(runtimeDependencies)
  local needed={}
  local function mark(n)if needed[n]then return end;needed[n]=true;for _,dep in ipairs(byName[n].localDependencies)do mark(dep)end end
  for n in pairs(seen)do mark(n)end
  for _,n in ipairs(names)do if not needed[n]then fail('Generated module is not reachable from runtime dependencies: '..n)end end
  local known={};for _,source in ipairs(context.sources or {})do known[source.file]=true end
  local sourceMap={}
  for _,row in ipairs(optionalList(result.sourceMap,4096))do
   fields(row,{module=true,line=true,file=true,jsonPath=true});local module=byName[row.module]
   local lineCount=0;if module then local _,count=module.source:gsub('\n','');lineCount=count end
   if not module or type(row.line)~='number' or row.line%1~=0 or row.line<1 or row.line>lineCount+1 or not known[row.file] or type(row.jsonPath)~='string' then fail('Invalid generated source mapping')end
   sourceMap[#sourceMap+1]={moduleId=module.id,path=module.path,line=row.line,file=row.file,jsonPath=row.jsonPath}
  end
  return{plan=plan,modules=ordered,runtimeDependencies=runtimeDependencies,arguments=arguments,sourceMap=sourceMap}
 end
 return M
end
