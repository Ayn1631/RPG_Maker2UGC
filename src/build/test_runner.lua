-- One harness for direct tests and explicitly selected verification. No shell.
return function()
 local M={}
 local function describe(value)
  if type(value)=='table' and value.code then return value.code..': '..tostring(value.reason)end
  return tostring(value)
 end
 function M.run(root,options,loader)
  options=options or {};root=root:gsub('/+$','')..'/'
  local catalog=assert(loadfile(root..'tools/test_suites.lua','t',{}))()
  local suites=catalog
  if options.suite then
   local found=false;for _,name in ipairs(catalog)do if name==options.suite then found=true end end
   if not found then error({severity='error',code='E_VERIFY_SUITE',reason='Unknown suite: '..tostring(options.suite)},0)end
   suites={options.suite}
  end
  local result={ok=true,passed=0,failed=0,cases={}};local current
  local function record(name,ok,err)
   local row={suite=current,name=name,ok=ok,reason=not ok and describe(err) or nil}
   result.cases[#result.cases+1]=row;local field=ok and 'passed' or 'failed';result[field]=result[field]+1
   if options.onResult then options.onResult(row)end
  end
  local t={}
  function t.eq(actual,expected)if actual~=expected then error('expected '..describe(expected)..', got '..describe(actual),2)end end
  function t.truthy(value)assert(value,'expected truthy value')end
  function t.raises_code(fn,code)
   local ok,err=pcall(fn);assert(not ok,'expected error '..code)
   assert(type(err)=='table' and err.code==code,'expected '..code..', got '..describe(err));return err
  end
  function t.test(name,fn)
   if options.filter and not name:find(options.filter,1,true)then return end
   local ok,err=pcall(fn);record(name,ok,err)
  end
  for _,name in ipairs(suites)do
   current=name
   local ok,err=pcall(function()assert(loadfile(root..'tests/test_'..name..'.lua'))()(t,loader,root)end)
   if not ok then record('suite setup',false,err)end
  end
  if result.passed+result.failed==0 then record('case selection',false,'Test filter matched no cases')end
  result.ok=result.failed==0;return result
 end
 return M
end
