-- Build-time registry. Only project-selected extension packages are read.
return function(deps)
 local J,D,S,H,Serialize=deps['contracts.json'],deps['contracts.diagnostic'],deps['sdk.schema'],deps['build.sha256'],deps['build.serialize']
 local M={};local function fail(code,reason,file)D.raise(code,reason,{file=file})end
 local function path(v)
  if type(v)~='string' or v=='' or v:find('[%z\\:]') or v:sub(1,1)=='/'then fail('E_EXTENSION_MANIFEST','Invalid relative extension path')end
  for part in v:gmatch('[^/]+')do if part=='.' or part=='..'then fail('E_EXTENSION_MANIFEST','Extension entry escapes its package')end end;return v
 end
 local function id(v)return type(v)=='string' and v:match('^[a-z][a-z0-9_%.]*$') and not v:find('..',1,true) and v:sub(-1)~='.'end
 local function version(v)return type(v)=='string' and v:match('^%d+%.%d+%.%d+$')end
 local function has(list,v)for _,x in ipairs(list or {})do if x==v then return true end end;return false end
 local function fields(v,allowed,label)
  if type(v)~='table' or v==J.null then fail('E_EXTENSION_MANIFEST','Expected '..label)end
  for k in pairs(v)do if not allowed[k]then fail('E_EXTENSION_MANIFEST','Unknown '..label..' field '..tostring(k))end end
 end
 function M.new(selections,options)
  selections=selections or {};local entries,order,plugins,inputs={},{},{},J.array();local policyOwners={};local registry={};local profile=options.profile
  local count=0;for k in pairs(selections)do if type(k)~='number' or k%1~=0 or k<1 then fail('E_EXTENSION_MANIFEST','Extensions must be a dense array')end;count=count+1 end
  if count~=#selections or count>64 then fail('E_EXTENSION_MANIFEST','At most 64 ordered extensions')end
  for _,selection in ipairs(selections)do
   fields(selection,{path=true,version=true,config=true,integrity=true},'selection')
   if type(selection.path)~='string' or selection.path=='' or not version(selection.version)then fail('E_EXTENSION_MANIFEST','Selection requires path and exact version')end
   if selection.integrity~=nil then
    if type(selection.integrity)~='table'then fail('E_EXTENSION_MANIFEST','Integrity must map package paths to SHA256')end
    for file,digest in pairs(selection.integrity)do path(file);if type(digest)~='string' or #digest~=64 or digest:find('[^0-9a-f]')then fail('E_EXTENSION_MANIFEST','Invalid pinned digest')end end
   end
   local files={};local records=J.array()
   local function read(relative)
    path(relative);if files[relative]then return files[relative]end
    local full=selection.path..'/'..relative;local bytes,reason=options.read(full)
    if type(bytes)~='string' or #bytes>4*1024*1024 then fail('E_EXTENSION_READ','Cannot read bounded extension entry: '..tostring(reason),full)end
    files[relative]=bytes;local row={path=full,bytes=#bytes,sha256=H.hex(bytes)}
    if selection.integrity and selection.integrity[relative]~=row.sha256 then fail('E_EXTENSION_INTEGRITY','Missing or changed pinned extension file',full)end
    inputs[#inputs+1]=row;records[#records+1]={path=relative,bytes=#bytes,sha256=row.sha256};return bytes
   end
   local m=J.decode(read('extension.json'))
   fields(m,{id=true,version=true,contractVersion=true,stateSchemaVersion=true,frameworkVersion=true,engineProfiles=true,dependencies=true,plugin=true,schema=true,dataFile=true,runtime=true,preview=true,capabilities=true,sourceAdapter=true,buildAdapter=true},'manifest')
   if not id(m.id) or not version(m.version) or m.version~=selection.version or entries[m.id] then fail('E_EXTENSION_MANIFEST','Duplicate ID or selected version mismatch')end
   for _,key in ipairs({'contractVersion','stateSchemaVersion'})do if type(m[key])~='number' or m[key]%1~=0 or m[key]<1 then fail('E_EXTENSION_MANIFEST','Invalid '..key)end end
   if m.frameworkVersion~=1 or not has(m.engineProfiles,profile)then fail('E_EXTENSION_PROFILE','Extension does not support this framework/profile')end
   if type(m.plugin)~='string' or not m.plugin:match('^[A-Za-z][A-Za-z0-9_]*$') or plugins[m.plugin]then fail('E_EXTENSION_MANIFEST','Duplicate or invalid plugin name')end
   if type(m.preview)~='table' or type(m.dependencies)~='table' or type(m.capabilities)~='table'then fail('E_EXTENSION_MANIFEST','Missing dependency, capability or native preview declarations')end
   for _,cap in ipairs(m.capabilities)do if not ({commands=true,dialogue=true,gold=true,inventory=true,menus=true,queries=true,source=true,build=true,policies=true})[cap]then fail('E_EXTENSION_CAPABILITY','Unimplemented extension capability '..tostring(cap))end end
   if not has(m.capabilities,'commands')then fail('E_EXTENSION_CAPABILITY','Extension requires commands capability')end
   local schema=J.decode(read(path(m.schema)))
   fields(schema,{config=true,data=true,state=true,commands=true,menus=true,queries=true,notes=true,inputs=true,plan=true,policies=true},'schema')
   for _,policy in ipairs(deps['sdk.policy'].declarations(schema.policies))do
    if not has(m.capabilities,'policies')then fail('E_EXTENSION_CAPABILITY','Rules require policies capability')end
    if policyOwners[policy.name]then fail('E_EXTENSION_POLICY','Exclusive rule '..policy.name..' already owned by '..policyOwners[policy.name])end
    policyOwners[policy.name]=m.id
   end
   local buildAdapter
   if has(m.capabilities,'build')then
    S.validate(schema.plan)
    buildAdapter=deps['build.bundle'].instantiate(read(path(m.buildAdapter)),m.buildAdapter,{['build.serialize']=Serialize,['sdk.schema']=S,['contracts.json']=J})
    if type(buildAdapter.compile)~='function'then fail('E_EXTENSION_BUILD','Build adapter must export compile',m.buildAdapter)end
   elseif m.buildAdapter~=nil or schema.plan~=nil then fail('E_EXTENSION_CAPABILITY','Build adapter and plan require build capability')end
   deps['sdk.source'].validate(schema)
   if (m.sourceAdapter~=nil or schema.notes~=nil or schema.inputs~=nil) and not has(m.capabilities,'source')then fail('E_EXTENSION_CAPABILITY','Source declarations require source capability')end
   local sourceAdapter
   if has(m.capabilities,'source')then
    local source=read(path(m.sourceAdapter));local env={pairs=pairs,ipairs=ipairs,next=next,type=type,tostring=tostring,tonumber=tonumber,assert=assert,error=error,select=select,math=math,string=string,table=table,utf8=utf8}
    local chunk,reason=load(source,'@'..m.sourceAdapter,'t',env)
    if not chunk then fail('E_EXTENSION_SOURCE',tostring(reason),m.sourceAdapter)end
    local ok,value=pcall(function()return chunk()({['contracts.json']=J,['sdk.schema']=S})end)
    if not ok or type(value)~='table' or type(value.normalize)~='function' or value.collectInputs~=nil and type(value.collectInputs)~='function'then fail('E_EXTENSION_SOURCE','Source adapter must export normalize and optional collectInputs',m.sourceAdapter)end
    sourceAdapter=value
   end
   if schema.queries~=nil then
    if not has(m.capabilities,'queries')then fail('E_EXTENSION_CAPABILITY','Query declarations require queries capability')end
    if type(schema.queries)~='table' or schema.queries==J.null or J.is_array(schema.queries)then fail('E_EXTENSION_SCHEMA','Queries must be a record')end
    for name,q in pairs(schema.queries)do
     if type(name)~='string' or not name:match('^[A-Za-z][A-Za-z0-9_]*$')then fail('E_EXTENSION_SCHEMA','Invalid query name')end
     fields(q,{args=true,result=true},'query');S.validate(q.args);S.validate(q.result)
     if q.args.type~='record' or (q.result.type~='boolean' and q.result.type~='integer')then fail('E_EXTENSION_SCHEMA','Queries require record arguments and boolean/integer results')end
    end
   end
   local menus=deps['sdk.menu'].definitions(schema.menus)
   if #menus>0 and not has(m.capabilities,'menus')then fail('E_EXTENSION_CAPABILITY','Menu declarations require menus capability')end
   for _,key in ipairs({'config','data','state'})do S.validate(schema[key])end
   if type(schema.commands)~='table'then fail('E_EXTENSION_SCHEMA','Commands must be a record')end
   for name,command in pairs(schema.commands)do
    if type(name)~='string' or not name:match('^[A-Za-z][A-Za-z0-9_]*$')then fail('E_EXTENSION_SCHEMA','Invalid command name')end
    fields(command,{args=true,order=true},'command');S.validate(command.args)
    if command.args.type~='record' or type(command.order)~='table'then fail('E_EXTENSION_SCHEMA','Commands need record arguments and ordered MV names')end
    local seen={};for _,key in ipairs(command.order)do if not command.args.properties[key] or seen[key]then fail('E_EXTENSION_SCHEMA','Invalid MV argument order')end;seen[key]=true end
    for key in pairs(command.args.properties)do if not seen[key]then fail('E_EXTENSION_SCHEMA','MV order omits '..key)end end
   end
   local engine=profile=='mv-turn' and 'mv' or 'mz'
   local native=read(path(m.preview[engine]));local runtime=read(path(m.runtime));path(m.dataFile)
   local embedded=native:match('const CONTRACT = ([^\r\n]+);')
   if not embedded or J.encode(J.decode(embedded))~=J.encode(schema)then fail('E_EXTENSION_SCHEMA','Native adapter schema is stale; regenerate with tools/sdk-native.lua')end
   if #(schema.policies or {})>0 then
    local expected=J.object();for _,p in ipairs(schema.policies)do expected[p.name]=deps['sdk.policy'].contract(p.name)end
    local raw=native:match('const POLICIES = ([^\r\n]+);')
    if not raw or J.encode(J.decode(raw))~=J.encode(expected)then fail('E_EXTENSION_POLICY','Native rule contracts are stale; regenerate native adapter')end
   end
   local identity=native:match('const EXTENSION = ([^\r\n]+);');identity=identity and J.decode(identity)
   if type(identity)~='table'then fail('E_EXTENSION_MANIFEST','Native adapter identity is missing')end
   for _,key in ipairs({'id','plugin','version','contractVersion','stateSchemaVersion','dataFile'})do if identity[key]~=m[key]then fail('E_EXTENSION_MANIFEST','Native adapter identity is stale: '..key)end end
   local entry={manifest=m,schema=schema,config=S.check(schema.config,selection.config or J.object()),native=native,runtime=runtime,records=records,files=files,sourceAdapter=sourceAdapter,buildAdapter=buildAdapter}
   entries[m.id]=entry;plugins[m.plugin]=entry
  end
  local visiting,visited={},{}
  local function visit(key)
   if visiting[key]then fail('E_EXTENSION_DEPENDENCY','Extension dependency cycle at '..key)end;if visited[key]then return end
   local e=entries[key];visiting[key]=true;local names={}
   for dep,v in pairs(e.manifest.dependencies)do
    if not entries[dep] or entries[dep].manifest.version~=v then fail('E_EXTENSION_DEPENDENCY','Missing exact dependency '..dep)end;names[#names+1]=dep
   end
   table.sort(names);for _,dep in ipairs(names)do visit(dep)end
   visiting[key]=nil;visited[key]=true;order[#order+1]=e
  end
  local names={};for key in pairs(entries)do names[#names+1]=key end;table.sort(names);for _,key in ipairs(names)do visit(key)end
  function registry.acceptPlugin(plugin,read)
   local e=plugins[plugin.name];if not e then return false end
   if type(plugin.parameters)~='table' or J.is_array(plugin.parameters)then fail('E_EXTENSION_PLUGIN','Plugin parameters must be an object')end
   if e.enabled then fail('E_EXTENSION_PLUGIN','Plugin enabled more than once: '..plugin.name)end
   if next(plugin.parameters)~=nil then fail('E_EXTENSION_PLUGIN','This contract uses project config/shared data, not implicit native plugin parameters')end
   for dep in pairs(e.manifest.dependencies)do
    if not entries[dep].enabled then fail('E_EXTENSION_DEPENDENCY','Native plugin '..plugin.name..' must load after '..entries[dep].manifest.plugin,'js/plugins.js')end
   end
   local file='js/plugins/'..plugin.name..'.js';if read(file)~=e.native then fail('E_EXTENSION_PLUGIN','Native adapter differs from registered implementation',file)end
   e.enabled=true;return true
  end
  function registry.loadData(read,index)
   local declarations,lock=J.array(),J.array()
   for _,e in ipairs(order)do
    local m=e.manifest;if not e.enabled then fail('E_EXTENSION_PLUGIN','Selected extension requires enabled native plugin '..m.plugin)end
    local file='data/r2u/'..m.id..'/'..m.dataFile;local bytes=read(file);if not bytes then fail('E_EXTENSION_READ','Missing shared extension data',file)end
    local function references(data)
     local refs={}
     for collection,rows in pairs(data)do if J.is_array(rows)then
     local ids={};for _,row in ipairs(rows)do if type(row)=='table' and type(row.id)=='string'then if ids[row.id]then fail('E_EXTENSION_REFERENCE','Duplicate shared ID '..row.id,file)end;ids[row.id]=true end end
      refs[collection]=ids
     end end
     return refs
    end
    e.data=S.check(e.schema.data,J.decode(bytes));e.refs={};e.refs=references(e.data)
    local sourceInputs,sourceNotes=J.array(),J.array()
    if e.sourceAdapter then
     sourceNotes=deps['sdk.source'].notes(m.id,e.schema.notes,index or {},e.refs)
     local context={extensionId=m.id,profile=profile,data=S.copy(e.data),config=S.copy(e.config),notes=S.copy(sourceNotes)}
     context.inputs,sourceInputs=deps['sdk.source'].inputs(e.sourceAdapter,context,e.schema.inputs or {},read)
     local ok,value=pcall(e.sourceAdapter.normalize,context)
     if not ok then fail('E_EXTENSION_SOURCE',type(value)=='table' and value.reason or tostring(value),m.sourceAdapter)end
     e.data=S.check(e.schema.data,value);e.refs=references(e.data)
    end
    declarations[#declarations+1]=J.object({id=m.id,version=m.version,contractVersion=m.contractVersion,stateSchemaVersion=m.stateSchemaVersion})
    local noteLocations=J.array();for _,n in ipairs(sourceNotes)do noteLocations[#noteLocations+1]={database=n.database,recordId=n.recordId,mapId=n.mapId,tag=n.tag,source=n.source}end
    e.sourceLocations={{file=file,jsonPath='$'}}
    for _,n in ipairs(sourceInputs)do e.sourceLocations[#e.sourceLocations+1]={file=n.path,jsonPath='$'}end
    for _,n in ipairs(noteLocations)do e.sourceLocations[#e.sourceLocations+1]=S.copy(n.source)end
    lock[#lock+1]=J.object({id=m.id,version=m.version,contractVersion=m.contractVersion,stateSchemaVersion=m.stateSchemaVersion,files=e.records,sourceInputs=sourceInputs,notes=noteLocations})
   end
   return declarations,lock
  end
  local function tokens(source)
   local out,buf,quote={}, {},nil;local active=false;local i=1
   while i<=#source do local c=source:sub(i,i)
    if c=='\\' then local nextChar=source:sub(i+1,i+1);if nextChar~='\\' and nextChar~='"' and nextChar~="'"then fail('E_EXTENSION_ARGUMENT','MV escaping supports only quotes and backslashes')end;buf[#buf+1]=nextChar;active=true;i=i+1
    elseif quote then if c==quote then quote=nil else buf[#buf+1]=c end
    elseif c=='"' or c=="'"then quote=c;active=true
    elseif c:match('%s')then if active then out[#out+1]=table.concat(buf);buf={};active=false end
    else buf[#buf+1]=c;active=true end;i=i+1
   end
   if quote then fail('E_EXTENSION_ARGUMENT','Unclosed MV quote')end;if active then out[#out+1]=table.concat(buf)end;return out
  end
  function registry.command(code,p)
   local plugin,name,raw,words
   if code==356 then words=tokens(p[1]);plugin,name=words[1],words[2]
   else plugin,name,raw=p[1],p[2],p[4]end
   local e=plugins[plugin];local command=e and e.schema.commands[name]
   if not e or not e.enabled or not command then fail('E_EXTENSION_COMMAND','No registered command '..tostring(plugin)..'.'..tostring(name))end
   if words then
    if #words-2>#command.order then fail('E_EXTENSION_ARGUMENT','Too many MV arguments')end;raw={}
    for i,key in ipairs(command.order)do raw[key]=words[i+2]end
   elseif type(raw)~='table' or J.is_array(raw)then fail('E_EXTENSION_ARGUMENT','MZ arguments must be a record')end
   local args=J.object();for k,v in pairs(raw)do
    local spec=command.args.properties[k];if not spec then fail('E_EXTENSION_ARGUMENT','Unknown argument '..tostring(k))end;args[k]=S.fromString(spec,v)
   end
   args=S.check(command.args,args,e.refs)
   return{extensionId=e.manifest.id,contractVersion=e.manifest.contractVersion,command=name,args=args}
  end
  function registry.script(source,kind)
   if type(source)~='string' or #source>65536 then fail('E_EXTENSION_SCRIPT','Expected bounded SDK script')end
   local method=kind=='command' and 'r2uCommand' or 'r2uQuery'
   local suffix=kind=='command' and '%s*;?%s*$' or '%s*$'
   local body=source:match('^%s*this%.'..method..'%s*%((.*)%)'..suffix)
   if not body then fail('E_EXTENSION_SCRIPT','Use this.'..method..' with three JSON literal arguments')end
   local ok,args=pcall(J.decode,'['..body..']')
   if not ok or #args~=3 or type(args[1])~='string' or type(args[2])~='string' or type(args[3])~='table' or J.is_array(args[3]) or args[3]==J.null then fail('E_EXTENSION_SCRIPT','SDK script arguments must be extension ID, member name, and a JSON object')end
   local e=entries[args[1]];local member=e and (kind=='command' and e.schema.commands or e.schema.queries or {})[args[2]]
   if not e or not e.enabled or not member then fail('E_EXTENSION_SCRIPT','Unknown registered SDK member')end
   if kind~='command' and member.result.type~=kind then fail('E_EXTENSION_SCRIPT','Query result type must be '..kind)end
   local out={extensionId=e.manifest.id,contractVersion=e.manifest.contractVersion,args=S.check(member.args,args[3],e.refs)}
   if kind=='command'then out.command=args[2]else out.kind='extension_query';out.query=args[2];out.resultType=kind end
   return out
  end
  function registry.generate(prefix)
   if #order==0 then return nil end
   local modules,dependencies,definitions,sources,sourceMap={}, {},{},{},{}
   for _,e in ipairs(order)do
    local m=e.manifest;local moduleId='extension.'..m.id..'.runtime';local file=(prefix or 'generated/extensions')..'/extension-'..m.id..'.lua'
    local compiled={plan=J.object(),runtimeDependencies={},arguments={}}
    if not e.data then fail('E_EXTENSION_BUILD','Load source data before generating modules',file)end
    if e.buildAdapter then
     compiled=deps['sdk.build'].compile(e.buildAdapter,{extensionId=m.id,profile=profile,data=e.data,config=e.config,refs=e.refs,sources=e.sourceLocations},e.schema.plan,prefix or 'generated/extensions')
     for _,row in ipairs(compiled.modules)do modules[#modules+1]={id=row.id,path=row.path,dependencies=row.dependencies};sources[row.path]=row.source end
     for _,row in ipairs(compiled.sourceMap)do sourceMap[#sourceMap+1]=row end
    end
    local ok,initial=pcall(function()
     local runtime=deps['build.bundle'].instantiate(e.runtime,file,compiled.arguments);if type(runtime.initial)~='function' or type(runtime.execute)~='function'then fail('E_EXTENSION_BUILD','Runtime must export initial and execute',file)end
     local state=S.check(e.schema.state,runtime.initial(S.copy(e.data),S.copy(e.config),S.copy(compiled.plan)),e.refs)
     if next(e.schema.queries or {}) and type(runtime.query)~='function'then fail('E_EXTENSION_BUILD','Queries require runtime.query',file)end
     if #(e.schema.policies or {})>0 and type(runtime.policy)~='function'then fail('E_EXTENSION_BUILD','Rules require runtime.policy',file)end
     for _,menu in ipairs(e.schema.menus or {})do
      if type(runtime.menu)~='function'then fail('E_EXTENSION_BUILD','Menu capability requires runtime.menu',file)end
      -- View content can depend on live query values, so it is validated when
      -- opened; the generator only checks the declared provider entry point.
     end
     return state
    end)
    if not ok then fail('E_EXTENSION_BUILD',type(initial)=='table' and initial.reason or tostring(initial),file)end
    modules[#modules+1]={id=moduleId,path=file,dependencies=compiled.runtimeDependencies};dependencies[#dependencies+1]=moduleId;sources[file]=e.runtime
    definitions[#definitions+1]='{id='..Serialize.literal(m.id)..',version='..Serialize.literal(m.version)..',contractVersion='..m.contractVersion..',stateSchemaVersion='..m.stateSchemaVersion..',capabilities='..Serialize.literal(m.capabilities)..',schema='..Serialize.literal(e.schema)..',config='..Serialize.literal(e.config)..',data='..Serialize.literal(e.data)..',refs='..Serialize.literal(e.refs)..',initial='..Serialize.literal(initial)..',plan='..Serialize.literal(compiled.plan)..',runtime=deps['..Serialize.literal(moduleId)..']}'
   end
   return{moduleId='generated.extension_program',dependencies=dependencies,modules=modules,sources=sources,sourceMap=sourceMap,
    source="return function(deps) return {kind='r2u.extension-program',schemaVersion=1,definitions={"..table.concat(definitions,',').."}} end\n"}
  end
  function registry.inputs()return inputs end
  function registry.standardUI(pluginName)local e=plugins[pluginName];return e~=nil and e.enabled==true end
  function registry.count()return #order end
  return registry
 end
 return M
end
