-- Selected, unhinted TrueType variation geometry. No bytecode, IO or native tools.
return function(deps)
 local S,MET,O=deps['assets.font_sfnt'],deps['assets.font_metrics'],deps['assets.font_outline'];local M={}
 local caps={axes=16,regions=4096,dataTables=1024,tuples=4095,points=65536,queries=4096,work=33554432}
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_VARIATION_SHAPE','Expected plain variation data')end end
 local function integer(v,a,b)if type(v)~='number'or v~=v or v%1~=0 or v<a or v>b then fail('E_FONT_VARIATION_SHAPE','Invalid variation integer')end;return v*1.0 end
 local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
 function M.open(bytes,origin,location,options)
  plain(location);if options==nil then options={}end;plain(options)
  for k in next,options do if k~='sfntLimits'and k~='outlineLimits'and k~='limits'then fail('E_FONT_VARIATION_SHAPE','Unknown variation option')end end
  local supplied=options.limits;if supplied==nil then supplied={}end;plain(supplied);for k in next,supplied do if not caps[k]then fail('E_FONT_VARIATION_SHAPE','Unknown variation limit')end end
  local cap={};for k,v in pairs(caps)do cap[k]=supplied[k]~=nil and integer(supplied[k],1,v)or v end
  local handle=S.openVariable(bytes,origin,options.sfntLimits);local sf=S.verifyVariableContainer(handle)
  local function bad(code,reason,tag,p)sf.bad(code,reason,sf.locations[tag]and sf.locations[tag]+1 or 1,p)end
  local used=0.0;local function charge(n,tag,p)used=used+n;if used>cap.work then bad('E_FONT_VARIATION_BUDGET','Variation work budget exceeded',tag,p)end;sf.charge(n)end
  for _,tag in ipairs({'cvar','MVAR','VVAR','VARC'})do if sf.tables[tag]then bad('E_FONT_VARIATION_UNSUPPORTED','Unsupported variation table '..tag,tag,1)end end
  local function read(tag,min)local a,b,c,d=sf.tableReader(tag,min);return a,b,c,d end
  local f16,f32,_,fb=read('fvar',16)
  if f16(1)~=1 or f16(3)~=0 or f16(7)~=2 or f16(11)~=20 then bad('E_FONT_VARIATION_UNSUPPORTED','Unsupported fvar format','fvar',1)end
  local axisCount,axisOffset,instances,instanceSize=f16(9),f16(5),f16(13),f16(15)
  if axisCount<1 or axisCount>cap.axes then bad('E_FONT_VARIATION_BUDGET','Axis count exceeds limit','fvar',9)end
  if axisOffset<16 or instanceSize~=axisCount*4+4 and instanceSize~=axisCount*4+6 then bad('E_FONT_VARIATION_TABLE','Invalid fvar record layout','fvar',5)end
  fb(axisOffset+1,axisCount*20+instances*instanceSize)
  local axes,coords,known,requested={}, {},{},{}
  local function fixed16(v)return math.floor(v*65536.0+.5)/65536.0 end
  local function fixed(p)local v=f32(p);if v>=2147483648.0 then v=v-4294967296.0 end;return v/65536 end
  for i=1,axisCount do
   local p=axisOffset+(i-1)*20+1;local tag=sf.tables.fvar:sub(p,p+3);local lo,default,hi=fixed(p+4),fixed(p+8),fixed(p+12)
   if not tag:match('^[%g ][%g ][%g ][%g ]$')or known[tag]or lo>default or default>hi or lo==hi or f16(p+16)&0xfffe~=0 then bad('E_FONT_VARIATION_TABLE','Invalid fvar axis','fvar',p)end
   local v=rawget(location,tag);if type(v)~='number'or v~=v or v<lo or v>hi then bad('E_FONT_VARIATION_LOCATION','Every axis needs an explicit in-range coordinate','fvar',p)end
   v=v*1.0;local effective=fixed16(v);local normal=effective==default and 0.0 or effective<default and fixed16((effective-default)/(default-lo))or fixed16((effective-default)/(hi-default))
   normal=math.max(-1,math.min(1,normal));axes[i]={tag=tag,minimum=lo,default=default,maximum=hi,requested=v,effective=effective,defaultNormalized=normal};coords[i]=normal;known[tag]=true;requested[tag]=v;charge(1,'fvar',p)
  end
  for k in next,location do if not known[k]then bad('E_FONT_VARIATION_LOCATION','Unknown axis coordinate','fvar',1)end end
  if sf.tables.avar then
   local a16,_,ai,ab=read('avar',8);if a16(1)~=1 or a16(3)~=0 or a16(5)~=0 or a16(7)~=axisCount then bad('E_FONT_VARIATION_UNSUPPORTED','Unsupported avar header','avar',1)end
   local p=9
   for i=1,axisCount do local n=a16(p);p=p+2;if n>4096 then bad('E_FONT_VARIATION_BUDGET','Axis map exceeds limit','avar',p-2)end;ab(p,n*4)
    local map,anchors={},{};local prevFrom,prevTo=-2,-2
    for j=1,n do local from,to=ai(p)/16384,ai(p+2)/16384
     if from< -1 or from>1 or to< -1 or to>1 or from<=prevFrom or to<prevTo then bad('E_FONT_VARIATION_TABLE','Invalid avar mapping','avar',p)end
     if (from==-1 or from==0 or from==1)and to==from then anchors[from]=true end
     map[j]={from,to};prevFrom,prevTo=from,to;p=p+4;charge(1,'avar',p)
    end
    if n>0 then if not anchors[-1]or not anchors[0]or not anchors[1]then bad('E_FONT_VARIATION_TABLE','Missing avar anchors','avar',p)end
     local x=coords[i];for j=1,n do if x==map[j][1]then coords[i]=map[j][2];break elseif j<n and x>map[j][1]and x<map[j+1][1]then local a,b=map[j],map[j+1];local ratio=fixed16((x-a[1])/(b[1]-a[1]));coords[i]=a[2]+fixed16(ratio*(b[2]-a[2]));break end end
    end;axes[i].avarMap=map
   end
  end
  local normalized,normalizedByTag={},{};for i,a in ipairs(axes)do coords[i]=math.floor(math.max(-1,math.min(1,coords[i]))*16384.0+.5)/16384.0;a.normalized=coords[i];normalized[i]=coords[i];normalizedByTag[a.tag]=coords[i]end
  local base=MET.parseBaseVariable(handle);local outlines=O.openBaseVariable(handle,{limits=options.outlineLimits})
  local g16,g32,gi,gb=read('gvar',20);local glyphCount=base.numGlyphs
  if g16(1)~=1 or g16(3)~=0 or g16(5)~=axisCount or g16(13)~=glyphCount or g16(15)&0xfffe~=0 then bad('E_FONT_VARIATION_TABLE','Invalid gvar header','gvar',1)end
  local sharedCount,sharedOffset,dataOffset=g16(7),g32(9),g32(17);if sharedCount>4096 then bad('E_FONT_VARIATION_BUDGET','Shared tuple count exceeds limit','gvar',7)end
  local long=g16(15)&1~=0;local headerEnd=20+(glyphCount+1)*(long and 4 or 2);gb(21,headerEnd-20);gb(sharedOffset+1,sharedCount*axisCount*2)
  if dataOffset<headerEnd or sharedCount>0 and sharedOffset<headerEnd then bad('E_FONT_VARIATION_TABLE','gvar data overlaps header','gvar',9)end
  local function tuple(reader,p,bias)local a={};for i=1,axisCount do local x=reader(p)/16384;if x< -1 or x>1 then bad('E_FONT_VARIATION_TABLE','Tuple outside normalized range','gvar',p+(bias or 0))end;a[i]=x;p=p+2 end;return a,p end
  local shared={};for i=1,sharedCount do shared[i]=tuple(gi,sharedOffset+(i-1)*axisCount*2+1)end
  local offsets={};local previous=0
  for id=0,glyphCount do local off=long and g32(21+id*4)or g16(21+id*2)*2;if off<previous then bad('E_FONT_VARIATION_TABLE','Unordered glyph variation offsets','gvar',21+id*(long and 4 or 2))end;gb(dataOffset+off+1,0);offsets[id+1]=off;previous=off;charge(1,'gvar',21)end
  if sharedCount>0 and previous>0 and sharedOffset<dataOffset+previous and dataOffset<sharedOffset+sharedCount*axisCount*2 then bad('E_FONT_VARIATION_TABLE','Shared tuple data overlaps glyph variation data','gvar',9)end
  local function scalar(peak,start,finish,tag,pos)
   if start then for i=1,axisCount do local p=peak[i];if start[i]>p or p>finish[i]or p~=0 and start[i]<0 and finish[i]>0 then bad('E_FONT_VARIATION_TABLE','Invalid intermediate region',tag or 'gvar',pos or 1)end end end
   local result=1.0;for i=1,axisCount do local p,x=peak[i],coords[i]
    if p~=0 then
     local factor
     if start then local a,b=start[i],finish[i]
      if x<a or x>b then return 0 elseif x==p then factor=1 elseif x<p then factor=(x-a)/(p-a)else factor=(b-x)/(b-p)end
     else if x==0 or x*p<0 then return 0 end;factor=math.min(1,x/p)end
     result=result*factor
    end
   end;return result
  end
  local hvar
  if sf.tables.HVAR then
   local head16=read('head',54);if head16(17)&2==0 then bad('E_FONT_VARIATION_TABLE','HVAR TrueType requires head left-sidebearing flag','head',17)end
   local h16,h32,hi,hb=read('HVAR',20);if h16(1)~=1 or h16(3)~=0 then bad('E_FONT_VARIATION_UNSUPPORTED','Unsupported HVAR version','HVAR',1)end
   local so=h32(5);hb(so+1,8);if so<20 or h16(so+1)~=1 then bad('E_FONT_VARIATION_TABLE','Invalid HVAR variation store','HVAR',5)end
   local relativeRegion=h32(so+3);local ro=so+relativeRegion;local dc=h16(so+7);if dc>cap.dataTables then bad('E_FONT_VARIATION_BUDGET','HVAR data count exceeds limit','HVAR',so+7)end
   if relativeRegion<8+dc*4 then bad('E_FONT_VARIATION_TABLE','HVAR region offset targets store header','HVAR',so+3)end;hb(so+9,dc*4);hb(ro+1,4)
   local rc=h16(ro+3);if h16(ro+1)~=axisCount or rc>cap.regions then bad('E_FONT_VARIATION_TABLE','Invalid HVAR region list','HVAR',ro+1)end;hb(ro+5,rc*axisCount*6)
   local scalars={};for r=1,rc do local start,peak,finish={},{},{};for i=1,axisCount do local p=ro+5+((r-1)*axisCount+i-1)*6;start[i],peak[i],finish[i]=hi(p)/16384,hi(p+2)/16384,hi(p+4)/16384
     if start[i]< -1 or finish[i]>1 or start[i]>peak[i]or peak[i]>finish[i]then bad('E_FONT_VARIATION_TABLE','Invalid HVAR region','HVAR',p)end
    end;scalars[r]=scalar(peak,start,finish,'HVAR',ro+5+(r-1)*axisCount*6);charge(axisCount,'HVAR',ro+1)
   end
   local datas={};for i=1,dc do local off=h32(so+9+(i-1)*4)
    if off~=0 then if off<8+dc*4 then bad('E_FONT_VARIATION_TABLE','HVAR item offset targets store header','HVAR',so+9+(i-1)*4)end;local p=so+off;hb(p+1,6);local items,words,regions=h16(p+1),h16(p+3),h16(p+5)
     if words&0x8000~=0 then bad('E_FONT_VARIATION_UNSUPPORTED','HVAR long-word deltas are unsupported','HVAR',p+3)end
     if words>regions or regions>rc then bad('E_FONT_VARIATION_TABLE','Invalid HVAR delta row','HVAR',p+3)end;hb(p+7,regions*2+items*(regions+words))
     local refs={};for j=1,regions do local ref=h16(p+7+(j-1)*2);if ref>=rc then bad('E_FONT_VARIATION_TABLE','Invalid HVAR region index','HVAR',p+7)end;refs[j]=ref+1 end
     datas[i]={items=items,words=words,regions=regions,refs=refs,offset=p+7+regions*2,stride=regions+words};charge(regions+1,'HVAR',p+1)
    end
   end
   local function indexMap(off)
    if off==0 then return nil end;if off<20 or off>=so and off<so+8+dc*4 then bad('E_FONT_VARIATION_TABLE','HVAR index map targets a header','HVAR',off+1)end;hb(off+1,4);local format,entry=sf.tables.HVAR:byte(off+1,off+2)
    if format~=0 or entry&0xc0~=0 then bad('E_FONT_VARIATION_UNSUPPORTED','Unsupported HVAR index map','HVAR',off+1)end
    local n=h16(off+3);if n==0 then bad('E_FONT_VARIATION_TABLE','Empty HVAR index map','HVAR',off+3)end
    local size=(entry>>4)+1;local bits=(entry&15)+1;hb(off+5,n*size);local out={}
    for i=1,n do local v=0.0;for j=1,size do v=v*256+sf.tables.HVAR:byte(off+4+(i-1)*size+j)end;out[i]={math.floor(v/2^bits),v%2^bits};charge(1,'HVAR',off+5)end;return out
   end
   local maps={advance=indexMap(h32(9)),lsb=indexMap(h32(13)),rsb=indexMap(h32(17))}
   hvar=function(id,kind)
    local map=maps[kind];if kind~='advance'and not map then return nil end
    local outer,inner=0,id;if map then local pair=map[math.min(id+1,#map)];outer,inner=pair[1],pair[2]end
    if outer==65535 and inner==65535 then return 0 end
    if outer>=dc then bad('E_FONT_VARIATION_TABLE','Invalid HVAR outer index','HVAR',so+1)end
    local d=datas[outer+1];if not d then return 0 end;if inner>=d.items then bad('E_FONT_VARIATION_TABLE','Invalid HVAR inner index','HVAR',d.offset)end
    local p=d.offset+inner*d.stride;local total=0.0;for j=1,d.regions do local delta;if j<=d.words then delta=hi(p);p=p+2 else delta=sf.tables.HVAR:byte(p);if delta>=128 then delta=delta-256 end;p=p+1 end;total=total+delta*scalars[d.refs[j]];charge(1,'HVAR',p)end;return total
   end
  end
  local queries=0;local Q={axes=copy(axes),normalized=copy(normalized),normalizedByTag=copy(normalizedByTag),location=copy(requested),unitsPerEm=base.unitsPerEm,numGlyphs=glyphCount,
   source={file=sf.file,bytes=#bytes,container=sf.container,variationApplied=true,hvarApplied=hvar~=nil,hintingApplied=false,layoutVariationsApplied=false,verticalMetricsApplied=false}}
  function Q.baseMetrics()return copy(base)end
  function Q.glyph(id)
   id=integer(id,0,glyphCount-1);queries=queries+1;if queries>cap.queries then bad('E_FONT_VARIATION_BUDGET','Selected glyph query limit exceeded','gvar',1)end
   local out=outlines.glyph(id);if out.sourceKind=='compound'then bad('E_FONT_VARIATION_UNSUPPORTED','Composite glyph variation is unsupported','glyf',1)end
   if out.pointCount>cap.points then bad('E_FONT_VARIATION_BUDGET','Selected glyph point limit exceeded','glyf',1)end
   charge(out.pointCount+4,'glyf',1)
   local points,ends={},{};for _,c in ipairs(out.contours)do for _,p in ipairs(c.points)do points[#points+1]=p end;ends[#ends+1]=#points end
   local n=#points;local metric=base.glyphs[id+1];local left=(out.declaredBounds and out.declaredBounds.xMin or 0)-metric.leftSideBearing
   points[n+1]={x=left,y=0};points[n+2]={x=left+metric.advanceUnits,y=0};points[n+3]={x=0,y=0};points[n+4]={x=0,y=0}
   local dx,dy={},{};for i=1,n+4 do dx[i],dy[i]=0.0,0.0 end
   local a,z=offsets[id+1],offsets[id+2]
   if z>a then
    charge(z-a,'gvar',dataOffset+a+1)
    local raw=sf.tables.gvar:sub(dataOffset+a+1,dataOffset+z);local u16,_,i16,bounds=sf.reader(raw,sf.locations.gvar,dataOffset+a)
    local packed,serialized=u16(1),u16(3);if packed&0x7000~=0 then bad('E_FONT_VARIATION_TABLE','Reserved glyph tuple flags','gvar',dataOffset+a+1)end
    local count=packed&0xfff;if count<1 or count>cap.tuples then bad('E_FONT_VARIATION_BUDGET','Glyph tuple count exceeds limit','gvar',dataOffset+a+1)end
    local headers,p={},5;for k=1,count do local length,index=u16(p),u16(p+2);p=p+4
     if index&0x1000~=0 then bad('E_FONT_VARIATION_TABLE','Reserved tuple flag','gvar',dataOffset+a+p)end
     local peak,start,finish;if index&0x8000~=0 then peak,p=tuple(i16,p,dataOffset+a)else peak=shared[(index&0xfff)+1];if not peak then bad('E_FONT_VARIATION_TABLE','Missing shared tuple','gvar',dataOffset+a+p)end end
     if index&0x4000~=0 then start,p=tuple(i16,p,dataOffset+a);finish,p=tuple(i16,p,dataOffset+a)end
     headers[k]={length=length,private=index&0x2000~=0,scalar=scalar(peak,start,finish,'gvar',dataOffset+a+p)};charge(axisCount,'gvar',dataOffset+a+p)
    end
    if serialized+1<p then bad('E_FONT_VARIATION_TABLE','Serialized tuple data overlaps headers','gvar',dataOffset+a+3)end;bounds(serialized+1,0);p=serialized+1
    local function packedPoints(pos,last)
     local function byte()if pos>last then bad('E_FONT_VARIATION_BOUNDS','Truncated packed point data','gvar',dataOffset+a+pos)end;local b=raw:byte(pos);pos=pos+1;return b end
     local count=byte();if count==0 then return false,pos end;if count&128~=0 then count=(count&127)*256+byte()end
     local list={};local value=0.0;while #list<count do local control=byte();local num=(control&127)+1;if #list+num>count then bad('E_FONT_VARIATION_TABLE','Packed point run exceeds count','gvar',dataOffset+a+pos)end
      for j=1,num do local d=byte();if control&128~=0 then d=d*256+byte()end;value=value+d;if value>=n+4 then bad('E_FONT_VARIATION_TABLE','Packed point outside glyph','gvar',dataOffset+a+pos)end;list[#list+1]=value+1;charge(1,'gvar',dataOffset+a+pos)end
     end;return list,pos
    end
    local sharedPoints=false;if packed&0x8000~=0 then sharedPoints,p=packedPoints(p,#raw)end
    local function deltas(pos,last,count)
     local out={};while #out<count do if pos>last then bad('E_FONT_VARIATION_BOUNDS','Truncated packed delta data','gvar',dataOffset+a+pos)end;local control=raw:byte(pos);pos=pos+1;local num=(control&63)+1
      if #out+num>count then bad('E_FONT_VARIATION_TABLE','Packed delta run exceeds count','gvar',dataOffset+a+pos)end
      for j=1,num do local d=0;if control&128==0 then local size=control&64~=0 and 2 or 1;if pos+size-1>last then bad('E_FONT_VARIATION_BOUNDS','Truncated delta value','gvar',dataOffset+a+pos)end
       if size==2 then d=i16(pos)else d=raw:byte(pos);if d>=128 then d=d-256 end end;pos=pos+size
      end;out[#out+1]=d;charge(1,'gvar',dataOffset+a+pos)end
     end;return out,pos
    end
    local function infer(values,key)
     local first=1;for _,last in ipairs(ends)do local refs={};for i=first,last do if values[i]~=nil then refs[#refs+1]=i end end
      if #refs>0 then for j=1,#refs do local r,s=refs[j],refs[j%#refs+1];local from,to=points[r][key],points[s][key];local dr,ds=values[r],values[s]
       local i=r==last and first or r+1;while i~=s do local x=points[i][key];local d
        if from==to then d=dr==ds and dr or 0 elseif x<=math.min(from,to)then d=from<to and dr or ds elseif x>=math.max(from,to)then d=from>to and dr or ds else d=dr+(x-from)/(to-from)*(ds-dr)end
        values[i]=d;i=i==last and first or i+1;charge(1,'gvar',dataOffset+a+1)
       end
      end end;first=last+1
     end
    end
    for _,h in ipairs(headers)do local last=p+h.length-1;bounds(p,h.length);local selected=sharedPoints
     if h.private then selected,p=packedPoints(p,last)end
     local amount=selected and #selected or n+4;local xs,ys;xs,p=deltas(p,last,amount);ys,p=deltas(p,last,amount)
     if p~=last+1 then bad('E_FONT_VARIATION_TABLE','Trailing tuple serialized bytes','gvar',dataOffset+a+p)end
     local vx,vy={},{};for i=1,amount do local target=selected and selected[i]or i;vx[target]=(vx[target]or 0)+xs[i];vy[target]=(vy[target]or 0)+ys[i]end
     infer(vx,'x');infer(vy,'y');for i=1,n+4 do dx[i]=dx[i]+(vx[i]or 0)*h.scalar;dy[i]=dy[i]+(vy[i]or 0)*h.scalar;charge(1,'gvar',dataOffset+a+p)end
    end
    for at=p,#raw do if raw:byte(at)~=0 then bad('E_FONT_VARIATION_TABLE','Unexpected glyph variation padding','gvar',dataOffset+a+at)end end
   end
   local bbox;for i=1,n do local p=points[i];p.x=p.x+dx[i];p.y=p.y+dy[i];if not bbox then bbox={xMin=p.x,yMin=p.y,xMax=p.x,yMax=p.y}else bbox.xMin=math.min(bbox.xMin,p.x);bbox.yMin=math.min(bbox.yMin,p.y);bbox.xMax=math.max(bbox.xMax,p.x);bbox.yMax=math.max(bbox.yMax,p.y)end end
   local rawAdvance=hvar and metric.advanceUnits+hvar(id,'advance')or metric.advanceUnits+dx[n+2]-dx[n+1]
   local lsbDelta=hvar and hvar(id,'lsb');local rawLsb=lsbDelta and metric.leftSideBearing+lsbDelta or (bbox and bbox.xMin or 0)-(left+dx[n+1])
   local rsbDelta=hvar and hvar(id,'rsb');local defaultWidth=out.declaredBounds and out.declaredBounds.xMax-out.declaredBounds.xMin or 0
   local rawRsb=rsbDelta and metric.advanceUnits-metric.leftSideBearing-defaultWidth+rsbDelta or rawAdvance-rawLsb-(bbox and bbox.xMax-bbox.xMin or 0)
   out.bounds=bbox;out.variableBase=nil;out.variationApplied=true;out.location=copy(requested);out.normalized=copy(normalized)
   out.metrics={glyphId=id,advanceUnits=math.max(0,math.floor(rawAdvance+.5)),advanceUnrounded=rawAdvance,leftSideBearing=math.floor(rawLsb+.5),leftSideBearingUnrounded=rawLsb,rightSideBearing=math.floor(rawRsb+.5),rightSideBearingUnrounded=rawRsb,variationApplied=true,hvarApplied=hvar~=nil}
   out.source={file=sf.file,declaredBoundsFromDefault=true};return out
  end
  function Q.metrics(id)return Q.glyph(id).metrics end
  function Q.stats()return{queries=queries,work=used,containerWork=sf.stats.workReserved}end
  return Q
 end
 return M
end
