return function(deps)
 local Windows=deps['platform.ugc.rpg_windows'];local M={}
 local function assetRequired(value,name)if not value then error({code='E_RESOURCE_BINDING',reason='Missing compiled resource: '..tostring(name)},0)end;return value end
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 local function clamp(v)return math.max(0,math.min(255,v))end
 local function fail(s)error({code='E_VISU_PRESENTATION',reason=s},0)end
 function M.evaluate(v,symbols)
  if type(v)=='number'then return v end
  if type(v)~='table'then fail('Expected coordinate expression')end
  if v.symbol then local n=symbols[v.symbol];if type(n)~='number'then fail('Unresolved coordinate symbol '..tostring(v.symbol))end;return n end
  if v.op=='positive'then return M.evaluate(v.value,symbols)elseif v.op=='negative'then return -M.evaluate(v.value,symbols)end
  local a,b=M.evaluate(v.left,symbols),M.evaluate(v.right,symbols)
  if v.op=='+'then return a+b elseif v.op=='-'then return a-b elseif v.op=='*'then return a*b elseif v.op=='/'and b~=0 then return a/b end
  fail('Invalid coordinate operator or division by zero')
 end
 local function ease(t,name)
  name=(name or 'linear'):lower()
  if name=='linear'then return t elseif name=='insine'then return 1-math.cos(t*math.pi/2)elseif name=='outsine'then return math.sin(t*math.pi/2)
  elseif name=='inoutsine'then return -(math.cos(math.pi*t)-1)/2
  elseif name=='inback'then return 2.70158*t^3-1.70158*t^2 elseif name=='outback'then return 1+2.70158*(t-1)^3+1.70158*(t-1)^2
  elseif name=='inelastic'then return t==0 and 0 or t==1 and 1 or -2^(10*t-10)*math.sin((t*10-10.75)*2*math.pi/3)end
  local power={quad=2,cubic=3,quart=4,quint=5};local dir,p=name:match('^(in)(.+)$');if not dir then dir,p=name:match('^(out)(.+)$')end
  if power[p]then return dir=='in'and t^power[p]or 1-(1-t)^power[p]end
  fail('Unsupported movement easing '..name)
 end
 function M.new(host,root,bindings,ui,skin)
  local surface=Windows.new(host,root,bindings,ui,skin)
  local updates=bindings.updates
  local function call(o,name,...)if updates then updates.call(o,name,...)else o[name](o,...)end end
  local function color(o,r,g,b,a)
   local value=host.Color.FromRGBA(r,g,b,a)
   if updates then updates.set(o,'bgColor',value,table.concat({r,g,b,a},':'))else o.bgColor=value end
  end
  local objects={};local animationViews={};local weather={};local sw,sh=ui.screen.width,ui.screen.height
  local leases={};local cachedFrames,activeLeases,stamp=0,0,0
  local filters=surface.group('RPG screen effects',rect(0,0,sw,sh));local layers={}
  for _,name in ipairs({'tone','flash','fade'})do
   layers[name]=surface.solid(filters,'RPG screen '..name,rect(0,0,sw,sh),{0,0,0,255});layers[name].bgColor=host.Color.FromRGBA(0,0,0,0)
  end
  local baseColors=setmetatable({},{__mode='k'})
  local function capture(object,out)
   for _,key in ipairs({'imageColor','fontColor','outlineColor','bgColor'})do
    local ok,value=pcall(function()return object[key]end)
    if ok and value~=nil then
     local success,r,g,b,a=pcall(host.Color.ToRGBA,value)
     if success and (a>0 or baseColors[object]and baseColors[object][key])then
      baseColors[object]=baseColors[object]or{};local base=baseColors[object][key]or{r,g,b,a};baseColors[object][key]=base
      out[#out+1]={object=object,key=key,r=base[1],g=base[2],b=base[3],a=base[4],applied=table.concat({math.floor(r+.5),math.floor(g+.5),math.floor(b+.5),math.floor(a+.5)},':')}
     end
    end
   end
   for _,child in ipairs(object:GetChildren())do capture(child,out)end
  end
  local function tint(entries,tone,opacity)
   local gray=clamp(tone[4])/255
   for _,e in ipairs(entries)do
    local light=e.r*.299+e.g*.587+e.b*.114
    local r,g,b,a=clamp(e.r+(light-e.r)*gray+tone[1]),clamp(e.g+(light-e.g)*gray+tone[2]),clamp(e.b+(light-e.b)*gray+tone[3]),clamp(e.a*opacity/255)
    -- Host colours are byte channels. Coalesce tiny tween changes before
    -- allocating a Color or crossing the host bridge.
    r,g,b,a=math.floor(r+.5),math.floor(g+.5),math.floor(b+.5),math.floor(a+.5)
    local key=table.concat({r,g,b,a},':')
    if key~=e.applied then
     local value=host.Color.FromRGBA(r,g,b,a)
     if updates then updates.set(e.object,e.key,value,key)else e.object[e.key]=value end;e.applied=key
    end
   end
  end
  local visu={last=0,clock=0,units={},effects={},serial=0,scale=1,stop=0}
  local function refkey(r)return r.kind..':'..tostring(r.id or r.troopSlot)end
  local function unit(r,locate)
   local key=refkey(r);local v=visu.units[key]
   if not v then local p=locate(r);if not p then fail('Missing battler position '..key)end
    v={ref=r,home={x=p.x,y=p.y,width=p.width or 48,height=p.height or 48},x=0,y=0,float=0,jump=0,angle=0,face=1,opacity=255,motion='wait',motionClock=visu.clock,tweens={}}
    visu.units[key]=v
   end;return v
  end
  local function point(r,locate)
   local p=locate and locate(r);if not p then fail('Missing Visu coordinate target')end
   local v=visu.units[refkey(r)]
   return{x=p.x+(v and v.x or 0),y=p.y+(v and v.y-v.float-v.jump or 0),width=p.width or 48,height=p.height or 48}
  end
  local function symbols(row,locate)
   local subject=point(row.subjectRef,locate);local target=row.allTargets and row.allTargets[1]or row.targetRef or row.subjectRef;local p=point(target,locate)
   -- MZ battler sprite x/y uses a bottom-centre anchor; locate supplies its
   -- visual centre for ordinary animation placement.
   return{width=sw,height=sh,subjectX=subject.x,subjectY=subject.y+subject.height/2,targetX=p.x,targetY=p.y+p.height/2,targetHeight=p.height}
  end
  local function atLocation(p,location,facing)
   location=location or 'middle center';local side,vertical=location:match('^(%a+) (%a+)$')
   local sx=({front=1,middle=0,back=-1})[side];local sy=({head=-.5,center=0,base=.5})[vertical]
   if not sx or not sy then fail('Unsupported target location '..location)end
   return{x=p.x+sx*(facing or 1)*p.width/2,y=p.y+sy*p.height}
  end
  local function animateUnit(v,field,to,duration,easing,revert)
   if duration<=0 then v[field]=to;v.tweens[field]=nil;return end
   v.tweens[field]={from=v[field],to=to,start=visu.clock,duration=duration,easing=easing,revert=revert}
  end
  local effectAssets={}
  local function effectAsset(kind,tone)
   local rgb=tone or {180,220,255};local key=kind..':'..table.concat(rgb,':');local asset=effectAssets[key];if asset then return asset end
   local frame={kind='r2u.primitive-frame',schemaVersion=1,width=96,height=96,palette={{clamp(rgb[1]),clamp(rgb[2]),clamp(rgb[3]),210}},rects={}}
   for i=0,7 do local angle=i*math.pi/4;frame.rects[#frame.rects+1]={x=math.floor(44+math.cos(angle)*32),y=math.floor(44+math.sin(angle)*32),width=8,height=8,colorIndex=1}end
   asset={renderKey='visu.effect:'..key,width=96,height=96,primitiveFrames={frame},frameTicks=1};effectAssets[key]=asset;return asset
  end
  local function effect(kind,p,duration,tone,extra)
   visu.serial=visu.serial+1;local e={id='visu:'..visu.serial,kind='animation',point=p,asset=effectAsset(kind,tone),start=visu.clock,duration=math.max(1,duration),elapsed=0,visuEffect=kind}
   for k,v in pairs(extra or {})do e[k]=v end;visu.effects[#visu.effects+1]=e;return e
  end
  local function advanceVisu(clock,locate)
   local delta=math.max(0,clock-visu.clock);visu.clock=clock
   for _,v in pairs(visu.units)do
    local home=locate(v.ref);if home then v.home={x=home.x,y=home.y,width=home.width or 48,height=home.height or 48}end
    v.motionElapsed=(v.motionElapsed or 0)+math.max(0,clock-math.max(clock-delta,visu.stop))*visu.scale
    for field,t in pairs(v.tweens)do local ratio=math.min(1,(clock-t.start)/t.duration);v[field]=t.from+(t.to-t.from)*ease(ratio,t.easing)
     if ratio==1 then if t.revert then v[field]=t.from end;v.tweens[field]=nil end
    end
    if v.jumpMotion then local j=v.jumpMotion;local ratio=math.min(1,(clock-j.start)/j.duration);v.jump=4*j.height*ratio*(1-ratio);if ratio==1 then v.jumpMotion=nil;v.jump=0 end end
    if v.trail and delta>0 then
     local trail=v.trail
     if clock-trail.last>=math.max(1,trail.delay)then
      trail.last=clock;local p=point(v.ref,locate)
      -- Six reusable leases per trail suffice for the geometric substitute.
      local live=0;for _,e in ipairs(visu.effects)do if e.trailOwner==v and clock-e.start<e.duration then live=live+1 end end
      if live<6 then effect('trail',{x=p.x,y=p.y},trail.duration,trail.tone,{trailOwner=v,opacity=trail.opacity})end
     end
    end
   end
   for i=#visu.effects,1,-1 do local e=visu.effects[i];e.elapsed=clock-e.start;if e.elapsed>=e.duration then table.remove(visu.effects,i)end end
  end
  local function consumeVisu(row,locate,battlers)
   local cmd,a=row.command,row.args;local ctx=symbols(row,locate)
   local function number(v,default)return v==nil and (default or 0)or M.evaluate(v,ctx)end
   local duration=math.max(0,number(a.Duration));local targets=row.targets or {}
   local function all(fn)for _,r in ipairs(targets)do fn(unit(r,locate),r)end end
   local function motion(v,name,frame)if name and name~=''then v.motion=name;v.motionClock=visu.clock;v.motionElapsed=0 end;v.frame=frame end
   if cmd=='ActSeq_Movement_Jump'then all(function(v)v.jumpMotion={start=visu.clock,height=number(a.Height),duration=math.max(1,duration)}end)
   elseif cmd=='ActSeq_Movement_Float'then all(function(v)animateUnit(v,'float',number(a.Height),duration,a.EasingType)end)
   elseif cmd=='ActSeq_Movement_Spin'then all(function(v)animateUnit(v,'angle',number(a.Angle),duration,a.EasingType,a.RevertAngle)end)
   elseif cmd=='ActSeq_Movement_Opacity'then all(function(v)animateUnit(v,'opacity',clamp(number(a.Opacity)),duration,a.EasingType)end)
   elseif cmd=='ActSeq_Movement_FaceDirection'then
    if a.Direction~='forward'and a.Direction~='backward'then fail('Unsupported facing '..tostring(a.Direction))end
    all(function(v)v.face=a.Direction=='forward'and 1 or -1 end)
   elseif cmd=='ActSeq_Movement_MoveBy'or cmd=='ActSeq_Movement_MoveToPoint'or cmd=='ActSeq_Movement_MoveToTarget'then
    all(function(v,r)
     local facing=r.kind=='actor'and -1 or 1;local x,y
     if cmd=='ActSeq_Movement_MoveBy'then x=v.home.x+v.x+number(a.DistanceX)*(a.DistanceAdjust=='horz'and facing or 1);y=v.home.y+v.y+number(a.DistanceY)
     elseif cmd=='ActSeq_Movement_MoveToPoint'then
      if a.Destination=='home'then x,y=v.home.x,v.home.y elseif a.Destination=='center'then x,y=sw/2,sh/2-v.home.height/2 else fail('Unsupported destination '..tostring(a.Destination))end
     else
      local total={x=0,y=0};local count=0
      for _,target in ipairs(row.allTargets or {})do local p=atLocation(point(target,locate),a.TargetLocation,target.kind=='actor'and -1 or 1);total.x=total.x+p.x;total.y=total.y+p.y;count=count+1 end
      if count==0 then fail('MoveToTarget has no resolved targets')end
      x,y=total.x/count-facing*number(a.MeleeDistance),total.y/count-v.home.height/2
     end
     if cmd~='ActSeq_Movement_MoveBy'then x=x+number(a.OffsetX)*(a.OffsetAdjust=='horz'and facing or 1);y=y+number(a.OffsetY)end
     if a.FaceDirection then v.face=x>=v.home.x+v.x and -facing or facing end
     animateUnit(v,'x',x-v.home.x,duration,a.EasingType);animateUnit(v,'y',y-v.home.y,duration,a.EasingType);motion(v,a.MotionType)
    end)
   elseif cmd=='ActSeq_Motion_MotionType'or cmd=='ActSeq_Motion_PerformAction'or cmd=='ActSeq_Motion_FreezeMotionFrame'then
    all(function(v)motion(v,a.MotionType or 'perform',cmd=='ActSeq_Motion_FreezeMotionFrame'and a.Frame or nil);v.actionRef=row.actionRef;v.showWeapon=a.ShowWeapon==true end)
   elseif cmd=='ActSeq_Motion_ClearFreezeFrame'then all(function(v)v.frame=nil;v.motionClock=visu.clock;v.motionElapsed=0 end)
   elseif cmd=='ActSeq_Impact_MotionTrailCreate'then all(function(v)v.trail={delay=a.delay,duration=a.duration,tone=a.tone,opacity=a.opacityStart,last=visu.clock-1}end)
   elseif cmd=='ActSeq_Impact_MotionTrailRemove'then all(function(v)v.trail=nil end)
   elseif cmd=='ActSeq_Impact_ShockwaveEachTargets'then
    all(function(_,r)local p=atLocation(point(r,locate),a.TargetLocation,r.kind=='actor'and -1 or 1);p.x=p.x+number(a.OffsetX);p.y=p.y+number(a.OffsetY);effect('shockwave',p,duration,nil,{radius=number(a.Wave,48),amp=number(a.Amp,12)})end)
   elseif cmd=='ActSeq_Impact_ZoomBlurPoint'then effect('zoom',{x=number(a.X),y=number(a.Y)},duration,nil,{radius=96+number(a.Radius),amp=number(a.Strength)*80})
   elseif cmd=='ActSeq_Impact_ColorBreak'then effect('colorbreak',{x=sw/2,y=sh/2},duration,{255,80,160},{radius=math.max(sw,sh),opacity=number(a.Intensity)})
   elseif cmd=='ActSeq_Impact_Oversaturate'or cmd=='ActSeq_Impact_BlueRedInvert'then
    local kind=cmd=='ActSeq_Impact_Oversaturate'and 'saturate'or'invert'
    for i=#visu.effects,1,-1 do if visu.effects[i].visuEffect==kind then table.remove(visu.effects,i)end end
    if a.Enable then effect(kind,{x=sw/2,y=sh/2},600,kind=='invert'and{70,120,255}or{255,200,80},{radius=math.max(sw,sh),opacity=90})end
   elseif cmd=='ActSeq_Impact_TimeStop'then visu.stop=visu.clock+number(a.ms)*60/1000;effect('timestop',{x=sw/2,y=sh/2},math.ceil(number(a.ms)*60/1000),{200,220,255},{radius=math.max(sw,sh)})
   elseif cmd=='ActSeq_Impact_TimeScale'then visu.scale=number(a.Scale,1);effect('timescale',{x=sw/2,y=sh/2},18,{100,180,255},{radius=math.max(sw,sh),opacity=80})
   elseif cmd=='ActSeq_BattleLog_UI'then if battlers then battlers(nil,{logVisible=a.ShowHide})end
   elseif cmd=='ActSeq_BattleLog_Clear'then if battlers then battlers(nil,{clearLog=true})end
   elseif cmd=='ActSeq_Set_SetupAction'then
    local v=unit(row.subjectRef,locate);motion(v,'skill');if a.CastAnimation then effect('cast',point(row.subjectRef,locate),24,{150,200,255})end
   elseif cmd=='ActSeq_Set_FinishAction'then
    for _,v in pairs(visu.units)do v.trail=nil;v.frame=nil;v.showWeapon=false;motion(v,'wait');animateUnit(v,'x',0,12,'OutSine');animateUnit(v,'y',0,12,'OutSine');animateUnit(v,'float',0,12,'OutSine');animateUnit(v,'angle',0,12,'OutSine');animateUnit(v,'opacity',255,12,'linear');v.face=1 end
    visu.scale=1;visu.stop=0;if a.ClearBattleLog and battlers then battlers(nil,{clearLog=true})end
   elseif cmd=='ActSeq_Projectile_Animation'then
    local function endpoint(def)
     local p
     if def.Type=='target'then local selector=def.Targets and def.Targets[1];local r=selector=='user'and row.subjectRef or (selector=='all targets'or selector=='current target')and row.allTargets[1];if not r then fail('Unsupported projectile target selector')end;p=atLocation(point(r,locate),def.TargetLocation,r.kind=='actor'and -1 or 1)
     elseif def.Type=='point'then p={x=number(def.PointX),y=number(def.PointY)}else fail('Unsupported projectile endpoint')end
     p.x=p.x+number(def.OffsetX);p.y=p.y+number(def.OffsetY);return p
    end
    effect('projectile',endpoint(a.Start),duration,nil,{asset=row.asset,goal=endpoint(a.Goal),arc=number(a.Extra and a.Extra.Arc),spin=number(a.Extra and a.Extra.Spin),easing=a.Extra and a.Extra.EasingType})
   else fail('Unsupported Visu presentation command '..tostring(cmd))end
  end
  local function pictureKey(p)
   local a=assetRequired(p.asset,p.name)
   return a.renderKey or p.name..':'..tostring(a.templateId)..':'..a.width..':'..a.height
  end
  local function rebuild(list)
   local seen,changed={},false
   for _,p in ipairs(list)do
    seen[p.id]=true;local asset=assetRequired(p.asset,p.name)
    local key=pictureKey(p)
    local entry=objects[p.id]
    if entry and entry.key~=key then entry.surface.close();objects[p.id]=nil;entry=nil;changed=true end
    if not entry and p.opacity>0 and p.scaleX~=0 and p.scaleY~=0 then
    changed=true
    local pictures=Windows.new(host,root,bindings,ui,skin)
    local g=pictures.group('RPG picture '..p.id,rect(0,0,asset.width,asset.height))
    if asset.primitive or asset.templateId then pictures.art(g,'RPG picture '..p.id..' art',asset.primitive or asset.templateId,rect(0,0,asset.width,asset.height),nil,false,asset.width,asset.height)
    else error({code='E_RESOURCE_BINDING',reason='Picture has no explicit artwork: '..p.name},0)
    end
    local paint={};capture(g.object,paint);objects[p.id]={group=g,paint=paint,key=key,surface=pictures}
    end
   end
   for id,entry in pairs(objects)do if not seen[id]then entry.surface.close();objects[id]=nil;changed=true end end
   return changed
  end
  local function release(entry)
   entry.surface.show(entry.group,false);entry.active=false;activeLeases=activeLeases-1
   stamp=stamp+1;entry.used=stamp
  end
  local function closeLease(entry)
   for _,frame in pairs(entry.frames)do frame.surface.close();cachedFrames=cachedFrames-1 end
   entry.surface.close()
  end
  local function trim()
   while cachedFrames>64+activeLeases do
    local oldest,owner,key
    for _,entry in ipairs(leases)do for id,frame in pairs(entry.frames)do
     if (not entry.active or entry.frame~=id) and (not oldest or frame.used<oldest.used)then oldest,owner,key=frame,entry,id end
    end end
    if not oldest then break end
    oldest.surface.close();owner.frames[key]=nil;cachedFrames=cachedFrames-1
   end
   while #leases-activeLeases>8 do
    local oldest,index
    for i,entry in ipairs(leases)do if not entry.active and (not oldest or entry.used<oldest.used)then oldest,index=entry,i end end
    closeLease(oldest);table.remove(leases,index)
   end
  end
  local function acquire(a,def,frame)
   -- Normal assets have a converter-assigned key. Raw host fixtures compute
   -- their signature only when acquiring a playback, never on each frame.
   local key=def.renderKey or table.concat({a.kind,tostring(a.animationId or a.balloonId),tostring(def.templateId),def.width,def.height,def.frames and table.concat(def.frames,',') or ''},':')
   local entry
   for _,candidate in ipairs(leases)do if not candidate.active and candidate.key==key then entry=candidate;break end end
   if not entry then
    local w=Windows.new(host,root,bindings,ui,skin);local g=w.group('RPG '..a.kind..' '..a.id,rect(0,0,def.width,def.height),nil,true)

    entry={surface=w,group=g,key=key,frames={}};leases[#leases+1]=entry
   end
   entry.active=true;entry.fixedPoint=nil;activeLeases=activeLeases+1;entry.surface.show(entry.group,true)
   local name='RPG '..a.kind..' '..a.id
   if updates then updates.set(entry.group.object,'name',name)else entry.group.object.name=name end
   animationViews[a.id]=entry;return entry
  end
  local function animation(a,world,locate)
   local def=assetRequired(a.asset,a.kind)
   local primitiveIndex=def.primitiveFrames and math.min(#def.primitiveFrames,math.floor(a.elapsed/(def.frameTicks or 4))+1)
   local primitive=primitiveIndex and def.primitiveFrames[primitiveIndex]
   local frame=primitiveIndex and 'primitive:'..primitiveIndex or def.frames and def.frames[math.min(#def.frames,math.floor(a.elapsed/(def.frameTicks or 4))+1)] or def.templateId
   if not frame then error({code='E_RESOURCE_BINDING',reason='Missing explicit animation/balloon frame'},0)end
   local entry=animationViews[a.id] or acquire(a,def,frame)
   if frame and (entry.frame~=frame or not entry.frames[frame])then
    local previous=entry.frames[entry.frame];if previous then previous.surface.show(previous.group,false)end
    local drawing=entry.frames[frame]
    if not drawing then
     local w=Windows.new(host,root,bindings,ui,skin)
     local g=w.group('RPG animation frame '..frame,rect(0,0,def.width,def.height),entry.group)
     w.art(g,'RPG animation art',primitive or frame,rect(0,0,def.width,def.height),nil,false,def.width,def.height)
     drawing={surface=w,group=g};entry.frames[frame]=drawing;cachedFrames=cachedFrames+1
    end
    stamp=stamp+1;drawing.used=stamp;drawing.surface.show(drawing.group,true);entry.frame=frame
   end
   local position
   if a.point then
    if not entry.fixedPoint then
     local ctx=a.subjectRef and symbols(a,locate)or{}
     entry.fixedPoint={x=M.evaluate(a.point.x,ctx),y=M.evaluate(a.point.y,ctx)}
    end
    position=entry.fixedPoint
   elseif a.targetRef then position=point(a.targetRef,locate)
   else position=locate and locate(a.characterId)end
   if not position then error({code='E_RESOURCE_BINDING',reason='Animation target has no resolved source position'},0)end
   local x,y=position.x,position.y;local ratio=math.min(1,a.elapsed/a.duration)
   if a.goal then local t=ease(ratio,a.easing);x=x+(a.goal.x-x)*t;y=y+(a.goal.y-y)*t+4*(a.arc or 0)*ratio*(1-ratio)end
   entry.surface.move(entry.group,x-entry.group.width/2,y-entry.group.height/2-(a.kind=='balloon' and 40 or 0))
   local scale=a.visuEffect and a.visuEffect~='projectile'and (a.radius or 48)/48*(a.visuEffect=='trail'and .4 or .3+ratio)or 1
   call(entry.group.object,'SetLocalScale',(a.mirror and -1 or 1)*scale,scale,1)
   call(entry.group.object,'SetLocalRotation',0,0,(a.spin or 0)*360*ratio)
   local drawing=entry.frames[entry.frame]
   if a.visuEffect and drawing then
    if not drawing.paint then drawing.paint={};capture(drawing.group.object,drawing.paint)end
    tint(drawing.paint,{0,0,0,0},(a.opacity or 255)*(1-ratio))
   end
   entry.seen=true
  end
  local movieSurface,movieRoot,movieCurrent;local movieFrames={};local movieCount,movieStamp=0,0;local movieVisible=false
  local function video(v)
   if not v then if movieRoot then movieSurface.show(movieRoot,false)end;movieVisible=false;return end
   if not movieRoot then
    movieSurface=Windows.new(host,root,bindings,ui,skin)
    movieRoot=movieSurface.group('RPG video replacement',rect(0,0,sw,sh))
    movieSurface.solid(movieRoot,'RPG video background',rect(0,0,sw,sh),{0,0,0,255})
   end
   movieSurface.show(movieRoot,true);movieVisible=true
   local key=v.templateId..':'..v.width..':'..v.height;local frame=movieFrames[key]
   if not frame then
    local w=Windows.new(host,root,bindings,ui,skin);local g=w.group('RPG video frame '..v.templateId,rect(0,0,sw,sh),movieRoot)
    local scale=math.min(sw/v.width,sh/v.height);local width,height=v.width*scale,v.height*scale
    w.art(g,'RPG video frame art',v.templateId,rect((sw-width)/2,(sh-height)/2,width,height),nil,false,v.width,v.height)
    frame={surface=w,group=g,key=key};movieFrames[key]=frame;movieCount=movieCount+1
   end
   if movieCurrent~=frame then
    if movieCurrent then movieCurrent.surface.show(movieCurrent.group,false)end
    frame.surface.show(frame.group,true);movieCurrent=frame
   end
   movieStamp=movieStamp+1;frame.used=movieStamp
   if movieCount>32 then
    local oldest;for _,candidate in pairs(movieFrames)do if candidate~=frame and (not oldest or candidate.used<oldest.used)then oldest=candidate end end
    oldest.surface.close();movieFrames[oldest.key]=nil;movieCount=movieCount-1
   end
  end
  local lastRevision,lastOrder;local S={}
  function S.raiseVideo()
   if movieVisible and movieRoot.object:GetSiblingIndex()~=#root:GetChildren()-1 then movieRoot.object:SetAsLastSibling()end
  end
  function S.update(state,world,locate,mapObject,battlers)
   if not state then return end
   if state.visu and visu.generation~=state.visu.generation then visu={last=0,clock=0,units={},effects={},serial=visu.serial,scale=1,stop=0,generation=state.visu.generation}end
   if state.visu then
    for _,row in ipairs(state.visu.events or {})do if row.id>visu.last then
     if row.id~=visu.last+1 then fail('Visu presentation journal overrun')end
     advanceVisu(row.clock,locate);consumeVisu(row,locate,battlers);visu.last=row.id
    end end
    advanceVisu(state.clock,locate)
    if battlers then for _,v in pairs(visu.units)do
     v.clock=visu.clock;v.motionSpeed=visu.scale;v.frozen=visu.clock<visu.stop
     local draw=battlers(v.ref,v)
     if draw and draw.group then
      -- Capture once per lazy frame version; colour writes are coalesced.
      if draw.paintVersion~=draw.version then draw.paint={};capture(draw.group.object,draw.paint);draw.paintVersion=draw.version end
      if not draw.paint then draw.paint={};capture(draw.group.object,draw.paint)end
      tint(draw.paint,{0,0,0,0},v.opacity)
     end
    end end
   elseif visu.last>0 then visu={last=0,clock=state.clock,units={},effects={},serial=visu.serial,scale=1,stop=0}end
   local playing={}
   for _,a in ipairs(state.animations)do
    -- Map effects belong to their source map. A transfer must not retarget an
    -- old event ID at the new map. A culled map sprite has no visible lease;
    -- its timing/audio continue in the domain without allocating UI offscreen.
    local sameMap=not a.mapId or not world.mapId or a.mapId==world.mapId
    local shown=sameMap and (a.battle or a.targetRef or a.point or locate and locate(a.characterId))
    if sameMap and shown then playing[#playing+1]=a end
   end
   for _,a in ipairs(visu.effects)do playing[#playing+1]=a end
   video(state.video)
   local key={};for _,p in ipairs(state.pictures)do key[#key+1]=p.id..':'..pictureKey(p)end;key=table.concat(key,'|')
   if rebuild(state.pictures)then lastOrder=nil;filters.object:SetAsLastSibling()end
   -- Position-only character changes must still move a live animation.
   for _,entry in pairs(animationViews)do entry.seen=false end
   for _,a in ipairs(playing)do local entry=animationViews[a.id];if entry then entry.seen=true end end
   for id,entry in pairs(animationViews)do if not entry.seen then release(entry);animationViews[id]=nil end end
   for _,a in ipairs(playing)do animation(a,world,locate)end
   trim()
   local order=key..':'..tostring(mapObject)
   for _,a in ipairs(playing)do order=order..':'..a.id end
   if mapObject and order~=lastOrder then
    local at=mapObject:GetSiblingIndex()+1
    for _,p in ipairs(state.pictures)do if objects[p.id]then objects[p.id].group.object:SetSiblingIndex(at);at=at+1 end end
    for _,a in ipairs(playing)do animationViews[a.id].group.object:SetSiblingIndex(at);at=at+1 end
    filters.object:SetSiblingIndex(at)
    lastOrder=order
   end
   if state.revision==lastRevision then return end;lastRevision=state.revision
   for _,p in ipairs(state.pictures)do local entry=objects[p.id]
   if entry then local g=entry.group
    local sx,sy=p.scaleX/100,p.scaleY/100
    local shown=p.opacity>0 and sx~=0 and sy~=0;entry.surface.show(g,shown)
    if shown then
    local x=p.x+(p.origin==0 and g.width*sx/2 or 0)-g.width/2
    local y=p.y+(p.origin==0 and g.height*sy/2 or 0)-g.height/2
    entry.surface.move(g,x,y);call(g.object,'SetLocalScale',sx,sy,1);call(g.object,'SetLocalRotation',0,0,-p.angle)
    local colorKey=table.concat(p.tone,':')..':'..p.opacity
    if colorKey~=entry.colorKey then tint(entry.paint,p.tone,p.opacity);entry.colorKey=colorKey end
    end
   end
   end
   local s=state.screen;local fade=s.fadeWhite and 255 or 0;color(layers.fade,fade,fade,fade,clamp(255-s.brightness))
   color(layers.flash,s.flash[1],s.flash[2],s.flash[3],clamp(s.flash[4]))
   local tone=s.tone;local amount=math.max(math.abs(tone[1]),math.abs(tone[2]),math.abs(tone[3]),tone[4])
   color(layers.tone,clamp(128+tone[1]),clamp(128+tone[2]),clamp(128+tone[3]),clamp(amount*.6))
   local count=s.weather.kind=='none' and 0 or math.floor(s.weather.power*4)
   for i=1,math.max(count,#weather)do
    local g=weather[i]
    if not g and i<=count then
     g=surface.group('RPG weather '..i,rect(0,0,3,s.weather.kind=='snow' and 3 or 22))
     g.flake=surface.solid(g,'RPG weather flake',rect(0,0,g.width,g.height),{215,232,245,160});weather[i]=g
    end
    if g then surface.show(g,i<=count);if i<=count then
     local height=s.weather.kind=='snow' and 3 or 22
     if g.height~=height then
      g.height=height
      call(g.object,'SetSizeDelta',g.width,height)
      call(g.flake,'SetSizeDelta',g.width,height)
      call(g.object,'SetAnchoredPosition',g.x+g.width/2-sw/2,sh/2-g.y-height/2)
     end
     local speed=s.weather.kind=='snow' and 1 or s.weather.kind=='storm' and 8 or 5
     surface.move(g,(i*137-state.clock*speed*.4)%sw,(i*79+state.clock*speed)%sh)
    end end
   end
  end
  function S.close()
   for _,e in pairs(movieFrames)do e.surface.close()end;movieFrames={};if movieSurface then movieSurface.close()end;movieRoot=nil;movieVisible=false
   for _,e in pairs(objects)do e.surface.close()end;objects={};surface.close();for _,e in ipairs(leases)do closeLease(e)end;leases={};animationViews={};activeLeases=0
  end
  return S
 end
 return M
end
