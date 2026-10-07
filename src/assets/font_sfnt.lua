-- Desktop-only bounded sfnt/WOFF1 container. Returned readers are not serialized IR.
return function(deps)
 local inflate=deps['vendor.libdeflate'];local M={}
 local caps={inputBytes=8388608,tables=128,expandedBytes=33554432,mappings=262144,glyphs=65535,work=2147483648.0,textBytes=1048576,textGlyphs=100000}
 local function fail(code,reason,offset,file,tableOffset)error({severity='error',code=code,reason=reason,offset=offset or 1,file=file,tableOffset=tableOffset},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_FONT_SHAPE','Expected plain font data')end end
 local function integer(v,lo,hi)if type(v)~='number' or v~=v or v%1~=0 or v<lo or v>hi then fail('E_FONT_SHAPE','Invalid font integer')end;return v*1.0 end
 local variableRegistry=setmetatable({},{__mode='k'})
 local function open(bytes,origin,limits,variable)
  if type(bytes)~='string'then fail('E_FONT_SHAPE','Font input must be bytes')end
  if origin==nil then origin={}end;plain(origin);for k in next,origin do if k~='file'then fail('E_FONT_SHAPE','Unknown font origin field')end end
  local file=origin.file;if file~=nil and (type(file)~='string' or #file>4096)then fail('E_FONT_SHAPE','Invalid font source file')end
  local function bad(code,reason,p,q)fail(code,reason,p,file,q)end
  if limits==nil then limits={}end;plain(limits);for k in next,limits do if not caps[k]then bad('E_FONT_SHAPE','Unknown font limit')end end
  local cap={};for k,v in pairs(caps)do
   if variable and k=='inputBytes'then v=33554432 elseif variable and k=='expandedBytes'then v=67108864 end
   cap[k]=limits[k]~=nil and integer(limits[k],1,v) or v
  end
  if #bytes>cap.inputBytes then bad('E_FONT_BUDGET','Font input byte budget exceeded')end
  local stats={workReserved=0.0};local function charge(n)
   if type(n)~='number' or n~=n or n%1~=0 or n<0 or n>9007199254740991 then bad('E_FONT_SHAPE','Invalid font work charge')end
   stats.workReserved=stats.workReserved+n;if stats.workReserved>cap.work then bad('E_FONT_BUDGET','Font work budget exceeded')end end
  local function reader(s,base,bias)
   local function bounds(p,n)if p<1 or p+n-1>#s then bad('E_FONT_BOUNDS','Truncated font structure',base and base+1 or p,base and p+(bias or 0))end end
   local function u16(p)bounds(p,2);local a,b=s:byte(p,p+1);return a*256.0+b end
   local function u32(p)bounds(p,4);local a,b,c,d=s:byte(p,p+3);return a*16777216.0+b*65536.0+c*256.0+d end
   local function i16(p)local n=u16(p);return n>=32768 and n-65536 or n end
   return u16,u32,i16,bounds
  end
  local function checksum(s,head)
   local sum=0.0;for p=1,#s,4 do charge(1);local a,b,c,d=s:byte(p,p+3);local value=(a or 0)*16777216.0+(b or 0)*65536.0+(c or 0)*256.0+(d or 0)
    if head and p==9 then value=0 end;sum=(sum+value)%4294967296.0
   end;return sum
  end
  local u16,u32,_,bounds=reader(bytes);bounds(1,4);local signature=bytes:sub(1,4);local woff=signature=='wOFF'
  if not woff and u32(1)~=65536 then bad('E_FONT_UNSUPPORTED','Only WOFF1 or single TrueType sfnt is supported')end
  bounds(1,woff and 44 or 12);if woff and u32(5)~=65536 then bad('E_FONT_UNSUPPORTED','WOFF flavor is not TrueType glyf',5)end
  local n=u16(woff and 13 or 5);if n<1 or n>cap.tables then bad('E_FONT_BUDGET','Font table count exceeds limit',woff and 13 or 5)end
  local header=(woff and 44 or 12)+n*(woff and 20 or 16);bounds(1,header)
  if woff then if u32(9)~=#bytes or u16(15)~=0 then bad('E_FONT_HEADER','Invalid WOFF length or reserved field',9)end
  else local power,selector=1,0;while power*2<=n do power=power*2;selector=selector+1 end;if u16(7)~=power*16 or u16(9)~=selector or u16(11)~=n*16-power*16 then bad('E_FONT_HEADER','Invalid sfnt search fields',7)end end
  local entries,ranges,seen={}, {},{};local expanded,sfntSize=0.0,12+n*16
  for i=0,n-1 do local p=(woff and 45 or 13)+i*(woff and 20 or 16);local tag=bytes:sub(p,p+3)
   if not tag:match('^[%g ][%g ][%g ][%g ]$') or seen[tag]then bad('E_FONT_TABLE','Invalid or duplicate table tag',p)end;seen[tag]=true
   if not variable and (tag=='fvar' or tag=='avar' or tag=='cvar' or tag=='gvar' or tag=='HVAR' or tag=='MVAR' or tag=='VVAR') then bad('E_FONT_UNSUPPORTED','Unsupported font variation table '..tag,p)end
   local offset=u32(p+(woff and 4 or 8));local length=u32(p+(woff and 8 or 12));local original=woff and u32(p+12) or length;local sum=u32(p+(woff and 16 or 4))
   if offset<header or offset%4~=0 or length>original then bad('E_FONT_TABLE','Invalid table offset or compressed length',p)end;bounds(offset+1,length)
   expanded=expanded+original;sfntSize=sfntSize+original+(-original)%4;if expanded>cap.expandedBytes then bad('E_FONT_BUDGET','Expanded table budget exceeded',p)end
   entries[#entries+1]={tag=tag,offset=offset,length=length,original=original,checksum=sum};if length>0 then ranges[#ranges+1]={offset,offset+length}end
  end
  if woff then
   if u32(17)~=sfntSize then bad('E_FONT_HEADER','WOFF totalSfntSize mismatch',17)end
   for _,p in ipairs({25,37})do local off,len=u32(p),u32(p+4);if off~=0 or len~=0 then if off<header or len==0 then bad('E_FONT_HEADER','Invalid auxiliary WOFF block',p)end;bounds(off+1,len);ranges[#ranges+1]={off,off+len}end end
   if (u32(25)==0)~=(u32(33)==0)then bad('E_FONT_HEADER','Invalid WOFF metadata original length',33)end
  end
  table.sort(ranges,function(a,b)return a[1]<b[1]end);for i=2,#ranges do if ranges[i][1]<ranges[i-1][2]then bad('E_FONT_TABLE','Overlapping font tables',ranges[i][1]+1)end end
  local tables,locations={},{}
  for _,e in ipairs(entries)do local data=bytes:sub(e.offset+1,e.offset+e.length)
   if e.length<e.original then
    local allowance=math.min(33554432.0,cap.work-stats.workReserved);if allowance<1 then bad('E_FONT_BUDGET','Inflater work budget exhausted',e.offset+1)end
    local ok,raw,left=pcall(inflate.DecompressZlib,inflate,data,e.original,allowance);stats.workReserved=stats.workReserved+allowance
    if not ok then bad(type(raw)=='table' and raw.code=='E_INFLATE_BUDGET' and 'E_FONT_BUDGET' or 'E_FONT_DEFLATE','Font table decompression failed',e.offset+1)end
    if type(raw)~='string' or left~=0 or #raw~=e.original then bad('E_FONT_DEFLATE','Invalid zlib data or expanded length',e.offset+1)end;data=raw
   end
   if checksum(data,e.tag=='head')~=e.checksum then bad('E_FONT_CHECKSUM','Font table checksum mismatch',e.offset+1)end;tables[e.tag]=data;locations[e.tag]=e.offset
  end
  if not woff and checksum(bytes,false)~=2981146554.0 then bad('E_FONT_CHECKSUM','sfnt whole-file checksum mismatch')end
  local function tableReader(name,min)
   local s=tables[name];if not s or #s<min then bad('E_FONT_TABLE','Missing or short '..name..' table',locations[name] and locations[name]+1 or 1)end
   return reader(s,locations[name])
  end
  stats.tables=n;stats.expandedBytes=expanded
  return{container=woff and 'woff1' or 'ttf',file=file,tables=tables,locations=locations,cap=cap,reader=reader,tableReader=tableReader,charge=charge,bad=bad,stats=stats}
 end
 function M.open(bytes,origin,limits)return open(bytes,origin,limits,false)end
 function M.openVariable(bytes,origin,limits)
  local internal=open(bytes,origin,limits,true)
  internal.variableBase=true;internal.variationApplied=false
  -- Opaque capability; no caller-owned table or function is trusted by parsers.
  local handle={kind='r2u.font-sfnt-variable-base',variationApplied=false}
  variableRegistry[handle]=internal;return handle
 end
 function M.verifyVariableContainer(handle)
  plain(handle);local internal=variableRegistry[handle]
  if not internal then fail('E_FONT_SHAPE','Expected original openVariable container')end
  -- Readers close over the original immutable byte strings. Each caller receives
  -- separate maps; modifying an inspection view cannot rewrite certified tables.
  local view={};for k,v in pairs(internal)do view[k]=v end
  for _,field in ipairs({'tables','locations','cap'})do local clone={};for k,v in pairs(internal[field])do clone[k]=v end;view[field]=clone end
  view.stats=setmetatable({},{__index=function(_,key)return internal.stats[key]end,
   __newindex=function()fail('E_FONT_SHAPE','Font statistics are read-only')end,__metatable='r2u.font-statistics',
   __pairs=function()return function(_,key)return next(internal.stats,key)end,nil,nil end})
  return view
 end
 return M
end
