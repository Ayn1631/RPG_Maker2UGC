-- Image bindings are container templates. All source resource keys resolve here.
return function(deps)
 local D,json=deps['contracts.diagnostic'],deps['contracts.json'];local M={}
 local function fail(reason)D.raise('E_RESOURCE_BINDING',reason)end
 local function integer(v,lo,hi)return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
 function M.compile(data,bindings,uiTemplates)
  bindings=bindings or {};if type(bindings)~='table'then fail('assetBindings must be a table')end
  for k in pairs(bindings)do if not ({tiles=true,characters=true,pictures=true,animations=true,balloons=true,videos=true,parallaxes=true,enemies=true,battlebacks1=true,battlebacks2=true})[k]then fail('Unknown assetBindings field '..tostring(k))end end
  local out={kind='r2u.resources',schemaVersion=1,tiles={},characters={},pictures={},animations={},balloons={},parallaxes={},enemies={},battlebacks1={},battlebacks2={}}
  out.faceTemplates=uiTemplates and uiTemplates.faces or {};out.iconTemplates=uiTemplates and uiTemplates.icons or {}
  out.stateIcons=json.object();out.statusIconTemplates=json.object();out.statusIconIndices=json.array()
  local statusIcons={}
  local function statusIcon(index)
   if not integer(index,0,9007199254740991)then fail('State/buff icon index must be a nonnegative integer')end
   if index>0 then statusIcons[index]=true end
  end
  for _,state in ipairs(data.database.States and data.database.States.records or {})do if state~=json.null then
   if not integer(state.id,1,9007199254740991)then fail('State icon entry needs a positive state ID')end
   local index=state.iconIndex or 0;statusIcon(index)
   out.stateIcons[string.format('%.0f',state.id)]=index
  end end
  for _,name in ipairs({'Items','Skills'})do for _,record in ipairs(data.database[name] and data.database[name].records or {})do if record~=json.null then
   for _,effect in ipairs(record.effects or {})do if effect.code==31 or effect.code==32 then
    if not integer(effect.dataId,0,7)then fail('Buff effect parameter must be 0..7')end
    local base=effect.code==31 and 32 or 48
    statusIcon(base+effect.dataId);statusIcon(base+8+effect.dataId)
   end end
  end end end
  for index in pairs(statusIcons)do
   out.statusIconIndices[#out.statusIconIndices+1]=index
   if uiTemplates then out.statusIconTemplates[string.format('%.0f',index)]=uiTemplates.icons and uiTemplates.icons[string.format('%.0f',index)] end
  end
  table.sort(out.statusIconIndices)
  out.richHelp=json.object()
  for _,name in ipairs({'Items','Weapons','Armors','Skills'})do
   for index,record in ipairs(data.database[name] and data.database[name].records or {})do
    local value=record~=json.null and record.description
    if type(value)=='string' and (value:find('\\',1,true) or data.visuWorld and value:find('<',1,true)) and not out.richHelp[value] then
     local ok,tokens=pcall(deps['converter.message'].compile,{value},data.engineProfile=='mv-turn' and 'mv-1.5.1' or 'mz-1.10.0',data.visuWorld)
     if not ok then D.raise(type(tokens)=='table' and tokens.code or 'E_UI_MESSAGE_CONTROL',type(tokens)=='table' and tokens.reason or tostring(tokens),{file='data/'..name..'.json',jsonPath='$['..(index-1)..'].description'})end
     for _,token in ipairs(tokens)do if token.kind=='icon' and uiTemplates then token.templateId=uiTemplates.icons and uiTemplates.icons[string.format('%.0f',token.value)] end end
     out.richHelp[value]=json.array(tokens)
    end
   end
  end
  out.bushDepth=data.engineProfile=='mv-turn' and 12 or (data.database.System.records.tileSize or 48)/4
  out.actorImages={}
  out.videos={};out.videoReplacements=json.array()
  for _,actor in ipairs(data.database.Actors and data.database.Actors.records or {})do if actor~=json.null then
   out.actorImages[tostring(actor.id)]={tileId=0,characterName=actor.characterName or '',characterIndex=actor.characterIndex or 0}
  end end
  local function binding(entry,w,h,kind)
   if type(entry)=='number'then entry={templateId=entry}end
   if type(entry)~='table' or not integer(entry.templateId,1,2147483647)then fail('Resource binding needs a positive templateId')end
   local r={templateId=entry.templateId,width=entry.width or w,height=entry.height or h}
   if not integer(r.width,1,4096) or not integer(r.height,1,4096)then fail('Resource dimensions must be 1..4096')end
   if kind=='characters' and (entry.displayWidth~=nil or entry.displayHeight~=nil)then
    if not integer(entry.displayWidth,1,4096) or not integer(entry.displayHeight,1,4096)then fail('Character displayWidth/displayHeight must both be 1..4096')end
    r.displayWidth,r.displayHeight=entry.displayWidth,entry.displayHeight
   end
   if kind=='characters' and entry.bushFrames~=nil then
    if type(entry.bushFrames)~='table' or #entry.bushFrames~=12 or entry.bushDepth~=out.bushDepth then fail('Character bushFrames need twelve pairs and the game bushDepth')end
    local count=0;for key in pairs(entry.bushFrames)do if not integer(key,1,12)then fail('bushFrames must be dense')end;count=count+1 end
    if count~=12 then fail('bushFrames must be dense')end
    r.bushFrames=json.array();r.bushDepth=entry.bushDepth
    for i,pair in ipairs(entry.bushFrames)do
     if type(pair)~='table' or not integer(pair.upperTemplateId,1,2147483647) or not integer(pair.lowerTemplateId,1,2147483647)then fail('Invalid bush frame template pair')end
     r.bushFrames[i]={upperTemplateId=pair.upperTemplateId,lowerTemplateId=pair.lowerTemplateId}
    end
   end
   if entry.frames then
    if type(entry.frames)~='table' or #entry.frames<1 or #entry.frames>600 or kind=='characters' and #entry.frames~=12 then fail('Invalid resource frame templates; characters require twelve')end
    local count=0;for k in pairs(entry.frames)do if not integer(k,1,#entry.frames)then fail('Resource frames must be a dense array')end;count=count+1 end
    if count~=#entry.frames then fail('Resource frames must be a dense array')end
    r.frames=json.array();for i,id in ipairs(entry.frames)do if not integer(id,1,2147483647)then fail('Invalid frame templateId')end;r.frames[i]=id end
   end
   if kind=='animations' or kind=='balloons' or kind=='videos' then
    r.frameTicks=entry.frameTicks or 4;r.durationFrames=entry.durationFrames or (r.frames and #r.frames*r.frameTicks or 60)
    if not integer(r.frameTicks,1,600) or not integer(r.durationFrames,1,36000)then fail('Invalid animation frame timing')end
   end
   if kind=='videos' then
    if entry.mode~='template-sequence' or not r.frames then fail('Video replacements require mode=template-sequence and explicit frame templates')end
    r.mode=entry.mode
   end
   if kind=='tiles' then
    if r.frames and #r.frames>12 then fail('Tile animations support at most twelve phases')end
    r.frameTicks=entry.frameTicks or 30
    if not integer(r.frameTicks,1,600)then fail('Invalid tile animation timing')end
    if entry.tableEdge then
     if not integer(entry.tableEdge,1,2147483647)then fail('tableEdge must be a positive templateId')end
     r.tableEdge={templateId=entry.tableEdge,width=r.width,height=r.height}
    end
   end
   return r
  end
  for _,kind in ipairs({'characters','pictures','animations','balloons','videos','parallaxes','battlebacks1','battlebacks2'})do
   for key,entry in pairs(bindings[kind] or {})do
    if type(key)~='string' or key==''then fail('Resource keys must be nonempty names')end
    local background=kind=='battlebacks1' or kind=='battlebacks2' or kind=='videos'
    out[kind][key]=binding(entry,background and 816 or kind=='characters' and 48 or 144,background and 624 or kind=='characters' and 48 or 144,kind)
    if kind=='animations'then out[kind][key].renderKey='animation:'..key
    elseif kind=='videos'then out[kind][key].renderKey='video:'..key end
   end
  end
  local system=data.database.System.records
  for _,enemy in ipairs(data.database.Enemies and data.database.Enemies.records or {})do
   if enemy~=json.null then
    local entry=bindings.enemies and (bindings.enemies[tostring(enemy.id)] or bindings.enemies[enemy.battlerName])
    if entry then out.enemies[tostring(enemy.id)]=binding(entry,96,120,'enemies')
    elseif enemy.battlerName==''then out.enemies[tostring(enemy.id)]={empty=true,width=1,height=1}end
   end
  end
  out.tileSize=system.tileSize or 48
  if not integer(out.tileSize,8,128)then fail('Unsupported tileSize')end
  local changedSets={}
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do if ins.op=='tileset'then changedSets[ins.id]=true end end end
  for _,map in ipairs(data.maps)do
   local sets={};for id in pairs(changedSets)do sets[id]=true end;sets[map.settings.tilesetId]=true
   local tileIds={};for slot=1,map.width*map.height*4 do tileIds[map.tiles[slot]]=true end
   for _,event in ipairs(map.events)do if event~=json.null then for _,page in ipairs(event.pages)do tileIds[page.image.tileId]=true end end end
   for setId in pairs(sets)do local set=data.database.Tilesets.records[setId+1]
   local setKey=string.format('%.0f',setId);local tiles=out.tiles[setKey] or {};out.tiles[setKey]=tiles
   for id in pairs(tileIds)do
    local tileKey=string.format('%.0f',id)
    if id>0 and not tiles[tileKey]then
     local entry=bindings.tiles and bindings.tiles[setKey..':'..tileKey]
     local flag=set.flags[id+1];if type(flag)~='number'then fail('Missing flag for tileset '..setId..' tile '..id)end
     local r=entry and binding(entry,out.tileSize,out.tileSize,'tiles') or {}
     r.upper=flag&0x10~=0;r.tableTile=id>=2816 and id<4352 and flag&0x80~=0;r.tileId=id
     if flag&0x40~=0 then out.hasBush=true end
     tiles[tileKey]=r
    end
   end
   end
  end
  out.unboundBushCharacters=json.array()
  if out.hasBush then for key,entry in pairs(out.characters)do
   local name=key:match('^(.*):%d+$') or key;local filename=name:match('[^/\\]+$') or name
   if not entry.bushFrames and not (filename:match('^[!$]+') or ''):find('!',1,true)then out.unboundBushCharacters[#out.unboundBushCharacters+1]=key end
  end;table.sort(out.unboundBushCharacters)end
  local usedVideos={}
  for _,program in pairs(data.eventPrograms)do for _,ins in ipairs(program.instructions)do
   if ins.op=='dialogue' and uiTemplates then
    local streams={ins.flowTokens or {},ins.speakerTokens or {}};for _,tokens in ipairs(ins.choiceTokens or {})do streams[#streams+1]=tokens end
    for _,tokens in ipairs(streams)do for _,token in ipairs(tokens)do
     if token.kind=='icon'then token.templateId=uiTemplates.icons and uiTemplates.icons[string.format('%.0f',token.value)] end
    end end
   end
   if ins.op=='video'then
    ins.asset=out.videos[ins.name]
    if not ins.asset then D.raise('E_VIDEO_BINDING','Bind video '..ins.name..' to an explicit assetBindings.videos template-sequence replacement',ins.source)end
    usedVideos[ins.name]=true
   elseif ins.op=='picture' and ins.action=='show'then ins.asset=out.pictures[ins.name]
   elseif ins.op=='animation' or ins.op=='enemy_animation'then ins.asset=out.animations[string.format('%.0f',ins.animationId)]
   elseif ins.op=='balloon'then ins.asset=out.balloons[string.format('%.0f',ins.balloonId)]
   end
   if (ins.op=='dialogue' or ins.op=='actor_image') and ins.faceName and ins.faceName~='' and uiTemplates then
    local key=ins.faceName..':'..string.format('%.0f',ins.faceIndex)
    ins.faceTemplateId=uiTemplates.faces and uiTemplates.faces[key]
   end
  end end
  for name in pairs(usedVideos)do out.videoReplacements[#out.videoReplacements+1]=name end;table.sort(out.videoReplacements)
  return out
 end
 return M
end
