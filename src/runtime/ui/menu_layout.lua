-- Standard source coordinates, with settled whole-row scrolling and clip bounds.
return function()
 local M={}
 local function fail(reason)error({severity='error',code='E_UI_MENU_LAYOUT',reason=reason},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('Expected plain layout data')end end
 local function number(v,lo,hi)if type(v)~='number' or v~=v or v<(lo or 0) or v>(hi or 32768)then fail('Invalid layout number')end;return v*1.0 end
 local function integer(v,lo,hi)local n=number(v,lo,hi);if n%1~=0 then fail('Expected integer layout count')end;return n end
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 local function copy(r)return rect(r.x,r.y,r.width,r.height)end
 function M.new(ui,measure)
  plain(ui);plain(ui.box);plain(ui.window);local mz=ui.profile=='mz-1.10.0'
  if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported UI profile')end
  local width,height=number(ui.box.width,1),number(ui.box.height,1)
  local pad,line,itemPad=number(ui.window.padding),number(ui.window.lineHeight,1),number(ui.window.itemPadding)
  if width<=240+pad*2+16 or height<=pad*2+52 then fail('UI area cannot contain source menu windows')end
  if type(measure)~='function'then fail('Text measurement service required')end
  local L={};local rowHeight=line+(mz and 8 or 0);local buttonHeight=mz and 52 or 0
  if ui.optDisplayTp~=nil and type(ui.optDisplayTp)~='boolean'then fail('Invalid TP display option')end
  local showTp=ui.optDisplayTp==true
  local function count(v)return integer(v,0,100000)end
  local function window(r)
   local contents=rect(r.x+pad,r.y+pad,math.max(0,r.width-pad*2),math.max(0,r.height-pad*2))
   return{rect=r,contents=contents,clipRect=copy(contents),rows={},visible=true}
  end
  local function selectable(r,n,cols,kind,first)
   local w=window(r);local c=w.contents;local member=kind=='member';local ih=member and math.floor(c.height/4) or ((kind=='param' or kind=='equip')and line or rowHeight)
   if ih<=0 then fail('Source row height is not positive')end
   local pageRows=math.floor(c.height/ih);local maxRows=math.max(1,math.ceil(n/cols));first=integer(first or 0,0,100000)
   local scrollY,originY
   if mz then
    scrollY=math.min(first*ih,math.max(0.0,maxRows*ih-c.height));first=math.floor(scrollY/ih);originY=scrollY-first*ih
   else first=math.min(first,math.max(0,maxRows-pageRows));scrollY=first*ih;originY=0 end
   w.scrollY=scrollY;w.originY=originY
   w.visibleRows=pageRows;w.firstVisibleRow=first;w.clipRect=copy(c)
   local drawRows=mz and math.ceil((c.height+ih)/ih) or pageRows
   local spacing=kind=='item' and 48 or 12;local colSpacing=kind=='item' and 16 or 8
   local iw=mz and math.floor(c.width/cols) or math.floor((c.width+spacing)/cols-spacing)
   for index=first*cols,math.min(n-1,(first+drawRows)*cols-1)do
    local col=index%cols;local row=math.floor(index/cols)-first
    local ir=mz and rect(c.x+col*iw+colSpacing/2,c.y+row*ih+2-originY,iw-colSpacing,ih-4) or rect(c.x+col*(iw+spacing),c.y+row*ih,iw,ih)
    local tr=rect(ir.x+itemPad,ir.y+(mz and (ir.height-line)/2 or 0),ir.width-itemPad*2,mz and line or ir.height)
    local entry={index=index,rect=ir,textRect=tr}
    if member then
     entry.faceRect=rect(ir.x+1,ir.y+1,144,mz and ir.height-2 or 144)
     entry.simpleStatusAnchor={x=ir.x+(mz and 180 or 162),y=ir.y+(mz and math.floor(ir.height/2-line*1.5) or ir.height/2-line*1.5)}
     if not mz then
      -- drawItemStatus x is relative to contents, then drawActorSimpleStatus
      -- reserves its own 180px class/value column and one more text padding.
      entry.simpleStatusWidth=ir.width-(ir.x-c.x+162)-itemPad
      entry.gaugeWidth=math.min(200,entry.simpleStatusWidth-180-itemPad)
      if entry.gaugeWidth==0 then entry.gaugeWidth=186 end -- drawActorHp width || 186
     end
    elseif kind=='item'then
     local measured=number(measure('000'),0,9007199254740991)
     local draw=mz and copy(tr) or rect(ir.x,ir.y,ir.width-itemPad,ir.height)
     entry.quantityRect=copy(draw);entry.nameRect=rect(draw.x,draw.y,draw.width-measured,draw.height)
    end
    w.rows[#w.rows+1]=entry
   end
   return w
  end
  function L.menu(options)
   plain(options);local actors,commands=count(options.actorCount),count(options.commandCount)
   local goldHeight=rowHeight+pad*2;local x=mz and width-240 or 0
   local commandRect=rect(x,buttonHeight,240,mz and height-buttonHeight-goldHeight or commands*line+pad*2)
   local memberRect=rect(mz and 0 or 240,buttonHeight,width-240,height-buttonHeight)
   local out={mainCommand=selectable(commandRect,commands,1,'command',options.commandFirstRow),gold=window(rect(x,height-goldHeight,240,goldHeight)),members=selectable(memberRect,actors,1,'member',options.memberFirstRow),buttonArea=rect(0,0,width,buttonHeight)}
   out.gold.textRect=rect(out.gold.contents.x+itemPad,out.gold.contents.y+(mz and 4 or 0),out.gold.contents.width-itemPad*2,line)
   return out
  end
  function L.item(options)
   plain(options);local items,categories=count(options.itemCount),integer(options.categoryCount,0,4)
   local helpHeight=line*2+pad*2;local categoryHeight=rowHeight+pad*2
   local helpRect=rect(0,mz and height-helpHeight or 0,width,helpHeight)
   local categoryRect=rect(0,mz and buttonHeight or helpHeight,width,categoryHeight)
   local y=categoryRect.y+categoryHeight;local bottom=mz and height-helpHeight or height
   local hidden=mz and categories<2;if hidden then y=categoryRect.y end
   if bottom-y<=pad*2 then fail('UI area cannot contain source item rows')end
   local out={help=window(helpRect),category=selectable(categoryRect,categories,4,'category',0),items=selectable(rect(0,y,width,bottom-y),items,2,'item',options.firstRow),buttonArea=rect(0,0,width,buttonHeight)}
   out.category.visible=not hidden;out.help.textRect=rect(out.help.contents.x+itemPad,out.help.contents.y,out.help.contents.width-itemPad*(mz and 2 or 1),line*2)
   if options.targeting then
    local index=integer(options.selectedIndex or 0,0,100000)
    -- Scene_ItemBase positions Window_MenuActor opposite the selected item column.
    out.itemActors=selectable(rect(index%2==0 and 240 or 0,buttonHeight,width-240,height-buttonHeight),count(options.actorCount),1,'member',options.actorFirstRow)
   end
   return out
  end
  function L.status(options)
   plain(options);local equipment=count(options.equipmentCount);local first=integer(options.equipmentFirstRow or 0,0,100000)
   local profileHeight=line*2+pad*2;local paramHeight=line*6+pad*2
   local out={sharedWindow=not mz,buttonArea=rect(0,0,width,buttonHeight)}
   if mz then
    if width<=300+pad*2+8 then fail('UI area cannot contain source equipment window')end
    local y=height-profileHeight-paramHeight
    if y-buttonHeight<=pad*2 then fail('UI area cannot contain source status window')end
    out.status=window(rect(0,buttonHeight,width,y-buttonHeight));out.status.drawFrame=true
    out.params=selectable(rect(0,y,300,paramHeight),6,1,'param',0);out.params.drawFrame=true
    out.equips=selectable(rect(300,y,width-300,paramHeight),equipment,1,'equip',first);out.equips.drawFrame=true
    out.profile=window(rect(0,height-profileHeight,width,profileHeight));out.profile.drawFrame=true
    local c=out.status.contents;local block2=math.floor(math.min(math.max(line*1.4,line),c.height-line*4))
    out.status.faceRect=rect(c.x+12,c.y+block2,144,144)
    out.status.levelAnchor={x=c.x+204,y=c.y+block2};out.status.iconsAnchor={x=c.x+204,y=c.y+block2+line}
    out.status.gauges={{kind='hp',x=c.x+204,y=c.y+block2+line*2},{kind='mp',x=c.x+204,y=c.y+block2+line*2+24}}
    if showTp then out.status.gauges[#out.status.gauges+1]={kind='tp',x=c.x+204,y=c.y+block2+line*2+48}end
    out.status.expRows={};for i=0,3 do out.status.expRows[#out.status.expRows+1]=rect(c.x+456,c.y+block2+line*i,270,line)end
    out.profile.textRect=rect(out.profile.contents.x+itemPad,out.profile.contents.y,out.profile.contents.width-itemPad*2,line*2)
    for _,row in ipairs(out.params.rows)do row.paramId=row.index+2;row.nameRect=rect(row.textRect.x,row.textRect.y,160,line);row.valueRect=rect(row.textRect.x+160,row.textRect.y,60,line)end
    for _,row in ipairs(out.equips.rows)do row.slotRect=rect(row.textRect.x,row.textRect.y,138,line);row.nameRect=rect(row.textRect.x+138,row.textRect.y,row.textRect.width-138,line)end
   else
    if first~=0 then fail('MV status has no equipment scrolling')end
    out.status=window(rect(0,0,width,height));out.status.drawFrame=true;local c=out.status.contents
    local function region(r)return{rect=r,contents=copy(r),clipRect=copy(c),rows={},drawFrame=false,visible=true}end
    out.params=region(rect(c.x+48,c.y+line*7,220,line*6))
    for i=0,5 do out.params.rows[#out.params.rows+1]={index=i,paramId=i+2,nameRect=rect(c.x+48,c.y+line*(7+i),160,line),valueRect=rect(c.x+208,c.y+line*(7+i),60,line)}end
    out.equips=region(rect(c.x+432,c.y+line*7,312,line*6))
    for i=0,math.min(equipment,6)-1 do out.equips.rows[#out.equips.rows+1]={index=i,nameRect=rect(c.x+432,c.y+line*(7+i),312,line)}end
    out.profile=region(rect(c.x+6,c.y+line*14,c.width-6,line*2));out.profile.textRect=copy(out.profile.rect)
    out.status.faceRect=rect(c.x+12,c.y+line*2,144,144);out.status.levelAnchor={x=c.x+204,y=c.y+line*2};out.status.iconsAnchor={x=c.x+204,y=c.y+line*3}
    out.status.gauges={{kind='hp',x=c.x+204,y=c.y+line*4,width=186},{kind='mp',x=c.x+204,y=c.y+line*5,width=186}}
    out.status.expRows={};for i=0,3 do out.status.expRows[#out.status.expRows+1]=rect(c.x+456,c.y+line*(2+i),270,line)end
    out.status.separators={};for _,n in ipairs({1,6,13})do out.status.separators[#out.status.separators+1]=rect(c.x,c.y+line*n+line/2-1,c.width,2)end
   end
   local c=out.status.contents;out.status.header={nameRect=rect(c.x+6,c.y,168,line),classRect=rect(c.x+192,c.y,168,line),nicknameRect=rect(c.x+432,c.y,270,line)}
   return out
  end
  return L
 end
 return M
end
