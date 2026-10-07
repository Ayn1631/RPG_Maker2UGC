-- Native troop scheduling around the existing combat authority and EventVM.
return function(deps)
 local Events,State=deps['runtime.world.events'],deps['runtime.core.state'];local Dialogue=deps['runtime.ui.dialogue'];local M={};local SAFE=9007199254740991
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function check(v,reason)if not v then fail('E_BATTLE_EVENT_SNAPSHOT',reason)end end
 local function integer(v,lo,hi)return type(v)=='number' and v==v and v%1==0 and v>=(lo or 0) and v<=(hi or SAFE)end
 local function percent(v)return type(v)=='number' and v==v and v>=0 and v<=100 end
 local function plain(v)return type(v)=='table' and getmetatable(v)==nil end
 local function copy(v,seen,depth,budget)
  local k=type(v);if k~='table'then
   if k=='number' and (v~=v or v< -SAFE or v>SAFE) or k~='nil' and k~='number' and k~='string' and k~='boolean'then fail('E_BATTLE_EVENT_SHAPE','Unsupported state value')end;return v
  end
  if not plain(v)then fail('E_BATTLE_EVENT_SHAPE','Expected plain data')end
  seen,depth,budget=seen or {},depth or 0,budget or {left=300000}
  if seen[v] or depth>64 then fail('E_BATTLE_EVENT_SHAPE','Cyclic or deeply nested data')end
  seen[v]=true;local out={};for key,value in next,v do
   if type(key)~='string' and not integer(key,-SAFE)then fail('E_BATTLE_EVENT_SHAPE','Invalid data key')end
   budget.left=budget.left-1;if budget.left<0 then fail('E_BATTLE_EVENT_SHAPE','Data budget exceeded')end
   out[key]=copy(value,seen,depth+1,budget)
  end;seen[v]=nil;return out
 end
 local function dense(v,max)
  check(plain(v),'Expected dense array');local n,high=0,0
  for k in next,v do check(integer(k,1,max or 100000),'Invalid array index');n=n+1;high=math.max(high,k)end
  check(n==high,'Sparse array');return n
 end
 local function fields(v,allowed)
  check(plain(v),'Expected snapshot object');for k in next,v do check(allowed[k],'Unknown field: '..tostring(k))end
 end
 local eligible={start=true,turn=true,turnEnd=true}
 local conditionFields={turnEnding=true,turnValid=true,turnA=true,turnB=true,enemyValid=true,enemyIndex=true,enemyHp=true,actorValid=true,actorId=true,actorHp=true,switchValid=true,switchId=true}
 function M.fromCompiledCatalog(input)
  local catalog=copy(input);fields(catalog,{kind=true,schemaVersion=true,troopPagesById=true})
  check(catalog.kind=='r2u.battle-event-catalog' and catalog.schemaVersion==1,'Unsupported battle event catalog')
  check(plain(catalog.troopPagesById),'Missing troop page catalog')
  for id,pages in next,catalog.troopPagesById do
   check(integer(id,1),'Invalid troop ID');dense(pages)
   for _,page in ipairs(pages)do
    fields(page,{programId=true,span=true,conditions=true})
    check(type(page.programId)=='string' and #page.programId>0 and #page.programId<=256,'Invalid page program ID');check(integer(page.span,0,2),'Invalid page span')
    local c=page.conditions;fields(c,conditionFields)
    for _,flag in ipairs({'turnEnding','turnValid','enemyValid','actorValid','switchValid'})do check(type(c[flag])=='boolean','Missing condition flag '..flag)end
    check(integer(c.turnA) and integer(c.turnB),'Invalid turn condition')
    check(integer(c.enemyIndex) and percent(c.enemyHp),'Invalid enemy condition')
    check(integer(c.actorId,c.actorValid and 1 or 0) and percent(c.actorHp),'Invalid actor condition')
    check(integer(c.switchId,c.switchValid and 1 or 0),'Invalid switch condition')
   end
  end
  local Factory={}
  function Factory.new(core,o)
   o=o or {};check(plain(o),'Invalid controller options')
   for _,name in ipairs({'eventPhase','isActionForced','processForcedAction','checkBattleEnd','eventBattler','eventCommand','setContext','advance','submit','view','snapshot','result'})do
    check(type(core)=='table' and type(core[name])=='function','Missing Core method '..name)
   end
   local battleId,troopId=o.battleId,o.troopId
   check(type(battleId)=='string' and #battleId>0 and #battleId<=128 and integer(troopId,1),'Invalid battle identity')
   local pages=catalog.troopPagesById[troopId];check(type(pages)=='table','Troop missing from event catalog')
   local programs=o.eventPrograms;check(plain(programs),'Missing compiled event programs')
   local pageIndex={};for i,page in ipairs(pages)do
    check(plain(programs[page.programId]) and type(programs[page.programId].instructions)=='table','Missing troop event program')
    check(not pageIndex[page.programId],'Duplicate troop page program');pageIndex[page.programId]=i
   end
   local restored;if o.state~=nil then restored=copy(o.state);check(plain(restored),'Invalid controller snapshot')end
   local vmSnapshot=restored and restored.vm
   local story=o.stateStore or State.new(vmSnapshot and vmSnapshot.state)
   for _,name in ipairs({'snapshot','getSwitch','getVariable','testCondition','setSwitches','applyVariables','setSelfSwitch'})do check(type(story)=='table' and type(story[name])=='function','Missing story method '..name)end
   local phase,turn=core.eventPhase();check(type(phase)=='string' and integer(turn),'Invalid Core event phase')
   local rt={schemaVersion=1,battleId=battleId,troopId=troopId,flags={},turnSeen=turn,queue={},taskId=false,taskProgramId=false,waitToken=false,commandSerial=0}
   for i=1,#pages do rt.flags[i]=false end
   local function common(id)return 'common:'..string.format('%.0f',id)end
   local function validCommon(id)return integer(id,1) and plain(programs[common(id)]) and type(programs[common(id)].instructions)=='table'end
   if restored then
    fields(restored,{schemaVersion=true,battleId=true,troopId=true,flags=true,turnSeen=true,queue=true,taskId=true,taskProgramId=true,waitToken=true,commandSerial=true,vm=true})
    check(restored.schemaVersion==1 and restored.battleId==battleId and restored.troopId==troopId,'Controller identity mismatch')
    check(restored.turnSeen==turn and integer(restored.commandSerial),'Invalid restored turn/counter')
    check(dense(restored.flags)==#pages,'Page flags differ from catalog')
    for i,value in ipairs(restored.flags)do check(type(value)=='boolean' and (pages[i].span~=2 or value==false),'Invalid page flag')end
    dense(restored.queue);for _,id in ipairs(restored.queue)do check(validCommon(id),'Unknown reserved common event')end
    check(restored.taskId==false or integer(restored.taskId,1),'Invalid active event task')
    check(restored.waitToken==false or type(restored.waitToken)=='string','Invalid forced wait token')
    rt=restored;rt.vm=nil
   end
   local dirty=true;local vm,rows;local busy=false;local latest
   local function syncStory()
    if not dirty then return end
    local snap=story.snapshot();local switches={};for id,value in pairs(snap.switches)do switches[#switches+1]={id=id,value=value}end
    table.sort(switches,function(a,b)return a.id<b.id end)
    core.setContext({switches=switches,variables=snap.variables});dirty=false
   end
   local adapter={snapshot=story.snapshot,getSwitch=story.getSwitch,getVariable=story.getVariable}
   function adapter.setSwitches(...)local out=story.setSwitches(...);dirty=true;return out end
   function adapter.applyVariables(...)local out=story.applyVariables(...);dirty=true;return out end
   function adapter.setSelfSwitch(_,key,value)
    if not ({A=true,B=true,C=true,D=true})[key] or type(value)~='boolean'then fail('E_EVENT_IR','Invalid battle self switch')end
   end
   function adapter.testCondition(c,context)
    if type(c)=='table' and c.kind=='self_switch'then
     if not ({A=true,B=true,C=true,D=true})[c.key] or type(c.value)~='boolean'then fail('E_EVENT_IR','Invalid battle self switch condition')end
     return c.value==false
    end;return story.testCondition(c,context)
   end
   local function collapseSound(record)
    if o.presentation and o.presentation.battleCollapse then o.presentation.battleCollapse(record.targetRef,record.targetCollapseType,record.targetEnemyId)end
    local name=record.targetRef.kind=='actor' and 'actorCollapse'
     or record.targetCollapseType==1 and 'bossCollapse1'
     or (record.targetCollapseType or 0)==0 and 'enemyCollapse'
    if name and o.audio then o.audio.systemSound(name)end
   end
   local function collect(out)
    if type(out)~='table' or type(out.ok)~='boolean' then fail('E_BATTLE_EVENT_SERVICE','Core must return an explicit outcome')end
    if out.ok==false then error(out.diagnostic or {code='E_BATTLE_EVENT_COMMAND',reason=out.reason or 'Core event command failed'},0)end
    for _,record in ipairs(out.records or {})do
     if rows then rows[#rows+1]=copy(record)end
     if record.kind=='actorSetup'then
      if o.resetActorPresentation then o.resetActorPresentation(record.actorId)end
     end
     if record.kind=='actionStart'then
      if record.visuSequence and o.presentation then
       if not o.presentation.visuAction then fail('E_BATTLE_EVENT_CAPABILITY','Visu action presentation is required')end
       o.presentation.visuAction(record)
      end
      if o.presentation and not record.visuSequence then for _,animation in ipairs(record.animations or {})do
       o.presentation.battleAnimation(animation.id,record.targets,animation.mirror)
      end end
      if record.enemyAttack and o.audio then o.audio.systemSound('enemyAttack')end
     elseif record.kind=='visuSequence' then
      if not o.presentation or not o.presentation.visuSequence then fail('E_BATTLE_EVENT_CAPABILITY','Visu sequence presentation is required')end
      o.presentation.visuSequence(record)
     elseif record.kind=='actionResult' then
      local function sound(name)if o.audio then o.audio.systemSound(name)end end
      if record.reaction=='counter'then sound('evasion')elseif record.reaction=='reflection'then sound('reflection')end
      local result=record.result or {}
      if result.used then
       if result.missed then if result.physical then sound('miss')end
       elseif result.evaded then sound(result.physical and 'evasion' or 'magicEvasion')
       else
        if result.hpAffected then
         if (result.hpDamage or 0)>0 and not result.drain then sound(record.targetRef.kind=='actor' and 'actorDamage' or 'enemyDamage')end
         if (result.hpDamage or 0)<0 then sound('recovery')end
        end
        if not record.targetDead then
         if (result.mpDamage or 0)<0 then sound('recovery')end
         if (result.tpDamage or 0)<0 then sound('recovery')end
        end
       end
       for _,id in ipairs(result.addedStates or {})do if id==1 then
        collapseSound(record)
       end end
      end
     elseif record.kind=='collapse' then collapseSound(record)
     elseif record.kind=='escape' and o.audio then o.audio.systemSound('escape')
     elseif o.presentation and record.kind=='animation' then
      o.presentation.battleAnimation(record.animationId,{record.targetRef})
     end
     if record.kind=='actionStart' and record.commonEvents then
      dense(record.commonEvents);for _,id in ipairs(record.commonEvents)do
       if not validCommon(id)then fail('E_BATTLE_EVENT_REFERENCE','Unknown action common event')end;rt.queue[#rt.queue+1]=id
      end
     end
    end
    return out
   end
   local handlers={}
   handlers.extension=function(ins,context,taskId)
    return o.extensionCommand(ins,context,taskId,function(token)return vm.resumeCommand(taskId,token)end,
     function(token)return vm.isCommandWaiting(taskId,token)end)
   end
   handlers.timer=function(ins)return o.timer.command(ins)end
   handlers.access=function(ins)return o.accessCommand(ins)end
   handlers.actor_text=function(ins)return o.actorText(ins)end
   handlers.visu_world=function(ins,context)local result=o.mapCommand(ins,context);dirty=true;return result end
   handlers.open_menu=function()return{kind='continue'}end
   handlers.scroll_map=function()return{kind='continue'}end
   for _,name in ipairs({'parallax','location_info','actor_image','vehicle_image','vehicle_bgm','map_name','tileset','battle_background','window_tone'})do handlers[name]=function(ins,context)
    local result=o.mapCommand(ins,context);dirty=true;return result
   end end
   handlers.audio=function(ins)
    if not o.audio then fail('E_BATTLE_EVENT_CAPABILITY','Audio service is required')end
    return o.audio.command(ins)
   end
   handlers.shop=function()return{kind='continue'}end
    for _,op in ipairs({'screen','picture','animation','balloon','video'})do handlers[op]=function(ins,context,taskId)
    if not o.presentation then fail('E_BATTLE_EVENT_CAPABILITY','Presentation service is required')end
     return o.presentation.command(ins,context,taskId,function(id,token)return vm.resumeCommand(id,token)end,
      function(id,token)return vm.isCommandWaiting(id,token)end,function()return vm.getMessage()==nil end)
   end end
   for _,op in ipairs({'enemy_hp','enemy_mp','enemy_tp','enemy_state','enemy_recover','enemy_appear','enemy_transform','enemy_animation','force_action','abort_battle',
     'change_equipment','gold','inventory','party_member','actor_recover','actor_exp','actor_level','actor_hp','actor_mp','actor_tp','actor_state','actor_param','actor_skill','actor_class','erase_event','transfer','battle'})do handlers[op]=function(ins)
    if ins.op=='erase_event'then return{kind='continue'}end
    if ins.op=='transfer'then fail('E_BATTLE_EVENT_UNSUPPORTED','Native battle transfer blocks; transfer in battle is not supported')end
    if ins.op=='battle'then return{kind='continue'}end
    if rt.commandSerial==SAFE then fail('E_BATTLE_EVENT_TIME','Command token counter exhausted')end
    syncStory();local out=collect(core.eventCommand(ins,story))
    if out.waitForAction and core.isActionForced() then
     rt.commandSerial=rt.commandSerial+1;rt.waitToken='action:'..string.format('%.0f',rt.commandSerial)
     return{kind='wait',token=rt.waitToken}
    end
    local messages={}
    for _,record in ipairs(out.records or {})do if record.kind=='actorGrowth'then
     local message=Dialogue.growth(o.ui,record.actorId,record.delta,o.actorName(record.actorId))
     if message then messages[#messages+1]=message end
    end end
    return{kind='continue',messages=messages}
   end end
   local conditions={visu_battle_test=function(c)return o.worldCondition(c)end,visu_literal=function(c)return o.worldCondition(c)end,extension_query=function(c)return o.worldCondition(c)end,button=function(c)return o.worldCondition(c)end,timer=function(c)return o.timer.test(c.seconds,c.comparison)end,direction=function()return false end,vehicle=function(c)return o.worldCondition(c)end};for _,kind in ipairs({'inventory','actor','gold','enemy'})do conditions[kind]=function(c)
    if kind=='actor' and c.test==1 and o.actorName then return o.actorName(c.id)==c.value end
    if type(core.eventCondition)~='function'then fail('E_BATTLE_EVENT_CAPABILITY','Core domain conditions unavailable')end
    syncStory();return core.eventCondition(c)
   end end
   local function resolveOperand(value,context)
    if value.kind=='random'then return value.minimum+core.eventRandom(value.span)end
    if value.kind=='extension_query'then return o.worldCondition(value)end
    if value.type==7 and value.id~=1 and value.id~=2 then return o.gameData(value,context)end
    return core.gameData(value)
   end
   vm=Events.new({eventPrograms=programs},{stateStore=adapter,resolveOperand=resolveOperand,commandHandlers=handlers,conditionHandlers=conditions,snapshot=vmSnapshot})
   -- rt and restored were detached independently; restore VM from the original
   -- snapshot, never from a live task or a handler-produced projection.
   if restored then
    local snap=vm.snapshot();check(dense(snap.tasks)==(rt.taskId==false and 0 or 1),'Controller task ownership differs')
    if rt.taskId==false then check(rt.taskProgramId==false and rt.waitToken==false,'Missing task with pending ownership')
    else
     local task=vm.getTask(rt.taskId);check(task~=nil,'Missing controller task')
     local root=#task.stack>0 and task.stack[1].programId or task.programId
     check(root==rt.taskProgramId and (pageIndex[root] or type(root)=='string' and root:match('^common:[1-9]%d*$')),'Foreign controller task')
     local index=pageIndex[root];check(not index or pages[index].span==2 or rt.flags[index],'Running page was not flagged')
     check(task.status=='RUNNING' or task.status=='WAITING' or task.status=='ERROR','Unexpected controller task status')
     if task.wait and task.wait.kind=='command'then
      local previous=programs[task.programId].instructions[task.pc-1]
      check(type(previous)=='table' and previous.op=='force_action','Forced wait does not follow force_action')
      check(rt.commandSerial>0 and rt.waitToken=='action:'..string.format('%.0f',rt.commandSerial) and task.wait.token==rt.waitToken,'Forced wait ownership differs')
     else
      check(rt.waitToken==false,'Pending token without command wait')
      if task.wait and task.wait.kind=='frames'then
       local previous=programs[task.programId].instructions[task.pc-1]
       check(task.executed>0 and type(previous)=='table' and previous.op=='wait' and integer(previous.frames,1),'Frame wait does not follow a positive wait')
      end
      check(not task.wait or task.wait.kind~='battle','Nested battle cannot retain a battle wait')
     end
    end
    check(phase~='battleEnd' or rt.taskId==false and #rt.queue==0,'Ended battle retains event work')
   end
   local function syncTurn()
    local _,current=core.eventPhase()
    if current~=rt.turnSeen then for i,page in ipairs(pages)do if page.span==1 then rt.flags[i]=false end end;rt.turnSeen=current end
   end
   local function clearTerminal()
    local current=core.eventPhase();if current~='battleEnd'then return end
    rt.queue={};if rt.taskId~=false then vm.cancel(rt.taskId);vm.release(rt.taskId)end
    rt.taskId,rt.taskProgramId,rt.waitToken=false,false,false
   end
   local function matches(c,p,n)
    if not (c.turnEnding or c.turnValid or c.enemyValid or c.actorValid or c.switchValid)then return false end
    if c.turnEnding and p~='turnEnd'then return false end
    if c.turnValid and (c.turnB==0 and n~=c.turnA or c.turnB>0 and (n<1 or n<c.turnA or n%c.turnB~=c.turnA%c.turnB))then return false end
    for _,side in ipairs({'enemy','actor'})do if c[side..'Valid']then
     local b=core.eventBattler(side,c[side=='enemy' and 'enemyIndex' or 'actorId'])
     if not b or not (b.hp/b.mhp*100<=c[side..'Hp'])then return false end
    end end
    if c.switchValid and not story.getSwitch(c.switchId)then return false end;return true
   end
   local function start(id,index)
    rt.taskId=vm.start(id);rt.taskProgramId=id
    if index and pages[index].span<=1 then rt.flags[index]=true end
   end
   local tpb=type(core.isTpb)=='function' and core.isTpb()
   local function visit(frames,timeActive)
    if vm.getMessage()then return false end
    if o.presentation then
     local visu=core.isVisuSequence and core.isVisuSequence()
     if visu then
      if not o.presentation.isVisuBusy then fail('E_BATTLE_EVENT_CAPABILITY','Explicit Visu presentation waits are required')end
      if o.presentation.isVisuBusy()then return false end
     elseif o.presentation.isBattleBusy()then return false end
    end
    syncTurn();local p,n=core.eventPhase()
    if eligible[p]then
     if core.isActionForced()then syncStory();collect(core.processForcedAction());syncTurn();clearTerminal();return true end
     if rt.waitToken~=false then
      check(vm.resumeCommand(rt.taskId,rt.waitToken),'Cannot resume forced event wait');rt.waitToken=false
     end
     vm.tick(frames);syncStory()
     if vm.getMessage()then return true end
     if rt.taskId~=false then
      local task=vm.getTask(rt.taskId)
      if task.status=='ERROR'then error(task.diagnostic,0)end
      if task.status=='RUNNING' or task.status=='WAITING'then return true end
      vm.release(rt.taskId);rt.taskId,rt.taskProgramId=false,false
     end
     local ending=core.checkBattleEnd()
     check(type(ending)=='table' and type(ending.ended)=='boolean','Invalid Core end check')
     collect({ok=true,records=ending.records});if ending.ended then clearTerminal();return true end
     if #rt.queue>0 then start(common(table.remove(rt.queue,1)));return true end
     local current,currentTurn=core.eventPhase()
     for i,page in ipairs(pages)do if not rt.flags[i] and matches(page.conditions,current,currentTurn)then start(page.programId,i);return true end end
     -- Native abort changes phase during the interpreter update. Its tail ran
     -- this visit; checkAbort completes it on the next battle update.
     if current=='aborting'then return true end
    elseif p=='input' or p=='battleEnd'then clearTerminal();return false end
    syncStory();collect(core.advance(1,tpb and {frames=frames,timeActive=timeActive} or nil));syncTurn();clearTerminal();return true
   end
   local W={result=core.result,setContext=core.setContext,gameData=core.gameData,extensionOperations=core.extensionOperations,isTpb=function()return tpb end}
   function W.view()local v=core.view();if latest then v.records=copy(latest)end;return v end
   function W.snapshot()syncTurn();local out=core.snapshot();out.eventRuntime=copy(rt);out.eventRuntime.vm=vm.snapshot();return out end
   local function messageToken(m)return'battle-event:'..#battleId..':'..battleId..':task:'..string.format('%.0f',m.taskId)..':message:'..string.format('%.0f',m.token)end
   function W.getMessage()local m=vm.getMessage();if m then m.token=messageToken(m);m.battleId=battleId end;return m end
   function W.respond(id,token,answer)
    if busy then return false end;local m=vm.getMessage()
    if not m or m.taskId~=id or messageToken(m)~=token then return false end
    return vm.respond(id,m.token,answer)
   end
   local function perform(fn,appendRecords)
    if busy then fail('E_BATTLE_EVENT_REENTRY','Event controller reentry')end
    if appendRecords==false then latest=nil end
    busy=true;rows={};local ok,out=pcall(fn);local emitted=rows;rows=nil;busy=false
    if #emitted>0 then
     if appendRecords and latest then for _,row in ipairs(emitted)do latest[#latest+1]=copy(row)end
     else latest=copy(emitted)end
    end
    if not ok then return{ok=false,records=emitted,diagnostic=type(out)=='table' and copy(out) or {code='E_BATTLE_EVENT_RUNTIME',reason=tostring(out)}}end
    return out or {ok=true,records=emitted}
   end
   function W.advance(budget,frames,timeActive,appendRecords)
    budget=budget==nil and 1 or budget;frames=frames==nil and 1 or frames
    if not integer(budget,0,1000) or not integer(frames)then fail('E_BATTLE_EVENT_NUMBER','Invalid progression budget or logical frames')end
    if appendRecords~=nil and type(appendRecords)~='boolean'then fail('E_BATTLE_EVENT_NUMBER','Record accumulation must be boolean')end
    return perform(function()
     if tpb then
      for frame=1,math.max(1,frames)do
       for action=1,budget do
        if not visit(frame<=frames and action==1 and 1 or 0,timeActive)then return end
        if vm.getMessage()then return end
       end
      end
      return
     end
     local consumed=false
     for _=1,budget do
      local p=core.eventPhase();local f=not consumed and eligible[p] and not vm.getMessage() and not core.isActionForced() and frames or 0
      if f~=0 then consumed=true end
      if not visit(f)then break end
      if vm.getMessage()then break end
     end
    end,appendRecords)
   end
   function W.step(budget,frames,timeActive)local out=W.advance(budget,frames,timeActive);out.view=W.view();out.result=W.result();return out end
   function W.abort()return perform(function()
    if rt.taskId~=false then vm.cancel(rt.taskId);vm.release(rt.taskId)end
    rt.taskId,rt.taskProgramId,rt.waitToken=false,false,false;rt.queue={}
    return collect(core.abort())
   end)end
   function W.submit(request)
    if vm.getMessage()then return{ok=false,reason='Battle event message is active',records={},view=W.view()}end
    return perform(function()
     syncStory();local out=core.submit(request)
     if type(out)=='table' and out.ok==false then return out end
     collect(out);syncTurn();clearTerminal();return out
    end)
   end
   return W
  end
  return Factory
 end
 return M
end
