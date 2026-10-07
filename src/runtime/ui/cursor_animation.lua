-- The two native Window cursor cycles differ slightly. No host or scene state.
return function()
 local M={};local SAFE=9007199254740991
 local function fail(why)error({severity='error',code='E_UI_CURSOR',reason=why},0)end
 local function activeFlag(v)if type(v)~='boolean'then fail('Expected active flag')end end
 function M.new(profile)
  local mz=profile=='mz-1.10.0';if not mz and profile~='mv-1.5.1'then fail('Unsupported cursor profile')end
  local phase=0.0;local C={}
  function C.advance(frames,active)
   activeFlag(active)
   if type(frames)~='number' or frames~=frames or frames%1~=0 or frames<0 or frames>SAFE then fail('Expected nonnegative safe logical frames')end
   if active then phase=(phase+frames%40)%40 end
  end
  function C.alpha(active,contentsOpacity)
   activeFlag(active)
   if type(contentsOpacity)~='number' or contentsOpacity~=contentsOpacity or contentsOpacity<0 or contentsOpacity>255 then fail('Invalid contents opacity')end
   local distance=active and math.min(phase,40-phase) or 0
   -- Native methods can return negative alpha while contents fade out. The
   -- drawing adapter clamps effective paint alpha, not this source formula.
   if mz then return contentsOpacity/255-distance/32 end
   return(contentsOpacity-distance*8)/255
  end
  function C.phase()return phase end
  return C
 end
 return M
end
