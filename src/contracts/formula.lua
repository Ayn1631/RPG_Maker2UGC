-- Pure bounded expression ASTs. No source execution or snapshot getters.
return function()
 local M={}
 local hard={maxSourceBytes=8192,maxTokens=4096,maxNodes=2048,maxDepth=64,maxOps=4096}
 local attributes={}
 for name in ('hp mp tp mhp mmp atk def mat mdf agi luk level hit eva cri cev mev mrf cnt hrg mrg trg tgr grd rec pha mcr tcr pdr mdr fdr exr'):gmatch('%S+')do attributes[name]=true end
 local arity={floor=1,ceil=1,round=1,abs=1,sqrt=1,pow=2,min=-1,max=-1}
 local precedence={['||']=1,['&&']=2,['==']=3,['!=']=3,['===']=3,['!==']=3,['<']=4,['<=']=4,['>']=4,['>=']=4,['+']=5,['-']=5,['*']=6,['/']=6,['%']=6}
 local function plain(v)return type(v)=='table' and getmetatable(v)==nil end
 local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
 local function integer(v)return finite(v) and v%1==0 and math.abs(v)<=9007199254740991 end
 local function raise(code,reason,origin,pos)
  -- Budget errors can precede AST validation; never copy untrusted positions.
  if not finite(pos) or pos<1 or pos>9007199254740991 or pos%1~=0 then pos=1 end
  local e={severity='error',code=code,reason=reason,offset=pos}
  if plain(origin)then for _,key in ipairs({'file','jsonPath','skillId','itemId','commandIndex'})do local v=rawget(origin,key);if v~=nil then e[key]=v end end end
  error(e,0)
 end
 local function originCopy(origin)
  if origin==nil then return {} end
  if not plain(origin)then raise('E_FORMULA_OPTIONS','Origin must be a plain record')end
  local out={}
  for _,key in ipairs({'file','jsonPath','skillId','itemId','commandIndex'})do
   local v=rawget(origin,key)
   if v~=nil then
    if key=='file' or key=='jsonPath' then if type(v)~='string'then raise('E_FORMULA_OPTIONS','Invalid origin '..key)end
    elseif not integer(v) or v<0 then raise('E_FORMULA_OPTIONS','Invalid origin '..key)end
    out[key]=v
   end
  end
  return out
 end
 local function limits(values,origin,phase)
  local out={};for key,v in pairs(hard)do out[key]=v end
  if values==nil then return out end
  if not plain(values)then raise('E_FORMULA_OPTIONS','Limits must be a plain record',origin)end
  for key,value in next,values do
   if not hard[key] or (phase=='compile' and key=='maxOps') or (phase=='evaluate' and (key=='maxTokens' or key=='maxSourceBytes')) or not integer(value) or value<1 or value>hard[key]then
    raise('E_FORMULA_OPTIONS','Invalid or unsupported budget',origin)
   end
   out[key]=value
  end
  return out
 end
 function M.compile(source,origin,budgets)
  origin=originCopy(origin);local budget=limits(budgets,origin,'compile')
  if type(source)~='string'then raise('E_FORMULA_SOURCE','Formula source must be a string',origin)end
  if #source>budget.maxSourceBytes then raise('E_FORMULA_BUDGET','Formula source exceeds byte budget',origin)end
  local tokens,position={},1
  local function token(kind,value,start)
   if #tokens>=budget.maxTokens then raise('E_FORMULA_BUDGET','Formula token budget exceeded',origin,start)end
   tokens[#tokens+1]={kind=kind,value=value,pos=start}
  end
  while position<=#source do
   local c=source:sub(position,position)
   if c:match('%s')then position=position+1
   elseif c:match('%d') or (c=='.' and source:sub(position+1,position+1):match('%d'))then
    local start=position
    while source:sub(position,position):match('%d')do position=position+1 end
    if source:sub(start,start)=='0' and position-start>1 then raise('E_FORMULA_SYNTAX','Legacy leading-zero numeric syntax is unsupported',origin,start)end
    if source:sub(position,position)=='.' then position=position+1;while source:sub(position,position):match('%d')do position=position+1 end end
    local exponent=source:sub(position,position)
    if exponent=='e' or exponent=='E'then
     position=position+1;local sign=source:sub(position,position);if sign=='+' or sign=='-'then position=position+1 end
     local digitStart=position;while source:sub(position,position):match('%d')do position=position+1 end
     if digitStart==position then raise('E_FORMULA_SYNTAX','Exponent requires digits',origin,position)end
    end
    local number=tonumber(source:sub(start,position-1))
    if not finite(number)then raise('E_FORMULA_NUMBER','Numeric literal must be finite',origin,start)end
    token('number',number+0.0,start)
   elseif c:match('[A-Za-z_]')then
    local start=position;position=position+1
    while source:sub(position,position):match('[A-Za-z0-9_]')do position=position+1 end
    token('identifier',source:sub(start,position-1),start)
   else
    local triple,pair=source:sub(position,position+2),source:sub(position,position+1)
    local op
    if pair=='++' or pair=='--'then raise('E_FORMULA_TOKEN','Update operators are unsupported',origin,position)end
    if triple=='===' or triple=='!=='then op=triple
    elseif precedence[pair]then op=pair
    elseif precedence[c] or c=='!' or c=='(' or c==')' or c=='[' or c==']' or c=='.' or c==',' or c=='?' or c==':'then op=c
    else raise('E_FORMULA_TOKEN','Unsupported token '..c,origin,position)end
    token('symbol',op,position);position=position+#op
   end
  end
  tokens[#tokens+1]={kind='end',value='<end>',pos=#source+1}
  local cursor,nodes,heights=1,0,{}
  local function current()return tokens[cursor]end
  local function take(value)
   local t=current();if value and t.value~=value then raise('E_FORMULA_SYNTAX','Expected '..value..', found '..tostring(t.value),origin,t.pos)end
   cursor=cursor+1;return t
  end
  local function make(node,children)
   nodes=nodes+1;if nodes>budget.maxNodes then raise('E_FORMULA_BUDGET','AST node budget exceeded',origin,node.pos)end
   local depth=1;for _,child in ipairs(children or {})do depth=math.max(depth,heights[child]+1)end
   if depth>budget.maxDepth then raise('E_FORMULA_BUDGET','AST depth budget exceeded',origin,node.pos)end
   heights[node]=depth;return node
  end
  local expression
  local function parse(minimum,depth)
   if depth>budget.maxDepth then raise('E_FORMULA_BUDGET','Parser depth budget exceeded',origin,current().pos)end
   local t=take();local left
   if t.kind=='number'then left=make({kind='number',value=t.value,pos=t.pos})
   elseif t.value=='true' or t.value=='false'then left=make({kind='boolean',value=t.value=='true',pos=t.pos})
   elseif t.value=='('then left=expression(0,depth+1);take(')')
   elseif t.value=='+' or t.value=='-' or t.value=='!'then
    local child=expression(7,depth+1);left=make({kind='unary',op=t.value,value=child,pos=t.pos},{child})
   elseif t.kind=='identifier' and (t.value=='a' or t.value=='b')then
    take('.');local name=take()
    if name.kind~='identifier' or not attributes[name.value]then raise('E_FORMULA_ATTRIBUTE','Unsupported battler attribute',origin,name.pos)end
    left=make({kind='property',target=t.value,name=name.value,pos=t.pos})
   elseif t.value=='v'then
    take('[');local index=expression(0,depth+1);take(']')
    left=make({kind='variable',index=index,pos=t.pos},{index})
   elseif t.value=='Math'then
    take('.');local name=take();local count=arity[name.value]
    if name.kind~='identifier' or not count then raise('E_FORMULA_CALL','Unsupported Math function',origin,name.pos)end
    take('(');local args={}
    if current().value~=')'then
     repeat
      if #args>=16 then raise('E_FORMULA_BUDGET','Math argument budget exceeded',origin,current().pos)end
      args[#args+1]=expression(0,depth+1)
      if current().value~=','then break end;take(',')
     until false
    end
    take(')')
    if #args<1 or (count~=-1 and #args~=count)then raise('E_FORMULA_CALL','Wrong Math argument count',origin,t.pos)end
    left=make({kind='call',name=name.value,args=args,pos=t.pos},args)
   else raise('E_FORMULA_SYNTAX','Expected a supported expression',origin,t.pos)end
   while true do
    local op=current();local priority=precedence[op.value]
    if priority and priority>=minimum then
     take();local right=expression(priority+1,depth+1)
     left=make({kind='binary',op=op.value,left=left,right=right,pos=op.pos},{left,right})
    elseif minimum==0 and op.value=='?'then
     take();local yes=expression(0,depth+1);take(':');local no=expression(0,depth+1)
     left=make({kind='conditional',condition=left,yes=yes,no=no,pos=op.pos},{left,yes,no})
    else break end
   end
   return left
  end
  expression=parse
  local root=expression(0,1)
  if current().kind~='end'then raise('E_FORMULA_SYNTAX','Unexpected trailing token',origin,current().pos)end
  return {kind='r2u.formula',schemaVersion=1,source=source,origin=origin,root=root}
 end
 local function truth(v)return v~=false and v~=0 end
 local function numeric(v)if v==true then return 1.0 elseif v==false then return 0.0 end;return v*1.0 end
 local function negativeZero(v)return v==0 and 1/v==-math.huge end
 local function round(v)
  if v==0 then return v end
  if v>=-0.5 and v<0 then return -0.0 end
  if math.abs(v)>=4503599627370496 then return v end
  local lower=math.floor(v)+0.0;return v-lower>=0.5 and lower+1.0 or lower
 end
 function M.evaluate(ast,context)
  if not plain(ast)then raise('E_FORMULA_AST','AST must be a plain record')end
  local origin=originCopy(rawget(ast,'origin'))
  if rawget(ast,'kind')~='r2u.formula' or rawget(ast,'schemaVersion')~=1 or type(rawget(ast,'source'))~='string' or #ast.source>hard.maxSourceBytes then raise('E_FORMULA_AST','Invalid formula schema',origin)end
  for key in next,ast do if key~='kind' and key~='schemaVersion' and key~='source' and key~='origin' and key~='root'then raise('E_FORMULA_AST','Unexpected AST field',origin)end end
  if context==nil then context={}end
  if not plain(context)then raise('E_FORMULA_CONTEXT','Context must be a plain record',origin)end
  local budget=limits(rawget(context,'limits'),origin,'evaluate')
  local visiting,nodes={},0
  local function validate(node,depth)
   if not plain(node) or visiting[node]then raise('E_FORMULA_AST','Invalid or cyclic AST node',origin)end
   if depth>budget.maxDepth then raise('E_FORMULA_BUDGET','AST depth budget exceeded',origin,rawget(node,'pos'))end
   nodes=nodes+1;if nodes>budget.maxNodes then raise('E_FORMULA_BUDGET','AST node budget exceeded',origin,rawget(node,'pos'))end
   visiting[node]=true
   local pos=rawget(node,'pos');if not integer(pos) or pos<1 or pos>#ast.source then raise('E_FORMULA_AST','Invalid node offset',origin)end
   local kind=rawget(node,'kind');local allowed={kind=true,pos=true}
   local function need(ok)if not ok then raise('E_FORMULA_AST','Invalid AST node shape',origin,pos)end end
   local function child(key)allowed[key]=true;validate(rawget(node,key),depth+1)end
   if kind=='number'then allowed.value=true;need(finite(rawget(node,'value')))
   elseif kind=='boolean'then allowed.value=true;need(type(rawget(node,'value'))=='boolean')
   elseif kind=='property'then allowed.target=true;allowed.name=true;need((node.target=='a' or node.target=='b') and attributes[node.name]==true)
   elseif kind=='variable'then child('index')
   elseif kind=='unary'then allowed.op=true;need(node.op=='+' or node.op=='-' or node.op=='!');child('value')
   elseif kind=='binary'then allowed.op=true;need(precedence[node.op]~=nil);child('left');child('right')
   elseif kind=='conditional'then child('condition');child('yes');child('no')
   elseif kind=='call'then
    allowed.name=true;allowed.args=true;need(arity[node.name]~=nil and plain(node.args))
    local count=0;for key in next,node.args do need(integer(key) and key>=1 and key<=16);count=count+1 end
    need(count>=1 and count<=16 and (arity[node.name]==-1 or count==arity[node.name]))
    for index=1,count do validate(rawget(node.args,index),depth+1)end
   else need(false)end
   for key in next,node do need(allowed[key]==true)end
   visiting[node]=nil
  end
  validate(rawget(ast,'root'),1)
  local operations=0
  local function checked(value,node)
   if not finite(value)then raise('E_FORMULA_NUMBER','Arithmetic result is not finite',origin,node.pos)end
   return value
  end
  local function snapshot(name,node)
   local value=rawget(context,name)
   if not plain(value)then raise('E_FORMULA_CONTEXT',name..' snapshot must be a plain table',origin,node.pos)end
   return value
  end
  local eval
  eval=function(node)
   operations=operations+1;if operations>budget.maxOps then raise('E_FORMULA_BUDGET','Evaluation operation budget exceeded',origin,node.pos)end
   local kind=node.kind
   if kind=='number'then return node.value*1.0 elseif kind=='boolean'then return node.value
   elseif kind=='property'then
    local value=rawget(snapshot(node.target,node),node.name)
    if not finite(value)then raise('E_FORMULA_CONTEXT','Missing or nonnumeric attribute '..node.target..'.'..node.name,origin,node.pos)end
    return value*1.0
   elseif kind=='variable'then
    local index=eval(node.index)
    if not integer(index) or index<1 then raise('E_FORMULA_INDEX','Variable index must be a positive safe integer',origin,node.pos)end
    local value=rawget(snapshot('v',node),index)
    if type(value)~='boolean' and not finite(value)then raise('E_FORMULA_CONTEXT','Missing or invalid variable '..tostring(index),origin,node.pos)end
    return type(value)=='number' and value*1.0 or value
   elseif kind=='conditional'then if truth(eval(node.condition))then return eval(node.yes)else return eval(node.no)end
   elseif kind=='unary'then
    local value=eval(node.value);if node.op=='!'then return not truth(value)end
    value=numeric(value);return node.op=='-' and -value or value
   elseif kind=='binary'then
    local left=eval(node.left);local op=node.op
    if op=='&&'then if not truth(left)then return left end;return eval(node.right)end
    if op=='||'then if truth(left)then return left end;return eval(node.right)end
    local right=eval(node.right)
    if op=='===' or op=='!=='then local equal=type(left)==type(right) and left==right;if op=='!=='then return not equal end;return equal end
    left,right=numeric(left),numeric(right)
    if op=='=='then return left==right elseif op=='!='then return left~=right elseif op=='<'then return left<right elseif op=='<='then return left<=right elseif op=='>'then return left>right elseif op=='>='then return left>=right end
    if (op=='/' or op=='%')and right==0 then raise('E_FORMULA_NUMBER','Division or remainder by zero',origin,node.pos)end
    local value
    if op=='+'then value=left+right elseif op=='-'then value=left-right elseif op=='*'then value=left*right elseif op=='/'then value=left/right else value=math.fmod(left,right)end
    return checked(value,node)
   elseif kind=='call'then
    local args={};for i,arg in ipairs(node.args)do args[i]=numeric(eval(arg))end
    local name,value=node.name
    if name=='floor'then value=args[1]==0 and args[1] or math.floor(args[1])+0.0
    elseif name=='ceil'then value=args[1]==0 and args[1] or math.ceil(args[1])+0.0;if value==0 and args[1]<0 then value=-0.0 end
    elseif name=='round'then value=round(args[1])
    elseif name=='abs'then value=math.abs(args[1])
    elseif name=='sqrt'then value=math.sqrt(args[1])
    elseif name=='pow'then value=args[1]^args[2]
    else
     value=args[1]
     for i=2,#args do local v=args[i]
      if name=='min'then if v<value or (v==0 and value==0 and negativeZero(v))then value=v end
      else if v>value or (v==0 and value==0 and not negativeZero(v))then value=v end end
     end
    end
    return checked(value,node)
   end
  end
  local value=eval(ast.root)
  if type(value)~='number'then raise('E_FORMULA_RESULT','Formula result must be numeric',origin,ast.root.pos)end
  return checked(value,ast.root)
 end
  return M
end
