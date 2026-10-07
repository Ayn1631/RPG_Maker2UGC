-- Offline normalization of the native 0..44 movement command vocabulary.
return function(deps)
 local json,diagnostic=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function integer(v)return type(v)=='number' and v==v and math.abs(v)<=9007199254740991 and v%1==0 end
 local function copy(v)if type(v)~='table'or v==json.null then return v end;local o=json.is_array(v)and json.array()or json.object();for k,x in pairs(v)do o[k]=copy(x)end;return o end
 local names={'down','left','right','up','lower_left','lower_right','upper_left','upper_right','random','toward','away','forward','backward','jump','wait','turn_down','turn_left','turn_right','turn_up','turn_right90','turn_left90','turn180','turn_random90','turn_random','turn_toward','turn_away','switch_on','switch_off','speed','frequency','walk_on','walk_off','step_on','step_off','fix_on','fix_off','through_on','through_off','transparent_on','transparent_off','image','opacity','blend','se'}
 function M.compile(route,source,options)
  local location=copy(source or {});options=options or {}
  local function check(ok,reason,code)if not ok then diagnostic.raise(code or 'E_MOVE_ROUTE_SOURCE',reason,location)end end
  check(type(route)=='table'and route~=json.null and not json.is_array(route),'Movement route must be an object')
  for _,k in ipairs({'repeat','skippable','wait'})do check(type(route[k])=='boolean','Movement route '..k..' must be boolean')end
  check(json.is_array(route.list)and #route.list>0,'Movement route must have a command list')
  local out=json.object({repeatRoute=route['repeat'],skippable=route.skippable,wait=route.wait,list=json.array()})
  local base=location.jsonPath or '$'
  for i,command in ipairs(route.list)do
   location.jsonPath=base..'.list['..(i-1)..']'
   check(type(command)=='table'and integer(command.code)and command.code>=0 and command.code<=45,'Unknown movement route command')
   local code,p=command.code,command.parameters
   local expected=(code==14 or code==41)and 2 or (code==15 or code>=27 and code<=30 or code>=42 and code<=45)and 1 or 0
   -- Native MZ omits parameters on parameterless route commands (including
   -- door turns and ROUTE_END). Missing required arguments are still errors.
   if p==nil and expected==0 then p=json.array()end
   check(json.is_array(p),'Movement command parameters must be an array')
   local ins=json.object({op=code==0 and 'end_route' or names[code]})
   check(#p==expected,'Invalid movement parameter count')
   local function number(n,min,max)check(integer(p[n])and p[n]>=min and p[n]<=max,'Invalid movement numeric parameter');return p[n]end
   if code==14 then ins.x=number(1,-9007199254740991,9007199254740991);ins.y=number(2,-9007199254740991,9007199254740991)
   elseif code==15 then ins.frames=number(1,1,9007199254740991)
   elseif code==27 or code==28 then ins.id=number(1,1,9007199254740991)
   elseif code==29 then ins.value=number(1,1,6)
   elseif code==30 then ins.value=number(1,1,5)
   elseif code==41 then check(type(p[1])=='string','Character image name must be a string');ins.name=p[1];ins.index=number(2,0,7)
   elseif code==42 then ins.value=number(1,0,255)
   elseif code==43 then ins.value=number(1,0,3)
   elseif code==44 then
    local se=p[1];check(type(se)=='table'and type(se.name)=='string','Movement SE must be an audio cue')
    for _,pair in ipairs({{'volume',0,100},{'pitch',50,150},{'pan',-100,100}})do check(integer(se[pair[1]])and se[pair[1]]>=pair[2]and se[pair[1]]<=pair[3],'Invalid movement SE '..pair[1])end
    ins.cue=copy(se)
   elseif code==45 then
    check(type(options.compileScript)=='function','Movement scripts require an explicit offline extension compiler','E_MOVE_ROUTE_SCRIPT')
    local extension=options.compileScript(p[1],copy(location));check(type(extension)=='table'and type(extension.name)=='string','Invalid movement script extension','E_MOVE_ROUTE_SCRIPT')
    ins.op='extension';ins.extension=copy(extension)
   end
   check(code~=0 or i==#route.list,'Route end must be the final command')
   out.list[#out.list+1]=ins
  end
  check(route.list[#route.list].code==0,'Movement route requires an end command')
  return out
 end
 return M
end
