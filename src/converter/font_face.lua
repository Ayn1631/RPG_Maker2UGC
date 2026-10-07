-- Offline static face subset including all glyph dependencies of selected GSUB.
return function(deps)
 local metrics=deps['assets.font_metrics'];local outlines=deps['assets.font_outline'];local layouts=deps['assets.font_layout']
 local shaper=deps['runtime.ui.font_shaper'];local sha=deps['build.sha256'];local M={}
 local function fail(code,why,file,cp)error({severity='error',code=code,reason=why,file=file,codepoint=cp},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_FACE_SHAPE','Expected plain face request')end end
 local function integer(v,lo,hi)if type(v)~='number'or v~=v or v%1~=0 or v<lo or v>hi then fail('E_FONT_FACE_SHAPE','Invalid face request integer')end;return v end
 local function dense(v,cap)plain(v);local n,high=0,0;for k in next,v do integer(k,1,cap);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_FONT_FACE_SHAPE','Expected dense face request array')end;return n end
 function M.compile(bytes,origin,request)
  plain(request);for k in next,request do if k~='codepoints'and k~='scripts'then fail('E_FONT_FACE_SHAPE','Unknown face request field')end end
  local n=dense(request.codepoints,65536);local last=-1
  for _,cp in ipairs(request.codepoints)do integer(cp,0,1114111);if cp<=last or cp>=55296 and cp<=57343 then fail('E_FONT_FACE_SHAPE','Expected sorted Unicode scalar demand')end;last=cp end
  local scripts=request.scripts;if dense(scripts,32)<1 then fail('E_FONT_FACE_SHAPE','Select at least one text script')end
  local selectedScripts={};for _,s in ipairs(scripts)do if type(s)~='string'or #s~=4 or not s:match('^[%g ][%g ][%g ][%g ]$')or selectedScripts[s]then fail('E_FONT_FACE_SHAPE','Invalid or duplicate script tag')end;selectedScripts[s]=true end
  local base=metrics.parse(bytes,origin);local layout=layouts.parse(bytes,origin);local reader=outlines.open(bytes,origin)
  local result={kind='r2u.font-face',schemaVersion=1,unitsPerEm=base.unitsPerEm,numGlyphs=base.numGlyphs,mappings={},missing={},glyphs={},layout=layout,selections={},source={file=base.source.file,sha256=sha.hex(bytes)},hintingApplied=false,approximation=true,canvasEquivalent='unverified'}
  local needed={};local cursor=1
  for _,cp in ipairs(request.codepoints)do
   while cursor<=#base.mappings and base.mappings[cursor].codepoint<cp do cursor=cursor+1 end
   local entry=base.mappings[cursor]
   if entry and entry.codepoint==cp then result.mappings[#result.mappings+1]={codepoint=cp,glyphId=entry.glyphId};needed[entry.glyphId]=true
   else result.missing[#result.missing+1]=cp end
  end
  local sorted={};for s in next,selectedScripts do sorted[#sorted+1]=s end;table.sort(sorted)
  for _,script in ipairs(sorted)do
   local selection=shaper.select(layout,{script=script});result.selections[#result.selections+1]={script=script,selection=selection}
   for _,id in ipairs(shaper.closure(layout,selection))do needed[id]=true end
  end
  local ids={};for id in next,needed do ids[#ids+1]=id end;table.sort(ids)
  local used={points=0.0,contours=0.0,components=0.0,instructionBytes=0.0};local caps={points=262144,contours=16384,components=32768,instructionBytes=1048576}
  local checked={};local function account(g)
   for k,cap in pairs(caps)do local v=k=='points'and g.stats.pointsAllocated or k=='contours'and g.stats.contoursAllocated or g.stats[k];used[k]=used[k]+v;if used[k]>cap then fail('E_FONT_FACE_BUDGET','Face subset '..k..' budget exceeded',base.source.file)end end
  end
  local inspect;inspect=function(g)
   if checked[g.glyphId]then return end
   for _,c in ipairs(g.components)do if c.useMyMetrics then fail('E_FONT_FACE_METRICS','Compound metrics inheritance is unsupported',base.source.file)end end
   for _,c in ipairs(g.components)do if not checked[c.glyphId]then local child=reader.glyph(c.glyphId);account(child);inspect(child)end end
   checked[g.glyphId]=true
  end
  for _,id in ipairs(ids)do local g=reader.glyph(id);account(g);inspect(g);result.glyphs[#result.glyphs+1]={glyphId=id,advanceUnits=base.glyphs[id+1].advanceUnits,outline=g}end
  result.coverage=#result.missing==0;result.stats={requestedCodepoints=n,mappedCodepoints=#result.mappings,subsetGlyphs=#result.glyphs,work=used}
  return result
 end
 return M
end
