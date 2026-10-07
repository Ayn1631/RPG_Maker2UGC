-- Export only referenced map tiles and turn the resulting PNGs into explicit template bindings.
return function(deps)
 local files,json,D=deps['build.files'],deps['contracts.json'],deps['contracts.diagnostic']
 local tiles,png,resources=deps['assets.tiles'],deps['assets.png'],deps['converter.resources'];local M={}
 -- Resolve every animation frame through its unique-frame template ID and preserve table edges.
 function M.bind(manifest,bindings)
  local function fail(reason)D.raise('E_TILE_BINDINGS',reason)end
  local function id(value)return type(value)=='number' and value%1==0 and value>0 and value<=2147483647 end
  if type(manifest)~='table' or manifest.kind~='r2u.tile-export' or manifest.schemaVersion~=1 or not json.is_array(manifest.entries)then fail('Expected a tile-export manifest')end
  bindings=bindings or {};bindings.tiles=bindings.tiles or {}
  for _,e in ipairs(manifest.entries)do
   if type(e)~='table' or type(e.key)~='string' or not e.key:match('^[1-9]%d*:[1-9]%d*$') or bindings.tiles[e.key] then fail('Invalid or duplicate tile binding key')end
   if not json.is_array(e.uniqueFrames) or not json.is_array(e.frames) or #e.frames<1 then fail('Missing tile frames: '..e.key)end
   local templates={}
   for _,f in ipairs(e.uniqueFrames)do
    if type(f)~='table' or type(f.file)~='string' or templates[f.file] or not id(f.templateId)then fail('Fill every uniqueFrames.templateId: '..e.key)end
    templates[f.file]=f.templateId
   end
   local frames={};for i,file in ipairs(e.frames)do if type(file)~='string' or not templates[file]then fail('Unknown tile frame: '..e.key)end;frames[i]=templates[file]end
   local entry={templateId=frames[1],width=e.width,height=e.height,frameTicks=e.frameTicks}
   if #frames>1 then entry.frames=frames end
   if e.tableEdge~=nil then
    if type(e.tableEdge)~='table' or not id(e.tableEdge.templateId)then fail('Fill tableEdge.templateId: '..e.key)end
    entry.tableEdge=e.tableEdge.templateId
   end
   bindings.tiles[e.key]=entry
  end
  return bindings
 end
 -- Rasterize referenced tiles offline; identical frame recipes share one emitted PNG.
 function M.export(data,config,root)
  local function read(path)
   local bytes,reason=files.read(files.join(config.sourceRoot,path))
   if not bytes then D.raise('E_TILE_SOURCE',tostring(reason),{file=path})end
   return bytes
  end
  local core=config.engineProfile=='mv-turn' and 'js/rpg_core.js' or 'js/rmmz_core.js'
  local tables=tiles.tables(read(core));local definitions=resources.compile(data,{})
  local size=definitions.tileSize;local cache,sources,items={},{},{}
  local dir='generated/'..config.gameId..'/tiles'
  local manifest={kind='r2u.tile-export',schemaVersion=1,tileSize=size,sourceEngine=core,entries=json.array(),sources=json.array(),
   instructions='Copy manifest.json to bindings.json, import PNGs into image templates, fill uniqueFrames/templateId and tableEdge/templateId, then build with --tile-bindings bindings.json. Re-export replaces manifest.json; keep edited bindings separately. PNGs are not loaded at runtime.'}
  local keys={};for key in pairs(definitions.tiles)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tonumber(a)<tonumber(b)end)
  for _,setKey in ipairs(keys)do
   local set=data.database.Tilesets.records[tonumber(setKey)+1]
   local function sheet(index)
    local name=set.tilesetNames[index+1];if not name or name==''then return nil end
    local path='img/tilesets/'..name..'.png'
    if not cache[path]then
     cache[path]=png.decode(read(path));sources[path]=true
    end
    return cache[path]
   end
   local ids={};for key in pairs(definitions.tiles[setKey])do ids[#ids+1]=tonumber(key)end;table.sort(ids)
   for _,id in ipairs(ids)do
    local key=setKey..':'..id;local flag=set.flags[id+1]
    local entry={key=key,width=size,height=size,frameTicks=30,frames=json.array(),uniqueFrames=json.array()}
    -- Key by the serialized raster recipe so visually identical frames are emitted once.
    local recipes={}
    for frame=0,tiles.frameCount(id)-1 do
     local recipe=tiles.recipe(id,size,flag,frame,tables);local signature=json.encode(recipe);local name=recipes[signature]
     if not name then
      name=setKey..'-'..id..'-'..frame..'.png';recipes[signature]=name
      items[#items+1]={path=files.join(root,dir..'/'..name),bytes=png.encode(tiles.raster(recipe,size,sheet))}
      entry.uniqueFrames[#entry.uniqueFrames+1]={file=name,templateId=json.null,phase=frame,rectangles=json.array(recipe)}
     end
     entry.frames[#entry.frames+1]=name
    end
    if id>=2816 and id<4352 and flag&0x80~=0 then
     local name=setKey..'-'..id..'-edge.png';local recipe=tiles.recipe(id,size,flag,0,tables,true)
     entry.tableEdge={file=name,templateId=json.null,rectangles=json.array(recipe)}
     items[#items+1]={path=files.join(root,dir..'/'..name),bytes=png.encode(tiles.raster(recipe,size,sheet))}
    end
    manifest.entries[#manifest.entries+1]=entry
   end
  end
  local names={};for name in pairs(sources)do names[#names+1]=name end;table.sort(names)
  for _,name in ipairs(names)do manifest.sources[#manifest.sources+1]={path=name,width=cache[name].width,height=cache[name].height}end
  manifest.imageCount=#items
  items[#items+1]={path=files.join(root,dir..'/manifest.json'),bytes=json.encode(manifest)..'\n'}
  files.mkdirs(root,dir)
  local notes=files.commit(items)
  return{output=files.join(root,dir..'/manifest.json'),tileCount=#manifest.entries,imageCount=manifest.imageCount,cleanupNotes=notes}
 end
 return M
end
