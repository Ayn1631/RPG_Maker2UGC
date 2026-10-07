-- Offline selected variable fallback face. Layout is proved for this alphabet, never stripped.
return function(deps)
 local V,P,SHA=deps['assets.font_variation'],deps['assets.font_layout_proof'],deps['build.sha256'];local M={}
 local caps={glyphs=4096,points=262144,contours=16384,instructionBytes=1048576}
 local function fail(code,reason,file)error({severity='error',code=code,reason=reason,file=file},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_FALLBACK_SHAPE','Expected plain fallback data')end end
 local function integer(v,a,b)if type(v)~='number'or v~=v or v%1~=0 or v<a or v>b then fail('E_FONT_FALLBACK_SHAPE','Invalid fallback integer')end;return v*1.0 end
 local function dense(v,cap)plain(v);local n,high=0,0;for k in next,v do integer(k,1,cap);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_FONT_FALLBACK_SHAPE','Expected dense fallback array')end;return n end
 function M.compile(bytes,origin,request,limits)
  plain(request);for k in next,request do if k~='codepoints'and k~='scripts'and k~='location'then fail('E_FONT_FALLBACK_SHAPE','Unknown fallback request field')end end
  local count=dense(request.codepoints,65536);local last=-1
  for _,cp in ipairs(request.codepoints)do integer(cp,0,1114111);if cp<=last or cp>=55296 and cp<=57343 then fail('E_FONT_FALLBACK_SHAPE','Expected sorted unique Unicode scalars')end;last=cp end
  if dense(request.scripts,32)<1 then fail('E_FONT_FALLBACK_SHAPE','Select at least one script')end
  local scripts,seen={},{};for _,script in ipairs(request.scripts)do if type(script)~='string'or not script:match('^[%g ][%g ][%g ][%g ]$')or seen[script]then fail('E_FONT_FALLBACK_SHAPE','Invalid or duplicate script')end;scripts[#scripts+1]=script;seen[script]=true end;table.sort(scripts)
  if limits==nil then limits={}end;plain(limits);for k in next,limits do if not caps[k]then fail('E_FONT_FALLBACK_SHAPE','Unknown fallback limit')end end
  local cap={};for k,v in pairs(caps)do cap[k]=limits[k]~=nil and integer(limits[k],1,v)or v end
  local query=V.open(bytes,origin,request.location);local base=query.baseMetrics()
  local face={kind='r2u.font-face',schemaVersion=1,unitsPerEm=query.unitsPerEm,numGlyphs=query.numGlyphs,mappings={},missing={},glyphs={},layoutProofs={},
   source={file=base.source.file,location=query.location,axes=query.axes,normalizedCoordinates=query.normalized,variationApplied=true},hintingApplied=false,approximation=true,canvasEquivalent='unverified'}
  local cursor,needed=1,{}
  for _,cp in ipairs(request.codepoints)do
   while cursor<=#base.mappings and base.mappings[cursor].codepoint<cp do cursor=cursor+1 end
   local entry=base.mappings[cursor];if entry and entry.codepoint==cp then face.mappings[#face.mappings+1]={codepoint=cp,glyphId=entry.glyphId};needed[entry.glyphId]=true else face.missing[#face.missing+1]=cp end
  end
  local ids={};for id in next,needed do ids[#ids+1]=id end;table.sort(ids)
  if #ids>cap.glyphs then fail('E_FONT_FALLBACK_BUDGET','Fallback glyph budget exceeded',base.source.file)end
  local used={points=0.0,contours=0.0,instructionBytes=0.0}
  for _,id in ipairs(ids)do
   local g=query.glyph(id);used.points=used.points+g.stats.pointsAllocated;used.contours=used.contours+g.stats.contoursAllocated;used.instructionBytes=used.instructionBytes+g.stats.instructionBytes
   for k,v in pairs(used)do if v>cap[k]then fail('E_FONT_FALLBACK_BUDGET','Fallback '..k..' budget exceeded',base.source.file)end end
   face.glyphs[#face.glyphs+1]={glyphId=id,advanceUnits=g.metrics.advanceUnits,outline=g}
  end
  if #ids>0 then for _,script in ipairs(scripts)do face.layoutProofs[#face.layoutProofs+1]=P.prove(bytes,origin,{script=script,language='default',glyphIds=ids,normalizedCoordinates=query.normalized})end end
  face.source.sha256=face.layoutProofs[1]and face.layoutProofs[1].source.sha256 or SHA.hex(bytes)
  face.coverage=#face.missing==0;face.stats={requestedCodepoints=count,mappedCodepoints=#face.mappings,subsetGlyphs=#ids,work=used,variation=query.stats()};return face
 end
 return M
end
