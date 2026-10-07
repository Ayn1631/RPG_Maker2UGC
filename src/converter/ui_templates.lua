-- Generic build-time template inventory, independent of any game adapter.
return function(deps)
 local J,D=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function fail(s)D.raise('E_UI_TEMPLATE_CATALOG',s)end
 local function id(value)
  if type(value)~='number' or value%1~=0 or value<1 or value>2147483647 then fail('Expected a positive client template ID')end
  return string.format('%.0f',value)
 end
 function M.compile(data,catalog)
  if type(catalog)~='table' or catalog.version~=1 or type(catalog.templates)~='table'then fail('Expected version 1 client template catalog')end
  local wanted={}
  local function need(value)if value~=nil and value~=J.null then wanted[id(value)]=true end end
  local templateFields={templateId=true,upperTemplateId=true,lowerTemplateId=true,faceTemplateId=true,
   containerTemplate=true,textTemplate=true,buttonTemplate=true,imageTemplate=true,cursorTemplate=true}
  local templateMaps={faceTemplates=true,iconTemplates=true,statusIconTemplates=true,faces=true,icons=true}
  local function walk(v)
   if type(v)~='table' or v==J.null then return end
   for key,value in pairs(v)do
    if templateFields[key]then need(value)
    elseif templateMaps[key] and type(value)=='table'then
     for _,entry in pairs(value)do if type(entry)=='number'then need(entry)else walk(entry)end end
    elseif key=='frames' and type(value)=='table'then
     for _,frame in pairs(value)do if type(frame)=='number'then need(frame)else walk(frame)end end
    else walk(value)end
   end
  end
  walk(data.worldPreview);walk(data.eventPreview);walk(data.resources);walk(data.uiArt)
  local art=data.worldPreview and data.worldPreview.artTemplates
  if art then need(art.portrait);need(art.icon)end
  local function descriptor(v,depth)
   if type(v)~='table' or v==J.null or depth>64 then fail('Invalid client template tree')end
   if not ({container=true,textbox=true,image=true,cursor=true,button=true})[v.kind]then fail('Unsupported client template kind '..tostring(v.kind))end
   if type(v.properties)~='table' or type(v.colors)~='table' or type(v.children)~='table'then fail('Template properties/colors/children are required')end
   local length=0;for key in pairs(v.children)do
    if type(key)~='number' or key%1~=0 or key<1 or key>#v.children then fail('Template children must be a dense array')end;length=length+1
   end
   if length~=#v.children then fail('Template children must be a dense array')end
   local out={kind=v.kind,count=1,properties=J.object(),colors=J.object(),children=J.array()}
   for key,value in pairs(v.properties)do
    if type(key)~='string' or not ({string=true,number=true,boolean=true})[type(value)]then fail('Only scalar native template defaults are supported')end
    if type(value)=='number' and (value~=value or value==math.huge or value==-math.huge)then fail('Non-finite template default')end
    out.properties[key]=value
   end
   for key,rgba in pairs(v.colors)do
    if not ({bgColor=true,imageColor=true,fontColor=true,outlineColor=true})[key]or type(rgba)~='table'or #rgba~=4 then fail('Invalid template RGBA default')end
    local copy=J.array();for i=1,4 do local n=rgba[i];if type(n)~='number'or n%1~=0 or n<0 or n>255 then fail('Invalid template color channel')end;copy[i]=n end;out.colors[key]=copy
   end
   for i,child in ipairs(v.children)do local compiled=descriptor(child,depth+1);out.children[i]=compiled;out.count=out.count+compiled.count end
   if out.count~=v.count then fail('Declared template count differs from its actual tree')end
   if out.count>400 then fail('A template cannot atomically instantiate more than 400 controls; split the template')end
   return out
  end
  local out={version=1,templates=J.object()}
  for key in pairs(wanted)do
   if not catalog.templates[key]then fail('No exact client template structure for ID '..key..'; import the target templates with tools/import-ui-templates.py and set uiTemplateCatalog')end
   out.templates[key]=descriptor(catalog.templates[key],0)
  end
  return out
 end
 return M
end
