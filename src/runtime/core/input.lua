-- Logical RPG Maker buttons. Physical aliases share a held count; no UI writes.
return function()
 local M={}
 local names={ok=true,cancel=true,menu=true,escape=true,shift=true,control=true,tab=true,pageup=true,pagedown=true,up=true,down=true,left=true,right=true}
 local function fail()error({code='E_INPUT_STATE',reason='Invalid logical button input'},0)end
 function M.new()
  local I={};local sources,counts={},{};local latest,age=nil,0
  local directions={};local directionIds={up=8,down=2,left=4,right=6}
  function I.set(source,name,pressed)
   if type(source)~='string' or not names[name] or type(pressed)~='boolean' then fail()end
   local old=sources[source]
   if old and old~=name then fail()end
   if pressed and not old then
    sources[source]=name;counts[name]=(counts[name] or 0)+1
    if counts[name]==1 then latest,age=name,0;if directionIds[name]then directions[#directions+1]=name end end
   elseif not pressed and old then
    sources[source]=nil;counts[name]=counts[name]-1
    if counts[name]==0 then
     counts[name]=nil;if latest==name then latest=nil end
     if directionIds[name]then for i=#directions,1,-1 do if directions[i]==name then table.remove(directions,i);break end end end
    end
   end
  end
  function I.test(name,mode)
   if not names[name] or (mode~=0 and mode~=1 and mode~=2) then fail()end
   if (name=='cancel' or name=='menu') and I.test('escape',mode) then return true end
   if mode==0 then return counts[name]~=nil end
   return latest==name and (age==0 or mode==2 and age>=24 and age%6==0)
  end
  function I.advance(frames)
   if type(frames)~='number' or frames%1~=0 or frames<0 or frames>9007199254740991 then fail()end
   -- Keep the repeat phase without an ever-growing counter.
   if latest then age=age+frames;if age>30 then age=24+(age-24)%6 end end
  end
  function I.direction()return directionIds[directions[#directions]]end
  function I.active()return latest~=nil or #directions>0 end
  function I.clear()sources,counts,directions={},{},{};latest,age=nil,0 end
  return I
 end
 return M
end
