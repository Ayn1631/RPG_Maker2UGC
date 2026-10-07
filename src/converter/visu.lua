-- Adapter for the supplied VisuMZ sample configuration, not arbitrary plugins.
return function(deps)
 local J,F,D=deps['contracts.json'],deps['build.files'],deps['contracts.diagnostic'];local M={}
 local names={'VisuMZ_0_CoreEngine','VisuMZ_1_BattleCore','VisuMZ_1_ElementStatusCore','VisuMZ_1_EventsMoveCore','VisuMZ_1_ItemsEquipsCore','VisuMZ_1_MainMenuCore','VisuMZ_1_MessageCore','VisuMZ_1_OptionsCore','VisuMZ_1_SaveCore','VisuMZ_1_SkillsStatesCore'}
 local function fail(s)D.raise('E_VISU_ADAPTER',s)end
 function M.wrap(base,config,root)
  if config.gameAdapter~='visu'then fail('Expected Visu game adapter')end
  local pinned=J.decode(assert(F.read(root..'/projects/visu-mz/plugin-parameters.json')))
  local out,enabled,parameters={}, {},{};for k,v in pairs(base)do out[k]=v end
  local world,index
  function out.acceptPlugin(plugin,read)
   if pinned[plugin.name]==nil then return base.acceptPlugin(plugin,read)end
   if enabled[plugin.name] or J.encode(plugin.parameters)~=J.encode(pinned[plugin.name])then fail('Unreviewed or repeated plugin configuration: '..plugin.name)end
   -- Register the real enabled source as a build input. No plugin is disabled.
   if not read('js/plugins/'..plugin.name..'.js')then fail('Missing enabled plugin '..plugin.name)end
   enabled[plugin.name]=true;parameters[plugin.name]=plugin.parameters;return true
  end
  function out.standardUI(name)return enabled[name]or base.standardUI(name)end
  function out.loadData(read,data)
   for _,name in ipairs(names)do if not enabled[name]then fail('Required source plugin was disabled: '..name)end end
   local declarations,lock=base.loadData(read,data)
   index=data;world=deps['converter.visu_world'].new(data)
   deps['converter.visu_gameplay'].prepare(data,parameters)
   if config.displayLocale=='zh-CN'then
    local dictionary={}
    for _,kind in ipairs({'database','dialogue'})do
     local file=root..'/projects/visu-mz/locales/zh-CN-'..kind..'.json'
     for source,value in pairs(J.decode(assert(F.read(file))))do
      if dictionary[source]~=nil and dictionary[source]~=value then fail('Conflicting Chinese text: '..source)end
      dictionary[source]=value
     end
    end
    -- All note-based name references have already resolved to stable IDs.
    deps['converter.visu_locale'].apply(data,dictionary)
   end
   return declarations,lock
  end
  function out.script(text,kind)return world.script(text,kind)end
  function out.command(code,p,context)return world.command(code,p,context)end
  return out
 end
 return M
end
