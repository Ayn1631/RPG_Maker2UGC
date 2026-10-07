-- Offline geometric colour collage. Runtime receives only immutable rectangles.
return function(deps)
 local D=deps['contracts.diagnostic'];local M={}
 local function fail(s)D.raise('E_PRIMITIVE_ART',s)end
 function M.merge(grid,w,h,palette,sx,sy)
  local out,previous={},{}
  for y=0,h-1 do local current={};local x=0
   while x<w do local c=grid[y*w+x+1] or 0;local right=x+1
    while right<w and (grid[y*w+right+1] or 0)==c do right=right+1 end
    if c~=0 then local key=x..':'..(right-x)..':'..c;local r=previous[key]
     if r then r.height=r.height+sy else r={x=x*sx,y=y*sy,width=(right-x)*sx,height=sy,colorIndex=c};out[#out+1]=r end
     current[key]=r
    end;x=right
   end;previous=current
  end
  return{kind='r2u.primitive-frame',schemaVersion=1,width=w*sx,height=h*sy,palette=palette,rects=out}
 end
 function M.redraw(image,cols,rows,options)
  if type(image.rgba)~='string' or #image.rgba~=image.width*image.height*4 then fail('Invalid RGBA source')end
  cols,rows=cols or 4,rows or 4;options=options or {}
  local maxColors,quantum,budget=options.colors or 4,options.quantum or 48,options.maxRects or 64
  if cols%1~=0 or rows%1~=0 or cols<1 or rows<1 or cols>64 or rows>64
   or maxColors%1~=0 or maxColors<2 or maxColors>16 or quantum<1 or quantum>128
   or budget%1~=0 or budget<4 or budget>512 then fail('Invalid redraw detail budget')end
  local samples,hist={},{}
  for gy=0,rows-1 do for gx=0,cols-1 do
   local r,g,b,a,n=0,0,0,0,0
   for y=math.floor(gy*image.height/rows),math.floor((gy+1)*image.height/rows)-1 do
    for x=math.floor(gx*image.width/cols),math.floor((gx+1)*image.width/cols)-1 do
     local R,G,B,A=image.rgba:byte((y*image.width+x)*4+1,(y*image.width+x)*4+4)
     r,g,b,a,n=r+R*A,g+G*A,b+B*A,a+A,n+1
    end
   end
   local c
   if n>0 and a/n>=80 then
    local function q(v)return math.max(0,math.min(255,math.floor(v/a/quantum+.5)*quantum))end
    c={q(r),q(g),q(b),255};local key=table.concat(c,',');hist[key]=hist[key] or {color=c,count=0,key=key};hist[key].count=hist[key].count+1
   end;samples[#samples+1]=c or false
  end end
  local colors={};for _,v in pairs(hist)do colors[#colors+1]=v end
  table.sort(colors,function(a,b)return a.count>b.count or a.count==b.count and a.key<b.key end)
  local palette={}
  -- Keep distinct small accents (eyes, doors, trim), not just the most common
  -- background colours. Stable ordering makes repeated exports deterministic.
  for i=1,math.min(maxColors,#colors)do
   local best,score=1,-1
   for j,entry in ipairs(colors)do if not entry.selected then
    local distance=195075
    for _,p in ipairs(palette)do local c=entry.color;distance=math.min(distance,(c[1]-p[1])^2+(c[2]-p[2])^2+(c[3]-p[3])^2)end
    local value=distance*math.sqrt(entry.count)
    if value>score then best,score=j,value end
   end end
   colors[best].selected=true;palette[i]=colors[best].color
  end
  local grid={};for i,c in ipairs(samples)do local best,distance=0,math.huge
   if c then for j,p in ipairs(palette)do local d=(c[1]-p[1])^2+(c[2]-p[2])^2+(c[3]-p[3])^2;if d<distance then best,distance=j,d end end end
   grid[i]=best
  end
  local frame=M.merge(grid,cols,rows,palette,image.width/cols,image.height/rows)
  if #frame.rects>budget then
   if maxColors>4 then return M.redraw(image,cols,rows,{colors=maxColors-2,quantum=quantum,maxRects=budget})end
   if cols>1 or rows>1 then return M.redraw(image,math.max(1,math.floor(cols/2)),math.max(1,math.floor(rows/2)),{colors=maxColors,quantum=quantum,maxRects=budget})end
  end
  frame.grid,frame.cols,frame.rows=grid,cols,rows;return frame
 end
 function M.validate(frame)
  if type(frame)~='table' or frame.kind~='r2u.primitive-frame' or frame.schemaVersion~=1 then fail('Expected primitive frame')end
  local function num(n,lo,hi)return type(n)=='number' and n==n and n>=lo and n<=hi end
  if not num(frame.width,1,4096) or not num(frame.height,1,4096) or type(frame.rects)~='table' or #frame.rects>512 or type(frame.palette)~='table' or #frame.palette>16 then fail('Primitive frame budget exceeded')end
  if frame.tileLayout then
   local p=frame.tileLayout
   if type(p)~='table' or not num(p.x,-4096,4096) or not num(p.y,-4096,4096)
    or p.width~=frame.width or p.height~=frame.height then fail('Invalid primitive tile layout')end
  end
  for _,p in ipairs(frame.palette)do if #p~=4 then fail('Expected RGBA colour')end;for _,v in ipairs(p)do if not num(v,0,255) or v%1~=0 then fail('Invalid colour')end end end
  for _,r in ipairs(frame.rects)do
   if r.imageId~=nil and r.imageId~=100001 and r.imageId~=100002 and r.imageId~=100003 then fail('Unsupported primitive image ID')end
   if r.rotation~=nil and not num(r.rotation,-180,180)then fail('Invalid primitive rotation')end
   if not num(r.x,0,frame.width) or not num(r.y,0,frame.height) or not num(r.width,.001,frame.width-r.x+1e-7) or not num(r.height,.001,frame.height-r.y+1e-7) or not frame.palette[r.colorIndex]then fail('Rectangle outside primitive frame')end
  end
  return frame
 end
 return M
end
