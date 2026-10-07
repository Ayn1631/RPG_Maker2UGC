return function()
 local M={}
 function M.new(world,ui,catalogs,request)
  local S={};local mode='command';local commandIndex,index,categoryIndex=0,0,0;local quantity=1;local pending,pendingMode;local revision=0;local statusPage=0
  local categories={};for i,symbol in ipairs({'item','weapon','armor','keyItem'})do
   if ui.profile=='mv-1.5.1' or ui.itemCategories[i] then categories[#categories+1]={symbol=symbol,label=ui.terms.commands[({item=5,weapon=13,armor=14,keyItem=15})[symbol]]}end
  end
  local function state()return world.shopView(request.token)end
  local function rows()
   local v=state();local out={};if not v then return out end
   local buying=mode=='buy' or mode=='number' and pendingMode=='buy'
   for _,r in ipairs(buying and v.buy or v.sell)do
    local c=categories[categoryIndex+1];local symbol=c and c.symbol
    if buying or symbol==r.kind and (r.kind~='item' or r.itypeId==1) or symbol=='keyItem' and r.kind=='item' and r.itypeId==2 then
     local source=catalogs[({item='items',weapon='weapons',armor='armors'})[r.kind]][r.id]
     r.name,r.description,r.iconIndex=source.name,source.description,source.iconIndex;out[#out+1]=r
    end
   end;index=math.max(0,math.min(index,#out-1));return out
  end
  function S.view()
   local v=state();local list=rows();local r=mode=='number' and pending or list[index+1]
   local comparison
   if r and (mode=='buy' or mode=='number') and type(world.shopComparison)=='function'then
    comparison=world.shopComparison(request.token,r.kind,r.id,statusPage)
    if comparison then
     statusPage=comparison.pageIndex
     for _,row in ipairs(comparison.rows)do
      row.name=world.getActorName and world.getActorName(row.actorId) or catalogs.actors[row.actorId].name
      if row.equipped then local source=catalogs[row.equipped.kind=='weapon' and 'weapons' or 'armors'][row.equipped.id];row.equipped.name,row.equipped.iconIndex=source.name,source.iconIndex end
     end
    end
   end
   return{mode=mode,commandIndex=commandIndex,selectedIndex=index,categoryIndex=categoryIndex,categories=categories,rows=list,
    quantity=quantity,pending=pending,pendingMode=pendingMode,maximum=pending and pending.maximum or 0,
    help=r and r.description or '',gold=v and v.gold or 0,purchaseOnly=request.purchaseOnly,revision=revision+(v and v.revision or 0),contentRevision=v and v.revision or 0,
    comparison=comparison,pageButtonsEnabled=comparison~=nil and comparison.pageCount>1,
    commands={{label=ui.terms.commands[25] or 'Buy',enabled=true},{label=ui.terms.commands[26] or 'Sell',enabled=not request.purchaseOnly},{label=ui.terms.commands[23] or 'Cancel',enabled=true}}}
  end
  function S.page(direction)
   local comparison=S.view().comparison
   if not comparison or comparison.pageCount<2 or (direction~=4 and direction~=6)then return false end
   statusPage=(statusPage+(direction==6 and 1 or -1)+comparison.pageCount)%comparison.pageCount;revision=revision+1;return true
  end
  function S.cancel()
   if mode=='command'then local result=world.finishSceneRequest(request.token);S.finished=result.ok;return result.ok
   elseif mode=='number'then mode=pendingMode;pending=nil elseif mode=='sell' and #categories>1 then mode='category' else mode='command'end
   revision=revision+1;return true
  end
  function S.confirm()
   if mode=='command'then
    if commandIndex==2 then return S.cancel()end
    if commandIndex==1 and request.purchaseOnly then return false end
    mode=commandIndex==0 and 'buy' or #categories>1 and 'category' or 'sell';index=0
   elseif mode=='category'then mode='sell';index=0
   elseif mode=='number'then
    local v=state();local r={token=request.token,revision=pending.quoteRevision or v.revision,mode=pendingMode,quantity=quantity,goodsIndex=pending.goodsIndex,kind=pending.kind,id=pending.id}
    local out=world.shopTransaction(r)
    if not out.ok then
     if out.reason=='stale'then mode=pendingMode;pending=nil;revision=revision+1 end
     return false
    end
    mode=pendingMode;pending=nil
   else
    local r=rows()[index+1];if not r or not r.enabled then return false end
    pending,pendingMode,quantity=r,mode,1;mode='number'
   end
   revision=revision+1;return true
  end
  function S.select(kind,value)
   if mode=='number'then
    if kind=='touch'then return false end
    local delta=value==6 and 1 or value==4 and -1 or value==8 and 10 or value==2 and -10 or 0
    local next=math.max(1,math.min(pending.maximum,quantity+delta));if next==quantity then return false end;quantity=next;revision=revision+1;return true
   end
   local count=mode=='command' and 3 or mode=='category' and #categories or #rows()
   local old=mode=='command' and commandIndex or mode=='category' and categoryIndex or index
   if count==0 then return false end;local next=old
   if kind=='touch'then if type(value)~='number' or value%1~=0 or value<0 or value>=count then return false end;if value==old then return S.confirm()end;next=value
   end
   if kind~='touch'then
    local cols=mode=='sell' and 2 or 1
    if value==2 then next=(old+cols)%count
    elseif value==8 then next=(old-cols+count)%count
    elseif value==6 and (mode=='command' or mode=='category')then next=(old+1)%count
    elseif value==4 and (mode=='command' or mode=='category')then next=(old-1+count)%count
    elseif mode=='sell' and value==6 then next=math.min(count-1,old+1)
    elseif mode=='sell' and value==4 then next=math.max(0,old-1)end
   end
   if next==old then return false end
   if mode=='command'then commandIndex=next elseif mode=='category'then categoryIndex=next else index=next end;revision=revision+1;return true
  end
  function S.soundState()return{mode=mode,index=mode=='command' and commandIndex or mode=='category' and categoryIndex or index,quantity=quantity,page=statusPage}end
  return S
 end
 return M
end
