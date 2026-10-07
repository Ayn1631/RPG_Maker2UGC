-- Check supplied, build-specific evidence. Never execute tests or publish a game.
return function(deps)
 local files,json,D=deps['build.files'],deps['contracts.json'],deps['contracts.diagnostic'];local M={}
 local function fail(code,reason,file)D.raise(code,reason,{file=file})end
 local function text(v)return type(v)=='string' and v~=''end
 -- Check supplied records against this build; the result validates consistency, not real gameplay or publication.
 function M.run(root,config,options)
  root=root:gsub('/+$','')..'/';local target=options.target or 'ugc'
  if target~='ugc' and target~='simulator'then fail('E_RELEASE_TARGET','--target must be simulator or ugc')end
  local cached={}
  local function bytes(path)
   if cached[path]~=nil then return cached[path]end
   local value,why=files.read(path);if not value then fail('E_RELEASE_INPUT',tostring(why),path)end
   cached[path]=value;return value
  end
  local function localFile(path)
   if not files.relative(path)then fail('E_RELEASE_PATH','Evidence paths must be workspace-relative and contained')end
   return root..path
  end
  local function object(path)local value=json.decode(bytes(path));if type(value)~='table' or value==json.null or json.is_array(value)then fail('E_RELEASE_SHAPE','Expected an evidence object',path)end;return value end
  local base='dist/'..config.gameId..'/';local artifact=bytes(root..base..'levelScript.lua');local build=object(root..base..'reports/build.json')
  if not text(build.buildId) or #build.buildId~=64 or build.buildId:find('[^0-9a-f]') or build.gameId~=config.gameId or build.bytes~=#artifact then
   fail('E_RELEASE_ARTIFACT','Build identity/byte length does not match artifact')
  end
  local report={kind='r2u.release-check',schemaVersion=1,command='release-check',stage='evidence-review',gameId=config.gameId,
   buildId=build.buildId,target=target,assessment='provided-evidence-consistency',saveScope='excluded',
   ok=true,ready=false,playable=false,publishable=false,published=false,gates=json.array(),diagnostics=json.array(),
   compilerDiagnostics=build.diagnostics or json.array()}
  local function gate(id,fn)
   local ok,result=pcall(fn)
   if ok then report.gates[#report.gates+1]={id=id,status=result and result.status or 'passed',evidence=result and result.evidence}
   else
    report.ok=false;local diagnostic=D.is(result) and result or D.new('E_RELEASE_EVIDENCE',tostring(result))
    diagnostic.gate=id;report.diagnostics[#report.diagnostics+1]=diagnostic
    report.gates[#report.gates+1]={id=id,status='not_passed',reason=diagnostic.reason}
   end
  end
  gate('build',function()
   if not json.is_array(build.diagnostics) or build.engineProfile~=config.engineProfile or not text(build.sourceVersion)then
    fail('E_RELEASE_METADATA','Build lacks current profile/version/diagnostic metadata; build once with the current compiler')
   end
   if build.artifactKind~='world-development-bundle'then fail('E_RELEASE_SCOPE','A game world bundle is required')end
   for _,field in ipairs({'lua53Syntax','eventCompile','rpgDataCompile','uiDataCompile','actorProgram','partyProgram'})do
    if not build.validation or build.validation[field]~='passed'then fail('E_RELEASE_BUILD','Missing compiled check: '..field)end
   end
   for _,d in ipairs(build.diagnostics)do
    if d.severity=='error' or d.code=='W_AUDIO_UNBOUND'then fail('E_RELEASE_BUILD','Unresolved compiler diagnostic: '..tostring(d.code))end
   end
   return{evidence=base..'reports/build.json'}
  end)
  local manifest;gate('evidence-manifest',function()
   if not options.evidence then fail('E_RELEASE_MISSING','Supply --evidence with the current build evidence manifest')end
   local path=(options.evidence:match('^%a:[/\\]') or options.evidence:match('^[/\\]'))and options.evidence or root..options.evidence
   manifest=object(path)
   if manifest.kind~='r2u.release-evidence' or manifest.schemaVersion~=1 or manifest.gameId~=config.gameId or manifest.buildId~=build.buildId
    or not json.is_array(manifest.verificationReports) or type(manifest.records)~='table' or json.is_array(manifest.records) then
    manifest=nil;fail('E_RELEASE_IDENTITY','Evidence manifest belongs to another build or has an invalid shape',path)
   end
   return{evidence=options.evidence}
  end)
  local artifactLines={};for line in (artifact:sub(-1)=='\n' and artifact or artifact..'\n'):gmatch('(.-)\n')do artifactLines[#artifactLines+1]=line end
  local function normalized(value)value=value:gsub('\r\n','\n'):gsub('\r','\n');return value:sub(-1)=='\n' and value or value..'\n'end
  gate('verification',function()
   if not manifest or #manifest.verificationReports==0 then fail('E_RELEASE_MISSING','No selected verification receipt was supplied')end
   local matched=0
   for _,path in ipairs(manifest.verificationReports)do
    local v=object(localFile(path))
    if v.kind~='r2u.verification' or v.schemaVersion~=1 or v.gameId~=config.gameId or v.buildId~=build.buildId
     or v.engineProfile~=config.engineProfile or v.ok~=true or not v.tests or v.tests.ok~=true
     or type(v.tests.passed)~='number' or v.tests.passed<1 or v.tests.passed%1~=0 or v.tests.failed~=0
     or not json.is_array(v.tests.cases) or #v.tests.cases~=v.tests.passed or not json.is_array(v.diagnostics) or #v.diagnostics~=0 then
     fail('E_RELEASE_VERIFICATION','Verification must contain passing selected tests for this build',path)
    end
    if bytes(localFile(v.artifactSnapshot))~=artifact then fail('E_RELEASE_STALE','Verification snapshot differs from current Lua',path)end
    local inputs=object(localFile(v.inputs));if next(inputs)==nil then fail('E_RELEASE_VERIFICATION','Verification source snapshots are missing',path)end
    for _,case in ipairs(v.tests.cases)do if case.ok~=true or not text(case.name)then fail('E_RELEASE_VERIFICATION','Verification case did not pass',path)end end
    local function input(relative)
     local found;for key,value in pairs(inputs)do if key==relative or key:sub(-#relative-1)=='/'..relative then
      if found or type(value)~='string'then fail('E_RELEASE_VERIFICATION','Ambiguous source snapshot',path)end;found=value
     end end
     if not found then fail('E_RELEASE_VERIFICATION','Missing source snapshot: '..relative,path)end;return found
    end
    local sourceMapPath=base..'reports/source-map.json'
    if input(sourceMapPath)~=bytes(root..sourceMapPath)then fail('E_RELEASE_STALE','Verified source map differs from current build',path)end
    local map={};for _,span in ipairs(json.decode(input(sourceMapPath)))do
     if type(span.moduleId)~='string' or map[span.moduleId] or not files.relative(span.path) or type(span.startLine)~='number'
      or type(span.endLine)~='number' or span.startLine%1~=0 or span.endLine%1~=0 or span.startLine<1
      or span.endLine<span.startLine or span.endLine>#artifactLines then fail('E_RELEASE_VERIFICATION','Invalid source-map range',path)end
     map[span.moduleId]=span
    end
    if not json.is_array(v.moduleChecks)then fail('E_RELEASE_VERIFICATION','Verification module scope missing',path)end
    for _,row in ipairs(v.moduleChecks)do
     if row.status=='different'then fail('E_RELEASE_STALE','Verification includes a mismatched runtime module',path)end
     if row.status=='artifact-bytes-match'then
      local span=map[row.moduleId]
      if not span or span.path~=row.path or table.concat(artifactLines,'\n',span.startLine,span.endLine)..'\n'~=normalized(input(row.path))then
       fail('E_RELEASE_STALE','Recorded test source differs from artifact module: '..tostring(row.moduleId),path)
      end
      matched=matched+1
     end
    end
   end
   if matched==0 then fail('E_RELEASE_VERIFICATION','Source-only checks do not verify this compiled runtime')end
   return{evidence=manifest.verificationReports}
  end)
  local function acceptance(id,required)
   gate(id,function()
    local path=manifest and manifest.records[id];if not path then fail('E_RELEASE_MISSING','Missing '..id..' acceptance record')end
    local record=object(localFile(path))
    if record.kind~='r2u.acceptance-record' or record.schemaVersion~=1 or record.gate~=id or record.gameId~=config.gameId
     or record.buildId~=build.buildId or record.engineProfile~=config.engineProfile or record.status~='passed'
     or not text(record.environment) or not json.is_array(record.cases)then fail('E_RELEASE_ACCEPTANCE','Acceptance identity, status or execution context invalid',path)end
    if bytes(localFile(record.artifactSnapshot))~=artifact then fail('E_RELEASE_STALE','Acceptance snapshot differs from current Lua',path)end
    if id=='native' and (record.runtime~='native' or record.sourceVersion~=build.sourceVersion)then fail('E_RELEASE_STALE','Native engine version differs',path)end
    if (id=='simulation' and record.runtime~='simulator') or (id=='ugc' and record.runtime~='ugc')then fail('E_RELEASE_ACCEPTANCE','Execution runtime differs from required target',path)end
    if id=='performance' and record.runtime~=target then fail('E_RELEASE_ACCEPTANCE','Performance evidence is for a different target',path)end
    if id=='extensions' and json.encode(record.extensionsLock)~=json.encode(build.extensionsLock)then fail('E_RELEASE_STALE','Extension lock changed',path)end
    local cases={}
    for _,case in ipairs(record.cases)do
     if not text(case.id) or cases[case.id] or case.status~='passed' or not text(case.observation)
      or not json.is_array(case.artifacts) or #case.artifacts==0 then fail('E_RELEASE_CASE','Cases require unique IDs, actual observations and supporting files',path)end
     for _,file in ipairs(case.artifacts)do if #bytes(localFile(file))==0 then fail('E_RELEASE_CASE','Supporting file is empty',file)end end
     if id=='resources' and case.id=='audio-index'then
      local c=case.contract
      if type(c)~='table' or c.parameter~='index' or c.type~='int' or c.position~=1 then fail('E_RELEASE_AUDIO','BGM contract requires first integer parameter named index',path)end
     end
     if id=='performance'then
      local actual,limits=case.measurements,case.limits
      local function count(v)return type(v)=='number' and v==v and v%1==0 and v>=0 and v<=9007199254740991 end
      if type(actual)~='table' or type(limits)~='table' or not count(actual.samples) or actual.samples<1 then fail('E_RELEASE_PERFORMANCE','Performance requires measured samples and limits',path)end
      for _,key in ipairs({'widgetUpdates','widgetCreates'})do
       if not count(actual[key]) or not count(limits[key]) or actual[key]>limits[key]then fail('E_RELEASE_PERFORMANCE','Widget measurement exceeds or lacks its declared limit: '..key,path)end
      end
     end
     cases[case.id]=true
    end
    for _,name in ipairs(required)do if not cases[name]then fail('E_RELEASE_COVERAGE','Missing required acceptance case: '..id..'/'..name,path)end end
    return{evidence=path}
   end)
   report.gates[#report.gates].requiredCases=json.array(required)
  end
  local compatibility={'world','events','actors','inventory','ui'}
  if build.battleInitialization=='precompiled'then compatibility[#compatibility+1]='battle'end
  acceptance('compatibility',compatibility)
  local resources={'bindings','audio-index','replacements'};if target=='ugc'then resources[#resources+1]='licenses'end
  acceptance('resources',resources)
  if build.extensionsLock and #build.extensionsLock>0 then
   local cases={};for _,extension in ipairs(build.extensionsLock)do cases[#cases+1]=extension.id..':lua';cases[#cases+1]=extension.id..':native'end
   acceptance('extensions',cases)
  else report.gates[#report.gates+1]={id='extensions',status='not_applicable',reason='Build has no enabled extensions'}end
  acceptance('native',{'playtest'})
  acceptance('simulation',{'startup','core-loop','ui','restart'})
  local performance={'idle-writes','interaction-writes','scene-reuse'};if target=='ugc'then performance[#performance+1]='target-device'end
  acceptance('performance',performance)
  if target=='ugc'then acceptance('ugc',{'load-build-id','input','ui-templates','audio-signals'})end
  gate('evidence-stability',function()
   for path,old in pairs(cached)do if files.read(path)~=old then fail('E_RELEASE_CHANGED','Evidence changed during assessment',path)end end
  end)
  report.ready=report.ok;report.playable=report.ready;report.publishable=report.ready and target=='ugc'
  report.output=base..'reports/release-check-'..target..'.json'
  files.commit({{path=root..report.output,bytes=json.encode(report)..'\n'}})
  return report,report.ok and 0 or 1
 end
 return M
end
