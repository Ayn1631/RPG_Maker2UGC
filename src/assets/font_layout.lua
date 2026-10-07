-- Desktop-only bounded OpenType subset. Runtime consumes only returned plain IR.
return function(deps)
 local S=deps['assets.font_sfnt'];local M={}
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then error({code='E_FONT_LAYOUT_SHAPE',reason='Expected plain layout options'},0)end end
 function M.parse(bytes,origin,options)
  if options==nil then options={}end;plain(options);for k in next,options do if k~='sfntLimits'and k~='limits'then error({code='E_FONT_LAYOUT_SHAPE',reason='Unknown layout option'},0)end end
  local limits=options.limits;if limits==nil then limits={}end;plain(limits);local caps={records=262144,work=8388608};for k,v in next,limits do if not caps[k]or type(v)~='number'or v%1~=0 or v<1 or v>caps[k]then error({code='E_FONT_LAYOUT_SHAPE',reason='Invalid layout limit'},0)end end
  local sf=S.open(bytes,origin,options.sfntLimits);local _,m32=sf.tableReader('maxp',6);local m16=sf.tableReader('maxp',6);local n=m16(5)
  if m32(1)~=65536 or n<1 or n>sf.cap.glyphs then sf.bad('E_FONT_LAYOUT_TABLE','Invalid maxp glyph count',sf.locations.maxp+1)end
  local ir={kind='r2u.font-layout',schemaVersion=1,numGlyphs=n,scripts={},features={},lookups={},gposEmpty=true,kernAbsent=true,stats={work=0,records=0}}
  local function charge(work,records)ir.stats.work=ir.stats.work+(work or 0);ir.stats.records=ir.stats.records+(records or 0);if ir.stats.work>(limits.work or caps.work)or ir.stats.records>(limits.records or caps.records)then sf.bad('E_FONT_LAYOUT_BUDGET','Layout parse budget exceeded')end end
  if sf.tables.kern then sf.bad('E_FONT_LAYOUT_UNSUPPORTED','kern table is unsupported',sf.locations.kern+1)end
  local function parseTable(tag)
   if not sf.tables[tag]then return {scripts={},features={},lookups={}}end
   local s=sf.tables[tag];local u16,u32,i16,bounds=sf.tableReader(tag,10)
   local function bad(reason,p,unsupported)sf.bad(unsupported and 'E_FONT_LAYOUT_UNSUPPORTED'or 'E_FONT_LAYOUT_TABLE',reason,sf.locations[tag]+1,p)end
   local function ptr(base,off,min)if off==0 or off<min then bad('Invalid relative layout offset',base)end;bounds(base+off,2);return base+off end
   local function glyph(id,p)if id>=n then bad('Layout glyph outside maxp',p)end;return id end
   local function count(p,stride,head)local c=u16(p);bounds(p,head+c*stride);charge(c,c);return c end
   local version=u32(1);if version~=65536 and version~=65537 then bad('Unsupported layout version',1,true)end
   if version==65537 then bounds(1,14);if u32(11)~=0 then bad('Feature variations are unsupported',11,true)end end
   local header=version==65537 and 14 or 10
   local sp,fp,lp=ptr(1,u16(5),header),ptr(1,u16(7),header),ptr(1,u16(9),header)
   local fc,lc=count(fp,6,2),count(lp,2,2);local out={scripts={},features={},lookups={}}
   local function indices(p,c,high)local arr={};bounds(p,c*2);for j=0,c-1 do local x=u16(p+j*2);if x>=high then bad('Layout index out of range',p+j*2)end;arr[#arr+1]=x end;return arr end
   local function lang(p)bounds(p,6);if u16(p)~=0 then bad('Reserved lookup order is nonzero',p)end;local req=u16(p+2);if req~=65535 and req>=fc then bad('Required feature out of range',p+2)end;local c=count(p+4,2,2);return {requiredFeatureIndex=req,featureIndices=indices(p+6,c,fc)}end
   local previous='';local sc=count(sp,6,2)
   for i=0,sc-1 do local p=sp+2+i*6;local name=s:sub(p,p+3);if not name:match('^[%g ][%g ][%g ][%g ]$')or name<=previous then bad('Invalid script order/tag',p)end;previous=name
    local q=ptr(sp,u16(p+4),2+sc*6);bounds(q,4);local lcount=count(q+2,6,2);local def=u16(q);local row={tag=name,languages={}};if def~=0 then row.defaultLangSys=lang(ptr(q,def,4+lcount*6))elseif name=='DFLT'then bad('DFLT has no default LangSys',q)end
    local last='';for j=0,lcount-1 do local at=q+4+j*6;local label=s:sub(at,at+3);if not label:match('^[%g ][%g ][%g ][%g ]$')or label<=last then bad('Invalid language order/tag',at)end;last=label;local l=lang(ptr(q,u16(at+4),4+lcount*6));l.tag=label;row.languages[#row.languages+1]=l end;out.scripts[#out.scripts+1]=row
   end
   previous='';for i=0,fc-1 do local p=fp+2+i*6;local name=s:sub(p,p+3);if not name:match('^[%g ][%g ][%g ][%g ]$')or name<previous then bad('Invalid feature order/tag',p)end;previous=name;local q=ptr(fp,u16(p+4),2+fc*6);bounds(q,4);if u16(q)~=0 then bad('Feature parameters are unsupported',q,true)end;local c=count(q+2,2,2);out.features[#out.features+1]={tag=name,lookupIndices=indices(q+4,c,lc)}end
   if tag=='GPOS'then if fc~=0 or lc~=0 then bad('Nonempty GPOS is unsupported',fp,true)end;return out end
   local function coverage(p)
    bounds(p,4);local fmt=u16(p);local result={};local last=-1
    if fmt==1 then local c=count(p+2,2,2);for i=0,c-1 do local id=glyph(u16(p+4+i*2),p+4+i*2);if id<=last then bad('Coverage glyphs unsorted',p)end;last=id;result[#result+1]=id end
    elseif fmt==2 then local c=count(p+2,6,2);for i=0,c-1 do local q=p+4+i*6;local a,b,index=u16(q),u16(q+2),u16(q+4);if a>b or a<=last or index~=#result then bad('Invalid coverage range/index',q)end;glyph(b,q+2);charge(b-a+1,b-a+1);for id=a,b do result[#result+1]=id end;last=b end
    else bad('Unsupported coverage format',p,true)end;return result
   end
   for i=0,lc-1 do local p=ptr(lp,u16(lp+2+i*2),2+lc*2);bounds(p,6);local typ,flags=u16(p),u16(p+2);local c=count(p+4,2,2);if flags~=0 then bad('Nonzero lookup flags are unsupported',p+2,true)end;if c==0 then bad('Empty lookup',p+4)end
    if typ~=1 and typ~=4 and typ~=6 then bad('Unsupported GSUB lookup type',p,true)end;local lookup={lookupType=typ,subtables={}}
    for j=0,c-1 do local q=ptr(p,u16(p+6+j*2),6+c*2);local fmt=u16(q);local sub
     if typ==1 then
      if fmt~=1 and fmt~=2 then bad('Unsupported single substitution format',q,true)end;bounds(q,6);local cov=coverage(ptr(q,u16(q+2),6+(fmt==2 and u16(q+4)*2 or 0)));sub={kind='single',mappings={}}
      if fmt==2 then local z=count(q+4,2,2);if z~=#cov then bad('Single coverage/replacement count mismatch',q)end end
      for k,id in ipairs(cov)do local output=fmt==1 and (id+i16(q+4))%65536 or u16(q+4+k*2);sub.mappings[#sub.mappings+1]={from=id,to=glyph(output,q)}end
     elseif typ==4 then
      if fmt~=1 then bad('Unsupported ligature format',q,true)end;bounds(q,6);local z=count(q+4,2,2);local cov=coverage(ptr(q,u16(q+2),6+z*2));if z~=#cov then bad('Ligature coverage/set count mismatch',q)end;sub={kind='ligature',sets={}}
      for k,id in ipairs(cov)do local setp=ptr(q,u16(q+4+k*2),6+z*2);local zc=count(setp,2,2);local set={first=id,ligatures={}};for zidx=0,zc-1 do local lig=ptr(setp,u16(setp+2+zidx*2),2+zc*2);bounds(lig,4);local components=u16(lig+2);if components<2 then bad('Ligature must have two components',lig+2)end;charge(components,components);bounds(lig,4+(components-1)*2);local comp={id};for at=0,components-2 do comp[#comp+1]=glyph(u16(lig+4+at*2),lig+4+at*2)end;set.ligatures[#set.ligatures+1]={components=comp,replacement=glyph(u16(lig),lig)}end;sub.sets[#sub.sets+1]=set end
     else
      if fmt~=3 then bad('Unsupported chained context format',q,true)end;sub={kind='chain',backtrack={},input={},lookahead={},records={}};local at=q+2
      local pending={};for _,key in ipairs({'backtrack','input','lookahead'})do local z=count(at,2,2);if key=='input'and z==0 then bad('Empty context input',at)end;for k=0,z-1 do pending[#pending+1]={key=key,off=u16(at+2+k*2)}end;at=at+2+z*2 end
      local z=count(at,4,2);for k=0,z-1 do local rec=at+2+k*4;local index,ref=u16(rec),u16(rec+2);if index>=u16(q+2+2+u16(q+2)*2)or ref>=lc then bad('Invalid contextual lookup record',rec)end;sub.records[#sub.records+1]={sequenceIndex=index,lookupIndex=ref}end;local minimum=at+2+z*4-q
      for _,v in ipairs(pending)do sub[v.key][#sub[v.key]+1]=coverage(ptr(q,v.off,minimum))end
     end;lookup.subtables[#lookup.subtables+1]=sub
    end;out.lookups[#out.lookups+1]=lookup
   end
   for _,l in ipairs(out.lookups)do for _,sub in ipairs(l.subtables)do if sub.kind=='chain'then for _,r in ipairs(sub.records)do if out.lookups[r.lookupIndex+1].lookupType~=1 then bad('Nested context supports single lookup only',lp,true)end end end end end
   return out
  end
  local g=parseTable('GSUB');parseTable('GPOS');ir.scripts=g.scripts;ir.features=g.features;ir.lookups=g.lookups;return ir
 end
 return M
end
