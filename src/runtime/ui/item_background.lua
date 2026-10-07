-- MZ's integer itemRect background, approximated without Canvas gradient dither.
-- The caller owns placement, fractional viewport clipping, and layer opacity.
return function(deps)
 local R=deps['assets.rectframe'];local M={}
 local caps={width=4094,height=510,pixels=262144,rects=8192,work=1048576}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function integer(n,lo,hi)
  if type(n)~='number'or n%1~=0 or n<lo or n>hi then fail('E_ITEM_BACKGROUND_SHAPE','Expected bounded finite integer')end
  return n*1.0
 end
 local function round(n)return math.floor(n+0.5)end
 local function span(p,lo,hi)return math.max(0,math.min(p+1,hi)-math.max(p,lo))end
 function M.render(width,height,limits)
  width=integer(width,1,caps.width);height=integer(height,1,caps.height)
  if limits==nil then limits={}end
  if type(limits)~='table'or getmetatable(limits)~=nil then fail('E_ITEM_BACKGROUND_SHAPE','Expected plain limits')end
  for k in next,limits do if not caps[k]then fail('E_ITEM_BACKGROUND_SHAPE','Unknown limit')end end
  local cap={};for k,v in pairs(caps)do local n=rawget(limits,k);if n==nil then n=v end;cap[k]=integer(n,1,v)end
  local iw,ih=width+2,height+2;local pixels=iw*ih
  if width>cap.width or height>cap.height or pixels>cap.pixels or pixels>=cap.work then fail('E_ITEM_BACKGROUND_BUDGET','Background dimensions or work budget exceeded')end
  local rows={}
  for y=-1,height do
   local outerY=span(y,-0.5,height+0.5);local innerY=span(y,0.5,height-0.5)
   local function pixel(x)
    local inside=x>=0 and x<width and y>=0 and y<height
    local fillAlpha=inside and 128 or 0
    -- Quantize premultiplied gradient first, then source-over the stroke.
    local fill=inside and round(16*(1-(y+0.5)/height))or 0
    local coverage=span(x,-0.5,width+0.5)*outerY-span(x,0.5,width-0.5)*innerY
    local sa=round(127.5*coverage);local sp=round(16*coverage)
    local alpha=round(sa+fillAlpha*(1-sa/255));local premul=round(sp+fill*(1-sa/255))
    local gray=alpha>0 and round(premul*255/alpha)or 0
    return string.char(gray,gray,gray,alpha)
   end
   if width==1 then rows[#rows+1]=pixel(-1)..pixel(0)..pixel(1)
   else rows[#rows+1]=pixel(-1)..pixel(0)..string.rep(pixel(1),width-2)..pixel(width-1)..pixel(width)end
  end
  local image={width=iw,height=ih,rgba=table.concat(rows)}
  local frame=R.compile(image,{x=0,y=0,width=iw,height=ih},{pixels=cap.pixels,rects=cap.rects,work=cap.work-pixels})
  return{originX=-1,originY=-1,frame=frame,approximation=true,canvasEquivalent='unverified',
   stats={pixels=pixels,rectangles=#frame.rects,workUsed=pixels+frame.stats.work}}
 end
 return M
end
