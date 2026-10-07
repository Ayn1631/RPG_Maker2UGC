-- Dynamic character motion over the session's existing map and RNG services.
return function()
 local M={}
 local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
 local straight={down=2,left=4,right=6,up=8};local diagonal={lower_left={4,2},lower_right={6,2},upper_left={4,8},upper_right={6,8}}
 local right90={[2]=4,[4]=8,[8]=6,[6]=2};local left90={[2]=6,[6]=8,[8]=4,[4]=2}
 function M.refreshBush(c,map,image,priority,depth)
  image=image or {};local filename=(image.characterName or ''):match('[^/\\]+$') or ''
  local object=(image.tileId or 0)>0 or (filename:match('^[!$]+') or ''):find('!',1,true)~=nil
  local jumping=c.motion and c.motion.jumpPeak~=nil or (c.jumpHeight or 0)>0
  if priority~=1 or object or jumping or not map.isBush(c.x,c.y)then c.bushDepth=0
  elseif not c.motion and (c.realX or c.x)==c.x and (c.realY or c.y)==c.y then c.bushDepth=depth
  else c.bushDepth=c.bushDepth or 0 end
 end
 function M.nearScreen(c,player,definition,screenWidth,screenHeight,tileSize)
  local tw=tileSize or 48;local cols,rows=screenWidth/tw,screenHeight/tw
  local loopX=definition.scrollType==2 or definition.scrollType==3;local loopY=definition.scrollType==1 or definition.scrollType==3
  local displayX=(player.realX or player.x)-(cols-1)/2;local displayY=(player.realY or player.y)-(rows-1)/2
  if loopX then displayX=displayX%definition.width else displayX=math.max(0,math.min(displayX,math.max(0,definition.width-cols)))end
  if loopY then displayY=displayY%definition.height else displayY=math.max(0,math.min(displayY,math.max(0,definition.height-rows)))end
  local x,y=c.realX or c.x,c.realY or c.y
  if loopX and x<displayX-(definition.width-cols)/2 then x=x+definition.width end
  if loopY and y<displayY-(definition.height-rows)/2 then y=y+definition.height end
  local px=(x-displayX)*tw+tw/2-screenWidth/2;local py=(y-displayY)*tw+tw/2-screenHeight/2
  return px>=-screenWidth and px<=screenWidth and py>=-screenHeight and py<=screenHeight
 end
 function M.initialize(c)
  c.realX,c.realY=c.realX or c.x,c.realY or c.y;c.speed=c.speed or 4;c.frequency=c.frequency or 3
  c.pattern=c.pattern or 1;c.originalPattern=c.pattern;c.opacity=c.opacity or 255;c.blendMode=c.blendMode or 0
  c.stopCount=0;c.animationCount=0;c.walkAnime=c.walkAnime~=false;c.stepAnime=c.stepAnime==true
 end
 function M.page(c,p)
  c.through=not p or p.through==true;c.directionFix=p and p.directionFix==true or false
  c.speed=p and p.moveSpeed or 4;c.frequency=p and p.moveFrequency or 3;c.moveType=p and p.moveType or 0
  c.image=p and copy(p.image)or nil
  local pattern=p and p.image and p.image.pattern or 1
  if c.originalPattern~=pattern then c.pattern,c.originalPattern=pattern,pattern end
  c.walkAnime=not p or p.walkAnime~=false;c.stepAnime=p and p.stepAnime==true or false
  if c.forcing then c.originalRoute=p and p.moveRoute;c.originalRouteIndex=1
  else c.route=p and p.moveRoute;c.routeIndex=1 end
 end
 function M.force(c,route)
  if not c.forcing then c.originalRoute,c.originalRouteIndex=c.route,c.routeIndex end
  c.route,c.routeIndex,c.forcing,c.waitCount=route,1,true,0
 end
 function M.new(services)
  local S={}
  local function map()return services.map()end
  local function canPass(c,x,y,d)
   if services.canPass then local result=services.canPass(c,x,y,d);if result~=nil then return result end end
   return map().canPass(x,y,d,c)
  end
  local function face(c,d)if not c.directionFix then c.direction=d end end
  local function delta(c,target)
   local def=services.definition();local dx,dy=c.x-target.x,c.y-target.y
   if (def.scrollType==2 or def.scrollType==3)and math.abs(dx)>def.width/2 then dx=dx+(dx<0 and def.width or -def.width)end
   if (def.scrollType==1 or def.scrollType==3)and math.abs(dy)>def.height/2 then dy=dy+(dy<0 and def.height or -def.height)end
   return dx,dy
  end
  local function start(c,x,y,dx,dy,duration,jump)
   if not jump and services.beforeMove then services.beforeMove(c)end
   c.motion={fromX=c.x,fromY=c.y,dx=dx,dy=dy,elapsed=0,duration=duration or 256/2^c.speed,jumpPeak=jump}
   c.x,c.y=x,y;c.stopCount=0
   if services.refreshBush then services.refreshBush(c)end
  end
  function S.move(c,d,backward,dash)
   c.dashing=dash==true
   if not backward then face(c,d)end
   local x,y,valid=map().step(c.x,c.y,d)
   if valid and canPass(c,c.x,c.y,d)then
    start(c,x,y,d==6 and 1 or d==4 and -1 or 0,d==2 and 1 or d==8 and -1 or 0,256/2^(c.speed+(dash and 1 or 0)));return true
   end
   if services.touch and valid then services.touch(c,x,y)end
   return false
  end
  function S.diagonal(c,h,v)
   if c.direction==10-h then face(c,h)end;if c.direction==10-v then face(c,v)end
   local x=map().step(c.x,c.y,h);local _,y=map().step(c.x,c.y,v)
   if not (canPass(c,c.x,c.y,v)and canPass(c,c.x,y,h)or canPass(c,c.x,c.y,h)and canPass(c,x,c.y,v))then return false end
   start(c,x,y,h==6 and 1 or -1,v==2 and 1 or -1);return true
  end
  function S.toward(c,target,away)
   local dx,dy=delta(c,target);local h=dx>0 and 4 or 6;local v=dy>0 and 8 or 2
   if away then h,v=10-h,10-v end
   if math.abs(dx)>math.abs(dy)then if S.move(c,h)then return true end;if dy~=0 then return S.move(c,v)end
   elseif dy~=0 then if S.move(c,v)then return true end;if dx~=0 then return S.move(c,h)end end
   return dx==0 and dy==0
  end
  function S.chase(c,target)
   if c.motion then return end;local dx,dy=delta(c,target)
   if dx~=0 and dy~=0 then S.diagonal(c,dx>0 and 4 or 6,dy>0 and 8 or 2)
   elseif dx~=0 then S.move(c,dx>0 and 4 or 6)elseif dy~=0 then S.move(c,dy>0 and 8 or 2)end
  end
  local function turnTarget(c,away)
   local dx,dy=delta(c,services.player());local d
   if math.abs(dx)>math.abs(dy)then d=dx>0 and 4 or 6 elseif dy~=0 then d=dy>0 and 8 or 2 end
   if d then face(c,away and 10-d or d)end
  end
  local toggles={walk_on={'walkAnime',true},walk_off={'walkAnime',false},step_on={'stepAnime',true},step_off={'stepAnime',false},fix_on={'directionFix',true},fix_off={'directionFix',false},through_on={'through',true},through_off={'through',false},transparent_on={'transparent',true},transparent_off={'transparent',false}}
  function S.jump(c,xOffset,yOffset,skipFollowers)
   if math.abs(xOffset)>math.abs(yOffset)then face(c,xOffset<0 and 4 or 6)elseif yOffset~=0 then face(c,yOffset<0 and 8 or 2)end
   local x,y=map().normalize(c.x+xOffset,c.y+yOffset)
   local distance=math.floor(math.sqrt(xOffset^2+yOffset^2)+0.5);local peak=10+distance-c.speed
   start(c,x,y,xOffset,yOffset,peak*2,peak)
   if not skipFollowers and services.followers then
    for _,f in ipairs(services.followers(c)or {})do local dx,dy=delta(f,c);S.jump(f,-dx,-dy,true)end
   end
   return true
  end
  function S.command(c,ins)
   local op=ins.op
   if straight[op]then return S.move(c,straight[op])elseif diagonal[op]then return S.diagonal(c,table.unpack(diagonal[op]))
   elseif op=='random'then local d=2+2*services.random(4,'world.route.move');if canPass(c,c.x,c.y,d)then return S.move(c,d)end;return true
   elseif op=='toward'or op=='away'then return S.toward(c,services.player(),op=='away')
   elseif op=='forward'or op=='backward'then return S.move(c,op=='backward'and 10-c.direction or c.direction,op=='backward')
   elseif op=='jump'then return S.jump(c,ins.x,ins.y)
   elseif op=='wait'then c.waitCount=ins.frames-1
   elseif op:match('^turn_')and straight[op:sub(6)]then face(c,straight[op:sub(6)])
   elseif op=='turn_right90'then face(c,right90[c.direction])elseif op=='turn_left90'then face(c,left90[c.direction])
   elseif op=='turn180'then face(c,10-c.direction)
   elseif op=='turn_random90'then face(c,services.random(2,'world.route.turn90')==0 and right90[c.direction]or left90[c.direction])
   elseif op=='turn_random'then face(c,2+2*services.random(4,'world.route.turn'))
   elseif op=='turn_toward'or op=='turn_away'then turnTarget(c,op=='turn_away')
   elseif op=='switch_on'or op=='switch_off'then services.switch(ins.id,op=='switch_on')
   elseif op=='speed'then c.speed=ins.value elseif op=='frequency'then c.frequency=ins.value
   elseif toggles[op]then local t=toggles[op];c[t[1]]=t[2]
   elseif op=='image'then c.image={tileId=0,characterName=ins.name,characterIndex=ins.index,direction=c.direction,pattern=c.pattern}
   elseif op=='opacity'then c.opacity=ins.value elseif op=='blend'then c.blendMode=ins.value
   elseif op=='se'then if services.audio then services.audio({op='audio',action='play',channel='se',cue=ins.cue})end
   elseif op=='extension'then
    if not services.extension then error({severity='error',code='E_MOVE_ROUTE_SCRIPT',reason='Movement extension adapter is unavailable'},0)end
    return services.extension(ins.extension,c)~=false
   else error({severity='error',code='E_MOVE_ROUTE_IR',reason='Unknown movement operation: '..tostring(op)},0)end
   return true
  end
  local function routine(c)
   if (c.waitCount or 0)>0 then c.waitCount=c.waitCount-1;return end
   local route=c.route;local ins=route and route.list[c.routeIndex or 1];if not ins then return end
   if ins.op=='end_route'then
    if route.repeatRoute then c.routeIndex=1
    elseif c.forcing then c.forcing=false;c.route,c.routeIndex=c.originalRoute,c.originalRouteIndex;c.originalRoute,c.originalRouteIndex=nil,nil
    else c.routeIndex=#route.list+1 end
    return
   end
   local success=S.command(c,ins)
   if success or route.skippable then
    c.routeIndex=c.routeIndex+1
    if route.repeatRoute and c.routeIndex>=#route.list then c.routeIndex=1 end
   end
  end
  function S.tick(c)
   local moving=c.motion~=nil or c.realX~=c.x or c.realY~=c.y
   if c.motion then
    local m=c.motion;m.elapsed=math.min(m.duration,m.elapsed+1);local progress=m.elapsed/m.duration
    c.realX,c.realY=m.fromX+m.dx*progress,m.fromY+m.dy*progress
    c.jumpHeight=m.jumpPeak and (m.jumpPeak^2-(m.elapsed-m.jumpPeak)^2)/2 or 0
    if progress==1 then c.motion=nil;c.realX,c.realY=c.x,c.y;c.jumpHeight=0;if services.arrive then services.arrive(c)end end
   else
    if c.lockedTask then c.stopCount=0 end
    c.stopCount=(c.stopCount or 0)+1
    if c.forcing then routine(c)
    elseif c.moveType and c.moveType>0 and not c.lockedTask and (not services.nearScreen or services.nearScreen(c))and c.stopCount>30*(5-c.frequency)then
     if c.moveType==3 then routine(c)
     elseif c.moveType==2 and map().distance(c.x,c.y,services.player().x,services.player().y)>=20 then S.command(c,{op='random'})
     else
      local draw=services.random(6,'world.autonomous.type')
      if c.moveType==1 then
       if draw<=1 then S.command(c,{op='random'})elseif draw<=4 then S.move(c,c.direction)else c.stopCount=0 end
      elseif draw<=3 then S.toward(c,services.player())elseif draw==4 then S.command(c,{op='random'})else S.move(c,c.direction)end
     end
    end
   end
   if moving and c.walkAnime then c.animationCount=(c.animationCount or 0)+1.5 elseif c.stepAnime or c.pattern~=c.originalPattern then c.animationCount=(c.animationCount or 0)+1 end
   if (c.animationCount or 0)>=(9-c.speed)*3 then
    c.pattern=(not c.stepAnime and not moving)and c.originalPattern or ((c.pattern+1)%4);c.animationCount=0
   end
  end
  return S
 end
 return M
end
