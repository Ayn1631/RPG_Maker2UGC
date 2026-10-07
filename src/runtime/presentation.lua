-- Frame-based event presentation. Static assets have already been resolved offline.
return function()
 local M={}
 local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
 local function fail(reason)error({severity='error',code='E_PRESENTATION',reason=reason},0)end
 local function easing(t,kind)if kind==1 then return t*t elseif kind==2 then return 1-(1-t)^2 elseif kind==3 then return t<.5 and 2*t*t or 1-2*(1-t)^2 end;return t end
 function M.new(resources,audio)
  local pictures,animations,waits={},{},{};local clock,sequence,revision=0,0,0;local story;local battle=false;local closed=false
  local screen={brightness=255,fadeWhite=false,tone={0,0,0,0},flash={0,0,0,0},shake=0,weather={kind='none',power=0}}
  local tweens={};local S={}
  local videos={}
  local collapses={}
  local visuEvents,visuActions,visuActionRefs={},{},{}
  local visuSerial,visuGeneration=0,0
  local visuWaitUntil=0
  local function animationSounds(a,from,to)
   if not audio or a.mute then return end
   for _,timing in ipairs(a.asset.soundTimings or {})do if timing.frame>from and timing.frame<=to then
    audio.command({channel='se',action='play',cue=timing.se})
   end end
  end
  local function videoHead()
   for i=#videos,1,-1 do local v=videos[i];if v.alive and not v.alive(v.taskId,v.token)then table.remove(videos,i);revision=revision+1 end end
   local v=videos[1]
   if v and not v.started and (not v.canStart or v.canStart())then v.started=true;revision=revision+1 end
   return v
  end
  function S.isVideoBusy()return videoHead()~=nil end
  local function tween(object,target,duration,kind)
   if duration<=0 then tweens[object]=nil;for k,v in pairs(target)do object[k]=v end;return end
   local from={};for k in pairs(target)do from[k]=object[k] or 0 end
   tweens[object]={object=object,from=from,target=target,elapsed=0,duration=duration,easing=kind or 0}
  end
  local function wait(ins,taskId,resume)
   if not ins.wait or (ins.duration or 0)<=0 then return {kind='continue'}end
   sequence=sequence+1;local token='presentation:'..sequence
   waits[#waits+1]={deadline=clock+ins.duration,taskId=taskId,token=token,resume=resume}
   return {kind='wait',token=token}
  end
  function S.bindStory(value)story=value end
  function S.setBattle(value)
   local nextBattle=value==true
   if nextBattle and not battle then visuGeneration=visuGeneration+1;visuSerial=0 end
   if battle and not nextBattle then
    for i=#animations,1,-1 do if animations[i].battle then table.remove(animations,i) end end
    collapses={};visuEvents={};visuActions={};visuActionRefs={};visuWaitUntil=0
   end
   battle=nextBattle
  end
  function S.battleAnimation(animationId,targets,mirror)
   if closed or animationId==0 then return end
   local asset=resources and resources.animations and resources.animations[string.format('%.0f',animationId)]
   if not asset then fail('Missing animation resource: '..tostring(animationId))end
   local seen={}
   for _,target in ipairs(targets or {})do
    local key=target.kind..':'..tostring(target.id or target.troopSlot)
    if not seen[key]then
     seen[key]=true;sequence=sequence+1
     animations[#animations+1]={id=sequence,kind='animation',asset=asset,animationId=animationId,targetRef=copy(target),mirror=mirror==true,elapsed=0,duration=asset.durationFrames or 60,battle=true}
     animationSounds(animations[#animations],-1,0)
    end
   end
   revision=revision+1
  end
  function S.visuAction(record)
   visuWaitUntil=0
   local key=record.subjectRef.kind..':'..tostring(record.subjectRef.id or record.subjectRef.troopSlot)
   visuActions[key]=copy(record.animations or {});visuActionRefs[key]=copy(record.actionRef)
  end
  -- Only presentation data crosses this boundary. Mechanics have already
  -- committed in battle.lua and must never be replayed by the renderer.
  function S.visuSequence(record)
   if closed then return end
   local cmd,a=record.command,record.args or {}
   local function nativeDuration(value)
    local n=tonumber(value);if not n or n%1~=0 or n<0 or n>360000 then fail('Invalid native Visu screen duration')end;return n
   end
   if cmd=='screenTone' then S.command({op='screen',action='tint',tone=a[1],duration=nativeDuration(a[2])},{})
   elseif cmd=='screenFlash' then S.command({op='screen',action='flash',color=a[1],duration=nativeDuration(a[2])},{})
   elseif cmd=='screenShake' then S.command({op='screen',action='shake',power=a[1],speed=a[2],duration=nativeDuration(a[3])},{})
   elseif cmd=='sound' then
    if not audio or not a[1] or not a[1].index then fail('Visu sequence SE requires compiled audio cue')end
    audio.command({channel='se',action='play',cue=a[1]})
   elseif cmd=='ActSeq_Animation_ShowAnimation' then S.battleAnimation(a.AnimationID,record.targets,a.Mirror)
   elseif cmd=='ActSeq_Animation_ActionAnimation' then
    local key=record.subjectRef.kind..':'..tostring(record.subjectRef.id or record.subjectRef.troopSlot)
    if not visuActions[key]then fail('Visu action animation has no actionStart record')end
    for _,v in ipairs(visuActions[key])do S.battleAnimation(v.id,record.targets,a.Mirror or v.mirror)end
   elseif cmd=='ActSeq_Animation_PlayAtCoordinate' then
    local asset=resources and resources.animations and resources.animations[string.format('%.0f',a.AnimationID)]
    if not asset then fail('Missing animation resource: '..tostring(a.AnimationID))end
    sequence=sequence+1;animations[#animations+1]={id=sequence,kind='animation',asset=asset,animationId=a.AnimationID,
     point={x=copy(a.pointX),y=copy(a.pointY)},subjectRef=copy(record.subjectRef),targetRef=copy(record.allTargets[1]),mirror=a.Mirror==true,mute=a.Mute==true,elapsed=0,duration=asset.durationFrames or 60,battle=true}
    animationSounds(animations[#animations],-1,0)
   elseif cmd=='wait' or cmd=='ActSeq_Animation_WaitForAnimation' or cmd:match('^ActSeq_Mechanics_') or cmd:match('^ActSeq_Element_') then
    -- Gameplay/wait timing belongs to the battle coordinator.
   else
    local supported={Movement=true,Motion=true,Impact=true,Set=true,BattleLog=true,Projectile=true}
    if not supported[cmd:match('^ActSeq_([^_]+)_')]then fail('Unsupported Visu presentation command '..tostring(cmd))end
    visuSerial=visuSerial+1;local row=copy(record);row.id=visuSerial;row.clock=clock
    row.actionRef=copy(visuActionRefs[record.subjectRef.kind..':'..tostring(record.subjectRef.id or record.subjectRef.troopSlot)])
    if cmd=='ActSeq_Projectile_Animation'then
     row.asset=resources and resources.animations and resources.animations[string.format('%.0f',a.AnimationID)]
     if not row.asset then fail('Missing projectile animation resource: '..tostring(a.AnimationID))end
    end
    visuEvents[#visuEvents+1]=row
    -- A bounded journal allows repeated snapshots without consuming events.
    -- A renderer that falls behind this window diagnoses a gap explicitly.
    if #visuEvents>512 then table.remove(visuEvents,1)end
   end
   if a.WaitForAnimation==true or a.WaitComplete==true or cmd=='ActSeq_Animation_WaitForAnimation' or a.WaitForEffect==true then
    for _,animation in ipairs(animations)do if animation.battle then visuWaitUntil=math.max(visuWaitUntil,clock+animation.duration-animation.elapsed)end end
   end
   if (cmd=='screenTone'or cmd=='screenFlash')and a[3]==true then visuWaitUntil=math.max(visuWaitUntil,clock+nativeDuration(a[2]))
   elseif cmd=='screenShake'and a[4]==true then visuWaitUntil=math.max(visuWaitUntil,clock+nativeDuration(a[3]))end
   if cmd=='ActSeq_Set_SetupAction'and a.CastAnimation and a.WaitForAnimation then visuWaitUntil=math.max(visuWaitUntil,clock+24)end
   if cmd=='ActSeq_Set_FinishAction'then
    if a.WaitForMovement then visuWaitUntil=math.max(visuWaitUntil,clock+12)end
    if a.WaitForEffect then for _,c in pairs(collapses)do visuWaitUntil=math.max(visuWaitUntil,clock+c.duration-c.elapsed)end end
   end
   revision=revision+1
  end
  function S.isVisuBusy()return clock<visuWaitUntil or S.isVideoBusy()end
  function S.isBattleBusy()
   if S.isVideoBusy()then return true end
   for _,a in ipairs(animations)do if a.battle then return true end end
   if next(collapses)then return true end
   return false
  end
  function S.battleCollapse(target,kind,enemyId)
   if closed or not battle or target.kind~='enemy'then return end
   local asset=resources and resources.enemies and resources.enemies[string.format('%.0f',enemyId or 0)]
   if kind==1 and not asset then fail('Boss collapse requires the bound enemy asset height')end
   local duration=kind==1 and asset.height or kind==2 and 16 or 32
   if type(duration)~='number' or duration%1~=0 or duration<1 or duration>32768 then fail('Invalid collapse duration')end
   collapses[string.format('%.0f',target.troopSlot)]={targetRef=copy(target),kind=kind or 0,elapsed=0,duration=duration}
   revision=revision+1
  end
  function S.command(ins,context,taskId,resume,isAlive,canStartVideo)
   if closed then return {kind='continue'}end
   revision=revision+1;local duration=ins.duration or 0
   if ins.op=='video'then
    local asset=ins.asset
    if type(asset)~='table' or asset.mode~='template-sequence' or not asset.frames or #asset.frames==0 then fail('Video requires a compiled template-sequence replacement')end
    if #videos>=64 then fail('Too many queued video replacements')end
    sequence=sequence+1;local token='video:'..sequence
    videos[#videos+1]={id=sequence,name=ins.name,asset=asset,elapsed=0,duration=asset.durationFrames,taskId=taskId,token=token,resume=resume,alive=isAlive,canStart=canStartVideo,started=false}
    return{kind='wait',token=token}
   elseif ins.op=='picture'then
    local id=ins.id+(battle and 100 or 0);local p=pictures[id]
    if ins.action=='erase'then if p then tweens[p]=nil;tweens[p.tone]=nil end;pictures[id]=nil
    elseif ins.action=='show' or ins.action=='move'then
     local x,y=ins.x,ins.y
     if ins.mode==1 then if not story then fail('Picture variable coordinates need story state')end;x,y=story.getVariable(x),story.getVariable(y)end
     if ins.action=='show'then
      if not ins.asset then fail('Missing picture resource: '..tostring(ins.name))end
      if p then tweens[p]=nil;tweens[p.tone]=nil end
      p={id=ins.id,name=ins.name,asset=ins.asset,origin=ins.origin,x=x,y=y,scaleX=ins.scaleX,scaleY=ins.scaleY,
       opacity=ins.opacity,blend=ins.blend,angle=0,rotationSpeed=0,tone={0,0,0,0}}
      pictures[id]=p
     elseif p then
      p.origin,p.blend=ins.origin,ins.blend
      tween(p,{x=x,y=y,scaleX=ins.scaleX,scaleY=ins.scaleY,opacity=ins.opacity},duration,ins.easing)
     end
    elseif p and ins.action=='rotate'then p.rotationSpeed=ins.speed
    elseif p and ins.action=='tint'then tween(p.tone,ins.tone,duration)end
   elseif ins.op=='screen'then
    if ins.action=='fade'then screen.fadeWhite=ins.white==true;tween(screen,{brightness=ins.brightness},duration)
    elseif ins.action=='tint'then tween(screen.tone,ins.tone,duration)
    elseif ins.action=='flash'then screen.flash=copy(ins.color);tween(screen.flash,{[4]=0},duration)
    elseif ins.action=='shake'then
     local mode=ins.shakeMode or screen.shakeMode or 'original';if not ({original=true,horizontal=true,vertical=true,random=true})[mode]then fail('Unknown screen shake mode '..tostring(mode))end
     screen.shakeMode=mode;screen.shakePower,screen.shakeSpeed,screen.shakeDuration,screen.shakeDirection=ins.power,ins.speed,duration,1
    elseif ins.action=='weather'then
     if not battle then screen.weather.kind=ins.kind;tween(screen.weather,{power=ins.power},duration)end
    end
   elseif ins.op=='animation' or ins.op=='balloon'then
    local entity=ins.characterId==0 and context.eventId or ins.characterId
    local asset=ins.asset;if not asset then fail('Missing '..ins.op..' resource: '..tostring(ins.animationId or ins.balloonId))end;duration=asset.durationFrames
    sequence=sequence+1;animations[#animations+1]={id=sequence,kind=ins.op,asset=asset,animationId=ins.animationId,balloonId=ins.balloonId,
     characterId=entity,mapId=context.mapId,elapsed=0,duration=duration,battle=battle,enemyIndex=ins.enemyIndex,allEnemies=ins.allEnemies}
    animationSounds(animations[#animations],-1,0)
    local command={wait=ins.wait,duration=duration};return wait(command,taskId,resume)
   else fail('Unknown presentation operation')end
   return wait(ins,taskId,resume)
  end
  function S.tick(frames)
   if closed or frames==0 then return end
   if type(frames)~='number' or frames%1~=0 or frames<0 then fail('Presentation frames must be nonnegative integers')end
   clock=clock+frames;local changed=false
   local remaining=frames
   while remaining>0 do
    local video=videoHead();if not video or not video.started then break end
    local used=math.min(remaining,video.duration-video.elapsed);video.elapsed=video.elapsed+used;remaining=remaining-used;changed=true
    if video.elapsed>=video.duration then table.remove(videos,1);video.resume(video.taskId,video.token)else break end
   end
   for object,t in pairs(tweens)do
    t.elapsed=math.min(t.duration,t.elapsed+frames);local ratio=easing(t.elapsed/t.duration,t.easing)
    for key,value in pairs(t.target)do object[key]=t.from[key]+(value-t.from[key])*ratio end
    changed=true;if t.elapsed==t.duration then tweens[object]=nil end
   end
   for _,p in pairs(pictures)do if p.rotationSpeed~=0 then p.angle=(p.angle+p.rotationSpeed/2*frames)%360;changed=true end end
   if screen.shakeMode and screen.shakeMode~='original'then
    if (screen.shakeDuration or 0)>0 then
     screen.shakeDuration=math.max(0,screen.shakeDuration-frames)
     -- Presentation-only deterministic jitter keeps combat RNG untouched.
     local phase=math.floor(clock*screen.shakeSpeed/5)
     local function jitter(seed)return ((phase*seed+17)%101/50-1)*screen.shakePower*2 end
     screen.shakeX=screen.shakeMode~='vertical'and jitter(37)or 0
     screen.shakeY=screen.shakeMode~='horizontal'and jitter(61)or 0
     if screen.shakeDuration==0 then screen.shakeX,screen.shakeY=0,0 end
     screen.shake=screen.shakeX;changed=true
    end
   elseif (screen.shakeDuration or 0)>0 or screen.shake~=0 then
    for _=1,frames do
     if (screen.shakeDuration or 0)>0 or screen.shake~=0 then
      local delta=screen.shakePower*screen.shakeSpeed*screen.shakeDirection/10
      if screen.shakeDuration<=1 and screen.shake*(screen.shake+delta)<0 then screen.shake=0 else screen.shake=screen.shake+delta end
      if screen.shake>screen.shakePower*2 then screen.shakeDirection=-1 elseif screen.shake< -screen.shakePower*2 then screen.shakeDirection=1 end
      screen.shakeDuration=math.max(0,screen.shakeDuration-1)
     end
    end;screen.shakeX,screen.shakeY=screen.shake,0;changed=true
   end
   for i=#animations,1,-1 do local a=animations[i];animationSounds(a,a.elapsed,math.min(a.duration,a.elapsed+frames));a.elapsed=a.elapsed+frames;if a.elapsed>=a.duration then table.remove(animations,i)end;changed=true end
   for key,c in pairs(collapses)do
    local elapsed=math.min(c.duration,c.elapsed+frames)
    if c.kind==1 and audio then
     -- Native decrements before testing remaining % 20 == 19. Enumerate only
     -- sound boundaries so batched ticks preserve cadence without frame loops.
     local first=c.duration%20+1
     local at=first+math.max(0,math.floor((c.elapsed-first)/20)+1)*20
     while at<=elapsed do audio.systemSound('bossCollapse2');at=at+20 end
    end
    c.elapsed=elapsed;changed=true;if elapsed==c.duration then collapses[key]=nil end
   end
   if screen.weather.kind~='none' and screen.weather.power>0 then changed=true end
   for i=#waits,1,-1 do local w=waits[i];if clock>=w.deadline then table.remove(waits,i);w.resume(w.taskId,w.token)end end
   if changed then revision=revision+1 end
  end
  function S.snapshot()
   local active={};for id,p in pairs(pictures)do if (id>100)==battle then active[#active+1]=copy(p)end end
   table.sort(active,function(a,b)return a.id<b.id end)
   local activeAnimations={};for _,a in ipairs(animations)do if a.battle==battle then activeAnimations[#activeAnimations+1]=copy(a)end end
   local v=videoHead();local video
   if v and v.started then local a=v.asset;video={id=v.id,name=v.name,width=a.width,height=a.height,elapsed=v.elapsed,duration=v.duration,
    templateId=a.frames[math.min(#a.frames,math.floor(v.elapsed/a.frameTicks)+1)]}end
   return {revision=revision,clock=clock,screen=copy(screen),pictures=active,animations=activeAnimations,collapses=copy(collapses),video=video,visu=battle and {generation=visuGeneration,events=copy(visuEvents)}or nil}
  end
  function S.close()closed=true;pictures,animations,waits,tweens,videos,collapses,visuEvents,visuActions,visuActionRefs={},{},{},{},{},{},{},{},{}end
  return S
 end
 return M
end
