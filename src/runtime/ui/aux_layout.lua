-- MV/MZ menu windows for skills, shops and effective session options.
return function()
 local M={}
 function M.new(ui)
  local L={};local w,h=ui.box.width,ui.box.height;local p,line=ui.window.padding,ui.window.lineHeight
  local mz=ui.profile=='mz-1.10.0';local bh=mz and 52 or 0;local rh=line+(mz and 8 or 0)
  local function rect(x,y,width,height)return{x=x,y=y,width=width,height=height}end
  local function window(x,y,width,height,n,cols,first,rowHeight)
   local rh=rowHeight or rh
   local c=rect(x+p,y+p,width-p*2,height-p*2);local out={rect=rect(x,y,width,height),contents=c,clipRect=c,rows={},visible=true,textRect=c}
   cols=cols or 1;n=n or 0;local visible=math.max(1,math.floor(c.height/rh));first=math.max(0,math.min(first or 0,math.max(0,math.ceil(n/cols)-visible)))
   out.visibleRows,out.firstVisibleRow=visible,first;local cell=c.width/cols
   for i=first*cols,math.min(n-1,(first+visible)*cols-1)do
    local r=rect(c.x+i%cols*cell+4,c.y+(math.floor(i/cols)-first)*rh+2,cell-8,rh-4)
    out.rows[#out.rows+1]={index=i,rect=r,textRect=rect(r.x+ui.window.itemPadding,r.y,r.width-ui.window.itemPadding*2,line)}
   end;return out
  end
  local function help()return window(0,mz and h-(line*2+p*2) or 0,w,line*2+p*2)end
  function L.skill(v,first,typeFirst)
   local helpWindow=help();local y=mz and bh or helpWindow.rect.height;local top=3*rh+p*2;local bottom=mz and helpWindow.rect.y or h
   local status=window(mz and 0 or 240,y,w-240,top);local c=status.contents
   status.faceRect=rect(c.x+(mz and 5 or 0),c.y,144,c.height)
   status.simpleStatusAnchor={x=c.x+(mz and 184 or 162),y=c.y+c.height/2-line*1.5}
   status.gaugeWidth=mz and 186 or math.min(200,c.width-342-ui.window.itemPadding*2)
   if status.gaugeWidth==0 then status.gaugeWidth=186 end
   return{help=helpWindow,types=window(mz and w-240 or 0,y,240,top,#v.types,1,typeFirst),status=status,
    list=window(0,y+top,w,bottom-y-top,#v.rows,2,first)}
  end
  function L.shop(v,first)
   local helpWindow=help();local y=mz and bh or helpWindow.rect.height;local top=rh+p*2;local bottom=mz and helpWindow.rect.y or h
   local listY=y+top;local category=v.mode=='category' or v.mode=='sell'
   local out={help=helpWindow,command=window(0,y,w-240,top,3,3),gold=window(w-240,y,240,top)}
   if v.mode=='command'then out.dummy=window(0,listY,w,bottom-listY)
   elseif v.mode=='number'then out.number=window(0,listY,w-352,bottom-listY);out.status=window(w-352,listY,352,bottom-listY)
   elseif category then
    local show=not mz or #v.categories>1
    if show then out.category=window(0,listY,w,top,#v.categories,#v.categories);listY=listY+top end
    out.list=window(0,listY,w,bottom-listY,#v.rows,2,first)
   else out.list=window(0,listY,w-352,bottom-listY,#v.rows,1,first);out.status=window(w-352,listY,352,bottom-listY)end
   return out
  end
  function L.options(v)
   -- Host fonts can be wider than RPG Maker's font. Keep labels and values
   -- in separate columns; W.text fits longer labels within the remaining width.
   local width=math.min(520,w);local height=math.min(h-bh,#v.rows*rh+p*2)
   return{list=window((w-width)/2,(h-height)/2,width,height,#v.rows)}
  end
  function L.extension(v,first)
   local header=line+p*2;local left=math.min(320,math.floor(w*.4));local y=bh+header
   return{header=window(0,bh,w,header),list=window(0,y,left,h-y,#v.rows,1,first,rh*2),
    detail=window(left,y,w-left,h-y-header),action=window(left,h-header,w-left,header)}
  end
  return L
 end
 return M
end
