-- Explicit source-used VisuStella world commands. No JavaScript evaluation.
return function(deps)
 local J,D=deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function fail(reason)D.raise('E_VISU_WORLD',reason)end
 local function int(v,lo,hi)
  local n=tonumber(v);if not n or n%1~=0 or n<(lo or 0) or n>(hi or 9007199254740991)then fail('Expected bounded literal integer: '..tostring(v))end
  return n
 end
 local function bool(v)if v=='true'then return true elseif v=='false'then return false end;fail('Expected literal boolean: '..tostring(v))end
 local function clone(v)
  if type(v)~='table' or v==J.null then return v end
  local o=J.is_array(v)and J.array()or J.object();for k,x in pairs(v)do o[k]=clone(x)end;return o
 end
 local function fields(args,names)
  local allowed={};for _,k in ipairs(names)do allowed[k]=true;if args[k]==nil then fail('Missing argument '..k)end end
  for k in pairs(args)do if not allowed[k]then fail('Unknown argument '..k)end end
 end
 function M.new(index)
  local out={};local db=index.database;local config={labels={},defaultBattleSystem=db.System.records.battleSystem,saveEnabled=false}
  index.visuWorld=config
  local function records(name)return db[name] and db[name].records or {}end
  local function staticText(value)
   if type(value)=='string'then return(value:gsub('\\[Tt][Rr][Oo][Oo][Pp][Nn][Aa][Mm][Ee]%[(%d+)%]',function(id)
    local r=records('Troops')[tonumber(id)+1];if not r or r==J.null then fail('Unknown TroopName reference '..id)end
    return r.name
   end):gsub('\\[Ii][Tt][Ee][Mm]%[(%d+)%]',function(id)
    local r=records('Items')[tonumber(id)+1];if not r or r==J.null then fail('Unknown Item text reference '..id)end
    return (r.iconIndex>0 and ('\\I['..r.iconIndex..']')or'')..r.name
   end))elseif type(value)=='table' and value~=J.null then for k,v in pairs(value)do value[k]=staticText(v)end end
   return value
  end
  for _,map in ipairs(index.maps)do for _,e in ipairs(map.events)do if e~=J.null then for _,p in ipairs(e.pages)do staticText(p.list)end end end end
  for _,e in ipairs(records('CommonEvents'))do if e~=J.null then staticText(e.list)end end
  for _,name in ipairs({'Items','Weapons','Armors','Skills'})do for _,r in ipairs(records(name))do if r~=J.null then r.description=staticText(r.description)end end end
  local function useful(name)
   local ids=J.array()
   for _,r in ipairs(records(name))do if r~=J.null and r.name:match('%S') and not r.name:find('-----',1,true)then ids[#ids+1]=r.id end end
   return ids
  end
  local scripts={}
  for _,v in ipairs({{'Items','item'},{'Weapons','weapon'},{'Armors','armor'}})do
   local n=v[2]
   local source='const amount = Math.max(0, $gameVariables.value(1));\nfor (const '..n..' of $data'..v[1]..') {\n    if (!'..n..') continue;\n    if ('..n..".name.trim() === '') continue;\n    if ("..n..'.name.match(/-----/i)) continue;\n    $gameParty.gainItem('..n..', amount);\n}'
   scripts[source]={op='visu_world',action='gain_all',itemKind=n,ids=useful(v[1]),variableId=1}
  end
  scripts[ [[for (const member of $gameParty.members()) {
    if (!member) continue;
    for (const skill of $dataSkills) {
        if (!skill) continue;
        if (skill.name.trim() === '') continue;
        if (skill.name.match(/-----/i)) continue;
        member.learnSkill(skill.id);
    }
}]] ]={op='visu_world',action='learn_all',ids=useful('Skills')}
  scripts[ [[const id = Math.randomInt(9) + 7;
const amount = Math.randomInt(10) + 1;
$gameParty.gainItem($dataItems[id], amount);]] ]={op='visu_world',action='random_treasure',minimumId=7,idCount=9,minimumAmount=1,amountCount=10}
  function out.script(text,kind)
   text=text:gsub('\r\n','\n')
   if kind=='boolean' and text=='BattleManager.isBattleTest()'then return {kind='visu_battle_test'}end
   if kind=='boolean' and text=='Imported.VisuMZ_3_ActSeqProjectiles'then
    for _,p in ipairs(index.plugins)do if p.status and p.name=='VisuMZ_3_ActSeqProjectiles'then fail('Projectiles plugin requires its own adapter')end end
    return{kind='visu_literal',value=false}
   end
   if kind=='command' and scripts[text]then return clone(scripts[text])end
   fail('Unreviewed '..kind..' script: '..text)
  end
  function out.command(code,p,context)
   if code~=357 then fail('Visu sample requires typed MZ plugin commands')end
   local plugin,name,a=p[1],p[2],p[4]
   if plugin=='VisuMZ_1_EventsMoveCore' and name=='CallEvent'then
    fields(a,{'MapId:eval','EventId:eval','PageId:eval'})
    local m=int(a['MapId:eval']);if m==0 then m=assert(context.mapId,'Current map required for CallEvent')end
    local e,pg=int(a['EventId:eval'],1),int(a['PageId:eval'],1)
    local found=false;for _,map in ipairs(index.maps)do if map.id==m then local event=map.events[e+1];found=event and event~=J.null and event.pages[pg]~=nil end end
    if not found then fail('CallEvent references a missing map/event/page')end
    return{op='call',programId=string.format('map:%d:event:%d:page:%d',m,e,pg)}
   elseif plugin=='VisuMZ_1_ItemsEquipsCore' and name=='BatchShop'then
    fields(a,{'Step1','Step1Start:num','Step1End:num','Step2','Step2Start:num','Step2End:num','Step3','Step3Start:num','Step3End:num','PurchaseOnly:eval','Optional','Blacklist:arraystr','Whitelist:arraystr'})
    if a['Blacklist:arraystr']~='[]' or a['Whitelist:arraystr']~='[]'then fail('BatchShop name filters require explicit review')end
    local goods=J.array()
    for i,v in ipairs({{'Items','item'},{'Weapons','weapon'},{'Armors','armor'}})do
     local first,last=int(a['Step'..i..'Start:num']),int(a['Step'..i..'End:num'])
     if first>0 and last>0 then
      if last<first or last>=#records(v[1])then fail('BatchShop range outside source database')end
      for id=first,last do local r=records(v[1])[id+1]
       if r and r~=J.null and r.name:match('%S') and not r.name:find('-----',1,true)then goods[#goods+1]={kind=v[2],id=id}end
      end
     end
    end
    return{op='shop',goods=goods,purchaseOnly=bool(a['PurchaseOnly:eval'])}
   elseif plugin=='VisuMZ_0_CoreEngine' and name=='OpenURL'then
    fields(a,{'URL:str'});local url=a['URL:str']
    if not url:match('^https?://') or url:find('[%z\r\n]')then fail('Expected explicit HTTP(S) URL')end
    return{op='visu_world',action='open_url',url=url}
   elseif plugin=='VisuMZ_0_CoreEngine' and name=='SystemSetBattleSystem'then
    fields(a,{'option:str'});local systems={database=config.defaultBattleSystem,dtb=0,['tpb active']=1,['tpb wait']=2}
    local system=systems[a['option:str']];if system==nil then fail('Unsupported battle system '..a['option:str'])end
    return{op='visu_world',action='battle_system',value=system}
   elseif plugin=='VisuMZ_0_CoreEngine' and name=='ScreenShake'then
    fields(a,{'Type:str','Power:num','Speed:num','Duration:eval','Wait:eval'})
    local mode=a['Type:str'];if not ({original=true,random=true,horizontal=true,vertical=true})[mode]then fail('Unknown shake type')end
    return{op='screen',action='shake',shakeMode=mode,power=int(a['Power:num'],0,9),speed=int(a['Speed:num'],0,9),duration=int(a['Duration:eval'],0,360000),wait=bool(a['Wait:eval'])}
   elseif plugin=='VisuMZ_1_MessageCore' and name=='ChoiceWindowProperties'then
    fields(a,{'LineHeight:num','MaxRows:num','MaxCols:num','TextAlign:str'})
    local align=a['TextAlign:str'];if not ({default=true,left=true,center=true,right=true})[align]then fail('Unknown choice alignment')end
    return{op='visu_world',action='choices',lineHeight=int(a['LineHeight:num'],1,512),rows=int(a['MaxRows:num'],1,8),columns=int(a['MaxCols:num'],1,6),align=align}
   elseif plugin=='VisuMZ_1_SaveCore' and (name=='SavePicture' or name=='SaveDescription')then
    local k=name=='SavePicture' and 'Filename:str' or 'Text:str';fields(a,{k})
    return{op='visu_world',action='save_metadata',key=name=='SavePicture' and 'picture' or 'description',value=a[k]}
   end
   fail('Unimplemented world command '..plugin..'.'..name)
  end
  -- Explicit note grammar. Unknown labels are not inferred from event names.
  for _,map in ipairs(index.maps)do local labels={};config.labels[tostring(map.id)]=labels
   for _,event in ipairs(map.events)do if event~=J.null then
    local pages={};labels[tostring(event.id)]=pages
    for n,p in ipairs(event.pages)do
     local note=event.note or '';for _,c in ipairs(p.list)do if c.code==108 or c.code==408 then note=note..'\n'..c.parameters[1]end end
     local label={};local box={left=0,right=0,up=0,down=0}
     for name,value in note:gmatch('<([^:<>]+):%s*([^<>]-)>')do
      name=name:lower();value=value:match('^%s*(.-)%s*$')
      if name=='label'then label.text=value
      elseif name=='icon'then label.icon=int(value,0,100000)
      elseif name=='label color'then label.color=int(value,0,31)
      elseif name=='label offset x'then label.x=int(value,-2048,2048)
      elseif name=='label offset y'then label.y=int(value,-2048,2048)
      elseif name=='label offset'then local x,y=value:match('^([+-]?%d+)%s*,%s*([+-]?%d+)$');label.x=int(x,-2048,2048);label.y=int(y,-2048,2048)
      elseif name=='icon buffer y'then label.iconY=int(value,-2048,2048)
      elseif name:match('^hitbox ')then local side=name:sub(8);if box[side]==nil then fail('Unknown hitbox side')end;box[side]=int(value,0,99)
      else fail('Unreviewed event note '..name)end
     end
     p.visuHitbox=box;pages[n]=label
    end
   end end
  end
  return out
 end
 return M
end
