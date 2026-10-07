-- Desktop configuration candidates only. Engine source and user configs are read-only.
return function(deps)
 local files,json,serialize=deps['build.files'],deps['contracts.json'],deps['build.serialize']
 local inspector,diagnostic=deps['converter.inspect'],deps['contracts.diagnostic']
 local M={}
 local function fail(code,reason,file)diagnostic.raise(code,reason,{file=file})end
 local function absolute(path,base)
  path=path:gsub('\\','/')
  if not path:match('^%a:/') and path:sub(1,1)~='/'then path=base:gsub('\\','/')..'/'..path end
  local prefix=path:match('^%a:/') or '/';local parts={}
  if path:sub(1,2)=='//'then fail('E_INIT_PATH','Use a local source directory',path)end
  for part in path:sub(#prefix+1):gmatch('[^/]+')do
   if part=='..'then if #parts==0 then fail('E_INIT_PATH','Path escapes its root',path)end;table.remove(parts)
   elseif part~='.'then parts[#parts+1]=part end
  end
  return prefix..table.concat(parts,'/')
 end
 local function read(path,optional)
  local bytes,reason,code=files.read(path)
  if not bytes and not(optional and code==2)then fail('E_INIT_SOURCE',tostring(reason),path)end
  return bytes
 end
 -- Inspect a source project and write setup guidance/config candidates without replacing existing user files.
 function M.create(root,options,bindings)
  local id=options.gameId
  if type(id)~='string' or #id>64 or not id:match('^[a-z][a-z0-9_-]*$') or id:match('^com[1-9]$') or id:match('^lpt[1-9]$')
   or ({con=true,prn=true,aux=true,nul=true})[id]then fail('E_CONFIG','--game-id requires a portable lowercase name')end
  if type(options.source)~='string' or options.source=='' or options.source:find('[%z\r\n]')then fail('E_INIT_PATH','--source requires an RPG Maker project directory')end
  local ok,lfs=pcall(require,'lfs');if not ok then fail('E_INIT_PATH','Configuration creation requires LuaFileSystem')end
  root=absolute(root,lfs.currentdir());local source=absolute(options.source,root)
  local outputRoot=root..'/projects/'..id
  local left,right=outputRoot,source
  if package.config:sub(1,1)=='\\'then left,right=left:lower(),right:lower()end
  local prefix=right..(right:sub(-1)=='/' and '' or '/')
  if left==right or left:sub(1,#prefix)==prefix then fail('E_INIT_PATH','Configuration output must be outside the source project',source)end
  local cores={mv=read(source..'/js/rpg_core.js',true),mz=read(source..'/js/rmmz_core.js',true)}
  local profile=options.profile;local known={['mv-turn']='mv',['mz-turn']='mz',['mz-tpb-active']='mz',['mz-tpb-wait']='mz'}
  if profile and not known[profile]then fail('E_CONFIG','Unknown --profile')end
  local engine=profile and known[profile]
  if not engine then
   if cores.mv and cores.mz then fail('E_INIT_PROFILE','Both MV and MZ cores exist; choose --profile',source)end
   engine=cores.mv and 'mv' or cores.mz and 'mz'
  end
  if not engine or not cores[engine]then fail('E_INIT_PROFILE','No matching RPG Maker MV/MZ core found',source)end
  local version=inspector.coreVersion(cores[engine])
  if not version then fail('E_SOURCE_VERSION','Core must contain one static RPGMAKER_VERSION literal',source)end
  local systemPath=source..'/data/System.json';local parsed,system=pcall(json.decode,read(systemPath))
  if not parsed or type(system)~='table' or json.is_array(system) or system==json.null then fail('E_INIT_SOURCE','Invalid System.json object',systemPath)end
  local detected='mv-turn'
  if engine=='mz'then
   detected=({[0]='mz-turn',[1]='mz-tpb-active',[2]='mz-tpb-wait'})[system.battleSystem]
   if not detected then fail('E_INIT_PROFILE','MZ System.battleSystem must be 0, 1 or 2',systemPath)end
  end
  if profile and profile~=detected then fail('E_INIT_PROFILE','Requested profile differs from System battle mode '..detected,systemPath)end
  local config={gameId=id,sourceRoot=source,engineProfile=detected,sourceVersion=version,
   worldPreview={presentation='rpg-maker',renderMode='platform',actors=true,
    containerTemplate=0,textTemplate=0,buttonTemplate=0,imageTemplate=0,cursorTemplate=0,whiteImageId=0,
    artTemplates={portrait=0,icon=0}},audioBindings={},assetBindings={},extensions={}}
  if bindings then
   if not bindings.worldPreview or bindings.worldPreview.presentation~='rpg-maker' or bindings.worldPreview.renderMode~='platform'then
    fail('E_INIT_BINDINGS','Binding project must use platform RPG Maker presentation')
   end
   for _,key in ipairs({'worldPreview','fontBindings','audioBindings','assetBindings'})do if bindings[key]~=nil then config[key]=bindings[key]end end
  end
  local directory=files.mkdirs(root,'projects/'..id);local name='project.lua';local n=0
  while lfs.symlinkattributes(directory..'/'..name,'mode') or lfs.symlinkattributes(directory..'/'..name..'.setup.md','mode')do
   n=n+1;if n>100 then fail('E_INIT_EXISTS','Too many existing candidates',directory)end
   name=n==1 and 'project.candidate.lua' or 'project.candidate-'..n..'.lua'
  end
  local lines={'-- Generated configuration candidate. Fill target bindings and run inspect before build.','return {'}
  for _,key in ipairs({'gameId','sourceRoot','engineProfile','sourceVersion','worldPreview','fontBindings','audioBindings','assetBindings','extensions'})do
   if config[key]~=nil then lines[#lines+1]='    '..key..' = '..serialize.literal(config[key])..','end
  end
  lines[#lines+1]='}';local relative='projects/'..id..'/'..name
  local guide='# 工程接入候选\n\n来源：`'..source..'`\n\n识别结果：`'..detected..'` / `'..version..'`。这是配置创建，不是转换或试玩通过。\n\n'
   ..(bindings and 'UI、字体、音频和资源绑定已从指定配置复制；核对目标模板与本工程资源对应关系。\n\n' or '将worldPreview中的0替换为目标容器、文字、按钮、图片、光标、白图和头像/图标模板ID。0不会被当作可运行绑定。\n\n')
   ..'1. 在extensions登记本工程需要的双端扩展。未知插件须适配。\n2. 填写audioBindings的BGM索引和assetBindings，或使用资源导出清单。\n3. 执行下面的inspect，修复定位诊断后build。\n4. 在模拟器导入单Lua并试玩；官方UGC另行接线和载入。\n\n```powershell\nlua tools/r2u.lua inspect --project '..relative..'\nlua tools/r2u.lua build --project '..relative..'\n```\n\n已有手写配置不会被覆盖；需要替换时由作者比较候选后处理。generated/dist目录在build阶段准备。\n'
  files.commit({{path=directory..'/'..name,bytes=table.concat(lines,'\n')..'\n',expectMissing=true},
   {path=directory..'/'..name..'.setup.md',bytes=guide,expectMissing=true}})
  local warning=diagnostic.new(bindings and 'W_INIT_REVIEW' or 'W_INIT_BINDINGS',
   bindings and 'Review copied template/resource bindings and register source extensions before inspect/build' or 'Fill zero template IDs with target bindings before inspect/build')
  warning.severity='warning'
  return {ok=true,command='init',stage='configuration-candidate',gameId=id,output=relative,setup=relative..'.setup.md',
   engineProfile=detected,sourceVersion=version,playable=false,publishable=false,bindingsReused=bindings~=nil,
   diagnostics=json.array({warning})}
 end
 return M
end
