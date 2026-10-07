-- Build-only extension inputs and namespaced note normalization.
return function(deps)
 local J,S,D=deps['contracts.json'],deps['sdk.schema'],deps['contracts.diagnostic'];local M={}
 local databases={Actors=true,Classes=true,Skills=true,Items=true,Weapons=true,Armors=true,Enemies=true,Troops=true,States=true,Tilesets=true,CommonEvents=true,Animations=true,Maps=true,MapEvents=true}
 local function fail(reason,file,jsonPath)D.raise('E_EXTENSION_SOURCE',reason,{file=file,jsonPath=jsonPath})end
 local function name(v)return type(v)=='string' and v:match('^[a-z][a-z0-9_]*$')end
 local function dense(v,max)
  if type(v)~='table' or v==J.null then fail('Expected source declaration list')end
  local n=0;for k in pairs(v)do if type(k)~='number' or k%1~=0 or k<1 or k>#v then fail('Source list must be dense')end;n=n+1 end
  if n~=#v or n>max then fail('Source declaration count exceeds limit')end
 end
 local function fields(v,allowed)
  if type(v)~='table' or v==J.null then fail('Expected source declaration')end
  for k in pairs(v)do if not allowed[k]then fail('Unknown source declaration field '..tostring(k))end end
 end
 -- Check the extension's declared source inputs against the supported database contract.
 function M.validate(schema)
  local seen={};dense(schema.notes or {},128)
  for _,d in ipairs(schema.notes or {})do
   fields(d,{database=true,tag=true,value=true,multiple=true,multiline=true})
   if not databases[d.database] or not name(d.tag)then fail('Invalid note database or tag')end
   if d.multiple~=nil and type(d.multiple)~='boolean' or d.multiline~=nil and type(d.multiline)~='boolean'then fail('Note multiple/multiline must be boolean')end
   local key=d.database..'.'..d.tag;if seen[key]then fail('Duplicate note declaration '..key)end;seen[key]=true;S.validate(d.value)
  end
  if schema.inputs~=nil then
   if type(schema.inputs)~='table' or schema.inputs==J.null or J.is_array(schema.inputs)then fail('Input schemas must be a record')end
   local n=0;for key,spec in pairs(schema.inputs)do if not name(key)then fail('Invalid input name')end;n=n+1;S.validate(spec)end
   if n>64 then fail('At most 64 extra inputs')end
  end
 end
 -- Extract namespaced source notes while retaining their source file and JSON locations.
 function M.notes(extensionId,declarations,index,refs)
  local byDatabase,out={},J.array();local prefix=extensionId..'.'
  for _,d in ipairs(declarations or {})do byDatabase[d.database]=byDatabase[d.database] or {};byDatabase[d.database][d.tag]=d end
  local function record(database,r,file,jsonPath,mapId)
   if type(r)~='table' or r==J.null then return end
   local note=r.note;if note==nil then note=''end;if type(note)~='string' or #note>65536 then fail('Note must be bounded text',file,jsonPath..'.note')end
   local cursor,seen=1,{}
   while true do
    local first,last,body=note:find('<([^<>]*)>',cursor);if not first then break end;cursor=last+1
    if body:sub(1,#prefix)==prefix or body:sub(1,#prefix+1)=='/'..prefix then
     local tag,colon,raw=body:match('^'..prefix:gsub('([^%w])','%%%1')..'([a-z][a-z0-9_]*)(:?)(.*)$')
     local d=tag and byDatabase[database][tag]
     if not d then fail('Unknown or unmatched note tag '..body,file,jsonPath..'.note')end
     if colon=='' then
      if raw~='' or not d.multiline then fail('This note requires an inline colon value',file,jsonPath..'.note')end
      local ending='</'..prefix..tag..'>';local a,b=note:find(ending,cursor,true)
      if not a then fail('Missing closing note tag '..tag,file,jsonPath..'.note')end
      raw=note:sub(cursor,a-1);cursor=b+1
      if raw:find('<'..prefix,1,true)then fail('Nested extension note tags are unsupported',file,jsonPath..'.note')end
     elseif not d.multiline and raw:find('[\r\n]')then fail('Multiline note is not declared',file,jsonPath..'.note')end
     if seen[tag] and not d.multiple then fail('Duplicate note tag '..tag,file,jsonPath..'.note')end;seen[tag]=true
     raw=raw:match('^%s*(.-)%s*$')
     local ok,value=pcall(function()return S.check(d.value,S.fromString(d.value,raw),refs)end)
     if not ok then fail(type(value)=='table' and value.reason or tostring(value),file,jsonPath..'.note')end
     out[#out+1]={database=database,recordId=r.id,mapId=mapId,tag=tag,value=value,
      record=S.copy(r),source={file=file,jsonPath=jsonPath..'.note'}}
    end
   end
  end
  local names={};for db in pairs(byDatabase)do names[#names+1]=db end;table.sort(names)
  for _,db in ipairs(names)do
   if db=='Maps' or db=='MapEvents'then
    for _,map in ipairs(index.maps or {})do
     local file=map.sourceLocation and map.sourceLocation.file or string.format('data/Map%03d.json',map.id)
     if db=='Maps'then local r=S.copy(map.settings or {});r.id=map.id;record(db,r,file,'$',map.id)
     else for slot,r in ipairs(map.events or {})do record(db,r,file,'$.events['..(slot-1)..']',map.id)end end
    end
   else
    local entries=index.database and index.database[db]
    for slot,r in ipairs(entries and entries.records or {})do record(db,r,'data/'..db..'.json','$['..(slot-1)..']')end
   end
  end
  return out
 end
 -- Run registered adapter readers and normalize their outputs before they enter a build package.
 function M.inputs(adapter,context,schemas,read)
  local declarations={}
  if adapter.collectInputs then declarations=adapter.collectInputs(S.copy(context))end
  dense(declarations,64)
  local values,locations,seen,cached=J.object(),J.array(),{},{}
  for _,d in ipairs(declarations)do
   fields(d,{name=true,path=true,format=true});local path=d.path
   if not name(d.name) or seen[d.name] or not schemas[d.name]then fail('Undeclared or duplicate extra input name')end
   if type(path)~='string' or path=='' or path:find('[%z\\:]') or path:sub(1,1)=='/' or path:find('//',1,true)then fail('Extra input path must be project-relative')end
   for part in path:gmatch('[^/]+')do if part=='.' or part=='..'then fail('Extra input path escapes the project')end end
   if d.format~='json' and d.format~='text'then fail('Extra input format must be json or text')end
   local bytes=cached[path] or read(path);if type(bytes)~='string' or #bytes>4*1024*1024 then fail('Missing or oversized extra input',path)end;cached[path]=bytes
   local ok,value=pcall(function()return S.check(schemas[d.name],d.format=='json' and J.decode(bytes) or bytes)end)
   if not ok then fail(type(value)=='table' and value.reason or tostring(value),path)end
   seen[d.name]=true;values[d.name]=value;locations[#locations+1]={name=d.name,path=path,format=d.format}
  end
  for key in pairs(schemas)do if not seen[key]then fail('Missing declared input '..key)end end
  return values,locations
 end
 return M
end
