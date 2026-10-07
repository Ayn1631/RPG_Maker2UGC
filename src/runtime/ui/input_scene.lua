-- Event input owns only the draft; World/VM validate and commit the answer.
return function(deps)
 local tables=deps['runtime.ui.name_tables'];local M={}
 local function chars(value)local out={};for _,cp in utf8.codes(value)do out[#out+1]=utf8.char(cp)end;return out end
 function M.newName(world,ui,request)
  local S={};local pages=ui.locale and ui.locale:match('^ja') and {tables.JAPAN1,tables.JAPAN2,tables.JAPAN3}
   or ui.locale and ui.locale:match('^ru') and {tables.RUSSIA} or {tables.LATIN1,tables.LATIN2}
  local default=chars(request.name or '');while #default>request.maxLength do table.remove(default)end
  local draft=chars(table.concat(default));local index,page,revision=0,0,0
  function S.view()local rows={};local terms=ui.terms and ui.terms.messages or {}
   for i,label in ipairs(pages[page+1])do rows[i]={label=(i==89 and rawget(terms,'inputPage') or i==90 and rawget(terms,'inputOk')) or label}end
   return{kind='name',actorId=request.actorId,name=table.concat(draft),characters=chars(table.concat(draft)),maxLength=request.maxLength,rows=rows,selectedIndex=index,page=page,revision=revision}
  end
  function S.page(direction)if #pages<2 then return false end;page=(page+(direction==4 and -1 or 1)+#pages)%#pages;revision=revision+1;return true end
  function S.cancel()if #draft==0 then return false end;table.remove(draft);revision=revision+1;return true end
  function S.confirm()
   if index==88 then return S.page(6)
   elseif index==89 then
    if #draft==0 then draft=chars(table.concat(default));revision=revision+1;return #draft>0 end
    local result=world.finishSceneRequest(request.token,{name=table.concat(draft)});S.finished=result and result.ok;return S.finished
   else local char=pages[page+1][index+1];if char=='' or #draft>=request.maxLength then return false end;draft[#draft+1]=char end
   revision=revision+1;return true
  end
  function S.select(kind,value)
   local next=index
   if kind=='touch'then if type(value)~='number' or value%1~=0 or value<0 or value>=90 then return false end;if value==index then return S.confirm()end;next=value
   elseif value==2 then next=(index+10)%90 elseif value==8 then next=(index+80)%90
   elseif value==6 then next=math.floor(index/10)*10+(index+1)%10 elseif value==4 then next=math.floor(index/10)*10+(index+9)%10 end
   if next==index then return false end;index=next;revision=revision+1;return true
  end
  function S.soundState()return{mode='name',index=index,page=page,length=#draft,blank=pages[page+1][index+1]==''}end
  return S
 end
 function M.newMessage(world,ui,catalogs,itemTypes,message)
  local S={};local number=message.numberInput and message.numberInput.value or 0;local index,revision=0,0
  local function rows()
   local out={};if message.itemChoice then
    local stock={}
    if world.itemChoiceRows then for _,record in ipairs(world.itemChoiceRows(message.itemChoice.itemType))do stock[record.id]=record.count end
    else stock=world.snapshot().party.inventory.item end
    for id,count in pairs(stock)do if count>0 and itemTypes[id]==message.itemChoice.itemType then
     local source=catalogs.items[id];out[#out+1]={id=id,name=source.name,iconIndex=source.iconIndex,count=count,
      showCount=message.itemChoice.itemType==1 or message.itemChoice.itemType==2 and (ui.profile=='mv-1.5.1' or ui.optKeyItemsNumber)}
    end end;table.sort(out,function(a,b)return a.id<b.id end);index=math.max(0,math.min(index,#out-1))
   else local text=string.format('%0'..message.numberInput.digits..'d',number);for i=1,#text do out[i]={label=text:sub(i,i)}end end
   return out
  end
  function S.view()return{kind=message.numberInput and 'number' or 'eventItem',rows=rows(),selectedIndex=index,value=number,revision=revision}end
  local function respond(answer)
   local ok=world.respond(message.taskId,message.token,answer);S.finished=ok;return ok
  end
  function S.confirm()if message.numberInput then return respond({kind='number',value=number})end;local row=rows()[index+1];return respond({kind='item',id=row and row.id or 0})end
  function S.cancel()if message.numberInput then return false end;return respond({kind='cancel'})end
  function S.select(kind,value)
   local count=#rows();if count==0 then return false end;local next=index
   if kind=='touch'then if type(value)~='number' or value%1~=0 or value<0 or value>=count then return false end
    if value==index and message.itemChoice then return S.confirm()end;next=value
   elseif message.numberInput then
    if value==8 or value==2 then local place=10^(count-index-1);local digit=math.floor(number/place)%10;local nextDigit=(digit+(value==8 and 1 or 9))%10;number=number+(nextDigit-digit)*place;revision=revision+1;return true
    elseif value==6 then next=(index+1)%count elseif value==4 then next=(index-1+count)%count end
   elseif value==2 then next=(index+2)%count elseif value==8 then next=(index-2+count)%count
   elseif value==6 then next=math.min(count-1,index+1)elseif value==4 then next=math.max(0,index-1)end
   if next==index then return false end;index=next;revision=revision+1;return true
  end
  function S.soundState()return{mode=message.numberInput and 'number' or 'eventItem',index=index,value=number}end
  return S
 end
 return M
end
