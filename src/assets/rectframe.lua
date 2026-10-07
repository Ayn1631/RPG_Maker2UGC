-- Lossless visible-pixel rectangles; no rendering or source mutation.
return function()
 local M={};local caps={pixels=1048576,rects=100000,work=8388608}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('E_RECTFRAME_SHAPE','Expected plain data')end end
 local function integer(n,lo,hi)if type(n)~='number' or n%1~=0 or n<lo or n>hi then fail('E_RECTFRAME_BOUNDS','Invalid integer bounds')end;return n*1.0 end
 function M.compile(image,region,options)
  plain(image);plain(region);if options==nil then options={}end;plain(options);local limits={}
  for k in next,options do if not caps[k]then fail('E_RECTFRAME_LIMIT','Unknown limit')end end
  for k,v in pairs(caps)do local n=rawget(options,k);if n==nil then n=v end;limits[k]=integer(n,1,v)end
  local iw,ih=integer(image.width,1,4096),integer(image.height,1,4096);if iw*ih>limits.pixels then fail('E_RECTFRAME_BUDGET','Image pixel budget exceeded')end
  if type(image.rgba)~='string' or #image.rgba~=iw*ih*4 then fail('E_RECTFRAME_SHAPE','RGBA byte count does not match dimensions')end
  for k in next,region do if k~='x' and k~='y' and k~='width' and k~='height'then fail('E_RECTFRAME_SHAPE','Unknown crop field')end end
  local x,y=integer(region.x,0,iw-1),integer(region.y,0,ih-1);local w,h=integer(region.width,1,iw),integer(region.height,1,ih)
  if x+w>iw or y+h>ih then fail('E_RECTFRAME_BOUNDS','Crop exceeds image')end
  local palette,indices,rects,previous={},{},{},{};local work,visible=0.0,0.0
  local function pixel(X,Y)work=work+1.0;if work>limits.work then fail('E_RECTFRAME_BUDGET','Pixel work budget exceeded')end;local offset=(Y*iw+X)*4+1;return image.rgba:sub(offset,offset+3)end
  for Y=0,h-1 do
   local current={};local X=0
   while X<w do
    local color=pixel(x+X,y+Y);local last=X+1;while last<w and pixel(x+last,y+Y)==color do last=last+1 end
    if color:byte(4)~=0 then
     -- Exact numeric key also avoids Fengari 0.1.5's unpadded binary-string hash.
     local r,g,b,a=color:byte(1,4);local colorKey=r*16777216.0+g*65536.0+b*256.0+a
     visible=visible+last-X;local index=indices[colorKey];if not index then index=#palette+1;indices[colorKey]=index;palette[index]={r,g,b,a}end
     local key=X..':'..(last-X)..':'..index;local old=previous[key]
     if old then old.height=old.height+1.0;current[key]=old
     else
      if #rects>=limits.rects then fail('E_RECTFRAME_BUDGET','Rectangle budget exceeded')end
      local rect={x=X,y=Y,width=last-X,height=1,colorIndex=index};rects[#rects+1]=rect;current[key]=rect
     end
    end;X=last
   end;previous=current
  end
  return{kind='r2u.rectframe',schemaVersion=1,width=w,height=h,origin='top-left',palette=palette,rects=rects,lossless=true,stats={pixels=w*h,visiblePixels=visible,rectangles=#rects,colors=#palette,work=work}}
 end
 return M
end
