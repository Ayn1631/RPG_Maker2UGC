-- World-space mounts: one scrolling parent, buffered chunks and immutable assets.
return function()
 local M={}
 local function fail(reason)error('E_MAP_VIEW: '..reason,0)end
 local function build(host,parent,bindings,ui,map,resources,actors,onRoot)
  local game,enum,color=host.game,host.Enum,host.Color
  local updates=bindings.updates
  local function call(object,name,...)
   if updates then updates.call(object,name,...)else object[name](object,...)end
  end
  local sw,sh=ui.screen.width,ui.screen.height;local cell=resources.tileSize or 48
  local live,count={},0;local stats={created=0,destroyed=0,live=0,peak=0,tileRebinds=0,positionWrites=0,characterSorts=0,framePrunes=0};local closed=false
  local reclaim
  local function reserve(needed,name)
   if count+needed>6000 and reclaim then reclaim(needed)end
   if count+needed>6000 then fail('Map control budget exceeded: live='..count..', limit=6000, needed='..needed..', requested='..tostring(name))end
  end
  local function create(id,name,owner)
   reserve(1,name)
   local o=game.InstantiateClientUIControl(id,owner);if not o then fail('Missing map template '..tostring(id))end
   o.name=name;count=count+1;stats.created=stats.created+1;stats.live=count;stats.peak=math.max(stats.peak,count);return o
  end
  local function place(o,x,y,w,h,pw,ph)
   o:SetAnchorMin(.5,.5);o:SetAnchorMax(.5,.5);o:SetPivot(.5,.5)
   o:SetSizeDelta(w,h);o:SetAnchoredPosition(x+w/2-pw/2,ph/2-y-h/2);o:SetActive(true);o:SetVisible(true)
  end
  local function group(name,owner,w,h,x,y,pw,ph)
   local o=create(bindings.containerTemplate,name,owner);place(o,x or 0,y or 0,w,h,pw or sw,ph or sh)
   return {object=o,width=w,height=h,x=x or 0,y=y or 0,children={},visible=true}
  end
  local function solid(name,owner,x,y,w,h,paint,imageId)
   local o=create(bindings.imageTemplate,name,owner.object);o:SetImage(enum.ImageSource.StaticReference,imageId or bindings.whiteImageId)
   o.imageColor=color.FromRGBA(paint[1],paint[2],paint[3],paint[4]);o.enableMask=false;o.enableSoftEdge=false;o:SetFillUnused()
   place(o,x,y,w,h,owner.width,owner.height);owner.children[#owner.children+1]=o;return o
  end
  local function visible(g,value)
   if g.visible~=value then
    g.visible=value;call(g.object,'SetVisible',value)
    if g.animBucket then for _,o in ipairs(g.children)do call(o,'SetVisible',value)end end
   end
  end
  local function move(g,x,y,pw,ph)
   if g.x==x and g.y==y then return end;g.x,g.y=x,y
   call(g.object,'SetAnchoredPosition',x+g.width/2-(pw or sw)/2,(ph or sh)/2-y-g.height/2);stats.positionWrites=stats.positionWrites+1
  end
  local function clear(g)
   if g.animBucket then g.animBucket.refs=g.animBucket.refs-1;g.animBucket=nil end
   for _,o in ipairs(g.children)do if o.alive then game.DestroyClientUIControl(o)end;count=count-1;stats.destroyed=stats.destroyed+1 end
   g.children={};g.paint=nil;stats.live=count
  end
  local function capture(object,out)
   for _,key in ipairs({'imageColor','fontColor','bgColor','outlineColor'})do
    local ok,value=pcall(function()return object[key]end)
    if ok and value~=nil then local success,r,g,b,a=pcall(color.ToRGBA,value)
     if success then out[#out+1]={object=object,key=key,r=r,g=g,b=b,a=a}end
    end
   end
   for _,child in ipairs(object:GetChildren())do capture(child,out)end
  end
  local function art(g,def,name)
   local o=create(def.templateId,name,g.object)
   if def.displayWidth then
    -- Native sprites anchor at their feet, even when taller than a tile.
    place(o,(g.width-def.width)/2,g.height-def.displayHeight/2-def.height/2,def.width,def.height,g.width,g.height)
    o:SetLocalScale(def.displayWidth/def.width,def.displayHeight/def.height,1)
   else
    place(o,(g.width-def.width)/2,(g.height-def.height)/2,def.width,def.height,g.width,g.height)
    o:SetLocalScale(math.min(g.width/def.width,g.height/def.height),math.min(g.width/def.width,g.height/def.height),1)
   end
   g.children[#g.children+1]=o
   return o
  end
  local function rememberPaint(out,o,p,alpha)
   if out then out[#out+1]={object=o,key='imageColor',r=p[1],g=p[2],b=p[3],a=alpha}end
  end
  local function primitive(g,frame,name,x,y,w,h,opacity,bush,paintOut,first,last)
   x,y,w,h=x or 0,y or 0,w or g.width,h or g.height;opacity=opacity or 255
   for i=first or 1,last or #frame.rects do local r=frame.rects[i]
    local rx,ry,rw,rh=x+r.x/frame.width*w,y+r.y/frame.height*h,r.width/frame.width*w,r.height/frame.height*h
    local p=frame.palette[r.colorIndex];local cut=bush and cell-(resources.bushDepth or 12) or math.huge
    local upper=math.max(0,math.min(rh,cut-ry))
    if r.rotation or r.imageId then
     local alpha=p[4]*(ry+rh/2>=cut and 128/255 or 1)
     -- Asset coordinates grow downwards; UGC UI rotation uses an upwards Y axis.
     local o=solid(name..' '..i,g,rx,ry,rw,rh,{p[1],p[2],p[3],alpha*opacity/255},r.imageId);if r.rotation then o:SetLocalRotation(0,0,-r.rotation)end
     rememberPaint(paintOut,o,p,alpha)
    else
     if upper>0 then local o=solid(name..' '..i,g,rx,ry,rw,upper,{p[1],p[2],p[3],p[4]*opacity/255});rememberPaint(paintOut,o,p,p[4])end
     if upper<rh then local alpha=p[4]*128/255;local o=solid(name..' '..i..' bush',g,rx,ry+upper,rw,rh-upper,{p[1],p[2],p[3],alpha*opacity/255});rememberPaint(paintOut,o,p,alpha)end
    end
   end
  end
  local root=group('RPG map',parent,sw,sh);live[1]=root.object;onRoot(root.object)
  solid('RPG map viewport',root,0,0,sw,sh,{31,42,49,255})
  local parallax=group('RPG map parallax',root.object,sw,sh);local parallaxKey
  local function updateParallax(view)
   local state=view.camera and view.camera.parallax
   local name=state and state.name or '';local def=(resources.parallaxes or {})[name]
   local key=name..':'..tostring(def and def.templateId)
   if key~=parallaxKey then
    parallaxKey=key;clear(parallax);visible(parallax,name~='')
    if name~='' then
     if def then
      for row=0,math.ceil(sh/def.height)do for col=0,math.ceil(sw/def.width)do
       if def.primitive then primitive(parallax,def.primitive,'RPG parallax geometry',col*def.width,row*def.height,def.width,def.height)
       else local o=create(def.templateId,'RPG parallax tile',parallax.object)
        place(o,col*def.width,row*def.height,def.width,def.height,sw,sh);parallax.children[#parallax.children+1]=o
       end
      end end
     else fail('Missing parallax resource: '..name)end
    end
   end
   if def then move(parallax,-(state.x%def.width),-(state.y%def.height))else move(parallax,0,0)end
  end
  -- Container parents work in both simulator renderers. Image-parent masking
  -- renders children differently in Web 0.3.5; outer screen bars clip overflow.
  local worldRoot=group('RPG map world',root.object,sw,sh)
  local lower=group('RPG map lower',worldRoot.object,sw,sh);local people=group('RPG map characters',worldRoot.object,sw,sh);local upper=group('RPG map upper',worldRoot.object,sw,sh)
  local lowerZ,upperZ={},{};local shadows,edges;local hasShadows,hasEdges=false,false
  for z=0,3 do
   lowerZ[z]=group('RPG lower layer '..z,lower.object,sw,sh)
   upperZ[z]=group('RPG upper layer '..z,upper.object,sw,sh)
   if z==1 then shadows=group('RPG shadows',lower.object,sw,sh);edges=group('RPG table edges',lower.object,sw,sh)end
  end
  local primitiveMounts,primitiveSerial,primitiveWanted={},0,{};local tilesetId=map.tilesetId
  local function destroyGroup(g)
   -- Destroying the parent releases its descendants (also used by S.close).
   -- Do not cross the native bridge once for every immutable child first.
   local released=1+#g.children
   game.DestroyClientUIControl(g.object);g.children={}
   count=count-released;stats.destroyed=stats.destroyed+released;stats.live=count
  end
  local function discardChunk(key,g)
   destroyGroup(g);primitiveMounts[key]=nil
  end
  local prepareQueue,prepareIndex={},1
  local visibleQueue,visibleIndex={},1
  local terrainCredit,tileCredit=96,8
  local edgeCredit=24;local motionX,motionY=0,0
  local function sortPreparation()
   for _,p in ipairs(prepareQueue)do
    p.ahead=p.sideX*motionX+p.sideY*motionY
   end
   table.sort(prepareQueue,function(a,b)
    if a.ahead~=b.ahead then return a.ahead>b.ahead end
    if a.distance~=b.distance then return a.distance<b.distance end
    return a.key<b.key
   end)
   prepareIndex=1
  end
  local function chunkVisible(g,value)
   if g.active~=value then g.active=value;call(g.object,'SetActive',value)end
   visible(g,value)
  end
  local function mountPrimitive(placement,budget)
   local key,plan=placement.key,placement.plan;local g=primitiveMounts[key]
   local spent=0
   if not g then
    reserve(1+#plan.frame.rects,'terrain chunk '..key)
    g=group('RPG geometry chunk '..key,(plan.upper and upperZ or lowerZ)[plan.layer].object,plan.frame.width,plan.frame.height,placement.x,placement.y)
    g.nextRect=1;g.active=true;primitiveMounts[key]=g;spent=1
   end
   local last=budget and math.min(#plan.frame.rects,g.nextRect+budget-spent-1) or #plan.frame.rects
   if last>=g.nextRect then
    primitive(g,plan.frame,'RPG terrain block',nil,nil,nil,nil,nil,nil,nil,g.nextRect,last)
    spent=spent+last-g.nextRect+1;g.nextRect=last+1
   end
   g.used=primitiveSerial;g.ready=g.nextRect>#plan.frame.rects;chunkVisible(g,g.ready)
   return spent
  end
  local function updatePrimitives(ix,iy)
   local maps=resources.primitiveChunks and resources.primitiveChunks[tostring(map.id)]
   local plans=maps and maps[tostring(tilesetId)] or {};local wanted,buffered,placements={},{},{};primitiveSerial=primitiveSerial+1
   prepareQueue,prepareIndex={},1
   local mw,mh=map.width*cell,map.height*cell;local margin=2*cell
   local loopX=map.scrollType==2 or map.scrollType==3;local loopY=map.scrollType==1 or map.scrollType==3
   local indexes=resources.primitiveChunkIndex and resources.primitiveChunkIndex[tostring(map.id)]
   local index=indexes and indexes[tostring(tilesetId)];local candidates
   if index and not loopX and not loopY then
    candidates={};local seen={};local size=index.cellSize
    for y=math.floor((iy*cell-margin)/size),math.floor((iy*cell+sh+margin)/size)do
     for x=math.floor((ix*cell-margin)/size),math.floor((ix*cell+sw+margin)/size)do
      for _,i in ipairs(index.buckets[x..':'..y] or {})do
       if not seen[i]then seen[i]=true;candidates[#candidates+1]=i end
      end
     end
    end
    -- Keep the compiled order for overlapping art. Looping maps retain the
    -- complete offset-aware path; old bundles without indexes remain valid.
    table.sort(candidates)
   end
   for n=1,candidates and #candidates or #plans do
    local i=candidates and candidates[n] or n;local plan=plans[i]
    local minX,maxX,minY,maxY=0,0,0,0
    if loopX then minX=math.floor((ix*cell-margin-plan.x-plan.frame.width)/mw);maxX=math.ceil((ix*cell+sw+margin-plan.x)/mw)end
    if loopY then minY=math.floor((iy*cell-margin-plan.y-plan.frame.height)/mh);maxY=math.ceil((iy*cell+sh+margin-plan.y)/mh)end
    for oy=minY,maxY do for ox=minX,maxX do
     local wx,wy=plan.x+ox*mw,plan.y+oy*mh;local x,y=wx-ix*cell,wy-iy*cell
     if x+plan.frame.width> -margin and y+plan.frame.height> -margin and x<sw+margin and y<sh+margin then
      local key=tostring(tilesetId)..':'..i..':'..ox..':'..oy
      local placement={key=key,plan=plan,x=wx,y=wy}
      buffered[key]=true
      if x+plan.frame.width>0 and y+plan.frame.height>0 and x<sw and y<sh then
       wanted[key]=true;placements[#placements+1]=placement
      elseif x+plan.frame.width> -cell and y+plan.frame.height> -cell and x<sw+cell and y<sh+cell then
       placement.distance=math.max(0,-x-plan.frame.width,x-sw,-y-plan.frame.height,y-sh)
       placement.sideX=x>=sw and 1 or x+plan.frame.width<=0 and -1 or 0
       placement.sideY=y>=sh and 1 or y+plan.frame.height<=0 and -1 or 0
       prepareQueue[#prepareQueue+1]=placement
      end
     end
    end end
   end
   primitiveWanted=wanted
   local idle={};local idleCost=0
   for key,g in pairs(primitiveMounts)do
    if buffered[key]then g.used=primitiveSerial;chunkVisible(g,g.ready)
    else chunkVisible(g,false);idle[#idle+1]={key=key,group=g};idleCost=idleCost+1+#g.children end
   end
   table.sort(idle,function(a,b)return a.group.used<b.group.used end)
   for i,e in ipairs(idle)do
    if #idle-i+1<=12 and idleCost<=256 then break end
    idleCost=idleCost-1-#e.group.children;discardChunk(e.key,e.group)
   end
   -- Required terrain uses the same bounded path as the scroll guard. A camera
   -- jump or opening the map must not synchronously clone the whole viewport.
   visibleQueue,visibleIndex=placements,1
   sortPreparation()
   stats.live=count
  end
  local function prepareVisible()
   while terrainCredit>0 and tileCredit>0 and visibleIndex<=#visibleQueue do
    local p=visibleQueue[visibleIndex];local g=primitiveMounts[p.key]
    if g and g.ready then visibleIndex=visibleIndex+1
    else
     local spent=mountPrimitive(p,terrainCredit)
     terrainCredit=terrainCredit-spent;tileCredit=tileCredit-1
     stats.frameTerrainGroups=(stats.frameTerrainGroups or 0)+1
     stats.frameTerrainControls=(stats.frameTerrainControls or 0)+spent
     if not primitiveMounts[p.key].ready then break end
     visibleIndex=visibleIndex+1
    end
   end
  end
  local function prepareEdge()
   -- One tile is a scroll guard, not a second viewport. Bound native cloning
   -- across frames; never evict useful terrain for optional preparation.
   local blocked
   while edgeCredit>0 and terrainCredit>0 and tileCredit>0 and prepareIndex<=#prepareQueue do
    local p=prepareQueue[prepareIndex];local g=primitiveMounts[p.key]
    local needed=g and #p.plan.frame.rects-g.nextRect+1 or 1+#p.plan.frame.rects
    if needed==0 then prepareIndex=prepareIndex+1
    elseif count+needed>5800 then
     -- Retry next frame, but do not block affordable chunks behind this one.
     blocked=blocked or prepareIndex;prepareIndex=prepareIndex+1
    else
     local spent=mountPrimitive(p,math.min(edgeCredit,terrainCredit))
     edgeCredit=edgeCredit-spent;terrainCredit=terrainCredit-spent;tileCredit=tileCredit-1;g=primitiveMounts[p.key]
     stats.frameTerrainGroups=(stats.frameTerrainGroups or 0)+1;stats.frameTerrainControls=(stats.frameTerrainControls or 0)+spent
     if g.nextRect<=#p.plan.frame.rects then break end
     prepareIndex=prepareIndex+1
    end
   end
   if blocked then prepareIndex=blocked end
  end
  -- All visible tiles on the same layer/clock share phase parents. A whole
  -- water surface advances with two host writes, independent of tile count.
  local animationClock,buckets=0,{}
  local function animatedTile(g,def,key)
   local signature=g.layerKey..':'..def.frameTicks..':'..#def.frames
   local b=buckets[signature]
   if not b then
    b={groups={},refs=0,ticks=def.frameTicks,phase=math.floor(animationClock/def.frameTicks)%#def.frames+1}
    buckets[signature]=b
    for i=1,#def.frames do
     local parent=group('RPG tile phase '..signature..':'..i,g.layer.object,sw,sh)
     visible(parent,i==b.phase);b.groups[i]=parent
    end
   end
   b.refs=b.refs+1;g.animBucket=b
   for i,id in ipairs(def.frames)do
    local o=create(id,'RPG animated tile '..key..':'..i,b.groups[i].object)
    place(o,g.x+(cell-def.width)/2,g.y+(cell-def.height)/2,def.width,def.height,sw,sh)
    local scale=math.min(cell/def.width,cell/def.height);o:SetLocalScale(scale,scale,1)
    g.children[#g.children+1]=o
   end
  end
  local cols,rows=math.ceil(sw/cell)+1,math.ceil(sh/cell)+1
  local slots,characters,characterPool,dormant={},{},{},{};local seenCharacters,seenSerial={},0
  local orderDirty,frameCacheDirty=true,true
  local lastX,lastY,cameraX,cameraY
  local characterFrames,frameCount,frameSerial={},0,0
  local function discardFrame(entry)
   frameCacheDirty=true
   destroyGroup(entry.group)
   entry.owner.frames[entry.key]=nil
   if entry.owner.current==entry then entry.owner.current=nil end
   characterFrames[entry]=nil;frameCount=frameCount-1
  end
  local function discardCharacter(record)
   orderDirty,frameCacheDirty=true,true
   local entries={};for _,entry in pairs(record.frames or {})do entries[#entries+1]=entry end
   for _,entry in ipairs(entries)do discardFrame(entry)end
   game.DestroyClientUIControl(record.object);count=count-1;stats.live=count;stats.destroyed=stats.destroyed+1
  end
  reclaim=function(needed)
   while count+needed>6000 do
    local oldestKey,oldest
    for key,g in pairs(primitiveMounts)do
     if not primitiveWanted[key] and (not oldest or g.used<oldest.used)then oldestKey,oldest=key,g end
    end
    if oldest then discardChunk(oldestKey,oldest)
    else
     local frame
     for entry in pairs(characterFrames)do
      if not entry.building and not (entry.owner.visible and entry.owner.current==entry) and (not frame or entry.used<frame.used)then frame=entry end
     end
     if not frame then break end;discardFrame(frame)
    end
   end
  end
  local function takeDormant(key)
   local record=dormant[key];if not record then return nil end
   dormant[key]=nil;record.poolKey=nil
   for i,value in ipairs(characterPool)do if value==record then table.remove(characterPool,i);break end end
   return record
  end
  local function pruneFrames()
   if not frameCacheDirty then return end
   stats.framePrunes=stats.framePrunes+1
   local active=0;for _ in pairs(characters)do active=active+1 end
   local budget=128+active
   while frameCount>budget do
    local oldest
    for entry in pairs(characterFrames)do
     if not (entry.owner.visible and entry.owner.current==entry) and (not oldest or entry.used<oldest.used)then oldest=entry end
    end
    if not oldest then break end;discardFrame(oldest)
   end
   stats.characterFrames=frameCount;frameCacheDirty=false
  end
  local function tileId(x,y,z)
   if map.scrollType==2 or map.scrollType==3 then x=x%map.width end
   if map.scrollType==1 or map.scrollType==3 then y=y%map.height end
   if x<0 or y<0 or x>=map.width or y>=map.height then return 0 end
   return map.tiles[(z*map.height+y)*map.width+x+1]
  end
  local function paintTile(g,def,key)
   visible(g,def~=nil);if g.key==key then return end;g.key=key;stats.tileRebinds=stats.tileRebinds+1;clear(g)
   if not def then visible(g,false);return end;visible(g,true)
   if def.primitive then
    local l=def.primitiveLayout
    primitive(g,def.primitive,'RPG tile geometry',l and l.x,l and l.y,l and l.width,l and l.height)
   elseif def.frames and #def.frames>1 then animatedTile(g,def,key)
   elseif def.templateId then art(g,def,'RPG tile template '..key)
   else fail('Missing tile resource: '..key)
   end
  end
  local legacyLayers={}
  local function refreshTiles(ix,iy)
   local function tileLayer(z,isUpper)
    local key=z..':'..tostring(isUpper==true);local g=legacyLayers[key]
    if not g then
     g=group('RPG tile viewport '..key,(isUpper and upperZ or lowerZ)[z].object,sw,sh,ix*cell,iy*cell);legacyLayers[key]=g
    end
    return g
   end
   local defs=resources.tiles[string.format('%.0f',tilesetId)] or {}
   for y=0,rows-1 do for x=0,cols-1 do
    local slotIndex=y*cols+x+1;local slot=slots[slotIndex] or {};slots[slotIndex]=slot
    for z=0,3 do
     local id=tileId(x+ix,y+iy,z);local def=defs[tostring(id)];if def and def.mergedPrimitive then def=nil end
     local layer=def and tileLayer(z,def.upper)
     local key=tostring(z)..':'..(def and def.upper and 'upper' or 'lower');local g=slot[key]
     if not g and def then g=group('RPG tile '..x..':'..y..':'..z,layer.object,cell,cell,x*cell,y*cell);g.layer,g.layerKey=layer,key;slot[key]=g end
     local other=slot[tostring(z)..':'..(def and def.upper and 'lower' or 'upper')];if other then visible(other,false)end
     if g then paintTile(g,def,tostring(tilesetId)..':'..tostring(id)..':'..key)end
    end
    local bits=tileId(x+ix,y+iy,4)
    for q=0,3 do
     local key='shadow'..q;local g=slot[key];local on=bits&(1<<q)~=0
     if on and not g then
      hasShadows=true
      g=group('RPG shadow '..x..':'..y..':'..q,shadows.object,cell/2,cell/2,x*cell+(q%2)*cell/2,y*cell+math.floor(q/2)*cell/2)
      solid('RPG shadow fill',g,0,0,cell/2,cell/2,{0,0,0,96});slot[key]=g
     end
     if g then visible(g,on)end
    end
    local above=defs[tostring(tileId(x+ix,y+iy-1,1))];local here=defs[tostring(tileId(x+ix,y+iy,1))]
    local edge=above and above.tableTile and not (here and here.tableTile) and tileId(x+ix,y+iy,0)<4352 and above.tableEdge
    local eg=slot.edge
    if edge and not eg then hasEdges=true;eg=group('RPG table edge '..x..':'..y,edges.object,cell,cell,x*cell,y*cell);slot.edge=eg end
    if eg then paintTile(eg,edge or nil,edge and 'edge:'..edge.templateId or 'edge:none')end
   end end
   for _,g in pairs(legacyLayers)do move(g,ix*cell,iy*cell)end
   if hasShadows then move(shadows,ix*cell,iy*cell)end
   if hasEdges then move(edges,ix*cell,iy*cell)end
   for key,b in pairs(buckets)do if b.refs==0 then
    for _,g in ipairs(b.groups)do game.DestroyClientUIControl(g.object);count=count-1;stats.destroyed=stats.destroyed+1 end
    buckets[key]=nil;stats.live=count
   end end
  end
  local function character(key,entity,image,player,transparent)
   seenCharacters[key]=seenSerial
   if transparent==nil then transparent=entity.transparent end
   local record=characters[key]
   if entity.erased then
    record=record or takeDormant(key);characters[key]=nil
    if record then discardCharacter(record)end;return
   end
   local shown=not entity.erased and (player or entity.page~=nil and entity.page~=false) and not transparent
   local rx,ry=entity.realX or entity.x,entity.realY or entity.y
   local wx,wy=rx,ry
   if map.scrollType==2 or map.scrollType==3 then if wx-cameraX< -1 then wx=wx+map.width elseif wx-cameraX>cols then wx=wx-map.width end end
   if map.scrollType==1 or map.scrollType==3 then if wy-cameraY< -1 then wy=wy+map.height elseif wy-cameraY>rows then wy=wy-map.height end end
   local x,y=wx-cameraX,wy-cameraY
   local sourceKey=image and (image.characterName or '')..':'..string.format('%.0f',image.characterIndex or 0) or ''
   local def=resources.characters[sourceKey]
   local isTile=image and (image.tileId or 0)>0
   if isTile then def=(resources.tiles[string.format('%.0f',tilesetId)] or {})[tostring(image.tileId)]end
   local filename=(image and image.characterName or ''):match('[^/\\]+$') or ''
   local prefix=filename:match('^[!$]+') or ''
   local objectCharacter=isTile or prefix:find('!',1,true)~=nil
   local worldTop=wy*cell-(objectCharacter and 0 or 6)-(entity.jumpHeight or 0)-(entity.altitude or 0)
   local top=worldTop-cameraY*cell
   local dw,dh=def and (def.displayWidth or def.primitiveFrames and def.width) or cell,def and (def.displayHeight or def.primitiveFrames and def.height) or cell
   local center=x*cell+cell/2;local bottom=top+cell
   shown=shown and image~=nil and ((image.characterName or '')~='' or isTile) and center+dw/2> -cell and center-dw/2<sw+cell and bottom> -cell and bottom-dh<sh+cell
   if not shown then
    if record then
     orderDirty,frameCacheDirty=true,true
     visible(record,false);characters[key]=nil;record.order,record.sibling=nil,nil
     record.poolKey=key;dormant[key]=record;characterPool[#characterPool+1]=record
     if #characterPool>32 then local old=table.remove(characterPool,1);dormant[old.poolKey]=nil;discardCharacter(old)end
    end
    return
   end
   if not record then
    record=takeDormant(key)
    if not record then
     -- Reuse an inactive mount only for an entity that has never owned one.
     record=table.remove(characterPool,1)
     if record then dormant[record.poolKey]=nil;record.poolKey=nil end
    end
    record=record or group('RPG '..key,people.object,cell,cell)
    record.frames=record.frames or {};record.object.name='RPG '..key;characters[key]=record;orderDirty,frameCacheDirty=true,true
   end;visible(record,true)
   local frame=entity.pattern==3 and 1 or entity.pattern or 1
   local frameIndex=(math.floor((entity.direction or 2)/2)-1)*3+frame+1
   if def and def.staticPrimitive then frameIndex=1 end
   local templateId=def and def.templateId
   if not isTile and def and def.frames then
    templateId=def.frames[frameIndex]
   end
   local parts=not isTile and def and def.bushFrames and def.bushFrames[frameIndex]
   local primitiveFrame=def and (isTile and def.primitive or def.primitiveFrames and def.primitiveFrames[frameIndex])
   local primitiveOpacity=entity.opacity or 255;local primitiveBush=(entity.bushDepth or 0)>0
   local visualKey=templateId and 'art:'..templateId..':'..def.width..':'..def.height..':'..dw..':'..dh or
    isTile and 'tile:'..tilesetId..':'..image.tileId or entity.kind or (player and 'player' or 'event')
   if parts then visualKey=visualKey..':bush:'..parts.upperTemplateId..':'..parts.lowerTemplateId end
   -- Opacity changes paint, not geometry. Never cache one control tree per alpha.
   if primitiveFrame then
    local assetKey=isTile and 'tile:'..tilesetId..':'..image.tileId or 'character:'..sourceKey..':'..frameIndex
    visualKey='primitive:'..assetKey..':'..tostring(primitiveBush)
   end
   local entry=record.frames[visualKey]
   if not entry then
    local g=group('RPG character frame '..visualKey,record.object,cell,cell,0,0,cell,cell)
    entry={key=visualKey,owner=record,group=g,opacity=255,bushFactor=1,paint={},building=true,used=frameSerial}
    record.frames[visualKey]=entry;characterFrames[entry]=true;frameCount=frameCount+1;frameCacheDirty=true
    local lowerControls={}
    if primitiveFrame then
     local l=isTile and def.primitiveLayout
     primitive(g,primitiveFrame,'RPG '..key..' colour block',l and l.x or (cell-dw)/2,l and l.y or cell-dh,l and l.width or dw,l and l.height or dh,primitiveOpacity,primitiveBush,entry.paint)
     entry.opacity=primitiveOpacity
    elseif parts then
     for _,part in ipairs({'upper','lower'})do
      local object=art(g,{templateId=parts[part..'TemplateId'],width=def.width,height=def.height,displayWidth=def.displayWidth,displayHeight=def.displayHeight},'RPG '..key..' '..part..' template')
      local paints={};capture(object,paints)
      for _,paint in ipairs(paints)do paint.lower=part=='lower';entry.paint[#entry.paint+1]=paint end
     end
    elseif templateId then art(g,{templateId=templateId,width=def.width,height=def.height,displayWidth=def.displayWidth,displayHeight=def.displayHeight},'RPG '..key..' template')
    else fail('Missing character/tile resource: '..tostring(sourceKey or image.tileId))
    end
    if not parts and not primitiveFrame then capture(g.object,entry.paint);for _,paint in ipairs(entry.paint)do paint.lower=lowerControls[paint.object]==true end end
   end
   entry.building=nil
   if record.current~=entry then
    if record.current then visible(record.current.group,false)end
    visible(entry.group,true);record.current=entry;frameSerial=frameSerial+1;entry.used=frameSerial
   end
   local opacity=entity.opacity or 255
   local bushFactor=(entity.bushDepth or 0)>0 and 128/255 or 1
   if entry.opacity~=opacity or entry.bushFactor~=bushFactor then
    for _,paint in ipairs(entry.paint)do
     local alpha=opacity*(paint.lower and bushFactor or 1)
     local previous=entry.opacity*(paint.lower and entry.bushFactor or 1)
     if alpha~=previous then
      local value=color.FromRGBA(paint.r,paint.g,paint.b,paint.a*alpha/255)
      if updates then updates.set(paint.object,paint.key,value,alpha)else paint.object[paint.key]=value end
     end
    end
    entry.opacity=opacity;entry.bushFactor=bushFactor
   end
   record.displayHeight=dh;move(record,wx*cell,worldTop,sw,sh)
   local order=(entity.priorityType or 1)*100000+math.floor((wy+1)*cell)*10+(player and 9 or (entity.id or 0)%9)
   if record.order~=order then record.order=order;orderDirty=true end
  end
  local S={}
  -- Source comment labels remain children of one scrolling world-space layer.
  -- Text/icon controls are instantiated only near the viewport and reused.
  local labelLayer,labelViews,labelSerial=nil,{},0
  local function updateLabels(world)
   local definitions=resources.visuLabels and resources.visuLabels[string.format('%.0f',map.id)]
   if not definitions then return end;labelSerial=labelSerial+1
   local function discard(key,g)destroyGroup(g);labelViews[key]=nil end
   for _,e in ipairs(world.events)do
    local pages=definitions[string.format('%.0f',e.id)];local label=pages and e.page and pages[e.page]
    local valid=label and not e.erased and not e.transparent and (label.text or label.icon)
    local g=labelViews[e.id]
    if not valid then if g then discard(e.id,g)end
    else
     local x=(e.realX or e.x)*cell;local y=(e.realY or e.y)*cell
     local shown=x-cameraX*cell> -cell*2 and x-cameraX*cell<sw+cell*2 and y-cameraY*cell> -cell*2 and y-cameraY*cell<sh+cell*2
     if g and g.page~=e.page then discard(e.id,g);g=nil end
     if shown and not g then
      labelLayer=labelLayer or group('RPG event labels',worldRoot.object,sw,sh)
      local text=label.text or '';local n=utf8.len(text)or #text
      local w=math.max(40,math.min(sw-24,n*19+24));g=group('RPG label '..e.id,labelLayer.object,w,80);g.page=e.page;labelViews[e.id]=g
      if text~=''then
       local o=create(bindings.textTemplate,'RPG event label text '..e.id,g.object)
       o.text=text;o.fontSize=math.max(o.minimumFontSize or 1,22);o.adaptiveFontSize=true
       local p=resources.visuLabelColors and resources.visuLabelColors[(label.color or 0)+1] or {255,255,255,255}
       o.fontColor=color.FromRGBA(p[1],p[2],p[3],p[4]);o.bgColor=color.FromRGBA(0,0,0,0)
       o.enableOutline=true;o.outlineColor=color.FromRGBA(0,0,0,220)
       o.horizontalAlignment=enum.TextHorizontalAlignment.Middle;o.verticalAlignment=enum.TextVerticalAlignment.Middle
       place(o,0,40,w,40,w,80);g.children[#g.children+1]=o
      end
      if label.icon then local f=resources.icons[string.format('%.0f',label.icon)];if not f then fail('Missing event label icon '..label.icon)end
       primitive(g,f,'RPG event label icon '..e.id,(w-32)/2,4-(label.iconY or 0),32,32)
      end
     end
     if g then visible(g,shown);g.used=shown and labelSerial or g.used
      if shown then move(g,x+cell/2-g.width/2+(label.x or 0),y-80+(label.y or 0),sw,sh)end
     end
    end
   end
   local inactive={};for key,g in pairs(labelViews)do if not g.visible then inactive[#inactive+1]={key=key,g=g}end end
   if #inactive>32 then table.sort(inactive,function(a,b)return(a.g.used or 0)<(b.g.used or 0)end)
    for i=1,#inactive-32 do discard(inactive[i].key,inactive[i].g)end
   end
  end
  function S.advance(frames)
   -- rpg_preview calls advance once per host update, including zero-tick
   -- updates. Input-triggered renders share the remaining credit.
   edgeCredit=24;terrainCredit,tileCredit=96,8;stats.frameTerrainGroups,stats.frameTerrainControls=0,0
   if closed or frames==0 then return end;animationClock=animationClock+frames
   for _,b in pairs(buckets)do
    local phase=math.floor(animationClock/b.ticks)%#b.groups+1
    if phase~=b.phase then visible(b.groups[b.phase],false);visible(b.groups[phase],true);b.phase=phase end
   end
  end
  function S.update(world)
   if closed then return end
   local createdBefore=stats.created;local previousX,previousY=cameraX,cameraY
   seenSerial=seenSerial+1
   if world.tilesetId and world.tilesetId~=tilesetId then tilesetId=world.tilesetId;lastX,lastY=nil,nil end
   local p=world.player
   if world.camera then cameraX,cameraY=world.camera.x,world.camera.y
   else
    cameraX=(p.realX or p.x)-(sw/cell-1)/2;cameraY=(p.realY or p.y)-(sh/cell-1)/2
    if map.scrollType~=2 and map.scrollType~=3 then cameraX=math.max(0,math.min(cameraX,math.max(0,map.width-sw/cell)))end
    if map.scrollType~=1 and map.scrollType~=3 then cameraY=math.max(0,math.min(cameraY,math.max(0,map.height-sh/cell)))end
   end
   local directionChanged=false
   if previousX then
    local dx,dy=cameraX-previousX,cameraY-previousY
    if map.scrollType==2 or map.scrollType==3 then dx=(dx+map.width/2)%map.width-map.width/2 end
    if map.scrollType==1 or map.scrollType==3 then dy=(dy+map.height/2)%map.height-map.height/2 end
    if dx~=0 or dy~=0 then
     local mx,my=dx>0 and 1 or dx<0 and -1 or 0,dy>0 and 1 or dy<0 and -1 or 0
     directionChanged=mx~=motionX or my~=motionY;motionX,motionY=mx,my
    end
   end
   updateParallax(world)
   local ix,iy=math.floor(cameraX),math.floor(cameraY)
   if ix~=lastX or iy~=lastY then updatePrimitives(ix,iy);refreshTiles(ix,iy);lastX,lastY=ix,iy
   elseif directionChanged then sortPreparation()end
   move(worldRoot,-cameraX*cell,-cameraY*cell)
   for _,e in ipairs(world.events)do character('event '..e.id,e,e.image,false)end
   updateLabels(world)
   local leader=world.party.members[1];local actorImages=world.actorImages or {}
   character('player',p,p.image or actorImages[leader] or actors[leader],true)
   for i,follower in ipairs(world.followers or {})do
    local id=follower.actorId or world.party.members[i+1]
    character('follower '..i,follower,follower.image or actorImages[id] or actors[id],true,not world.followersVisible or follower.transparent)
   end
   for _,name in ipairs({'boat','ship','airship'})do local v=world.vehicles and world.vehicles[name]
    if v then character('vehicle '..name,v,v.image,true,v.mapId~=world.mapId)end
   end
   -- Leaving the viewport is temporary; disappearing from the world is not.
   for key,record in pairs(characters)do if seenCharacters[key]~=seenSerial then characters[key]=nil;seenCharacters[key]=nil;discardCharacter(record)end end
   for i=#characterPool,1,-1 do local record=characterPool[i]
    if seenCharacters[record.poolKey]~=seenSerial then dormant[record.poolKey]=nil;seenCharacters[record.poolKey]=nil;table.remove(characterPool,i);discardCharacter(record)end
   end
   if orderDirty then
    local sorted={};for key,record in pairs(characters)do sorted[#sorted+1]={key=key,record=record}end
    table.sort(sorted,function(a,b)if (a.record.order or 0)==(b.record.order or 0)then return a.key<b.key end;return (a.record.order or 0)<(b.record.order or 0)end)
    for i,entry in ipairs(sorted)do if entry.record.sibling~=i-1 then entry.record.object:SetSiblingIndex(i-1);entry.record.sibling=i-1 end end
    orderDirty=false;stats.characterSorts=stats.characterSorts+1
   end
   -- Required visible terrain/actor creation consumes optional work credit
   -- first, so a heavy crossing does not also append a fresh preparation batch.
   edgeCredit=math.max(0,edgeCredit-(stats.created-createdBefore))
   pruneFrames();prepareVisible();prepareEdge()
   stats.pendingTerrain=math.max(0,#visibleQueue-visibleIndex+1)+math.max(0,#prepareQueue-prepareIndex+1)
   stats.peakTerrainGroups=math.max(stats.peakTerrainGroups or 0,stats.frameTerrainGroups or 0)
   stats.peakTerrainControls=math.max(stats.peakTerrainControls or 0,stats.frameTerrainControls or 0)
  end
  function S.stats()local r={};for k,v in pairs(stats)do r[k]=v end;return r end
  function S.locate(id)
   local g=characters[id==-1 and 'player' or 'event '..tostring(id)]
   if g and g.visible then return{x=g.x+g.width/2-cameraX*cell,y=g.y+g.height-(g.displayHeight or g.height)/2-cameraY*cell}end
  end
  function S.close()if closed then return end;closed=true;for _,o in ipairs(live)do if o.alive then game.DestroyClientUIControl(o)end end;stats.live=0;stats.characterFrames=0 end
  S.object=root.object;root.object:SetAsFirstSibling();return S
 end
 function M.new(host,parent,bindings,ui,map,resources,actors)
  local root;local ok,result=pcall(build,host,parent,bindings,ui,map,resources,actors,function(o)root=o end)
  if not ok then if root and root.alive then host.game.DestroyClientUIControl(root)end;error(result,0)end
  return result
 end
 return M
end
