-- Source logical pixels. Host scaling, drawing, fonts and interaction are separate.
return function(deps)
 local flow=deps['runtime.ui.message_flow']
 local M={}
 local function fail(reason)error({severity='error',code='E_UI_LAYOUT',reason=reason},0)end
 local function plain(x)if type(x)~='table' or getmetatable(x)~=nil then fail('Expected plain layout data')end end
 local function number(x,lo,hi)if type(x)~='number' or x~=x or x<(lo or 0) or x>(hi or 32768)then fail('Invalid layout number')end;return x*1.0 end
 local function choiceEnum(x)number(x,0,2);if x%1~=0 then fail('Invalid window mode')end;return x end
 local function texts(x,limit)
  plain(x);local count,highest=0,0
  for key,value in next,x do
   if type(key)~='number' or key%1~=0 or key<1 or key>limit or type(value)~='string'then fail('Expected a bounded dense string array')end
   count=count+1;highest=math.max(highest,key)
  end
  if count~=highest then fail('Text array must not contain gaps')end;return count
 end
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 function M.new(ui,measure)
  plain(ui);plain(ui.box);plain(ui.window)
  local mz=ui.profile=='mz-1.10.0';if not mz and ui.profile~='mv-1.5.1'then fail('Unsupported UI profile')end
  local width,height=number(ui.box.width,1),number(ui.box.height,1)
  local padding,line,itemPad=number(ui.window.padding),number(ui.window.lineHeight,1),number(ui.window.itemPadding)
  if type(measure)~='function'then fail('A text measurement service is required')end
  local messageHeight=line*4+padding*2+(mz and 8 or 0)
  if width<=padding*2 or height<messageHeight then fail('UI area is too small for the source message window')end
  local rowHeight=line+(mz and 8 or 0)
  local L={}
  local function measured(text)
   if type(text)~='string'then fail('Text must be a string')end
   return number(measure(text),0,9007199254740991)
  end
  function L.message(message,previous)
   plain(message);local lineCount=texts(message.lines,100000)
   if message.scroll then
    return{message={rect=rect(0,0,width,height),contents=rect(padding,padding,width-padding*2,height-padding*2),background=2,visible=true,scroll=true},name=false,choices=false}
   end
   if previous~=nil then plain(previous)end
   local position=choiceEnum(message.position==nil and 2 or message.position)
   local background=choiceEnum(message.background==nil and 0 or message.background)
   local shown=lineCount>0
   local y=0
   if shown then y=position*(height-messageHeight)/2
   elseif previous~=nil then plain(previous);y=number(previous.y,0,height)end
   local frame=rect(0,y,width,messageHeight)
   local textX=padding+(mz and 4 or 0)
   if mz and message.rtl==true then textX=width-padding-4 end
   local out={message={visible=shown,rect=frame,background=background,contents=rect(padding,y+padding,width-padding*2,messageHeight-padding*2),textX=textX,textY=y+padding},name=false,choices=false}
   local speaker=message.speaker or '';if type(speaker)~='string'then fail('Speaker must be a string')end
   if mz and shown and speaker~=''then
    local tokens=message.speakerTokens
    local textWidth=tokens and flow.inline(tokens,ui,measure).width or measured(speaker)
    local w=math.min(width,math.ceil(textWidth)+(padding+itemPad)*2)
    local h=line+padding*2;local x=message.rtl==true and width-w or 0
    local ny=y>0 and y-h or y+messageHeight
    out.name={rect=rect(x,ny,w,h),contents=rect(x+padding,ny+padding,w-padding*2,h-padding*2),clipRect=rect(x+padding,ny+padding,w-padding*2,h-padding*2),background=background,textX=x+padding+itemPad,textY=ny+padding,text=speaker,
     rich=tokens and flow.inline(tokens,ui,measure,itemPad,0) or nil}
   end
   if message.choices~=nil then
    local limit=message.extendedChoices and 128 or 6;local count=texts(message.choices,limit)
    if count<1 or count>limit then fail('Choices exceed declared native/extended limit')end
    local cp=choiceEnum(message.choicePosition==nil and 2 or message.choicePosition)
    local cb=choiceEnum(message.choiceBackground==nil and 0 or message.choiceBackground)
    local style=message.choiceLayout or {};local columns=style.columns or 1
    number(columns,1,6);if columns%1~=0 then fail('Invalid choice columns')end
    local choiceLine=style.lineHeight or line;number(choiceLine,1,512)
    local choiceHeight=choiceLine+(mz and 8 or 0)
    local widest=96
    for i,text in ipairs(message.choices)do local tokens=message.choiceTokens and message.choiceTokens[i]
     local tw=tokens and flow.inline(tokens,ui,measure).width or measured(text)
     if mz then tw=math.ceil(tw)end;widest=math.max(widest,tw+itemPad*2)
    end
    local cw=math.min(width,(widest+(mz and 8 or 0))*columns+padding*2)
    local maxRows=y<height/2 and y+messageHeight>height/2 and 4 or 8
    maxRows=style.rows or maxRows;number(maxRows,1,8)
    local totalRows=math.ceil(count/columns)
    local rows=math.min(totalRows,maxRows);local ch=rows*choiceHeight+padding*2
    local cx=cp*(width-cw)/2;local cy=y>=height/2 and y-ch or y+messageHeight
    local selected=message.selectedChoice;if selected==nil then selected=message.defaultChoice or 0 end
    number(selected,-1,count-1);if selected%1~=0 then fail('Invalid selected choice')end
    local first=previous and previous.choiceFirstVisibleRow or 0
    number(first,0,5);if first%1~=0 then fail('Invalid choice scroll row')end
    first=math.min(first,math.max(0,totalRows-rows))
    if not mz and selected==-1 then first=0 end
    local selectedRow=math.floor(selected/columns)
    if selected>=0 then if selectedRow<first then first=selectedRow elseif selectedRow>=first+rows then first=selectedRow-rows+1 end end
    local items={};local cursor=false
    local cellWidth=(cw-padding*2)/columns
    for index=first*columns,math.min(count-1,(first+rows)*columns-1)do
     local ry=(math.floor(index/columns)-first)*choiceHeight;local rx=(index%columns)*cellWidth
     local ir=mz and rect(cx+padding+rx+4,cy+padding+ry+2,math.floor(cellWidth)-8,choiceHeight-4) or rect(cx+padding+rx,cy+padding+ry,math.floor(cellWidth),choiceHeight)
     local textRect=rect(ir.x+itemPad,ir.y+(ir.height-choiceLine)/2,math.max(0,ir.width-itemPad*2),choiceLine)
     local tokens=message.choiceTokens and message.choiceTokens[index+1]
     local labelWidth=tokens and flow.inline(tokens,ui,measure).width or measured(message.choices[index+1])
     local align=style.align;local offset=align=='center' and math.max(0,(textRect.width-labelWidth)/2) or align=='right' and math.max(0,textRect.width-labelWidth) or 0
     textRect.x=textRect.x+offset;textRect.width=textRect.width-offset
     items[#items+1]={index=index,label=message.choices[index+1],rect=ir,textRect=textRect,
      rich=tokens and flow.inline(tokens,ui,measure,textRect.x-cx-padding,textRect.y-cy-padding) or nil}
     if index==selected then cursor=ir end
    end
    out.choices={rect=rect(cx,cy,cw,ch),contents=rect(cx+padding,cy+padding,cw-padding*2,ch-padding*2),clipRect=rect(cx+padding,cy+padding,cw-padding*2,ch-padding*2),background=cb,items=items,cursor=cursor,firstVisibleRow=first,visibleRows=rows,upArrow=first>0,downArrow=first+rows<totalRows}
   end
   return out
  end
  return L
 end
 return M
end
