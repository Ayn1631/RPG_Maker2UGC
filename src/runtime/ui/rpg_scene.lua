-- Native menu/message interaction state only. World owns all gameplay authority.
return function(deps)
 local equipmentScenes=deps['runtime.ui.equip_scene']
 local battleScenes=deps['runtime.ui.battle_scene']
 local skillScenes,shopScenes,optionScenes=deps['runtime.ui.skill_scene'],deps['runtime.ui.shop_scene'],deps['runtime.ui.options_scene']
 local inputScenes=deps['runtime.ui.input_scene']
 local messageFlows=deps['runtime.ui.message_flow']
 local M={};local serial=0.0;local SAFE=9007199254740991
 local function fail(reason)error({severity='error',code='E_UI_SCENE',reason=reason},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('Expected plain UI data')end end
 local function integer(v,lo,hi)if type(v)~='number' or v~=v or v%1~=0 or v<lo or v>hi then fail('Invalid UI integer')end;return v*1.0 end
 local function dense(v)plain(v);local n,high=0,0;for k in next,v do integer(k,1,100000);n=n+1;high=math.max(high,k)end;if n~=high then fail('Expected dense UI array')end;return n end
 local function copy(v,seen,depth)
  if type(v)~='table'then if type(v)=='function' or type(v)=='userdata' or type(v)=='thread'then fail('Executable value in UI projection')end;return v end
  plain(v);seen=seen or {};depth=depth or 0;if seen[v] or depth>64 then fail('Invalid cyclic UI data')end;seen[v]=true;local out={};for k,x in next,v do if type(k)~='number' and type(k)~='string'then fail('Invalid UI data key')end;out[k]=copy(x,seen,depth+1)end;seen[v]=nil;return out
 end
 local termIndex={item=4,skill=5,equip=6,status=7,formation=8,save=9,gameEnd=10,options=11,weapon=12,armor=13,keyItem=14}
 local flagIndex={item=1,skill=2,equip=3,status=4,formation=5,save=6}
 local categoryOrder={'item','weapon','armor','keyItem'}
 function M.new(createWorld,ui,data,onExitGame)
  if onExitGame~=nil and type(onExitGame)~='function'then fail('Exit game handler must be a function')end
  if type(createWorld)~='function'then fail('World factory required')end;plain(ui);plain(data)
  local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported UI profile')end
  local equipmentTypes=rawget(ui,'equipmentTypes')
  local marked=rawget(data,'rpgInitialization')~=nil or rawget(data,'rpgProgram')~=nil or rawget(data,'executionProjection')~=nil
  if equipmentTypes~=nil or marked then
   if dense(equipmentTypes)==0 then fail('Source equipment type zero position required')end
   for _,label in ipairs(equipmentTypes)do if type(label)~='string'then fail('Invalid source equipment type label')end end
  end
  dense(ui.menuCommandOrder);dense(ui.menuCommands);plain(ui.terms);dense(ui.terms.commands)
  local order,flags,labels={}, {},{}
  local seen={};for _,symbol in ipairs(ui.menuCommandOrder)do if not termIndex[symbol] or symbol=='weapon' or symbol=='armor' or symbol=='keyItem' or seen[symbol]then fail('Invalid menu command order')end;seen[symbol]=true;order[#order+1]=symbol end
  for symbol,index in pairs(termIndex)do local label=ui.terms.commands[index+1];if type(label)~='string'then fail('Missing source command term')end;labels[symbol]=label end
  for i=1,6 do if type(ui.menuCommands[i])~='boolean'then fail('Missing source menu flag')end;flags[i]=ui.menuCommands[i]end
  local categories={};if mz then dense(ui.itemCategories);if #ui.itemCategories~=4 or type(ui.optKeyItemsNumber)~='boolean'then fail('MZ item category/quantity configuration required')end end
  for i,symbol in ipairs(categoryOrder)do if mz and type(ui.itemCategories[i])~='boolean'then fail('Invalid source category flag')end;if not mz or ui.itemCategories[i]then categories[#categories+1]={symbol=symbol,label=labels[symbol]}end end
  local keyNumbers=not mz or ui.optKeyItemsNumber
  local presentation=ui.presentationDefs;if not presentation then fail('Native UI presentation definitions required')end;plain(presentation)
  local catalogs={};for _,name in ipairs({'actors','classes','items','weapons','armors'})do
   catalogs[name]={};dense(presentation[name]);for _,record in ipairs(presentation[name])do
    plain(record);local id=integer(record.id,1,SAFE);if catalogs[name][id] or type(record.name)~='string'then fail('Invalid presentation definition')end
    local r={id=id,name=record.name};local keys=name=='actors' and {'nickname','profile','faceName','characterName'} or name~='classes' and {'description'} or {}
    for _,key in ipairs(keys)do if record[key]~=nil and type(record[key])~='string'then fail('Invalid presentation text')end;r[key]=record[key] or ''end
    for _,key in ipairs(name=='actors' and {'faceIndex','characterIndex'} or name~='classes' and {'iconIndex'} or {})do r[key]=record[key]~=nil and integer(record[key],0,SAFE) or 0 end
    catalogs[name][id]=r
   end
  end
  plain(data.world);plain(data.world.definitions);local itemTypes={};dense(data.world.definitions.items)
  for _,r in ipairs(data.world.definitions.items)do plain(r);itemTypes[integer(r.id,1,SAFE)]=integer(r.itypeId,1,4)end
  serial=serial+1.0;if serial>SAFE then fail('UI instance token exhausted')end;local instance=serial;local epoch=1.0
  local input=deps['runtime.core.input'].new()
  local world=createWorld({startAtTitle=ui.startAtTitle==true,buttonInput=input.test});if type(world)~='table'then fail('World instance required')end
  for _,name in ipairs({'snapshot','getMessage','isBusy','move','confirm','respond','tick','mapData','close'})do if type(world[name])~='function'then fail('World method missing')end end
  local scene,focus=ui.startAtTitle==true and 'title' or 'map',ui.startAtTitle==true and 'title' or 'map';local closed=false;local menuIndex,actorIndex,categoryIndex,itemIndex=0,0,0,0
  local selected=-1;local lastTask,lastMessage,mapSignature;local S={}
  local personalCommand,equipment,targetItem,targetInfo,targetItemIndex,menuActorId;local formationPending=-1;local targetIndex=0;local itemContentRevision=0
  local battle,battleRevision;local buildView
  local skill,shop,optionsScene,extensionScene
  local extensionReturn='menu'
  local auroraRevision
  local nameInput,messageInput;local titleIndex,endIndex=0,0;local optionsReturn='menu';local exitRequested=false
  local messageFlow
  local eventMenuToken
  local mapNameWasVisible=false
  local function mapNameVisibility(visible)
   if mapNameWasVisible and not visible and world.hideMapName then world.hideMapName()end
   mapNameWasVisible=visible
  end
  local function closeEventMenu()
   if not eventMenuToken then return true end
   local result=world.finishSceneRequest(eventMenuToken);if not result.ok then return false end
   eventMenuToken=nil;return true
  end
  if scene=='title' and world.enterTitle then world.enterTitle()end
  local function bump()epoch=epoch+1.0;if epoch>SAFE then fail('UI token exhausted')end end
  local function token()return string.format('rpg:%.0f:%.0f',instance,epoch)end
  local function battleFocus()
   local mode,revision,present=battle.status()
   if not present then return false end
   if scene~='battle' or revision~=battleRevision then bump()end
   battleRevision=revision;scene,focus='battle','battle_'..mode;return true
  end
  local function sync()
   local snap=world.snapshot();local message=world.getMessage()
   if snap.errors and #snap.errors>0 then
    local d=snap.errors[#snap.errors]
    error((d.code or 'E_WORLD_EVENT')..': '..(d.reason or 'Event execution failed')..' '..(d.file or '')..' '..(d.jsonPath or ''),0)
   end
   local bv=snap.battle
   -- Older World adapters may expose getBattle without the snapshot field.
   -- Production snapshots already include it, and must not fetch it twice.
   if bv==nil and type(world.getBattle)=='function'then bv=world.getBattle();snap.battle=bv end
   if bv and bv.result and bv.result.aborted then
    local result=world.finishBattle({battleId=bv.battleId,revision=bv.revision})
    if result.ok then snap=world.snapshot();message=world.getMessage();bv=snap.battle end
   end
   local inBattle=false
   if bv and bv~=false then
    if not battle then battle=battleScenes.new(world,ui)end
    battle.sync(bv,true);battle.setMessageBusy(message~=nil);inBattle=battleFocus()
   end
   if not inBattle and scene=='battle'then scene,focus='map','map';battle,battleRevision=nil,nil;bump()end
   if message and (message.taskId~=lastTask or message.token~=lastMessage)then
    lastTask,lastMessage=message.taskId,message.token;selected=message.choices and message.defaultChoice or -1;if not inBattle then scene='map'end;bump()
    messageInput=(message.numberInput or message.itemChoice) and inputScenes.newMessage(world,ui,catalogs,itemTypes,message) or nil
    messageFlow=messageFlows.new(message,ui,{members=snap.party.members,variables=snap.story and snap.story.variables,itemCount=world.itemCount,
     actorName=function(id)return world.getActorName and world.getActorName(id) or catalogs.actors[id] and catalogs.actors[id].name or ''end})
   elseif not message and lastMessage~=nil then lastTask,lastMessage=nil,nil;selected=-1;if scene=='map'then focus='map'end;bump()end
   if not message then messageInput,messageFlow=nil,nil end
   if message then local ready=messageFlow and messageFlow.status().inputReady
    focus=ready and (messageInput and messageInput.view().kind or message.choices and 'choice' or 'message') or 'message'
   end
   if inBattle then mapNameVisibility(false);return snap,message end
   if not message and type(world.getSceneRequest)=='function'then
    local request=world.getSceneRequest()
    if request and request.kind=='shop' and scene~='shop'then shop=shopScenes.new(world,ui,catalogs,request);scene,focus='shop','shop_command';bump()end
    if request and request.kind=='menu' and not eventMenuToken then eventMenuToken=request.token;scene,focus='menu','menu';menuIndex=0;bump()end
    if request and request.kind=='name' and scene~='name'then nameInput=inputScenes.newName(world,ui,request);scene,focus='name','name';bump()end
    if request and request.kind=='title' and scene~='title'then
     world.finishSceneRequest(request.token);scene,focus='title','title';if world.enterTitle then world.enterTitle()end;bump()
    end
   end
   if snap.gameOver and scene~='title' and scene~='options' then if scene~='gameover'then scene,focus='gameover','gameover';bump()end end
   local av=world.auroraView and world.auroraView()
   if av then
    if scene~='aurora'or av.revision~=auroraRevision then bump()end
    scene,focus,auroraRevision='aurora','aurora',av.revision
   elseif scene=='aurora'then scene,focus='map','map';auroraRevision=nil;bump()end
   local p=snap.player;local sig=string.format('%.0f:%.0f:%.0f:%.0f',snap.mapId,p.x,p.y,p.direction)
   if mapSignature and mapSignature~=sig then bump()end;mapSignature=sig
   mapNameVisibility(scene=='map')
   actorIndex=math.max(0,math.min(actorIndex,#snap.party.members-1));return snap,message
  end
  local function actorEnabled(snap)return snap.actors~=nil and snap.actors~=false and type(world.getActor)=='function' end
  local function equipmentEnabled(snap)
   if not actorEnabled(snap)then return false end
   for _,name in ipairs({'equipState','equipCandidates','previewEquip','equipmentCommand'})do if type(world[name])~='function'then return false end end
   return true
  end
  local function commands(snap)
   local out={};for _,symbol in ipairs(order)do if symbol~='save' and (not flagIndex[symbol] or flags[flagIndex[symbol]])then
    local enabled=symbol=='gameEnd' or symbol=='options' and type(world.getSettings)=='function' and type(world.setSetting)=='function' or #snap.party.members>0 and (symbol=='item' or symbol=='skill' and type(world.skillMenu)=='function' and type(world.useSkill)=='function' or symbol=='status' and actorEnabled(snap) or symbol=='equip' and equipmentEnabled(snap) or symbol=='formation' and #snap.party.members>=2 and type(world.swapPartyMembers)=='function')
    if symbol=='formation' and snap.access and snap.access.formation==false then enabled=false end
    out[#out+1]={symbol=symbol,label=labels[symbol],enabled=enabled,reason=not enabled and 'unavailable' or nil}
   end end
   if world.extensionMenus then for _,entry in ipairs(world.extensionMenus())do
    out[#out+1]={symbol=entry.symbol,label=entry.label,extensionId=entry.extensionId,menuId=entry.id,enabled=true}
   end end
   return out
  end
  local function rows(snap)
   local list={};local category=categories[categoryIndex+1];if not category then return list end
   local symbol=category.symbol;local kind=(symbol=='keyItem' or symbol=='item') and 'item' or symbol;local name=kind=='item' and 'items' or kind=='weapon' and 'weapons' or 'armors'
   for id,count in pairs(snap.party.inventory[kind])do if count>0 and (kind~='item' or itemTypes[id]==(symbol=='keyItem' and 2 or 1))then
    local r=catalogs[name][id];if not r then fail('Inventory presentation definition missing')end
    local info=kind=='item' and type(world.itemUseInfo)=='function' and type(world.useItem)=='function' and world.itemUseInfo(id) or nil
    list[#list+1]={kind=kind,id=id,name=r.name,description=r.description,iconIndex=r.iconIndex,count=count,showCount=symbol~='keyItem' or keyNumbers,enabled=info~=nil and info.enabled==true,reason=info and info.reason}
   end end;table.sort(list,function(a,b)return a.id<b.id end);return list
  end
  local function choose(index,count,cols,horizontal,direction)
   if count==0 then return index end
   if direction==2 then if index<count-cols or cols==1 then return(index+cols)%count end
   elseif direction==8 then if mz then index=math.max(index,0)end;if index>=cols or cols==1 then return(index-cols+count)%count end
   elseif direction==6 and cols>=2 then if index<count-1 or horizontal then return(index+1)%count end
   elseif direction==4 and cols>=2 then if mz then index=math.max(index,0)end;if index>0 or horizontal then return(index-1+count)%count end end
   return index
  end
  local function chooseMessage(index,message,direction)
   local start=index;local count=#message.choices
   for _=1,count do
    local nextIndex=choose(index,count,message.choiceLayout and message.choiceLayout.columns or 1,false,direction)
    if nextIndex==index then return start end;index=nextIndex
    if not message.choiceEnabled or message.choiceEnabled[index+1]~=false then return index end
   end
   return start
  end
  local function back()
   if scene=='name'then local ok=nameInput.cancel();if ok then bump()end;return ok
   elseif scene=='title' or scene=='gameover'then return false
   elseif scene=='gameEnd'then scene,focus='menu','menu'
   elseif scene=='skill'then
    if skill.cancel()then focus='skill_'..skill.view().mode else scene,focus='menu','menu';skill=nil end
   elseif scene=='shop'then
    if not shop.cancel()then return false end
    if shop.finished then scene,focus='map','map';shop=nil;world.tick(0);sync()else focus='shop_'..shop.view().mode end
   elseif scene=='options'then scene,focus=optionsReturn,optionsReturn;optionsScene=nil
   elseif scene=='extension'then scene,focus=extensionReturn,extensionReturn;extensionScene=nil
   elseif scene=='equip'then
    if equipment.cancel()then focus='equip_'..equipment.view().mode else scene,focus='menu','menu';equipment=nil end
   elseif focus=='item_actor'then focus='item';targetItem,targetInfo=nil,nil
   elseif focus=='actor'then
    if personalCommand=='formation' and formationPending>=0 then formationPending=-1 else focus='menu';personalCommand=nil end
   elseif scene=='status'then scene,focus='menu','menu'
   elseif scene=='item' and focus=='item' and #categories>=2 then focus='category';itemIndex=0
   elseif scene=='item'then scene,focus='menu','menu'
   elseif scene=='menu'then
    if not closeEventMenu()then return false end
    scene,focus='map','map';world.tick(0);sync()
   else return false end;bump();return true
  end
  local function applyItem(itemId,targetActorId)
   local result=world.useItem(itemId,targetActorId)
   if not result or result.ok~=true then return false end
   itemContentRevision=itemContentRevision+1
   bump()
   if result.commonEvents and #result.commonEvents>0 then
    closeEventMenu()
    scene,focus='map','map';targetItem,targetInfo=nil,nil;world.tick(0)
   end
   sync();return true
  end
  local function contains(ids,id)for _,value in ipairs(ids or {})do if value==id then return true end end;return false end
  local function toTitle()
   exitRequested=false
   scene,focus='title','title';battle,battleRevision=nil,nil;nameInput,messageInput,messageFlow,shop,skill,equipment=nil,nil,nil,nil,nil,nil
   if world.enterTitle then world.enterTitle()end;bump();return true
  end
  local function newGame()
   exitRequested=false
   local settings=world.getSettings and world.getSettings() or nil;if settings then settings.audioAvailable=nil end
   input.clear();world.close();world=createWorld({settings=settings,startAtTitle=true,buttonInput=input.test})
   if world.leaveTitle then world.leaveTitle()end
   scene,focus='map','map';battle,battleRevision=nil,nil;eventMenuToken=nil;mapSignature,lastTask,lastMessage=nil,nil,nil;titleIndex=0;menuIndex,actorIndex=0,0;bump();sync();return true
  end
  local function requestExit()
   if exitRequested or not onExitGame then return false end
   exitRequested=true;bump();onExitGame();return true
  end
  local function confirm(snap,message)
   if scene=='title'then
    if titleIndex==0 then return newGame()elseif titleIndex==2 and world.getSettings then optionsReturn='title';optionsScene=optionScenes.new(world,ui);scene,focus='options','options';bump();return true elseif titleIndex==3 then return requestExit()end;return false
   elseif scene=='gameover'then return toTitle()
   elseif scene=='gameEnd'then if endIndex==0 then return toTitle()elseif endIndex==1 then return requestExit()end;return back()
   elseif scene=='name'then local ok=nameInput.confirm();if ok then if nameInput.finished then nameInput=nil;scene,focus='map','map';world.tick(0);sync()end;bump()end;return ok
   elseif scene=='skill'then local ok=skill.confirm();if ok then
    if skill.commonEvents then closeEventMenu();scene,focus='map','map';skill=nil;world.tick(0);sync()else focus='skill_'..skill.view().mode end;bump()end;return ok
   elseif scene=='shop'then local ok=shop.confirm();if ok then
    if shop.finished then scene,focus='map','map';shop=nil;world.tick(0);sync()else focus='shop_'..shop.view().mode end;bump()end;return ok
   elseif scene=='options'then local ok=optionsScene.confirm();if ok then bump()end;return ok
   elseif scene=='extension'then local ok=extensionScene.confirm();if ok then bump()end;return ok
   elseif scene=='equip'then local ok=equipment.confirm();if ok then focus='equip_'..equipment.view().mode;bump()end;return ok
   elseif focus=='message' or focus=='choice'then
    if focus=='choice' and selected<0 then return false end
    local answer=focus=='choice' and {kind='choice',index=selected} or {kind='confirm'}
    local ok=world.respond(message.taskId,message.token,answer);if ok then bump();world.tick(0);sync()end;return ok
   elseif scene=='map'then local ok=world.confirm();if ok then bump()end;world.tick(0);sync();return ok
   elseif focus=='menu'then
    local c=commands(snap)[menuIndex+1];if not c or not c.enabled then return false end
    if c.extensionId then extensionReturn='menu';extensionScene=deps['runtime.ui.extension_scene'].new(world,ui,c.extensionId,c.menuId);scene,focus='extension','extension'
    elseif c.symbol=='item'then scene='item';categoryIndex,itemIndex=0,0;focus=#categories>=2 and 'category' or 'item'
    elseif c.symbol=='options'then optionsReturn='menu';optionsScene=optionScenes.new(world,ui);scene,focus='options','options'
    elseif c.symbol=='gameEnd'then endIndex=0;exitRequested=false;scene,focus='gameEnd','gameEnd'
    elseif c.symbol=='status' or c.symbol=='equip' or c.symbol=='formation' or c.symbol=='skill'then
     personalCommand=c.symbol;focus='actor';formationPending=-1
     if menuActorId then for index,id in ipairs(snap.party.members)do if id==menuActorId then actorIndex=index-1;break end end end
    else return false end;bump();return true
   elseif focus=='actor'then
    if #snap.party.members==0 then return false end
    menuActorId=snap.party.members[actorIndex+1]
    if personalCommand=='formation'then
     if formationPending>=0 then
      local result=world.swapPartyMembers(actorIndex,formationPending);if not result or not result.ok then return false end
      formationPending=-1
     else formationPending=actorIndex end
     bump();return true
    end
    if not actorEnabled(snap)then return false end
    if personalCommand=='skill'then
     skill=skillScenes.new(world,ui,menuActorId);scene,focus='skill','skill_type'
    elseif personalCommand=='equip'then
     if not equipmentEnabled(snap)then return false end
     equipment=equipmentScenes.new(world,ui,catalogs,snap.party.members[actorIndex+1]);scene,focus='equip','equip_command'
    else scene,focus='status','status'end;bump();return true
   elseif focus=='category'then focus='item';itemIndex=0;bump();return true
   elseif focus=='item'then
    local item=rows(snap)[itemIndex+1];if not item or not item.enabled then return false end
    local info=world.itemUseInfo(item.id);if not info.enabled then return false end
    if info.needsTarget or info.all or info.scope==11 then
     targetItem,targetInfo,targetItemIndex=item,copy(info),itemIndex;targetIndex=math.max(0,math.min(targetIndex,#snap.party.members-1))
     if info.all then targetIndex=0 elseif info.scope==11 then
      for index,id in ipairs(snap.party.members)do if id==info.userId then targetIndex=index-1 end end
     end
     focus='item_actor';bump();return true
    end
    return applyItem(item.id)
   elseif focus=='item_actor'then
    local info=world.itemUseInfo(targetItem.id);targetInfo=copy(info);if not info.enabled then return false end
    if info.all then return applyItem(targetItem.id) end
    local id=info.scope==11 and info.userId or snap.party.members[targetIndex+1]
    if not contains(info.targets,id)then return false end
    return applyItem(targetItem.id,id)
   end
   return false
  end
  function S.tick(frames,withView,held)
   integer(frames,0,SAFE);if closed then return end
   if scene=='map' or scene=='battle'or scene=='aurora'then
    local timeActive=battle and battle.isTimeActive and battle.isTimeActive()
    if frames>0 and input.active()then
     -- Sample each logical frame so batched 30 Hz host updates cannot skip a
     -- trigger or a 24/6-frame repeat. Projection/rendering stays once per tick.
     for frame=1,frames do
      -- Native key-down is an edge, not a repeating OS event. Ask for the
      -- next step while held; world.move rejects motion/busy/collision states.
      local direction=input.direction()
      if direction and scene=='map' and focus=='map' and not world.isBusy()then
       if world.move(direction,input.test('shift',0))then bump()end
      elseif scene=='aurora'and(direction==2 or direction==8)then
       local name=direction==2 and'down'or'up'
       if input.test(name,2)and not input.test(name,1)and world.auroraInput('navigate',direction)then
        bump();if world.playSystemSound then world.playSystemSound('cursor')end
       end
      end
      world.tick(1,timeActive,frame>1);input.advance(1)
     end
    else world.tick(frames,timeActive);input.advance(frames)end
   else
    if world.advancePlaytime then world.advancePlaytime(frames)end;input.advance(frames)
   end
   local snap,message=sync()
   if messageFlow then
    local revision=messageFlow.status().revision;messageFlow.tick(frames,message.scroll and held)
    if messageFlow.status().finished then
     if world.respond(message.taskId,message.token,{kind='confirm'})then world.tick(0);snap,message=sync();bump()end
    else
     if messageFlow.status().revision~=revision then bump()end
     local ready=messageFlow.status().inputReady
     focus=ready and (messageInput and messageInput.view().kind or message.choices and 'choice' or 'message') or 'message'
    end
   end
   if withView then return buildView(snap,message)end
  end
  local function dispatch(action,snap,message)
   if scene=='aurora'then
    local ok=world.auroraInput(action.kind,action.kind=='touch'and action.index or action.direction)
    if ok then bump();world.tick(0);snap,message=sync()end
    return ok,buildView(snap,message)
   end
   for k in next,action do if k~='kind' and k~='token' and k~='direction' and k~='index' and k~='dash' and not (action.kind=='extension_menu' and (k=='extensionId' or k=='menuId'))then fail('Unknown UI action field')end end
   if messageFlow and not messageFlow.status().inputReady then
    local ok=false
    if action.kind=='confirm' or action.kind=='cancel' or action.kind=='touch'then ok=messageFlow.confirm()end
    if ok then
     if messageFlow.status().finished then
      ok=world.respond(message.taskId,message.token,{kind='confirm'})
      if ok then world.tick(0)end
     end
     snap,message=sync()
     bump()
    end
    return ok,buildView(snap,message)
   end
   if messageInput then
    local ok=false
    if action.kind=='confirm'then ok=messageInput.confirm()elseif action.kind=='cancel'then ok=messageInput.cancel()
    elseif action.kind=='navigate' or action.kind=='touch'then ok=messageInput.select(action.kind,action.kind=='touch' and action.index or action.direction)end
    if ok then if messageInput.finished then world.tick(0);sync()end;bump()end
    return ok,buildView(world.snapshot(),world.getMessage())
   end
   if scene=='battle' and message then
    local kind=action.kind;local answer
    if kind=='cancel'then
     if message.choices and message.cancelChoice==-1 then return false,buildView(snap,message)end
     answer={kind=message.choices and 'cancel' or 'confirm'}
    elseif kind=='confirm'then
     if message.choices and (selected<0 or message.choiceEnabled and message.choiceEnabled[selected+1]==false) then return false,buildView(snap,message)end
     answer=message.choices and {kind='choice',index=selected} or {kind='confirm'}
    elseif (kind=='navigate' or kind=='touch') and message.choices then
     local nextIndex
     if kind=='touch'then
      integer(action.index,0,SAFE);if action.index>=#message.choices then return false,buildView(snap,message)end
      if message.choiceEnabled and message.choiceEnabled[action.index+1]==false then return false,buildView(snap,message)end
      if action.index==selected then answer={kind='choice',index=selected}else nextIndex=action.index end
     else
      if action.direction~=2 and action.direction~=4 and action.direction~=6 and action.direction~=8 then fail('Invalid navigation direction')end
      nextIndex=chooseMessage(selected,message,action.direction)
     end
     if nextIndex~=nil then local changed=nextIndex~=selected;selected=nextIndex;if changed then bump()end;return changed,buildView(snap,message)end
    else return false,buildView(snap,message)end
    local ok=world.respond(message.taskId,message.token,answer)
    if ok then bump();world.tick(0)end
    snap,message=sync();return ok,buildView(snap,message)
   end
   if scene=='battle'then local ok,updated,changed=battle.dispatch(action,snap.battle,true)
    if ok and type(battle.finished)=='table' and battle.finished.gameOver then
     battle,battleRevision=nil,nil;scene,focus='gameover','gameover';bump()
     snap,message=sync()
    elseif changed and not updated then snap,message=sync()
    else
     if changed then snap.battle=updated end
     battleFocus()
    end
    return ok,buildView(snap,message)
   end
   local kind=action.kind
   if kind=='extension_menu' then
    if scene~='map' or message or world.isBusy() or snap.player.motion or snap.access and snap.access.menu==false then return false end
    for _,m in ipairs(world.extensionMenus and world.extensionMenus() or {})do
     if m.extensionId==action.extensionId and m.id==action.menuId then
      extensionReturn='map';extensionScene=deps['runtime.ui.extension_scene'].new(world,ui,m.extensionId,m.id)
      scene,focus='extension','extension';bump();return true,buildView(snap,message)
     end
    end
    return false
   end
   if kind=='menu' or kind=='cancel' and scene=='map' and not message then
    if snap.access and snap.access.menu==false then return false end
    if scene~='map' or world.isBusy() or snap.player.motion then return false end
    if data.aurora and world.auroraMenu()then bump();sync();return true end
    scene,focus='menu','menu';menuIndex=math.min(menuIndex,#commands(snap)-1);if world.getSettings and not world.getSettings().commandRemember then menuIndex=0 end;bump();return true
   elseif kind=='cancel'then
    if message then
     if message.choices and message.cancelChoice==-1 then return false end
     local ok=world.respond(message.taskId,message.token,{kind=message.choices and 'cancel' or 'confirm'});if ok then bump();world.tick(0);sync()end;return ok
    end;return back()
   elseif kind=='confirm'then return confirm(snap,message)
   elseif kind=='page' or kind=='pageButton'then
    if scene=='name'then local ok=nameInput.page(action.direction);if ok then bump()end;return ok end
    if scene=='shop'then
     if kind=='pageButton' and (not mz or not ui.touchUI)then return false end
     local ok=shop.page(action.direction);if ok then bump()end;return ok
    end
    if (scene~='status' and scene~='equip' and scene~='skill') or #snap.party.members==0 then return false end
    if scene=='skill' and not skill.canPage()then return false end
    if scene=='skill' and kind=='page' and skill.view().mode~='type'then return false end
    if kind=='pageButton' and (not mz or not ui.touchUI)then return false end
    if scene=='equip' and kind=='page' and not equipment.canPageKey()then local ok=equipment.pageKey(action.direction);if ok then bump()end;return ok end
    if scene=='equip' and not (kind=='pageButton' and equipment.canPage() or kind=='page' and equipment.canPageKey())then return false end
    if action.direction~=4 and action.direction~=6 then fail('Status page direction must be 4 or 6')end
    actorIndex=(actorIndex+(action.direction==6 and 1 or -1)+#snap.party.members)%#snap.party.members;menuActorId=snap.party.members[actorIndex+1]
    if scene=='equip'then equipment.setActor(snap.party.members[actorIndex+1]);focus='equip_command'
    elseif scene=='skill'then skill.setActor(menuActorId);focus='skill_type'end;bump();return true
   elseif kind=='navigate' or kind=='touch'then
    if kind=='navigate' then if action.direction~=2 and action.direction~=4 and action.direction~=6 and action.direction~=8 then fail('Invalid navigation direction')end;if action.dash~=nil and type(action.dash)~='boolean'then fail('Invalid dash flag')end end
    if scene=='name'then local ok=nameInput.select(kind,kind=='touch' and action.index or action.direction);if ok then if nameInput.finished then nameInput=nil;scene,focus='map','map';world.tick(0);sync()end;bump()end;return ok end
    if scene=='title' or scene=='gameEnd'then
     local count=scene=='title' and 4 or 3;local index=scene=='title' and titleIndex or endIndex
     if kind=='touch'then
      integer(action.index,0,count-1)
      if action.index==(scene=='title' and 3 or 1)then
       if scene=='title'then titleIndex=action.index else endIndex=action.index end
       return requestExit()
      end
      if action.index==index then return confirm(snap,message)end;index=action.index
     else index=choose(index,count,1,false,action.direction)end
     if scene=='title'then titleIndex=index else endIndex=index end;bump();return true
    elseif scene=='gameover'then if kind=='touch'then return toTitle()end;return false end
    if scene=='skill' or scene=='shop' or scene=='options' or scene=='extension'then
     local controller=scene=='skill' and skill or scene=='shop' and shop or scene=='extension' and extensionScene or optionsScene
     local ok=controller.select(kind,kind=='touch' and action.index or action.direction)
     if ok then
      if scene=='skill' and skill.commonEvents then closeEventMenu();scene,focus='map','map';skill=nil;world.tick(0);sync()
      elseif scene=='shop' and shop.finished then scene,focus='map','map';shop=nil;world.tick(0);sync()
      else focus=(scene=='options' or scene=='extension') and scene or scene..'_'..controller.view().mode end;bump()
     end;return ok
    end
    if scene=='equip'then local ok=equipment.select(kind,kind=='touch' and action.index or action.direction);if ok then focus='equip_'..equipment.view().mode;bump()end;return ok end
    if focus=='map'then if kind~='navigate'then return false end;local dash=action.dash;if dash==nil then dash=input.test('shift',0)end;local ok=world.move(action.direction,dash);if ok then bump();sync()end;return ok end
    local index,count,cols,horizontal
    if focus=='choice'then index,count,cols=selected,#message.choices,message.choiceLayout and message.choiceLayout.columns or 1
    elseif focus=='menu'then index,count,cols=menuIndex,#commands(snap),1
    elseif focus=='actor'then index,count,cols=actorIndex,#snap.party.members,1
    elseif focus=='item_actor'then
     if targetInfo.all or targetInfo.scope==11 then
      if kind~='touch'then return false end;integer(action.index,0,SAFE);if action.index>=#snap.party.members then return false end
      return confirm(snap,message)
     end
     index,count,cols=targetIndex,#snap.party.members,1
    elseif focus=='category'then index,count,cols,horizontal=categoryIndex,#categories,4,true
    elseif focus=='item'then index,count,cols=itemIndex,#rows(snap),2
    else return false end
    if kind=='touch'then integer(action.index,0,SAFE);if action.index>=count then return false end;if focus=='choice' and message.choiceEnabled and message.choiceEnabled[action.index+1]==false then return false end;if action.index==index then return confirm(snap,message)end;index=action.index
    else index=focus=='choice' and chooseMessage(index,message,action.direction) or choose(index,count,cols,horizontal,action.direction)end
    local changed
    if focus=='choice'then changed=index~=selected;selected=index
    elseif focus=='menu'then changed=index~=menuIndex;menuIndex=index
    elseif focus=='actor'then changed=index~=actorIndex;actorIndex=index
    elseif focus=='item_actor'then changed=index~=targetIndex;targetIndex=index
    elseif focus=='category'then changed=index~=categoryIndex;categoryIndex=index;itemIndex=0
    else changed=index~=itemIndex;itemIndex=index end
    if changed then bump()end;return changed
   else fail('Unsupported UI action')end
  end
  local function soundContext()
   local controller=messageInput or scene=='battle' and focus~='choice' and focus~='message' and battle or scene=='name' and nameInput
    or scene=='equip' and equipment or scene=='skill' and skill or scene=='shop' and shop
    or scene=='options' and optionsScene or scene=='extension' and extensionScene
   local state=controller and controller.soundState() or {}
   if not controller then
    state.index=focus=='choice' and selected or focus=='menu' and menuIndex or focus=='actor' and actorIndex
     or focus=='item_actor' and targetIndex or focus=='category' and categoryIndex or focus=='item' and itemIndex
     or scene=='title' and titleIndex or scene=='gameEnd' and endIndex or nil
    state.allTargets=focus=='item_actor' and targetInfo and (targetInfo.all or targetInfo.scope==11)
   end
   return{scene=scene,focus=focus,controller=controller,state=state,itemRevision=itemContentRevision,
    quiet=messageFlow and not messageFlow.status().inputReady or focus=='message' or scene=='gameover'
     or scene=='battle' and not messageInput and focus~='choice' and (state.mode=='wait' or state.mode=='result')}
  end
  local function playFeedback(before,action,ok)
   if before.quiet then return end
   local kind=action.kind;local prior=before.state
   local current=before.controller and before.controller.soundState() or soundContext().state
   local function sound(name)world.playSystemSound(name)end
   if ok and action.kind=='touch' and (before.scene=='title' and action.index==3 or before.scene=='gameEnd' and action.index==1)then sound('ok');return end
   if before.scene=='map' and before.focus=='map'then
    if ok and (kind=='menu' or kind=='cancel' or kind=='extension_menu')then sound('ok')end;return
   end
   if kind=='cancel'then if ok then sound('cancel')end;return end
   if kind=='page' or kind=='pageButton'then if ok then sound('cursor')end;return end
   local changed=prior.index~=current.index or prior.page~=current.page or prior.quantity~=current.quantity or prior.value~=current.value
   local confirming=kind=='confirm' or kind=='touch' and prior.mode~='number' and (action.index==prior.index or prior.allTargets)
   if before.scene=='options'then if ok and changed then sound('cursor')end;return end
   if not confirming then if ok and changed then sound('cursor')end;return end
   if before.scene=='name' and prior.blank then return end
   if not ok or before.scene=='extension' and current.rejected then sound('buzzer');return end
   if itemContentRevision~=before.itemRevision then
    if before.focus~='item_actor'then sound('ok')end;sound('useItem')
   elseif before.scene=='skill' and current.contentRevision~=prior.contentRevision then
    if prior.mode~='actor'then sound('ok')end;sound('useSkill')
   elseif before.scene=='equip' and current.revision~=prior.revision then
    if prior.mode=='command'then sound('ok')end;sound('equip')
   elseif before.scene=='shop' and prior.mode=='number'then sound('shop')
   else sound('ok')end
  end
  function S.dispatch(action)
   if closed then return false end;plain(action);local snap,message=sync()
   if action.token~=token() or snap.presentation and snap.presentation.video then return false,buildView(snap,message)end
   -- Capture only interaction scalars, never another complete UI projection.
   local before=world.playSystemSound and soundContext()
   local ok,view=dispatch(action,snap,message)
   if before and before.scene=='aurora'then if ok then world.playSystemSound(action.kind=='navigate'and'cursor'or action.kind=='cancel'and'cancel'or'ok')end
   elseif before then playFeedback(before,action,ok)end
   return ok,view
  end
  local function actorPresentation(id)
   local source=catalogs.actors[id];if not source then fail('Actor presentation definition missing')end
   if world.actorPresentation then return world.actorPresentation(id,source)end
   local out=copy(source);if world.getActorName then out.name=world.getActorName(id)end;return out
  end
  buildView=function(snap,message)
   local menu=commands(snap);if message then message=copy(message);message.selectedChoice=selected end
   local out={scene=scene,focus=focus,token=token(),closed=closed,world=snap,message=message,menu={commands=menu,selectedIndex=menuIndex,formation=focus=='actor'and personalCommand=='formation',pendingIndex=formationPending},members={}}
   if messageFlow and message then out.messageFlow=messageFlow.view()end
   if scene=='battle'then out.battle=battle.project()end
   for _,id in ipairs(snap.party.members)do local member={actorId=id,sourceActor=actorPresentation(id)}
    if scene~='map' and scene~='battle' and scene~='title' and scene~='gameover' and scene~='extension' and actorEnabled(snap)then member.actorView=copy(world.getActor(id))end;out.members[#out.members+1]=member
   end
   if scene=='item'then
    local entries=rows(snap);itemIndex=math.max(0,math.min(itemIndex,#entries-1))
    local targeting=focus=='item_actor';if targeting then targetInfo=copy(world.itemUseInfo(targetItem.id))end
    out.items={categories=copy(categories),categoryIndex=categoryIndex,rows=entries,selectedIndex=itemIndex,revision=itemContentRevision,
     help=targeting and targetItem.description or focus=='item' and entries[itemIndex+1] and entries[itemIndex+1].description or '',
     readOnly=type(world.itemUseInfo)~='function' or type(world.useItem)~='function',targeting=targeting,
     targetIndex=targetIndex,targetAll=targeting and targetInfo.all==true or false,
     targetItemId=targeting and targetItem.id or nil,targetItemIndex=targeting and targetItemIndex or nil,targetInfo=targeting and copy(targetInfo) or nil}
   end
   if scene=='status' and out.members[actorIndex+1]then
    local m=out.members[actorIndex+1];if type(world.actorProgression)~='function'then fail('World actorProgression method missing for Status')end
    out.status={actorId=m.actorId,sourceActor=copy(m.sourceActor),actorView=copy(m.actorView),sourceClass=copy(catalogs.classes[m.actorView.state.classId]),progression=copy(world.actorProgression(m.actorId))}
   end
   if scene=='equip'then out.equip=equipment.view();out.equip.sourceActor=actorPresentation(out.equip.actorId)end
   if scene=='skill'then out.skill=skill.view();out.skill.sourceActor=actorPresentation(out.skill.actorId)end
   if scene=='shop'then out.shop=shop.view()end
   if scene=='options'then out.options=optionsScene.view()end
   if scene=='extension'then out.extension=extensionScene.view()end
   if scene=='aurora'then out.aurora=world.auroraView()end
   if scene=='title'then out.system={selectedIndex=titleIndex,rows={{label=ui.terms.commands[19] or 'New Game',enabled=true},{label=ui.terms.commands[20] or 'Continue',enabled=false},{label=labels.options,enabled=type(world.getSettings)=='function'},{label='退出游戏',enabled=onExitGame~=nil and not exitRequested}},gameTitle=ui.gameTitle or ''}end
   if scene=='gameEnd'then out.system={selectedIndex=endIndex,rows={{label=ui.terms.commands[22] or 'To Title',enabled=true},{label='退出游戏',enabled=onExitGame~=nil and not exitRequested},{label=ui.terms.commands[23] or 'Cancel',enabled=true}}}end
   if scene=='title'and data.aurora then out.system.rows[1].label='新的旅程';out.system.rows[2].label='继续冒险';out.system.rows[3].label='游戏设置'end
   if scene=='gameover'then out.system={rows={},selectedIndex=0}end
   if scene=='name'then out.input=nameInput.view();out.input.sourceActor=actorPresentation(out.input.actorId)end
   if messageInput then out.input=messageInput.view()end
   local help=out.items and out.items.help or out.equip and out.equip.help or out.skill and out.skill.help or out.shop and out.shop.help or out.battle and out.battle.help
   local tokens=help and data.resources and data.resources.richHelp and data.resources.richHelp[help]
   if tokens then out.helpTokens=messageFlows.project(tokens,ui,{members=snap.party.members,variables=snap.story and snap.story.variables,itemCount=world.itemCount,
    actorName=function(id)return world.getActorName and world.getActorName(id) or catalogs.actors[id] and catalogs.actors[id].name or ''end})end
   out.memberIndex=actorIndex;return out
  end
  function S.view()local snap,message=sync();return buildView(snap,message)end
  function S.mapData()if world.mapDefinition then return world.mapDefinition()end;return copy(world.mapData())end
  function S.extensionShortcuts()return world.extensionMenus and world.extensionMenus() or {}end
  function S.setButton(source,name,pressed)if not closed then input.set(source,name,pressed)end end
  function S.close()if closed then return end;closed=true;input.clear();bump();world.close()end
  return S
 end
 return M
end
