-- Skill selection holds no resource or actor state; World resolves every use.
return function()
 local M={}
 function M.new(world,ui,actorId)
  local S={};local mode='type';local typeIndex,itemIndex,targetIndex=0,0,0;local revision,contentRevision=0,0;local pending
  local function menu()return world.skillMenu(actorId)end
  local function rows()
   local m=menu();local list={};local stype=m.types[typeIndex+1]
   for _,r in ipairs(m.skills)do if r.stypeId==stype then list[#list+1]=r end end
   itemIndex=math.max(0,math.min(itemIndex,#list-1));return list
  end
  function S.view()
   local m=menu();typeIndex=math.max(0,math.min(typeIndex,#m.types-1));local list=rows();local types={}
   for _,id in ipairs(m.types)do types[#types+1]={id=id,label=ui.skillTypes and ui.skillTypes[id+1] or tostring(id)}end
   local r=mode=='actor' and pending or list[itemIndex+1]
   return{actorId=actorId,mode=mode,typeIndex=typeIndex,selectedIndex=itemIndex,targetIndex=targetIndex,types=types,rows=list,
    help=r and r.description or '',revision=revision,contentRevision=contentRevision,targeting=mode=='actor',targetInfo=pending and world.skillUseInfo(actorId,pending.id),actorView=world.getActor(actorId)}
  end
  function S.setActor(id)actorId=id;mode='type';typeIndex,itemIndex=0,0;pending=nil;revision=revision+1;contentRevision=contentRevision+1 end
  function S.canPage()return mode~='actor'end
  function S.cancel()
   if mode=='actor'then mode='item';pending=nil elseif mode=='item'then mode='type' else return false end
   revision=revision+1;return true
  end
  local function apply(r,target)
   local out=world.useSkill(actorId,r.id,target)
   if not out or not out.ok then return false end
   revision=revision+1;contentRevision=contentRevision+1
   if out.commonEvents and #out.commonEvents>0 then S.commonEvents=true;pending=nil end
   return true
  end
  function S.confirm()
   if mode=='type'then if #menu().types==0 then return false end;mode='item';itemIndex=0;revision=revision+1;return true end
   if mode=='item'then local r=rows()[itemIndex+1];if not r then return false end
    local info=world.skillUseInfo(actorId,r.id);if not info.enabled then return false end
    if not info.needsTarget then return apply(r)end
    pending=r;mode='actor';targetIndex=0
    if info.scope==11 then for i,id in ipairs(world.snapshot().party.members)do if id==actorId then targetIndex=i-1 end end end
    revision=revision+1;return true
   end
   local info=world.skillUseInfo(actorId,pending.id);if not info.enabled then return false end
   if info.all then return apply(pending)end
   local id=info.scope==11 and actorId or world.snapshot().party.members[targetIndex+1]
   for _,eligible in ipairs(info.targets)do if eligible==id then return apply(pending,id)end end;return false
  end
  function S.select(kind,value)
   local count,index,cols
   if mode=='type'then count,index,cols=#menu().types,typeIndex,1
   elseif mode=='item'then count,index,cols=#rows(),itemIndex,2
   else
    local info=world.skillUseInfo(actorId,pending.id)
    if info.all or info.scope==11 then if kind=='touch' and value>=0 and value<#world.snapshot().party.members then return S.confirm()end;return false end
    count,index,cols=#world.snapshot().party.members,targetIndex,1
   end
   if count==0 then return false end
   local nextIndex=index
   if kind=='touch'then if type(value)~='number' or value%1~=0 or value<0 or value>=count then return false end;if value==index then return S.confirm()end;nextIndex=value
   elseif value==2 then nextIndex=(index+cols)%count elseif value==8 then nextIndex=(index-cols+count)%count
   elseif cols==2 and value==6 then nextIndex=math.min(count-1,index+1)elseif cols==2 and value==4 then nextIndex=math.max(0,index-1)end
   if nextIndex==index then return false end
   if mode=='type'then typeIndex=nextIndex;itemIndex=0 elseif mode=='item'then itemIndex=nextIndex else targetIndex=nextIndex end
   revision=revision+1;return true
  end
  function S.soundState()return{mode=mode,index=mode=='type' and typeIndex or mode=='actor' and targetIndex or itemIndex,contentRevision=contentRevision,
   allTargets=mode=='actor' and pending and (pending.scope==8 or pending.scope==10 or pending.scope==11 or pending.scope==13 or pending.scope==14)}end
  return S
 end
 return M
end
