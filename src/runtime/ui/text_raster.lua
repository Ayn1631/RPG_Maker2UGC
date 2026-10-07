-- One already-shaped drawText run. No strings, font lookup, IO or host state.
return function(deps)
 local raster,rects=deps['assets.font_raster'],deps['assets.rectframe'];local M={}
 local caps={glyphs=4096,points=65536,contours=8192,edges=65536,width=4096,height=512,pixels=262144,curveDepth=16,work=33554432,rects=100000}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_TEXT_RASTER_SHAPE','Expected plain text raster data')end end
 local function fields(v,allowed)plain(v);for k in next,v do if not allowed[k]then fail('E_TEXT_RASTER_SHAPE','Unknown text raster field')end end end
 local function num(v,lo,hi)if type(v)~='number'or v~=v or v<lo or v>hi then fail('E_TEXT_RASTER_SHAPE','Invalid finite text raster number')end;return v*1.0 end
 local function integer(v,lo,hi)v=num(v,lo,hi);if v%1~=0 then fail('E_TEXT_RASTER_SHAPE','Expected text raster integer')end;return v end
 local function dense(v,maximum)plain(v);local n,high=0,0;for k in next,v do integer(k,1,maximum);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_TEXT_RASTER_SHAPE','Expected dense text raster array')end;return n end
 function M.render(run,style,limits)
  fields(run,{advance=true,glyphs=true});fields(style,{fontSize=true,lineHeight=true,width=true,strokeWidth=true,align=true,offsetX=true,offsetY=true})
  if limits==nil then limits={}end;fields(limits,caps)
  local cap={};for k,v in pairs(caps)do cap[k]=limits[k]~=nil and integer(limits[k],1,v)or v end
  local advance=num(run.advance,0,1048576);local size=num(style.fontSize,1/256,512);local height=num(style.lineHeight,1/256,4096)
  local width=num(style.width,0,4096);local effectiveWidth=width==0 and 4294967295.0 or width
  local stroke=num(style.strokeWidth,0,64);local align=style.align
  local offsetX=num(style.offsetX==nil and 0 or style.offsetX,-32768,32768);local offsetY=num(style.offsetY==nil and 0 or style.offsetY,-32768,32768)
  if align~='left'and align~='center'and align~='right'then fail('E_TEXT_RASTER_SHAPE','Unsupported text alignment')end
  local count=dense(run.glyphs,caps.glyphs);if count>cap.glyphs then fail('E_TEXT_RASTER_BUDGET','Glyph count budget exceeded')end
  local stats={glyphs=count,points=0,contours=0,workUsed=0.0,rasterWork=0,rectangles=0}
  local function charge(n)stats.workUsed=stats.workUsed+n;if stats.workUsed>cap.work then fail('E_TEXT_RASTER_BUDGET','Text raster work budget exceeded')end end
  local function remaining()local n=cap.work-stats.workUsed;if n<1 then fail('E_TEXT_RASTER_BUDGET','Text raster work budget exhausted')end;return n end
  local merged={kind='r2u.font-outline',schemaVersion=1,glyphId=0,unitsPerEm=16,pointCount=0,contours={},hintingApplied=false,instructionsExecuted=false}
  for _,g in ipairs(run.glyphs)do
   charge(1);fields(g,{outline=true,fontSize=true,x=true,y=true})
   local fontSize=num(g.fontSize,1/256,512);local ox,oy=num(g.x,-1048576,1048576),num(g.y,-1048576,1048576)
   local o=g.outline;plain(o)
   if o.kind~='r2u.font-outline'or o.schemaVersion~=1 or o.hintingApplied~=false or o.instructionsExecuted~=false then fail('E_TEXT_RASTER_SHAPE','Expected unhinted glyph outline')end
   integer(o.glyphId,0,65535);local units=integer(o.unitsPerEm,16,16384);local expected=integer(o.pointCount,0,65536)
   local nc=dense(o.contours,caps.contours);stats.contours=stats.contours+nc;if stats.contours>cap.contours then fail('E_TEXT_RASTER_BUDGET','Contour count budget exceeded')end
   local glyphPoints=0;local factor=fontSize/units
   for _,contour in ipairs(o.contours)do
    charge(1);plain(contour);local n=dense(contour.points,caps.points);if n==0 then fail('E_TEXT_RASTER_SHAPE','Empty contour must be omitted')end
    glyphPoints=glyphPoints+n;stats.points=stats.points+n;if stats.points>cap.points then fail('E_TEXT_RASTER_BUDGET','Point count budget exceeded')end
    local target={points={}}
    for _,p in ipairs(contour.points)do
     charge(1);plain(p);if type(p.onCurve)~='boolean'then fail('E_TEXT_RASTER_SHAPE','Expected on-curve flag')end
     local x=num(p.x,-1048576,1048576)*factor+ox;local y=num(p.y,-1048576,1048576)*factor+oy
     target.points[#target.points+1]={x=num(x,-1048576,1048576),y=num(y,-1048576,1048576),onCurve=p.onCurve}
    end;merged.contours[#merged.contours+1]=target
   end
   if expected~=glyphPoints then fail('E_TEXT_RASTER_SHAPE','Glyph point count mismatch')end
  end
  merged.pointCount=stats.points
  local scaleX=advance>effectiveWidth and effectiveWidth/advance or 1
  local spare=effectiveWidth-advance*scaleX;local origin=align=='right'and spare or align=='center'and spare/2 or 0
  -- The source width-zero sentinel can place centered ink across int32 max.
  origin=origin+offsetX
  local ix=math.floor(origin)*1.0;local baseline=math.floor(offsetY+height/2+size*.35+.5)-offsetY
  local rasterLimits={};for _,k in ipairs({'points','contours','edges','width','height','pixels','curveDepth'})do rasterLimits[k]=cap[k]end;rasterLimits.work=remaining()
  local mask=raster.render(merged,{fontSize=16,strokeWidth=stroke,phaseX=origin-ix,horizontalScale=scaleX},rasterLimits)
  stats.rasterWork=mask.stats.workUsed;charge(stats.rasterWork)
  local function frame(alpha)
   if mask.empty then return nil end
   charge(#alpha);local rgba={};for i=1,#alpha do rgba[i]=string.char(255,255,255,alpha:byte(i))end
   local result=rects.compile({width=mask.width,height=mask.height,rgba=table.concat(rgba)},
    {x=0,y=0,width=mask.width,height=mask.height},
    {pixels=cap.pixels,rects=math.max(1,cap.rects-stats.rectangles),work=math.min(8388608,remaining())})
   charge(result.stats.work);stats.rectangles=stats.rectangles+#result.rects
   if stats.rectangles>cap.rects then fail('E_TEXT_RASTER_BUDGET','Combined fill and stroke rectangle budget exceeded')end
   return result
  end
  local result={x=ix+mask.left-offsetX,y=baseline+mask.top,baseline=baseline,advance=advance,scaleX=scaleX,
   fill=frame(mask.fillAlpha),stroke=frame(mask.strokeAlpha),stats=stats,hintingApplied=false,approximation=true,canvasEquivalent='unverified'}
  return result
 end
 return M
end
