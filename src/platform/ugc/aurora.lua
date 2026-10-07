-- Retained Aurora panel: selection moves one parent; animation touches model
-- roots / gauge width only. Static image children are written once on mount.
return function(deps)
 local M={};local windows=deps['platform.ugc.rpg_windows']
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 function M.new(host,parent,bindings,ui,skin,art,dispatch)
  local W=windows.new(host,parent,bindings,ui,skin);local width,height=ui.screen.width,ui.screen.height
  local panel,selection,title,lines,rows,actors,stage,gauges,ball,footer
  local revision,selected,token,stageKey,modelKey;local lineRows={};local modelSurfaces={};local lastShown={};local textSpecs={}
  local minimumFont=20;local bodyPage,bodyRevision,choiceFirst=0,nil,nil;local pager,choicePager
  local api={}
  local function surface()return windows.new(host,parent,bindings,ui,skin)end
  local function txt(owner,name,value,r,size,paint)
   local o=W.text(owner,'Aurora '..name,value,r,size,paint or{230,239,243,255},true);textSpecs[o]={rect=r,size=size};return o
  end
  local function font(size)return math.max(size,minimumFont)end
  -- Native UGC line metrics and padding are taller than the simulator's glyphs.
  -- Size the layout from the template minimum before placing adjacent controls.
  local function textHeight(size)return math.ceil(font(size)*1.65)+8 end
  local function wrap(values,maxWidth)
   local result={};for _,value in ipairs(values)do local line,used='',0
    for _,cp in utf8.codes(value)do local c=utf8.char(cp);local advance=(cp>=128 and 1.1 or .7)*font(21)
     if c=='\n'or used+advance>maxWidth then result[#result+1]=line;line,used='',0 end
     if c~='\n'then line=line..c;used=used+advance end
    end;result[#result+1]=line
   end;return result
  end
  local function destroyModels()for _,s in ipairs(modelSurfaces)do s.close()end;modelSurfaces={};actors={};modelKey=nil end
  local function model(id,tier,x,y,size)
   local frame=assert(art.species[tostring(id)]and art.species[tostring(id)][tier],'Aurora model binding missing')
   local sw=surface();modelSurfaces[#modelSurfaces+1]=sw
   local g=sw.group('Aurora model '..id..' '..tier,rect(x,y,size,size),panel)
   sw.blit(g,frame,0,0,size,size)
   return{surface=sw,group=g,x=x,y=y,size=size}
  end
  local function status(p,x,y)
   local nh,th=textHeight(22),textHeight(20);local by=8+nh+th;local h=by+14+th+4
   local g=W.group('Aurora status '..x,rect(x,y,325,h),panel)
   W.solid(g,'Aurora status back',rect(0,0,325,h),{21,51,66,255})
   local n=txt(g,'name','',rect(8,4,309,nh),22,{255,245,217,255})
   local t=txt(g,'types','',rect(8,4+nh,309,th),20,{181,219,229,255})
   W.solid(g,'Aurora hp back',rect(8,by,309,10),{10,31,41,255})
   local bar=W.group('Aurora HP',rect(8,by,309,10),g);W.solid(bar,'Aurora HP fill',rect(0,0,309,10),{134,210,162,255})
   local hp=txt(g,'hp','',rect(8,by+14,309,th),20)
   return{group=g,name=n,types=t,hp=hp,bar=bar,barY=by,lastHp=-1}
  end
  local function set(object,value)if lastShown[object]~=value then local spec=textSpecs[object];W.updateText(object,value,spec.rect,spec.size);lastShown[object]=value end end
  function api.close()
   destroyModels();if stage then stage.surface.close();stage=nil end
   W.close();panel=nil;revision,selected,stageKey=nil,nil,nil;lineRows={};rows={};lastShown={};textSpecs={};bodyPage,bodyRevision,choiceFirst,pager,choicePager=0,nil,nil,nil,nil
  end
  local function create()
   panel=W.group('Aurora scene',rect(0,0,width,height))
   W.solid(panel,'Aurora backdrop',rect(0,0,width,height),{8,25,35,255})
   W.solid(panel,'Aurora header',rect(0,0,width,76),{22,59,74,255})
   W.solid(panel,'Aurora header line',rect(0,73,width,3),{141,213,180,255})
   title=txt(panel,'title','',rect(38,8,width-225,60),28,{255,242,203,255})
   minimumFont=title.minimumFontSize or 20
   lines=W.group('Aurora lines',rect(40,100,width-80,480),panel)
   selection=W.group('Aurora selection',rect(36,0,4,42),panel)
   W.solid(selection,'Aurora selected edge',rect(0,0,4,42),{255,229,160,255})
   footer=txt(panel,'cancel','返回 [X]',rect(width-150,10,135,56),20)
   local cancel=W.area(panel,'Aurora cancel',rect(width-150,10,140,52))
   W.bind(cancel,function()dispatch{kind='cancel',token=token}end)
   rows={};actors={};gauges={}
  end
  local function modelProjection(v)
   local key={};if v.battle then key={'battle',v.battle.player.id,v.battle.enemy.id}
   else key={v.tier};for _,p in ipairs(v.portraits)do key[#key+1]=p.id end end;key=table.concat(key,':')
   if key==modelKey then return end;destroyModels();modelKey=key
   if v.battle then actors[1]=model(v.battle.player.id,'detail',85,145,180);actors[2]=model(v.battle.enemy.id,'detail',800,112,180)
   else for i,p in ipairs(v.portraits)do local size=#v.portraits==1 and v.tier=='detail'and 180 or 96
    actors[i]=model(p.id,v.tier,878+(i-1)%2*100,115+math.floor((i-1)/2)*108,size)end end
  end
  function api.render(v,newToken)
   token=newToken;if not panel then create()end
   local bg=v.battle and v.battle.terrain or''
   if bg~=stageKey then
    if stage then stage.surface.close();stage=nil end
    if bg~=''then local sw=surface();local g=sw.group('Aurora battle backdrop',rect(26,96,width-52,250),panel)
     sw.blit(g,assert(art.backgrounds[bg]),0,0,width-52,250);g.object:SetSiblingIndex(3);stage={surface=sw,group=g}
    end;stageKey=bg
   end
   if v.battle and not gauges[1]then
    gauges[2]=status(v.battle.enemy,432,100)
    gauges[1]=status(v.battle.player,282,108+gauges[2].group.height)
   end
   for _,g in ipairs(gauges)do W.show(g.group,v.battle~=nil)end
   modelProjection(v)
   local lh=textHeight(21);local bh=math.max(44,textHeight(20)+6);local step=bh+5
   local ly=v.battle and math.max(366,gauges[1].group.y+gauges[1].group.height+12)or 100
   local n=#v.choices
   local pageRows=math.max(1,math.floor((height-25-ly-lh-16)/step))
   local shown=math.min(n,pageRows);local first=math.floor(v.selectedIndex/pageRows)*pageRows
   if v.revision~=revision or first~=choiceFirst then
    if bodyRevision~=v.revision then bodyPage=0;bodyRevision=v.revision end
    set(title,v.title);footer:SetVisible(not v.lock)
    local tw=#v.portraits>0 and 810 or width-80
    local textLines=wrap(v.lines,tw-16);W.move(lines,40,ly)
    local cy=math.min(math.max(v.battle and 425 or 160,ly+#textLines*lh+20),height-25-shown*step)
    local capacity=math.max(1,math.floor((cy-ly-16)/lh))
    local paged=#textLines>capacity
    local pages=math.max(1,math.ceil(#textLines/capacity));bodyPage=bodyPage%pages
    local visibleLines=math.min(capacity,#textLines-bodyPage*capacity)
    for i=1,visibleLines do local value=textLines[bodyPage*capacity+i]
     if not lineRows[i]then lineRows[i]=txt(lines,'line '..i,'',rect(0,(i-1)*lh,tw,lh),21,{190,213,222,255})end
     local spec=textSpecs[lineRows[i]]
     if spec.rect.width~=tw then spec.rect.width=tw;lineRows[i]:SetSizeDelta(tw,lh);lineRows[i]:SetAnchoredPosition(tw/2-lines.width/2,lines.height/2-(i-1)*lh-lh/2)end
     set(lineRows[i],value);lineRows[i]:SetVisible(true)
    end
    for i=visibleLines+1,#lineRows do lineRows[i]:SetVisible(false)end
    if paged and not pager then
     pager={group=W.group('Aurora text pages',rect(width-550,8,360,60),panel)}
     pager.text=txt(pager.group,'text page','',rect(0,0,360,60),20)
     for i,delta in ipairs({-1,1})do local hit=W.area(pager.group,'Aurora text page '..i,rect((i-1)*180,0,180,60))
      W.bind(hit,function()bodyPage=bodyPage+delta;revision=nil end)
     end
    end
    if pager then W.show(pager.group,paged);if paged then set(pager.text,'‹ 正文 '..(bodyPage+1)..' / '..pages..' ›')end end
    local titleWidth=paged and width-620 or width-225
    if textSpecs[title].rect.width~=titleWidth then
     textSpecs[title].rect.width=titleWidth;title:SetSizeDelta(titleWidth,60);title:SetAnchoredPosition(38+titleWidth/2-width/2,height/2-38)
     W.updateText(title,v.title,textSpecs[title].rect,textSpecs[title].size)
    end
    local bw=#v.portraits>0 and 800 or width-72
    if n>pageRows and not choicePager then
     choicePager=W.group('Aurora choice scroll',rect(width-34,0,32,144),panel)
     for i,d in ipairs({8,2})do
      txt(choicePager,'scroll '..i,i==1 and'↑'or'↓',rect(0,(i-1)*72,32,64),20)
      local hit=W.area(choicePager,'Aurora choice scroll '..i,rect(0,(i-1)*72,32,72))
      W.bind(hit,function()dispatch{kind='navigate',direction=d,token=token}end)
     end
    end
    if choicePager then W.show(choicePager,n>pageRows);W.move(choicePager,width-34,cy)end
    shown=math.min(shown,n-first)
    for i=1,shown do local label=v.choices[first+i]
     local row=rows[i]
     if not row then
      local sw=surface();local g=sw.group('Aurora choice '..i,rect(36,cy+(i-1)*(bh+5),bw,bh),panel)
      sw.solid(g,'Aurora choice back',rect(0,0,bw,bh),{23,51,67,255})
      local t=sw.text(g,'Aurora choice text '..i,'',rect(14,3,bw-28,bh-3),20,nil,true)
      local hit=sw.area(g,'Aurora choice hit '..i,rect(0,0,bw,bh))
      row={surface=sw,group=g,text=t,hit=hit,bw=bw,bh=bh};rows[i]=row
      sw.bind(hit,function()dispatch{kind='touch',index=row.index,token=token}end)
     end
     -- Width/height changes affect the row parent; all fixed children scale with it.
     row.group.object:SetLocalScale(bw/row.bw,bh/row.bh,1);row.surface.move(row.group,36+(bw-row.bw)/2,cy+(i-1)*(bh+5)+(bh-row.bh)/2);row.surface.show(row.group,true)
     row.index=first+i-1
     if row.label~=label then row.surface.updateText(row.text,label,rect(14,3,row.bw-28,row.bh-3),20);row.label=label end
    end
    -- Rows no longer present are no longer needed. Delete their own subtree.
    for i=#rows,shown+1,-1 do rows[i].surface.close();rows[i]=nil end
    selection.object:SetLocalScale(1,bh/42,1)
    selection.cy,selection.bh=cy,bh;selected=nil;revision=v.revision;choiceFirst=first
   end
   if selected~=v.selectedIndex then
    W.move(selection,30,selection.cy+(v.selectedIndex-choiceFirst)*(selection.bh+5)+(selection.bh-42)/2);selection.object:SetAsLastSibling()
    selected=v.selectedIndex
   end
   -- Selection is a narrow accent; opaque row backgrounds remain stable.
   if v.battle then
    local fx=v.battle.fx
    for i,p in ipairs({v.battle.player,v.battle.enemy})do
     local g=gauges[i];set(g.name,p.name..'  Lv.'..p.level);set(g.types,p.types..' '..p.status)
     local hp=p.hp;if fx then local id=i==1 and fx.pid or fx.eid;local old=i==1 and fx.php or fx.ehp;if id==p.id then hp=math.floor(old+(p.hp-old)*math.min(1,fx.t/30)+.5)end end
     if g.lastHp~=hp then local ratio=math.max(0,hp/p.maxHp);g.bar.object:SetLocalScale(ratio,1,1);W.move(g.bar,8-309*(1-ratio)/2,g.barY);set(g.hp,'HP '..hp..' / '..p.maxHp);g.lastHp=hp end
    end
    local enemy=actors[2];local visible=not fx or not(fx.kind=='attack'and fx.t>8 and fx.t<28 and math.floor(fx.t/4)%2==0)and not(fx.kind=='ball'and fx.success and fx.t>36)
    enemy.surface.show(enemy.group,visible)
    if fx and fx.kind=='ball'and fx.t<70 then
     if not ball then ball=W.group('Aurora capture ball',rect(0,0,16,16),panel);W.solid(ball,'Aurora ball red',rect(0,0,16,8),{238,119,116,255});W.solid(ball,'Aurora ball white',rect(0,8,16,8),{233,245,235,255});W.solid(ball,'Aurora ball seam',rect(0,7,16,3),{16,41,56,255})end
     local q=math.min(1,fx.t/35);W.move(ball,fx.t<38 and 212+650*q or 872+math.sin(fx.t*1.5)*6,fx.t<38 and 257-140*math.sin(q*math.pi)-70*q or 260);W.show(ball,true)
    elseif ball then W.show(ball,false)end
   elseif ball then W.show(ball,false)end
  end
  local close=api.close
  function api.close()for _,r in ipairs(rows or{})do r.surface.close()end;close();gauges,ball=nil,nil end
  return api
 end
 return M
end
