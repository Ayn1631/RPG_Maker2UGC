-- Framework-owned contracts for exclusive, deterministic rule providers.
return function(deps)
 local S,D,J=deps['sdk.schema'],deps['contracts.diagnostic'],deps['contracts.json'];local M={}
 local safe=9007199254740991
 local function integer(min)return{type='integer',min=min,max=safe}end
 local contracts={
  ['battle.damage']={args={type='record',properties={subjectKind={type='enum',values=J.array({'actor','enemy'})},value=integer(-safe)}},result=integer(-safe),
   key=function(a)return a.subjectKind..':'..string.format('%.0f',a.value)end},
  ['shop.price']={args={type='record',properties={mode={type='enum',values=J.array({'buy','sell'})},kind={type='enum',values=J.array({'item','weapon','armor'})},id=integer(1),basePrice=integer(0)}},result=integer(0),
   key=function(a)return a.mode..':'..a.kind..':'..string.format('%.0f:%.0f',a.id,a.basePrice)end},
  ['world.encounterSteps']={args={type='record',properties={mapId=integer(1),baseSteps=integer(1)}},result=integer(1),
   key=function(a)return string.format('%.0f:%.0f',a.mapId,a.baseSteps)end}}
 local function fail(reason)D.raise('E_EXTENSION_POLICY',reason)end
 function M.declarations(value)
  if value==nil then return{}end
  if type(value)~='table' or value==J.null then fail('Policy declarations must be a dense list')end
  local n=0;for k in pairs(value)do if type(k)~='number' or k%1~=0 or k<1 or k>#value then fail('Policy list must be dense')end;n=n+1 end
  if n~=#value or n>32 then fail('Invalid policy list size')end
  local out,seen={},{}
  for _,v in ipairs(value)do
   if type(v)~='table' or v==J.null then fail('Expected policy declaration')end
   for k in pairs(v)do if k~='name' and k~='contractVersion'then fail('Unknown policy declaration field')end end
   if not contracts[v.name] or v.contractVersion~=1 or seen[v.name]then fail('Unknown, duplicate or incompatible rule policy')end
   seen[v.name]=true;out[#out+1]={name=v.name,contractVersion=1}
  end
  return out
 end
 function M.input(name,value)
  local c=contracts[name];if not c then fail('Unknown policy '..tostring(name))end
  local args=S.check(c.args,value);return args,c.key(args)
 end
 function M.result(name,value)return S.check(assert(contracts[name]).result,value)end
 function M.contract(name)local c=assert(contracts[name]);return S.copy({contractVersion=1,args=c.args,result=c.result})end
 return M
end
