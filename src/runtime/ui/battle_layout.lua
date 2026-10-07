-- MV/MZ Scene_Battle source box geometry. Presentation assets remain replaceable.
return function()
 local M={}
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 function M.new(ui)
  local mz=ui.profile=='mz-1.10.0';local width,height=ui.box.width,ui.box.height
  local pad,line=ui.window.padding,ui.window.lineHeight;local ih=line+(mz and 8 or 0);local area=ih*4+pad*2
  local function window(r,p)
   p=p or pad;local c=rect(r.x+p,r.y+p,r.width-p*2,r.height-p*2)
   return{rect=r,contents=c,clipRect=rect(c.x,c.y,c.width,c.height),rows={},visible=true}
  end
  local function selectable(r,count,cols,first)
   local w=window(r);local c=w.contents;w.visibleRows=math.floor(c.height/ih);w.firstVisibleRow=first or 0;w.maxCols=cols
   local iw=math.floor(c.width/cols)
   for i=w.firstVisibleRow*cols,math.min(count-1,(w.firstVisibleRow+w.visibleRows)*cols-1)do
    local r=rect(c.x+(i%cols)*iw+4,c.y+(math.floor(i/cols)-w.firstVisibleRow)*ih+2,iw-8,ih-4)
    w.rows[#w.rows+1]={index=i,rect=r,textRect=rect(r.x+8,r.y+(r.height-line)/2,r.width-16,line)}
   end;return w
  end
  local L={}
  function L.battle(o)
   local status=window(rect(mz and 0 or 192,height-area-(mz and 4 or 0),width-192,area+(mz and 10 or 0)),mz and 8 or pad)
   local c=status.contents;local iw=math.floor(c.width/4)
   for i=0,math.min(o.partyCount,4)-1 do
    if mz then
     local r=rect(c.x+i*iw+4,c.y,iw-8,c.height)
     local gauges=ui.optDisplayTp and 3 or 2;local gy=r.y+r.height-10-gauges*24
     status.rows[#status.rows+1]={index=i,rect=r,nameRect=rect(r.x+8,gy-24,r.width-16,24),faceRect=rect(r.x+1,r.y+1,r.width-2,math.max(1,gy-24-r.y+12)),gaugesX=r.x+8,gaugesY=gy,gaugeWidth=math.max(1,r.width-16),iconRect=rect(r.x+r.width-36,r.y+4,32,32),iconCycle=true}
    else
     local r=rect(c.x,c.y+i*line,c.width,line);local textX=r.x+6;local textWidth=r.width-12
     local gx=textX+textWidth-330
     local gauges={hp=rect(gx,r.y,ui.optDisplayTp and 108 or 201,line),mp=rect(gx+(ui.optDisplayTp and 123 or 216),r.y,ui.optDisplayTp and 96 or 114,line)}
     if ui.optDisplayTp then gauges.tp=rect(gx+234,r.y,96,line)end
     status.rows[#status.rows+1]={index=i,rect=r,nameRect=rect(textX,r.y,150,line),gauges=gauges,iconRect=rect(textX+156,r.y+2,math.max(0,textWidth-330-15-156),32),iconCycle=false}
    end
   end
   local command=selectable(rect(mz and width-192 or 0,height-area,192,area),o.mode=='party' and 2 or (o.mode=='actor' and o.rowCount or 4),1,o.firstRow)
   command.visible=o.mode=='party' or o.mode=='actor'
   local background=o.mode=='target' and o.backgroundMode~=nil
   local list=selectable(rect(0,height-area,width,area),background and o.backgroundCount or o.rowCount or 0,2,background and o.backgroundFirstRow or o.firstRow);list.visible=o.mode=='skill' or o.mode=='item' or background
   if background then
    list.sourceRect=rect(list.rect.x,list.rect.y,list.rect.width,list.rect.height)
    list.rect=rect(mz and width-192 or 0,list.rect.y,192,list.rect.height)
    list.clipRect=rect(list.rect.x,list.contents.y,mz and 192-pad or 192,list.contents.height);list.partial=true
   end
   local targets=selectable(rect(status.rect.x,height-area,status.rect.width,area),o.rowCount or 0,2,o.firstRow);targets.visible=o.mode=='target'
   if targets.visible and o.targetSide=='actor'then
    targets=window(rect(status.rect.x,status.rect.y,status.rect.width,status.rect.height),mz and 8 or pad);targets.background=2;targets.visible=true
    for i,actorIndex in ipairs(o.targetIndices or {})do local row=status.rows[actorIndex+1];if row then targets.rows[#targets.rows+1]={index=i-1,rect=row.rect,textRect=row.nameRect}end end
   end
   local help=window(rect(0,0,width,line*2+pad*2));help.textRect=rect(help.contents.x+8,help.contents.y,help.contents.width-16,line*2);help.visible=list.visible
   local log=window(rect(0,0,width,line*3+pad*2));log.background=2;log.textRect=rect(log.contents.x+8,log.contents.y,log.contents.width-16,line*3)
   -- Scene_Message.messageWindowRect: calcWindowHeight(4, false) + 8;
   -- Window_Message.updatePlacement defaults to positionType 2 (bottom).
   local resultHeight=line*4+pad*2+(mz and 8 or 0)
   local result=window(rect(0,height-resultHeight,width,resultHeight));result.visible=o.mode=='result';result.textRect=rect(result.contents.x+(mz and 4 or 0),result.contents.y,result.contents.width-(mz and 4 or 0),line*4)
   local continueRect=rect(result.contents.x+result.contents.width-100,result.rect.y+result.rect.height-20,100,20)
   result.rows[1]={index=0,rect=continueRect,textRect=continueRect}
   return{status=status,command=command,list=list,targets=targets,help=help,log=log,result=result,field=rect(0,0,width,height-area),buttonArea=rect(0,line*2+pad*2,width,mz and 52 or 0)}
  end
  return L
 end
 return M
end
