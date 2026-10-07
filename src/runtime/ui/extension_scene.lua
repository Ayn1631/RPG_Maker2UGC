-- One generic list/detail controller for all registered MenuProviders.
return function(deps)
 local textLimit=deps['runtime.ui.text_limit']
 local M={}
 local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
 function M.new(world,ui,extensionId,menuId)
  local S={};local index,revision,detailPage=0,0,0;local model,notice;local pages={''}
  local function paginate()
   local row=model.rows[index+1];local value=row and row.description or 'No entries.'
   local p,line=ui.window.padding,ui.window.lineHeight;local width=ui.box.width-math.min(320,math.floor(ui.box.width*.4))-2*p
   local height=ui.box.height-(ui.profile=='mz-1.10.0' and 52 or 0)-2*(line+2*p)-2*p-line*2
   local limit=math.max(1,math.floor(height/line));local lines,buffer,used={},'',0
   for _,cp in utf8.codes(value)do
    local c=utf8.char(cp);local advance=(cp<128 and .65 or 1.1)*ui.window.fontSize
    if c=='\n' then lines[#lines+1]=buffer;buffer,used='',0
    elseif c~='\r'then
     if used+advance>width and buffer~=''then
      local space=buffer:match('^.*()%s')
      if space and space>1 then lines[#lines+1]=buffer:sub(1,space-1);buffer=buffer:sub(space+1)
      else lines[#lines+1]=buffer;buffer=''end
      used=0;for _,part in utf8.codes(buffer)do used=used+(part<128 and .65 or 1.1)*ui.window.fontSize end
     end
     if c~=' ' or buffer~=''then buffer=buffer..c;used=used+advance end
    end
   end
   lines[#lines+1]=buffer;pages={}
   for first=1,#lines,limit do local chunk={};for i=first,math.min(#lines,first+limit-1)do chunk[#chunk+1]=lines[i]end
    for _,part in ipairs(textLimit.split(table.concat(chunk,'\n')))do pages[#pages+1]=part end
   end
   detailPage=math.min(detailPage,#pages-1)
  end
  local function refresh()
   local selected=model and model.rows[index+1] and model.rows[index+1].id
   model=world.extensionMenuView(extensionId,menuId);index=math.min(index,math.max(0,#model.rows-1))
   for i,row in ipairs(model.rows)do if row.id==selected then index=i-1;break end end
   paginate()
   revision=revision+1
  end
  refresh()
  function S.view()
   local view=copy(model);view.selectedIndex=index;view.revision=revision;view.notice=notice or ''
   view.description=pages[detailPage+1];view.detailPage=detailPage;view.detailPages=#pages;return view
  end
  function S.confirm()
   local row=model.rows[index+1];if not row or not row.action then return false end
   local result=world.extensionMenuAction({extensionId=extensionId,menuId=menuId,rowId=row.id,revision=model.revision})
   if result.ok then notice=nil else notice='Action unavailable: '..tostring(result.reason)end
   refresh();return true
  end
  function S.select(kind,value)
   if #model.rows==0 then return false end
   if kind=='navigate' and (value==4 or value==6)then
    local nextPage=math.max(0,math.min(#pages-1,detailPage+(value==6 and 1 or -1)))
    if nextPage==detailPage then return false end;detailPage=nextPage;revision=revision+1;return true
   end
   if kind=='touch'then
    if type(value)~='number' or value%1~=0 or value<0 or value>=#model.rows then return false end
    if value==index then return S.confirm()end;index=value
   elseif value==2 then index=(index+1)%#model.rows
   elseif value==8 then index=(index-1+#model.rows)%#model.rows
   else return false end
   notice=nil;detailPage=0;paginate();revision=revision+1;return true
  end
  function S.soundState()return{index=index,page=detailPage,rejected=notice~=nil}end
  return S
 end
 return M
end
