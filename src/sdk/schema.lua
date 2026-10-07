-- Small shared extension schema, deliberately not JSON Schema or a code evaluator.
return function(deps)
 local J,D=deps['contracts.json'],deps['contracts.diagnostic'];local S={};local SAFE=9007199254740991
 local function fail(reason,path)D.raise('E_EXTENSION_SCHEMA',reason,{jsonPath=path or '$'})end
 local function object(v)return type(v)=='table' and v~=J.null and not J.is_array(v)end
 local function integer(v)return type(v)=='number' and v==v and v%1==0 and math.abs(v)<=SAFE end
 local function copy(v,seen)
  if type(v)~='table' or v==J.null then return v end
  seen=seen or {};if seen[v]then fail('Cyclic extension data')end;seen[v]=true
  local out=J.is_array(v) and J.array() or J.object();for k,x in pairs(v)do out[k]=copy(x,seen)end;seen[v]=nil;return out
 end
 S.copy=copy
 local types={integer=true,number=true,boolean=true,string=true,enum=true,ref=true,list=true,record=true}
 local common={type=true,required=true,default=true}
 local fields={integer={min=true,max=true},number={min=true,max=true},boolean={},string={minLength=true,maxLength=true},enum={values=true},ref={reference=true},list={items=true,minItems=true,maxItems=true},record={properties=true}}
 function S.validate(schema)
  local seen={}
  local function visit(s,path,depth)
   if not object(s) or not types[s.type] or depth>32 or seen[s]then fail('Invalid or recursive schema',path)end
   seen[s]=true;for k in pairs(s)do if not common[k] and not fields[s.type][k]then fail('Unknown schema field '..tostring(k),path)end end
   if s.required~=nil and type(s.required)~='boolean'then fail('required must be boolean',path)end
   for _,key in ipairs({'min','max','minLength','maxLength','minItems','maxItems'})do
    if s[key]~=nil and (type(s[key])~='number' or s[key]~=s[key] or math.abs(s[key])>SAFE)then fail('Invalid bound '..key,path)end
   end
   for _,pair in ipairs({{'min','max'},{'minLength','maxLength'},{'minItems','maxItems'}})do if s[pair[1]] and s[pair[2]] and s[pair[1]]>s[pair[2]]then fail('Reversed schema bounds',path)end end
   for _,key in ipairs({'minLength','maxLength','minItems','maxItems'})do if s[key] and (not integer(s[key]) or s[key]<0)then fail('Length bounds must be nonnegative integers',path)end end
   if s.maxLength and s.maxLength>65536 or s.maxItems and s.maxItems>10000 then fail('Schema exceeds extension data limits',path)end
   if s.type=='record'then
    if not object(s.properties)then fail('Record requires properties',path)end
    for name,child in pairs(s.properties)do if type(name)~='string' or name==''then fail('Invalid property name',path)end;visit(child,path..'.'..name,depth+1)end
   elseif s.type=='list'then visit(s.items,path..'[]',depth+1)
   elseif s.type=='enum'then
    if type(s.values)~='table' or #s.values<1 then fail('Enum needs values',path)end
    local n=0;for k in pairs(s.values)do if not integer(k) or k<1 or k>#s.values then fail('Enum must be dense',path)end;n=n+1 end
    if n~=#s.values or n>256 then fail('Enum length outside bounds',path)end
    local used={};for _,v in ipairs(s.values)do if type(v)~='string' or used[v]then fail('Enum values must be unique strings',path)end;used[v]=true end
   elseif s.type=='ref' and (type(s.reference)~='string' or s.reference=='')then fail('Reference needs a named collection',path)end
   seen[s]=nil
  end
  visit(schema,'$',0);return true
 end
 function S.check(schema,value,refs,path)
  local budget=20000
  local function check(s,v,p,depth)
   budget=budget-1;if budget<0 or depth>32 then fail('Extension data budget exceeded',p)end
   if v==nil then
    if s.default~=nil then v=copy(s.default)elseif s.required==false then return nil else fail('Missing required value',p)end
   end
   local kind=s.type
   if kind=='record'then
    if not object(v)then fail('Expected record',p)end
    local out=J.object();for k in pairs(v)do if not s.properties[k]then fail('Unknown field '..tostring(k),p)end end
    for k,child in pairs(s.properties)do out[k]=check(child,v[k],p..'.'..k,depth+1)end;return out
   elseif kind=='list'then
    if type(v)~='table' or v==J.null then fail('Expected list',p)end
    local n,high=0,0;for k in pairs(v)do if not integer(k) or k<1 then fail('Expected dense list',p)end;n=n+1;high=math.max(high,k)end
    if n~=high or n<(s.minItems or 0) or n>(s.maxItems or 1024) or n>10000 then fail('List length outside bounds',p)end
    local out=J.array();for i=1,n do out[i]=check(s.items,v[i],p..'['..(i-1)..']',depth+1)end;return out
   elseif kind=='integer' or kind=='number'then
    if type(v)~='number' or v~=v or math.abs(v)>SAFE or kind=='integer' and v%1~=0 then fail('Expected finite '..kind,p)end
    if s.min and v<s.min or s.max and v>s.max then fail('Number outside bounds',p)end
   elseif kind=='boolean'then if type(v)~='boolean'then fail('Expected boolean',p)end
   else
    if type(v)~='string' or not utf8.len(v) or #v>65536 then fail('Expected bounded UTF-8 string',p)end
    local n=utf8.len(v);if n<(s.minLength or 0) or n>(s.maxLength or 65536)then fail('String length outside bounds',p)end
    if kind=='enum'then local found=false;for _,x in ipairs(s.values)do if x==v then found=true end end;if not found then fail('Unknown enum value',p)end
    elseif kind=='ref' then if not refs or not refs[s.reference] or not refs[s.reference][v]then fail('Unknown '..s.reference..' reference '..v,p)end
    elseif kind~='string'then fail('Unknown schema type',p)end
   end
   return v
  end
  return check(schema,value,path or '$',0)
 end
 function S.fromString(schema,value)
  if type(value)~='string'then fail('Native plugin parameters must be strings')end
  local kind=schema.type
  if kind=='integer' or kind=='number'then
   if not value:match('^[+-]?%d+%.?%d*[eE]?[+-]?%d*$')then fail('Invalid numeric parameter')end
   local n=tonumber(value);if not n then fail('Invalid numeric parameter')end;return n
  elseif kind=='boolean'then
   if value=='true'then return true elseif value=='false'then return false end;fail('Boolean parameter must be true or false')
  elseif kind=='list' or kind=='record'then return J.decode(value)
  else return value end
 end
 return S
end
