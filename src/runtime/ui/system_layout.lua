-- Calculate rectangles for system menus without creating or mutating host controls.
return function()
 local M={}
 function M.new(ui)
  local L={};local w,h,p,line=ui.box.width,ui.box.height,ui.window.padding,ui.window.lineHeight
  -- MZ system windows reserve eight extra pixels per row for their native touch layout.
  local mz=ui.profile=='mz-1.10.0';local rh=line+(mz and 8 or 0)
  local function rect(x,y,width,height)return{x=x,y=y,width=width,height=height}end
  -- `first` and returned row indices are zero-based, matching RPG Maker list indices.
  local function window(x,y,width,height,n,cols,first)
   local c=rect(x+p,y+p,width-p*2,height-p*2);local out={rect=rect(x,y,width,height),contents=c,clipRect=c,textRect=c,rows={},visible=true}
   cols=cols or 1;first=first or 0;out.visibleRows=math.floor(c.height/rh);out.firstVisibleRow=first
   local cell=c.width/cols
   for i=first*cols,math.min(n-1,(first+out.visibleRows)*cols-1)do local r=rect(c.x+i%cols*cell+4,c.y+(math.floor(i/cols)-first)*rh+2,cell-8,rh-4)
    out.rows[#out.rows+1]={index=i,rect=r,textRect=rect(r.x+ui.window.itemPadding,r.y,r.width-ui.window.itemPadding*2,line)}
   end;return out
  end
  -- Center the title commands and honor the source title-command window offsets.
  function L.title()
   local t=ui.titleCommandWindow or {};local height=4*rh+p*2
   local command=window((w-240)/2+(t.offsetX or 0),h-height-96+(t.offsetY or 0),240,height,4);command.background=t.background or 0
   return{command=command,title=rect(20,h/4,w-40,96)}
  end
  -- The end-game command list is centered independently of title-screen commands.
  function L.gameEnd()local height=3*rh+p*2;return{command=window((w-240)/2,(h-height)/2,240,height,3)}end
  -- Game over keeps only the centered message rectangle.
  function L.gameover()return{title=rect(20,h/2-48,w-40,96)}end
  -- Lay out the name editor and its ten-column character palette.
  function L.name(v)
   local width=math.min(600,w);local editHeight=144+p*2;local inputHeight=9*rh+p*2;local top=(h-editHeight-inputHeight-8)/2
   local edit=window((w-width)/2,top,width,editHeight,0);edit.faceRect=rect(edit.contents.x,edit.contents.y,144,144)
   local input=window((w-width)/2,top+editHeight+8,width,inputHeight,90,10)
   local cell=math.floor((input.contents.width-24)/10)
   for _,row in ipairs(input.rows)do
    local col=row.index%10;local x=input.contents.x+col*cell+math.floor(col/5)*24+4
    row.rect=rect(x,input.contents.y+math.floor(row.index/10)*rh+2,cell-8,rh-4)
    row.textRect=rect(row.rect.x,row.rect.y,row.rect.width,line)
   end
   return{edit=edit,list=input}
  end
  -- Place numeric/choice input opposite the message window to avoid covering its text.
  function L.messageInput(v,messageLayout,first)
   local m=messageLayout.message;local y=m.rect.y
   if v.kind=='number'then
    local width=math.max(#v.rows*48,mz and ui.touchUI and 192 or 0)+p*2;local height=rh+p*2+(mz and ui.touchUI and 56 or 0)
    local top=y>=h/2 and y-height-8 or y+m.rect.height+8
    local model=window((w-width)/2,top,width,height,#v.rows,#v.rows)
    local offset=(model.contents.width-#v.rows*48)/2
    for _,row in ipairs(model.rows)do row.rect=rect(model.contents.x+offset+row.index*48,model.contents.y+2,48,rh-4);row.textRect=row.rect end
    return model
   end
   local height=4*rh+p*2;local top=y>=h/2 and 0 or h-height
   return window(0,top,w,height,#v.rows,2,first)
  end
  return L
 end
 return M
end
