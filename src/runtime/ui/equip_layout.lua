-- Native MV 1.5.1 / MZ 1.10.0 equipment geometry, in source box pixels.
return function()
 local M={}
 local function fail(s)error({severity='error',code='E_UI_EQUIP_LAYOUT',reason=s},0)end
 local function plain(v)if type(v)~='table' or getmetatable(v)~=nil then fail('Expected plain equipment layout data')end end
 local function number(v,lo,hi)if type(v)~='number' or v~=v or v<(lo or 0) or v>(hi or 32768)then fail('Invalid equipment layout number')end;return v*1.0 end
 local function integer(v)local n=number(v,0,100000);if n%1~=0 then fail('Expected integer count or row')end;return n end
 local function default(v,d)if v==nil then return d end;return v end
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 local function copy(r)return rect(r.x,r.y,r.width,r.height)end
 function M.new(ui,measure)
  plain(ui);plain(ui.box);plain(ui.window)
  local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported equipment UI profile')end
  local width,height=number(ui.box.width,1),number(ui.box.height,1)
  local pad,line,ip=number(ui.window.padding),number(ui.window.lineHeight,1),number(ui.window.itemPadding)
  if ui.touchUI~=nil and type(ui.touchUI)~='boolean'then fail('Invalid touch UI option')end
  local touch=ui.touchUI==true
  if type(measure)~='function'then fail('Text measurement service required')end
  local ih=line+(mz and 8 or 0);local helpHeight=2*line+2*pad;local commandHeight=ih+2*pad
  local top=mz and 52 or helpHeight;local statusHeight=mz and height-52-helpHeight or 7*line+2*pad
  local slotHeight=statusHeight-commandHeight
  local itemHeight=mz and slotHeight or height-top-statusHeight
  if width<=312+2*pad+2*ip+8 or 312<=2*pad+2*ip+128 or slotHeight<=2*pad or itemHeight<=2*pad then fail('UI area cannot contain native equipment windows')end
  local function window(r)
   local c=rect(r.x+pad,r.y+pad,r.width-2*pad,r.height-2*pad)
   return{rect=r,contents=c,clipRect=copy(c),rows={},visible=true,active=false}
  end
  local function itemName(row,r)
   row.nameRect=copy(r)
   row.iconRect=rect(r.x+(mz and 0 or 2),r.y+(mz and (line-32)/2 or 2),32,32)
   row.itemTextRect=rect(r.x+36,r.y,mz and math.max(0,r.width-36) or r.width-36,line)
  end
  local function selectable(r,n,cols,kind,first,pixel)
   local w=window(r);local c=w.contents;local maxRows=math.max(1,math.ceil(n/cols));local page=math.floor(c.height/ih)
   if first~=nil and pixel~=nil then fail('Row and pixel scroll requests are mutually exclusive')end
   if pixel==nil then first=integer(default(first,0));pixel=first*ih
   else pixel=number(pixel,0,9007199254740991);if not mz and pixel%ih~=0 then fail('MV equipment scroll must be a whole native row')end end
   local scrollY,originY
   if mz then scrollY=math.min(pixel,math.max(0,maxRows*ih-c.height));first=math.floor(scrollY/ih);originY=scrollY-first*ih
   else scrollY=math.min(pixel,math.max(0,maxRows-page)*ih);first=scrollY/ih;originY=0 end
   w.visibleRows=page;w.firstVisibleRow=first;w.scrollY=scrollY;w.originY=originY;w.maxCols=cols;w.itemHeight=ih
   local draws=mz and math.ceil((c.height+ih)/ih) or page
   local spacing=kind=='item' and 48 or 12;local iw=mz and math.floor(c.width/cols) or math.floor((c.width+spacing)/cols-spacing)
   for index=first*cols,math.min(n-1,(first+draws)*cols-1)do
    local col=index%cols;local row=math.floor(index/cols)-first
    local ir=mz and rect(c.x+col*iw+4,c.y+row*ih+2-originY,iw-8,ih-4) or rect(c.x+col*(iw+spacing),c.y+row*ih,iw,ih)
    local tr=rect(ir.x+ip,ir.y+(mz and (ir.height-line)/2 or 0),ir.width-2*ip,line)
    local e={index=index,rect=ir,textRect=tr}
    if kind=='slot'then
     e.slotRect=rect(tr.x,tr.y,138,line)
     itemName(e,rect(tr.x+138,tr.y,mz and tr.width-138 or 312,line))
    elseif kind=='item'then
     local nw=number(measure('000'),0,9007199254740991)
     local draw=mz and copy(tr) or rect(ir.x,ir.y,ir.width-ip,line)
     e.quantityRect=copy(draw);itemName(e,rect(draw.x,draw.y,draw.width-nw,line))
    else e.symbol=({'equip','optimize','clear'})[index+1]end
    w.rows[#w.rows+1]=e
   end
   return w
  end
  local L={}
  function L.equip(o)
   plain(o);local mode=default(o.mode,'command');if mode~='command' and mode~='slot' and mode~='item'then fail('Invalid equipment UI mode')end
   local slots,items=integer(o.slotCount),integer(o.itemCount);local preview=default(o.preview,false);if type(preview)~='boolean'then fail('Invalid preview option')end
   local help=window(rect(0,mz and height-helpHeight or 0,width,helpHeight))
   help.textRect=rect(help.contents.x+ip,help.contents.y,help.contents.width-ip*(mz and 2 or 1),2*line)
   local status=window(rect(0,top,312,statusHeight));local c=status.contents
   status.nameRect=rect(c.x+ip,c.y,mz and c.width-2*ip or 168,line)
   if mz then status.faceRect=rect(c.x+ip,c.y+line,144,144)end
   status.preview=preview
   for i=0,5 do
    local y=c.y+(mz and 144+math.floor(line*(i+1.5)) or line*(i+1))
    local px=mz and c.width-ip-128 or 140
    status.rows[#status.rows+1]={index=i,paramId=i+2,nameRect=rect(c.x+ip,y,mz and px-2*ip or 120,line),currentRect=rect(c.x+px,y,48,line),arrowRect=rect(c.x+(mz and px+48 or 188),y,32,line),newRect=rect(c.x+(mz and px+80 or 222),y,48,line),newVisible=preview}
   end
   local command=selectable(rect(312,top,width-312,commandHeight),3,3,'command',0)
   local slotRect=rect(312,top+commandHeight,width-312,slotHeight)
   local sw=selectable(slotRect,slots,1,'slot',o.slotFirstRow,o.slotScrollY)
   local iw=selectable(mz and copy(slotRect) or rect(0,top+statusHeight,width,itemHeight),items,mz and 1 or 2,'item',o.itemFirstRow,o.itemScrollY)
   sw.visible=not mz or mode~='item';iw.visible=not mz or mode=='item';command.active=mode=='command';sw.active=mode=='slot';iw.active=mode=='item'
   local enabled=mode~='item'
   local out={help=help,status=status,command=command,slots=sw,items=iw,buttonArea=rect(0,0,width,mz and 52 or 0),pageButtonsEnabled=enabled}
   if mz then out.buttons={cancel={rect=rect(width-100,2,96,48),visible=touch},pageup={rect=rect(4,2,48,48),visible=touch and enabled},pagedown={rect=rect(56,2,48,48),visible=touch and enabled}}end
   return out
  end
  return L
 end
 -- No font service is needed to query the native page capacity. Reuse the
 -- same constructor/window calculation so navigation cannot drift from paint.
 function M.navigation(ui)
  local r=M.new(ui,function()error('Unexpected text measurement for navigation',0)end).equip({slotCount=0,itemCount=0})
  local function nav(w)return{visibleRows=w.visibleRows,maxCols=w.maxCols,innerHeight=w.contents.height,itemHeight=w.itemHeight}end
  return{slots=nav(r.slots),items=nav(r.items)}
 end
 return M
end
