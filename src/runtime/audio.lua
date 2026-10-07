-- Small mutable channel state. No project IO, source-name lookup or frame signals.
return function()
 local M={}
 local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
 local function fail(reason)error({severity='error',code='E_AUDIO_RUNTIME',reason=reason},0)end
 function M.new(catalog,emit)
  if type(catalog)~='table' or catalog.kind~='r2u.audio-catalog' or type(emit)~='function'then fail('Compiled audio catalog and emitter required')end
  local channels,volume={}, {bgm=100,bgs=100,me=100,se=100}
  local clock,serial=0,0;local saved,battleSaved,walkingSaved;local closed=false;local S={}
  local system={battleBgm=catalog.battleBgm,victoryMe=catalog.victoryMe,defeatMe=catalog.defeatMe}
  local function send(channel,operation,cue,seconds,position)
   serial=serial+1
   if catalog.enabled then emit({channel=channel,signal=catalog.signals[channel],index=cue and cue.index or 0,
    audioId=cue and cue.audioId or nil,operation=operation,volume=(cue and cue.volume or 0)*volume[channel]/100,
    pitch=cue and cue.pitch or 100,pan=cue and cue.pan or 0,seconds=seconds or 0,position=position or 0,sequence=serial})end
  end
  local function position(state)return state and state.position+(clock-state.start)*state.cue.pitch/100 or 0 end
  local function stop(channel)
   if channels[channel]then send(channel,'stop');channels[channel]=nil end
  end
  local function play(channel,cue,pos)
   if not cue or cue.name==''then stop(channel);return end
   local prior=channels[channel]
   if prior and prior.cue.index==cue.index and prior.cue.name==cue.name and channel~='se' and channel~='me' then
    if prior.cue.volume==cue.volume and prior.cue.pitch==cue.pitch and prior.cue.pan==cue.pan and not prior.fadeEnd then return end
    local at=position(prior);prior.cue=copy(cue);prior.start=clock;prior.position=at;prior.fadeEnd=nil
    send(channel,'update',cue,0,at);return
   end
   channels[channel]={cue=copy(cue),start=clock,position=pos or 0}
   send(channel,'play',cue,0,pos)
  end
  function S.command(ins)
   if closed then return {kind='continue'}end
   local channel,action=ins.channel,ins.action
   if not volume[channel]then fail('Unknown audio channel')end
   if action=='play'then play(channel,ins.cue)
   elseif action=='stop'then stop(channel)
   elseif action=='fade'then
    local state=channels[channel]
    if state then if ins.seconds<=0 then stop(channel)else state.fadeEnd=clock+ins.seconds;send(channel,'fade',state.cue,ins.seconds,position(state))end end
   elseif action=='save'then local state=channels[channel];saved=state and {cue=copy(state.cue),position=position(state)} or false
   elseif action=='save_walking'then local state=channels[channel];walkingSaved=state and {cue=copy(state.cue),position=position(state)} or false
   elseif action=='replay_walking'then
    if walkingSaved then stop(channel);play(channel,walkingSaved.cue,walkingSaved.position)elseif walkingSaved==false then stop(channel)end
   elseif action=='replay'then
    if saved then stop(channel);play(channel,saved.cue,saved.position)elseif saved==false then stop(channel)end
   elseif action=='system'then system[ins.field]=copy(ins.cue)
   else fail('Unknown audio operation')end
   return {kind='continue'}
  end
  function S.map(id)
   local cues=catalog.maps[tostring(id)];if not cues or closed then return end
   for _,channel in ipairs({'bgm','bgs'})do if cues[channel]then play(channel,cues[channel])end end
  end
  function S.beginBattle()
   if closed then return end
   battleSaved={};for _,channel in ipairs({'bgm','bgs'})do local state=channels[channel];battleSaved[channel]=state and {cue=copy(state.cue),position=position(state)} or false;stop(channel)end
   S.systemSound('battleStart')
   play('bgm',system.battleBgm)
  end
  function S.systemSound(name)
   if closed then return end
   local cue=catalog.systemSounds and catalog.systemSounds[name]
   if cue then play('se',cue)end
  end
  function S.title()
   if closed then return end
   stop('bgm');stop('bgs');stop('me');stop('se');battleSaved=nil
   play('bgm',catalog.titleBgm)
  end
  function S.endBattle(outcome)
   if closed or not battleSaved then return end
   local code=type(outcome)=='table' and outcome.code or outcome
   if code==0 then play('me',system.victoryMe)elseif code==2 then play('me',system.defeatMe)end
   stop('bgm')
   if not (type(outcome)=='table' and outcome.gameover)then
    for _,channel in ipairs({'bgm','bgs'})do local state=battleSaved[channel];if state then play(channel,state.cue,state.position)end end
   end
   battleSaved=nil
  end
  function S.setVolume(channel,value)
   if not volume[channel] or type(value)~='number' or value%1~=0 or value<0 or value>100 then fail('Volume must be 0..100')end
   if closed or volume[channel]==value then return end;volume[channel]=value
   local state=channels[channel];if state then send(channel,'volume',state.cue,0,position(state))end
  end
  function S.tick(seconds)
   if closed then return end
   if type(seconds)~='number' or seconds~=seconds or seconds<0 or seconds==math.huge then fail('Invalid audio elapsed time')end
   clock=clock+seconds
   for _,channel in ipairs({'bgm','bgs','me','se'})do local state=channels[channel];if state and state.fadeEnd and clock>=state.fadeEnd then stop(channel)end end
  end
  function S.snapshot()return {channels=copy(channels),volume=copy(volume),sequence=serial,clock=clock,status=catalog.enabled and 'signal_sent_unconfirmed' or 'unbound'}end
  function S.close()if closed then return end;for _,channel in ipairs({'bgm','bgs','me','se'})do stop(channel)end;closed=true end
  return S
 end
 return M
end
