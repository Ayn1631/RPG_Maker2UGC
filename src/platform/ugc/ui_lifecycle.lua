-- Logical controls are available immediately; native trees only change in a host frame.
return function()
 local M={}
 local LIMIT=400
 local function pack(...)return{n=select('#',...),...}end
 local setters={SetAnchorMin=true,SetAnchorMax=true,SetPivot=true,SetAnchoredPosition=true,
  SetSizeDelta=true,SetLocalRotation=true,SetLocalScale=true,SetImage=true,SetFillUnused=true,
  SetActive=true,SetVisible=true}
 local eventMethods={AddKeyEventListener='RemoveKeyEventListener',AddCursorEventListener='RemoveCursorEventListener',AddNavigationEventListener='RemoveNavigationEventListener'}
 local resetMethods={SetAnchorMin={'anchorMinX','anchorMinY'},SetAnchorMax={'anchorMaxX','anchorMaxY'},SetPivot={'pivotX','pivotY'},
  SetAnchoredPosition={'anchoredPositionX','anchoredPositionY'},SetSizeDelta={'sizeDeltaX','sizeDeltaY'},
  SetLocalRotation={'localRotationX','localRotationY','localRotationZ'},SetLocalScale={'localScaleX','localScaleY','localScaleZ'},
  SetImage={'imageSource','imageId'},SetActive={'active'},SetVisible={'visible'},SetFillUnused={'fillType'},
  SetSoftEdgeWidth={'softEdgeWidthX','softEdgeWidthY'},SetFillHorizontal={'fillType','fillHorizontalType','fillAmount'},
  SetFillVertical={'fillType','fillVerticalType','fillAmount'},SetFillRadial90={'fillType','fillRadial90Type','fillAmount'},
  SetFillRadial180={'fillType','fillRadialType','fillAmount'},SetFillRadial360={'fillType','fillRadialType','fillAmount'}}
 local fillMethods={SetFillUnused=true,SetFillHorizontal=true,SetFillVertical=true,SetFillRadial90=true,SetFillRadial180=true,SetFillRadial360=true}
 function M.new(host,catalog,options)
  local function fail(code,reason)
   -- OnStart failures occur before the renderer installs its error reporter.
   -- Print the structured reason too: the official host displays error tables
   -- as <table>, which otherwise hides the actual failed API contract.
   if host and type(host.logError)=='function'then pcall(host.logError,'R2U '..code..': '..reason)end
   error({severity='error',code=code,reason=reason},0)
  end
  if not host or not host.game or not host.script or not host.script.object then fail('E_UI_LIFECYCLE_HOST','UI lifecycle requires a script root and game')end
  if type(catalog)~='table'or catalog.version~=1 or type(catalog.templates)~='table'then fail('E_UI_TEMPLATE_CATALOG','Missing UI template catalog version 1')end
  options=options or {}
  -- Simulator A/B measured higher total latency even with 2048 idle slots.
  -- Retain explicit opt-in until the target host demonstrates a net benefit.
  local capacity=options.poolCapacity;if capacity==nil then capacity=0 end
  local idleFrames=options.poolIdleFrames;if idleFrames==nil then idleFrames=600 end
  if type(capacity)~='number'or capacity~=capacity or capacity%1~=0 or capacity<0 or capacity>2048
   or type(idleFrames)~='number'or idleFrames~=idleFrames or idleFrames%1~=0 or idleFrames<1 then
   fail('E_UI_POOL_OPTIONS','Expected poolCapacity integer 0..2048 and positive integer poolIdleFrames')
  end
  local checked={}
  local function validate(d,path,visiting)
   if type(d)~='table'or visiting[d]then fail('E_UI_TEMPLATE_CATALOG','Invalid template hierarchy at '..path)end
   visiting[d]=true;local n=1
   if type(d.children)~='table'or type(d.properties)~='table'or type(d.colors)~='table'or type(d.kind)~='string'then fail('E_UI_TEMPLATE_CATALOG','Incomplete descriptor at '..path)end
   for i,child in ipairs(d.children)do n=n+validate(child,path..'/'..i,visiting)end
   visiting[d]=nil
   if d.count~=n then fail('E_UI_TEMPLATE_CATALOG','Incorrect native control count at '..path)end
   return n
  end
  local nativeGame,nativeScript=host.game,host.script
  -- Host getters may return fresh userdata wrappers for one native control.
  -- Lua table keys ignore userdata __eq, so cache the runtime control ID.
  -- Official ClientUIBaseControl documents `id`; the installed simulator
  -- exposes `Id`. Select between these two evidenced contracts once per host,
  -- then use that field directly (no repeated exception probes per control).
  local owner,byNative={},setmetatable({},{__mode='v'})
  local idField
  local function validId(id)
   return type(id)=='number'and id==id and id%1==0 or type(id)=='string'and #id>0
  end
  local function nativeId(native)
   if not idField then
    local ok,id=pcall(function()return native.id end)
    if ok and validId(id)then idField='id';return id end
    local alternateOk,alternate=pcall(function()return native.Id end)
    if alternateOk and validId(alternate)then idField='Id';return alternate end
    fail('E_UI_CONTROL_ID','Cannot read runtime control ID: official id='..(ok and type(id)or 'unavailable')
     ..', simulator Id='..(alternateOk and type(alternate)or 'unavailable')..'; expected an integer or nonempty string')
   end
   local id=native[idField]
   if not validId(id)then fail('E_UI_CONTROL_ID','Invalid runtime control '..idField..': got '..type(id))end
   return id
  end
  local createQueue,createHead,destroyQueue,destroyHead={},1,{},1
  local creating,destroying=0,0
  local active,enabled,desired,applied=false,true,false,nil
  local stats={created=0,destroyed=0,canceled=0,lastFrameCreated=0,lastFrameDestroyed=0,peakFrameCreated=0,peakFrameDestroyed=0,frames=0,
   poolCapacity=capacity,poolIdle=0,poolHits=0,poolMisses=0,poolReturns=0,poolEvictions=0,poolPeak=0,
   lastFrameAcquired=0,lastFrameReleased=0,peakFrameAcquired=0,peakFrameReleased=0}
  local pools,idleByNative={},{}
  local oldest,newest
  local R,methods,meta={},{},{}
  local function state(o)
   local s=type(o)=='table'and rawget(o,'_uiLifecycle')
   if not s or s.owner~=owner then fail('E_UI_CONTROL_HANDLE','Expected a control from this UI lifecycle')end
   return s
  end
  local function pending()return creating+destroying+(not enabled and stats.poolIdle or 0)end
  local function schedule()
   -- A canceled startup may never receive another update; release its queue now.
   if creating==0 then createQueue,createHead={},1 end
   local value=desired or destroying>0 or enabled and creating>0 or stats.poolIdle>0
   if value~=applied and nativeScript.alive~=false then nativeScript:EnableUpdate(value);applied=value end
  end
  local function remember(s,key)
   if not s.poolable or s.defaults[key]then return end
   local ok,value=pcall(function()return s.native[key]end)
   if not ok or value==nil then s.poolable=false;return end
   s.defaults[key]={value=value}
   s.current[key]=value
  end
  local function nativeCall(s,name,args)
   if s.retired then return end
   local fn=s.native[name]
   if type(fn)~='function'then fail('E_UI_CONTROL_METHOD','Unsupported native control method '..name)end
   if not s.poolable then return fn(s.native,table.unpack(args,1,args.n))end
   local fields=resetMethods[name]
   if not fields then
    if not eventMethods[name]and not name:match('^Remove.*EventListener')and not name:match('^Get')and not name:match('^Find')then s.poolable=false end
    return fn(s.native,table.unpack(args,1,args.n))
   end
   for _,key in ipairs(fields)do remember(s,key)end
   if not s.poolable then return fn(s.native,table.unpack(args,1,args.n))end
   if fillMethods[name]then
    -- Fill methods also choose an enum value not present in their arguments.
    -- Retain their observed result; reuse only when no overlapping field changed.
    local saved=s.calls[name];local same=saved and saved.args.n==args.n
    if same then for i=1,args.n do if saved.args[i]~=args[i]then same=false;break end end end
    if same then for _,key in ipairs(fields)do if s.current[key]~=saved.values[key]then same=false;break end end end
    if same then return end
    fn(s.native,table.unpack(args,1,args.n));local values={}
    for _,key in ipairs(fields)do local value=s.native[key];s.current[key]=value;values[key]=value end
    s.calls[name]={args=args,values=values};return
   end
   local same=true;for i,key in ipairs(fields)do if s.current[key]~=args[i]then same=false;break end end
   if same then return end
   fn(s.native,table.unpack(args,1,args.n))
   for i,key in ipairs(fields)do s.current[key]=args[i]end
  end
  local function detach(s)
   if not s.parent then return end
   local children=s.parent.children
   for i,child in ipairs(children)do if child==s then table.remove(children,i);break end end
  end
  local function order(s)
   if not s.native or not s.parent or s.retired then return end
   local previous
   for _,child in ipairs(s.parent.children)do
    if child==s then break end
    if child.native and not child.retired then previous=child.native end
   end
   local at=0
   if previous then
    at=previous:GetSiblingIndex()+1
    if s.native:GetSiblingIndex()<at then at=at-1 end
   end
   s.native:SetSiblingIndex(at)
  end
  local function createState(parent,descriptor,native)
   local s={owner=owner,parent=parent,descriptor=descriptor,native=native,children={},builtins={},shadow={},writes={},operations={},listeners={}}
   local handle=setmetatable({_uiLifecycle=s},meta);s.handle=handle
   if parent then parent.children[#parent.children+1]=s end
   if native then s.nativeId=nativeId(native);byNative[s.nativeId]=handle end
   if descriptor then
    for key,value in pairs(descriptor.properties)do s.shadow[key]=value end
    for key,value in pairs(descriptor.colors)do
     if not host.Color or type(host.Color.FromRGBA)~='function'then fail('E_UI_LIFECYCLE_HOST','Template colors require Color.FromRGBA')end
     s.shadow[key]=host.Color.FromRGBA(table.unpack(value))
    end
    for _,child in ipairs(descriptor.children)do s.builtins[#s.builtins+1]=createState(s,child)end
   end
   return s
  end
  local function wrap(native,parent)
   local existing=byNative[nativeId(native)]
   if existing then return state(existing)end
   local s=createState(parent,nil,native)
   for _,child in ipairs(native:GetChildren())do wrap(child,s)end
   return s
  end
  local function property(s,key,value)
   if s.poolable then
    remember(s,key)
    if key=='fontSize'then remember(s,'minimumFontSize')
    elseif key=='minimumFontSize'then remember(s,'fontSize')end
    if key=='fontSize'then value=math.max(s.current.minimumFontSize or s.native.minimumFontSize or 1,math.floor(value))end
    if s.poolable and s.current[key]==value then return end
   elseif key=='fontSize'then value=math.max(s.native.minimumFontSize or 1,math.floor(value))end
   s.native[key]=value
   if s.poolable then
    s.current[key]=value
    if key=='minimumFontSize'then s.current.fontSize=s.native.fontSize end
   end
  end
  local function enqueue(s,key,job)
   local old=s.operations[key]
   if old then old.obsolete=true end
   s.operations[key]=job;s.writes[#s.writes+1]=job
  end
  meta.__index=function(handle,key)
   local s=rawget(handle,'_uiLifecycle')
   if key=='alive'then return not s.retired and (not s.native or s.native.alive~=false)end
   if key=='parent'then return s.parent and s.parent.handle end
   if methods[key]then return methods[key]end
   if s.retired then return s.shadow[key]end
   if s.native then
    local value=s.native[key]
    if type(value)=='function'then return function(_,...)return nativeCall(s,key,pack(...))end end
    return value
   end
   if s.shadow[key]~=nil then return s.shadow[key]end
   if type(key)=='string'and key:match('^[A-Z]')then fail('E_UI_CONTROL_METHOD','Unsupported pending control method '..key)end
  end
  meta.__newindex=function(handle,key,value)
   local s=rawget(handle,'_uiLifecycle')
   if s.retired then return end
   if key=='alive'or key=='parent'or methods[key]then fail('E_UI_CONTROL_PROPERTY','Cannot replace control member '..key)end
   if s.native then property(s,key,value)
   else s.shadow[key]=value;enqueue(s,key,{key=key,value=value})end
  end
  for name in pairs(setters)do
   methods[name]=function(handle,...)
    local s=state(handle);if s.retired then return end
    local args=pack(...)
    if s.native then return nativeCall(s,name,args)end
    local field=name=='SetActive'and 'active'or name=='SetVisible'and 'visible'
    if field then s.shadow[field]=args[1]end
    enqueue(s,field or '@'..name,{method=name,args=args})
   end
  end
  for add,remove in pairs(eventMethods)do
   methods[add]=function(handle,event,callback)
    local s=state(handle);if s.retired then return end
    local row={method=add,event=event,callback=callback};s.listeners[#s.listeners+1]=row
    if s.native then row.applied=true;return nativeCall(s,add,pack(event,callback))end
   end
   methods[remove]=function(handle,event,callback)
    local s=state(handle)
    if s.retired then return end
    if s.native then nativeCall(s,remove,pack(event,callback))end
    for i=#s.listeners,1,-1 do local row=s.listeners[i];if row.method==add and row.event==event and row.callback==callback then table.remove(s.listeners,i)end end
   end
  end
  function methods:GetChildren()
   local children={};for _,child in ipairs(state(self).children)do if not child.retired then children[#children+1]=child.handle end end;return children
  end
  function methods:GetSiblingIndex()
   local s=state(self);if s.parent then for i,child in ipairs(s.parent.children)do if child==s then return i-1 end end end;return 0
  end
  function methods:SetSiblingIndex(index)
   local s=state(self);if not s.parent or s.retired then return end
   if type(index)~='number'or index~=index then fail('E_UI_CONTROL_ORDER','Expected sibling index')end
   local siblings=s.parent.children;detach(s)
   table.insert(siblings,math.max(1,math.min(math.floor(index)+1,#siblings+1)),s);order(s)
  end
  function methods:SetAsFirstSibling()self:SetSiblingIndex(0)end
  function methods:SetAsLastSibling()local s=state(self);if s.parent then self:SetSiblingIndex(#s.parent.children)end end
  local root=wrap(nativeScript.object)
  local function hide(s)
   if not s.poolable then s.native:SetActive(false);s.native:SetVisible(false);return end
   remember(s,'active');remember(s,'visible')
   if s.current.active~=false then s.native:SetActive(false);s.current.active=false end
   if s.current.visible~=false then s.native:SetVisible(false);s.current.visible=false end
  end
  local function unlink(entry)
   if entry.previous then entry.previous.next=entry.next else oldest=entry.next end
   if entry.next then entry.next.previous=entry.previous else newest=entry.previous end
   local bucket=pools[entry.key]
   if entry.templatePrevious then entry.templatePrevious.templateNext=entry.templateNext else bucket.first=entry.templateNext end
   if entry.templateNext then entry.templateNext.templatePrevious=entry.templatePrevious else bucket.last=entry.templatePrevious end
   bucket.count=bucket.count-1;if bucket.count==0 then pools[entry.key]=nil end
   stats.poolIdle=stats.poolIdle-1;idleByNative[entry.nativeId]=nil
  end
  local function take(key)
   local bucket=pools[key];if not bucket then return end
   local entry=bucket.last;unlink(entry);stats.poolHits=stats.poolHits+1;return entry
  end
  local function reset(s)
   local overwritten={}
   for _,job in ipairs(s.writes)do if not job.obsolete then
    local fields=job.method and resetMethods[job.method]
    if fields then for _,key in ipairs(fields)do overwritten[key]=true end
    elseif job.key then overwritten[job.key]=true end
   end end
   -- Establish the next lower font bound first, so a previous lifetime's bound
   -- cannot clamp a saved/default fontSize or an upcoming explicit fontSize.
   local minimum=s.operations.minimumFontSize
   local defaultFont=s.defaults.fontSize
   local function restoreFont()
    if defaultFont and s.current.fontSize~=defaultFont.value then s.native.fontSize=defaultFont.value;s.current.fontSize=defaultFont.value end
   end
   if minimum and not minimum.obsolete then
    -- With no explicit fontSize, reconstruct the baseline before applying the
    -- new bound. This preserves whatever clamping the native bound setter does.
    if defaultFont and not overwritten.fontSize then
     if s.defaults.minimumFontSize then property(s,'minimumFontSize',s.defaults.minimumFontSize.value)end
     restoreFont()
    end
    property(s,'minimumFontSize',minimum.value);minimum.obsolete=true
   elseif s.defaults.minimumFontSize then property(s,'minimumFontSize',s.defaults.minimumFontSize.value)end
   for key,row in pairs(s.defaults)do
    if not overwritten[key]and key~='minimumFontSize'and key~='fontSize'and key~='active'and key~='visible'and key~='imageSource'and key~='imageId'then
     property(s,key,row.value)
    end
   end
   if defaultFont and not overwritten.fontSize and not overwritten.minimumFontSize then restoreFont()end
   if s.defaults.imageSource and not overwritten.imageSource and not overwritten.imageId then
    nativeCall(s,'SetImage',pack(s.defaults.imageSource.value,s.defaults.imageId.value))
   end
   if not overwritten.active then nativeCall(s,'SetActive',pack(s.defaults.active.value))end
   if not overwritten.visible then nativeCall(s,'SetVisible',pack(s.defaults.visible.value))end
  end
  local function park(s)
   for _,row in ipairs(s.listeners)do if row.applied then s.native[eventMethods[row.method]](s.native,row.event,row.callback)end end
   hide(s);if s.parent~=root then s.native.parent=root.native end
   local key=s.templateKey;local bucket=pools[key]
   if not bucket then bucket={count=0};pools[key]=bucket end
   local entry={native=s.native,nativeId=s.nativeId,key=key,frame=stats.frames,
    defaults=s.defaults,current=s.current,calls=s.calls,previous=newest,templatePrevious=bucket.last}
   if newest then newest.next=entry else oldest=entry end;newest=entry
   if bucket.last then bucket.last.templateNext=entry else bucket.first=entry end;bucket.last=entry;bucket.count=bucket.count+1
   idleByNative[entry.nativeId]=entry;stats.poolIdle=stats.poolIdle+1;stats.poolReturns=stats.poolReturns+1
   stats.poolPeak=math.max(stats.poolPeak,stats.poolIdle)
  end
  local function retire(s,hidden)
   if s.retired then return end
   s.retired=true
   if s.queued then creating=creating-s.descriptor.count;s.queued=false;stats.canceled=stats.canceled+s.descriptor.count end
   -- Inherited native visibility hides an entire branch. Descendants only need
   -- logical retirement and postorder reclamation, not more host property calls.
   if s.native and not hidden then hide(s);hidden=true end
   for _,child in ipairs(s.children)do retire(child,hidden)end
   if s.native then
    if not s.reclaim then s.reclaim=true;destroyQueue[#destroyQueue+1]=s;destroying=destroying+1 end
   end
   s.writes,s.operations={},{ }
  end
  local facade=setmetatable({},{__index=nativeGame})
  function facade.InstantiateClientUIControl(id,parent)
   if not enabled then fail('E_UI_LIFECYCLE_DISABLED','Cannot create controls while UI lifecycle is disabled')end
   if type(id)=='number'and (id~=id or id%1~=0)then fail('E_UI_TEMPLATE_UNKNOWN','Expected an integer native template ID')end
   local key=type(id)=='number'and string.format('%.0f',id)or tostring(id)
   local descriptor=catalog.templates[key]
   if not descriptor then fail('E_UI_TEMPLATE_UNKNOWN','No native template catalog entry for '..key)end
   if not checked[key]then
    if validate(descriptor,key,{})>LIMIT then fail('E_UI_TEMPLATE_BUDGET','Atomic template '..key..' exceeds 400 native controls')end
    checked[key]=true
   end
   local p=state(parent);if p.retired then fail('E_UI_CONTROL_PARENT','Cannot create under a retired control')end
   local s=createState(p,descriptor);s.template=id;s.templateKey=key;s.queued=true
   s.poolable=capacity>0 and descriptor.count==1
   if s.poolable then s.defaults,s.current,s.calls={},{},{}end
   createQueue[#createQueue+1]=s;creating=creating+descriptor.count;schedule();return s.handle
  end
  function facade.DestroyClientUIControl(handle)
   local s=state(handle);if s.retired then return end
   detach(s);retire(s);schedule()
  end
  -- Existing root lookups must keep the same logical identity.
  function facade.GetClientUIControl(...)
   local native=nativeGame.GetClientUIControl(...);if native and not idleByNative[nativeId(native)]then return wrap(native).handle end
  end
  local script=setmetatable({object=root.handle},{__index=function(_,key)
   local value=nativeScript[key]
   if type(value)=='function'then return function(_,...)return value(nativeScript,...)end end
   return value
  end,__newindex=function(_,key,value)nativeScript[key]=value end})
  rawset(script,'EnableUpdate',function(_,value)desired=value==true;schedule()end)
  local localHost={};for key,value in pairs(host)do localHost[key]=value end
  localHost.script,localHost.game,localHost.uiLifecycle=script,facade,R;R.host,R.game=localHost,facade
  local function bind(s,native)
   s.native,s.nativeId=native,nativeId(native);byNative[s.nativeId]=s.handle
   if s.poolable then remember(s,'active');remember(s,'visible')end
   local children=native:GetChildren()
   local count,mismatch=1,#children~=#s.builtins
   for i,child in ipairs(children)do
    -- Even a mismatched native tree must be fully owned before reporting the
    -- catalog error, so normal close can reclaim it with the destruction budget.
    local logical=s.builtins[i]or createState(s)
    local n,bad=bind(logical,child);count=count+n;mismatch=mismatch or bad
   end
   return count,mismatch
  end
  local function apply(s,hidden)
   if s.retired then
    if not hidden then hide(s)end
    for _,child in ipairs(s.builtins)do apply(child,true)end
    if not s.reclaim then s.reclaim=true;destroyQueue[#destroyQueue+1]=s;destroying=destroying+1 end
   else
    -- A font-size change must respect the real template's lower bound, including
    -- a minimumFontSize change queued later in the same logical transaction.
    local minimum=s.operations.minimumFontSize
    if minimum and not minimum.obsolete then property(s,'minimumFontSize',minimum.value);minimum.obsolete=true end
    for _,job in ipairs(s.writes)do if not job.obsolete then
     if job.method then nativeCall(s,job.method,job.args)else property(s,job.key,job.value)end
    end end
    for _,row in ipairs(s.listeners)do if not row.applied then nativeCall(s,row.method,pack(row.event,row.callback));row.applied=true end end
    order(s);for _,child in ipairs(s.builtins)do apply(child)end
   end
   s.writes,s.operations={},{ }
  end
  function R.beginFrame()
   if active then fail('E_UI_LIFECYCLE_FRAME','A host frame is already active')end
   active=true;stats.frames=stats.frames+1;stats.lastFrameCreated,stats.lastFrameDestroyed=0,0
   stats.lastFrameAcquired,stats.lastFrameReleased=0,0
  end
  function R.endFrame()active=false;schedule()end
  function R.flush()
   if not active then return 0,0 end
   local added,removed=0,0
   while oldest and (not enabled or stats.frames-oldest.frame>=idleFrames)
    and stats.lastFrameDestroyed<LIMIT and stats.lastFrameReleased<LIMIT do
    local entry=oldest;unlink(entry)
    if entry.native.alive~=false then
     nativeGame.DestroyClientUIControl(entry.native);stats.destroyed=stats.destroyed+1
     stats.lastFrameDestroyed=stats.lastFrameDestroyed+1;removed=removed+1
    end
    stats.poolEvictions=stats.poolEvictions+1;stats.lastFrameReleased=stats.lastFrameReleased+1
   end
   while destroyHead<=#destroyQueue and stats.lastFrameDestroyed<LIMIT and stats.lastFrameReleased<LIMIT do
    local s=destroyQueue[destroyHead]
    if s.native.alive~=false then
     for _,child in ipairs(s.native:GetChildren())do if child.alive~=false then fail('E_UI_CONTROL_HIERARCHY','Refusing to destroy a native parent with live descendants')end end
     if enabled and s.poolable and stats.poolIdle<capacity then park(s)
     else
      nativeGame.DestroyClientUIControl(s.native)
      removed=removed+1;stats.destroyed=stats.destroyed+1;stats.lastFrameDestroyed=stats.lastFrameDestroyed+1
     end
    end
    stats.lastFrameReleased=stats.lastFrameReleased+1
    destroying=destroying-1;byNative[s.nativeId]=nil;s.native,s.nativeId=nil,nil
    s.defaults,s.current,s.calls=nil,nil,nil;s.listeners,s.children,s.builtins={},{},{}
    destroyQueue[destroyHead]=false;destroyHead=destroyHead+1
   end
   if destroyHead>#destroyQueue then destroyQueue,destroyHead={},1 end
   while enabled and createHead<=#createQueue do
    local s=createQueue[createHead]
    if s.queued then
     if s.descriptor.count>LIMIT-stats.lastFrameAcquired then break end
     local bucket=pools[s.templateKey]
     if not bucket and s.descriptor.count>LIMIT-stats.lastFrameCreated then break end
     if not s.parent.native then fail('E_UI_CONTROL_PARENT','Queued control parent has not materialized')end
     local recycled=s.poolable and take(s.templateKey)
     local native
     if recycled then
      native=recycled.native;s.defaults,s.current,s.calls=recycled.defaults,recycled.current,recycled.calls
      if s.parent~=root then native.parent=s.parent.native end
     else
      stats.poolMisses=stats.poolMisses+1
      native=nativeGame.InstantiateClientUIControl(s.template,s.parent.native)
     end
     if not native then fail('E_UI_TEMPLATE_MISSING','Native template '..tostring(s.template)..' could not be instantiated')end
     local count=s.descriptor.count
     stats.lastFrameAcquired=stats.lastFrameAcquired+count
     if not recycled then stats.created=stats.created+count;stats.lastFrameCreated=stats.lastFrameCreated+count;added=added+count end
     creating=creating-count;s.queued=false
     createQueue[createHead]=false;createHead=createHead+1
     local actual,mismatch=bind(s,native)
     if actual~=count then
      s.poolable=false;stats.created=stats.created+actual-count;stats.lastFrameCreated=stats.lastFrameCreated+actual-count;added=added+actual-count
      stats.lastFrameAcquired=stats.lastFrameAcquired+actual-count
     end
     stats.peakFrameCreated=math.max(stats.peakFrameCreated,stats.lastFrameCreated)
     if mismatch then fail('E_UI_TEMPLATE_MISMATCH','Native hierarchy differs from catalog for template '..tostring(s.template))end
     if recycled then reset(s)end
     apply(s)
    else createQueue[createHead]=false;createHead=createHead+1 end
   end
   if createHead>#createQueue then createQueue,createHead={},1 end
   stats.peakFrameCreated=math.max(stats.peakFrameCreated,stats.lastFrameCreated)
   stats.peakFrameDestroyed=math.max(stats.peakFrameDestroyed,stats.lastFrameDestroyed)
   stats.peakFrameAcquired=math.max(stats.peakFrameAcquired,stats.lastFrameAcquired)
   stats.peakFrameReleased=math.max(stats.peakFrameReleased,stats.lastFrameReleased)
   schedule();return added,removed
  end
  function R.pending()return pending()end
  function R.retired(handle)local s=type(handle)=='table'and rawget(handle,'_uiLifecycle');return s and s.owner==owner and s.retired==true or false end
  function R.setEnabled(value)
   enabled=value==true
   if not enabled then
    for i=createHead,#createQueue do local s=createQueue[i];if s and s.queued then detach(s);retire(s)end end
   end
   schedule()
  end
  function R.stats()
   local result={};for key,value in pairs(stats)do result[key]=value end
   result.pending= pending();result.pendingCreated=creating;result.pendingDestroyed=destroying+(not enabled and stats.poolIdle or 0);return result
  end
  return R
 end
 return M
end
