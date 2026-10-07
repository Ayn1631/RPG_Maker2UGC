return function()
 local M={}
 function M.new(world,ui)
  local S={};local index,revision=0,0
  local names={'alwaysDash','commandRemember'}
  local settings=world.getSettings()
  -- Only advertise channels that the shared audio service can actually change.
  if settings.audioAvailable then for _,name in ipairs({'bgmVolume','bgsVolume','meVolume','seVolume'})do names[#names+1]=name end end
  function S.view()
   local values=world.getSettings();local rows={}
   for _,name in ipairs(names)do local v=values[name];rows[#rows+1]={symbol=name,label=ui.terms.messages[name] or name,value=v,status=type(v)=='boolean' and (rawget(ui.terms.messages,v and 'optionOn' or 'optionOff') or (v and 'ON' or 'OFF')) or tostring(v)..'%'}end
   return{rows=rows,selectedIndex=index,revision=revision}
  end
  function S.change(direction,wrap)
   local name=names[index+1];local value=world.getSettings()[name]
   if type(value)=='boolean'then if direction==4 then value=false elseif direction==6 then value=true else value=not value end
   else value=value+(direction==4 and -20 or 20);if wrap and value>100 then value=0 end;value=math.max(0,math.min(100,value))end
   local result=world.setSetting(name,value);if result.ok then revision=revision+1 end;return result.ok
  end
  function S.confirm()return S.change(nil,true)end
  function S.select(kind,value)
   if kind=='touch'then if type(value)~='number' or value%1~=0 or value<0 or value>=#names then return false end;if value==index then return S.confirm()end;index=value
   elseif value==4 or value==6 then return S.change(value,false)
   elseif value==2 then index=(index+1)%#names elseif value==8 then index=(index-1+#names)%#names else return false end
   revision=revision+1;return true
  end
  function S.soundState()return{index=index,value=world.getSettings()[names[index+1]]}end
  return S
 end
 return M
end
