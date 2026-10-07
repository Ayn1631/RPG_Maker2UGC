-- Logical viewport and parallax state. Renderers only consume its projection.
return function()
 local M={}
 function M.new(map,width,height,cell,player)
  local cols,rows=width/cell,height/cell
  local loopX,loopY=map.scrollType==2 or map.scrollType==3,map.scrollType==1 or map.scrollType==3
  local x,y,px,py,lastX,lastY=0,0,0,0,0,0
  local settings=map.settings or {};local name=settings.parallaxName or ''
  local parX,parY,sx,sy=settings.parallaxLoopX==true,settings.parallaxLoopY==true,settings.parallaxSx or 0,settings.parallaxSy or 0
  local rest,speed,direction=0,0,2;local C={}
  local function bounded(value,size,screen,loop)
   if loop then return value%size end
   local edge=size-screen;if edge<0 then return edge/2 end
   return math.max(0,math.min(value,edge))
  end
  local function scroll(dx,dy)
   local ox,oy=x,y
   x,y=bounded(x+dx,map.width,cols,loopX),bounded(y+dy,map.height,rows,loopY)
   if loopX then if parX then px=px+dx end else px=px+x-ox end
   if loopY then if parY then py=py+dy end else py=py+y-oy end
   return x~=ox or y~=oy
  end
  function C.center(player)
   lastX,lastY=player.realX or player.x,player.realY or player.y
   local tx,ty=lastX-(cols-1)/2,lastY-(rows-1)/2
   x,y=bounded(tx,map.width,cols,loopX),bounded(ty,map.height,rows,loopY)
   px,py=loopX and tx or x,loopY and ty or y
  end
  function C.project(rx,ry)
   local ax,ay=rx-x,ry-y
   if loopX and rx<x-(map.width-cols)/2 then ax=ax+map.width end
   if loopY and ry<y-(map.height-rows)/2 then ay=ay+map.height end
   return ax,ay
  end
  function C.follow(player)
   local rx,ry=player.realX or player.x,player.realY or player.y
   local dx,dy=rx-lastX,ry-lastY
   if loopX and math.abs(dx)>map.width/2 then dx=dx+(dx<0 and map.width or -map.width)end
   if loopY and math.abs(dy)>map.height/2 then dy=dy+(dy<0 and map.height or -map.height)end
   local ax,ay=C.project(rx,ry)
   if (dy>0 and ay>(rows-1)/2)or(dy<0 and ay<(rows-1)/2)then scroll(0,dy)end
   if (dx>0 and ax>(cols-1)/2)or(dx<0 and ax<(cols-1)/2)then scroll(dx,0)end
   lastX,lastY=rx,ry
  end
  function C.start(ins)
   if not ({[2]=true,[4]=true,[6]=true,[8]=true})[ins.direction] or type(ins.distance)~='number' or ins.distance<0 or ins.distance%1~=0 or ins.distance>100000
    or type(ins.speed)~='number' or ins.speed%1~=0 or ins.speed<1 or ins.speed>6 then error({code='E_WORLD_CAMERA',reason='Invalid map scroll'},0)end
   rest,speed,direction=ins.distance,2^ins.speed/256,ins.direction
  end
  function C.isScrolling()return rest>0 end
  function C.tick()
   if rest>0 then
    local dx=direction==6 and speed or direction==4 and -speed or 0
    local dy=direction==2 and speed or direction==8 and -speed or 0
    if scroll(dx,dy)then rest=math.max(0,rest-speed)else rest=0 end
   end
   if parX then px=px+sx/cell/2 end
   if parY then py=py+sy/cell/2 end
  end
  function C.parallax(ins)
   if parX and not ins.loopX then px=0 end;if parY and not ins.loopY then py=0 end
   name,parX,parY,sx,sy=ins.name,ins.loopX,ins.loopY,ins.sx,ins.sy
  end
  function C.view()
   local zero=name:sub(1,1)=='!'
   return{x=x,y=y,scrolling=rest>0,parallax={name=name,x=zero and px*cell or parX and px*cell/2 or 0,y=zero and py*cell or parY and py*cell/2 or 0}}
  end
  C.center(player);return C
 end
 return M
end
