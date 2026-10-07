-- Editable desktop Lua library -> selected immutable runtime artwork.
return function(deps)
 local F,D=deps['build.files'],deps['contracts.diagnostic']
 local A=deps['assets.primitive_art']
 local J,S=deps['contracts.json'],deps['build.serialize'];local M={}
 local function fail(s)D.raise('E_PRIMITIVE_ART',s)end
 local function records(data,name)return data.database[name] and data.database[name].records or {}end
 local function faceKey(name,index)return(name or '')..':'..string.format('%.0f',index or 0)end
 -- Every request below comes from a source reference, never a visual guess.
 function M.references(data)
  local refs={tiles={},characters={},faces={},icons={},enemies={},pictures={},battlebacks1={},battlebacks2={},parallaxes={},animations={},balloons={}}
  local function add(kind,key)if key~=nil and key~=''then refs[kind][type(key)=='number' and string.format('%.0f',key) or key]=true end end
  local resources=data.resources or deps['converter.resources'].compile(data)
  for set,defs in pairs(resources.tiles)do for id in pairs(defs)do add('tiles',set..':'..id)end end
  for _,r in ipairs(deps['converter.character_export'].collect(data))do add('characters',r.key)end
  local function face(name,index)if name and name~=''then add('faces',faceKey(name,index))end end
  for _,a in ipairs(records(data,'Actors'))do if a~=J.null then face(a.faceName,a.faceIndex)end end
  -- State icon 0 is native "no icon"; positive state/buff icons are already
  -- enumerated by resources.statusIconIndices. Item/message index 0 is distinct.
  for _,kind in ipairs({'Items','Weapons','Armors','Skills'})do for _,r in ipairs(records(data,kind))do if r~=J.null then
   if r.iconIndex~=nil then add('icons',r.iconIndex)end
   if r.animationId and r.animationId>0 then add('animations',r.animationId)end
  end end end
  for _,id in ipairs(resources.statusIconIndices or {})do add('icons',id)end
  for _,e in ipairs(records(data,'Enemies'))do if e~=J.null and e.battlerName~=''then add('enemies',e.id)end end
  local function tokens(stream)for _,v in ipairs(stream or {})do if v.kind=='icon'then add('icons',v.value)end end end
  for _,stream in pairs(resources.richHelp or {})do tokens(stream)end
  for _,map in ipairs(data.maps)do for _,kind in ipairs({'parallaxes','battlebacks1','battlebacks2'})do
   add(kind,map.settings[({parallaxes='parallaxName',battlebacks1='battleback1Name',battlebacks2='battleback2Name'})[kind]])
  end end
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
   if ins.op=='actor_image' or ins.op=='dialogue'then face(ins.faceName,ins.faceIndex)end
   if ins.op=='picture' and ins.action=='show'then add('pictures',ins.name)
   elseif ins.op=='parallax'then add('parallaxes',ins.name)
   elseif ins.op=='battle_background'then add('battlebacks1',ins.name1);add('battlebacks2',ins.name2)
   elseif ins.op=='animation' or ins.op=='enemy_animation'then if ins.animationId>0 then add('animations',ins.animationId)end
   elseif ins.op=='balloon'then if ins.balloonId>0 then add('balloons',ins.balloonId)end end
   tokens(ins.flowTokens);tokens(ins.speakerTokens);for _,stream in ipairs(ins.choiceTokens or {})do tokens(stream)end
  end end
  if data.visuWorld then
   refs.visuSvActors={}
   for _,a in ipairs(records(data,'Actors'))do if a~=J.null then
    add('visuSvActors',a.battlerName)
    for _,tag in ipairs({'Battle Portrait','Menu Portrait'})do add('pictures',a.visu and a.visu[tag])end
   end end
   for _,e in ipairs(records(data,'Enemies'))do if e~=J.null and e.visu and e.visu['Sideview Battlers']then
    for name in e.visu['Sideview Battlers']:gmatch('[^\r\n]+')do add('visuSvActors',name:match('^%s*(.-)%s*$'))end
   end end
   for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
    if ins.op=='actor_image'then add('visuSvActors',ins.battlerName)end
   end end
   add('balloons',10)
   for _,events in pairs(data.visuWorld.labels)do for _,pages in pairs(events)do for _,label in ipairs(pages)do add('icons',label.icon)end end end
   for _,r in ipairs(records(data,'Skills'))do if r~=J.null and r.visu then for _,ins in ipairs(r.visu.sequence or {})do
    local a=ins.args or {};if a.AnimationID then add('animations',a.AnimationID)end
   end end end
  end
  return refs
 end
 function M.export(data,config)
  local option=config.primitiveArt;if not option then fail('Configure primitiveArt.path with explicit source-mapped geometry')end
  -- The selection command must retain explicit bindings for source videos and
  -- effects while enumerating resources, just like the normal build command.
  data.resources=data.resources or deps['converter.resources'].compile(data,config.assetBindings,config.worldPreview and config.worldPreview.artTemplates)
  local bytes=F.read(option.path)
  if not bytes then fail('Missing explicit primitive library: '..option.path..'. Convert source drawing recipes or bind source assets; automatic shape generation was removed.')end
  local chunk,reason=load(bytes,'@'..option.path,'t',{});if not chunk then fail(reason)end
  local library=chunk()
  if type(library)~='table' or library.kind~='r2u.primitive-library' or library.schemaVersion~=1 then fail('Invalid explicit primitive library')end
  local selected={kind=library.kind,schemaVersion=1,style=library.style,sourceRecipe=library.sourceRecipe}
  for kind,keys in pairs(M.references(data))do if kind~='animations' and kind~='balloons'then
   selected[kind]={}
   for key in pairs(keys)do
    local value=library[kind] and library[kind][key]
    if not value then fail('Missing explicit primitive resource: '..kind..'/'..key)end
    if kind=='characters' or kind=='visuSvActors'then
     if #value.frames~=(kind=='characters'and 12 or 54) then fail('Invalid explicit motion frame count: '..key)end
     for _,f in ipairs(value.frames)do A.validate(f)end
    else A.validate(value)end
    selected[kind][key]=value
   end
  end end
  local path=option.path..'.selected.lua'
  F.commit({{path=path,bytes='-- Selected explicit source resource geometry; no inferred artwork.\nreturn '..S.literal(selected)..'\n'}})
  return {output=path,style=selected.style,sourceImages=0,unavailableSources={}}
 end
 function M.validateResources(data)
  local res=data.resources;local missing={}
  for kind,keys in pairs(M.references(data))do for key in pairs(keys)do
   local value
   if kind=='tiles'then local set,id=key:match('^(%d+):(%d+)$');value=res.tiles[set] and res.tiles[set][id]
   elseif kind=='faces'then value=res.faces and res.faces[key] or res.faceTemplates and res.faceTemplates[key]
   elseif kind=='icons'then value=res.icons and res.icons[key] or res.iconTemplates and res.iconTemplates[key]
   else value=res[kind] and res[kind][key]end
   local valid=type(value)=='number' or type(value)=='table' and (value.kind=='r2u.primitive-frame' or value.primitive or value.primitiveFrames or value.templateId or value.frames)
   if not valid then missing[#missing+1]=kind..'/'..key end
  end end
  table.sort(missing)
  if #missing>0 then fail('Missing explicit resource bindings ('..#missing..'): '..table.concat(missing,', '))end
 end
 local function frame(value)
  A.validate(value);return{kind=value.kind,schemaVersion=1,width=value.width,height=value.height,palette=value.palette,rects=value.rects,cols=value.cols,rows=value.rows,composition=value.composition}
 end
 local function composedChunks(data)
  local res=data.resources;res.primitiveChunks={};local size=res.tileSize;local statistics={tiles=0,rectangles=0,chunks=0,occludedTiles=0}
  for _,map in ipairs(data.maps)do local maps={};res.primitiveChunks[tostring(map.id)]=maps
   for set,defs in pairs(res.tiles)do local plans={};maps[set]=plans
    -- Only eliminate art proven to be covered by a later opaque lower-layer
    -- tile. Keep overhangs, rotated bounds, translucent art and upper layers.
    -- This is offline geometry work; collision/event data is never changed.
    local opaque,contained,hidden={},{},{}
    for id,d in pairs(defs)do local f=d.primitive
     if f and not d.primitiveLayout then
      local inside=true
      for _,r in ipairs(f.rects)do
       local angle=(r.rotation or 0)*math.pi/180;local c,s=math.abs(math.cos(angle)),math.abs(math.sin(angle))
       local hw,hh=(r.width*c+r.height*s)/2,(r.width*s+r.height*c)/2
       local cx,cy=r.x+r.width/2,r.y+r.height/2
       if cx-hw<0 or cy-hh<0 or cx+hw>f.width or cy+hh>f.height then inside=false end
       if not d.upper and not r.imageId and not r.rotation and r.x<=0 and r.y<=0 and r.x+r.width>=f.width and r.y+r.height>=f.height and f.palette[r.colorIndex][4]==255 then opaque[id]=true end
      end
      contained[id]=inside
     end
    end
    local area=map.width*map.height
    for cell=1,area do local covered=false
     for z=3,0,-1 do
      local index=z*area+cell;local id=tostring(map.tiles[index]);local d=defs[id]
      if covered and d and not d.upper and contained[id]then hidden[index]=true;statistics.occludedTiles=statistics.occludedTiles+1 end
      if opaque[id]then covered=true end
     end
    end
    local function block(tx,ty,w,h,z,upper)
     local palette,colors,grid,parts={},{},{},{};local count=0
     local function color(p)local key=table.concat(p,',');if not colors[key]then palette[#palette+1]=p;colors[key]=#palette end;return colors[key]end
     for y=0,h-1 do for x=0,w-1 do
      local index=(z*map.height+ty+y)*map.width+tx+x+1
      local id=map.tiles[index];local d=defs[tostring(id)];local f=d and d.primitive
      if f then d.mergedPrimitive=true end
      if f and d.upper==upper and not hidden[index]then count=count+1
       for i,r in ipairs(f.rects)do local c=color(f.palette[r.colorIndex])
        local layout=d.primitiveLayout;local ox,oy,dw,dh=0,0,size,size
        if layout then ox,oy,dw,dh=layout.x,layout.y,layout.width,layout.height end
        if not layout and i==1 and not r.imageId and not r.rotation and r.x==0 and r.y==0 and r.width==f.width and r.height==f.height then grid[y*w+x+1]=c
        else parts[#parts+1]={x=x*size+ox+r.x/f.width*dw,y=y*size+oy+r.y/f.height*dh,width=r.width/f.width*dw,height=r.height/f.height*dh,colorIndex=c,rotation=r.rotation,imageId=r.imageId}end
       end
      end
     end end
     if count==0 then return end
     local f=A.merge(grid,w,h,palette,size,size)
     for _,part in ipairs(parts)do f.rects[#f.rects+1]=part end
     -- Sparse ground remains merged up to 8x8. Dense structural art is split
     -- offline down to 2x2 so viewport edges don't load hundreds of hidden
     -- components. No runtime geometry rebuild or rasterization is needed.
     if #f.rects>48 and (w>2 or h>2)then
      local stepX=w>2 and math.ceil(w/2) or w;local stepY=h>2 and math.ceil(h/2) or h
      for y=0,h-1,stepY do for x=0,w-1,stepX do block(tx+x,ty+y,math.min(stepX,w-x),math.min(stepY,h-y),z,upper)end end
      return
     end
     if #f.rects>0 then
      -- A multi-cell object's parts are owned once, by their centre cell.
      -- Enlarge only the compiled mount bounds to cover geometric overhang;
      -- the source map tiles, layers and collision flags remain untouched.
      local left,top,right,bottom=0,0,f.width,f.height
      for _,r in ipairs(f.rects)do
       local angle=(r.rotation or 0)*math.pi/180;local c,s=math.abs(math.cos(angle)),math.abs(math.sin(angle))
       local hw,hh=(r.width*c+r.height*s)/2,(r.width*s+r.height*c)/2
       local cx,cy=r.x+r.width/2,r.y+r.height/2
       left=math.min(left,r.x,cx-hw);top=math.min(top,r.y,cy-hh)
       right=math.max(right,r.x+r.width,cx+hw);bottom=math.max(bottom,r.y+r.height,cy+hh)
      end
      for _,r in ipairs(f.rects)do r.x,r.y=r.x-left,r.y-top end
      f.width,f.height=right-left,bottom-top
      plans[#plans+1]={x=tx*size+left,y=ty*size+top,layer=z,upper=upper,frame=f};statistics.chunks=statistics.chunks+1;statistics.rectangles=statistics.rectangles+#f.rects
     end
     statistics.tiles=statistics.tiles+count
    end
    for cy=0,math.ceil(map.height/8)-1 do for cx=0,math.ceil(map.width/8)-1 do
     for z=0,3 do for _,upper in ipairs({false,true})do block(cx*8,cy*8,math.min(8,map.width-cx*8),math.min(8,map.height-cy*8),z,upper)end end
    end end
   end
  end
  res.primitiveStyle.mapGeometry=statistics
 end
 local function indexChunks(resources)
  -- Bake the spatial lookup offline; the UGC host never builds an index.
  resources.primitiveChunkIndex={};local size=resources.tileSize*4
  for mapId,sets in pairs(resources.primitiveChunks)do local maps={};resources.primitiveChunkIndex[mapId]=maps
   for setId,plans in pairs(sets)do local buckets={};maps[setId]={cellSize=size,buckets=buckets}
    for i,plan in ipairs(plans)do
     for y=math.floor(plan.y/size),math.ceil((plan.y+plan.frame.height)/size)-1 do
      for x=math.floor(plan.x/size),math.ceil((plan.x+plan.frame.width)/size)-1 do
       local key=x..':'..y;local bucket=buckets[key] or {};buckets[key]=bucket;bucket[#bucket+1]=i
      end
     end
    end
   end
  end
 end
 function M.chunks(data)
  if data.resources.primitiveStyle.name=='structural-shape-composition'then composedChunks(data);indexChunks(data.resources);return end
  local res=data.resources;res.primitiveChunks={};local size=res.tileSize;local chunkSize=8;local statistics={tiles=0,rectangles=0,chunks=0}
  for _,map in ipairs(data.maps)do local maps={};res.primitiveChunks[tostring(map.id)]=maps
   for set,defs in pairs(res.tiles)do local plans={};maps[set]=plans
    local gridSize=4
    for _,d in pairs(defs)do if d.primitive then local f=d.primitive
     local n=math.max(f.cols or 4,f.rows or 4)
     if not ({[1]=true,[2]=true,[4]=true,[8]=true,[16]=true,[32]=true})[n]then fail('Terrain grid must use power-of-two detail up to 32')end
     gridSize=math.max(gridSize,n)
    end end
    for cy=0,math.ceil(map.height/chunkSize)-1 do for cx=0,math.ceil(map.width/chunkSize)-1 do
     local w,h=math.min(chunkSize,map.width-cx*chunkSize),math.min(chunkSize,map.height-cy*chunkSize)
     for z=0,3 do for _,upper in ipairs({false,true})do
      local grid,palette,colors={},{},{};local sourceTiles=0
      for y=0,h-1 do for x=0,w-1 do local id=map.tiles[(z*map.height+cy*chunkSize+y)*map.width+cx*chunkSize+x+1]
       local d=defs[tostring(id)];local f=d and d.primitive
       if f and d.upper==upper then
        local aligned=true;for _,r in ipairs(f.rects)do
         if r.imageId then fail('Native image primitives require structural-shape-composition')end
         for _,v in ipairs({r.x/f.width*gridSize,r.y/f.height*gridSize,r.width/f.width*gridSize,r.height/f.height*gridSize})do if math.abs(v-math.floor(v+.5))>1e-7 then aligned=false end end end
        if not aligned then fail('Terrain primitive rectangles must align to the shared detail grid')end
        sourceTiles=sourceTiles+1;d.mergedPrimitive=true
        for _,r in ipairs(f.rects)do local p=f.palette[r.colorIndex];local key=table.concat(p,',');local c=colors[key]
         if not c then palette[#palette+1]=p;c=#palette;colors[key]=c end
         for yy=math.floor(r.y/f.height*gridSize+.5),math.floor((r.y+r.height)/f.height*gridSize+.5)-1 do
          for xx=math.floor(r.x/f.width*gridSize+.5),math.floor((r.x+r.width)/f.width*gridSize+.5)-1 do grid[(y*gridSize+yy)*w*gridSize+x*gridSize+xx+1]=c end end
        end
       end
      end end
      if sourceTiles>0 then local f=A.merge(grid,w*gridSize,h*gridSize,palette,size/gridSize,size/gridSize)
       if #f.rects>0 then plans[#plans+1]={x=cx*chunkSize*size,y=cy*chunkSize*size,layer=z,upper=upper,frame=f};statistics.chunks=statistics.chunks+1;statistics.rectangles=statistics.rectangles+#f.rects end
       statistics.tiles=statistics.tiles+sourceTiles
      end
     end end
    end end
   end
  end
  res.primitiveStyle.mapGeometry=statistics
  indexChunks(res)
 end
 function M.apply(data,library)
  if type(library)~='table' or library.kind~='r2u.primitive-library' or library.schemaVersion~=1 then fail('Invalid primitive library')end
  local res=data.resources;local used=0;res.faces={};res.icons={}
  if data.visuWorld then
   res.visuLabels=data.visuWorld.labels;res.visuBattleLayout={maxBattleMembers=4,sourceHome='visu-sample',actorBattlers={}}
   res.visuLabelColors=data.uiSkin and data.uiSkin.textColors
   res.visuBattleLayout.attackMotions=records(data,'System').attackMotions
   res.visuBattleLayout.magicSkillTypes=records(data,'System').magicSkills
   res.visuBattleLayout.weaponTypesById={};res.visuBattleLayout.skillTypesById={}
   for _,r in ipairs(records(data,'Weapons'))do if r~=J.null then res.visuBattleLayout.weaponTypesById[tostring(r.id)]=r.wtypeId end end
   for _,r in ipairs(records(data,'Skills'))do if r~=J.null then res.visuBattleLayout.skillTypesById[tostring(r.id)]=r.stypeId end end
   for _,a in ipairs(records(data,'Actors'))do if a~=J.null then res.visuBattleLayout.actorBattlers[tostring(a.id)]=a.battlerName end end
  end
  local requests=M.references(data)
  for key in pairs(requests.icons)do local value=library.icons and library.icons[key];if value then res.icons[key]=frame(value)end end
  if requests.visuSvActors then res.visuSvActors={};res.visuPortraits={}
   for name in pairs(requests.visuSvActors)do local value=library.visuSvActors and library.visuSvActors[name]
    if value then local frames={};if #value.frames~=54 then fail('SV actor requires 18 motions of 3 frames: '..name)end
     for i,f in ipairs(value.frames)do frames[i]=frame(f)end
     res.visuSvActors[name]={width=value.width,height=value.height,primitiveFrames=frames}
    end
   end
   for _,a in ipairs(records(data,'Actors'))do if a~=J.null and a.visu then
    res.visuPortraits[tostring(a.id)]={battle=a.visu['Battle Portrait'],menu=a.visu['Menu Portrait']}
   end end
  end
  for _,kind in ipairs({'animations','balloons'})do for key in pairs(requests[kind])do
   local value=library[kind] and library[kind][key]
   if value then
    local frames={};for i,f in ipairs(value.frames)do frames[i]=frame(f)end
    if #frames<1 then fail('Empty effect sequence '..kind..'/'..key)end
    res[kind][key]={primitiveFrames=frames,width=frames[1].width,height=frames[1].height,
     durationFrames=value.durationFrames,frameTicks=value.frameTicks,renderKey='primitive-'..kind..':'..key}
    if kind=='animations' and data.visuWorld then
     local source=records(data,'Animations')[tonumber(key)+1];local out=res[kind][key];out.soundTimings={}
     for _,timing in ipairs(source and source.soundTimings or {})do
      if timing.se.name~='' and timing.se.index==nil then fail('Unbound animation sound '..key..'/'..timing.se.name)end
      out.soundTimings[#out.soundTimings+1]={frame=timing.frame,se=timing.se}
      out.durationFrames=math.max(out.durationFrames,timing.frame+1)
     end
    end
   end
  end end
  for set,defs in pairs(res.tiles)do for id,def in pairs(defs)do local value=library.tiles and library.tiles[set..':'..id]
   if value then def.primitive=frame(value);def.primitiveLayout=value.tileLayout;def.templateId,def.frames=nil,nil;used=used+1 end
  end end
  for _,r in ipairs(deps['converter.character_export'].collect(data))do local value=library.characters and library.characters[r.key]
   if value then if #value.frames~=12 then fail('Character requires twelve primitive frames')end
    local frames={};for i,v in ipairs(value.frames)do frames[i]=frame(v);if v.width~=value.width or v.height~=value.height then fail('Character frame dimensions must match its mount')end end
    res.characters[r.key]={width=value.width,height=value.height,primitiveFrames=frames};used=used+1
   end
  end
  for _,enemy in ipairs(records(data,'Enemies'))do if enemy~=J.null then local value=library.enemies and library.enemies[tostring(enemy.id)]
   if value then local f=frame(value);res.enemies[tostring(enemy.id)]={width=f.width,height=f.height,primitive=f};used=used+1 end
  end end
  if data.uiArt then
   for _,actor in ipairs(data.uiArt.actors)do local source=records(data,'Actors')[actor.actorId+1];local value=source and library.faces and library.faces[faceKey(source.faceName,source.faceIndex)]
    if value then actor.primitive=frame(value);actor.templateId=nil;used=used+1 end
   end
   for _,icon in ipairs(data.uiArt.icons)do local value=library.icons and library.icons[string.format('%.0f',icon.iconIndex)];if value then icon.primitive=frame(value);res.icons[string.format('%.0f',icon.iconIndex)]=icon.primitive;icon.templateId=nil;used=used+1 end end
  end
  local function background(kind,name)
   local value=name and library[kind] and library[kind][name]
   if value then local f=frame(value);res[kind][name]={width=f.width,height=f.height,primitive=f};used=used+1 end
  end
  for name in pairs(requests.pictures)do background('pictures',name)end
  for _,map in ipairs(data.maps)do background('parallaxes',map.settings.parallaxName);background('battlebacks1',map.settings.battleback1Name);background('battlebacks2',map.settings.battleback2Name)end
  local function useFace(name,index)
   local key=faceKey(name,index);local value=library.faces and library.faces[key]
   if value then res.faces[key]=frame(value)end
  end
  for _,actor in ipairs(records(data,'Actors'))do if actor~=J.null then useFace(actor.faceName,actor.faceIndex)end end
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
   if ins.op=='animation' or ins.op=='enemy_animation'then ins.asset=res.animations[string.format('%.0f',ins.animationId)]
   elseif ins.op=='balloon'then ins.asset=res.balloons[string.format('%.0f',ins.balloonId)]end
   if ins.op=='parallax'then background('parallaxes',ins.name)
   elseif ins.op=='battle_background'then background('battlebacks1',ins.name1);background('battlebacks2',ins.name2)end
   if ins.op=='picture' and ins.action=='show' then
    local value=library.pictures and library.pictures[ins.name]
    if value then
     if not res.pictures[ins.name] or not res.pictures[ins.name].primitive then
      local f=frame(value);res.pictures[ins.name]={width=f.width,height=f.height,primitive=f,renderKey='primitive-picture:'..ins.name};used=used+1
     end
     ins.asset=res.pictures[ins.name]
    end
   end
   if ins.op=='dialogue' or ins.op=='actor_image'then useFace(ins.faceName,ins.faceIndex)end
   local streams={ins.flowTokens or {},ins.speakerTokens or {}};for _,tokens in ipairs(ins.choiceTokens or {})do streams[#streams+1]=tokens end
   for _,tokens in ipairs(streams)do for _,token in ipairs(tokens)do
    if token.kind=='icon'then local key=string.format('%.0f',token.value);local value=library.icons and library.icons[key];if value then res.icons[key]=frame(value)end end
   end end
  end end
  res.primitiveStyle={name=library.style,assets=used,terrainAnimation='static-collage'}
  for _,index in ipairs(res.statusIconIndices or {})do local key=string.format('%.0f',index);local value=library.icons and library.icons[key];if value then res.icons[key]=frame(value)end end
  for _,tokens in pairs(res.richHelp or {})do for _,token in ipairs(tokens)do
   if token.kind=='icon'then local key=string.format('%.0f',token.value);local value=library.icons and library.icons[key];if value then res.icons[key]=frame(value)end end
  end end
  M.chunks(data)
  return used
 end
 return M
end
