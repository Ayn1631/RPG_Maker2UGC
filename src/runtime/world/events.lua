-- Cooperative, bounded scheduler over compiler IR. No platform, IO or coroutine.
return function(deps)
  local stateModule,dialogueModule=deps["runtime.core.state"],deps["runtime.ui.dialogue"]
  local M={}
  local limit=9007199254740991
  local function integer(v) return type(v)=="number" and v==v and v>=-limit and v<=limit and v%1==0 end
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function copy(v,seen)
    if type(v)~="table" then return v end
    seen=seen or {}; if seen[v] then return seen[v] end
    local out={}; seen[v]=out; for key,value in pairs(v) do out[key]=copy(value,seen) end; return out
  end
  local function active(task) return task and (task.status=="RUNNING" or task.status=="WAITING") end
  -- Snapshots contain mutable interpreter state only, never program bytecode or
  -- services. Validate detached input before rebuilding the live task ring.
  local function snapshotCopy(value,seen,depth,budget)
    local kind=type(value)
    if kind~='table' then
      if kind=='number' and (value~=value or value< -limit or value>limit) then fail('E_EVENT_SNAPSHOT','Invalid snapshot number') end
      if kind~='nil' and kind~='number' and kind~='string' and kind~='boolean' then fail('E_EVENT_SNAPSHOT','Executable snapshot value') end
      return value
    end
    if getmetatable(value)~=nil then fail('E_EVENT_SNAPSHOT','Snapshot must contain plain tables') end
    seen,depth,budget=seen or {},depth or 0,budget or {left=200000}
    if seen[value] or depth>64 then fail('E_EVENT_SNAPSHOT','Cyclic or deeply nested snapshot') end
    seen[value]=true;local out={}
    for k,v in next,value do
      if type(k)~='string' and not integer(k) then fail('E_EVENT_SNAPSHOT','Invalid snapshot key') end
      budget.left=budget.left-1;if budget.left<0 then fail('E_EVENT_SNAPSHOT','Snapshot exceeds data budget') end
      out[k]=snapshotCopy(v,seen,depth+1,budget)
    end
    seen[value]=nil;return out
  end
  local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
  end
  local actorOps={actor_recover=true,actor_exp=true,actor_level=true,actor_hp=true,actor_mp=true,actor_tp=true,actor_state=true,actor_param=true,actor_skill=true,actor_class=true}
  local actorFields={op=true,source=true,actorMode=true,actorSelector=true}
  local growthFields={op=true,source=true,actorMode=true,actorSelector=true,operation=true,operand=true,showLevelUp=true}
  local function actorInstruction(instruction)
    local op=instruction.op;local growth=op=='actor_exp' or op=='actor_level'
    local arithmetic=growth or op=='actor_hp' or op=='actor_mp' or op=='actor_tp' or op=='actor_param'
    local allowed={};for k,v in pairs(growth and growthFields or actorFields)do allowed[k]=v end
    if arithmetic then allowed.operation=true;allowed.operand=true end
    if op=='actor_hp'then allowed.allowDeath=true;if type(instruction.allowDeath)~='boolean'then fail('E_EVENT_IR','Invalid allowDeath')end
    elseif op=='actor_param'then allowed.paramId=true;if not integer(instruction.paramId) or instruction.paramId<0 or instruction.paramId>7 then fail('E_EVENT_IR','Invalid parameter ID')end
    elseif op=='actor_state' or op=='actor_skill'then
      local field=op=='actor_state' and 'stateId' or 'skillId';allowed[field]=true;allowed.operation=true
      if not integer(instruction[field]) or instruction[field]<1 or (instruction.operation~=0 and instruction.operation~=1)then fail('E_EVENT_IR','Invalid actor state/skill')end
    elseif op=='actor_class'then
      allowed.classId=true;allowed.keepExp=true
      if not integer(instruction.classId) or instruction.classId<1 or type(instruction.keepExp)~='boolean'then fail('E_EVENT_IR','Invalid actor class')end
    end
    for key in pairs(instruction) do if not allowed[key] then fail("E_EVENT_IR","Unknown actor instruction field") end end
    if instruction.actorMode~=0 and instruction.actorMode~=1 then fail("E_EVENT_IR","Invalid actor selector mode") end
    if not integer(instruction.actorSelector) or instruction.actorSelector<(instruction.actorMode==0 and 0 or 1) then
      fail("E_EVENT_IR","Invalid actor selector")
    end
    if arithmetic then
      if instruction.operation~=0 and instruction.operation~=1 then fail("E_EVENT_IR","Invalid actor growth operation") end
      if growth and type(instruction.showLevelUp)~="boolean" then fail("E_EVENT_IR","Invalid show level up option") end
      local operand=instruction.operand
      if type(operand)~="table" then fail("E_EVENT_IR","Invalid actor growth operand") end
      for key in pairs(operand) do if key~="kind" and key~="value" then fail("E_EVENT_IR","Unknown actor operand field") end end
      if (operand.kind~="constant" and operand.kind~="variable") or not integer(operand.value)
        or (operand.kind=="variable" and operand.value<1) then fail("E_EVENT_IR","Invalid actor growth operand") end
    end
  end
  function M.new(data,options)
    if type(data)~="table" or type(data.eventPrograms)~="table" then fail("E_EVENT_PACKAGE","Missing event programs") end
    if options~=nil and type(options)~="table" then fail("E_EVENT_OPTIONS","options must be a table") end
    options=options or {}
    if options.shouldYield~=nil and type(options.shouldYield)~='function'then fail('E_EVENT_OPTIONS','shouldYield must be a function')end
    local function option(name,default,maximum)
      local value=options[name]; if value==nil then value=default end
      if not integer(value) or value<1 or value>maximum then fail("E_EVENT_OPTIONS","Invalid "..name) end
      return value
    end
    local perTaskBudget,frameBudget,maxCallDepth=option("perTaskBudget",64,1000000),option("frameBudget",512,1000000),option("maxCallDepth",32,1024)
    local restored
    if options.snapshot~=nil then restored=snapshotCopy(options.snapshot) end
    if options.snapshot~=nil and options.state~=nil then fail('E_EVENT_OPTIONS','Use state or a snapshot, not both') end
    if options.stateStore~=nil and options.state~=nil then fail("E_EVENT_OPTIONS","Use stateStore or state, not both") end
    local state
    if restored~=nil and type(restored)~='table'then fail('E_EVENT_SNAPSHOT','Snapshot must be a table')end
    if restored and type(restored.state)~='table'then fail('E_EVENT_SNAPSHOT','Snapshot needs a story state')end
    if options.stateStore~=nil then state=options.stateStore else state=stateModule.new(restored and restored.state or options.state) end
    for _,method in ipairs({"snapshot","testCondition","setSwitches","applyVariables","setSelfSwitch"}) do
      if type(state)~="table" or type(state[method])~="function" then fail("E_EVENT_OPTIONS","Invalid shared state store") end
    end
    local dialogue=dialogueModule.new()
    -- Growth notices do not suspend the issuing instruction. The next message
    -- waits for this channel, while switches, rewards and other commands continue.
    local notices,noticeDialogue={},dialogueModule.new()
    local function openNotice()
      if #notices>0 and not noticeDialogue.busy()then noticeDialogue.open(notices[1].taskId,notices[1].message)end
    end
    local function clearNotices(id)
      for i=#notices,1,-1 do if notices[i].taskId==id then table.remove(notices,i)end end
      noticeDialogue.release(id);openNotice()
    end
    local function addNotices(id,messages)
      if messages==nil then return end
      if type(messages)~='table' or #notices+#messages>10000 then fail('E_EVENT_SERVICE','Invalid notification queue')end
      local prepared={}
      for _,message in ipairs(messages)do
        local check=dialogueModule.new();check.open(id,message)
        if message.choices or message.numberInput or message.itemChoice or message.scroll then fail('E_EVENT_SERVICE','Notification must contain plain message text')end
        prepared[#prepared+1]={taskId=id,message=copy(message)}
      end
      for _,entry in ipairs(prepared)do notices[#notices+1]=entry end;openNotice()
    end
    local handlers,conditions=options.commandHandlers,options.conditionHandlers
    if handlers==nil then handlers={} end
    if conditions==nil then conditions={} end
    if type(handlers)~="table" or type(conditions)~="table" then fail("E_EVENT_OPTIONS","Event handlers must be tables") end
    for _,registry in ipairs({handlers,conditions}) do
      for key,handler in pairs(registry) do
        if type(key)~="string" or type(handler)~="function" then fail("E_EVENT_OPTIONS","Event handler requires a string name and function") end
      end
    end
    for _,name in ipairs({"nop","return","jump","branch","switches","variables","self_switch","wait","call","dialogue"}) do
      if handlers[name] then fail("E_EVENT_OPTIONS","Cannot replace built-in command: "..name) end
    end
    for _,name in ipairs({"switch","variable","self_switch"}) do
      if conditions[name] then fail("E_EVENT_OPTIONS","Cannot replace built-in condition: "..name) end
    end
    local programs,tasks,clock,lastTaskId=data.eventPrograms,{},0,0
    -- Final results remain queryable until explicit release. The separate ring
    -- contains only live tasks, so retained history never enters tick scans.
    local running,firstActive,nextActive,activeCount={},nil,nil,0
    local S={}
    local function enqueue(id)
      if activeCount==0 then
        running[id]={previous=id,next=id}; firstActive=id; nextActive=id
      else
        local tail=running[firstActive].previous
        running[id]={previous=tail,next=firstActive}
        running[tail].next=id; running[firstActive].previous=id
      end
      activeCount=activeCount+1
    end
    local function retire(id)
      local node=running[id]; if not node then return end
      if activeCount==1 then firstActive=nil; nextActive=nil
      else
        running[node.previous].next=node.next; running[node.next].previous=node.previous
        if firstActive==id then firstActive=node.next end
        if nextActive==id then nextActive=node.next end
      end
      running[id]=nil; activeCount=activeCount-1
    end
    local function program(id)
      local value=type(id)=="string" and programs[id] or nil
      if type(value)~="table" or type(value.instructions)~="table" then fail("E_EVENT_REFERENCE","Unknown or invalid program: "..tostring(id)) end
      return value
    end
    local function target(value,instructions)
      if not integer(value) or value<1 or value>#instructions then fail("E_EVENT_TARGET","Invalid instruction target") end
      return value
    end
    local function finish(task,status)
      task.status=status; task.wait=nil; dialogue.release(task.id); retire(task.id)
      if status~='DONE'then clearNotices(task.id)end
    end
    local function taskError(task,err,source)
      local diagnostic
      if type(err)=="table" and type(err.code)=="string" and type(err.reason)=="string" then diagnostic=copy(err)
      else diagnostic={severity="error",code="E_EVENT_RUNTIME",reason="Event instruction failed: "..tostring(err)} end
      diagnostic.severity="error"
      if type(source)=="table" then
        diagnostic.source=copy(source)
        for _,key in ipairs({"file","jsonPath","commandIndex"}) do
          if source[key]~=nil then diagnostic[key]=source[key] end
        end
      end
      task.diagnostic=diagnostic; finish(task,"ERROR")
    end
    function S.start(id)
      local entry=program(id)
      if lastTaskId==limit then fail("E_EVENT_TIME","Task ID exhausted") end
      lastTaskId=lastTaskId+1
      local task={id=lastTaskId,programId=id,pc=1,stack={},context=copy(entry.context or {}),
        status="RUNNING",executed=0,budgetYields=0}
      tasks[task.id]=task; enqueue(task.id); return task.id
    end
    local function execute(task,instruction,currentProgram)
      if type(instruction)~="table" then fail("E_EVENT_IR","Missing instruction") end
      local op=instruction.op
      if op=="nop" then task.pc=task.pc+1
      elseif op=="return" then
        local frame=task.stack[#task.stack]
        if frame then task.stack[#task.stack]=nil; task.programId=frame.programId; task.pc=frame.pc
        else finish(task,"DONE") end
      elseif op=="jump" then task.pc=target(instruction.target,currentProgram.instructions)
      elseif op=="branch" then
        local otherwise=target(instruction.otherwise,currentProgram.instructions)
        local condition=instruction.condition
        local handler=type(condition)=="table" and conditions[condition.kind]
        local result
        if handler then result=handler(copy(condition),copy(task.context))
        else result=state.testCondition(condition,task.context) end
        if not active(task) then return end
        if type(result)~="boolean" then fail("E_EVENT_CONDITION","Condition handler must return a boolean") end
        if result then task.pc=task.pc+1 else task.pc=otherwise end
      elseif op=="switches" then state.setSwitches(instruction.first,instruction.last,instruction.value); task.pc=task.pc+1
      elseif op=="variables" then
        local resolve=options.resolveOperand and function(operand)return options.resolveOperand(copy(operand),copy(task.context))end
        state.applyVariables(instruction.first,instruction.last,instruction.operation,instruction.operand,resolve); task.pc=task.pc+1
      elseif op=="self_switch" then state.setSelfSwitch(task.context,instruction.key,instruction.value); task.pc=task.pc+1
      elseif op=="wait" then
        local frames=instruction.frames
        if not integer(frames) or frames<0 or frames>limit-clock then fail("E_EVENT_TIME","Invalid wait duration or deadline") end
        task.pc=task.pc+1
        if frames>0 then task.status="WAITING"; task.wait={kind="frames",deadline=clock+frames} end
      elseif op=="call" then
        if type(instruction.programId)~="string" or not instruction.programId:match("^common:[1-9]%d*$") then fail("E_EVENT_REFERENCE","Call requires a common program id") end
        program(instruction.programId)
        if #task.stack+1>=maxCallDepth then fail("E_EVENT_DEPTH","Maximum active event call frames exceeded") end
        task.stack[#task.stack+1]={programId=task.programId,pc=task.pc+1}
        task.programId=instruction.programId; task.pc=1
      elseif op=="dialogue" then
        if dialogue.busy() or noticeDialogue.busy() then task.status="WAITING"; task.wait={kind="channel"}; return end
        if instruction.choices~=nil then
          if type(instruction.choices)~="table" or type(instruction.choiceTargets)~="table" then fail("E_EVENT_IR","Missing choices or destinations") end
          for index=1,#instruction.choices do target(instruction.choiceTargets[index],currentProgram.instructions) end
          if instruction.cancelChoice==-2 or (integer(instruction.cancelChoice) and instruction.cancelChoice>=#instruction.choices) then
            target(instruction.cancelTarget,currentProgram.instructions)
          end
        end
        local message=copy(instruction)
        if message.numberInput then message.numberInput.value=state.getVariable(message.numberInput.variableId)end
        dialogue.open(task.id,message); task.status="WAITING"; task.wait={kind="message"}
      elseif op=="battle" and handlers.battle then
        local allowed={op=true,source=true,troopOperand=true,canEscape=true,canLose=true,resultTargets=true,skipTarget=true}
        for key in pairs(instruction) do if not allowed[key] then fail("E_EVENT_IR","Unknown battle instruction field") end end
        local operand=instruction.troopOperand
        if type(operand)~="table" then fail("E_EVENT_IR","Missing troop operand") end
        for key in pairs(operand) do if key~="kind" and key~="value" then fail("E_EVENT_IR","Unknown troop operand field") end end
        local validOperand=integer(operand.value) and ((operand.kind=='constant' or operand.kind=='variable') and operand.value>=1 or operand.kind=='encounter' and operand.value==0)
        if not validOperand
          or type(instruction.canEscape)~="boolean" or type(instruction.canLose)~="boolean"
          or type(instruction.resultTargets)~="table" or #instruction.resultTargets~=3 then fail("E_EVENT_IR","Invalid battle instruction") end
        local targets={}
        for key,value in pairs(instruction.resultTargets) do
          if not integer(key) or key<1 or key>3 then fail("E_EVENT_IR","Invalid battle result targets") end
          targets[key]=target(value,currentProgram.instructions)
        end
        local skip=target(instruction.skipTarget,currentProgram.instructions)
        local result=handlers.battle(copy(instruction),copy(task.context),task.id)
        if not active(task) then return end
        if type(result)~="table" then fail("E_EVENT_SERVICE","Battle handler must continue or wait") end
        if result.kind=="continue" then task.pc=skip
        elseif result.kind=="wait" and type(result.token)=="string" and #result.token>0 and #result.token<=256 then
          task.status="WAITING";task.wait={kind="battle",token=result.token,targets=targets}
        else fail("E_EVENT_SERVICE","Battle wait requires an opaque token") end
      elseif handlers[op] then
        if actorOps[op] then actorInstruction(instruction) end
        local result=handlers[op](copy(instruction),copy(task.context),task.id)
        if not active(task) then return end
        if type(result)~='table' then fail('E_EVENT_SERVICE','Command handler must continue or wait') end
        if result.kind=='continue' then addNotices(task.id,result.messages);task.pc=task.pc+1
        elseif result.kind=='wait' and type(result.token)=='string' and #result.token>0 and #result.token<=256 then
          task.pc=task.pc+1;task.status='WAITING';task.wait={kind='command',token=result.token}
        else fail('E_EVENT_SERVICE','Command wait requires an opaque token') end
      else fail("E_EVENT_OP","Unknown IR operation: "..tostring(op)) end
    end
    function S.tick(frames)
      if not integer(frames) or frames<0 or frames>limit-clock then fail("E_EVENT_TIME","Logical frames must be nonnegative safe integers without clock overflow") end
      clock=clock+frames
      -- Snapshot eligible IDs, not history: callbacks may cancel/release peers
      -- or create tasks. Each existing task gets at most one visit this tick;
      -- new tasks begin next tick and removed peers cannot shift array indices.
      local schedule,cursor={},nextActive
      for i=1,activeCount do schedule[i]=cursor; cursor=running[cursor].next end
      local total=0
      for _,id in ipairs(schedule) do
        if total>=frameBudget then break end
        if options.shouldYield and options.shouldYield()then break end
        local node=running[id]
        if node then
          local task=tasks[id]; nextActive=node.next
          if task.status=="WAITING" then
            if task.wait.kind=="frames" and clock>=task.wait.deadline or task.wait.kind=="channel" and not dialogue.busy() and not noticeDialogue.busy() then
              task.status="RUNNING"; task.wait=nil
            end
          end
          local used=0
          while task.status=="RUNNING" and used<perTaskBudget and total<frameBudget do
            local current=programs[task.programId]
            local instruction=current and current.instructions and current.instructions[task.pc]
            if task.executed==limit then
              taskError(task,{code='E_EVENT_TIME',reason='Event execution counter exhausted'},type(instruction)=='table' and instruction.source or nil)
              break
            end
            used=used+1; total=total+1; task.executed=task.executed+1
            local ok,err=pcall(execute,task,instruction,current)
            if not ok and active(task) then taskError(task,err,type(instruction)=="table" and instruction.source or nil) end
          end
          if task.status=="RUNNING" and used>0 and (used==perTaskBudget or total==frameBudget) then
            if task.budgetYields==limit then taskError(task,{code='E_EVENT_TIME',reason='Event budget counter exhausted'})
            else task.budgetYields=task.budgetYields+1 end
          end
        end
      end
      return total
    end
    function S.getTask(id) return tasks[id] and copy(tasks[id]) or nil end
    function S.getState() return state.snapshot() end
    function S.getMessage()
      local message=dialogue.getMessage();if message then return message end
      message=noticeDialogue.getMessage();if message then message.token=-message.token end;return message
    end
    function S.respond(id,token,answer)
      if type(token)=='number' and token<0 then
        if dialogue.busy()then return false end
        local accepted=noticeDialogue.respond(id,-token,answer)
        if accepted then table.remove(notices,1);openNotice()end
        return accepted
      end
      local task=tasks[id]
      if not active(task) or not task.wait or task.wait.kind~="message" then return false end
      local accepted,destination,write=dialogue.respond(id,token,answer)
      if not accepted then return false end
      if write then state.applyVariables(write.variableId,write.variableId,0,{kind='constant',value=write.value})end
      task.pc=destination or task.pc+1; task.wait=nil; task.status="RUNNING"; return true
    end
    function S.cancel(id)
      local task=tasks[id]; if not active(task) then return false end
      finish(task,"CANCELLED"); return true
    end
    function S.resumeBattle(id,token,result)
      local task=tasks[id]
      if not active(task) or not task.wait or task.wait.kind~="battle" or task.wait.token~=token
        or not integer(result) or result<0 or result>2 then return false end
      task.pc=task.wait.targets[result+1];task.wait=nil;task.status="RUNNING";return true
    end
    function S.resumeCommand(id,token)
      local task=tasks[id]
      if not active(task) or not task.wait or task.wait.kind~='command' or task.wait.token~=token then return false end
      task.wait=nil;task.status='RUNNING';return true
    end
    function S.isCommandWaiting(id,token)
      local task=tasks[id]
      return task~=nil and task.status=='WAITING' and task.wait~=nil and task.wait.kind=='command' and task.wait.token==token
    end
    function S.snapshot()
      local ids,entries,order={},{},{};for id in pairs(tasks)do ids[#ids+1]=id end;table.sort(ids)
      for _,id in ipairs(ids)do entries[#entries+1]=copy(tasks[id])end
      local cursor=nextActive;for _=1,activeCount do order[#order+1]=cursor;cursor=running[cursor].next end
      local message=dialogue.getMessage()
      return snapshotCopy({schemaVersion=1,clock=clock,lastTaskId=lastTaskId,state=state.snapshot(),tasks=entries,
        order=order,messageSerial=dialogue.sequence(),messageTaskId=message and message.taskId or false,
        notices=noticeDialogue.sequence()>0 and notices or nil,noticeSerial=noticeDialogue.sequence()>0 and noticeDialogue.sequence() or nil})
    end
    -- Consume a final result only after its owner has read status/diagnostic.
    -- Active tasks must be cancelled first. IDs and dialogue tokens never reset.
    function S.release(id)
      local task=tasks[id]; if not task or active(task) then return false end
      tasks[id]=nil; return true
    end
    if restored then
      local function check(v,reason)if not v then fail('E_EVENT_SNAPSHOT',reason)end end
      local function fields(v,allowed)
        check(type(v)=='table','Expected snapshot object')
        for k in pairs(v)do check(allowed[k],'Unknown snapshot field: '..tostring(k))end
      end
      local function natural(v)check(integer(v) and v>=0,'Expected snapshot nonnegative integer');return v end
      local function dense(v,max)
        check(type(v)=='table','Expected snapshot array');local n,high=0,0
        for k in pairs(v)do check(integer(k) and k>=1 and k<=max,'Invalid snapshot array index');n=n+1;high=math.max(high,k)end
        check(n==high,'Sparse snapshot array');return n
      end
      local function address(id,pc,live,afterLast)
        check(type(id)=='string' and type(programs[id])=='table' and type(programs[id].instructions)=='table','Unknown snapshot program')
        check(integer(pc) and pc>=1 and (not live or pc<=#programs[id].instructions+(afterLast and 1 or 0)),'Invalid snapshot instruction address')
      end
      fields(restored,{schemaVersion=true,clock=true,lastTaskId=true,state=true,tasks=true,order=true,messageSerial=true,messageTaskId=true,notices=true,noticeSerial=true})
      check(restored.schemaVersion==1,'Unsupported interpreter snapshot version')
      clock,lastTaskId=natural(restored.clock),natural(restored.lastTaskId)
      local serial=natural(restored.messageSerial);local messageId=restored.messageTaskId
      check(messageId==false or integer(messageId) and messageId>=1,'Invalid snapshot message owner')
      fields(restored.state,{switches=true,variables=true,selfSwitches=true})
      check(equal(state.snapshot(),restored.state),'Shared story state does not match interpreter snapshot')
      local liveCount=0;local statuses={RUNNING=true,WAITING=true,DONE=true,ERROR=true,CANCELLED=true}
      for i=1,dense(restored.tasks,100000)do
        local task=restored.tasks[i]
        fields(task,{id=true,programId=true,pc=true,stack=true,context=true,status=true,executed=true,budgetYields=true,wait=true,diagnostic=true})
        check(integer(task.id) and task.id>=1 and task.id<=lastTaskId and not tasks[task.id],'Duplicate or invalid snapshot task')
        check(statuses[task.status],'Invalid snapshot task status');address(task.programId,task.pc,active(task),true)
        natural(task.executed);natural(task.budgetYields);check(type(task.context)=='table','Invalid snapshot event context')
        local depth=dense(task.stack,maxCallDepth-1)
        for j=1,depth do local frame=task.stack[j];fields(frame,{programId=true,pc=true});address(frame.programId,frame.pc,active(task),true)end
        local entry=programs[depth>0 and task.stack[1].programId or task.programId]
        check(equal(task.context,entry.context or {}),'Snapshot event context differs from its source')
        if active(task)then liveCount=liveCount+1 end
        if task.status=='WAITING'then
          local wait=task.wait;check(type(wait)=='table','Missing snapshot wait')
          if wait.kind=='frames'then fields(wait,{kind=true,deadline=true});natural(wait.deadline)
          elseif wait.kind=='channel' or wait.kind=='message'then
            fields(wait,{kind=true});local instruction=programs[task.programId].instructions[task.pc]
            check(type(instruction)=='table' and instruction.op=='dialogue','Message wait must reference dialogue')
            check(wait.kind~='message' or messageId==task.id,'Snapshot message ownership differs')
          elseif wait.kind=='command'then
            fields(wait,{kind=true,token=true});check(type(wait.token)=='string' and #wait.token>0 and #wait.token<=256,'Invalid command wait token')
            local previous=programs[task.programId].instructions[task.pc-1]
            local builtins={nop=true,['return']=true,jump=true,branch=true,switches=true,variables=true,self_switch=true,wait=true,call=true,dialogue=true,battle=true}
            check(task.executed>0 and type(previous)=='table' and not builtins[previous.op] and type(handlers[previous.op])=='function','Command wait does not follow a bound command')
          elseif wait.kind=='battle'then
            fields(wait,{kind=true,token=true,targets=true});check(type(wait.token)=='string' and #wait.token>0 and #wait.token<=256,'Invalid battle wait token')
            check(dense(wait.targets,3)==3,'Battle wait requires three targets')
            for _,pc in ipairs(wait.targets)do address(task.programId,pc,true)end
            local instruction=programs[task.programId].instructions[task.pc]
            check(task.executed>0 and type(instruction)=='table' and instruction.op=='battle' and equal(wait.targets,instruction.resultTargets),'Battle wait branches differ from compiled instruction')
          else check(false,'Unknown snapshot wait kind')end
        else check(task.wait==nil,'Only waiting tasks may retain a wait')end
        check(task.status~='ERROR' or type(task.diagnostic)=='table','Error task needs its diagnostic')
        tasks[task.id]=task
      end
      check(dense(restored.order,100000)==liveCount,'Active snapshot schedule is incomplete')
      local scheduled={};for _,id in ipairs(restored.order)do
        check(integer(id) and active(tasks[id]) and not scheduled[id],'Invalid or repeated active task');scheduled[id]=true;enqueue(id)
      end
      if messageId~=false then
        local task=tasks[messageId];check(task and task.status=='WAITING' and task.wait.kind=='message' and serial>=1,'Missing active snapshot message')
        local instruction=copy(programs[task.programId].instructions[task.pc])
        if instruction.numberInput then instruction.numberInput.value=state.getVariable(instruction.numberInput.variableId)end
        dialogue=dialogueModule.new(serial-1);check(dialogue.open(messageId,instruction),'Cannot restore message')
      else dialogue=dialogueModule.new(serial)end
      if restored.notices~=nil or restored.noticeSerial~=nil then
        local n=dense(restored.notices,10000);local count=natural(restored.noticeSerial)
        check(count>0,'Invalid notification serial')
        for _,entry in ipairs(restored.notices)do
          fields(entry,{taskId=true,message=true});check(integer(entry.taskId) and entry.taskId>=1 and entry.taskId<=lastTaskId,'Invalid notification owner')
          local message=entry.message;check(type(message)=='table' and not message.choices and not message.numberInput and not message.itemChoice and not message.scroll,'Invalid notification')
          local validator=dialogueModule.new();validator.open(entry.taskId,message)
        end
        notices=copy(restored.notices);noticeDialogue=dialogueModule.new(n>0 and count-1 or count);openNotice()
      end
    end
    return S
  end
  return M
end
