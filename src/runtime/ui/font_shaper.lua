-- Plain-data GSUB subset. No font parser, IO, normalization, bidi or mark engine.
return function()
 local M={};local MAX=262144
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_SHAPER_SHAPE','Expected plain shaper data')end end
 local function int(v,lo,hi)if type(v)~='number'or v~=v or v%1~=0 or v<lo or v>hi then fail('E_FONT_SHAPER_SHAPE','Integer outside shaper bounds')end;return v end
 local function dense(v)plain(v);local n,max=0,0;for k in next,v do int(k,1,MAX);n=n+1;max=math.max(max,k)end;if n~=max then fail('E_FONT_SHAPER_SHAPE','Expected dense shaper array')end;return n end
 local function tag(v)if type(v)~='string'or not v:match('^[%g ][%g ][%g ][%g ]$')then fail('E_FONT_SHAPER_SHAPE','Invalid OpenType tag')end end
 local function validate(ir)
  plain(ir);if ir.kind~='r2u.font-layout'or ir.schemaVersion~=1 or ir.gposEmpty~=true or ir.kernAbsent~=true then fail('E_FONT_SHAPER_SHAPE','Invalid layout contract')end
  local n=int(ir.numGlyphs,1,65535);local nf,nl=dense(ir.features),dense(ir.lookups);local records=0
  local function charge(k)records=records+k;if records>MAX then fail('E_FONT_SHAPER_BUDGET','Layout validation record budget exceeded')end end
  charge(nf+nl);local function boundedDense(v)local count=dense(v);charge(count+1);return count end
  local function gid(x)charge(1);return int(x,0,n-1)end
  local function indices(arr,high)boundedDense(arr);for _,v in ipairs(arr)do int(v,0,high-1)end end
  local function lang(v)plain(v);int(v.requiredFeatureIndex,0,65535);if v.requiredFeatureIndex~=65535 then int(v.requiredFeatureIndex,0,nf-1)end;indices(v.featureIndices,nf)end
  boundedDense(ir.scripts);local last='';for _,s in ipairs(ir.scripts)do plain(s);tag(s.tag);if s.tag<=last then fail('E_FONT_SHAPER_SHAPE','Scripts unsorted')end;last=s.tag;if s.defaultLangSys~=nil then lang(s.defaultLangSys)elseif s.tag=='DFLT'then fail('E_FONT_SHAPER_SHAPE','DFLT missing language')end;boundedDense(s.languages);local prev='';for _,l in ipairs(s.languages)do plain(l);tag(l.tag);if l.tag<=prev then fail('E_FONT_SHAPER_SHAPE','Languages unsorted')end;prev=l.tag;lang(l)end end
  for _,f in ipairs(ir.features)do plain(f);tag(f.tag);indices(f.lookupIndices,nl)end
  local function cov(a)boundedDense(a);local prev=-1;for _,g in ipairs(a)do gid(g);if g<=prev then fail('E_FONT_SHAPER_SHAPE','Coverage unsorted')end;prev=g end end
  for _,l in ipairs(ir.lookups)do plain(l);if l.lookupType~=1 and l.lookupType~=4 and l.lookupType~=6 then fail('E_FONT_SHAPER_SHAPE','Unsupported lookup')end;boundedDense(l.subtables);if #l.subtables==0 then fail('E_FONT_SHAPER_SHAPE','Empty lookup')end
   for _,s in ipairs(l.subtables)do plain(s)
    if l.lookupType==1 and s.kind=='single'then boundedDense(s.mappings);local prev=-1;for _,v in ipairs(s.mappings)do plain(v);gid(v.from);gid(v.to);if v.from<=prev then fail('E_FONT_SHAPER_SHAPE','Single mapping unsorted')end;prev=v.from end
    elseif l.lookupType==4 and s.kind=='ligature'then boundedDense(s.sets);local prev=-1;for _,set in ipairs(s.sets)do plain(set);gid(set.first);if set.first<=prev then fail('E_FONT_SHAPER_SHAPE','Ligature sets unsorted')end;prev=set.first;boundedDense(set.ligatures);for _,v in ipairs(set.ligatures)do plain(v);gid(v.replacement);boundedDense(v.components);if #v.components<2 or v.components[1]~=set.first then fail('E_FONT_SHAPER_SHAPE','Invalid ligature components')end;for _,g in ipairs(v.components)do gid(g)end end end
    elseif l.lookupType==6 and s.kind=='chain'then for _,key in ipairs({'backtrack','input','lookahead'})do boundedDense(s[key]);for _,v in ipairs(s[key])do cov(v)end end;if #s.input<1 then fail('E_FONT_SHAPER_SHAPE','Empty context input')end;boundedDense(s.records);for _,v in ipairs(s.records)do plain(v);int(v.sequenceIndex,0,#s.input-1);int(v.lookupIndex,0,nl-1)end
    else fail('E_FONT_SHAPER_SHAPE','Subtable/type mismatch')end
   end
  end
  for _,l in ipairs(ir.lookups)do for _,s in ipairs(l.subtables)do if s.kind=='chain'then for _,r in ipairs(s.records)do if ir.lookups[r.lookupIndex+1].lookupType~=1 then fail('E_FONT_SHAPER_SHAPE','Nested lookup must be single')end end end end end
  return n
 end
 function M.select(ir,options)
  validate(ir);if options==nil then options={}end;plain(options);for k in next,options do if k~='script'and k~='language'and k~='features'then fail('E_FONT_SHAPER_SHAPE','Unknown selection option')end end
  local script=options.script;if script==nil then script='DFLT'end;tag(script);local language=options.language;if language==nil then language='default'end;if language~='default'then tag(language)end
  local allowed={ccmp=true,locl=true,rlig=true,liga=true,clig=true,calt=true,jp04=true,vert=true};local enabled={ccmp=true,locl=true,rlig=true,liga=true,clig=true,calt=true}
  if options.features~=nil then plain(options.features);for k,v in next,options.features do if not allowed[k]or type(v)~='boolean'then fail('E_FONT_SHAPER_SHAPE','Unsupported feature option')end;enabled[k]=v end end
  local chosen,def;for _,s in ipairs(ir.scripts)do if s.tag==script then chosen=s end;if s.tag=='DFLT'then def=s end end;chosen=chosen or def
  if not chosen then if #ir.scripts==0 and #ir.features==0 and #ir.lookups==0 then return{script=script,language=language,stages={},featureIndices={}}end;fail('E_FONT_SHAPER_UNSUPPORTED','No requested or DFLT script')end
  local lang=chosen.defaultLangSys;local selectedLanguage='default';for _,l in ipairs(chosen.languages)do if l.tag==language then lang=l;selectedLanguage=language end end;if not lang then fail('E_FONT_SHAPER_UNSUPPORTED','No requested or default language system')end
  local result={script=chosen.tag,language=selectedLanguage,stages={},featureIndices={}};local fs={};for _,i in ipairs(lang.featureIndices)do if enabled[ir.features[i+1].tag]then fs[i]=true end end;if lang.requiredFeatureIndex~=65535 then fs[lang.requiredFeatureIndex]=true end
  for i=0,#ir.features-1 do if fs[i]then local name=ir.features[i+1].tag;if not allowed[name]then fail('E_FONT_SHAPER_UNSUPPORTED','Unsupported required feature '..name)end;result.featureIndices[#result.featureIndices+1]=i end end
  -- HarfBuzz generic simple shaper has no script-specific pauses among these
  -- features: merge selected defaults and explicit options in LookupList order.
  local ids={};for _,i in ipairs(result.featureIndices)do for _,li in ipairs(ir.features[i+1].lookupIndices)do ids[li]=true end end
  local stage={lookupIndices={}};for i=0,#ir.lookups-1 do if ids[i]then stage.lookupIndices[#stage.lookupIndices+1]=i end end;if #stage.lookupIndices>0 then result.stages[1]=stage end
  return result
 end
 local function selection(ir,s)plain(s);dense(s.stages);if #s.stages>4 then fail('E_FONT_SHAPER_SHAPE','Too many layout stages')end;local refs={};for _,stage in ipairs(s.stages)do plain(stage);dense(stage.lookupIndices);local last=-1;for _,i in ipairs(stage.lookupIndices)do int(i,0,#ir.lookups-1);if i<=last then fail('E_FONT_SHAPER_SHAPE','Lookup stage unsorted')end;last=i;refs[#refs+1]=i end end;return refs end
 function M.closure(ir,selected)
  validate(ir);local refs=selection(ir,selected);local seen,visited={},{};local function add(g)seen[g]=true end
  local visit;visit=function(i)if visited[i]then return end;visited[i]=true;for _,s in ipairs(ir.lookups[i+1].subtables)do if s.kind=='single'then for _,v in ipairs(s.mappings)do add(v.from);add(v.to)end elseif s.kind=='ligature'then for _,set in ipairs(s.sets)do for _,v in ipairs(set.ligatures)do for _,g in ipairs(v.components)do add(g)end;add(v.replacement)end end else for _,key in ipairs({'backtrack','input','lookahead'})do for _,a in ipairs(s[key])do for _,g in ipairs(a)do add(g)end end end;for _,v in ipairs(s.records)do visit(v.lookupIndex)end end end end
  for _,i in ipairs(refs)do visit(i)end;local result={};for g in next,seen do result[#result+1]=g end;table.sort(result);return result
 end
 -- Build-time output contains only selected refs, not another copy of layout.
 function M.compileSelection(ir,selected)
  local n=validate(ir);local refs=selection(ir,selected)
  return{kind='r2u.compiled-font-selection',schemaVersion=1,numGlyphs=n,lookupIndices=refs}
 end
 local function apply(ir,n,refs,input,options)
  dense(input);if options==nil then options={}end;plain(options);for k in next,options do if k~='maxWork'and k~='maxGlyphs'then fail('E_FONT_SHAPER_SHAPE','Unknown apply option')end end
  local maxWork=options.maxWork~=nil and int(options.maxWork,1,8388608)or 8388608;local maxGlyphs=options.maxGlyphs~=nil and int(options.maxGlyphs,1,100000)or 100000;if #input>maxGlyphs then fail('E_FONT_SHAPER_BUDGET','Input glyph budget exceeded')end
  local work=0;local function charge()work=work+1;if work>maxWork then fail('E_FONT_SHAPER_BUDGET','Lookup execution budget exceeded')end end
  local glyphs={};for _,g in ipairs(input)do plain(g);int(g.glyphId,0,n-1);int(g.clusterStart,1,1048577);int(g.clusterEnd,g.clusterStart,1048577);local v={glyphId=g.glyphId,clusterStart=g.clusterStart,clusterEnd=g.clusterEnd};glyphs[#glyphs+1]=v end
  local substitutions=0
  local function has(a,g)local lo,hi=1,#a;while lo<=hi do charge();local mid=math.floor((lo+hi)/2);if a[mid]==g then return true elseif a[mid]<g then lo=mid+1 else hi=mid-1 end end;return false end
  local atLookup;atLookup=function(li,pos)
   local l=ir.lookups[li+1];for _,s in ipairs(l.subtables)do charge()
    if s.kind=='single'then local lo,hi=1,#s.mappings;while lo<=hi do charge();local mid=math.floor((lo+hi)/2);local v=s.mappings[mid];if v.from==glyphs[pos].glyphId then glyphs[pos].glyphId=v.to;substitutions=substitutions+1;return true,1 elseif v.from<glyphs[pos].glyphId then lo=mid+1 else hi=mid-1 end end
    elseif s.kind=='ligature'then local lo,hi=1,#s.sets;local set;while lo<=hi do charge();local mid=math.floor((lo+hi)/2);local v=s.sets[mid];if v.first==glyphs[pos].glyphId then set=v;break elseif v.first<glyphs[pos].glyphId then lo=mid+1 else hi=mid-1 end end;if set then for _,v in ipairs(set.ligatures)do charge();local match=pos+#v.components-1<=#glyphs;if match then for k=2,#v.components do charge();if glyphs[pos+k-1].glyphId~=v.components[k]then match=false;break end end end;if match then local g=glyphs[pos];g.glyphId=v.replacement;for k=2,#v.components do local other=glyphs[pos+k-1];g.clusterStart=math.min(g.clusterStart,other.clusterStart);g.clusterEnd=math.max(g.clusterEnd,other.clusterEnd)end;for k=1,#glyphs-pos-#v.components+1 do charge();glyphs[pos+k]=glyphs[pos+#v.components+k-1]end;for k=1,#v.components-1 do glyphs[#glyphs]=nil end;substitutions=substitutions+1;return true,1 end end end
    else local match=pos>#s.backtrack and pos+#s.input+#s.lookahead-1<=#glyphs
     if match then for k,cov in ipairs(s.backtrack)do if not has(cov,glyphs[pos-k].glyphId)then match=false;break end end end
     if match then for k,cov in ipairs(s.input)do if not has(cov,glyphs[pos+k-1].glyphId)then match=false;break end end end
     if match then for k,cov in ipairs(s.lookahead)do if not has(cov,glyphs[pos+#s.input+k-1].glyphId)then match=false;break end end end
     if match then for _,r in ipairs(s.records)do charge();atLookup(r.lookupIndex,pos+r.sequenceIndex)end;return true,#s.input end
    end
   end;return false,1
  end
  for _,li in ipairs(refs)do local pos=1;while pos<=#glyphs do charge();local _,advance=atLookup(li,pos);pos=pos+advance end end
  return{kind='r2u.glyph-run',schemaVersion=1,glyphs=glyphs,substitutionCount=substitutions,work=work,unicodeShapingApplied=false,canvasEquivalent='unverified'}
 end
 function M.apply(ir,selected,input,options)
  local n=validate(ir);local refs=selection(ir,selected)
  return apply(ir,n,refs,input,options)
 end
 -- Internal generated-program path only. Its lexical layout/program were
 -- validated by compileSelection; dynamic glyph/cluster/options budgets remain.
 function M.applyCompiled(ir,program,input,options)
  plain(program);if program.kind~='r2u.compiled-font-selection'or program.schemaVersion~=1 then fail('E_FONT_SHAPER_SHAPE','Invalid compiled selection')end
  return apply(ir,int(program.numGlyphs,1,65535),program.lookupIndices,input,options)
 end
 function M.validateSimpleText(text)
  if type(text)~='string'then fail('E_FONT_SHAPER_TEXT','Text must be UTF8 bytes')end;if #text>1048576 then fail('E_FONT_SHAPER_BUDGET','Text byte budget exceeded')end
  local count=0;local ok,err=pcall(function()for _,cp in utf8.codes(text)do if cp>1114111 or cp>=55296 and cp<=57343 then fail('E_FONT_SHAPER_TEXT','Invalid Unicode scalar')end;count=count+1;if count>100000 then fail('E_FONT_SHAPER_BUDGET','Text scalar budget exceeded')end
   if not (cp>=32 and cp<=126 or cp>=160 and cp<=255 and cp~=173 or cp>=0x2010 and cp<=0x2027 or cp>=0x2190 and cp<=0x21FF or cp>=0x3000 and cp<=0x303F and (cp<0x302A or cp>0x302F)or cp>=0x3041 and cp<=0x3096 or cp>=0x30A1 and cp<=0x30FC or cp>=0x3400 and cp<=0x4DBF or cp>=0x4E00 and cp<=0x9FFF or cp>=0xFF01 and cp<=0xFF5E)then fail('E_FONT_SHAPER_UNSUPPORTED','Unicode normalization/script/mark handling is unsupported for this scalar')end
  end end);if not ok then if type(err)=='table'then error(err,0)end;fail('E_FONT_SHAPER_TEXT','Invalid UTF8 text')end;return true
 end
 return M
end
