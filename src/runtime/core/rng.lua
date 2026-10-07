-- Versioned deterministic draws and finite golden-test streams. No global RNG.
return function()
  local M={}
  local maximum=9007199254740991
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function integer(v) return type(v)=="number" and v==v and v>=0 and v<=maximum and v%1==0 end
  local function plain(v)
    if type(v)~="table" or getmetatable(v)~=nil then fail("E_RNG_STATE","Expected a plain table") end
  end
  local function valuesCopy(values)
    plain(values);local count=0;local result={}
    for k,v in next,values do
      if not integer(k) or k<1 or k>100000 then fail("E_RNG_STATE","Fixed stream must be a dense bounded array") end
      if type(v)~="number" or v~=v or v<0 or v>=1 then fail("E_RNG_STATE","Fixed draw must be finite in [0,1)") end
      count=count+1;result[k]=v*1.0
    end
    for i=1,count do if result[i]==nil then fail("E_RNG_STATE","Fixed stream contains a gap") end end
    return result
  end
  local function create(algorithm,state,draws,values)
    local last
    local R={}
    local function draw(purpose,upper)
      if type(purpose)~="string" or #purpose==0 or #purpose>128 then fail("E_RNG_ARGUMENT","A draw requires a purpose of 1..128 bytes") end
      if draws==maximum then fail("E_RNG_STATE","Draw counter exhausted") end
      local unit,nextState
      if algorithm=="r2u-fixed-v1" then
        unit=values[draws+1]
        if unit==nil then fail("E_RNG_EXHAUSTED","Fixed random stream exhausted") end
      else
        nextState=(state*16807.0)%2147483647.0
        unit=(nextState-1.0)/2147483646.0
      end
      local result=upper and math.floor(unit*upper) or unit
      if nextState then state=nextState end
      draws=draws+1.0
      last={index=draws,purpose=purpose,unit=unit,result=result,upper=upper}
      return result
    end
    function R.nextUnit(purpose) return draw(purpose) end
    function R.nextInt(upper,purpose)
      if not integer(upper) or upper<1 or upper>2147483647 then fail("E_RNG_ARGUMENT","Integer upper bound must be 1..2147483647") end
      return draw(purpose,upper)
    end
    function R.lastDraw()
      if not last then return nil end
      local result={};for k,v in next,last do result[k]=v end;return result
    end
    function R.snapshot()
      local result={algorithm=algorithm,draws=draws}
      if values then result.values=valuesCopy(values) else result.state=state end
      return result
    end
    return R
  end
  function M.new(seed)
    if not integer(seed) or seed<1 or seed>2147483646 then fail("E_RNG_STATE","Seed must be 1..2147483646") end
    return create("r2u-lcg31-v1",seed,0)
  end
  function M.fixed(values) return create("r2u-fixed-v1",nil,0,valuesCopy(values)) end
  function M.restore(snapshot)
    plain(snapshot)
    local algorithm=snapshot.algorithm
    if algorithm~="r2u-lcg31-v1" and algorithm~="r2u-fixed-v1" then fail("E_RNG_STATE","Unknown random algorithm") end
    local allowed={algorithm=true,draws=true};allowed[algorithm=="r2u-fixed-v1" and "values" or "state"]=true
    for key in next,snapshot do if not allowed[key] then fail("E_RNG_STATE","Unknown random snapshot field") end end
    if not integer(snapshot.draws) then fail("E_RNG_STATE","Invalid draw counter") end
    if algorithm=="r2u-fixed-v1" then
      local values=valuesCopy(snapshot.values)
      if snapshot.draws>#values then fail("E_RNG_STATE","Fixed stream position exceeds its length") end
      return create(algorithm,nil,snapshot.draws,values)
    end
    if not integer(snapshot.state) or snapshot.state<1 or snapshot.state>2147483646 then fail("E_RNG_STATE","Invalid random state") end
    return create(algorithm,snapshot.state,snapshot.draws)
  end
  return M
end
