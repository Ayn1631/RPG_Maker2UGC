-- Offline source glyph pack. No shaping, hinting, IO, or executable output.
return function(deps)
 local M={};local metrics=deps['assets.font_metrics'];local outlines=deps['assets.font_outline'];local sha=deps['build.sha256']
 local function fail(code,reason,file,cp)error({severity='error',code=code,reason=reason,file=file,codepoint=cp},0)end
 function M.compile(bytes,origin,codepoints)
  local file
  local function shape(reason)fail('E_UI_FONT_SHAPE',reason,file)end
  local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then shape('Expected plain font-pack input')end end
  if origin~=nil then plain(origin);for k in next,origin do if k~='file' then shape('Unknown origin field')end end;if type(origin.file)~='string' then shape('Expected source file string')end;file=origin.file end
  if type(bytes)~='string' then shape('Expected font byte string')end
  plain(codepoints);local n,high=0,0;for k in next,codepoints do if type(k)~='number' or k%1~=0 or k<1 or k>4096 then shape('Expected dense requested codepoint array')end;n=n+1;high=math.max(high,k)end
  if n~=high or n==0 then shape('Expected 1 to 4096 requested codepoints')end
  local previous=-1;for i=1,n do local cp=codepoints[i];if type(cp)~='number' or cp~=cp or cp%1~=0 or cp<0 or cp>1114111 or cp>=55296 and cp<=57343 or cp<=previous then shape('Expected strictly increasing Unicode scalar codepoints')end;previous=cp end
  local font=metrics.parse(bytes,origin)
  for _,v in ipairs(font.layoutTables)do if v.table=='kern' or #v.features>0 then fail('E_UI_FONT_LAYOUT','Unsupported source layout table '..v.table,file)end end
  local ids={};for i,cp in ipairs(codepoints)do local low,high,id=1,#font.mappings
   while low<=high do local mid=math.floor((low+high)/2);local v=font.mappings[mid];if v.codepoint==cp then id=v.glyphId;break elseif v.codepoint<cp then low=mid+1 else high=mid-1 end end
   if not id then fail('E_UI_FONT_COVERAGE','Source font does not cover requested codepoint',file,cp)end;ids[i]=id
  end
  local reader=outlines.open(bytes,origin);local used={points=0.0,contours=0.0,components=0.0,instructionBytes=0.0};local caps={points=262144,contours=8192,components=16384,instructionBytes=1048576}
  local checked={}
  local function account(g)
   for k,cap in pairs(caps)do local stat=k=='points' and g.stats.pointsAllocated or k=='contours' and g.stats.contoursAllocated or g.stats[k];used[k]=used[k]+stat;if used[k]>cap then fail('E_UI_FONT_BUDGET','Aggregate glyph '..k..' budget exceeded',file)end end
  end
  local function inspect(g)
   if checked[g.glyphId]then return end
   for _,c in ipairs(g.components)do if c.useMyMetrics then fail('E_UI_FONT_LAYOUT','Compound USE_MY_METRICS advance inheritance is unsupported',file)end end
   for _,c in ipairs(g.components)do if not checked[c.glyphId]then local child=reader.glyph(c.glyphId);account(child);inspect(child)end end
   checked[g.glyphId]=true
  end
  local result={kind='r2u.font-pack',schemaVersion=1,unitsPerEm=font.unitsPerEm,glyphs={},source={file=file,sha256=sha.hex(bytes)},hintingApplied=false,shapingApplied=false,canvasEquivalent='unverified',approximation=true}
  for i,cp in ipairs(codepoints)do local id=ids[i];local g=reader.glyph(id);account(g);inspect(g);result.glyphs[i]={codepoint=cp,glyphId=id,advanceUnits=font.glyphs[id+1].advanceUnits,outline=g}end
  return result
 end
 return M
end
