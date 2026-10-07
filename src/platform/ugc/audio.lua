return function()
 local M={}
 -- Node contract order: index:Int, operation:String, volume:Float,
 -- pitch:Int, pan:Int, seconds:Float, position:Float. index=0 means stop.
 function M.emitter(host)
  local instances={};local remoteSe=false
  local function stopLocal()
   for _,id in ipairs(instances)do if host.game.IsAudioAlive(id)then host.game.StopAudio(id)end end
   instances={}
  end
  return function(cue)
   if cue.channel=='se' then
    if cue.operation=='stop' or cue.operation=='volume' and cue.volume==0 then stopLocal()end
    if cue.audioId then
     if not host or not host.game or type(host.game.PlayAudio2D)~='function'
      or type(host.game.IsAudioAlive)~='function' or type(host.game.StopAudio)~='function'then
      error({severity='error',code='E_PLATFORM_AUDIO',reason='Client SE requires PlayAudio2D, IsAudioAlive and StopAudio'},0)
     end
     if cue.operation=='play' and cue.volume>0 then
      local live={};for _,id in ipairs(instances)do if host.game.IsAudioAlive(id)then live[#live+1]=id end end
      local id=host.game.PlayAudio2D(math.floor(cue.audioId))
      if type(id)=='number'then live[#live+1]=id end;instances=live
     end
     return
    end
    if cue.operation=='stop' and not remoteSe then return end
    if cue.operation=='play'then remoteSe=true elseif cue.operation=='stop'then remoteSe=false end
   end
   if not host or not host.game or type(host.game.ServerSignal)~='function'then
    error({severity='error',code='E_PLATFORM_AUDIO',reason='ServerSignal is required for bound audio'},0)
   end
   local signal=host.game.ServerSignal(cue.signal)
   signal:AddInt(cue.index);signal:AddString(cue.operation);signal:AddFloat(cue.volume)
   signal:AddInt(cue.pitch);signal:AddInt(cue.pan);signal:AddFloat(cue.seconds);signal:AddFloat(cue.position)
   signal:SendSignal()
  end
 end
 return M
end
