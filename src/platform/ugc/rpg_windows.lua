-- Draw simplified platform UI or explicit source RPG Maker pixels with client controls.
return function(deps)
 local textLimit=deps['runtime.ui.text_limit']
 local M={}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 function M.new(host,parent,bindings,ui,skin)
  local game,enum,color=host.game,host.Enum,host.Color
  if not game or not enum or not color or not parent or not bindings.containerTemplate or not bindings.imageTemplate or not bindings.textTemplate or not bindings.whiteImageId then fail('E_PLATFORM_NOT_CONFIGURED','RPG windows need container/image/text templates and a verified white image binding')end
  local width,height=ui.screen.width,ui.screen.height
  local renderMode=bindings.renderMode;if renderMode==nil then renderMode='platform'end
  if renderMode~='platform'and renderMode~='source'then fail('E_UI_RENDER_MODE','Unknown RPG UI render mode')end
  local platform=renderMode=='platform'
  local patternMode=bindings.windowPattern;if patternMode==nil then patternMode=platform and 'simple'or 'source'end
  local geometry
  if platform and patternMode~='simple'or not platform and patternMode~='source'and patternMode~='geometry'then fail('E_UI_PATTERN_UNSUPPORTED','Window pattern does not match its render mode')end
  if patternMode=='geometry'then
   local function reject()fail('E_UI_PATTERN_UNSUPPORTED','Geometry requires a verified MZ period-three pattern')end
   local function plain(v)return type(v)=='table'and getmetatable(v)==nil end
   if ui.profile~='mz-1.10.0'or not plain(skin)then reject()end
   local g=skin.patternGeometry
   local allowed={kind=true,schemaVersion=true,approximation=true,period=true,phase=true,color=true,lineWidth=true,lineOffset=true,rotationDegrees=true,sourceRegion=true,verifiedPixels=true}
   if not plain(g)then reject()end;for k in next,g do if not allowed[k]then reject()end end
   if g.kind~='r2u.window-pattern-geometry'or g.schemaVersion~=1 or g.approximation~=true or g.period~=3 or g.phase~=0 or g.verifiedPixels~=9216
    or g.lineWidth~=1/math.sqrt(2)or g.lineOffset~=1 or g.rotationDegrees~=45 or not plain(g.color)or not plain(g.sourceRegion)then reject()end
   local region={x=0,y=96,width=96,height=96};for k in next,g.sourceRegion do if region[k]==nil then reject()end end;for k,v in pairs(region)do if g.sourceRegion[k]~=v then reject()end end
   local count=0;for k in next,g.color do if type(k)~='number'or k%1~=0 or k<1 or k>4 then reject()end;count=count+1 end;if count~=4 then reject()end
   geometry={color={}};for i=1,4 do local v=g.color[i];if type(v)~='number'or v%1~=0 or v<0 or v>255 or i==4 and v==0 then reject()end;geometry.color[i]=v end
  end
  local live,count,listeners={},0,{};local maxControls=bindings.maxControls or 250000
  local queue,queueHead,planned,groups={},1,0,{}
  local dynamicPaint={}
  local windowTone=ui.window.tone;local toneImages={};local toneKey
  local backgroundBatching={}
  local deferred=bindings.deferred==true
  local revealNeeded=false
  local function pos(o,x,y,w,h,pw,ph)
   o:SetAnchorMin(.5,.5);o:SetAnchorMax(.5,.5);o:SetPivot(.5,.5)
   o:SetAnchoredPosition(x+w/2-pw/2,ph/2-y-h/2);o:SetSizeDelta(w,h);o:SetActive(true);o:SetVisible(true)
  end
  local function create(template,name,p)
   if count+planned>=maxControls then fail('E_UI_CONTROL_BUDGET','Source UI rectangle/control budget exceeded')end
   local o=game.InstantiateClientUIControl(template,p);if not o then fail('E_PLATFORM_TEMPLATE','Missing RPG UI template')end
   count=count+1;o.name=name;return o
  end
  local function rgba(p,alpha,tone)
   local function channel(i)return math.max(0,math.min(255,p[i]+(tone and tone[i] or 0)))end
   return color.FromRGBA(channel(1),channel(2),channel(3),math.floor(p[4]*(alpha or 1)+.5))
  end
  local W={}
  local updates=bindings.updates
  local function visibility(group,value)
   if group.appliedVisible==value then return end;group.appliedVisible=value
   if updates then updates.call(group.object,'SetVisible',value)else group.object:SetVisible(value)end
  end
  function W.group(name,r,owner,animateOpacity)
   if animateOpacity~=nil and type(animateOpacity)~='boolean'then fail('E_UI_OPACITY','Expected animation flag')end
   if owner then owner.hasImmediateChildren=true end
   local o=create(bindings.containerTemplate,name,owner and owner.object or parent);live[#live+1]=o
   pos(o,r.x,r.y,r.width,r.height,owner and owner.width or width,owner and owner.height or height)
   local group={object=o,x=r.x,y=r.y,width=r.width,height=r.height,controls={},count=1,owner=owner,visible=true,appliedVisible=true}
   if animateOpacity then dynamicPaint[group]={opacity=1,images={}}end
   groups[#groups+1]=group;if deferred then visibility(group,false);revealNeeded=true end
   return group
  end
  local function backgroundContainer(batch)
   local owner=batch.owner
   batch.group=W.group(batch.name,{x=0,y=0,width=owner.width,height=owner.height},owner)
   batch.group.object:SetSiblingIndex(512+batch.index-1)
  end
  function W.paintOpacity(group,alpha)
   local record=dynamicPaint[group]
   if not record then fail('E_UI_OPACITY','Group was not created for dynamic opacity')end
   if type(alpha)~='number' or alpha~=alpha or alpha<0 or alpha>1 then fail('E_UI_OPACITY','Expected finite opacity from zero to one')end
   if alpha==record.opacity then return end;record.opacity=alpha
   for _,entry in ipairs(record.images)do
    if entry.object.alive then
     local field=entry.field or 'imageColor'
     if updates then updates.set(entry.object,field,rgba(entry.paint,alpha),alpha)
     else entry.object[field]=rgba(entry.paint,alpha)end
    end
   end
  end
  function W.move(group,x,y)
   if group.x==x and group.y==y then return end
   group.x,group.y=x,y
   local px=x+group.width/2-(group.owner and group.owner.width or width)/2
   local py=(group.owner and group.owner.height or height)/2-y-group.height/2
   if updates then updates.call(group.object,'SetAnchoredPosition',px,py)else group.object:SetAnchoredPosition(px,py)end
   visibility(group,group.visible and planned==0)
   if group.background then W.move(group.background,x+group.backgroundOffsetX,y+group.backgroundOffsetY)end
  end
  function W.show(group,visible)
   group.visible=visible;visibility(group,visible and planned==0)
   if group.background then W.show(group.background,visible)end
  end
  local function rasterRect(group,x,y,w,h)
   if bindings.pixelScale then
    -- One shared destination grid prevents independently antialiased adjacent
    -- quads from leaking the window underneath an opaque source image.
    local s=bindings.pixelScale;local gx,gy=group.x,group.y;local p=group.owner
    while p do gx,gy=gx+p.x,gy+p.y;p=p.owner end
    local ox,oy=bindings.pixelOffsetX or 0,bindings.pixelOffsetY or 0
    local function snap(v,offset)return(math.floor(v*s+offset+.5)-offset)/s end
    local right,bottom=snap(gx+x+w,ox)-gx,snap(gy+y+h,oy)-gy
    x,y=snap(gx+x,ox)-gx,snap(gy+y,oy)-gy;w,h=right-x,bottom-y
   end
   return x,y,w,h
  end
  local function pixel(job)
   local group=job.backgroundBatch and job.backgroundBatch.group or job.group
   local x,y,w,h=job.x,job.y,job.width,job.height
   if not job.rotation then x,y,w,h=rasterRect(group,x,y,w,h)end
   if w<=0 or h<=0 then return end
   local o=create(bindings.imageTemplate,job.name,group.object)
   if job.rotation and type(o.SetLocalRotation)~='function'then W.close();fail('E_PLATFORM_NOT_CONFIGURED','Geometry pattern requires SetLocalRotation(x,y,z)')end
   o:SetImage(enum.ImageSource.StaticReference,job.imageId or bindings.whiteImageId)
   local dynamic=dynamicPaint[group]
   if job.windowTone then job.tone=windowTone end
   if dynamic then
    local paint={};for i=1,3 do paint[i]=math.max(0,math.min(255,job.paint[i]+(job.tone and job.tone[i] or 0)))end
    paint[4]=job.paint[4]*(job.alpha or 1)
    o.imageColor=rgba(paint,dynamic.opacity);dynamic.images[#dynamic.images+1]={object=o,paint=paint}
   else o.imageColor=rgba(job.paint,job.alpha,job.tone)end
   if job.windowTone then toneImages[#toneImages+1]={object=o,paint=job.paint,alpha=job.alpha,dynamic=dynamic}end
   o.enableMask=false;o.enableSoftEdge=false;o:SetFillUnused();pos(o,x,y,w,h,group.width,group.height)
   if job.rotation then o:SetLocalRotation(0,0,job.rotation)end
   -- Deferred images still occupy their source draw order, below later text/areas.
   if job.sibling~=nil and group.hasImmediateChildren then o:SetSiblingIndex(job.sibling)end
   group.controls[#group.controls+1]=o
  end
  local function draw(job,batching)
   if batching then
    batching.images=batching.images+1
    if batching.images>512 then
     if (batching.images-1)%512==0 then
      local index=math.floor((batching.images-1)/512)
      local batch={owner=job.group,index=index,name=job.group.object.name..' batch '..string.format('%.0f',index)}
      batching.current=batch
      if deferred then
       if count+planned>=maxControls then fail('E_UI_CONTROL_BUDGET','Source UI rectangle/control budget exceeded')end
       queue[#queue+1]={group=job.group,backgroundContainer=batch};planned=planned+1
      else backgroundContainer(batch)end
     end
     job.backgroundBatch=batching.current
    end
   end
   if deferred then
    if count+planned>=maxControls then fail('E_UI_CONTROL_BUDGET','Source UI rectangle/control budget exceeded')end
    job.sibling=job.group.count-1;queue[#queue+1]=job;planned=planned+1
   else pixel(job)end
   job.group.count=job.group.count+1
  end
  local function patternLines(group,w,h)
   if w+h>9007199254740991 or w~=w or h~=h then fail('E_UI_PATTERN_UNSUPPORTED','Geometry background dimensions exceed the safe source domain')end
   local root2=math.sqrt(2);local thick=1/root2
   for step=0.0,w+h-2.0,3.0 do
    local d=step+1;local left=math.max(.25,d-(h-.25));local right=math.min(w-.25,d-.25)
    if right>left then local middle=(left+right)/2;local length=(right-left)*root2
     draw({group=group,name=group.object.name..' geometry line',paint=geometry.color,alpha=ui.window.backOpacity/255,tone=ui.window.tone,windowTone=true,
      x=middle-length/2,y=d-middle-thick/2,width=length,height=thick,rotation=45})
    end
   end
  end
  function W.area(group,name,r)
   group.hasImmediateChildren=true
   if not bindings.cursorTemplate then fail('E_PLATFORM_NOT_CONFIGURED','Native UI needs a cursor area template')end
   local object=create(bindings.cursorTemplate,name,group.object);object.raycastTarget=true
   pos(object,r.x,r.y,r.width,r.height,group.width,group.height)
   local area={object=object};listeners[#listeners+1]=area;return area
  end
  function W.bind(area,callback)
   if area.callback and area.object.alive then area.object:RemoveCursorEventListener(enum.CursorEventType.CursorClick,area.callback)end
   area.callback=callback
   if callback then area.object:AddCursorEventListener(enum.CursorEventType.CursorClick,callback)end
  end
  function W.bindHeld(area,callback)
   for _,entry in ipairs(area.heldListeners or {})do if area.object.alive then area.object:RemoveCursorEventListener(entry.key,entry.callback)end end
   area.heldListeners={}
   for _,entry in ipairs({{'CursorDown',true},{'CursorUp',false},{'CursorExit',false}})do
    local key=enum.CursorEventType[entry[1]]
    if not key then fail('E_PLATFORM_NOT_CONFIGURED','Scrolling text requires '..entry[1])end
    local fn=function()callback(entry[2])end
    area.object:AddCursorEventListener(key,fn);area.heldListeners[#area.heldListeners+1]={key=key,callback=fn}
   end
  end
  -- Art IDs refer to fixed-size container templates, never to image resources.
  -- A mount controls layout and scale without changing the cloned artwork.
  function W.art(group,name,templateId,r,clip,disabled,standardWidth,standardHeight)
   local ok,result=pcall(function()
    local primitive=type(templateId)=='table' and templateId.kind=='r2u.primitive-frame' and templateId
    if not primitive and (type(templateId)~='number'or templateId%1~=0 or templateId<1 or templateId>2147483647) then fail('E_UI_ART_TEMPLATE','Invalid art container template ID')end
    local x,y,right,bottom=r.x,r.y,r.x+r.width,r.y+r.height
    if clip then x,y=math.max(x,clip.x),math.max(y,clip.y);right,bottom=math.min(right,clip.x+clip.width),math.min(bottom,clip.y+clip.height)end
    if right<=x or bottom<=y then return nil end
    local mount=W.group(name,{x=x,y=y,width=right-x,height=bottom-y},group);group.count=group.count+1
    if primitive then
     local sw,sh=primitive.width,primitive.height;local scale=math.min(mount.width/sw,mount.height/sh)
     W.blit(mount,primitive,(mount.width-sw*scale)/2,(mount.height-sh*scale)/2,sw*scale,sh*scale,disabled and .6 or 1)
     return mount
    end
    local o=create(templateId,name..' template',mount.object);live[#live+1]=o
    if type(o.SetLocalScale)~='function'then fail('E_PLATFORM_NOT_CONFIGURED','Art containers require SetLocalScale(x,y,z)')end
    local sw,sh=standardWidth or 144,standardHeight or 144
    pos(o,(mount.width-sw)/2,(mount.height-sh)/2,sw,sh,mount.width,mount.height)
    local scale=math.min(mount.width/sw,mount.height/sh)
    o:SetLocalScale(scale,scale,1)
    mount.controls[#mount.controls+1]=o;mount.count=mount.count+1
    if disabled then W.solid(mount,name..' disabled',{x=0,y=0,width=mount.width,height=mount.height},{0,0,0,96})end
    return mount
   end)
   if not ok then W.close();error(result,0)end
   return result
  end
  function W.blit(group,frame,x,y,w,h,alpha,tone,clipWidth,clipHeight,clipLeft,clipTop)
   local sx,sy=w/frame.width,h/frame.height
   local batching=backgroundBatching[group]
   local prefix=deferred and group.object.name..' pixel ' or nil
   for i,r in ipairs(frame.rects)do
    local rx,ry,rw,rh=x+r.x*sx,y+r.y*sy,r.width*sx,r.height*sy
    if clipLeft and rx<clipLeft then rw=rw-(clipLeft-rx);rx=clipLeft end
    if clipTop and ry<clipTop then rh=rh-(clipTop-ry);ry=clipTop end
    if clipWidth then rw=math.min(rw,clipWidth-rx)end;if clipHeight then rh=math.min(rh,clipHeight-ry)end
    if rw>0 and rh>0 then
     local job={group=group,name=(prefix or group.object.name..' pixel ')..i,paint=frame.palette[r.colorIndex],imageId=r.imageId,alpha=alpha,tone=tone,windowTone=group.windowTone and tone~=nil,x=rx,y=ry,width=rw,height=rh,rotation=r.rotation and -r.rotation}
     draw(job,batching)
    end
   end
  end
  function W.solid(group,name,r,paint)
   group.hasImmediateChildren=true
   local x,y,w,h=rasterRect(group,r.x,r.y,r.width,r.height)
   if w<=0 or h<=0 then return nil end
   local o=create(bindings.textTemplate,name,group.object);o.text='';o.bgColor=rgba(paint)
   if dynamicPaint[group]then dynamicPaint[group].images[#dynamicPaint[group].images+1]={object=o,paint=paint,field='bgColor'}end
   pos(o,x,y,w,h,group.width,group.height);group.controls[#group.controls+1]=o;group.count=group.count+1;return o
  end
  function W.parts(group,parts,x,y,w,h,alpha,clip)
   local m=parts.margin;if w<m*2 or h<m*2 then fail('E_UI_WINDOW_SIZE','Window is smaller than its native frame corners')end
   local dw,dh=w-m*2,h-m*2
   for _,p in ipairs({{'tl',x,y,m,m},{'tr',x+w-m,y,m,m},{'bl',x,y+h-m,m,m},{'br',x+w-m,y+h-m,m,m},
    {'top',x+m,y,dw,m},{'bottom',x+m,y+h-m,dw,m},{'left',x,y+m,m,dh},{'right',x+w-m,y+m,m,dh},{'center',x+m,y+m,dw,dh}})do
    if parts[p[1]] and p[4]>0 and p[5]>0 then
     W.blit(group,parts[p[1]],p[2],p[3],p[4],p[5],alpha,nil,
      clip and clip.x+clip.width,clip and clip.y+clip.height,clip and clip.x,clip and clip.y)
    end
   end
  end
  function W.setWindowTone(tone)
   if not tone then return end
   local key=table.concat(tone,':');if toneKey==key then return end;toneKey=key;windowTone=tone
   for _,entry in ipairs(toneImages)do if entry.object.alive then
    local alpha=(entry.alpha or 1)*(entry.dynamic and entry.dynamic.opacity or 1)
    if updates then updates.set(entry.object,'imageColor',rgba(entry.paint,alpha,tone),key)else entry.object.imageColor=rgba(entry.paint,alpha,tone)end
   end end
  end
  function W.window(name,r,background)
   local group=W.group(name,r);local ok,reason=pcall(function()
    if background==nil or background==0 then
     local m=ui.window.margin;local w,h=r.width-m*2,r.height-m*2
     if w>0 and h>0 then
      local back=W.group(name..' background',{x=r.x+m,y=r.y+m,width=w,height=h})
      back.windowTone=true
      group.background=back
      group.backgroundOffsetX,group.backgroundOffsetY=m,m
      if platform then W.blit(back,skin.back,0,0,w,h,ui.window.backOpacity/255,windowTone)
      elseif ui.profile=='mv-1.5.1' then
       if not skin.mvBack or skin.mvBack.mode~='tile' or skin.mvBack.toneApplied~=true or skin.mvBack.opacityApplied~=false then fail('E_UI_BACK_COMPOSITION','MV requires a source-composited window background')end
       local tile=skin.mvBack.tile
       for y=0,h-1,tile.height do for x=0,w-1,tile.width do W.blit(back,tile,x,y,tile.width,tile.height,ui.window.backOpacity/255,nil,w,h)end end
      else
       if ui.profile=='mz-1.10.0'and patternMode=='source'then backgroundBatching[back]={images=0}end
       W.blit(back,skin.back,0,0,w,h,ui.window.backOpacity/255,ui.window.tone)
       if patternMode=='geometry'then patternLines(back,w,h)
       else for y=0,h-1,skin.pattern.height do for x=0,w-1,skin.pattern.width do
         W.blit(back,skin.pattern,x,y,skin.pattern.width,skin.pattern.height,ui.window.backOpacity/255,ui.window.tone,w,h)
       end end end
       backgroundBatching[back]=nil
      end
     end
     W.parts(group,skin.frame,0,0,r.width,r.height,ui.window.opacity/255)
     group.object:SetAsLastSibling()
    elseif background==1 then
     local colors=ui.window.dimColors
     if not colors or not colors.center or not colors.edge then fail('E_UI_DIM_STYLE','Source dimmer colors are required')end
     local m=ui.window.padding
     if type(m)~='number' or m%1~=0 or m<1 or r.height<m*2 then fail('E_UI_DIM_SIZE','Dim window must contain both source padding gradients')end
     if r.width==0 then return end
     local offset=ui.profile=='mz-1.10.0' and -4 or 0
     local dw=r.width-offset*2
     local back=W.group(name..' dimmer',{x=r.x+offset,y=r.y,width=dw,height=r.height})
     group.background=back;group.backgroundOffsetX,group.backgroundOffsetY=offset,0
     local function mix(a,b,t)
      local c={};for i=1,4 do
       if type(a[i])~='number' or type(b[i])~='number' or a[i]~=a[i] or b[i]~=b[i] or a[i]<0 or a[i]>255 or b[i]<0 or b[i]>255 then fail('E_UI_DIM_STYLE','Invalid source dimmer channel')end
       c[i]=a[i]+(b[i]-a[i])*t
      end;return c
     end
     if platform then
      W.solid(back,name..' dimmer top',{x=0,y=0,width=dw,height=m},mix(colors.edge,colors.center,.5))
      W.solid(back,name..' dimmer bottom',{x=0,y=r.height-m,width=dw,height=m},mix(colors.center,colors.edge,.5))
     else for y=0,m-1 do
      W.solid(back,name..' dimmer top '..y,{x=0,y=y,width=dw,height=1},mix(colors.edge,colors.center,(y+.5)/m))
      W.solid(back,name..' dimmer bottom '..y,{x=0,y=r.height-m+y,width=dw,height=1},mix(colors.center,colors.edge,(y+.5)/m))
     end end
     W.solid(back,name..' dimmer center',{x=0,y=m,width=dw,height=r.height-m*2},colors.center)
     group.object:SetAsLastSibling()
    elseif background~=2 then fail('E_UI_BACKGROUND','Unknown source window background')end
   end)
   if not ok then W.close();error(reason,0)end
   return group
  end
  local function fittedFontSize(value,r,size)
   -- Host font metrics are unavailable. Leave room for padding/outline and
   -- use conservative advances so bounded labels remain on one host line.
   local em=0
   for _,cp in utf8.codes(value)do
    if cp>=128 then em=em+1.1
    elseif cp==77 or cp==87 or cp==64 or cp==37 then em=em+1
    elseif cp==32 or cp==46 or cp==44 or cp==58 or cp==59 or cp==33 or cp==39 then em=em+.35
    else em=em+.65 end
   end
   if em==0 then return size end
   return math.max(1,math.floor(math.min(size,math.max(1,r.width-8)/em,math.max(1,r.height-4)/1.2)))
  end
  function W.text(group,name,text,r,size,paint,fitSingleLine)
   text=textLimit.clip(text)
   group.hasImmediateChildren=true
   local fontSize=size or ui.window.fontSize
   if platform and fitSingleLine~=false and not text:find('[\r\n]')then fontSize=fittedFontSize(text,r,fontSize)end
   -- Host TextBox.fontSize is an integer even when layout sizes are fractional.
   local o=create(bindings.textTemplate,name,group.object)
   -- Inherit the template's valid host minimum; setting it to 1 is rejected
   -- by UGC. The documented API does not specify a universal numeric range.
   fontSize=math.max(o.minimumFontSize or 1,math.floor(fontSize))
   o.text=text;o.fontSize=fontSize
   o.fontColor=rgba(paint or skin.textColors[1]);o.bgColor=color.FromRGBA(0,0,0,0)
   o.horizontalAlignment=enum.TextHorizontalAlignment.Left;o.verticalAlignment=enum.TextVerticalAlignment.Middle
   -- Platform fonts have host-specific line metrics. Our width estimate is
   -- only an upper bound: let the host fit the actual glyphs into short rows.
   o.adaptiveFontSize=platform
   o.enableOutline=true;o.outlineColor=rgba(ui.window.outlineColor or {0,0,0,128})
   pos(o,r.x,r.y,r.width,r.height,group.width,group.height);group.controls[#group.controls+1]=o;group.count=group.count+1;return o
  end
  function W.updateText(object,value,r,size,multiline)
   value=textLimit.clip(value)
   local fontSize=multiline and size or fittedFontSize(value,r,size)
   fontSize=math.max(object.minimumFontSize or 1,math.floor(fontSize))
   if updates then updates.set(object,'text',value);updates.set(object,'fontSize',fontSize)
   else if object.text~=value then object.text=value end;if object.fontSize~=fontSize then object.fontSize=fontSize end end
  end
  function W.number(group,name,run,r,paint,outline,clip)
   local left,top,right,bottom=r.x,r.y,r.x+r.width,r.y+r.height
   if clip then left=math.max(left,clip.x);top=math.max(top,clip.y);right=math.min(right,clip.x+clip.width);bottom=math.min(bottom,clip.y+clip.height)end
   if right<=left or bottom<=top then return end
   W.glyphs(group,name,run,r.x,r.y,paint,outline,{x=left,y=top,width=right-left,height=bottom-top})
  end
  function W.glyphs(group,name,run,originX,originY,paint,outline,clip)
   local left,top,right,bottom=clip.x,clip.y,clip.x+clip.width,clip.y+clip.height
   if right<=left or bottom<=top then return end
   -- Whole-string stroke first. Native Bitmap.drawText only applies paintOpacity
   -- to its fill; the source outline colour has independent alpha.
   for _,layer in ipairs({{run.stroke,outline,' stroke'},{run.fill,paint,' fill'}})do
    local frame,c=layer[1],layer[2]
    if frame then for i,p in ipairs(frame.rects)do
     local x,y=originX+run.x+p.x,originY+run.y+p.y
     local w,h=math.min(x+p.width,right)-math.max(x,left),math.min(y+p.height,bottom)-math.max(y,top)
     if w>0 and h>0 then
      local alpha=frame.palette[p.colorIndex][4]*c[4]/255
      if alpha>0 then draw({group=group,name=name..layer[3]..' pixel '..i,paint={c[1],c[2],c[3],alpha},x=math.max(x,left),y=math.max(y,top),width=w,height=h})end
     end
    end end
   end
  end
  function W.close()
   queue,queueHead,planned,groups={},1,0,{}
   dynamicPaint={}
   toneImages={}
   backgroundBatching={}
   revealNeeded=false
   for _,area in ipairs(listeners)do if area.object.alive then
    if area.callback then area.object:RemoveCursorEventListener(enum.CursorEventType.CursorClick,area.callback)end
    for _,entry in ipairs(area.heldListeners or {})do area.object:RemoveCursorEventListener(entry.key,entry.callback)end
   end end;listeners={}
   for i=#live,1,-1 do local o=live[i];if o.alive then game.DestroyClientUIControl(o)end end;live={};count=0
   if updates then updates.prune()end
  end
  function W.pending()return planned end
  function W.enqueueRender(group,render)
   if type(render)~='function'then fail('E_UI_DRAW_BATCH','Expected an internal glyph render callback')end
   if not deferred then render();return end
   if count+planned>=maxControls then fail('E_UI_CONTROL_BUDGET','Source UI render/control budget exceeded')end
   queue[#queue+1]={group=group,render=render};planned=planned+1
  end
  function W.flush(limit)
   if type(limit)~='number' or limit%1~=0 or limit<1 or limit>10000 then fail('E_UI_DRAW_BATCH','Invalid per-frame control limit')end
   local done=0
   while planned>0 and done<limit do
    local job=queue[queueHead];queue[queueHead]=false;queueHead=queueHead+1;planned=planned-1
    local ok,reason=pcall(function()if job.group.object.alive then
     if job.backgroundContainer then
      backgroundContainer(job.backgroundContainer)
     elseif job.render then job.render()else pixel(job)end
    end end)
    if not ok then W.close();error(reason,0)end;done=done+1
    -- Glyph raster work must not accumulate for a whole menu in one host call.
    if job.render then break end
   end
   if planned==0 and revealNeeded then
    queue,queueHead={},1
    for _,group in ipairs(groups)do if group.object.alive then visibility(group,group.visible)end end
    revealNeeded=false
   end
   return planned==0
  end
  function W.controlCount()return count end
  return W
 end
 return M
end
