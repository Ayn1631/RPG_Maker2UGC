-- Equipment focus and display projection. World retains inventory/Actor authority.
return function(deps)
 local M={}
 local function fail(why)error({severity='error',code='E_UI_EQUIP',reason=why},0)end
 local function copy(x)if type(x)~='table'then return x end;local r={};for k,v in pairs(x)do r[k]=copy(v)end;return r end
 function M.new(world,ui,catalogs,actorId)
  for _,method in ipairs({'equipState','equipCandidates','previewEquip','equipmentCommand','snapshot'})do if type(world[method])~='function'then fail('Missing equipment authority: '..method)end end
  local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported equipment UI profile')end
  -- Navigation stays local; equipment and inventory changes are committed by `world`.
  local mode,commandIndex,slotIndex,itemIndex='command',0,-1,-1
  local navigation=deps['runtime.ui.equip_layout'].navigation(ui)
  local scrollY={slots=0,items=0}
  -- Bump this when a visible selection or candidate set changes so renderers can discard stale rows.
  local revision=0.0;local E={}
  local function state()return world.equipState(actorId)end
  local function candidates()if slotIndex<0 then return {false}end;return world.equipCandidates(actorId,slotIndex+1)end
  local function boundedScroll(kind,count,y)
   local n=navigation[kind];local rows=math.max(1,math.ceil(count/n.maxCols))
   local maximum=mz and math.max(0,rows*n.itemHeight-n.innerHeight) or math.max(0,rows-n.visibleRows)*n.itemHeight
   return math.max(0,math.min(y,maximum))
  end
  local function ensure(kind,index,count)
   if index<0 then return end
   local n=navigation[kind];local top=math.floor(index/n.maxCols)*n.itemHeight;local y=scrollY[kind]
   local low=mz and top+n.itemHeight-n.innerHeight or top-(n.visibleRows-1)*n.itemHeight
   if y>top then y=top elseif y<low then y=low end
   scrollY[kind]=boundedScroll(kind,count,y)
  end
  local function changed(content)if content then revision=revision+1 end;return true end
  local function present(key,inventory)
   if not key or key==false then return {item=false,name='',description='',iconIndex=0,count=0}end
   local record=catalogs[key.kind=='weapon' and 'weapons' or 'armors'][key.id]
   if not record then fail('Equipment presentation definition missing')end
   return {item=copy(key),name=record.name,description=record.description,iconIndex=record.iconIndex,count=inventory[key.kind][key.id] or 0}
  end
  function E.setActor(id)
   actorId=id;ensure('slots',slotIndex,#state().actor.equipmentSlots)
   mode,slotIndex,itemIndex='command',-1,-1;scrollY.items=0;return changed()
  end
  function E.canPage()return mode~='item'end
  function E.canPageKey()return mode=='command'end
  function E.pageKey(direction)
   if direction~=4 and direction~=6 then fail('Invalid equipment page direction')end
   if mode=='command'then return false end
   local kind=mode=='slot' and 'slots' or 'items';local n=navigation[kind]
   local count=kind=='slots' and #state().actor.equipmentSlots or #candidates()
   local index=kind=='slots' and slotIndex or itemIndex;local top=math.floor(scrollY[kind]/n.itemHeight)
   local rows=math.max(1,math.ceil(count/n.maxCols));local down=direction==6
   if n.visibleRows==0 or count==0 or down and top+n.visibleRows>=rows or not down and top<=0 then return false end
   scrollY[kind]=boundedScroll(kind,count,scrollY[kind]+(down and 1 or -1)*n.visibleRows*n.itemHeight)
   index=math.max(0,math.min(count-1,index+(down and 1 or -1)*n.visibleRows*n.maxCols))
   if kind=='slots'then slotIndex=index;scrollY.items=0 else itemIndex=index end
   if not mz then ensure(kind,index,count)end;return changed()
  end
  function E.cancel()
   if mode=='item'then mode,itemIndex='slot',-1
   elseif mode=='slot'then mode,slotIndex='command',-1;scrollY.items=0
   else return false end;return changed()
  end
  -- Commit the selection through the authoritative world command; UI candidates never edit actor state directly.
  function E.confirm()
   if mode=='command'then
    if commandIndex==0 then mode,slotIndex='slot',0;scrollY.items=0;if not mz then ensure('slots',0,#state().actor.equipmentSlots)end;return changed()end
    local result=world.equipmentCommand({actorId=actorId,action=commandIndex==1 and 'optimize' or 'clear'})
    if result.ok then return changed(true)end;return false
   elseif mode=='slot'then
    if not state().changeableSlots[slotIndex+1]then return false end
    mode,itemIndex='item',0;ensure('items',0,#candidates());return changed()
   else
    local list=candidates();if itemIndex<0 or itemIndex>=#list then return false end
    local result=world.equipmentCommand({actorId=actorId,action='change',slot=slotIndex+1,item=list[itemIndex+1]})
    if result.ok then mode,itemIndex='slot',-1;return changed(true)end;return false
   end
  end
  function E.select(kind,value)
   local index,count,cols,horizontal
   if mode=='command'then index,count,cols,horizontal=commandIndex,3,3,true
   elseif mode=='slot'then index,count,cols=slotIndex,#state().actor.equipmentSlots,1
   else index,count,cols=itemIndex,#candidates(),mz and 1 or 2 end
   if count==0 then return false end
   local nextIndex=index
   if kind=='touch'then
    if type(value)~='number' or value%1~=0 or value<0 then fail('Invalid equipment selection')end
    if value>=count then return false end;if value==index then return E.confirm()end;nextIndex=value
   elseif kind=='navigate'then
    if value==2 then if index<count-cols or cols==1 then nextIndex=(index+cols)%count end
    elseif value==8 then if mz then index=math.max(index,0)end;if index>=cols or cols==1 then nextIndex=(index-cols+count)%count end
    elseif value==6 then if cols>=2 and (index<count-1 or horizontal)then nextIndex=(index+1)%count end
    elseif value==4 then if mz then index=math.max(index,0)end;if cols>=2 and (index>0 or horizontal)then nextIndex=(index-1+count)%count end
    else fail('Invalid equipment navigation')end
   else fail('Invalid equipment selection kind')end
   if nextIndex==index then return false end
   if mode=='command'then commandIndex=nextIndex elseif mode=='slot'then slotIndex=nextIndex;scrollY.items=0 else itemIndex=nextIndex end
   if mode~='command'then ensure(mode=='slot' and 'slots' or 'items',nextIndex,count)end
   return changed()
  end
  -- Return a UI projection containing candidate previews without mutating actor equipment.
  function E.view()
   local current=state();local inventory=world.snapshot().party.inventory;local slots,items={},{}
   for i,etype in ipairs(current.actor.equipmentSlots)do
    local row=present(current.actor.equipment[i],inventory);row.etypeId=etype;row.enabled=current.changeableSlots[i];slots[i]=row
   end
   for i,key in ipairs(candidates())do items[i]=present(key,inventory);items[i].enabled=true end
   local selected=mode=='item' and items[itemIndex+1] or mode=='slot' and slots[slotIndex+1] or nil
   local preview
   if mode=='item' and selected then preview=world.previewEquip(actorId,slotIndex+1,selected.item).actor end
   return {actorId=actorId,actorView=copy(current.actor),previewActor=copy(preview),mode=mode,commandIndex=commandIndex,slotIndex=slotIndex,itemIndex=itemIndex,
    slots=slots,items=items,slotScrollY=scrollY.slots,itemScrollY=scrollY.items,help=selected and selected.description or '',pageButtonsEnabled=E.canPage(),revision=revision}
  end
  function E.soundState()return{mode=mode,index=mode=='command' and commandIndex or mode=='slot' and slotIndex or itemIndex,revision=revision}end
  return E
 end
 return M
end
