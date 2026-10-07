-- Standard native UI data only. Rendering/font import are separate capabilities.
return function(deps)
 local json,diagnostic=deps['contracts.json'],deps['contracts.diagnostic'];local M={};local SAFE=9007199254740991
 local arrayMeta,objectMeta=getmetatable(json.array()),getmetatable(json.object())
 function M.compile(data,options)
  local diagnostics={};local file,path='source-index','$'
  local function fail(reason,code,p)diagnostic.raise(code or 'E_UI_SOURCE',reason,{file=file,jsonPath=p or path})end
  local function check(ok,reason,code,p)if not ok then fail(reason,code,p)end end
  local function tableData(v)
   check(type(v)=='table' and not rawequal(v,json.null),'Expected data table')
   local mt=getmetatable(v);check(mt==nil or rawequal(mt,arrayMeta) or rawequal(mt,objectMeta),'Untrusted metatable')
  end
  local function object(v)tableData(v);check(not rawequal(getmetatable(v),arrayMeta),'Expected object')end
  local function finite(v)check(type(v)=='number' and v==v and v~=math.huge and v~=-math.huge,'Expected finite number');return v*1.0 end
  local function integer(v,lo,hi)local value=finite(v);check(value%1==0 and value>=(lo or -SAFE) and value<=(hi or SAFE),'Integer outside supported range');return value end
  local function text(v)check(type(v)=='string','Expected string');return v end
  local function boolean(v)check(type(v)=='boolean','Expected boolean');return v end
  local function dense(v)
   tableData(v);check(not rawequal(getmetatable(v),objectMeta),'Expected array')
   local count,high=0,0;for k in next,v do integer(k,1,100000);count=count+1;high=math.max(high,k)end
   check(count==high,'Expected dense array');return count
  end
  local function at(p,fn)local old=path;path=p;local out=fn();path=old;return out end
  local function asset(relative,base)
   check(type(relative)=='string' and #relative<=4096,'Expected bounded font filename','E_UI_FONT')
   check(not relative:find('[%z\1-\31]') and not relative:find('[:?#]') and not relative:match('^[/\\]'),'Font resource must be a local relative path','E_UI_FONT')
   check(not relative:find('%%'),'Encoded font URLs require an explicit adapter','E_UI_FONT')
   local out={};for part in (base..'/'..relative):gsub('\\','/'):gmatch('[^/]+')do
    if part=='..'then check(#out>0,'Font resource escapes source root','E_UI_FONT');table.remove(out)
    elseif part~='.'then out[#out+1]=part end
   end;check(#out>0,'Empty font path','E_UI_FONT');return table.concat(out,'/')
  end
  local function term(v)if rawequal(v,json.null)then return ''end;return text(v)end
  local function terms(source)
   object(source);local out={}
   for _,key in ipairs({'basic','params','commands'})do
    out[key]=at('$.terms.'..key,function()local n=dense(source[key]);local a={};for i=1,n do a[i]=at('$.terms.'..key..'['..(i-1)..']',function()return term(source[key][i])end)end;return a end)
   end
   out.messages=at('$.terms.messages',function()
    object(source.messages);local a={};local count=0
    for key,v in next,source.messages do check(type(key)=='string','Message key must be string');count=count+1;check(count<=100000,'Too many UI messages','E_UI_BUDGET');a[key]=at('$.terms.messages.'..key,function()return term(v)end)end
    return a
   end);return out
  end
  local function mvFonts(css)
   if css==nil then
    local d=diagnostic.new('W_UI_FONT_CSS','GameFont asset is unknown without original fonts/gamefont.css',{file='fonts/gamefont.css',jsonPath='$'});d.severity='warning';diagnostics[#diagnostics+1]=d;return {},false
   end
   local oldFile,oldPath=file,path;file,path='fonts/gamefont.css','$'
   check(type(css)=='string' and #css<=1048576,'Expected bounded static CSS','E_UI_FONT')
   local source=css:gsub('/%*.-%*/','');local found={}
   for block in source:gmatch('@font%-face%s*{(.-)}')do
    local declarations={}
    for declaration in (block..';'):gmatch('(.-);')do
     local key,value=declaration:match('^%s*([%w%-]+)%s*:%s*(.-)%s*$')
     if key then key=key:lower();declarations[key]=declarations[key] or {};declarations[key][#declarations[key]+1]=value end
    end
    local families=declarations['font-family'];local family=families and families[1]
    if family then
     family=family:match('^%s*(.-)%s*$');if family:sub(1,1)=='"' or family:sub(1,1)=="'"then local quote=family:sub(1,1);check(family:sub(-1)==quote,'Malformed font family','E_UI_FONT');family=family:sub(2,-2)end
     if family=='GameFont'then
      check(#families==1,'Duplicate font-family declarations require an adapter','E_UI_FONT')
      check(not declarations['font-weight'] and not declarations['font-style'],'Font variants require an explicit font adapter','E_UI_FONT')
      local sources=declarations.src;check(sources and #sources==1,'Exactly one GameFont src declaration required','E_UI_FONT');local src=sources[1]
      local url=src:match('^%s*url%s*%((.-)%)%s*$');check(url~=nil,'Only one static local GameFont URL is supported','E_UI_FONT')
      url=url:match('^%s*(.-)%s*$');if url:sub(1,1)=='"' or url:sub(1,1)=="'"then local quote=url:sub(1,1);check(url:sub(-1)==quote,'Malformed font URL','E_UI_FONT');url=url:sub(2,-2)end
      found[#found+1]={family='GameFont',path=asset(url,'fonts')}
     end
    end
   end
   check(#found==1,'Exactly one static GameFont rule required','E_UI_FONT');file,path=oldFile,oldPath;return found,true
  end
  local function compile()
   object(data);if options==nil then options={}end;object(options)
   for key in next,options do check(key=='mvFontCss' or key=='includePresentation' or key=='hostFont' or key=='extensions','Unknown UI compile option')end
   if options.extensions~=nil then check(type(options.extensions)=='table' and type(options.extensions.standardUI)=='function','Expected registered extension service')end
   if options.includePresentation~=nil then boolean(options.includePresentation)end
   if options.hostFont~=nil then boolean(options.hostFont)end
   local mv=data.engineProfile=='mv-turn' and data.sourceVersion=='1.5.1'
   -- 1.9 and 1.10 native layout differ only in icon coordinate rounding and
   -- shop bitmap/scroll repairs; platform rendering shares the same contract.
   local mz=(data.engineProfile=='mz-turn' or data.engineProfile=='mz-tpb-active' or data.engineProfile=='mz-tpb-wait') and (data.sourceVersion=='1.10.0' or data.sourceVersion=='1.9.0' and data.visuWorld~=nil)
   check(mv or mz,'Only MV 1.5.1 and MZ 1.10.0 standard UI profiles are supported','E_UI_PROFILE')
   if data.plugins~=nil then
    file='js/plugins.js';for i=1,dense(data.plugins)do
     path='$['..(i-1)..']';local p=data.plugins[i];object(p);text(p.name);boolean(p.status)
     check(not p.status or options and options.extensions and options.extensions.standardUI(p.name),'Enabled plugins have no standard UI adapter','E_UI_UNSUPPORTED')
    end
   end
   file,path='data/System.json','$';object(data.database);object(data.database.System);local s=data.database.System.records;object(s)
   local locale=at('$.locale',function()return text(s.locale)end)
   local out={schemaVersion=1,profile=mv and 'mv-1.5.1' or 'mz-1.10.0',locale=locale,screen={},box={},window={},fonts={assets={}},
    menuCommandOrder={'item','skill','equip','status','formation','options','save','gameEnd'},touchUI=mz,touchUIConfigurable=mz,
    capabilities={nativeUiConfig=true,fontAssetsKnown=true,fontsImported=false,pixelFaithfulRender=false,standardCoreOnly=true}}
   out.gameTitle=at('$.gameTitle',function()return text(s.gameTitle)end);out.currencyUnit=at('$.currencyUnit',function()return text(s.currencyUnit)end);out.optDisplayTp=at('$.optDisplayTp',function()return boolean(s.optDisplayTp)end)
   out.startAtTitle=true
   out.optDrawTitle=s.optDrawTitle==nil and true or at('$.optDrawTitle',function()return boolean(s.optDrawTitle)end)
   out.titleCommandWindow={offsetX=0,offsetY=0,background=0}
   if s.titleCommandWindow~=nil then at('$.titleCommandWindow',function()
    object(s.titleCommandWindow);local t=s.titleCommandWindow
    out.titleCommandWindow={offsetX=integer(t.offsetX or 0),offsetY=integer(t.offsetY or 0),background=integer(t.background or 0,0,2)}
   end)end
   out.itemCategories=mv and {true,true,true,true} or at('$.itemCategories',function()
    check(dense(s.itemCategories)==4,'Item categories require four flags');local a={};for i=1,4 do a[i]=at('$.itemCategories['..(i-1)..']',function()return boolean(s.itemCategories[i])end)end;return a
   end)
   out.optKeyItemsNumber=mv or at('$.optKeyItemsNumber',function()return boolean(s.optKeyItemsNumber)end)
   local iconSize=mv and 32 or (s.iconSize~=nil and at('$.iconSize',function()return integer(s.iconSize,1)end) or 32)
   local faceSize=mv and 144 or (s.faceSize~=nil and at('$.faceSize',function()return integer(s.faceSize,1)end) or 144)
   out.art={iconWidth=iconSize,iconHeight=iconSize,faceWidth=faceSize,faceHeight=faceSize}
   out.window={padding=mv and 18 or 12,margin=4,lineHeight=36,itemPadding=mv and 6 or 8,opacity=255,
    fontSize=28,backOpacity=192,tone={},toneChannels=3,skinPath='img/system/Window.png',outlineWidth=mv and 4 or 3,outlineColor={0,0,0,(mv and .5 or .6)*255.0},
    dimColors={center={0,0,0,153},edge={0,0,0,0}}}
   out.window.tone=at('$.windowTone',function()
    check(dense(s.windowTone)==4,'Window tone requires four source components');local a={};for i=1,4 do a[i]=at('$.windowTone['..(i-1)..']',function()return integer(s.windowTone[i],i==4 and 0 or -255,255)end)end;return a
   end)
   out.terms=at('$.terms',function()return terms(s.terms)end)
   out.equipmentTypes=at('$.equipTypes',function()
    local n=dense(s.equipTypes);check(n>=1,'Equipment type dictionary requires source slot zero');local a={}
    for i=1,n do a[i]=at('$.equipTypes['..(i-1)..']',function()return text(s.equipTypes[i])end)end;return a
   end)
   if s.skillTypes~=nil then out.skillTypes=at('$.skillTypes',function()
    local n=dense(s.skillTypes);check(n>=1,'Skill type dictionary requires source slot zero');local a={}
    for i=1,n do a[i]=at('$.skillTypes['..(i-1)..']',function()return text(s.skillTypes[i])end)end;return a
   end)end
   out.menuCommands=at('$.menuCommands',function()
    if mv and (s.menuCommands==nil or rawequal(s.menuCommands,json.null) or s.menuCommands==false)then return{true,true,true,true,true,true}end
    local n=dense(s.menuCommands);local a={};for i=1,n do at('$.menuCommands['..(i-1)..']',function()boolean(s.menuCommands[i])end)end
    for i=1,6 do a[i]=s.menuCommands[i]==true end;return a
   end)
   if mv then
    out.screen={width=816,height=624,scale=1};out.box={width=816,height=624,offsetX=0,offsetY=0}
    local face=locale:match('^zh') and 'SimHei, Heiti TC, sans-serif' or locale:match('^ko') and 'Dotum, AppleGothic, sans-serif' or 'GameFont'
    out.fonts={mainFace=face,numberFace=face,titleFace='GameFont',fallbackFonts='',assets={}}
    if not options.hostFont then local assets,known=mvFonts(options.mvFontCss);out.fonts.assets=assets;out.capabilities.fontAssetsKnown=known end
   else
    local a=at('$.advanced',function()object(s.advanced);return s.advanced end)
    local function value(key,fn)return at('$.advanced.'..key,function()return fn(a[key])end)end
    out.screen={width=value('screenWidth',function(v)return integer(v,1)end),height=value('screenHeight',function(v)return integer(v,1)end),scale=1}
    if a.screenScale~=nil then out.screen.scale=value('screenScale',function(v)local n=finite(v);check(n>0 and n<=SAFE,'Screen scale must be positive supported finite number');return n end)end
    local w=value('uiAreaWidth',function(v)return integer(v,9)end)-8.0;local h=value('uiAreaHeight',function(v)return integer(v,9)end)-8.0
    out.box={width=w,height=h,offsetX=(out.screen.width-w)/2.0,offsetY=(out.screen.height-h)/2.0}
    out.window.fontSize=value('fontSize',function(v)return integer(v,1)end)
    out.window.backOpacity=value('windowOpacity',function(v)local n=finite(v);check(n>=-SAFE and n<=SAFE,'Opacity outside supported number domain');return math.max(0.0,math.min(255.0,n))end)
    local fallback=value('fallbackFonts',text);local face='rmmz-mainfont, '..fallback
    out.fonts={mainFace=face,numberFace='rmmz-numberfont, '..face,titleFace=face,fallbackFonts=fallback,assets={}}
    for _,pair in ipairs(options.hostFont and {} or {{'mainFontFilename','rmmz-mainfont'},{'numberFontFilename','rmmz-numberfont'}})do
     local relative=value(pair[1],text);if relative~=''then out.fonts.assets[#out.fonts.assets+1]={family=pair[2],path=at('$.advanced.'..pair[1],function()return asset(relative,'fonts')end)}end
    end
   end
   if options.hostFont then
    out.fonts={mainFace='host',numberFace='host',titleFace='host',fallbackFonts='',assets={}}
    out.capabilities.fontAssetsKnown=false;out.capabilities.hostFont=true
   end
   if options.includePresentation then
    out.presentationDefs={}
    local entries={{'Actors','actors',{'name','nickname','profile','faceName','characterName'}},{'Classes','classes',{'name'}},{'Items','items',{'name','description'}},{'Weapons','weapons',{'name','description'}},{'Armors','armors',{'name','description'}}}
    if data.database.Skills~=nil then entries[#entries+1]={'Skills','skills',{'name','description'}}end
    for _,entry in ipairs(entries)do
     local name,key,strings=entry[1],entry[2],entry[3];file,path='data/'..name..'.json','$'
     local envelope=data.database[name];object(envelope);local values=envelope.records;local n=dense(values);local records={};out.presentationDefs[key]=records
     if n>0 then check(rawequal(values[1],json.null),'Database slot zero must be null')end
     for i=2,n do
      local source=values[i];if not rawequal(source,json.null)then
       path='$['..(i-1)..']';object(source);local record={id=at(path..'.id',function()local id=integer(source.id,1);check(id==i-1,'Record ID must match source array slot');return id end)}
       for _,field in ipairs(strings)do record[field]=at(path..'.'..field,function()return text(source[field])end)end
       if name=='Actors'then
        for _,field in ipairs({'faceIndex','characterIndex'})do record[field]=at(path..'.'..field,function()return integer(source[field],0,7)end)end
       elseif name~='Classes'then record.iconIndex=at(path..'.iconIndex',function()return integer(source.iconIndex,0)end)end
       records[#records+1]=record
      end
     end
    end
   end
   return out
  end
  local ok,value=pcall(compile)
  if ok then return{ok=true,ui=value,diagnostics=diagnostics}end
  if diagnostic.is(value)then diagnostics[#diagnostics+1]=value;return{ok=false,diagnostics=diagnostics}end
  error(value,0)
 end
 return M
end
