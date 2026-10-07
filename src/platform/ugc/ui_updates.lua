-- Coalesce writes within one render transaction; unchanged host values cost zero writes.
return function(deps)
 local textLimit=deps['runtime.ui.text_limit']
 local M={}
 local function equalArgs(a,n,...)
  if not a or a.n~=n then return false end
  for i=1,n do if a[i]~=select(i,...)then return false end end;return true
 end
 local function equal(a,b)
  if not a or a.n~=b.n then return false end
  for i=1,b.n do if a[i]~=b[i]then return false end end;return true
 end
 function M.new(isRetired)
  local applied,pending,queue={},{},{};local tracked,pruneIndex={},1;local depth=0;local failedJob
  local stats={requested=0,submitted=0,unchanged=0,coalesced=0,flushes=0}
  local B={}
  local function cached(object,key,n,...)
   stats.requested=stats.requested+1
   local p=pending[object];local job=p and p[key]
   local previous=job and job.values or applied[object] and applied[object][key]
   if equalArgs(previous,n,...)then stats.unchanged=stats.unchanged+1;return true end
   return false
  end
  local function enqueue(object,key,values,method,value)
   local p=pending[object];local job=p and p[key]
   if job then job.values,job.method,job.value=values,method,value;stats.coalesced=stats.coalesced+1
   else p=p or {};pending[object]=p;job={object=object,key=key,values=values,method=method,value=value};p[key]=job;queue[#queue+1]=job end
   if depth==0 then B.flush()end
  end
  function B.begin()depth=depth+1 end
  function B.call(object,name,...)
   local key,n='@'..name,select('#',...)
   if cached(object,key,n,...)then return end
   enqueue(object,key,{n=n,...},name)
  end
  function B.set(object,key,value,stamp)
   if key=='text'then value=textLimit.clip(value)end
   -- Normalize before comparison so fractional layout changes do not enqueue
   -- redundant writes to the same integer host font size.
   if key=='fontSize'then value=math.max(object.minimumFontSize or 1,math.floor(value))end
   local signature=stamp;if stamp==nil then signature=value end
   if cached(object,key,1,signature)then return end
   enqueue(object,key,{n=1,signature},nil,value)
  end
  function B.flush()
   if depth>0 then depth=depth-1;if depth>0 then return end end
   if #queue==0 then return end;stats.flushes=stats.flushes+1
   local batch=queue;queue={};pending={}
   for _,job in ipairs(batch)do
    if job.object.alive~=false and not(isRetired and isRetired(job.object))then
     local cache=applied[job.object]
     if not cache then cache={};applied[job.object]=cache;tracked[#tracked+1]=job.object end
     if not equal(cache[job.key],job.values)then
      failedJob=job
      if job.method then job.object[job.method](job.object,table.unpack(job.values,1,job.values.n))else job.object[job.key]=job.value end
      failedJob=nil;cache[job.key]=job.values;stats.submitted=stats.submitted+1
     else stats.unchanged=stats.unchanged+1 end
    end
   end
  end
  function B.prune()
   -- Native property reads also cross the host bridge. Bound cleanup work
   -- per frame instead of polling every cached control on every update.
   local remaining=math.min(32,#tracked)
   while remaining>0 and #tracked>0 do
    if pruneIndex>#tracked then pruneIndex=1 end
    local object=tracked[pruneIndex]
    if object.alive==false then
     applied[object]=nil;tracked[pruneIndex]=tracked[#tracked];tracked[#tracked]=nil
    else pruneIndex=pruneIndex+1 end
    remaining=remaining-1
   end
  end
  function B.failureContext()
   if not failedJob then return nil end
   local ok,name=pcall(function()return failedJob.object.name end)
   return 'control='..(ok and tostring(name) or '<unavailable>')..' operation='..failedJob.key
  end
  function B.clear()applied,pending,queue={},{},{};tracked,pruneIndex={},1;depth=0;failedJob=nil end
  function B.stats()local copy={};for k,v in pairs(stats)do copy[k]=v end;return copy end
  return B
 end
 return M
end
