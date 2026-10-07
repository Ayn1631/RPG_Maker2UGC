-- Compile the source Window.png regions once; runtime only consumes RectFrames.
return function(deps)
 local P,R,S,B,G=deps['assets.png'],deps['assets.rectframe'],deps['build.sha256'],deps['assets.window_back'],deps['assets.window_pattern'];local M={}
 local function fail(reason)error({severity='error',code='E_UI_SKIN',reason=reason},0)end
 function M.compile(bytes,ui)
  if type(ui)~='table' or getmetatable(ui)~=nil or type(ui.window)~='table' or getmetatable(ui.window)~=nil then fail('UI source configuration required')end
  local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported source skin profile')end
  local image=P.decode(bytes);if image.width<192 or image.height<192 then fail('Window skin must contain the original 192 by 192 regions')end
  local function crop(x,y,w,h)return R.compile(image,{x=x,y=y,width=w,height=h})end
  local function parts(x,y,w,h,m,center)
   local out={margin=m,sourceWidth=w,sourceHeight=h,tl=crop(x,y,m,m),tr=crop(x+w-m,y,m,m),bl=crop(x,y+h-m,m,m),br=crop(x+w-m,y+h-m,m,m),
    top=crop(x+m,y,w-m*2,m),bottom=crop(x+m,y+h-m,w-m*2,m),left=crop(x,y+m,m,h-m*2),right=crop(x+w-m,y+m,m,h-m*2)}
   if center then out.center=crop(x+m,y+m,w-m*2,h-m*2)end;return out
  end
  -- Native Bitmap.getPixel returns RGB; a palette cell's alpha is not text alpha.
  local colors={};for n=0,31 do local x=96+(n%8)*12+6;local y=144+math.floor(n/8)*12+6;local p=(y*image.width+x)*4+1;local r,g,b=image.rgba:byte(p,p+2);colors[n+1]={r,g,b,255}end
  local pauses={};for n=0,3 do pauses[n+1]=crop(144+(n%2)*24,96+math.floor(n/2)*24,24,24)end
  return{kind='r2u.window-skin',schemaVersion=1,profile=ui.profile,source={path=ui.window.skinPath,sha256=S.hex(bytes),width=image.width,height=image.height,colorType=image.colorType},losslessSourcePixels=true,
   mvBack=not mz and B.compile(image,{profile=ui.profile,tone={ui.window.tone[1],ui.window.tone[2],ui.window.tone[3]}}) or nil,
   patternGeometry=mz and G.detect(image) or nil,
   back=crop(0,0,mz and 95 or 96,mz and 95 or 96),pattern=crop(0,96,96,96),frame=parts(96,0,96,96,24,false),cursor=parts(96,96,48,48,4,true),
   arrows={up=crop(132,24,24,12),down=crop(132,60,24,12)},pauses=pauses,textColors=colors}
 end
 -- Sample the source palette and a few colors; never preserve source raster regions.
 function M.compilePlatform(bytes,ui)
  if type(ui)~='table' or getmetatable(ui)~=nil or type(ui.window)~='table' or getmetatable(ui.window)~=nil then fail('UI source configuration required')end
  if ui.profile~='mv-1.5.1' and ui.profile~='mz-1.10.0' then fail('Unsupported source skin profile')end
  local image=P.decode(bytes);if image.width<192 or image.height<192 then fail('Window skin must contain the original 192 by 192 regions')end
  local function color(x,y,a)local p=(y*image.width+x)*4+1;local r,g,b=image.rgba:byte(p,p+2);return {r,g,b,a or 255}end
  local function frame(w,h,paint)
   return {kind='r2u.rectframe',schemaVersion=1,width=w,height=h,origin='top-left',palette=paint and {paint} or {},
    rects=paint and {{x=0,y=0,width=w,height=h,colorIndex=1}} or {},lossless=false,
    stats={pixels=0,visiblePixels=0,rectangles=paint and 1 or 0,colors=paint and 1 or 0,work=0}}
  end
  local function parts(m,edge,center)
   local out={margin=m,sourceWidth=m*3,sourceHeight=m*3}
   for _,key in ipairs({'tl','tr','bl','br','top','bottom','left','right'})do out[key]=frame(m,m,edge)end
   if center then out.center=frame(m,m,center)end;return out
  end
  local colors={};for n=0,31 do colors[n+1]=color(96+(n%8)*12+6,144+math.floor(n/8)*12+6)end
  local edge,cursor=color(144,12),color(120,120)
  local pauses={};for i=1,4 do pauses[i]=frame(24,24,edge)end
  return {kind='r2u.window-skin',schemaVersion=1,profile=ui.profile,renderMode='platform',losslessSourcePixels=false,
   source={path=ui.window.skinPath,sha256=S.hex(bytes),width=image.width,height=image.height,colorType=image.colorType},
   back=frame(1,1,color(48,48)),pattern=frame(96,96),frame=parts(4,edge),cursor=parts(2,cursor,{cursor[1],cursor[2],cursor[3],80}),
   arrows={up=frame(24,12,edge),down=frame(24,12,edge)},pauses=pauses,textColors=colors}
 end
 return M
end
