-- Bounded, unhinted quadratic-outline coverage. No font bytecode, IO or host API.
return function()
 local M={}
 local caps={points=65536,contours=8192,edges=65536,width=4096,height=512,pixels=262144,curveDepth=16,work=33554432}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_FONT_RASTER_SHAPE','Expected plain raster data')end end
 local function finite(v,lo,hi)
  if type(v)~='number' or v~=v or v<lo or v>hi then fail('E_FONT_RASTER_SHAPE','Invalid finite raster number')end;return v*1.0
 end
 local function integer(v,lo,hi)local n=finite(v,lo,hi);if n%1~=0 then fail('E_FONT_RASTER_SHAPE','Expected raster integer')end;return n end
 local function dense(v)
  plain(v);local n,high=0,0;for k in next,v do integer(k,1,262144);n=n+1;high=math.max(high,k)end
  if n~=high then fail('E_FONT_RASTER_SHAPE','Expected dense outline array')end;return n
 end
 local function midpoint(a,b)return{x=(a.x+b.x)/2,y=(a.y+b.y)/2,onCurve=true}end
 function M.render(glyph,options,limits)
  plain(glyph);plain(options);if limits==nil then limits={}end;plain(limits)
  if glyph.kind~='r2u.font-outline' or glyph.schemaVersion~=1 or glyph.hintingApplied~=false or glyph.instructionsExecuted~=false then fail('E_FONT_RASTER_SHAPE','Expected unhinted source glyph outline')end
  local glyphId=integer(glyph.glyphId,0,65535);local units=integer(glyph.unitsPerEm,16,16384)
  local expectedPoints=integer(glyph.pointCount,0,262144)
  local allowed={fontSize=true,strokeWidth=true,samples=true,phaseX=true,phaseY=true,horizontalScale=true}
  for k in next,options do if not allowed[k]then fail('E_FONT_RASTER_SHAPE','Unknown raster option')end end
  for k in next,limits do if not caps[k]then fail('E_FONT_RASTER_SHAPE','Unknown raster limit')end end
  local cap={};for k,v in pairs(caps)do cap[k]=limits[k]~=nil and integer(limits[k],1,v) or v end
  local size=finite(options.fontSize,1/256,512);local scale=size/units
  local stroke=options.strokeWidth~=nil and finite(options.strokeWidth,0,64)or 0
  local horizontalScale=options.horizontalScale~=nil and finite(options.horizontalScale,0,1)or 1
  if horizontalScale==0 then fail('E_FONT_RASTER_SHAPE','Horizontal scale must be positive')end
  local samples=options.samples~=nil and integer(options.samples,1,16)or 8
  if samples~=1 and samples~=2 and samples~=4 and samples~=8 and samples~=16 then fail('E_FONT_RASTER_SHAPE','Samples must be a power of two up to 16')end
  local phaseX=options.phaseX~=nil and finite(options.phaseX,0,1)or 0
  local phaseY=options.phaseY~=nil and finite(options.phaseY,0,1)or 0
  if phaseX==1 or phaseY==1 then fail('E_FONT_RASTER_SHAPE','Pixel phase must be less than one')end
  local stats={points=0,contours=0,edges=0,workUsed=0.0,subpixelRows=0}
  local function charge(n)stats.workUsed=stats.workUsed+n;if stats.workUsed>cap.work then fail('E_FONT_RASTER_BUDGET','Raster work budget exceeded')end end
  local contours={};local minx,miny,maxx,maxy
  local contourCount=dense(glyph.contours);if contourCount>cap.contours then fail('E_FONT_RASTER_BUDGET','Contour budget exceeded')end
  for _,contour in ipairs(glyph.contours)do
   plain(contour);local n=dense(contour.points);if n<1 then fail('E_FONT_RASTER_SHAPE','Empty contour must be omitted')end
   stats.points=stats.points+n;if stats.points>cap.points then fail('E_FONT_RASTER_BUDGET','Point budget exceeded')end
   local points={};for _,p in ipairs(contour.points)do
    charge(1);plain(p);if type(p.onCurve)~='boolean'then fail('E_FONT_RASTER_SHAPE','Missing on-curve flag')end
    local x=finite(p.x,-1048576,1048576)*scale*horizontalScale+phaseX;local y=-finite(p.y,-1048576,1048576)*scale+phaseY
    minx=minx and math.min(minx,x)or x;maxx=maxx and math.max(maxx,x)or x
    miny=miny and math.min(miny,y)or y;maxy=maxy and math.max(maxy,y)or y
    points[#points+1]={x=x,y=y,onCurve=p.onCurve}
   end;contours[#contours+1]=points
  end
  stats.contours=contourCount;if stats.points~=expectedPoints then fail('E_FONT_RASTER_SHAPE','Outline point count mismatch')end
  local tolerance=1/(samples*4);local radius=stroke/2
  local result={kind='r2u.font-raster',schemaVersion=1,glyphId=glyphId,fontSize=size,strokeWidth=stroke,samples=samples,
   phaseX=phaseX,phaseY=phaseY,horizontalScale=horizontalScale,flattenTolerance=tolerance,hintingApplied=false,approximation=true,canvasEquivalent='unverified',stats=stats}
  local function empty()result.empty=true;result.left=0;result.top=0;result.width=0;result.height=0;result.fillAlpha='';result.strokeAlpha='';return result end
  if not minx then return empty()end
  local left,top=math.floor(minx-radius*horizontalScale),math.floor(miny-radius)
  local width,height=(math.ceil(maxx+radius*horizontalScale)-left)*1.0,(math.ceil(maxy+radius)-top)*1.0
  if width>cap.width or height>cap.height or width*height>cap.pixels then fail('E_FONT_RASTER_BUDGET','Raster dimensions exceed budget')end
  if width<=0 or height<=0 then return empty()end
  local edges={}
  local function line(a,b)
   charge(1);local dx,dy=b.x-a.x,b.y-a.y;local lengthSquared=dx*dx+dy*dy
   if lengthSquared==0 then return end
   if #edges>=cap.edges then fail('E_FONT_RASTER_BUDGET','Flattened edge budget exceeded')end
   local e={a=a,b=b,dx=dx,dy=dy,low=math.min(a.y,b.y),high=math.max(a.y,b.y)}
   if radius>0 then
    -- Canvas maxWidth condenses both the glyph and its stroked outline.
    local originalDx=dx/horizontalScale;local length=math.sqrt(originalDx*originalDx+dy*dy)
    local nx,ny=-dy/length*radius*horizontalScale,originalDx/length*radius
    e.quad={{x=a.x+nx,y=a.y+ny},{x=b.x+nx,y=b.y+ny},{x=b.x-nx,y=b.y-ny},{x=a.x-nx,y=a.y-ny}}
   end
   edges[#edges+1]=e
  end
  local function curve(a,b,c,depth)
   charge(1);local dx,dy=a.x-2*b.x+c.x,a.y-2*b.y+c.y
   -- A quadratic's deviation from its endpoint chord is bounded by |P0-2P1+P2|/4.
   if dx*dx+dy*dy<=16*tolerance*tolerance then line(a,c);return end
   if depth>=cap.curveDepth then fail('E_FONT_RASTER_BUDGET','Quadratic subdivision depth exceeded')end
   local ab,bc=midpoint(a,b),midpoint(b,c);local middle=midpoint(ab,bc)
   curve(a,ab,middle,depth+1);curve(middle,bc,c,depth+1)
  end
  for _,points in ipairs(contours)do
   local n=#points;local first,last=points[1],points[n];local start,from,to
   if first.onCurve then start,from,to=first,2,n
   elseif last.onCurve then start,from,to=last,1,n-1
   else start,from,to=midpoint(last,first),1,n end
   local current,control=start,nil
   for i=from,to do local p=points[i]
    if p.onCurve then
     if control then curve(current,control,p,0)else line(current,p)end;current,control=p,nil
    else
     if control then local middle=midpoint(control,p);curve(current,control,middle,0);current=middle end
     control=p
    end
   end
   if control then curve(current,control,start,0)else line(current,start)end
  end
  stats.edges=#edges;if #edges==0 then return empty()end
  local fillCounts,strokeCounts={},{}
  local function span(counts,row,x0,x1)
   if x1<=x0 then return end
   local first=math.max(0,math.ceil((x0-left)*samples-.5))
   local last=math.min(width*samples-1,math.ceil((x1-left)*samples-.5)-1)
   if first>last then return end
   local p0,p1=math.floor(first/samples),math.floor(last/samples);charge(p1-p0+1)
   for p=p0,p1 do
    local amount=math.min(last,(p+1)*samples-1)-math.max(first,p*samples)+1
    local index=row*width+p+1;counts[index]=(counts[index]or 0)+amount
   end
  end
  local function sorted(values,key)
   if #values>1 then charge(#values*(math.ceil(math.log(#values)/math.log(2))+1));table.sort(values,function(a,b)return a[key]<b[key]end)end
  end
  local function strokeIntervals(e,y,out,seen)
   local lo,hi
   for i=1,4 do local a,b=e.quad[i],e.quad[i%4+1]
    if (a.y<=y and y<b.y)or(b.y<=y and y<a.y)then
     local x=a.x+(b.x-a.x)*((y-a.y)/(b.y-a.y));lo=lo and math.min(lo,x)or x;hi=hi and math.max(hi,x)or x
    end
   end
   if lo and hi>lo then out[#out+1]={lo=lo,hi=hi}end
   -- Adjacent internal edges share endpoint identity. Its identical round-cap
   -- interval is needed once per sample row; union coverage is unchanged.
   for endpoint=1,2 do local p=endpoint==1 and e.a or e.b
    if not seen[p]then seen[p]=true;local dy=y-p.y
     if math.abs(dy)<radius then local dx=math.sqrt(math.max(0,radius*radius-dy*dy))*horizontalScale;out[#out+1]={lo=p.x-dx,hi=p.x+dx}end
    end
   end
  end
  local rows=height*samples;stats.subpixelRows=rows
  local candidates,lastBand=edges,-1
  for scan=0,rows-1 do
   local y=top+(scan+.5)/samples;local row=math.floor(scan/samples);local crossings,intervals,seen={},{},{}
   local band=math.floor(row/4)
   if band~=lastBand then
    lastBand=band;candidates={};local lo=top+band*4;local hi=math.min(top+height,lo+4);charge(#edges)
    -- Preserve original edge order and exact per-sample tests below. Only one
    -- four-pixel band's candidates are retained; preprocessing is budgeted.
    for _,e in ipairs(edges)do if e.high+radius>=lo and e.low-radius<=hi then candidates[#candidates+1]=e end end
   end
   charge(#candidates)
   for _,e in ipairs(candidates)do
    if y>=e.low and y<e.high then crossings[#crossings+1]={x=e.a.x+e.dx*((y-e.a.y)/e.dy),w=e.dy>0 and 1 or -1}end
    if radius>0 and y>=e.low-radius and y<=e.high+radius then charge(6);strokeIntervals(e,y,intervals,seen)end
   end
   sorted(crossings,'x');local previous,winding,i=nil,0,1
   while i<=#crossings do
    local x=crossings[i].x;if previous and winding~=0 then span(fillCounts,row,previous,x)end
    repeat winding=winding+crossings[i].w;i=i+1 until i>#crossings or crossings[i].x~=x
    previous=x
   end
   if winding~=0 then fail('E_FONT_RASTER_SHAPE','Unbalanced closed glyph crossings')end
   sorted(intervals,'lo');local lo,hi
   for _,v in ipairs(intervals)do
    if not lo then lo,hi=v.lo,v.hi
    elseif v.lo<=hi then hi=math.max(hi,v.hi)
    else span(strokeCounts,row,lo,hi);lo,hi=v.lo,v.hi end
   end
   if lo then span(strokeCounts,row,lo,hi)end
  end
  local denominator=samples*samples
  local function encode(counts)
   charge(width*height);local out={}
   for y=0,height-1 do local row={};for x=0,width-1 do
    local n=counts[y*width+x+1]or 0;if n<0 or n>denominator then fail('E_FONT_RASTER_SHAPE','Coverage exceeds one pixel')end
    row[#row+1]=string.char(math.floor(n*255/denominator+.5))
   end;out[#out+1]=table.concat(row)end;return table.concat(out)
  end
  result.empty=false;result.left=left;result.top=top;result.width=width;result.height=height
  result.fillAlpha=encode(fillCounts);result.strokeAlpha=encode(strokeCounts);return result
 end
 return M
end
