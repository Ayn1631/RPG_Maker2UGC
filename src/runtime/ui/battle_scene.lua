-- Battle window input state. The World remains the sole combat authority.
return function()
 local M={}
 local function fail(s)error({severity='error',code='E_UI_BATTLE',reason=s},0)end
 local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
 local function same(a,b)return a and b and a.kind==b.kind and a.id==b.id and a.battleId==b.battleId and a.troopSlot==b.troopSlot end
 -- TPB clock-only updates must not renew every native button listener. Keep
 -- comparing state/slots/rows so a changed action context still expires tokens.
 local function sameInteraction(a,b,scope)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  local function ignored(k)
   return scope=='root' and (k=='revision' or k=='records')
    or scope=='clock' and (k=='chargeTime' or k=='castTime' or k=='idleTime')
  end
  for k,v in pairs(a)do if not ignored(k)then
   local child=scope=='root' and (k=='party' or k=='troop' or k=='targets') and 'battlers'
    or scope=='battlers' and 'battler' or scope=='battler' and k=='tpb' and 'clock' or 'value'
   if not sameInteraction(v,b[k],child)then return false end
  end end
  for k in pairs(b)do if not ignored(k) and a[k]==nil then return false end end
  return true
 end
 function M.new(world,ui)
  if type(world.getBattle)~='function' or type(world.submitBattle)~='function'then fail('World battle methods required')end
  local S={};local view;local mode,index='wait',0;local pending,returnMode,returnIndex,skillType;local signature;local revision=0
  local resultPages,resultPage={},0
  local tpbInputOpened=false
  local authorityChanged,pipeline,refreshNeeded=false,false,false;local messageBusy=false
  local function bump()revision=revision+1 end
  local function label(command)
   local n=({fight=1,escape=2,attack=3,guard=4,item=5,skill=6})[command]
   return n and ui.terms.commands[n] or command
  end
  local function enabled(command)
   for _,r in ipairs(view.commands or {})do if r.command==command then return r.enabled==true end end
   return false
  end
  local function resultMessages(b)
   local terms=ui.terms.messages or {};local basic=ui.terms.basic or {};local result=b.result;local rewards=result.rewards or {};local pages={}
   local function formatted(key,fallback,values)
    local value=(terms[key] or fallback):gsub('%%(%d+)',function(n)
     local v=values[tonumber(n)];if type(v)=='number' and v%1==0 then return string.format('%.0f',v)end;return tostring(v or '')
    end)
    return (value:gsub('\\G',function()return ui.currencyUnit or ''end))
   end
   local function append(lines)
    local page={}
    for _,text in ipairs(lines)do for line in (text..'\n'):gmatch('(.-)\n')do
     if #page==4 then pages[#pages+1]=page;page={}end;page[#page+1]=line
    end end
    if #page>0 then pages[#pages+1]=page end
   end
   local function actorName(id)
    if world.getActorName then return world.getActorName(id)end
    for _,actor in ipairs(b.party or {})do if actor.ref.id==id then return actor.name end end
    for _,actor in ipairs(ui.presentationDefs and ui.presentationDefs.actors or {})do if actor.id==id then return actor.name end end
    fail('Reward actor name projection missing')
   end
   local function definitionName(kind,id)
    local list=kind=='skill' and 'skills' or kind=='weapon' and 'weapons' or kind=='armor' and 'armors' or 'items'
    for _,entry in ipairs(ui.presentationDefs and ui.presentationDefs[list] or {})do if entry.id==id then return entry.name end end
    fail('Reward '..kind..' name projection missing')
   end
   local leader=b.party[1] and b.party[1].name or '';local party=#b.party>1 and formatted('partyName','%1’s Party',{leader}) or leader
   local opening={formatted(result.code==0 and 'victory' or result.code==1 and 'escapeStart' or 'defeat',result.code==0 and '%1 Victory' or result.code==1 and '%1 Escaped' or '%1 Defeat',{party})}
   if result.code==0 then
    if (rewards.exp or 0)>0 then opening[#opening+1]=formatted('obtainExp','%1 %2 received!',{rewards.exp,basic[9] or 'EXP'})end
    if (rewards.gold or 0)>0 then opening[#opening+1]=formatted('obtainGold','%1\\G found!',{rewards.gold})end
   end
   append(opening)
   if result.code==0 then
    local drops={};for _,item in ipairs(rewards.items or {})do drops[#drops+1]=formatted('obtainItem','%1 found!',{item.name or definitionName(item.kind or 'item',item.id)})end;append(drops)
    for _,entry in ipairs(rewards.actors or {})do local delta=entry.delta
     if delta and delta.levelTo>delta.levelFrom then
      local lines={formatted('levelUp','%1 is now %2 %3!',{actorName(entry.actor.state.actorId),basic[1] or 'Level',delta.levelTo})}
      for _,id in ipairs(delta.learnedSkillsAdded or {})do lines[#lines+1]=formatted('obtainSkill','%1 learned!',{definitionName('skill',id)})end;append(lines)
     end
    end
   end
   return pages
  end
  local function rows()
   if mode=='party'then return{{command='fight',name=label('fight'),enabled=view.input~=false and view.input~=nil},{command='escape',name=label('escape'),enabled=view.canEscape==true and enabled('escape')}}
   elseif mode=='actor'then
    if view.visuCommands then
     local result={};for _,source in ipairs(view.visuCommands)do local row=copy(source)
      row.name=row.label or (row.command=='party' and 'Party' or label(row.command));result[#result+1]=row
     end;return result
    end
    local o={{command='attack',name=label('attack'),enabled=enabled('attack')}}
    if ui.skillTypes then
     local types=view.skillTypes;if type(types)~='table'then fail('Source battle skill types projection required')end
     for _,id in ipairs(types)do local name=ui.skillTypes[id+1];if type(name)~='string'then fail('Missing source skill type label')end;o[#o+1]={command='skill',stypeId=id,name=name,enabled=enabled('skill')}end
    else o[#o+1]={command='skill',name=label('skill'),enabled=enabled('skill')}end
    for _,c in ipairs({'guard','item'})do o[#o+1]={command=c,name=label(c),enabled=enabled(c)}end;return o
   elseif mode=='skill'then local o={};for _,s in ipairs(view.skills or {})do if not skillType or s.stypeId==skillType then o[#o+1]=s end end;return o
   elseif mode=='item'then return view.items or {}
   elseif mode=='target'then
    local o={};local scope=pending.scope;local kind=view.input.actorRef.kind
    for _,r in ipairs(view.targets or {})do
     local friend=r.ref.kind==kind
     local valid=scope==1 and not friend and not r.dead or scope==7 and friend and not r.dead or scope==9 and friend and r.dead or scope==12 and friend
     if valid and not r.hidden then o[#o+1]=r end
    end;return o
   elseif mode=='result'then return{{name=rawget(ui.terms.messages or {},'battleContinue') or 'Continue',enabled=true}}end;return{}
  end
  local function memory()
   if not world.getSettings or not world.getSettings().commandRemember or not world.getBattleCommandMemory or not view or not view.input then return nil end
   return world.getBattleCommandMemory(view.input.actorRef.id)
  end
  local function selectRemembered()
   local saved=memory();if not saved then return end
   for i,row in ipairs(rows())do
    if mode=='actor' and row.command==saved.command and (row.command~='skill' or row.stypeId==saved.stypeId)
      or mode=='skill' and row.id==saved.skillId or mode=='item' and row.id==saved.itemId then index=i-1;return end
   end
  end
  function S.sync(nextView,provided)
   if not provided then nextView=world.getBattle()end
   if not nextView or nextView==false then view=nil;signature=nil;tpbInputOpened=false;mode,index='wait',0;return false end
   local input=nextView.input
   local actor=input and input.actorRef
   local sig=tostring(nextView.battleId)..':'..tostring(nextView.revision)
   if sig~=signature then
    local previous=view
    local clockOnly=previous and (nextView.battleSystem or 0)>0 and sameInteraction(previous,nextView,'root')
    view=copy(nextView);signature=sig;if not clockOnly then bump()end
    if previous and previous.battleId~=view.battleId then previous=nil;skillType=nil;returnMode,returnIndex=nil,nil;S.finished=nil;tpbInputOpened=false end
    if view.result and view.result~=false or view.phase=='battleEnd'then
     if not previous or not previous.result or previous.result==false or previous.battleId~=view.battleId then resultPages=resultMessages(view);resultPage=0 end
     mode,index='result',0;pending=nil
    elseif not input or input==false then mode,index='wait',0;pending=nil
    elseif not previous or not previous.input or previous.input==false or not same(previous.input.actorRef,actor) or previous.input.actionSlot~=input.actionSlot then
     local continuous=previous and previous.input and previous.input~=false
     local tpb=(view.battleSystem or 0)>0
     mode,index=(continuous or tpb and tpbInputOpened) and 'actor' or 'party',0
     if tpb then tpbInputOpened=true end
     pending=nil;skillType=nil;if mode=='actor'then selectRemembered()end
    elseif mode=='wait' or mode=='result'then mode,index=(view.battleSystem or 0)>0 and tpbInputOpened and 'actor' or 'party',0 end
   else view=copy(nextView)end
   if messageBusy then mode,index,pending='wait',0,nil end
   index=math.max(0,math.min(index,#rows()-1));return true
  end
  function S.setMessageBusy(busy)
   if type(busy)~='boolean'then fail('Message busy flag required')end
   if busy==messageBusy then return end;messageBusy=busy
   pending,returnMode,returnIndex,skillType=nil,nil,nil,nil;mode,index='wait',0
   if not busy and view then
    if view.result and view.result~=false or view.phase=='battleEnd'then mode='result'
    elseif view.input and view.input~=false then mode=(view.battleSystem or 0)>0 and tpbInputOpened and 'actor' or 'party'end
   end;bump()
  end
  local function submit(target)
   local input=view.input;local request={battleId=view.battleId,revision=view.revision,command=pending.command,id=pending.id,targetIndex=target or -1}
   if input and input~=false then request.actorRef=copy(input.actorRef);request.actionSlot=input.actionSlot end
   local result=world.submitBattle(request)
   authorityChanged=true
   if result~=true and (type(result)~='table' or not result.ok)then
    if pipeline then refreshNeeded=true else S.sync()end;return false
   end
   if input and input~=false and world.setBattleCommandMemory and pending.command~='cancel' and pending.command~='escape'then
    world.setBattleCommandMemory(input.actorRef.id,{command=pending.command,stypeId=skillType,skillId=pending.command=='skill' and pending.id or nil,itemId=pending.command=='item' and pending.id or nil})
   end
   mode,index,pending='wait',0,nil;bump()
   if type(result)=='table' and result.view~=nil then S.sync(result.view,true)
   elseif pipeline then refreshNeeded=true else S.sync()end;return true
  end
  local function choose(command,id,scope)
   local selected=rows()[index+1]
   pending={command=command,id=id,scope=scope,help=selected and selected.description or ''};returnMode,returnIndex=mode,index
   if scope==1 or scope==7 or scope==9 or scope==12 then mode,index='target',0;bump();return true end
   return submit(-1)
  end
  local function confirm()
   local r=rows()[index+1];if not r or r.enabled==false then return false end
   if mode=='party'then if r.command=='fight'then mode,index='actor',0;selectRemembered();bump();return true end;pending={command='escape'};return submit(-1)
   elseif mode=='actor'then
    if r.command=='party'then mode,index='party',0;bump();return true end
    if r.command=='skill_direct'then return choose(r.command,r.id,r.scope)end
    if r.command=='escape'then pending={command='escape'};return submit(-1)end
    if r.command=='skill' or r.command=='item'then mode,index=r.command,0;skillType=r.stypeId;selectRemembered();bump();return true end
    return choose(r.command,nil,r.command=='attack' and (view.input.attackScope or 1) or (view.input.guardScope or 11))
   elseif mode=='skill' or mode=='item'then return choose(mode,r.id,r.scope)
   elseif mode=='target'then return submit(r.index)
   elseif mode=='result'then
    if resultPage<#resultPages-1 then resultPage=resultPage+1;bump();return true end
    if type(world.finishBattle)~='function'then return false end
    local result=world.finishBattle({battleId=view.battleId,revision=view.revision});authorityChanged=true
    if result==false or type(result)=='table' and result.ok==false then if pipeline then refreshNeeded=true else S.sync()end;return false end
    S.finished=copy(result);S.sync(nil,true);bump();return true
   end;return false
  end
  local function handle(action)
   if action.kind=='confirm'then return confirm()
   elseif action.kind=='cancel'then
    if mode=='target'then mode,index=returnMode or 'actor',returnIndex or 0;pending=nil
    elseif mode=='skill' or mode=='item'then mode,index='actor',0;selectRemembered()
    elseif mode=='actor'then
     if view.input.canPrevious then pending={command='cancel'};return submit(-1)end
     mode,index='party',0
    else return false end;bump();return true
   elseif action.kind=='navigate' or action.kind=='touch'then
    local n=#rows();if n==0 then return false end;local nextIndex=index
    if action.kind=='touch'then
     if type(action.index)~='number' or action.index%1~=0 or action.index<0 or action.index>=n then return false end
     if action.index==index then return confirm()end;nextIndex=action.index
    else
     local d=action.direction;local cols=mode=='target' and pending.scope~=1 and (ui.profile=='mv-1.5.1' and 1 or 4) or (mode=='skill' or mode=='item' or mode=='target') and 2 or 1
     if d==2 then nextIndex=(index+cols)%n elseif d==8 then nextIndex=(index-cols+n)%n
     elseif d==6 and cols>1 then nextIndex=(index+1)%n elseif d==4 and cols>1 then nextIndex=(index-1+n)%n else return false end
    end
    if nextIndex==index then return false end;index=nextIndex;bump();return true
   end;return false
  end
  function S.status()return mode,revision,view~=nil end
  function S.soundState()return{mode=mode,index=index}end
  function S.isTimeActive()
   if not view or not view.battleSystem or view.battleSystem==0 then return nil end
   if messageBusy then return false end
   if view.battleSystem==1 then return mode~='skill' and mode~='item'end
   if view.battleSystem==2 then return mode~='party' and mode~='actor' and mode~='skill' and mode~='item' and mode~='target'end
   return nil
  end
  function S.project()
   if not view then return nil end
   local out=copy(view);out.mode=mode;out.selectedIndex=index;out.rows=copy(rows());out.uiRevision=revision;out.skillType=skillType;out.messageBusy=messageBusy
   local row=out.rows[index+1];out.help=(mode=='skill' or mode=='item') and row and row.description or ''
   out.targetSide=mode=='target' and pending.scope==1 and 'enemy' or 'actor';out.pending=copy(pending)
   if mode=='target' and (returnMode=='skill' or returnMode=='item') then
    local list={};for _,entry in ipairs(returnMode=='item' and view.items or view.skills or {})do if returnMode=='item' or not skillType or entry.stypeId==skillType then list[#list+1]=copy(entry)end end
    out.backgroundList={mode=returnMode,rows=list,selectedIndex=returnIndex or 0};out.help=pending.help
   end
   if mode=='result'then out.resultPage=resultPage;out.resultPageCount=#resultPages;out.resultLines=copy(resultPages[resultPage+1] or {});out.resultText=table.concat(out.resultLines,'\n')end
   return out
  end
  function S.view(snapshot,provided)
   if not S.sync(snapshot,provided)then return nil end;return S.project()
  end
  function S.dispatch(action,snapshot,provided)
   authorityChanged,refreshNeeded,pipeline=false,false,provided==true;if not S.sync(snapshot,provided)then return false,nil,false end
   if messageBusy then return false,nil,false end
   local accepted=handle(action)
   return accepted,authorityChanged and not refreshNeeded and copy(view) or nil,authorityChanged
  end
  return S
 end
 return M
end
