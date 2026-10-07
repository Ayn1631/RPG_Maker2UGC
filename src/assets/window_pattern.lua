-- Offline recognition only. Geometry is explicitly an approximation of source pixels.
return function()
 local M={};local allowed={width=true,height=true,rgba=true,colorType=true,bitDepth=true}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function dimension(n)
  if type(n)~='number' or n%1~=0 or n<1 or n>4096 then fail('E_WINDOW_PATTERN_BOUNDS','Image dimension must be an integer from 1 to 4096')end
  return n*1.0
 end
 function M.detect(image)
  if type(image)~='table' or getmetatable(image)~=nil then fail('E_WINDOW_PATTERN_SHAPE','Expected plain decoded PNG image')end
  for k in next,image do if not allowed[k]then fail('E_WINDOW_PATTERN_SHAPE','Unknown image field')end end
  local w,h=dimension(rawget(image,'width')),dimension(rawget(image,'height'))
  if w*h>1048576 then fail('E_WINDOW_PATTERN_BUDGET','Image exceeds PNG/RectFrame pixel budget')end
  local rgba=rawget(image,'rgba');if type(rgba)~='string' or #rgba~=w*h*4.0 then fail('E_WINDOW_PATTERN_SHAPE','RGBA byte count does not match dimensions')end
  local kind,depth=rawget(image,'colorType'),rawget(image,'bitDepth')
  if (kind~=nil and kind~=3 and kind~=6)or(depth~=nil and depth~=8)then fail('E_WINDOW_PATTERN_SHAPE','Unexpected decoded PNG metadata')end
  if w<96 or h<192 then return nil end
  local color
  for y=0,95 do for x=0,95 do
   local offset=((y+96.0)*w+x)*4.0+1.0
   local r,g,b,a=rgba:byte(offset,offset+3.0)
   if (x+y)%3==0 then
    if a==0 then return nil end
    if not color then color={r,g,b,a}
    elseif r~=color[1]or g~=color[2]or b~=color[3]or a~=color[4]then return nil end
   elseif a~=0 then return nil end
  end end
  return{kind='r2u.window-pattern-geometry',schemaVersion=1,approximation=true,period=3,phase=0,color=color,
   lineWidth=1/math.sqrt(2),lineOffset=1,rotationDegrees=45,sourceRegion={x=0,y=96,width=96,height=96},verifiedPixels=9216}
 end
 return M
end
