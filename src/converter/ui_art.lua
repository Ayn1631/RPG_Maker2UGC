-- Offline source artwork; all host IO is contained at build.files.join.
return function(deps)
 local F,P,R,H,D=deps['build.files'],deps['assets.png'],deps['assets.rectframe'],deps['build.sha256'],deps['contracts.diagnostic'];local M={}
 local caps={files=64,frames=4096,inputBytes=67108864,pixels=4194304,rects=250000,work=2147483648.0};local SAFE=9007199254740991
 local function fail(code,reason,file)D.raise(code,reason,{file=file})end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_UI_ART_SHAPE','Expected plain source artwork data')end end
 local function integer(n,lo,hi)if type(n)~='number' or n~=n or n%1~=0 or n<lo or n>hi then fail('E_UI_ART_SHAPE','Invalid artwork integer')end;return n*1.0 end
 local function dense(a)plain(a);local n,high=0,0;for k in next,a do integer(k,1,100000);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_UI_ART_SHAPE','Expected dense artwork array')end end
 local function keys(v,allowed)for k in next,v do if not allowed[k]then fail('E_UI_ART_SHAPE','Unknown artwork option')end end end
 local function facePath(name)
  if type(name)~='string'then fail('E_UI_ART_SHAPE','Face name must be a string')end
  if name==''then return nil end
  if not F.relative(name) or name:find('[%z\1-\31]')then fail('E_UI_ART_PATH','Face name must be contained source path')end
  local relative=F.relative('img/faces/'..name..'.png');if not relative then fail('E_UI_ART_PATH','Invalid face source path')end;return relative
 end
 function M.validateTemplates(bindings)
  plain(bindings);keys(bindings,{portrait=true,icon=true,faces=true,icons=true})
  local out={portrait=integer(bindings.portrait,1,2147483647),icon=integer(bindings.icon,1,2147483647),faces={},icons={}}
  for _,kind in ipairs({'faces','icons'})do
   local values=bindings[kind];if values~=nil then
    plain(values);local count=0
    for key,value in next,values do
     if type(key)~='string' or #key>4096 then fail('E_UI_ART_SHAPE','Template override key must be a bounded string')end
     if kind=='faces' then
      local name,index=key:match('^(.*):([0-7])$')
      if not name or name=='' then fail('E_UI_ART_SHAPE','Face template key must be faceName:faceIndex (0..7)')end;facePath(name)
     elseif not (key=='0' or key:match('^[1-9]%d*$')) or not tonumber(key) or tonumber(key)>SAFE then
      fail('E_UI_ART_SHAPE','Icon template key must be a canonical nonnegative decimal integer')
     end
     count=count+1;if count>100000 then fail('E_UI_ART_SHAPE','Too many template overrides')end
     out[kind][key]=integer(value,1,2147483647)
    end
   end
  end
  return out
 end
 function M.compilePlatform(ui,bindings)
  local templates=M.validateTemplates(bindings);plain(ui)
  if ui.profile~='mv-1.5.1' and ui.profile~='mz-1.10.0' then fail('E_UI_ART_PROFILE','Unsupported UI artwork profile')end
  plain(ui.art);local size={};for _,key in ipairs({'faceWidth','faceHeight','iconWidth','iconHeight'})do size[key]=integer(ui.art[key],1,4096)end
  if size.faceWidth~=size.faceHeight or size.iconWidth~=size.iconHeight or ui.profile=='mv-1.5.1' and (size.faceWidth~=144 or size.iconWidth~=32)then fail('E_UI_ART_SHAPE','Sizes do not match source profile')end
  plain(ui.presentationDefs);local defs=ui.presentationDefs
  local out={kind='r2u.ui-art',schemaVersion=1,profile=ui.profile,renderMode='platform',sources={},frames={},actors={},icons={},buttons={},
   losslessSourcePixels=false,coverage={actors='all',icons='all'},stats={files=0,frames=0,inputBytes=0,decodedPixels=0,rectangles=0,workReserved=0}}
  dense(defs.actors);local actors={}
  for _,actor in ipairs(defs.actors)do
   plain(actor);local id=integer(actor.id,1,SAFE);if actors[id]then fail('E_UI_ART_SHAPE','Duplicate actor ID')end;actors[id]=true
   local path=facePath(actor.faceName);local index=integer(actor.faceIndex,0,7);local record={actorId=id}
   if path then record.faceName=actor.faceName;record.faceIndex=index;record.width=144;record.height=144
    record.templateId=templates.faces[actor.faceName..':'..string.format('%.0f',index)]
   else record.empty=true end
   out.actors[#out.actors+1]=record
  end
  table.sort(out.actors,function(a,b)return a.actorId<b.actorId end)
  local icons={};for _,kind in ipairs({'items','weapons','armors','skills'})do
   local records=kind=='skills' and (defs[kind] or {}) or defs[kind]
   dense(records);local seen={};for _,record in ipairs(records)do
    plain(record);local id=integer(record.id,1,SAFE);if seen[id]then fail('E_UI_ART_SHAPE','Duplicate presentation record ID')end;seen[id]=true
    local index=integer(record.iconIndex,0,SAFE)
    if not icons[index]then icons[index]=true;out.icons[#out.icons+1]={iconIndex=index,templateId=templates.icons[string.format('%.0f',index)],width=32,height=32}end
   end
  end
  table.sort(out.icons,function(a,b)return a.iconIndex<b.iconIndex end)
  if ui.profile=='mz-1.10.0' then for _,b in ipairs({{'cancel',96},{'pageup',48},{'pagedown',48},{'menu',48}})do
   out.buttons[#out.buttons+1]={symbol=b[1],width=b[2],height=48,coldOpacity=192,hotOpacity=255}
  end end
  return out
 end
 function M.compile(sourceRoot,ui,options)
  if type(sourceRoot)~='string' or sourceRoot=='' or sourceRoot:find('[%z\1-\31]')then fail('E_UI_ART_PATH','Source root required')end
  plain(ui);local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('E_UI_ART_PROFILE','Unsupported UI artwork profile')end
  plain(ui.art);local size={};for _,key in ipairs({'faceWidth','faceHeight','iconWidth','iconHeight'})do size[key]=integer(ui.art[key],1,4096)end
  if size.faceWidth~=size.faceHeight or size.iconWidth~=size.iconHeight or not mz and (size.faceWidth~=144 or size.iconWidth~=32)then fail('E_UI_ART_SHAPE','Sizes do not match source profile')end
  if options==nil then options={}end;plain(options);keys(options,{actorIds=true,iconIndices=true,limits=true})
  local requested=options.limits;if requested==nil then requested={}end;plain(requested);keys(requested,caps);local limits={};for key,value in pairs(caps)do limits[key]=requested[key]~=nil and integer(requested[key],1,value) or value end
  plain(ui.presentationDefs);local defs=ui.presentationDefs;local actorById,actorIds,iconSet,iconIndices={},{},{},{}
  dense(defs.actors);for _,actor in ipairs(defs.actors)do plain(actor);local id=integer(actor.id,1,SAFE);if actorById[id]then fail('E_UI_ART_SHAPE','Duplicate actor ID')end
   actorById[id]={path=facePath(actor.faceName),index=integer(actor.faceIndex,0,7)};actorIds[#actorIds+1]=id
  end;table.sort(actorIds)
  for _,kind in ipairs({'items','weapons','armors','skills'})do local records=kind=='skills' and (defs[kind] or {}) or defs[kind];dense(records);local seen={};for _,record in ipairs(records)do plain(record);local id=integer(record.id,1,SAFE);if seen[id]then fail('E_UI_ART_SHAPE','Duplicate presentation record ID')end;seen[id]=true;local index=integer(record.iconIndex,0,SAFE);if not iconSet[index]then iconSet[index]=true;iconIndices[#iconIndices+1]=index end end end;table.sort(iconIndices)
  local function select(request,defaults,actors)
   if request==nil then return defaults end;dense(request);local out,seen={},{};for _,v in ipairs(request)do local n=integer(v,actors and 1 or 0,SAFE);if seen[n]then fail('E_UI_ART_SHAPE','Duplicate artwork request')end;seen[n]=true;if actors and not actorById[n]then fail('E_UI_ART_REFERENCE','Requested actor presentation is missing')end;out[#out+1]=n end;table.sort(out);return out
  end
  actorIds=select(options.actorIds,actorIds,true);iconIndices=select(options.iconIndices,iconIndices,false)
  local out={kind='r2u.ui-art',schemaVersion=1,profile=ui.profile,sources={},frames={},actors={},icons={},buttons={},coverage={actors=options.actorIds~=nil and 'explicit' or 'all',icons=options.iconIndices~=nil and 'explicit' or 'all'},losslessSourcePixels=true,
   stats={files=0.0,frames=0.0,inputBytes=0.0,decodedPixels=0.0,rectangles=0.0,workReserved=0.0}}
  local cache,frames={},{};local stats=out.stats
  local function budget(ok,why,file)if not ok then fail('E_UI_ART_BUDGET',why,file)end end
  local function guarded(file,fn,...)
   local ok,value=pcall(fn,...);if ok then return value end
   if D.is(value)then local e={};for k,v in pairs(value)do e[k]=v end;e.file=file;error(e,0)end;error(value,0)
  end
  local function source(relative)
   if cache[relative]then return cache[relative]end
   local full=F.join(sourceRoot,relative);budget(stats.files<limits.files,'Source file budget exceeded',relative)
   budget(stats.decodedPixels<limits.pixels,'Decoded pixel budget exceeded',relative)
   -- Reserve the decoder's complete operation allowance, since PNG intentionally
   -- does not export internal counters. This is a conservative bound, not timing.
   local allowance=math.min(33554432.0,limits.work-stats.workReserved);budget(allowance>=1,'PNG operation allowance exhausted',relative)
   local bytes,reason=F.read(full);if type(bytes)~='string'then fail('E_UI_ART_READ',type(reason)=='string' and reason or 'Source image cannot be read',relative)end
   budget(#bytes<=limits.inputBytes-stats.inputBytes,'Total source byte budget exceeded',relative)
   local image=guarded(relative,P.decode,bytes,{inputBytes=math.min(16777216,limits.inputBytes-stats.inputBytes),pixels=math.min(1048576,limits.pixels-stats.decodedPixels),work=allowance})
   stats.files=stats.files+1.0;stats.inputBytes=stats.inputBytes+#bytes;stats.decodedPixels=stats.decodedPixels+image.width*image.height;stats.workReserved=stats.workReserved+allowance
   local index=#out.sources+1;out.sources[index]={path=relative,sha256=H.hex(bytes),bytes=#bytes,width=image.width,height=image.height,colorType=image.colorType,bitDepth=image.bitDepth}
   local entry={image=image,index=index};cache[relative]=entry;return entry
  end
  local function crop(relative,x,y,w,h)
   local key=relative..':'..x..':'..y..':'..w..':'..h;if frames[key]then return frames[key]end
   budget(stats.frames<limits.frames,'Unique frame budget exceeded',relative)
   budget(stats.rectangles<limits.rects,'Rectangle budget exceeded',relative)
   local entry=source(relative);local remaining=limits.work-stats.workReserved;budget(remaining>=1,'Rectangle operation allowance exhausted',relative)
   local region={x=x,y=y,width=w,height=h};local frame=guarded(relative,R.compile,entry.image,region,{rects=math.min(100000,limits.rects-stats.rectangles),work=math.min(8388608,remaining)})
   local index=#out.frames+1;out.frames[index]={sourceIndex=entry.index,region=region,frame=frame};frames[key]=index
   stats.frames=stats.frames+1.0;stats.rectangles=stats.rectangles+#frame.rects;stats.workReserved=stats.workReserved+frame.stats.work;return index
  end
  for _,id in ipairs(actorIds)do local def=actorById[id];local record={actorId=id};if def.path then record.frameIndex=crop(def.path,(def.index%4)*size.faceWidth,math.floor(def.index/4)*size.faceHeight,size.faceWidth,size.faceHeight)else record.empty=true end;out.actors[#out.actors+1]=record end
  for _,index in ipairs(iconIndices)do out.icons[#out.icons+1]={iconIndex=index,frameIndex=crop('img/system/IconSet.png',(index%16)*size.iconWidth,math.floor(index/16)*size.iconHeight,size.iconWidth,size.iconHeight)}end
  if mz then
   local buttons={{'cancel',0,2},{'pageup',2,1},{'pagedown',3,1},{'menu',10,1}}
   for _,b in ipairs(buttons)do out.buttons[#out.buttons+1]={symbol=b[1],coldFrameIndex=crop('img/system/ButtonSet.png',b[2]*48,0,b[3]*48,48),hotFrameIndex=crop('img/system/ButtonSet.png',b[2]*48,48,b[3]*48,48),coldOpacity=192,hotOpacity=255}end
  end
  return out
 end
 return M
end
