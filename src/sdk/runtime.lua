-- Compiled definitions stay private. Domain operations commit before extension state.
return function(deps)
 local Schema=deps['sdk.schema'];local M={}
 local function fail(reason)error({severity='error',code='E_EXTENSION_RUNTIME',reason=reason},0)end
 local function int(v)return type(v)=='number' and v%1==0 and math.abs(v)<=2147483647 end
 function M.new(program,declarations)
  if type(program)~='table' or program.kind~='r2u.extension-program' or program.schemaVersion~=1 then fail('Compiled extension program required')end
  local definitions,states,capabilities,revisions,menus,policies={},{},{},{},{},{}
  for _,d in ipairs(program.definitions)do
   if definitions[d.id] or type(d.runtime)~='table' or type(d.runtime.execute)~='function'then fail('Duplicate or missing extension runtime')end
   definitions[d.id]=d;states[d.id]=Schema.copy(d.initial);local caps={};for _,c in ipairs(d.capabilities)do caps[c]=true end;capabilities[d.id]=caps
   revisions[d.id]=0
   for _,p in ipairs(deps['sdk.policy'].declarations(d.schema.policies))do
    if policies[p.name] or not caps.policies or type(d.runtime.policy)~='function'then fail('Conflicting or missing policy provider '..p.name)end
    policies[p.name]={definition=d,revision=-1,cache={},count=0}
   end
   for _,m in ipairs(d.schema.menus or {})do
    if not caps.menus or type(d.runtime.menu)~='function'then fail('Declared menu provider is unavailable')end
    menus[#menus+1]={extensionId=d.id,id=m.id,label=m.label,keyEvent=m.keyEvent or '',symbol='extension:'..d.id..':'..m.id}
   end
  end
  local seen={};for _,d in ipairs(declarations or {})do
   local registered=definitions[d.id]
   if not registered or seen[d.id] or registered.version~=d.version or registered.contractVersion~=d.contractVersion or registered.stateSchemaVersion~=d.stateSchemaVersion then fail('Extension lock does not match runtime')end;seen[d.id]=true
  end
  for id in pairs(definitions)do if not seen[id]then fail('Undeclared extension runtime '..id)end end
  local R={}
  local function contextFor(d,context)
   local plan=d.plan;if plan==nil then plan={}end
   return{state=Schema.copy(states[d.id]),data=Schema.copy(d.data),config=Schema.copy(d.config),plan=Schema.copy(plan),query=context.query}
  end
  function R.menus()return Schema.copy(menus)end
  function R.policyRevision(name)local p=policies[name];return p and revisions[p.definition.id] or -1 end
  function R.policy(name,input,default)
   local p=policies[name];if not p then return default end
   local d=p.definition;local args,key=deps['sdk.policy'].input(name,input)
   if p.revision~=revisions[d.id] then p.cache={};p.count=0;p.revision=revisions[d.id]end
   if p.cache[key]~=nil then return p.cache[key]end
   if p.count>=512 then p.cache={};p.count=0 end
   -- Policies receive no world query/RNG/clock service: cache by their own state
   -- revision and explicit input, never by an implicit mutable game context.
   local result=deps['sdk.policy'].result(name,d.runtime.policy(name,contextFor(d,{}),args))
   p.cache[key]=result;p.count=p.count+1;return result
  end
  function R.query(ins,context)
   local d=definitions[ins.extensionId];local spec=d and d.schema.queries and d.schema.queries[ins.query]
   if not spec or not capabilities[d.id].queries or ins.contractVersion~=d.contractVersion or ins.resultType~=spec.result.type or type(d.runtime.query)~='function'then fail('Unknown query or result contract')end
   local args=Schema.check(spec.args,ins.args,d.refs)
   return Schema.check(spec.result,d.runtime.query(ins.query,contextFor(d,context),args),d.refs)
  end
  function R.menu(extensionId,menuId,context)
   local d=definitions[extensionId];local found=false
   for _,m in ipairs(menus)do if m.extensionId==extensionId and m.id==menuId then found=true;break end end
   if not found then fail('Unknown extension menu')end
   local view=deps['sdk.menu'].view(d.runtime.menu(menuId,contextFor(d,context)),d.schema.commands,d.refs)
   view.extensionId,view.id,view.revision=extensionId,menuId,revisions[extensionId]
   return view
  end
  function R.menuAction(request,context)
   if not definitions[request.extensionId] or request.revision~=revisions[request.extensionId]then return nil,'stale' end
   local view=R.menu(request.extensionId,request.menuId,context)
   for _,row in ipairs(view.rows)do if row.id==request.rowId then
    if not row.action then return nil,'disabled' end
    return{extensionId=request.extensionId,contractVersion=definitions[request.extensionId].contractVersion,command=row.action.command,args=row.action.args}
   end end
   return nil,'missing-row'
  end
  function R.prepare(ins,context)
   local d=definitions[ins.extensionId];local caps=capabilities[ins.extensionId]
   if not d or ins.contractVersion~=d.contractVersion or not d.schema.commands[ins.command] or not caps.commands then fail('Unknown extension command or contract')end
   local args=Schema.check(d.schema.commands[ins.command].args,ins.args,d.refs)
   if revisions[d.id]>=9007199254740991 then fail('Extension revision exhausted')end
   local ctx=contextFor(d,context)
   local result=d.runtime.execute(ins.command,ctx,args)
   if type(result)~='table'then fail('Extension command must return a proposal')end
   for k in pairs(result)do if k~='state' and k~='operations' and k~='message'then fail('Unknown extension result field '..tostring(k))end end
   local state=Schema.check(d.schema.state,result.state,d.refs)
   local operations=result.operations or {};if type(operations)~='table' or #operations>128 then fail('Invalid operation list')end
   local n=0;for k in pairs(operations)do if not int(k) or k<1 or k>#operations then fail('Operations must be dense')end;n=n+1 end;if n~=#operations then fail('Operations contain holes')end
   for _,op in ipairs(operations)do
    if type(op)~='table' or not caps[op.kind] or not int(op.amount)then fail('Unpermitted domain operation')end
    local allowed={kind=true,amount=true}
    if op.kind=='inventory'then
     allowed.id,allowed.itemKind=true,true
     if not int(op.id) or op.id<1 or not ({item=true,weapon=true,armor=true})[op.itemKind]then fail('Invalid inventory operation')end
    elseif op.kind~='gold'then fail('Unsupported domain operation')end
    for k in pairs(op)do if not allowed[k]then fail('Unknown domain operation field')end end
   end
   local message
   if result.message then
    if not caps.dialogue then fail('Extension has no dialogue capability')end
    local v=result.message;if type(v)~='table' or type(v.lines)~='table' or #v.lines>1024 or type(v.speaker or '')~='string'then fail('Invalid extension message')end
    for k in pairs(v)do if k~='lines' and k~='speaker'then fail('Unknown extension message field')end end
    local tokens={};local bytes=0;local count=0
    for k in pairs(v.lines)do if not int(k) or k<1 or k>#v.lines then fail('Message lines must be dense')end;count=count+1 end
    if count~=#v.lines then fail('Message lines contain holes')end
    for i,line in ipairs(v.lines)do
     if type(line)~='string' or not utf8.len(line)then fail('Message must contain UTF-8 text')end
     bytes=bytes+#line+1;if bytes>65536 then fail('Message text exceeds budget')end
     if i>1 then tokens[#tokens+1]={kind='newline'}end
     local first=true
     for part in (line..'\n'):gmatch('(.-)\n')do
      if not first then tokens[#tokens+1]={kind='newline'}end
      if part~=''then tokens[#tokens+1]={kind='text',value=part}end
      first=false
     end
    end
    message={speaker=v.speaker or '',lines=Schema.copy(v.lines),flowTokens=tokens,background=0,position=2}
   end
   return{id=d.id,state=state,operations=Schema.copy(operations),message=message}
  end
  function R.commit(proposal)states[proposal.id]=proposal.state;revisions[proposal.id]=revisions[proposal.id]+1 end
  function R.snapshot()return Schema.copy(states)end
  return R
 end
 return M
end
