-- One message channel per session. Answers never execute event instructions.
return function()
  local M={}
  local function fail(reason) error({severity="error",code="E_EVENT_IR",reason=reason},0) end
  local function integer(v) return type(v)=="number" and v==v and v>=-9007199254740991 and v<=9007199254740991 and v%1==0 end
  local function copy(v,seen)
    if type(v)~="table" then return v end
    seen=seen or {}; if seen[v] then return seen[v] end
    local out={}; seen[v]=out; for key,value in pairs(v) do out[key]=copy(value,seen) end; return out
  end
  local function texts(values)
    if type(values)~="table" then fail("Message text must be an array") end
    local count=0
    for key,value in pairs(values) do
      if not integer(key) or key<1 or key>#values or type(value)~="string" then fail("Invalid message text array") end
      count=count+1
    end
    if count~=#values then fail("Message text must be dense") end
    return copy(values)
  end
  -- Uses compiled presentation text and growth deltas; no source parsing or host writes.
  function M.growth(ui,actorId,delta,actorName)
    if not delta or delta.levelTo<=delta.levelFrom then return nil end
    local terms=ui and ui.terms or {};local messages,basic=terms.messages or {},terms.basic or {}
    local function format(key,fallback,args)
      local text=(messages[key] or fallback):gsub('%%(%d+)',function(i)
        local value=args[tonumber(i)];return type(value)=='number' and string.format('%.0f',value) or tostring(value or '')
      end)
      return text
    end
    local lines={format('levelUp','%1 is now %2 %3!',{actorName,basic[1] or 'Level',delta.levelTo})}
    for _,id in ipairs(delta.learnedSkillsAdded or {})do
      local name
      for _,skill in ipairs(ui and ui.presentationDefs and ui.presentationDefs.skills or {})do if skill.id==id then name=skill.name;break end end
      if not name then fail('Missing learned skill presentation: '..tostring(id))end
      lines[#lines+1]=format('obtainSkill','%1 learned!',{name})
    end
    return {lines=lines,speaker='',background=0,position=2,faceName='',faceIndex=0}
  end
  function M.new(initialSerial)
    if initialSerial~=nil and (not integer(initialSerial) or initialSerial<0) then fail("Invalid message sequence") end
    local current, serial=nil,initialSerial or 0
    local D={}
    function D.sequence() return serial end
    function D.busy() return current~=nil end
    function D.open(taskId,instruction)
      if current then return false end
      local message={taskId=taskId,lines=texts(instruction.lines),speaker=instruction.speaker,
        background=instruction.background,position=instruction.position,faceName=instruction.faceName or '',faceIndex=instruction.faceIndex or 0,
        faceTemplateId=instruction.faceTemplateId,flowTokens=copy(instruction.flowTokens),speakerTokens=copy(instruction.speakerTokens)}
      if type(message.speaker)~="string" then fail("Message speaker must be a string") end
      if instruction.scroll~=nil then
        local scroll=instruction.scroll
        if type(scroll)~='table' or not integer(scroll.speed) or scroll.speed<1 or scroll.speed>8 or type(scroll.noFast)~='boolean'
          or instruction.choices or instruction.numberInput or instruction.itemChoice then fail('Invalid scrolling text settings')end
        message.scroll={speed=scroll.speed,noFast=scroll.noFast}
      end
      if instruction.choices~=nil then
        message.choices=texts(instruction.choices)
        message.choiceTokens=copy(instruction.choiceTokens)
        message.extendedChoices=instruction.extendedChoices==true
        message.choiceEnabled=copy(instruction.choiceEnabled)
        message.choicePosition=instruction.choicePosition==nil and 2 or instruction.choicePosition
        message.choiceBackground=instruction.choiceBackground==nil and 0 or instruction.choiceBackground
        if not integer(message.choicePosition) or message.choicePosition<0 or message.choicePosition>2
          or not integer(message.choiceBackground) or message.choiceBackground<0 or message.choiceBackground>2 then fail("Invalid choice presentation settings") end
        if #message.choices<1 or #message.choices>(message.extendedChoices and 128 or 6) then fail("Choices exceed declared native/extended limit") end
        local count=#message.choices
        if not integer(instruction.defaultChoice) or instruction.defaultChoice< -1 or instruction.defaultChoice>=count
          or not integer(instruction.cancelChoice) or instruction.cancelChoice< -2 then fail("Invalid choice settings") end
        message.defaultChoice=instruction.defaultChoice
        message.cancelChoice=instruction.cancelChoice>=count and -2 or instruction.cancelChoice
      end
      if instruction.numberInput~=nil then
        local input=instruction.numberInput
        if message.choices or instruction.itemChoice or type(input)~='table' or not integer(input.variableId) or input.variableId<1
          or not integer(input.digits) or input.digits<1 or input.digits>8 then fail('Invalid number input')end
        message.numberInput={variableId=input.variableId,digits=input.digits,value=math.max(0,math.min(10^input.digits-1,math.floor(input.value or 0)))}
      elseif instruction.itemChoice~=nil then
        local input=instruction.itemChoice
        if message.choices or type(input)~='table' or not integer(input.variableId) or input.variableId<1
          or not integer(input.itemType) or input.itemType<1 or input.itemType>4 then fail('Invalid item choice')end
        message.itemChoice=copy(input)
      end
      if serial==9007199254740991 then fail("Message token exhausted") end
      serial=serial+1; message.token=serial
      current={view=message,choiceTargets=copy(instruction.choiceTargets),cancelTarget=instruction.cancelTarget}
      return true
    end
    function D.getMessage() return current and copy(current.view) or nil end
    function D.release(taskId)
      if current and current.view.taskId==taskId then current=nil; return true end
      return false
    end
    function D.respond(taskId,token,answer)
      if not current or current.view.taskId~=taskId or current.view.token~=token or type(answer)~="table" then return false end
      local view,target=current.view,nil
      if view.choices then
        local index
        if answer.kind=="choice" then index=answer.index
        elseif answer.kind=="cancel" then
          if view.cancelChoice==-1 then return false end
          if view.cancelChoice==-2 then target=current.cancelTarget else index=view.cancelChoice end
        else return false end
        if index~=nil then
          if not integer(index) or index<0 or index>=#view.choices then return false end
          if view.choiceEnabled and view.choiceEnabled[index+1]==false then return false end
          target=current.choiceTargets[index+1]
        elseif answer.kind~="cancel" or view.cancelChoice~=-2 then return false end
      elseif view.numberInput then
        if answer.kind~='number' or not integer(answer.value) or answer.value<0 or answer.value>=10^view.numberInput.digits then return false end
        target={variableId=view.numberInput.variableId,value=answer.value}
      elseif view.itemChoice then
        if answer.kind=='cancel'then target={variableId=view.itemChoice.variableId,value=0}
        elseif answer.kind=='item' and integer(answer.id) and answer.id>=0 then target={variableId=view.itemChoice.variableId,value=answer.id}
        else return false end
      elseif answer.kind~="confirm" then return false end
      current=nil
      if view.numberInput or view.itemChoice then return true,nil,target end
      return true,target
    end
    return D
  end
  return M
end
