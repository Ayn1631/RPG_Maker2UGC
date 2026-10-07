-- Selected checks and supplied trace comparison, never an implicit full test run.
return function(deps)
 local files,json,runner,D=deps['build.files'],deps['contracts.json'],deps['build.test_runner'],deps['contracts.diagnostic']
 local M={}
 local function fail(code,reason,file)D.raise(code,reason,{file=file})end
 local function read(path)
  local bytes,reason=files.read(path);if not bytes then fail('E_VERIFY_INPUT',tostring(reason),path)end;return bytes
 end
 local function normal(bytes)bytes=bytes:gsub('\r\n','\n'):gsub('\r','\n');return bytes:sub(-1)=='\n' and bytes or bytes..'\n'end
 local function environment()
  return {assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,type=type,tonumber=tonumber,tostring=tostring,
   select=select,math=math,string=string,table=table,utf8=utf8,setmetatable=setmetatable,getmetatable=getmetatable,
   rawequal=rawequal,rawget=rawget,rawset=rawset,pcall=pcall,xpcall=xpcall}
 end
 function M.run(root,config,options)
  root=root:gsub('/+$','')..'/'
  if not options.suite and not options.trace then fail('E_VERIFY_SCOPE','Select --suite or supply --trace; verify does not run every suite by default')end
  local base='dist/'..config.gameId..'/';local artifactPath=root..base..'levelScript.lua'
  local source=read(artifactPath);local recordBytes=read(root..base..'reports/build.json');local record=json.decode(recordBytes)
  if type(record.buildId)~='string' or #record.buildId~=64 or record.buildId:find('[^0-9a-f]') or record.gameId~=config.gameId or record.bytes~=#source then fail('E_VERIFY_ARTIFACT','Artifact does not match its build receipt',artifactPath)end
  local chunk,reason=load(source,'@'..artifactPath,'t',environment())
  if not chunk then fail('E_VERIFY_SYNTAX',tostring(reason),artifactPath)end
  local loaded,artifact=pcall(chunk)
  if not loaded then fail('E_VERIFY_ARTIFACT',type(artifact)=='table' and artifact.reason or tostring(artifact),artifactPath)end
  if type(artifact)~='table' or type(artifact.entry)~='table' or artifact.buildId~=record.buildId or type(artifact.package)~='table'
   or artifact.package.gameId~=config.gameId or artifact.package.engineProfile~=config.engineProfile then
   fail('E_VERIFY_ARTIFACT','Bundle identity/profile differs from the selected project or receipt',artifactPath)
  end
  local report={kind='r2u.verification',schemaVersion=1,command='verify',stage='selected-verification',ok=true,
   gameId=config.gameId,buildId=record.buildId,engineProfile=artifact.package.engineProfile,sourceVersion=artifact.package.sourceVersion,
   playable=false,publishable=false,artifactCheck='syntax-and-static-entry',scope='selected-source-tests-and-provided-traces',
   sourceProjectFreshness='not_checked',artifactSelection='existing-build',
   selection={suite=options.suite,case=options.case,trace=options.trace},inputCoverage='loader-dependency-closure-and-selected-test',
   nativePlaytest='not_run',simulatorPlaytest='not_run',ugcRuntime='not_run',diagnostics=json.array(),moduleChecks=json.array()}
  local snapshots={};local function capture(path)if snapshots[path]~=nil then return snapshots[path]end;local bytes=read(path);snapshots[path]=bytes;return bytes end
  for _,path in ipairs({'src/build/verify.lua','src/build/files.lua','src/contracts/json.lua','src/contracts/diagnostic.lua'})do capture(root..path)end
  capture(root..base..'reports/build.json');local mapBytes=capture(root..base..'reports/source-map.json')
  local mapping={};local lines={};for line in normal(source):gmatch('(.-)\n')do lines[#lines+1]=line end
  for _,row in ipairs(json.decode(mapBytes))do
   if type(row.moduleId)~='string' or mapping[row.moduleId] or not files.relative(row.path) or type(row.startLine)~='number'
    or type(row.endLine)~='number' or row.startLine%1~=0 or row.endLine%1~=0 or row.startLine<1
    or row.endLine<row.startLine or row.endLine>#lines then fail('E_VERIFY_MAP','Invalid source-map entry')end
   mapping[row.moduleId]=row
  end
  local function issue(err)
   report.ok=false;report.diagnostics[#report.diagnostics+1]=D.is(err) and err or D.new('E_VERIFY',tostring(err))
  end
  if options.suite then
   local definitions=assert(load(capture(root..'tools/module_manifest.lua'),'@manifest','t',{}))()
   local indexed={};for _,row in ipairs(definitions)do indexed[row.id]=row end
   capture(root..'tools/bootstrap.lua');capture(root..'tools/test_suites.lua');capture(root..'src/build/test_runner.lua')
   if not options.suite:match('^[a-z][a-z0-9_]*$')then fail('E_VERIFY_SUITE','Invalid suite name')end
   capture(root..'tests/test_'..options.suite..'.lua')
   local baseLoader=assert(loadfile(root..'tools/bootstrap.lua'))()(root);local checked={}
   local function inspect(id)
    if checked[id]then return end;checked[id]=true
    local definition=indexed[id];if not definition then fail('E_VERIFY_MODULE','Unknown source module '..id)end
    local path=definition.path or 'src/'..id:gsub('%.','/')..'.lua';local bytes=capture(root..path)
    local row=mapping[id];local status='source-only'
    if row then
     local body=table.concat(lines,'\n',row.startLine,row.endLine)..'\n'
     if row.path~=path or body~=normal(bytes)then
      report.moduleChecks[#report.moduleChecks+1]={moduleId=id,status='different',path=path}
      fail('E_VERIFY_STALE_SOURCE','Selected test module differs from the compiled artifact; build before verifying: '..id,root..path)
     end
     status='artifact-bytes-match'
    end
    report.moduleChecks[#report.moduleChecks+1]={moduleId=id,status=status,path=path}
    for _,dependency in ipairs(definition.dependencies or {})do inspect(dependency)end
   end
   local ok,result=pcall(runner.run,root,{suite=options.suite,filter=options.case},function(id)inspect(id);return baseLoader(id)end)
   if ok then
    report.tests=result;report.tests.cases=json.array(result.cases)
    if not result.ok then issue(D.new('E_VERIFY_TEST','Selected test cases failed or matched no cases'))end
   else issue(result)end
  end
  for _,row in ipairs(report.moduleChecks)do if row.status=='different'then issue(D.new('E_VERIFY_STALE_SOURCE','Compiled module differs from selected source: '..row.moduleId))end end
  if options.trace then
   local ok,result=pcall(function()
    local pairPath=(options.trace:match('^%a:[/\\]') or options.trace:match('^[/\\]'))and options.trace or root..options.trace
    local pair=json.decode(capture(pairPath));local parent=pairPath:gsub('\\','/'):match('^(.*)/') or '.'
    if pair.kind~='r2u.trace-pair' or pair.schemaVersion~=1 or not files.relative(pair.native) or not files.relative(pair.lua)then fail('E_VERIFY_TRACE','Invalid trace-pair contract',pairPath)end
    local nativePath,luaPath=files.join(parent,pair.native),files.join(parent,pair.lua)
    local a,b=json.decode(capture(nativePath)),json.decode(capture(luaPath))
    for _,side in ipairs({{a,'native'},{b,'lua'}})do local trace=side[1]
     if trace.kind~='r2u.trace' or trace.schemaVersion~=1 or trace.side~=side[2] or trace.buildId~=record.buildId
      or trace.engineProfile~=report.engineProfile or trace.sourceVersion~=report.sourceVersion or type(trace.caseId)~='string' or trace.caseId==''
      or not json.is_array(trace.records) or #trace.records==0 then fail('E_VERIFY_TRACE','Trace identity/profile/version or nonempty records invalid',pairPath)end
    end
    if a.caseId~=b.caseId or json.encode(a.records)~=json.encode(b.records)then fail('E_VERIFY_TRACE_DIFFERENCE','Native and Lua trace records differ',pairPath)end
    return {status='matched',caseId=a.caseId,native=nativePath,lua=luaPath,recordCount=#a.records,provenance='provided-files-not-executed-by-verify'}
   end)
   if ok then report.traceComparison=result else issue(result)end
  else report.traceComparison={status='not_run'}end
  if read(artifactPath)~=source then issue(D.new('E_VERIFY_INPUT_CHANGED','Compiled artifact changed during verification',{file=artifactPath}))end
  for path,bytes in pairs(snapshots)do if read(path)~=bytes then issue(D.new('E_VERIFY_INPUT_CHANGED','Verification input changed while tests ran',{file=path}))end end
  -- Bind the receipt to exact tested artifact bytes, without another SHA256 pass.
  local snapshotPath=base..'reports/verified-'..record.buildId..'.lua';local previous=files.read(root..snapshotPath)
  if previous and previous~=source then fail('E_VERIFY_ARTIFACT_CHANGED','Same buildId already has a different verified artifact snapshot',root..snapshotPath)end
  local index=1;while files.read(root..base..'reports/verify-'..index..'.json') or files.read(root..base..'reports/verify-'..index..'.inputs.json')do
   index=index+1;if index>10000 then fail('E_VERIFY_REPORT','Too many verification receipts')end
  end
  report.output=base..'reports/verify-'..index..'.json';report.inputs=base..'reports/verify-'..index..'.inputs.json';report.artifactSnapshot=snapshotPath
  local items={{path=root..report.inputs,bytes=json.encode(snapshots)..'\n',expectMissing=true},
   {path=root..report.output,bytes=json.encode(report)..'\n',expectMissing=true}}
  if not previous then table.insert(items,1,{path=root..snapshotPath,bytes=source,expectMissing=true})end
  files.commit(items)
  return report,report.ok and 0 or 1
 end
 return M
end
