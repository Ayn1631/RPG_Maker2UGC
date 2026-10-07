-- Shared map/battle timer, advanced by active scene frames only.
return function()
 local M={}
 function M.new(profile)
  local frames,working=0,false;local T={}
  local function number(v,max)
   if type(v)~='number' or v~=v or v%1~=0 or v<0 or v>max then error({code='E_EVENT_TIMER',reason='Timer requires a nonnegative bounded integer'},0)end
   return v
  end
  function T.command(ins)
   if ins.action=='start'then frames=number(ins.seconds,math.floor(9007199254740991/60))*60;working=true
   elseif ins.action=='stop'then working=false
   else error({code='E_EVENT_TIMER',reason='Unknown timer operation'},0)end
   return{kind='continue'}
  end
  function T.tick(delta)
   number(delta,9007199254740991)
   if not working or frames==0 then return false end
   local before=frames;frames=math.max(0,frames-delta);return before>0 and frames==0
  end
  function T.test(seconds,comparison)
   number(seconds,9007199254740991);number(comparison,1)
   if not working then return false end
   local value=profile=='mv-turn' and math.floor(frames/60) or frames/60
   if comparison==0 then return value>=seconds end;return value<=seconds
  end
  function T.snapshot()return{frames=frames,seconds=math.floor(frames/60),working=working}end
  return T
 end
 return M
end
