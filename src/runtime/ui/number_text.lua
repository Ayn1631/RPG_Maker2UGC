-- Source gauge-number drawing; outline coverage remains explicitly unhinted.
return function(deps)
 local textRaster=deps['runtime.ui.text_raster'];local M={}
 local function fail(code,why)error({severity='error',code=code,reason=why},0)end
 local function plain(t)if type(t)~='table'or getmetatable(t)~=nil then fail('E_NUMBER_TEXT_SHAPE','Expected plain number-font data')end end
 local function num(n,lo,hi)if type(n)~='number'or n~=n or n<lo or n>hi then fail('E_NUMBER_TEXT_SHAPE','Number outside supported range')end;return n*1.0 end
 local function integer(n,lo,hi)n=num(n,lo,hi);if n%1~=0 then fail('E_NUMBER_TEXT_SHAPE','Expected integer')end;return n end
 local function dense(t,cap)plain(t);local n,high=0,0;for k in next,t do integer(k,1,cap);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_NUMBER_TEXT_SHAPE','Expected dense array')end;return n end
 local function copy(v)
  if type(v)~='table'then return v end
  local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
 end
 function M.new(pack)
  plain(pack)
  if pack.kind~='r2u.font-pack'or pack.schemaVersion~=1 or pack.hintingApplied~=false or pack.shapingApplied~=false then fail('E_NUMBER_TEXT_SHAPE','Expected source font pack')end
  local units=integer(pack.unitsPerEm,16,16384);local glyphs={};local points=0
  if dense(pack.glyphs,4096)~=10 then fail('E_NUMBER_TEXT_COVERAGE','Gauge font requires exactly ten decimal glyphs')end
  for i,e in ipairs(pack.glyphs)do
   plain(e);if e.codepoint~=47+i then fail('E_NUMBER_TEXT_COVERAGE','Gauge digits must be ordered 0 through 9')end
   local id=integer(e.glyphId,1,65535);local advance=integer(e.advanceUnits,0,65535);plain(e.outline)
   local o=e.outline
   if o.kind~='r2u.font-outline'or o.schemaVersion~=1 or o.glyphId~=id or o.unitsPerEm~=units or o.hintingApplied~=false or o.instructionsExecuted~=false then fail('E_NUMBER_TEXT_SHAPE','Invalid source outline')end
   local g={advance=advance,contours={},pointCount=0};dense(o.contours,8192)
   for _,c in ipairs(o.contours)do
    plain(c);local n=dense(c.points,65536);if n==0 then fail('E_NUMBER_TEXT_SHAPE','Empty contour')end
    points=points+n;if points>65536 then fail('E_NUMBER_TEXT_BUDGET','Number font point budget exceeded')end
    local cc={points={}};for _,p in ipairs(c.points)do plain(p);if type(p.onCurve)~='boolean'then fail('E_NUMBER_TEXT_SHAPE','Invalid on-curve flag')end
     cc.points[#cc.points+1]={x=num(p.x,-1048576,1048576),y=num(p.y,-1048576,1048576),onCurve=p.onCurve}
    end;g.contours[#g.contours+1]=cc;g.pointCount=g.pointCount+n
   end
   if o.pointCount~=g.pointCount then fail('E_NUMBER_TEXT_SHAPE','Point count mismatch')end
   g.outline={kind='r2u.font-outline',schemaVersion=1,glyphId=id,unitsPerEm=units,pointCount=g.pointCount,contours=g.contours,hintingApplied=false,instructionsExecuted=false};glyphs[i]=g
  end
  local cache,order={},{};local stats={renders=0,hits=0,entries=0,rectangles=0};local api={}
  function api.render(text,style)
   if type(text)~='string'or #text<1 or #text>16 or not text:match('^%d+$')then fail('E_NUMBER_TEXT_VALUE','Expected 1 to 16 decimal digits')end
   plain(style);for k in next,style do if k~='fontSize'and k~='lineHeight'and k~='width'and k~='strokeWidth'then fail('E_NUMBER_TEXT_SHAPE','Unknown number style')end end
   local size=num(style.fontSize,1/256,512);local height=num(style.lineHeight,1/256,512);local width=num(style.width,1/256,512);local stroke=num(style.strokeWidth,0,64)
   local key=text..':'..string.format('%.17g:%.17g:%.17g:%.17g',size,height,width,stroke)
   if cache[key]then stats.hits=stats.hits+1;return copy(cache[key])end
   local advance=0.0;for i=1,#text do advance=advance+glyphs[text:byte(i)-47].advance end
   local run={advance=advance*size/units,glyphs={}};local pointCount=0;local cursor=0.0
   for i=1,#text do local g=glyphs[text:byte(i)-47]
    pointCount=pointCount+g.pointCount;if pointCount>65536 then fail('E_NUMBER_TEXT_BUDGET','Number run point budget exceeded')end
    run.glyphs[#run.glyphs+1]={outline=g.outline,fontSize=size,x=cursor*size/units,y=0}
    cursor=cursor+g.advance
   end
   local result=textRaster.render(run,{fontSize=size,lineHeight=height,width=width,strokeWidth=stroke,align='right'})
   stats.renders=stats.renders+1
   local cost=(result.fill and #result.fill.rects or 0)+(result.stroke and #result.stroke.rects or 0)
   if cost<=32768 then
    while #order>=128 or stats.rectangles+cost>32768 do
     local oldKey=table.remove(order,1);local old=cache[oldKey];stats.rectangles=stats.rectangles-(old.fill and #old.fill.rects or 0)-(old.stroke and #old.stroke.rects or 0)
     cache[oldKey]=nil
    end
    order[#order+1]=key;cache[key]=result;stats.rectangles=stats.rectangles+cost
   end;stats.entries=#order
   return copy(result)
  end
  function api.stats()return copy(stats)end
  return api
 end
 return M
end
