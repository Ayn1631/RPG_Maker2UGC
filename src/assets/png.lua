-- Offline, finite PNG subset. No filesystem, host image API or executable metadata.
return function(deps)
 local inflate=deps['vendor.libdeflate'];local M={}
 local caps={inputBytes=16777216,pixels=1048576,inflatedBytes=8388608,work=33554432}
 local function fail(code,reason,offset)error({severity='error',code=code,reason=reason,offset=offset or 1},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_PNG_SHAPE','Expected plain limits')end end
 local function limits(v)
  if v==nil then v={}end;plain(v);for k in next,v do if caps[k]==nil then fail('E_PNG_LIMIT','Unknown limit')end end
  local out={};for k,max in pairs(caps)do local n=rawget(v,k);if n==nil then n=max end;if type(n)~='number' or n%1~=0 or n<1 or n>max then fail('E_PNG_LIMIT','Limit must be a positive integer no larger than default')end;out[k]=n*1.0 end;return out
 end
 local crcTable={};for n=0,255 do local c=n;for _=1,8 do c=(c&1)==1 and ((c>>1)~0xedb88320) or (c>>1)end;crcTable[n]=c end
 local function u32(s,p)local a,b,c,d=s:byte(p,p+3);return a*16777216.0+b*65536.0+c*256.0+d end
 -- Offline RGBA encoder. Filter 0 keeps the writer small; zlib still compresses rows.
 function M.encode(image)
  plain(image)
  local w,h,rgba=image.width,image.height,image.rgba
  if type(w)~='number' or type(h)~='number' or w%1~=0 or h%1~=0 or w<1 or h<1 or w>4096 or h>4096 or w*h>caps.pixels
   or type(rgba)~='string' or #rgba~=w*h*4 then fail('E_PNG_SHAPE','Expected bounded RGBA image')end
  local function chunk(kind,data)
   local value=kind..data;local crc=0xffffffff
   for i=1,#value do crc=(crc>>8)~crcTable[(crc~value:byte(i))&255]end
   return string.pack('>I4',#data)..value..string.pack('>I4',crc~0xffffffff)
  end
  local rows={};for y=0,h-1 do rows[#rows+1]='\0'..rgba:sub(y*w*4+1,(y+1)*w*4)end
  return '\137PNG\13\10\26\10'..chunk('IHDR',string.pack('>I4I4BBBBB',w,h,8,6,0,0,0))
   ..chunk('IDAT',inflate:CompressZlib(table.concat(rows),{level=1}))..chunk('IEND','')
 end
 function M.decode(bytes,options)
  if type(bytes)~='string'then fail('E_PNG_SHAPE','PNG input must be a byte string')end
  local limit=limits(options);if #bytes>limit.inputBytes then fail('E_PNG_BUDGET','PNG input byte limit exceeded')end
  local work=0.0;local function charge(n)work=work+n;if work>math.floor(limit.work/2)then fail('E_PNG_BUDGET','PNG work limit exceeded')end end
  if bytes:sub(1,8)~='\137PNG\13\10\26\10'then fail('E_PNG_FORMAT','Invalid PNG signature')end
  local function check(ok,reason,p,code)if not ok then fail(code or 'E_PNG_FORMAT',reason,p)end end
  local p,w,h,kind,depth=9;local palette,alpha;local idats={};local began,ended,finished=false,false,false;local expected,idatOffset;local chunkCount=0
  while p<=#bytes do
   local start=p;check(#bytes-p+1>=12,'Truncated PNG chunk',p);local length=u32(bytes,p);check(length<2147483648 and length<=#bytes-p-11,'Invalid PNG chunk length',p)
   local name=bytes:sub(p+4,p+7);check(name:match('^[A-Za-z][A-Za-z][A-Z][A-Za-z]$')~=nil,'Invalid PNG chunk name',p+4)
   chunkCount=chunkCount+1;check(chunkCount<=4096,'Too many PNG chunks',p,'E_PNG_BUDGET');charge(length+12.0)
   local crc=0xffffffff;for i=p+4,p+7+length do crc=(crc>>8)~crcTable[(crc~bytes:byte(i))&255]end;crc=crc~0xffffffff;if crc<0 then crc=crc+4294967296.0 end
   check(crc==u32(bytes,p+8+length),'PNG CRC mismatch',p,'E_PNG_CRC');local payload=p+8;p=p+length+12
   if chunkCount==1 then check(name=='IHDR','IHDR must be first',start)end
   if name=='IHDR'then
    check(w==nil and length==13,'Invalid or duplicate IHDR',start);w,h=u32(bytes,payload),u32(bytes,payload+4);depth,kind=bytes:byte(payload+8,payload+9)
    check(w>0 and h>0 and w<=4096 and h<=4096 and w*h<=limit.pixels,'PNG dimensions/pixels exceed limit',start,'E_PNG_BUDGET')
    check(depth==8 and (kind==3 or kind==6) and bytes:byte(payload+10)==0 and bytes:byte(payload+11)==0 and bytes:byte(payload+12)==0,'Only 8-bit indexed/RGBA non-interlaced PNG is supported',start,'E_PNG_UNSUPPORTED')
    expected=h*(1.0+w*(kind==3 and 1 or 4));check(expected<=limit.inflatedBytes,'Filtered PNG output exceeds limit',start,'E_PNG_BUDGET')
   elseif name=='PLTE'then
    check(not began and not palette and length>0 and length<=768 and length%3==0,'Invalid PLTE or chunk order',start);palette=bytes:sub(payload,payload+length-1)
   elseif name=='tRNS'then
    check(kind==3 and palette and not alpha and not began and length>0 and length<=#palette/3,'Invalid tRNS or chunk order',start);alpha=bytes:sub(payload,payload+length-1)
   elseif name=='IDAT'then
    check(not ended and (kind~=3 or palette~=nil),'Invalid IDAT sequence or missing palette',start);began=true;idatOffset=idatOffset or start;idats[#idats+1]=bytes:sub(payload,payload+length-1)
   elseif name=='IEND'then
    check(length==0 and began and p==#bytes+1,'Invalid IEND or trailing data',start);finished=true;break
   else
    check(name~='acTL' and name~='fcTL' and name~='fdAT','Animated PNG is not supported',start,'E_PNG_UNSUPPORTED')
    check(name:byte(1)>=97,'Unsupported critical PNG chunk',start,'E_PNG_UNSUPPORTED')
   end
   if began and name~='IDAT'then ended=true end
  end
  check(finished,'Missing IEND',p)
  local ok,raw,left=pcall(inflate.DecompressZlib,inflate,table.concat(idats),expected,math.floor(limit.work/2))
  if not ok then if type(raw)=='table' and raw.code=='E_INFLATE_BUDGET'then fail('E_PNG_BUDGET',raw.reason,idatOffset)end;fail('E_PNG_INFLATE','Zlib decoder failed',idatOffset)end
  check(raw~=nil,'Invalid zlib stream or Adler32',idatOffset,'E_PNG_INFLATE');check(left==0 and #raw==expected,'Unexpected inflated size or trailing zlib data',idatOffset,'E_PNG_INFLATE')
  local channels=kind==3 and 1 or 4;local stride=w*channels;local previous={};local output={};local q=1
  local function paeth(a,b,c)local v=a+b-c;local x,y,z=math.abs(v-a),math.abs(v-b),math.abs(v-c);return x<=y and x<=z and a or y<=z and b or c end
  for _=1,h do
   local filter=raw:byte(q);q=q+1;check(filter<=4,'Unknown PNG scanline filter',idatOffset);local row={};charge(stride+w)
   for x=1,stride do local a=x>channels and row[x-channels] or 0;local b=previous[x] or 0;local c=x>channels and (previous[x-channels] or 0) or 0
    local predictor=filter==0 and 0 or filter==1 and a or filter==2 and b or filter==3 and math.floor((a+b)/2) or paeth(a,b,c)
    row[x]=(raw:byte(q)+predictor)%256;q=q+1
   end
   for x=1,w do
    if kind==6 then local i=(x-1)*4+1;output[#output+1]=string.char(row[i],row[i+1],row[i+2],row[i+3])
    else local i=row[x];check(i<#palette/3,'Palette index outside PLTE',idatOffset);local r,g,b=palette:byte(i*3+1,i*3+3);output[#output+1]=string.char(r,g,b,alpha and alpha:byte(i+1) or 255)end
   end;previous=row
  end
  return{width=w,height=h,rgba=table.concat(output),colorType=kind,bitDepth=depth}
 end
 return M
end
