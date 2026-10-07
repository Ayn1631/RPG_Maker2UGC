-- Build-time display-text translation. Gameplay symbols and asset identities stay intact.
return function(deps)
 local J,D=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 function M.visit(data,translate)
  local function field(row,key,kind)
   if type(row[key])=='string' and row[key]:match('%S')then row[key]=translate(row[key],kind)end
  end
  local function values(row,kind)for k in pairs(row or {})do field(row,k,kind)end end
  local function list(commands)
   for _,c in ipairs(commands or {})do local p=c.parameters
    if c.code==401 or c.code==405 then field(p,1,'dialogue')
    elseif c.code==101 then field(p,5,'dialogue')
    elseif c.code==102 then values(p[1],'dialogue')
    elseif c.code==402 then field(p,2,'dialogue')
    elseif c.code==320 or c.code==324 or c.code==325 then field(p,2,'dialogue')
    elseif c.code==357 and p[1]=='VisuMZ_1_SaveCore' and p[2]=='SaveDescription'then field(p[4],'Text:str','dialogue')end
   end
  end
  local function traits(v)
   values(v.traitLabels,'database')
   -- traitSets/group/candidate.name remain exact internal identities; only labels render.
   for _,group in ipairs(v.randomTraits or {})do for _,candidate in ipairs(group.candidates)do traits(candidate.visu)end end
  end
  for _,name in ipairs({'Actors','Classes','Skills','Items','Weapons','Armors','States','Enemies','Troops'})do
   for _,r in ipairs(data.database[name].records)do if r~=J.null then
    for _,key in ipairs({'name','nickname','profile','description','message1','message2','message3','message4'})do field(r,key,'database')end
    if r.visu then
     field(r.visu,'Command Text','database');field(r.visu,'Biography','database');traits(r.visu)
     for _,command in ipairs(r.visu.battleCommands or {})do field(command,'label','database')end
    end
    if name=='Troops'then for _,page in ipairs(r.pages)do list(page.list)end end
   end end
  end
  for _,e in ipairs(data.database.CommonEvents.records)do if e~=J.null then list(e.list)end end
  for _,map in ipairs(data.maps)do
   field(map.settings,'displayName','database')
   for _,event in ipairs(map.events)do if event~=J.null then for _,page in ipairs(event.pages)do list(page.list)end end end
  end
  for _,events in pairs(data.visuWorld.labels)do for _,pages in pairs(events)do for _,label in ipairs(pages)do field(label,'text','dialogue')end end end
  local s=data.database.System.records
  field(s,'gameTitle','database');field(s,'currencyUnit','database')
  for _,key in ipairs({'elements','skillTypes','weaponTypes','armorTypes','equipTypes'})do values(s[key],'database')end
  for _,key in ipairs({'basic','commands','params','messages'})do values(s.terms[key],'database')end
 end
 function M.apply(data,dictionary)
  M.visit(data,function(text)
   local translated=dictionary[text]
   if type(translated)~='string'then D.raise('E_VISU_TRANSLATION','Missing Chinese display text: '..text)end
   return translated
  end)
  data.database.System.records.locale='zh-CN'
  data.database.System.records.terms.messages.optionOn='开启'
  data.database.System.records.terms.messages.optionOff='关闭'
  data.database.System.records.terms.messages.battleContinue='继续'
  data.database.System.records.terms.messages.inputPage='翻页'
  data.database.System.records.terms.messages.inputOk='确定'
 end
 return M
end
