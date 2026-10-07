-- Desktop-only proof for a specified glyph alphabet. Never discards layout tables.
return function(deps)
 local S,SHA=deps['assets.font_sfnt'],deps['build.sha256'];local M={}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_LAYOUT_PROOF_SHAPE','Expected plain proof data')end end
 local function int(v,lo,hi)if type(v)~='number'or v~=v or v%1~=0 or v<lo or v>hi then fail('E_FONT_LAYOUT_PROOF_SHAPE','Invalid proof integer')end;return v end
 local function dense(v,max)plain(v);local n,high=0,0;for k in next,v do int(k,1,max);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_FONT_LAYOUT_PROOF_SHAPE','Expected dense proof array')end;return n end
 local function tag(v)if type(v)~='string'or not v:match('^[%g ][%g ][%g ][%g ]$')then fail('E_FONT_LAYOUT_PROOF_SHAPE','Invalid OpenType tag')end end
 function M.prove(bytes,origin,request,options)
  plain(request);for k in next,request do if k~='script'and k~='language'and k~='glyphIds'and k~='normalizedCoordinates'then fail('E_FONT_LAYOUT_PROOF_SHAPE','Unknown proof request field')end end
  tag(request.script);if request.language~='default'then tag(request.language)end
  local count=dense(request.glyphIds,65535);if count==0 then fail('E_FONT_LAYOUT_PROOF_SHAPE','Proof glyph alphabet must not be empty')end
  local coords={};dense(request.normalizedCoordinates,64);for i,v in ipairs(request.normalizedCoordinates)do if type(v)~='number'or v~=v or v< -1 or v>1 then fail('E_FONT_LAYOUT_PROOF_SHAPE','Invalid normalized coordinate')end;coords[i]=v end
  if options==nil then options={}end;plain(options);for k in next,options do if k~='sfntLimits'and k~='limits'then fail('E_FONT_LAYOUT_PROOF_SHAPE','Unknown proof option')end end
  local limits=options.limits;if limits==nil then limits={}end;plain(limits);local caps={work=8388608,records=262144};for k,v in next,limits do if not caps[k]then fail('E_FONT_LAYOUT_PROOF_SHAPE','Unknown proof limit')end;int(v,1,caps[k])end
  local sf=S.verifyVariableContainer(S.openVariable(bytes,origin,options.sfntLimits));local stats={work=0,records=0}
  local function charge(w,r)stats.work=stats.work+(w or 0);stats.records=stats.records+(r or 0);if stats.work>(limits.work or caps.work)or stats.records>(limits.records or caps.records)then sf.bad('E_FONT_LAYOUT_PROOF_BUDGET','Layout proof budget exceeded')end end
  local m16,m32=sf.tableReader('maxp',6);local glyphCount=m16(5);if m32(1)~=65536 or glyphCount<1 or glyphCount>sf.cap.glyphs then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid maxp glyph count',sf.locations.maxp+1)end
  local wanted,allowed,last={},{},-1;for _,g in ipairs(request.glyphIds)do int(g,0,glyphCount-1);if g<=last then fail('E_FONT_LAYOUT_PROOF_SHAPE','Glyph alphabet must be sorted and unique')end;last=g;allowed[#allowed+1]=g;wanted[g]=true end
  local axisCount=0
  if sf.tables.fvar then local a16,a32,_,bounds=sf.tableReader('fvar',16);if a32(1)~=65536 or a16(7)~=2 then sf.bad('E_FONT_LAYOUT_PROOF_UNSUPPORTED','Unsupported fvar header',sf.locations.fvar+1)end
   axisCount=a16(9);local axisSize=a16(11);if axisCount<1 or axisCount>64 or axisSize<20 or a16(5)<16 then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid fvar axis directory',sf.locations.fvar+1)end;bounds(a16(5)+1,axisCount*axisSize);charge(axisCount,axisCount)
  end
  if #coords~=axisCount then fail('E_FONT_LAYOUT_PROOF_SHAPE','Normalized coordinate count differs from fvar axes')end
  for _,t in ipairs({'kern','kerx','morx','mort','trak'})do if sf.tables[t]then sf.bad('E_FONT_LAYOUT_PROOF_UNSUPPORTED','Other layout table is unsupported: '..t,sf.locations[t]+1)end end
  local varItems
  local function variationIndex(outer,inner)
   if not varItems then
    local u16,u32,_,bounds=sf.tableReader('GDEF',18);if u32(1)~=65539 then sf.bad('E_FONT_LAYOUT_PROOF_UNSUPPORTED','VariationIndex requires GDEF1.3',sf.locations.GDEF+1)end
    local p=u32(15)+1;if p<=18 then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid GDEF variation store offset',sf.locations.GDEF+1)end;bounds(p,8);if u16(p)~=1 then sf.bad('E_FONT_LAYOUT_PROOF_UNSUPPORTED','Unsupported GDEF variation store format',sf.locations.GDEF+1)end
    local c=u16(p+6);bounds(p,8+c*4);charge(c,c);local region=p+u32(p+2);if region<p+8+c*4 then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid variation region offset',sf.locations.GDEF+1)end;bounds(region,4);local axes,regions=u16(region),u16(region+2);if axes~=axisCount then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','GDEF region axis mismatch',sf.locations.GDEF+1)end;bounds(region+4,axes*regions*6);charge(axes*regions,axes*regions);varItems={}
    for i=0,c-1 do local q=p+u32(p+8+i*4);if q<p+8+c*4 then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid variation item data offset',sf.locations.GDEF+1)end;bounds(q,6);local items,wordCount,rc=u16(q),u16(q+2),u16(q+4);local long=wordCount>=32768;wordCount=wordCount%32768;if wordCount>rc then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Invalid variation delta word count',sf.locations.GDEF+1)end;bounds(q+6,rc*2);for j=0,rc-1 do if u16(q+6+j*2)>=regions then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','Variation region index out of range',sf.locations.GDEF+1)end end;local width=wordCount*(long and 4 or 2)+(rc-wordCount)*(long and 2 or 1);bounds(q+6+rc*2,items*width);charge(rc+items,rc+items);varItems[i+1]=items end
   end
   if outer>=#varItems or inner>=varItems[outer+1]then sf.bad('E_FONT_LAYOUT_PROOF_TABLE','VariationIndex outer/inner out of range',sf.locations.GDEF+1)end
  end
  local selectedTables={}
  local function inspect(name)
   if not sf.tables[name]then return end
   local s=sf.tables[name];local u16,u32,i16,bounds=sf.tableReader(name,10)
   local function bad(reason,p,code)sf.bad(code or 'E_FONT_LAYOUT_PROOF_TABLE',reason,sf.locations[name]+1,p)end
   local function ptr(base,offset,minimum)if offset==0 or offset<minimum then bad('Invalid layout relative offset',base)end;bounds(base+offset,2);return base+offset end
   local function countAt(p,stride,head)local c=u16(p);bounds(p,head+c*stride);charge(c,c);return c end
   local function gid(g,p)if g>=glyphCount then bad('Glyph index outside maxp',p)end;return g end
   local function indices(p,c,max)bounds(p,c*2);local out={};for i=0,c-1 do local v=u16(p+i*2);if v>=max then bad('Layout index out of range',p+i*2)end;out[#out+1]=v end;return out end
   local version=u32(1);if version~=65536 and version~=65537 then bad('Unsupported layout version',1,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;local header=version==65537 and 14 or 10;bounds(1,header)
   local sp,fp,lp=ptr(1,u16(5),header),ptr(1,u16(7),header),ptr(1,u16(9),header);local fc,lc=countAt(fp,6,2),countAt(lp,2,2)
   local features,lookups,scripts={},{},{}
   local function feature(q)bounds(q,4);local c=countAt(q+2,2,2);local result=indices(q+4,c,lc);local params=u16(q);if params~=0 then ptr(q,params,4+c*2)end;return result,params end
   local previous='';for i=0,fc-1 do local p=fp+2+i*6;local t=s:sub(p,p+3);if not t:match('^[%g ][%g ][%g ][%g ]$')or t<previous then bad('Invalid feature order/tag',p)end;previous=t;local refs,params=feature(ptr(fp,u16(p+4),2+fc*6));features[i+1]={tag=t,lookupIndices=refs,params=params}end
   local function language(q)bounds(q,6);if u16(q)~=0 then bad('Nonzero reserved LangSys lookupOrder',q)end;local required=u16(q+2);if required~=65535 and required>=fc then bad('Invalid required feature index',q+2)end;local c=countAt(q+4,2,2);return{requiredFeatureIndex=required,featureIndices=indices(q+6,c,fc)}end
   local sc=countAt(sp,6,2);previous='';for i=0,sc-1 do local p=sp+2+i*6;local t=s:sub(p,p+3);if not t:match('^[%g ][%g ][%g ][%g ]$')or t<=previous then bad('Invalid script order/tag',p)end;previous=t;local q=ptr(sp,u16(p+4),2+sc*6);bounds(q,4);local n=countAt(q+2,6,2);local row={tag=t,languages={}};if u16(q)~=0 then row.defaultLangSys=language(ptr(q,u16(q),4+n*6))elseif t=='DFLT'then bad('DFLT without default LangSys',q)end;local lastTag='';for j=0,n-1 do local at=q+4+j*6;local label=s:sub(at,at+3);if not label:match('^[%g ][%g ][%g ][%g ]$')or label<=lastTag then bad('Invalid LangSys order/tag',at)end;lastTag=label;row.languages[label]=language(ptr(q,u16(at+4),4+n*6))end;scripts[t]=row end
   for i=0,lc-1 do local p=ptr(lp,u16(lp+2+i*2),2+lc*2);bounds(p,6);local typ=u16(p);if typ<1 or typ>(name=='GSUB'and 8 or 9)then bad('Lookup type outside table enumeration',p)end;local c=countAt(p+4,2,2);local flags=u16(p+2);if flags%32>=16 then bounds(p+6+c*2,2)end;local refs={};for j=0,c-1 do refs[#refs+1]=ptr(p,u16(p+6+j*2),6+c*2+(flags%32>=16 and 2 or 0))end;lookups[i+1]={lookupType=typ,flags=flags,positions=refs}end
   local chosen=scripts[request.script]or scripts.DFLT;if not chosen then if sc~=0 or fc~=0 or lc~=0 then bad('No requested or DFLT script',sp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;if version==65537 and u32(11)~=0 then bad('FeatureVariations without script are unsupported',11,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;selectedTables[#selectedTables+1]={table=name,present=true,script=request.script,language=request.language,features={},lookups={}};return end
   local lang=chosen.languages[request.language]or chosen.defaultLangSys;if not lang then bad('No requested or default LangSys',sp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;local actualLanguage=chosen.languages[request.language]and request.language or 'default'
   local defaults={ccmp=true,locl=true,rlig=true,liga=true,clig=true,calt=true,kern=true,mark=true,mkmk=true}
   -- Other generic/default or automatically activated HarfBuzz features need
   -- their own profile. Never certify identity by silently omitting them.
   local extraDefaults={rvrn=true,ltra=true,ltrm=true,rclt=true,curs=true,dist=true,abvm=true,blwm=true,rand=true,Harf=true,HARF=true,Buzz=true,BUZZ=true,frac=true,numr=true,dnom=true}
   local selected={};for _,i in ipairs(lang.featureIndices)do local t=features[i+1].tag;if extraDefaults[t]then bad('Additional default/automatic feature is unsupported: '..t,fp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;if defaults[t]then selected[i]=true end end;if lang.requiredFeatureIndex~=65535 then if not defaults[features[lang.requiredFeatureIndex+1].tag]then bad('Unknown required feature',fp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;selected[lang.requiredFeatureIndex]=true end
   local variationRecords=0
   if version==65537 and u32(11)~=0 then local p=ptr(1,u32(11),header);bounds(p,8);if u16(p)~=1 or u16(p+2)~=0 then bad('Unsupported FeatureVariations version',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;local c=u32(p+4);if c>262144 then bad('FeatureVariations record count exceeds budget',p,'E_FONT_LAYOUT_PROOF_BUDGET')end;bounds(p+8,c*8);charge(c,c);variationRecords=c;local firstMatched=false
    for i=0,c-1 do local at=p+8+i*8;local conditionOffset,subOffset=u32(at),u32(at+4);local matched=true
     if conditionOffset~=0 then local q=ptr(p,conditionOffset,8+c*8);local n=countAt(q,4,2);for j=0,n-1 do local cond=ptr(q,u32(q+2+j*4),2+n*4);bounds(cond,8);if u16(cond)~=1 then bad('Unknown FeatureVariations condition',cond,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;local axis=u16(cond+2);local low,high=i16(cond+4)/16384,i16(cond+6)/16384;if axis>=axisCount or low< -1 or high>1 or low>high then bad('Invalid FeatureVariations axis/range',cond)end;if coords[axis+1]<low or coords[axis+1]>high then matched=false end end end
     local substitutionCount=0
     if subOffset~=0 then local q=ptr(p,subOffset,8+c*8);bounds(q,6);if u16(q)~=1 or u16(q+2)~=0 then bad('Unsupported FeatureTableSubstitution version',q,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;local n=countAt(q+4,6,2);substitutionCount=n;local lastIndex=-1;for j=0,n-1 do local r=q+6+j*6;local index=u16(r);if index>=fc or index<=lastIndex then bad('Invalid alternate feature index/order',r)end;lastIndex=index;feature(ptr(q,u32(r+2),6+n*6))end end
     if matched and not firstMatched then firstMatched=true;if substitutionCount>0 then bad('Active FeatureVariations alternate features are unsupported',at,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end end
    end
   end
   local summary={table=name,present=true,script=chosen.tag,language=actualLanguage,features={},lookups={},featureVariationRecords=variationRecords};local refs={};for i=0,fc-1 do if selected[i]then local f=features[i+1];if f.params~=0 then bad('Selected feature parameters are unsupported',fp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;summary.features[#summary.features+1]={index=i,tag=f.tag,lookupIndices=f.lookupIndices};for _,li in ipairs(f.lookupIndices)do refs[li]=true end end end
   local function coverage(p,role)
    bounds(p,4);local fmt=u16(p);local out={};local prev=-1
    local function append(id,q)gid(id,q);if id<=prev then bad('Coverage glyph order is invalid',q)end;prev=id;out[#out+1]=id;if wanted[id]then bad('Active '..name..' '..role..' coverage intersects allowed glyph '..id,q,'E_FONT_LAYOUT_PROOF_HIT')end end
    if fmt==1 then local c=countAt(p+2,2,2);for i=0,c-1 do append(u16(p+4+i*2),p+4+i*2)end
    elseif fmt==2 then local c=countAt(p+2,6,2);for i=0,c-1 do local q=p+4+i*6;local a,b,index=u16(q),u16(q+2),u16(q+4);if a>b or a<=prev or index~=#out then bad('Invalid coverage range/index',q)end;charge(b-a+1,b-a+1);for id=a,b do append(id,q)end end
    else bad('Unknown coverage format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;return out
   end
   local function device(base,off)
    if off==0 then return end;local p=ptr(base,off,1);bounds(p,6);local first,last,fmt=u16(p),u16(p+2),u16(p+4)
    if fmt==32768 then variationIndex(first,last)elseif fmt>=1 and fmt<=3 then if first>last then bad('Invalid device size range',p)end;local words=math.ceil((last-first+1)*(2^fmt)/16);bounds(p+6,words*2);charge(words,words)else bad('Unknown Device/VariationIndex format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end
   end
   local function valueSize(fmt)if fmt>=256 then bad('Reserved ValueFormat bits',lp)end;local n=0;for i=0,7 do if math.floor(fmt/(2^i))%2==1 then n=n+2 end end;return n end
   local function value(p,fmt,base)local size=valueSize(fmt);bounds(p,size);local at=p;for i=0,7 do if math.floor(fmt/(2^i))%2==1 then if i>=4 then device(base,u16(at))end;at=at+2 end end;charge(1,1);return at end
   local function classDef(p,maxClass)
    bounds(p,4);local fmt=u16(p);if fmt==1 then bounds(p,6);local first,c=u16(p+2),countAt(p+4,2,2);if c>0 then gid(first+c-1,p+2)end;for i=0,c-1 do if u16(p+6+i*2)>=maxClass then bad('Class index out of range',p)end end
    elseif fmt==2 then local c=countAt(p+2,6,2);local last=-1;for i=0,c-1 do local q=p+4+i*6;local a,b,cl=u16(q),u16(q+2),u16(q+4);gid(b,q+2);if a>b or a<=last or cl>=maxClass then bad('Invalid class range/index',q)end;last=b end
    else bad('Unknown class definition',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end
   end
   local function anchor(base,off,required)
    if off==0 then if required then bad('Missing mark anchor',base)end;return end;local p=ptr(base,off,1);bounds(p,6);local fmt=u16(p);if fmt==2 then bounds(p,8)elseif fmt==3 then bounds(p,10);device(p,u16(p+6));device(p,u16(p+8))elseif fmt~=1 then bad('Unknown anchor format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;charge(1,1)
   end
   for li=0,lc-1 do if refs[li]then local l=lookups[li+1];if l.flags~=0 then bad('Nonzero selected lookup flags',lp,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;if #l.positions==0 then bad('Empty selected lookup',lp)end;local row={index=li,lookupType=l.lookupType,flags=l.flags,subtables={}}
    for _,p in ipairs(l.positions)do local fmt=u16(p);local sub={format=fmt}
     if name=='GSUB'and l.lookupType==1 then
      if fmt~=1 and fmt~=2 then bad('Unknown selected single format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;bounds(p,6);local c=fmt==2 and countAt(p+4,2,2)or 0;local cov=coverage(ptr(p,u16(p+2),6+c*2),'single input');if fmt==2 and c~=#cov then bad('Single coverage/replacement count mismatch',p)end;for i,g in ipairs(cov)do gid(fmt==1 and (g+i16(p+4))%65536 or u16(p+4+i*2),p)end;sub.coverageCount=#cov
     elseif name=='GSUB'and l.lookupType==4 then
      if fmt~=1 then bad('Unknown selected ligature format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;bounds(p,6);local c=countAt(p+4,2,2);local cov=coverage(ptr(p,u16(p+2),6+c*2),'ligature first input');if c~=#cov then bad('Ligature coverage/set mismatch',p)end;for i=0,c-1 do local set=ptr(p,u16(p+6+i*2),6+c*2);local n=countAt(set,2,2);for j=0,n-1 do local lig=ptr(set,u16(set+2+j*2),2+n*2);bounds(lig,4);gid(u16(lig),lig);local z=u16(lig+2);if z<2 then bad('Invalid ligature component count',lig)end;bounds(lig+4,(z-1)*2);charge(z,z);for k=0,z-2 do gid(u16(lig+4+k*2),lig)end end end;sub.coverageCount=#cov
     elseif name=='GPOS'and l.lookupType==2 then
      if fmt~=1 and fmt~=2 then bad('Unknown selected PairPos format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;bounds(p,fmt==1 and 10 or 16);local v1,v2=u16(p+4),u16(p+6);local size=valueSize(v1)+valueSize(v2)
      if fmt==1 then local c=countAt(p+8,2,2);local cov=coverage(ptr(p,u16(p+2),10+c*2),'pair first input');if #cov~=c then bad('Pair coverage/set mismatch',p)end;for i=0,c-1 do local q=ptr(p,u16(p+10+i*2),10+c*2);local n=countAt(q,2+size,2);local last=-1;for j=0,n-1 do local at=q+2+j*(2+size);local g=gid(u16(at),at);if g<=last then bad('Pair second glyph order invalid',at)end;last=g;at=value(at+2,v1,q);value(at,v2,q)end end;sub.coverageCount=#cov
      else local c1,c2=u16(p+12),u16(p+14);if c1==0 or c2==0 then bad('Empty PairPos class matrix',p)end;local cells=c1*c2;charge(cells,cells);bounds(p+16,cells*size);local cov=coverage(ptr(p,u16(p+2),16+cells*size),'pair first input');classDef(ptr(p,u16(p+8),16+cells*size),c1);classDef(ptr(p,u16(p+10),16+cells*size),c2);for i=0,cells-1 do local at=value(p+16+i*size,v1,p);value(at,v2,p)end;sub.coverageCount=#cov end
     elseif name=='GPOS'and l.lookupType==4 then
      if fmt~=1 then bad('Unknown selected MarkBase format',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;bounds(p,12);local marks=coverage(ptr(p,u16(p+2),12),'mark input');local bases=coverage(ptr(p,u16(p+4),12),'base input');local classes=u16(p+6);if classes==0 then bad('Empty MarkBase class count',p)end;local ma,ba=ptr(p,u16(p+8),12),ptr(p,u16(p+10),12);local mc=countAt(ma,4,2);if mc~=#marks then bad('MarkArray count mismatch',ma)end;for i=0,mc-1 do local at=ma+2+i*4;if u16(at)>=classes then bad('Mark class outside classCount',at)end;anchor(ma,u16(at+2),true)end;local bc=u16(ba);if bc~=#bases then bad('BaseArray count mismatch',ba)end;charge(bc*classes,bc*classes);bounds(ba+2,bc*classes*2);for i=0,bc*classes-1 do anchor(ba,u16(ba+2+i*2),false)end;sub.markCoverageCount=#marks;sub.baseCoverageCount=#bases
     else bad('Unknown selected lookup type',p,'E_FONT_LAYOUT_PROOF_UNSUPPORTED')end;row.subtables[#row.subtables+1]=sub
    end;summary.lookups[#summary.lookups+1]=row
   end end;selectedTables[#selectedTables+1]=summary
  end
  inspect('GSUB');inspect('GPOS')
  return{kind='r2u.font-layout-proof',schemaVersion=1,proof='no-active-lookup-intersection',profile='horizontal-ltr-default-features-no-hit-v1',request={script=request.script,language=request.language},source={file=sf.file,sha256=SHA.hex(bytes)},allowedGlyphIds=allowed,normalizedCoordinates=coords,selectedTables=selectedTables,numGlyphs=glyphCount,stats=stats,unicodeShapingApplied=false}
 end
 return M
end
