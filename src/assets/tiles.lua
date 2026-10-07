-- Offline RPG Maker tile recipes. The source engine's numeric tables are data,
-- never JavaScript executed by the converter.
return function(deps)
 local json,D=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function fail(reason)D.raise('E_TILE_EXPORT',reason)end
 function M.tables(core)
  local result={}
  for name,rows in pairs({FLOOR=48,WALL=16,WATERFALL=4})do
   local at=core:match('Tilemap%.'..name..'_AUTOTILE_TABLE%s*=%s*()')
   local text=at and core:sub(at):match('^(%b[])%s*;')
   if not text then fail('Missing literal '..name..' autotile table in source engine')end
   local a=json.decode(text)
   if #a~=rows then fail('Unexpected '..name..' autotile table length')end
   for _,row in ipairs(a)do
    if type(row)~='table' or #row~=4 then fail('Invalid autotile row')end
    for _,pair in ipairs(row)do
     if type(pair)~='table' or #pair~=2 then fail('Invalid autotile quarter')end
     for _,n in ipairs(pair)do if type(n)~='number' or n%1~=0 or n<0 or n>5 then fail('Invalid autotile coordinate')end end
    end
   end
   result[name]=a
  end
  return result
 end
 function M.frameCount(id)
  if id<2048 or id>=2816 then return 1 end
  local kind=math.floor((id-2048)/48)
  if kind==2 or kind==3 then return 1 end
  return kind>3 and kind%2==1 and 3 or 4
 end
 function M.recipe(id,size,flag,frame,tables,edge)
  if type(id)~='number' or id%1~=0 or id<1 or id>=8192 or (id>=1024 and id<1536) then fail('Invalid tile ID')end
  if type(size)~='number' or size%4~=0 or size<8 or size>128 then fail('Tile export requires tileSize divisible by four (8..128)')end
  local out={};local function rect(set,sx,sy,dx,dy,w,h)out[#out+1]={set=set,sx=sx,sy=sy,dx=dx,dy=dy,width=w,height=h}end
  if id<2048 then
   if edge then return out end
   local set=id>=1536 and 4 or 5+math.floor(id/256)
   rect(set,(math.floor(id/128)%2*8+id%8)*size,(math.floor(id%256/8)%16)*size,0,0,size,size)
   return out
  end
  local kind,shape=math.floor((id-2048)/48),(id-2048)%48
  local tx,ty=kind%8,math.floor(kind/8);local bx,by,set=0,0,0
  local tab,isTable=tables.FLOOR,false;frame=frame or 0
  if id<2816 then
   local water=({0,1,2,1})[frame%4+1]
   if kind==0 then bx=water*2 elseif kind==1 then bx,by=water*2,3
   elseif kind==2 then bx=6 elseif kind==3 then bx,by=6,3
   else
    bx=math.floor(tx/4)*8;by=ty*6+(math.floor(tx/2)%2)*3
    if kind%2==0 then bx=bx+water*2 else bx=bx+6;by=by+frame%3;tab=tables.WATERFALL end
   end
  elseif id<4352 then set,bx,by=1,tx*2,(ty-2)*3;isTable=flag&0x80~=0
  elseif id<5888 then set,bx,by,tab=2,tx*2,(ty-6)*2,tables.WALL
  else set,bx,by=3,tx*2,math.floor((ty-10)*2.5+(ty%2==1 and .5 or 0));if ty%2==1 then tab=tables.WALL end end
  local row=tab[shape+1];if not row then fail('Invalid autotile shape for tile '..id)end
  local half=size/2
  if edge then
   if not isTable then return out end
   for i=0,1 do local q=row[i+3];rect(set,(bx*2+q[1])*half,(by*2+q[2])*half+half/2,i*half,0,half,half/2)end
   return out
  end
  for i=0,3 do
   local q=row[i+1];local sx,sy=(bx*2+q[1])*half,(by*2+q[2])*half
   local dx,dy=i%2*half,math.floor(i/2)*half
   if isTable and (q[2]==1 or q[2]==5)then
    local qx=q[2]==1 and (4-q[1])%4 or q[1]
    rect(set,(bx*2+qx)*half,(by*2+3)*half,dx,dy,half,half)
    rect(set,sx,sy,dx,dy+half/2,half,half/2)
   else rect(set,sx,sy,dx,dy,half,half)end
  end
  return out
 end
 function M.raster(recipe,size,sheet)
  local pixels={};for i=1,size*size do pixels[i]='\0\0\0\0'end
  for _,r in ipairs(recipe)do
   local image=sheet(r.set)
   if image then for y=0,r.height-1 do for x=0,r.width-1 do
    local sx,sy=r.sx+x,r.sy+y;local dx,dy=r.dx+x,r.dy+y
    if sx>=0 and sy>=0 and sx<image.width and sy<image.height and dx>=0 and dy>=0 and dx<size and dy<size then
     local p=(sy*image.width+sx)*4+1;local sr,sg,sb,sa=image.rgba:byte(p,p+3);local index=dy*size+dx+1
     if sa==255 then pixels[index]=string.char(sr,sg,sb,sa)
     elseif sa>0 then
      local dr,dg,db,da=pixels[index]:byte(1,4);local a=sa*255+da*(255-sa)
      local function blend(s,d)return math.floor((s*sa*255+d*da*(255-sa)+math.floor(a/2))/a)end
      pixels[index]=string.char(blend(sr,dr),blend(sg,dg),blend(sb,db),math.floor((a+127)/255))
     end
    end
   end end end
  end
  return{width=size,height=size,rgba=table.concat(pixels)}
 end
 return M
end
