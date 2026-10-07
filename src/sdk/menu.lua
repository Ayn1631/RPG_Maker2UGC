-- Shared MenuProvider contract; providers never receive host controls.
return function(deps)
 local S=deps['sdk.schema'];local M={}
 local function str(max,required,default)return{type='string',maxLength=max,required=required,default=default}end
 local function fail(reason)error({code='E_EXTENSION_MENU',reason=reason},0)end
 local descriptor={type='list',maxItems=16,items={type='record',properties={id={type='string',minLength=1,maxLength=64},label={type='string',minLength=1,maxLength=80},keyEvent=str(80,false,'')}}}
 local rowSchema={type='record',properties={id={type='string',minLength=1,maxLength=128},label=str(128),status=str(128,false,''),description=str(4096,false,'')}}
 function M.definitions(value)
  local result=S.check(descriptor,value or {});local ids={}
  for _,d in ipairs(result)do if not d.id:match('^[a-z][a-z0-9_]*$') or ids[d.id]then fail('Invalid or duplicate menu ID')end;ids[d.id]=true end
  return result
 end
 function M.view(raw,commands,refs)
  if type(raw)~='table' then fail('Menu provider must return a view')end
  for k in pairs(raw)do if k~='title' and k~='rows'then fail('Unknown menu view field')end end
  local title=S.check(str(128),raw.title);local rows=raw.rows
  if type(rows)~='table' or #rows>256 then fail('Invalid menu rows')end
  local n=0;for k in pairs(rows)do if type(k)~='number' or k%1~=0 or k<1 or k>#rows then fail('Menu rows must be dense')end;n=n+1 end
  if n~=#rows then fail('Menu rows contain holes')end
  local result={title=title,rows={}};local ids={}
  for i,row in ipairs(rows)do
   if type(row)~='table'then fail('Menu row must be a record')end
   local value={};for k,v in pairs(row)do if k~='action'then value[k]=v end end
   value=S.check(rowSchema,value);if ids[value.id]then fail('Duplicate menu row ID')end;ids[value.id]=true
   if row.action~=nil then
    local a=row.action;if type(a)~='table'then fail('Invalid menu action')end
    for k in pairs(a)do if k~='label' and k~='command' and k~='args'then fail('Unknown menu action field')end end
    local command=type(a.command)=='string' and commands[a.command]
    if not command then fail('Menu action must name a registered command')end
    value.action={label=S.check({type='string',minLength=1,maxLength=80},a.label),command=a.command,args=S.check(command.args,a.args,refs)}
   end
   result.rows[i]=value
  end
  return result
 end
 return M
end
