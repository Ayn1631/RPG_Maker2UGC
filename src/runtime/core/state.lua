-- Platform-free event state. All range writes validate before committing.
return function()
  local M = {}
  local limit = 9007199254740991
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function integer(v)
    return type(v)=="number" and v==v and v>=-limit and v<=limit and v%1==0
  end
  local function number(v)
    if not integer(v) then fail("E_EVENT_NUMBER","Expected a finite safe integer") end
    return v
  end
  local function id(v)
    if not integer(v) or v<1 then fail("E_EVENT_REFERENCE","Invalid state id") end
    return v
  end
  local function range(first,last)
    id(first); id(last)
    if first>last then fail("E_EVENT_REFERENCE","Invalid state range") end
  end
  local function boolean(v)
    if type(v)~="boolean" then fail("E_EVENT_IR","Expected boolean state value") end
    return v
  end
  local function selfKey(context,key)
    if type(context)~="table" or not integer(context.mapId) or context.mapId<1
      or not integer(context.eventId) or context.eventId<1 then
      fail("E_EVENT_CONTEXT","Self-switch requires mapId and eventId")
    end
    if key~="A" and key~="B" and key~="C" and key~="D" then fail("E_EVENT_IR","Invalid self-switch key") end
    return string.format("%d:%d:%s",context.mapId,context.eventId,key)
  end
  function M.new(initial)
    if initial~=nil and type(initial)~="table" then fail("E_EVENT_OPTIONS","state must be a table") end
    local data={switches={},variables={},selfSwitches={}}
    for _,field in ipairs({"switches","variables","selfSwitches"}) do
      local values=initial and initial[field]
      if values~=nil then
        if type(values)~="table" then fail("E_EVENT_OPTIONS","State fields must be tables") end
        for key,value in pairs(values) do
          if field=="selfSwitches" then
            if type(key)~="string" or not key:match("^[1-9]%d*:[1-9]%d*:[ABCD]$") then
              fail("E_EVENT_REFERENCE","Invalid self-switch state key")
            end
          else id(key) end
          if field=="variables" then number(value) else boolean(value) end
          data[field][key]=value
        end
      end
    end
    local S={}
    function S.getSwitch(key) id(key); local v=data.switches[key]; if v==nil then return false end; return v end
    function S.getVariable(key) id(key); local v=data.variables[key]; if v==nil then return 0 end; return v end
    function S.getSelfSwitch(context,key)
      local v=data.selfSwitches[selfKey(context,key)]; if v==nil then return false end; return v
    end
    function S.setSwitches(first,last,value)
      range(first,last); boolean(value); for key=first,last do data.switches[key]=value end
    end
    function S.setSelfSwitch(context,key,value)
      local full=selfKey(context,key); boolean(value); data.selfSwitches[full]=value
    end
    function S.readOperand(operand)
      if type(operand)~="table" then fail("E_EVENT_IR","Missing variable operand") end
      if operand.kind=="constant" then return number(operand.value) end
      if operand.kind=="variable" then return S.getVariable(operand.value) end
      fail("E_EVENT_IR","Unknown operand kind")
    end
    function S.applyVariables(first,last,operation,operand,resolve)
      range(first,last)
      if not integer(operation) or operation<0 or operation>5 then fail("E_EVENT_IR","Unknown variable operation") end
      local external=type(operand)=='table' and (operand.kind=='random' or operand.kind=='game_data' or operand.kind=='extension_query')
      if external and type(resolve)~='function'then fail('E_EVENT_IR','Variable operand resolver is required')end
      local value=not external and S.readOperand(operand) or operand.kind~='random' and number(resolve(operand)) or nil
      local pending={}
      for key=first,last do
        local right=(value~=nil and value or number(resolve(operand)))+0.0
        if (operation==4 or operation==5) and right==0 then fail("E_EVENT_NUMBER","Division or remainder by zero") end
        local left=S.getVariable(key)+0.0
        local value
        if operation==0 then value=right
        elseif operation==1 then value=left+right
        elseif operation==2 then value=left-right
        elseif operation==3 then value=left*right
        elseif operation==4 then value=left/right
        else value=math.fmod(left,right) end -- JS remainder follows the dividend sign.
        if value~=value or value< -limit or value>limit then fail("E_EVENT_NUMBER","Variable result exceeds finite safe range") end
        pending[key]=number(math.floor(value))
      end
      for key=first,last do data.variables[key]=pending[key] end
    end
    function S.testCondition(condition,context)
      if type(condition)~="table" then fail("E_EVENT_IR","Missing condition") end
      if condition.kind=="switch" then return S.getSwitch(condition.id)==boolean(condition.value) end
      if condition.kind=="self_switch" then return S.getSelfSwitch(context,condition.key)==boolean(condition.value) end
      if condition.kind=="variable" then
        local left,right=S.getVariable(condition.id),S.readOperand(condition.operand)
        local op=condition.comparison
        if op==0 then return left==right elseif op==1 then return left>=right elseif op==2 then return left<=right
        elseif op==3 then return left>right elseif op==4 then return left<right elseif op==5 then return left~=right end
      end
      fail("E_EVENT_IR","Unknown condition or comparison")
    end
    function S.snapshot()
      local view={switches={},variables={},selfSwitches={}}
      for field,values in pairs(data) do for key,value in pairs(values) do view[field][key]=value end end
      return view
    end
    return S
  end
  return M
end
