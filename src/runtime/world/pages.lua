-- Highest matching source event page. Trigger orchestration belongs to the caller.
return function(deps)
  local M={}
  local limit=9007199254740991
  local function fail(reason) error({severity="error",code="E_WORLD_PAGE",reason=reason},0) end
  local function integer(v) return type(v)=="number" and v==v and v>=-limit and v<=limit and v%1==0 end
  local function number(v) return type(v)=="number" and v==v and v>=-limit and v<=limit end
  local function id(v) return integer(v) and v>0 end
  local rules={
    {valid="switch1Valid",key="switch1Id",service="getSwitch"},
    {valid="switch2Valid",key="switch2Id",service="getSwitch"},
    {valid="variableValid",key="variableId",service="getVariable"},
    {valid="selfSwitchValid",key="selfSwitchCh",service="getSelfSwitch"},
    {valid="itemValid",key="itemId",service="hasItem"},
    {valid="actorValid",key="actorId",service="hasActor"},
  }
  function M.select(eventDef,context,services)
    if type(context)~="table" then fail("Page context must be a table") end
    if context.erased==true then return nil end
    if context.erased~=nil and type(context.erased)~="boolean" then fail("Erased must be boolean") end
    if not id(context.mapId) or not id(context.eventId) then fail("Page context requires map and event ids") end
    if type(eventDef)~="table" or type(eventDef.pages)~="table" then fail("Event requires a page array") end
    services=services==nil and {} or services
    if type(services)~="table" then fail("Page services must be a table") end
    local pages=eventDef.pages
    local count=0
    for key in pairs(pages) do
      if not integer(key) or key<1 then fail("Pages must be a consecutive array") end
      count=count+1
    end
    -- Validate every page before evaluating, so invalid data cannot hide under a
    -- higher matching page or behind an earlier false condition.
    for index=1,count do
      local page=pages[index]
      if type(page)~="table" or type(page.conditions)~="table" then fail("Each page requires conditions") end
      local c=page.conditions
      for _,rule in ipairs(rules) do
        if c[rule.valid]~=nil and type(c[rule.valid])~="boolean" then fail("Invalid "..rule.valid) end
        if c[rule.valid]==true then
          local value=c[rule.key]
          if rule.valid=="selfSwitchValid" then
            if value~="A" and value~="B" and value~="C" and value~="D" then fail("Invalid self switch key") end
          elseif not id(value) then fail("Invalid "..rule.key) end
          if rule.valid=="variableValid" and not number(c.variableValue) then fail("Variable threshold must be a finite number") end
          if type(services[rule.service])~="function" then fail("Missing "..rule.service.." service") end
        end
      end
    end
    local function call(name,...)
      local ok,value=pcall(services[name],...)
      if not ok then fail("Page service failed: "..name) end
      if name=="getVariable" then
        if not number(value) then fail("Variable service must return a finite number") end
      elseif type(value)~="boolean" then fail(name.." service must return boolean") end
      return value
    end
    local function meets(c)
      if c.switch1Valid and not call("getSwitch",c.switch1Id) then return false end
      if c.switch2Valid and not call("getSwitch",c.switch2Id) then return false end
      if c.variableValid and call("getVariable",c.variableId)<c.variableValue then return false end
      if c.selfSwitchValid and not call("getSelfSwitch",context,c.selfSwitchCh) then return false end
      if c.itemValid and not call("hasItem","item",c.itemId,false) then return false end
      if c.actorValid and not call("hasActor",c.actorId) then return false end
      return true
    end
    for index=count,1,-1 do if meets(pages[index].conditions) then return index end end
    return nil
  end
  return M
end
