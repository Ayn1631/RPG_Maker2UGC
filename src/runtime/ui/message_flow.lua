-- Source-token message progression. Inserted actor/variable strings stay literal.
return function(deps)
 local textLimit=deps['runtime.ui.text_limit']
 local M={};local function fail(reason)error({severity='error',code='E_UI_MESSAGE_CONTROL',reason=reason},0)end
 local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
 function M.compile(lines,profile,visu)
  local source=table.concat(lines,'\n');if #source>65536 then fail('Message exceeds the token budget')end
  local out,plain={},{};local pos=1
  -- Visu disables WordWrap for a window containing an alignment tag. Native
  -- MV/MZ messages keep angle brackets and editor line breaks unchanged.
  local lower=visu and source:lower() or '';local hasAlignment=lower:find('<center>',1,true) or lower:find('</center>',1,true)
  local wrapping=false
  local function flush()if #plain>0 then out[#out+1]={kind='text',value=table.concat(plain)};plain={}end end
  local function emit(kind,value,code)flush();out[#out+1]={kind=kind,value=value,code=code}end
  while pos<=#source do
   local c=source:sub(pos,pos)
   local tag=visu and c=='<' and source:sub(pos):match('^(</?[%a ]+>)')
   local name=tag and tag:lower()
   if name=='<wordwrap>' or name=='</wordwrap>'then
    wrapping=name=='<wordwrap>' and not hasAlignment;emit('wordwrap',wrapping);pos=pos+#tag
   elseif name=='<center>' or name=='</center>'then emit('align',name=='<center>' and 'center' or 'left');pos=pos+#tag
   elseif name=='<br>' or name=='<line break>'then emit('newline');pos=pos+#tag
   elseif c=='\n'then if wrapping then plain[#plain+1]=' 'else emit('newline')end;pos=pos+1 elseif c=='\f'then emit('page');pos=pos+1
   elseif c~='\\'then plain[#plain+1]=c;pos=pos+1
   else
    local at=pos;local first=source:sub(pos+1,pos+1):upper()
    local code=first=='G' and first or source:sub(pos+1):match('^([%a]+)') or source:sub(pos+1,pos+1);code=code:upper();pos=pos+1+#code
    if code=='\\'then plain[#plain+1]='\\'
    elseif code=='G'then emit('currency')
    elseif code=='LASTGAINOBJ' or code=='LASTGAINOBJQUANTITY'then emit('visu_gain',nil,code)
    elseif code=='ITEMQUANTITY'then
     local digits=source:sub(pos):match('^%[(%d+)%]');if not digits then fail('Missing ItemQuantity id')end
     pos=pos+#digits+2;emit('item_quantity',tonumber(digits))
    elseif code=='N' or code=='P' or code=='V' or code=='C' or code=='I' or code=='FS' or code=='PX' or code=='PY'then
     local digits=source:sub(pos):match('^%[(%d+)%]');if not digits then fail('Missing numeric parameter for '..code)end
     local n=tonumber(digits);if not n or n>9007199254740991 then fail('Invalid message parameter')end;pos=pos+#digits+2
     if code=='N' or code=='P' or code=='V'then emit('dynamic',n,code)
     elseif code=='C'then if n>31 then fail('Color index must be 0..31')end;emit('color',n)
     elseif code=='I'then emit('icon',n)
     else
      if profile~='mz-1.10.0'then fail(code..' requires the MZ profile')end
      if (code=='FS' and (n<1 or n>512)) or (code~='FS' and n>32768)then fail('Style parameter outside supported bounds')end
      emit(code=='FS' and 'font' or code=='PX' and 'x' or 'y',n)
     end
    elseif code=='.' or code=='|'then emit('wait',code=='.' and 15 or 60)
    elseif code=='!'then emit('pause')elseif code=='>'then emit('fast',true)elseif code=='<'then emit('fast',false)
    elseif code=='^'then emit('auto')elseif code=='$'then emit('gold')
    elseif code=='{'then emit('grow')elseif code=='}'then emit('shrink')
    else fail('Unsupported message control at '..at..': '..code)end
   end
  end;flush();return out
 end
 function M.project(tokens,ui,context)
  context=context or {};local out={}
  for i,token in ipairs(tokens)do
   local t=copy(token);out[i]=t
   if t.kind=='currency'then t.kind='text';t.value=ui.currencyUnit or ''
   elseif t.kind=='item_quantity'then
    if not context.itemCount then fail('ItemQuantity requires the party query')end
    t.kind='text';t.value=string.format('%.0f',context.itemCount(t.value))
   elseif t.kind=='dynamic'then
    local value=''
    if t.code=='N'then value=context.actorName and context.actorName(t.value) or ''
    elseif t.code=='P'then value=context.actorName and context.actorName((context.members or {})[t.value]) or ''
    else local n=(context.variables or {})[t.value] or 0;value=n%1==0 and string.format('%.0f',n) or tostring(n)end
    t.kind='text';t.value=value;t.code=nil
   end
  end
  return out
 end
 -- Window_Base rich text has styles but no Window_Message wait/pause state.
 -- Tokens are compiled offline; dynamic insertions arrive as literal text.
 function M.inline(tokens,ui,measure,originX,originY)
  originX,originY=originX or 0,originY or 0
  local font,color=ui.window.fontSize,0;local x,y=originX,originY
  local result={runs={},icons={},width=0};local mz=ui.profile=='mz-1.10.0'
  local function size(t,n)
   if t.kind=='font'then return t.value elseif t.kind=='grow' and n<=96 then return n+12 elseif t.kind=='shrink' and n>=24 then return n-12 end;return n
  end
  local function lineHeight(index)
   local current,maximum=font,font
   for i=index,#tokens do local t=tokens[i];if t.kind=='newline'then break end;current=size(t,current);maximum=math.max(maximum,current)end
   return maximum+(mz and ui.window.lineHeight-ui.window.fontSize or 8)
  end
  local height=lineHeight(1)
  for i,t in ipairs(tokens)do
   if t.kind=='text'then
    for _,part in ipairs(textLimit.split(t.value))do
     local width=measure(part,font)
     result.runs[#result.runs+1]={x=x,y=y,width=width,height=height,text=part,fontSize=font,colorIndex=color};x=x+width
    end
   elseif t.kind=='icon'then
    local iw=ui.art and ui.art.iconWidth or 32;local ih=ui.art and ui.art.iconHeight or 32
    result.icons[#result.icons+1]={x=x+2+(mz and (32-iw)/2 or 0),y=y+2+(mz and (32-ih)/2 or 0),width=iw,height=ih,iconIndex=t.value,templateId=t.templateId};x=x+36
   elseif t.kind=='color'then color=t.value
   elseif t.kind=='font' or t.kind=='grow' or t.kind=='shrink'then font=size(t,font)
   elseif t.kind=='x'then x=t.value elseif t.kind=='y'then y=t.value
   elseif t.kind=='newline'then result.width=math.max(result.width,x-originX);x=originX;y=y+height;height=lineHeight(i+1)
   elseif t.kind=='dynamic' or t.kind=='currency'then fail('Inline text needs projected dynamic tokens')end
   result.width=math.max(result.width,x-originX)
  end
  return result
 end
 function M.new(message,ui,context)
  context=context or {};local tokens=message.flowTokens or M.compile(message.sourceLines or message.lines,ui.profile);local stream={}
  local function literal(value)for _,cp in utf8.codes(value)do stream[#stream+1]={kind='glyph',value=utf8.char(cp)}end end
  for _,t in ipairs(tokens)do
   if t.kind=='text'then literal(t.value)
   elseif t.kind=='currency'then literal(ui.currencyUnit or '')
   elseif t.kind=='dynamic'then
    local value='';if t.code=='N'then value=context.actorName and context.actorName(t.value) or ''
    elseif t.code=='P'then value=context.actorName and context.actorName((context.members or {})[t.value]) or ''
    else local n=(context.variables or {})[t.value] or 0;value=n%1==0 and string.format('%.0f',n) or tostring(n)end
    literal(value)
   else stream[#stream+1]=copy(t)end
  end
  local scroll=message.scroll;local scrollY=-(ui.box and ui.box.height or ui.screen and ui.screen.height or 624);local scrollHeight=0
  local F={};local index,wait,pause,done=1,0,nil,false
  local font,color=ui.window.fontSize,0;local x,y,row=0,0,0;local lineFast,showFast,auto,gold=false,false,false,false
  local wrap,align=false,'left';local lineEnd;local markup=false
  for _,token in ipairs(stream)do if token.kind=='wordwrap' or token.kind=='align'then markup=true;break end end
  local runs,icons={},{};local page,revision=0,0;local activeRun;local pageUnits,activeUnits=0,0
  local startX=message.faceName and message.faceName~='' and 164 or 0
  x=startX
  local lineSpacing=ui.window.lineHeight-ui.window.fontSize
  local contentsHeight=ui.window.lineHeight*4+(ui.profile=='mz-1.10.0' and 8 or 0)
  local contentsWidth=ui.box and ui.box.width and ui.box.width-(ui.window.padding or 0)*2-4
  if markup and (not contentsWidth or contentsWidth<=startX)then fail('Visu message needs a text area wider than its face inset')end
  local function glyphWidth(value,size)
   if context.measure then return context.measure(value,size)end
   -- The host TextBox API cannot measure its font. A full-em advance keeps
   -- Visu wrapped text inside the box even for wide Latin letters such as W.
   -- Preserve the existing native layout when no Visu markup is present.
   return size*(markup and 1 or value:byte()<128 and .55 or 1)
  end
  local function lineHeight()
   local size,max=font,font
   for i=index,#stream do local t=stream[i];if t.kind=='newline' or t.kind=='page'then break end
    if t.kind=='font'then size=t.value elseif t.kind=='grow' and size<=96 then size=size+12 elseif t.kind=='shrink' and size>=24 then size=size-12 end;max=math.max(max,size)
   end;return max+lineSpacing
  end
  -- Plan only the upcoming visual line. This keeps alignment stable while the
  -- typewriter reveals glyphs, and repeats with reset styles after a new page.
  local function prepareLine()
   if not markup then return lineHeight()end
   local size,maximum,width=font,font,0;local scanningWrap,lineAlign=wrap,align
   local boundary,boundaryWidth,boundaryHeight;local visible=false
   lineEnd=nil
   for i=index,#stream do
    local t=stream[i];local advance
    if t.kind=='newline' or t.kind=='page'then break
    elseif t.kind=='wordwrap'then scanningWrap=t.value
    elseif t.kind=='align'then if not visible then lineAlign=t.value end
    elseif t.kind=='font'then size=t.value;maximum=math.max(maximum,size)
    elseif t.kind=='grow' and size<=96 then size=size+12;maximum=math.max(maximum,size)
    elseif t.kind=='shrink' and size>=24 then size=size-12
    elseif t.kind=='glyph'then
     advance=glyphWidth(t.value,size)
     if t.value:byte()>=128 and visible then boundary,boundaryWidth,boundaryHeight=i,width,maximum end
    elseif t.kind=='icon'then
     advance=36;if visible then boundary,boundaryWidth,boundaryHeight=i,width,maximum end
    end
    if advance then
     if scanningWrap and visible and width+advance>contentsWidth-startX then
      lineEnd=boundary or i;width=boundary and boundaryWidth or width;maximum=boundary and boundaryHeight or maximum;break
     end
     width=width+advance;visible=true
     if t.kind=='icon' or t.value:match('^%s$')then boundary,boundaryWidth,boundaryHeight=i+1,width,maximum end
    end
   end
   x=startX+(lineAlign=='center' and math.max(0,(contentsWidth-startX-width)/2) or 0)
   return maximum+lineSpacing
  end
  local height=prepareLine()
  local function newPage()
   runs,icons={},{};activeRun=nil;pageUnits=0;page=page+1;font,color=ui.window.fontSize,0;x,y,row=startX,0,0
   lineFast,showFast,auto=false,false,false;pause=nil;height=prepareLine();revision=revision+1
  end
  local function paused(kind)pause=kind;wait=10;activeRun=nil;revision=revision+1 end
  local function endText()
   if scroll then done=true;pause=#stream==0 and 'complete' or 'scroll';scrollHeight=math.max(scrollHeight,y+height)
   elseif message.choices or message.numberInput or message.itemChoice then done=true;pause='input'
   elseif auto then done=true;pause='auto'else paused('end');done=true end
  end
  local function step()
   if index>#stream then endText();return false end
   if lineEnd and index==lineEnd then
    x=startX;y=y+height;row=row+1;lineFast=false;activeRun=nil;height=prepareLine()
   end
   if not scroll and (y+height>contentsHeight or row>=4) and (#runs>0 or #icons>0) then paused('page');return false end
   local t=stream[index];index=index+1
   if t.kind=='glyph'then
    local units=textLimit.units(utf8.codepoint(t.value))
    if not scroll and pageUnits+units>textLimit.maximum then index=index-1;paused('page');return false end
    if activeRun and activeUnits+units>textLimit.maximum then activeRun=nil end
    if not activeRun then
     if #runs>=(scroll and 4096 or 256) then fail('Message exceeds the style run budget')end
     activeRun={x=x,y=y+(height-font)/2,fontSize=font,colorIndex=color,text='',width=0};runs[#runs+1]=activeRun;activeUnits=0
    end
    activeRun.text=activeRun.text..t.value
    activeUnits=activeUnits+units;pageUnits=pageUnits+units
    local width=glyphWidth(t.value,font)
    activeRun.width=activeRun.width+width;x=x+width;revision=revision+1
   elseif t.kind=='icon'then
    if #icons>=(scroll and 2048 or 128) then fail('Message exceeds the icon budget')end
    icons[#icons+1]={x=x+2,y=y+(height-32)/2,iconIndex=t.value,templateId=t.templateId};x=x+36;activeRun=nil;revision=revision+1
   elseif t.kind=='newline'then x=startX;y=y+height;row=row+1;lineFast=false;activeRun=nil;height=prepareLine()
    if not scroll and index<=#stream and (y+height>contentsHeight or row>=4)then paused('page')end
   elseif t.kind=='page'then if not scroll then paused('page')end
   elseif t.kind=='color'then color=t.value;activeRun=nil
   elseif t.kind=='font'then font=t.value;activeRun=nil
   elseif t.kind=='grow'then if font<=96 then font=font+12 end;activeRun=nil
   elseif t.kind=='shrink'then if font>=24 then font=font-12 end;activeRun=nil
   elseif t.kind=='x'then x=t.value;activeRun=nil elseif t.kind=='y'then y=t.value;activeRun=nil
   elseif t.kind=='wordwrap'then wrap=t.value
   elseif t.kind=='align'then align=t.value
   elseif not scroll then
    if t.kind=='wait'then wait=t.value elseif t.kind=='pause'then paused('control')
    elseif t.kind=='fast'then lineFast=t.value elseif t.kind=='auto'then auto=true elseif t.kind=='gold'then gold=true;revision=revision+1 end
   end
   if scroll then scrollHeight=math.max(scrollHeight,y+height)end
   if index>#stream and wait==0 and not pause then endText()end
   return t.kind=='glyph' or t.kind=='icon'
  end
  function F.tick(frames,held)
   if scroll then
    if pause~='complete' then scrollY=scrollY+frames*scroll.speed/2*(held and not scroll.noFast and 3 or 1)
     if scrollY>=scrollHeight then pause='complete';revision=revision+1 end
    end
    return F.status()
   end
   if held then showFast=true end
   for _=1,frames do
    if wait>0 then wait=wait-1
    elseif not pause and not done then
     while not pause and wait==0 and not done do
      local visible=step();if visible and not showFast and not lineFast then break end
     end
    end
   end
   return F.status()
  end
  function F.confirm()
   if scroll then return false end
   if wait>0 then return false end
   if pause=='end'then pause='complete';revision=revision+1;return true
   elseif pause=='control'then pause=nil;revision=revision+1;return true
   elseif pause=='page'then newPage();return true
   elseif pause=='input' or pause=='auto' or pause=='complete'then return false end
   showFast=true;F.tick(1,true);return true
  end
  function F.view()return{runs=copy(runs),icons=copy(icons),page=page,revision=revision,wait=wait,pause=pause,finished=pause=='auto' or pause=='complete',inputReady=pause=='input',gold=gold,done=done,scroll=scroll and {y=scrollY,height=scrollHeight} or nil}end
  function F.status()return{revision=revision,finished=pause=='auto' or pause=='complete',inputReady=pause=='input',pause=pause,wait=wait}end
  if #stream==0 then endText()end
  if scroll then while not done do step()end end
  return F
 end
 return M
end
