return function(deps)
 local files,json,D=deps['build.files'],deps['contracts.json'],deps['contracts.diagnostic']
 local chars,png=deps['assets.characters'],deps['assets.png'];local M={}
 local function fail(reason)D.raise('E_CHARACTER_EXPORT',reason)end
 local function integer(n,lo,hi)return type(n)=='number' and n%1==0 and n>=lo and n<=hi end
 function M.collect(data,bindings)
  local found={}
  local function add(name,index)
   if name=='' or name==nil then return end
   if type(name)~='string' or not integer(index,0,7) or not files.relative(name..'.png')then fail('Invalid character image name/index')end
   local key=name..':'..string.format('%.0f',index);found[key]={key=key,name=name,index=index}
  end
  local function image(record)if record and record~=json.null then add(record.characterName,record.characterIndex)end end
  local function route(r,raw)
   for _,ins in ipairs(r and r.list or {})do
    if raw and ins.code==41 then add(ins.parameters[1],ins.parameters[2])
    elseif not raw and ins.op=='image'then add(ins.name,ins.index)end
   end
  end
  for _,actor in ipairs(data.database.Actors and data.database.Actors.records or {})do image(actor)end
  local system=data.database.System.records
  for _,key in ipairs({'boat','ship','airship'})do image(system[key])end
  for _,map in ipairs(data.maps)do for _,event in ipairs(map.events)do if event~=json.null then
   for _,page in ipairs(event.pages)do image(page.image);route(page.moveRoute,true)end
  end end end
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
   if ins.op=='actor_image' or ins.op=='vehicle_image'then image(ins)
   elseif ins.op=='move_route'then route(ins.route,false)end
  end end
  for key in pairs(bindings and bindings.characters or {})do
   if type(key)~='string'then fail('Character binding keys must be name:index')end
   local name,index=key:match('^(.*):(%d+)$');if not name then fail('Character binding keys must be name:index')end;add(name,tonumber(index))
  end
  local keys={};for key in pairs(found)do keys[#keys+1]=key end;table.sort(keys)
  local result={};for _,key in ipairs(keys)do result[#result+1]=found[key]end;return result
 end
 function M.bind(manifest,bindings)
  local function reject(reason)D.raise('E_CHARACTER_BINDINGS',reason)end
  if type(manifest)~='table' or manifest.kind~='r2u.character-export' or manifest.schemaVersion~=1 or not json.is_array(manifest.entries)then reject('Expected a character-export manifest')end
  bindings=bindings or {};bindings.characters=bindings.characters or {}
  for _,e in ipairs(manifest.entries)do
   if type(e)~='table' or type(e.name)~='string' or e.name=='' or not integer(e.index,0,7) or e.key~=e.name..':'..string.format('%.0f',e.index) or bindings.characters[e.key]then reject('Invalid or duplicate character key')end
   if not integer(e.width,1,4096) or not integer(e.height,1,4096) or not json.is_array(e.frames) or #e.frames~=12 then reject('Expected twelve character frames and valid dimensions')end
   local frames,bushFrames={},{};for i,f in ipairs(e.frames)do
    if type(f)~='table' or not integer(f.templateId,1,2147483647) or f.direction~=(math.floor((i-1)/3)+1)*2 or f.pattern~=(i-1)%3 then reject('Fill all twelve frame template IDs in down/left/right/up order: '..e.key)end
    frames[i]=f.templateId
    if e.bushDepth~=nil then
     if not integer(e.bushDepth,1,e.height) or not integer(f.upperTemplateId,1,2147483647) or not integer(f.lowerTemplateId,1,2147483647)then reject('Fill upperTemplateId/lowerTemplateId for bush frames: '..e.key)end
     bushFrames[i]={upperTemplateId=f.upperTemplateId,lowerTemplateId=f.lowerTemplateId}
    end
   end
   bindings.characters[e.key]={templateId=frames[2],frames=frames,width=e.width,height=e.height,displayWidth=e.width,displayHeight=e.height}
   if e.bushDepth then bindings.characters[e.key].bushDepth=e.bushDepth;bindings.characters[e.key].bushFrames=bushFrames end
  end
  return bindings
 end
 function M.export(data,config,root)
  local used=M.collect(data,config.assetBindings);local cache,items,sources={},{},{}
  local depth=config.engineProfile=='mv-turn' and 12 or (data.database.System.records.tileSize or 48)/4
  local dir='generated/'..config.gameId..'/characters'
  local manifest={kind='r2u.character-export',schemaVersion=1,entries=json.array(),sources=json.array(),
   instructions='Copy manifest.json to bindings.json; import PNGs as same-size container image templates, fill frames[].templateId and (when present) upperTemplateId/lowerTemplateId, then build with --character-bindings bindings.json. Re-export replaces manifest.json; keep completed bindings separately.'}
  for index,entry in ipairs(used)do
   local path='img/characters/'..entry.name..'.png';local image=cache[path]
   if not image then
    local bytes,reason=files.read(files.join(config.sourceRoot,path));if not bytes then D.raise('E_CHARACTER_SOURCE',tostring(reason),{file=path})end
    image=png.decode(bytes);cache[path]=image;sources[#sources+1]={path=path,width=image.width,height=image.height}
   end
   local layout=chars.layout(entry.name,entry.index,image.width,image.height)
   entry.width,entry.height=layout.width,layout.height;entry.source=path
   entry.bigCharacter,entry.objectCharacter=layout.bigCharacter,layout.objectCharacter;entry.frames=json.array()
   if not layout.objectCharacter then entry.bushDepth=depth end
   for phase,r in ipairs(layout.frames)do
    local name=string.format('%04d-%02d.png',index,phase)
    local frame=chars.crop(image,r)
    items[#items+1]={path=files.join(root,dir..'/'..name),bytes=png.encode(frame)}
    local descriptor={file=name,templateId=json.null,direction=r.direction,pattern=r.pattern,x=r.x,y=r.y}
    if entry.bushDepth then
     local upper,lower=chars.splitBush(frame,entry.bushDepth)
     descriptor.upperFile=name:gsub('%.png$','-upper.png');descriptor.lowerFile=name:gsub('%.png$','-lower.png')
     descriptor.upperTemplateId,descriptor.lowerTemplateId=json.null,json.null
     items[#items+1]={path=files.join(root,dir..'/'..descriptor.upperFile),bytes=png.encode(upper)}
     items[#items+1]={path=files.join(root,dir..'/'..descriptor.lowerFile),bytes=png.encode(lower)}
    end
    entry.frames[#entry.frames+1]=descriptor
   end
   manifest.entries[#manifest.entries+1]=entry
  end
  table.sort(sources,function(a,b)return a.path<b.path end);manifest.sources=json.array(sources);manifest.imageCount=#items
  items[#items+1]={path=files.join(root,dir..'/manifest.json'),bytes=json.encode(manifest)..'\n'}
  files.mkdirs(root,dir);local notes=files.commit(items)
  return{output=files.join(root,dir..'/manifest.json'),characterCount=#used,imageCount=manifest.imageCount,cleanupNotes=notes}
 end
 return M
end
