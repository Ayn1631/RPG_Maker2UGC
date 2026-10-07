-- MV1.5.1 uniform-base fast path. Compose into one bitmap before sprite opacity.
-- Nonuniform stretched bases require the future target-size compositor.
return function(deps)
 local R=deps['assets.rectframe'];local M={};local caps={pixels=1048576,rects=9216,work=65536}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(x)if type(x)~='table' or getmetatable(x)~=nil then fail('E_UI_BACK_SHAPE','Expected plain window-back data')end end
 local function number(x,lo,hi)if type(x)~='number' or x~=x or x<lo or x>hi then fail('E_UI_BACK_SHAPE','Invalid window-back number')end;return x*1.0 end
 local function integer(x,lo,hi)local n=number(x,lo,hi);if n%1~=0 then fail('E_UI_BACK_SHAPE','Expected integer window-back value')end;return n end
 local function clamped(x)if x<=0 then return 0 elseif x>=255 then return 255 end;local f=math.floor(x);local d=x-f;if d>.5 or d==.5 and f%2~=0 then return f+1 end;return f end
 local function premul(c,a)return math.floor(c*a/255.0+.5)end
 -- Match the observed Chromium/Skia normalized-float32 readPixels path, whose
 -- final rounding is ties-to-even. This is distinct from ideal real division.
 local function f32(n)return(string.unpack('f',string.pack('f',n)))end
 local inv255=f32(1/255.0);local straightCache={}
 local function straight(c,a)
  if a==0 then return 0 end;local key=a*256.0+c;local cached=straightCache[key];if cached~=nil then return cached end
  local reciprocal=f32(1/f32(a*inv255));local value=clamped(f32(f32(f32(c*inv255)*reciprocal)*255.0));straightCache[key]=value;return value
 end
 function M.compile(image,options,limits)
  plain(image);plain(options);if options.profile~='mv-1.5.1'then fail('E_UI_BACK_PROFILE','Only MV1.5.1 uniform-base composition is supported')end
  for k in next,options do if k~='profile' and k~='tone'then fail('E_UI_BACK_SHAPE','Unknown compositor option')end end
  plain(options.tone);local tone={};local count=0;for k in next,options.tone do integer(k,1,3);count=count+1 end;if count~=3 then fail('E_UI_BACK_SHAPE','RGB tone requires exactly three channels')end
  for i=1,3 do tone[i]=number(options.tone[i],-255,255)end
  if limits==nil then limits={}end;plain(limits);for k in next,limits do if not caps[k]then fail('E_UI_BACK_SHAPE','Unknown compositor limit')end end
  local cap={};for k,v in pairs(caps)do cap[k]=limits[k]~=nil and integer(limits[k],1,v) or v end
  local w,h=integer(image.width,96,4096),integer(image.height,192,4096);if w*h>cap.pixels then fail('E_UI_BACK_BUDGET','Source pixel budget exceeded')end
  if type(image.rgba)~='string' or #image.rgba~=w*h*4 then fail('E_UI_BACK_SHAPE','Source RGBA byte count mismatch')end
  local work=0.0;local function charge()work=work+1.0;if work>cap.work then fail('E_UI_BACK_BUDGET','Compositor operation budget exceeded')end end
  local br,bg,bb,ba=image.rgba:byte(1,4);local base={premul(br,ba),premul(bg,ba),premul(bb,ba),ba}
  for y=0,95 do for x=0,95 do charge();local p=(y*w+x)*4+1;local r,g,b,a=image.rgba:byte(p,p+3)
   if a~=ba or premul(r,a)~=base[1] or premul(g,a)~=base[2] or premul(b,a)~=base[3]then fail('E_UI_BACK_NONUNIFORM','Nonuniform MV base requires target-size composition')end
  end end
  local toned=tone[1]~=0 or tone[2]~=0 or tone[3]~=0;local pixels={}
  for y=0,95 do for x=0,95 do charge();local p=((y+96)*w+x)*4+1;local r,g,b,a=image.rgba:byte(p,p+3);local scale=(256.0-a)/256.0
   local outA=a+math.floor(ba*scale);local rgb={premul(r,a)+math.floor(base[1]*scale),premul(g,a)+math.floor(base[2]*scale),premul(b,a)+math.floor(base[3]*scale)}
   for i=1,3 do local c=straight(rgb[i],outA);if toned then c=straight(premul(clamped(c+tone[i]),outA),outA)end;rgb[i]=c end
   pixels[#pixels+1]=string.char(rgb[1],rgb[2],rgb[3],outA)
  end end
  if work>=cap.work then fail('E_UI_BACK_BUDGET','No rectangle compilation budget remains')end
  local tile=R.compile({width=96,height=96,rgba=table.concat(pixels)},{x=0,y=0,width=96,height=96},{rects=cap.rects,work=cap.work-work})
  return{kind='r2u.mv-window-back',schemaVersion=1,profile='mv-1.5.1',mode='tile',tile=tile,toneApplied=true,opacityApplied=false,sourceComposition='canvas-source-over',stats={pixels=9216,rectangles=#tile.rects,work=work+tile.stats.work}}
 end
 return M
end
