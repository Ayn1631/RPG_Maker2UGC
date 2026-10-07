-- Offline TrueType metrics, not a shaper or a rasterizer. No IO or executable font data.
return function(deps)
 local sfnt=deps['assets.font_sfnt'];local M={};local SAFE=9007199254740991
 local caps={inputBytes=8388608,tables=128,expandedBytes=33554432,mappings=262144,glyphs=65535,work=2147483648.0,textBytes=1048576,textGlyphs=100000}
 local function fail(code,reason,offset,file,tableOffset)error({severity='error',code=code,reason=reason,offset=offset or 1,file=file,tableOffset=tableOffset},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_FONT_SHAPE','Expected plain font data')end end
 local function integer(v,lo,hi)if type(v)~='number' or v~=v or v%1~=0 or v<lo or v>hi then fail('E_FONT_SHAPE','Invalid font integer')end;return v*1.0 end
 local function dense(v)plain(v);local n,high=0,0;for k in next,v do integer(k,1,262144);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_FONT_SHAPE','Expected dense font array')end;return n end
 local function parseContainer(sf)
  local tables,locations,cap=sf.tables,sf.locations,sf.cap
  local reader,tableReader,charge,bad=sf.reader,sf.tableReader,sf.charge,sf.bad
  local h16,h32=tableReader('head',54);if h32(1)~=65536 or h32(13)~=1594834165 then bad('E_FONT_TABLE','Invalid TrueType head',locations.head+1)end
  local units=h16(19);if units<16 or units>16384 then bad('E_FONT_TABLE','Invalid unitsPerEm',locations.head+1)end
  local m16,m32=tableReader('maxp',32);local glyphCount=m16(5);if m32(1)~=65536 or glyphCount<1 then bad('E_FONT_TABLE','Invalid TrueType maxp',locations.maxp+1)end
  if glyphCount>cap.glyphs then bad('E_FONT_BUDGET','Glyph count budget exceeded',locations.maxp+1)end
  local a16,a32,aSigned=tableReader('hhea',36);local metricsCount=a16(35);if a32(1)~=65536 or metricsCount<1 or metricsCount>glyphCount then bad('E_FONT_TABLE','Invalid horizontal metrics count',locations.hhea+1)end
  if aSigned(33)~=0 then bad('E_FONT_TABLE','Unsupported hhea metric data format',locations.hhea+1)end
  local hm16,_,hmSigned=tableReader('hmtx',metricsCount*4+(glyphCount-metricsCount)*2);local locaFormat=h16(51)
  if (locaFormat~=0 and locaFormat~=1)or h16(53)~=0 then bad('E_FONT_TABLE','Unsupported glyph location format',locations.head+1)end
  local l16,l32=tableReader('loca',(glyphCount+1)*(locaFormat==0 and 2 or 4));tableReader('glyf',0);local previousLocation=0
  for i=0,glyphCount do local offset=locaFormat==0 and l16(i*2+1)*2 or l32(i*4+1);if offset<previousLocation or offset>#tables.glyf then bad('E_FONT_TABLE','Glyph location escapes glyf table',locations.loca+1)end;previousLocation=offset end
  local glyphs={};local lastAdvance
  for id=0,glyphCount-1 do charge(1);local advance,bearing;if id<metricsCount then advance=hm16(id*4+1);bearing=hmSigned(id*4+3);lastAdvance=advance else advance=lastAdvance;bearing=hmSigned(metricsCount*4+(id-metricsCount)*2+1)end;glyphs[#glyphs+1]={glyphId=id,advanceUnits=advance,leftSideBearing=bearing}end
  local c16,c32,_,cbounds=tableReader('cmap',4);if c16(1)~=0 then bad('E_FONT_CMAP','Invalid cmap version',locations.cmap+1)end
  local records=c16(3);if records>cap.tables then bad('E_FONT_BUDGET','Too many cmap encodings',locations.cmap+1)end;cbounds(1,4+records*8)
  local selected,rank,formats=nil,0,{}
  for i=0,records-1 do local p=5+i*8;local platform,encoding,off=c16(p),c16(p+2),c32(p+4);cbounds(off+1,2);local format=c16(off+1);formats[#formats+1]={platform=platform,encoding=encoding,format=format}
   local score=0;if format==12 and (platform==0 or platform==3 and encoding==10)then score=platform==3 and 4 or 3 elseif format==4 and (platform==0 or platform==3 and encoding==1)then score=platform==3 and 2 or 1 end
   if score>rank then selected={format=format,offset=off};rank=score end
  end
  if not selected then bad('E_FONT_UNSUPPORTED','No supported Unicode cmap4/12',locations.cmap+1)end
  local mappings={};local function add(cp,id)
   charge(1);if id<0 or id>=glyphCount then bad('E_FONT_CMAP','cmap glyph ID outside maxp',locations.cmap+1)end
   if id~=0 then if cp>1114111 or cp>=55296 and cp<=57343 then bad('E_FONT_CMAP','Mapping is not a Unicode scalar',locations.cmap+1)end;if #mappings>=cap.mappings then bad('E_FONT_BUDGET','Unicode mapping budget exceeded',locations.cmap+1)end;mappings[#mappings+1]={codepoint=cp,glyphId=id}end
  end
  local start=selected.offset+1;local length=selected.format==12 and c32(start+4) or c16(start+2);cbounds(start,length)
  local sub=tables.cmap:sub(start,start+length-1);local s16,s32,sSigned,sBounds=reader(sub,locations.cmap,start-1)
  if selected.format==12 then
   sBounds(1,16);if s16(3)~=0 then bad('E_FONT_CMAP','Invalid format12 reserved field',locations.cmap+1)end
   local groups=s32(13);if groups>cap.mappings or 16+groups*12~=length then bad('E_FONT_CMAP','Invalid format12 group count',locations.cmap+1)end;local previous=-1
   for i=0,groups-1 do local p=17+i*12;local first,last,id=s32(p),s32(p+4),s32(p+8);if first>last or first<=previous or last>1114111 or id+last-first>=glyphCount then bad('E_FONT_CMAP','Invalid format12 group',locations.cmap+1)end
    for cp=first,last do add(cp,id+cp-first)end;previous=last
   end
  else
   sBounds(1,16);local seg2=s16(7);if seg2==0 or seg2%2~=0 then bad('E_FONT_CMAP','Invalid format4 segment count',locations.cmap+1)end;local segments=seg2/2;sBounds(1,16+segments*8)
   local power,selector=1,0;while power*2<=segments do power=power*2;selector=selector+1 end
   if s16(9)~=power*2 or s16(11)~=selector or s16(13)~=segments*2-power*2 then bad('E_FONT_CMAP','Invalid format4 search fields',locations.cmap+1)end
   if s16(15+segments*2)~=0 then bad('E_FONT_CMAP','Invalid format4 padding',locations.cmap+1)end;local previous=-1
   for i=0,segments-1 do local last=s16(15+i*2);local first=s16(17+segments*2+i*2);local delta=sSigned(17+segments*4+i*2);local rp=17+segments*6+i*2;local ro=s16(rp)
    if first>last or first<=previous or ro%2~=0 then bad('E_FONT_CMAP','Invalid format4 segment',locations.cmap+1)end
    for cp=first,last do local id;if ro==0 then id=(cp+delta)%65536 else local at=rp+ro+(cp-first)*2;if at<17+segments*8 then bad('E_FONT_CMAP','Format4 glyph array points into header',locations.cmap+1)end;id=s16(at);if id~=0 then id=(id+delta)%65536 end end;add(cp,id)end;previous=last
   end;if previous~=65535 then bad('E_FONT_CMAP','Format4 sentinel segment missing',locations.cmap+1)end
  end
  local layout={};for _,tag in ipairs({'GSUB','GPOS'})do if tables[tag]then local x16,x32,_,xb=tableReader(tag,10);local version=x32(1);if version~=65536 and version~=65537 then bad('E_FONT_UNSUPPORTED','Unsupported layout table version',locations[tag]+1)end
   local off=x16(7);xb(off+1,2);local count=x16(off+1);if count>(sf.variableBase and 4096 or cap.tables)then bad('E_FONT_BUDGET','Too many layout features',locations[tag]+1)end;xb(off+1,2+count*6);local features={};for i=0,count-1 do local p=off+3+i*6;local feature=tables[tag]:sub(p,p+3);local foff=x16(p+4);xb(off+foff+1,4);features[#features+1]=feature;if sf.variableBase then charge(1)end end;layout[#layout+1]={table=tag,features=features,executed=false}
  end end
  if tables.kern then layout[#layout+1]={table='kern',features={},executed=false}end
  return{kind='r2u.font-metrics',schemaVersion=1,container=sf.container,unitsPerEm=units,numGlyphs=glyphCount,ascent=aSigned(5),descent=aSigned(7),lineGap=aSigned(9),glyphs=glyphs,mappings=mappings,cmapFormat=selected.format,cmapRecords=formats,layoutTables=layout,source={file=sf.file},limits={textBytes=cap.textBytes,textGlyphs=cap.textGlyphs},stats={tables=sf.stats.tables,expandedBytes=sf.stats.expandedBytes,mappings=#mappings,workReserved=sf.stats.workReserved},outlinesExecuted=false,hintingExecuted=false}
 end
 function M.parse(bytes,origin,limits)return parseContainer(sfnt.open(bytes,origin,limits))end
 function M.parseBaseVariable(container)
  local out=parseContainer(sfnt.verifyVariableContainer(container));out.variableBase=true;out.variationApplied=false;return out
 end
 function M.measureSimple(font,text,size)
  plain(font);if font.kind~='r2u.font-metrics' or font.schemaVersion~=1 then fail('E_FONT_SHAPE','Invalid font metrics object')end
  local units=integer(font.unitsPerEm,16,16384);local n=integer(font.numGlyphs,1,65535);if dense(font.glyphs)~=n then fail('E_FONT_SHAPE','Glyph metrics count mismatch')end
  for i,g in ipairs(font.glyphs)do plain(g);if g.glyphId~=i-1 then fail('E_FONT_SHAPE','Glyph metrics ID mismatch')end;integer(g.advanceUnits,0,65535);integer(g.leftSideBearing,-32768,32767)end
  dense(font.mappings);local previous=-1;for _,r in ipairs(font.mappings)do plain(r);local cp=integer(r.codepoint,0,1114111);integer(r.glyphId,1,n-1);if cp<=previous or cp>=55296 and cp<=57343 then fail('E_FONT_SHAPE','Invalid Unicode mapping order')end;previous=cp end
  plain(font.limits);local maxBytes=integer(font.limits.textBytes,1,caps.textBytes);local maxGlyphs=integer(font.limits.textGlyphs,1,caps.textGlyphs)
  if type(text)~='string'then fail('E_FONT_TEXT','Text must be UTF8 bytes')end;if #text>maxBytes then fail('E_FONT_BUDGET','Text byte budget exceeded')end
  if type(size)~='number' or size~=size or size<0 or size>4096 then fail('E_FONT_SHAPE','Invalid font pixel size')end;size=size*1.0
  local result={glyphs={},missing={},coverage=true,advanceUnits=0.0,shapingApplied=false,fontUnitArithmeticExact=true,canvasEquivalent='unverified',limitations={}}
  dense(font.layoutTables);for _,v in ipairs(font.layoutTables)do plain(v);if v.table~='GSUB' and v.table~='GPOS' and v.table~='kern'then fail('E_FONT_SHAPE','Invalid layout declaration')end;dense(v.features);local features={};for _,f in ipairs(v.features)do if type(f)~='string' or #f~=4 then fail('E_FONT_SHAPE','Invalid feature tag')end;features[#features+1]=f end;result.limitations[#result.limitations+1]={code='FONT_LAYOUT_NOT_APPLIED',table=v.table,features=features}end
  local ok,e=pcall(function()for at,cp in utf8.codes(text)do
   if cp>1114111 or cp>=55296 and cp<=57343 or cp<32 or cp==127 then fail('E_FONT_TEXT','Only single-line Unicode scalar text is supported',at)end
   if #result.glyphs>=maxGlyphs then fail('E_FONT_BUDGET','Text glyph budget exceeded',at)end
   local low,high,id=1,#font.mappings,0;while low<=high do local mid=math.floor((low+high)/2);local r=font.mappings[mid];if r.codepoint==cp then id=r.glyphId;break elseif r.codepoint<cp then low=mid+1 else high=mid-1 end end
   local g=font.glyphs[id+1];result.glyphs[#result.glyphs+1]={requestedCodepoint=cp,glyphId=id,covered=id~=0,byteOffset=at,advanceUnits=g.advanceUnits,leftSideBearing=g.leftSideBearing}
   if id==0 then result.coverage=false;result.missing[#result.missing+1]={requestedCodepoint=cp,byteOffset=at}end
   result.advanceUnits=result.advanceUnits+g.advanceUnits;if result.advanceUnits>SAFE then fail('E_FONT_BUDGET','Advance sum exceeds safe integer range',at)end
  end end)
  if not ok then if type(e)=='table' and e.code then error(e,0)end;fail('E_FONT_TEXT','Invalid UTF8 sequence')end
  if not result.coverage then result.limitations[#result.limitations+1]={code='FONT_GLYPH_MISSING'}end
  result.advance=result.advanceUnits*size/units;result.fontSize=size;return result
 end
 return M
end
