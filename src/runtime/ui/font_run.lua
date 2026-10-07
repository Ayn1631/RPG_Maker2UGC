-- One-line simple-script layout. All measurement and drawing share this result.
return function(deps)
 local H=deps['runtime.ui.font_shaper'];local M={}
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_RUN_SHAPE','Expected plain font-run data')end end
 local function num(n,lo,hi)if type(n)~='number'or n~=n or n<lo or n>hi then fail('E_FONT_RUN_SHAPE','Invalid finite font-run number')end;return n*1.0 end
 local function int(n,lo,hi)n=num(n,lo,hi);if n%1~=0 then fail('E_FONT_RUN_SHAPE','Expected font-run integer')end;return n end
 local function dense(v,cap)plain(v);local n,high=0,0;for k in next,v do int(k,1,cap);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_FONT_RUN_SHAPE','Expected dense font-run array')end;return n end
 local function clone(v,seen,depth,budget)
  budget=budget or {nodes=0,bytes=0};budget.nodes=budget.nodes+1;if budget.nodes>2097152 then fail('E_FONT_RUN_BUDGET','Font snapshot budget exceeded')end
  local kind=type(v)
  if kind=='number'then return num(v,-9007199254740991,9007199254740991)
  elseif kind=='string'then budget.bytes=budget.bytes+#v;if budget.bytes>8388608 then fail('E_FONT_RUN_BUDGET','Font snapshot string budget exceeded')end;return v
  elseif kind=='boolean'or kind=='nil'then return v
  elseif kind~='table'then fail('E_FONT_RUN_SHAPE','Executable font-run value')end
  plain(v);depth=depth or 0;seen=seen or {};if depth>64 or seen[v]then fail('E_FONT_RUN_SHAPE','Cyclic or deeply nested font data')end
  seen[v]=true;local out={};for k,x in next,v do if type(k)~='string'and type(k)~='number'then fail('E_FONT_RUN_SHAPE','Invalid font data key')end;if type(k)=='number'then int(k,-9007199254740991,9007199254740991)end;out[k]=clone(x,seen,depth+1,budget)end;seen[v]=nil;return out
 end
 local function script(cp)
  if cp>=65 and cp<=90 or cp>=97 and cp<=122 or cp>=192 and cp<=255 and cp~=215 and cp~=247 then return'latn'end
  if cp>=0x3400 and cp<=0x4DBF or cp>=0x4E00 and cp<=0x9FFF then return'hani'end
  if cp>=0x3041 and cp<=0x3096 or cp>=0x30A1 and cp<=0x30FC then return'kana'end
  return nil
 end
 local function proofRegistry(face)
  local registry={};plain(face.source)
  if type(face.source.sha256)~='string'or #face.source.sha256~=64 or not face.source.sha256:match('^[0-9a-f]+$')then fail('E_FONT_RUN_PROOF','Invalid proof source identity')end
  local axes=dense(face.source.normalizedCoordinates,64);for _,v in ipairs(face.source.normalizedCoordinates)do num(v,-1,1)end
  if dense(face.layoutProofs,32)==0 then fail('E_FONT_RUN_PROOF','No layout proof supplied')end
  local defaults={ccmp=true,locl=true,rlig=true,liga=true,clig=true,calt=true,kern=true,mark=true,mkmk=true}
  for _,p in ipairs(face.layoutProofs)do
   plain(p);plain(p.source);plain(p.request)
   if p.kind~='r2u.font-layout-proof'or p.schemaVersion~=1 or p.proof~='no-active-lookup-intersection'or p.profile~='horizontal-ltr-default-features-no-hit-v1'or p.unicodeShapingApplied~=false
    or p.numGlyphs~=face.numGlyphs or p.source.sha256~=face.source.sha256 then fail('E_FONT_RUN_PROOF','Mismatched layout proof identity')end
   local s=p.request.script;if type(s)~='string'or not s:match('^[%g ][%g ][%g ][%g ]$')or p.request.language~='default'or registry[s]then fail('E_FONT_RUN_PROOF','Unsupported or duplicate proof request')end
   if dense(p.normalizedCoordinates,64)~=axes then fail('E_FONT_RUN_PROOF','Proof axis count mismatch')end
   for i,v in ipairs(p.normalizedCoordinates)do num(v,-1,1);if v~=face.source.normalizedCoordinates[i]then fail('E_FONT_RUN_PROOF','Proof instance coordinates mismatch')end end
   local allowed,last={},-1;if dense(p.allowedGlyphIds,65535)==0 then fail('E_FONT_RUN_PROOF','Empty proof alphabet')end
   for _,id in ipairs(p.allowedGlyphIds)do int(id,0,face.numGlyphs-1);if id<=last then fail('E_FONT_RUN_PROOF','Unsorted proof alphabet')end;last=id;allowed[id]=true end
   dense(p.selectedTables,2);local tables={}
   for _,tb in ipairs(p.selectedTables)do
    plain(tb);if tb.table~='GSUB'and tb.table~='GPOS'or tables[tb.table]or tb.present~=true or tb.script~=s and tb.script~='DFLT'or tb.language~='default'then fail('E_FONT_RUN_PROOF','Invalid selected proof table')end;tables[tb.table]=true
    if tb.featureVariationRecords~=nil then int(tb.featureVariationRecords,0,262144)end
    dense(tb.lookups,65535);dense(tb.features,65535);local refs={};last=-1
    for _,l in ipairs(tb.lookups)do plain(l);int(l.index,0,65534);if l.index<=last or l.flags~=0 or tb.table=='GSUB'and l.lookupType~=1 and l.lookupType~=4 or tb.table=='GPOS'and l.lookupType~=2 and l.lookupType~=4 then fail('E_FONT_RUN_PROOF','Unsupported proof lookup')end;last=l.index;refs[l.index]=false
     if dense(l.subtables,65535)==0 then fail('E_FONT_RUN_PROOF','Empty proof lookup')end
     for _,st in ipairs(l.subtables)do plain(st);if st.format~=1 and not(st.format==2 and (tb.table=='GSUB'and l.lookupType==1 or tb.table=='GPOS'and l.lookupType==2))then fail('E_FONT_RUN_PROOF','Unsupported proof format')end
      if tb.table=='GPOS'and l.lookupType==4 then int(st.markCoverageCount,0,face.numGlyphs);int(st.baseCoverageCount,0,face.numGlyphs)else int(st.coverageCount,0,face.numGlyphs)end
     end
    end
    last=-1;for _,f in ipairs(tb.features)do plain(f);int(f.index,0,65534);if f.index<=last or not defaults[f.tag]then fail('E_FONT_RUN_PROOF','Unsupported proof feature')end;last=f.index;dense(f.lookupIndices,65535)
     for _,id in ipairs(f.lookupIndices)do int(id,0,65534);if refs[id]==nil then fail('E_FONT_RUN_PROOF','Missing feature lookup proof')end;refs[id]=true end
    end
    for _,used in pairs(refs)do if not used then fail('E_FONT_RUN_PROOF','Unreferenced proof lookup')end end
   end
   registry[s]=allowed
  end
  return registry
 end
 -- Offline compile and strict raw new share exactly the same validation path.
 function M.compile(faces)
  if dense(faces,16)==0 then fail('E_FONT_RUN_SHAPE','At least one face is required')end
  faces=clone(faces);local bank={}
  for index,face in ipairs(faces)do
   plain(face);if face.kind~='r2u.font-face'or face.schemaVersion~=1 or face.hintingApplied~=false then fail('E_FONT_RUN_SHAPE','Invalid source face contract')end
   local units=int(face.unitsPerEm,16,16384);local total=int(face.numGlyphs,1,65535);local item={units=units,glyphs={},map={},layout=face.layout,selections={}}
   if face.layoutProofs~=nil then
    if face.layout~=nil or face.selections~=nil then fail('E_FONT_RUN_PROOF','Ambiguous layout execution path')end;item.proofs=proofRegistry(face)
   else plain(face.layout);if face.layout.numGlyphs~=total then fail('E_FONT_RUN_SHAPE','Layout glyph count disagrees with face')end end
   dense(face.glyphs,65535);local last=-1
   for _,g in ipairs(face.glyphs)do plain(g);local id=int(g.glyphId,0,total-1);if id<=last then fail('E_FONT_RUN_SHAPE','Unsorted face glyphs')end;last=id
    num(g.advanceUnits,0,1048576);plain(g.outline)
    if g.outline.kind~='r2u.font-outline'or g.outline.schemaVersion~=1 or g.outline.glyphId~=id or g.outline.unitsPerEm~=units or g.outline.hintingApplied~=false or g.outline.instructionsExecuted~=false then fail('E_FONT_RUN_SHAPE','Glyph outline identity or execution flags mismatch')end
    local expected=int(g.outline.pointCount,0,65536);local actual=0;dense(g.outline.contours,8192)
    for _,c in ipairs(g.outline.contours)do plain(c);local count=dense(c.points,65536);if count==0 then fail('E_FONT_RUN_SHAPE','Empty contour')end;actual=actual+count;if actual>65536 then fail('E_FONT_RUN_BUDGET','Glyph point budget exceeded')end
     for _,p in ipairs(c.points)do plain(p);num(p.x,-1048576,1048576);num(p.y,-1048576,1048576);if type(p.onCurve)~='boolean'then fail('E_FONT_RUN_SHAPE','Invalid on-curve flag')end end
    end
    if actual~=expected then fail('E_FONT_RUN_SHAPE','Outline point count mismatch')end;item.glyphs[id]=g
   end
   dense(face.mappings,65536);last=-1
   for _,m in ipairs(face.mappings)do plain(m);local cp=int(m.codepoint,0,1114111);local id=int(m.glyphId,1,total-1)
    if cp<=last or cp>=55296 and cp<=57343 or not item.glyphs[id]then fail('E_FONT_RUN_SHAPE','Invalid face mapping')end;last=cp;item.map[cp]=id
   end
   if not item.proofs then dense(face.selections,32)
   for _,entry in ipairs(face.selections)do plain(entry);if type(entry.script)~='string'or item.selections[entry.script]then fail('E_FONT_RUN_SHAPE','Invalid script registry')end
    local selected=H.select(face.layout,{script=entry.script})
    for _,id in ipairs(H.closure(face.layout,selected))do if not item.glyphs[id]then fail('E_FONT_RUN_SHAPE','Missing selected substitution glyph')end end;item.selections[entry.script]=H.compileSelection(face.layout,selected)
   end end
   bank[index]=item
  end
  return{kind='r2u.compiled-font-bank',schemaVersion=1,faces=bank}
 end
 -- Internal generated-program entry, never a raw-new trusted option. The bank
 -- is private trusted generated code, and is not exposed by the service.
 function M.fromCompiled(compiled)
  plain(compiled);if compiled.kind~='r2u.compiled-font-bank'or compiled.schemaVersion~=1 then fail('E_FONT_RUN_SHAPE','Invalid compiled font bank')end
  local bank=compiled.faces;local api={}
  function api.layout(text,size)
   size=num(size,1/256,512);H.validateSimpleText(text)
   local chars,missing={},{};for at,cp in utf8.codes(text)do
    if #chars>=4096 then fail('E_FONT_RUN_BUDGET','Text run glyph budget exceeded')end
    local owner,id;for fi,f in ipairs(bank)do if f.map[cp]then owner,id=fi,f.map[cp];break end end
    chars[#chars+1]={cp=cp,at=at,face=owner,glyphId=id,script=script(cp)}
    if not owner then missing[#missing+1]={codepoint=cp,byteOffset=at}end
   end
   if #missing>0 then return{coverage=false,missing=missing,run=nil,canvasEquivalent='unverified'}end
   local nextScript='DFLT';for i=#chars,1,-1 do if chars[i].script then nextScript=chars[i].script end;chars[i].followingScript=nextScript end
   local previous;for _,c in ipairs(chars)do if c.script then previous=c.script else c.script=previous or c.followingScript end end
   local result={coverage=true,missing={},run={advance=0.0,glyphs={}},clusters={},hintingApplied=false,canvasEquivalent='unverified',unicodeShapingApplied=false};local i=1;local points=0;local outputBudget={nodes=0,bytes=0};local work=0
   while i<=#chars do
    local first=chars[i];local last=i;while last<#chars and chars[last+1].face==first.face and chars[last+1].script==first.script do last=last+1 end
    local f=bank[first.face];local selected=f.proofs and f.proofs[first.script] or f.selections[first.script]
    if not selected then fail('E_FONT_RUN_SCRIPT','Source face subset lacks requested script '..first.script)end
    local input={};for at=i,last do input[#input+1]={glyphId=chars[at].glyphId,clusterStart=chars[at].at,clusterEnd=chars[at+1]and chars[at+1].at or #text+1}end
    local remaining=8388608-work;if remaining<1 then fail('E_FONT_RUN_BUDGET','Combined shaping work budget exhausted')end
    local shaped
    if f.proofs then
     for _,g in ipairs(input)do if not selected[g.glyphId]then fail('E_FONT_RUN_PROOF','Glyph is outside the certified layout alphabet')end end
     shaped={glyphs=input,work=#input}
    else shaped=H.applyCompiled(f.layout,selected,input,{maxGlyphs=4096,maxWork=remaining})end
    work=work+shaped.work;if work>8388608 then fail('E_FONT_RUN_BUDGET','Combined shaping work budget exceeded')end
    for _,g in ipairs(shaped.glyphs)do
     if g.glyphId==0 then fail('E_FONT_RUN_GLYPH','Selected substitution produced a missing glyph')end
     local source=f.glyphs[g.glyphId];if not source then fail('E_FONT_RUN_GLYPH','Unpacked substitution glyph')end
     points=points+int(source.outline.pointCount,0,65536);if points>65536 then fail('E_FONT_RUN_BUDGET','Text outline point budget exceeded')end
     result.run.glyphs[#result.run.glyphs+1]={outline=clone(source.outline,nil,0,outputBudget),fontSize=size,x=result.run.advance,y=0}
     result.clusters[#result.clusters+1]={faceIndex=first.face,glyphId=g.glyphId,byteStart=g.clusterStart,byteEnd=g.clusterEnd,script=first.script}
     result.run.advance=result.run.advance+source.advanceUnits*size/f.units;if result.run.advance>1048576 then fail('E_FONT_RUN_BUDGET','Text advance budget exceeded')end
    end;i=last+1
   end
   return result
  end
  return api
 end
 function M.new(faces)return M.fromCompiled(M.compile(faces))end
 return M
end
