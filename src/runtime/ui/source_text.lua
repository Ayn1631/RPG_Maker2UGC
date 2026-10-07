-- Shared source-font measurement and drawing, with bounded private caches.
return function(deps)
 local runs=deps['runtime.ui.font_run'];local raster=deps['runtime.ui.text_raster'];local M={}
 local function fail(code,reason,missing)error({severity='error',code=code,reason=reason,missing=missing},0)end
 local function num(v,lo,hi)if type(v)~='number'or v~=v or v<lo or v>hi then fail('E_SOURCE_TEXT_STYLE','Invalid finite text style number')end;return v*1.0 end
 local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
 local function cache(cap,costCap)
  local values,order,cost={},{},0
  return {
   get=function(key)return values[key]and values[key].value end,
   put=function(key,value,n)
    if n>costCap then return end
    while #order>=cap or cost+n>costCap do local old=table.remove(order,1);cost=cost-values[old].cost;values[old]=nil end
    values[key]={value=value,cost=n};order[#order+1]=key;cost=cost+n
   end,
   stats=function()return {entries=#order,cost=cost}end,
  }
 end
 local function create(font)
  local layouts,frames=cache(128,32768),cache(128,65536)
  local stats={layouts=0,layoutHits=0,renders=0,renderHits=0};local api={}
  local function layout(text,size)
   size=num(size,1/256,512)
   if type(text)~='string'or #text>16384 then fail('E_SOURCE_TEXT_VALUE','Expected a bounded text line')end
   local key=string.format('%.17g:',size)..text;local run=layouts.get(key)
   if run then stats.layoutHits=stats.layoutHits+1;return run end
   local result=font.layout(text,size)
   if not result.coverage then fail('E_SOURCE_TEXT_COVERAGE','Text contains characters outside the imported font chain',result.missing)end
   run=result.run;local points=0;for _,g in ipairs(run.glyphs)do points=points+g.outline.pointCount end
   layouts.put(key,run,math.max(points,#run.glyphs));stats.layouts=stats.layouts+1;return run
  end
  function api.measure(text,size)return layout(text,size).advance end
  function api.render(text,style)
   if type(style)~='table'or getmetatable(style)~=nil then fail('E_SOURCE_TEXT_STYLE','Expected plain text style')end
   for k in next,style do if not ({fontSize=true,lineHeight=true,width=true,strokeWidth=true,align=true,offsetX=true,offsetY=true})[k]then fail('E_SOURCE_TEXT_STYLE','Unknown text style field')end end
   local size=num(style.fontSize,1/256,512);local height=num(style.lineHeight,1/256,4096);local width=num(style.width,0,4096);local stroke=num(style.strokeWidth,0,64)
   local align=style.align;if align~='left'and align~='center'and align~='right'then fail('E_SOURCE_TEXT_STYLE','Unsupported text alignment')end
   local ox=num(style.offsetX==nil and 0 or style.offsetX,-32768,32768);local oy=num(style.offsetY==nil and 0 or style.offsetY,-32768,32768)
   local run=layout(text,size)
   local key=string.format('%.17g:%.17g:%.17g:%.17g:%.17g:%.17g:',size,height,width,stroke,ox,oy)..align..':'..text
   local result=frames.get(key)
   if result then stats.renderHits=stats.renderHits+1;return copy(result)end
   result=raster.render(run,{fontSize=size,lineHeight=height,width=width,strokeWidth=stroke,align=align,offsetX=ox,offsetY=oy});stats.renders=stats.renders+1
   frames.put(key,result,(result.fill and #result.fill.rects or 0)+(result.stroke and #result.stroke.rects or 0))
   return copy(result)
  end
  function api.stats()local out=copy(stats);out.layoutCache=layouts.stats();out.frameCache=frames.stats();return out end
  return api
 end
 function M.new(faces)return create(runs.new(faces))end
 -- Used only by the trusted generated.ui_fonts factory with its private bank.
 function M.newCompiled(bank)return create(runs.fromCompiled(bank))end
 return M
end
