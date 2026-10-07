-- Desktop-only fixed-entry deployment. The managed copy permits exact comparison
-- without rehashing the compiled artifact or trusting a user-edited receipt.
return function(deps)
 local files,json,diagnostic=deps['build.files'],deps['contracts.json'],deps['contracts.diagnostic']
 local M={}
 local function fail(code,reason,path)diagnostic.raise(code,reason,{file=path})end
 local function canonical(path)
  path=path:gsub('\\','/');local prefix=path:match('^%a:/') or path:match('^/')
  if not prefix or path:sub(1,2)=='//' then fail('E_DEPLOY_PATH','Expected an absolute local path',path)end
  local parts={};for part in path:sub(#prefix+1):gmatch('[^/]+')do
   if part=='..'then if #parts==0 then fail('E_DEPLOY_PATH','Path escapes its root',path)end;table.remove(parts)
   elseif part~='.'then parts[#parts+1]=part end
  end
  return prefix..table.concat(parts,'/')
 end
 local function samePath(a,b)return package.config:sub(1,1)=='\\' and a:lower()==b:lower() or a==b end
 local function read(path)
  local bytes,reason,code=files.read(path)
  if not bytes and code~=2 then fail('E_DEPLOY_READ',tostring(reason),path)end
  return bytes
 end
 function M.prepare(root,target,gameId)
  if type(target)~='string' or target:find('[%z\r\n]') or not target:lower():match('%.lua$')then
   fail('E_DEPLOY_PATH','--target requires a Lua file path',target)
  end
  local ok,lfs=pcall(require,'lfs');if not ok then fail('E_DEPLOY_PATH','Deployment requires LuaFileSystem')end
  root=canonical((root:match('^%a:[/\\]') or root:match('^[/\\]'))and root or lfs.currentdir()..'/'..root)
  target=canonical((target:match('^%a:[/\\]') or target:match('^[/\\]'))and target or root..'/'..target)
  if samePath(target,root..'/dist/'..gameId..'/levelScript.lua')then fail('E_DEPLOY_PATH','Target must differ from the build output',target)end
  -- Refuse links and missing parents; the CLI never creates an external directory.
  local prefix=target:match('^%a:/') or '/';local current=prefix
  local parts={};for part in target:sub(#prefix+1):gmatch('[^/]+')do parts[#parts+1]=part end
  for i,part in ipairs(parts)do
   current=current:gsub('/$','')..'/'..part;local mode=lfs.symlinkattributes(current,'mode')
   if i<#parts and mode~='directory' or i==#parts and mode and mode~='file'then
    fail('E_DEPLOY_PATH','Target parents must exist and no component may be a link',current)
   end
  end
  local plan={target=target,gameId=gameId,baselinePath=target..'.r2u-last.lua',receiptPath=target..'.r2u.json'}
  for _,path in ipairs({plan.baselinePath,plan.receiptPath})do
   local mode=lfs.symlinkattributes(path,'mode');if mode and mode~='file'then fail('E_DEPLOY_PATH','Managed sidecar must be a regular file',path)end
  end
  plan.previous,plan.baseline,plan.receiptBytes=read(target),read(plan.baselinePath),read(plan.receiptPath)
  if plan.receiptBytes then
   local parsed,record=pcall(json.decode,plan.receiptBytes)
   if not parsed or type(record)~='table' or record.kind~='r2u.deployment' or record.schemaVersion~=1
    or record.gameId~=gameId or type(record.target)~='string' or not samePath(record.target,target)
    or type(record.buildId)~='string' or #record.buildId~=64 or record.buildId:find('[^0-9a-f]')then
    fail('E_DEPLOY_RECEIPT','Invalid or foreign deployment receipt',plan.receiptPath)
   end
   if not plan.baseline or plan.previous~=plan.baseline then fail('E_DEPLOY_CHANGED','Target differs from the last deployed bytes; preserve the external edit before deploying',target)end
   plan.record=record
  elseif plan.previous or plan.baseline then
   fail('E_DEPLOY_UNMANAGED','Existing target or sidecar has no managed receipt; choose a new target',target)
  end
  return plan
 end
 function M.install(plan,source,identity)
  if type(source)~='string' or type(identity)~='table' or type(identity.buildId)~='string'
   or #identity.buildId~=64 or identity.buildId:find('[^0-9a-f]')then fail('E_DEPLOY_ARTIFACT','A compiled artifact identity is required')end
  local function item(path,bytes,previous)return{path=path,bytes=bytes,expected=previous,expectMissing=previous==nil}end
  local items,backup={},nil
  if plan.previous and plan.previous~=source then
   backup=plan.target..'.r2u-backup-'..plan.record.buildId..'.lua'
   local lfs=require('lfs');local mode=lfs.symlinkattributes(backup,'mode')
   if mode and mode~='file'then fail('E_DEPLOY_PATH','Backup must be a regular file',backup)end
   local previous=read(backup)
   if previous and previous~=plan.previous then fail('E_DEPLOY_CHANGED','An existing backup was modified',backup)end
   items[#items+1]=item(backup,plan.previous,previous)
  end
  local record={kind='r2u.deployment',schemaVersion=1,gameId=plan.gameId,target=plan.target,
   buildId=identity.buildId,sha256=identity.sha256,bytes=#source,backup=backup,
   copied=true,loaded='not_run',published=false,comparison='exact-bytes'}
  items[#items+1]=item(plan.baselinePath,source,plan.baseline)
  items[#items+1]=item(plan.receiptPath,json.encode(record)..'\n',plan.receiptBytes)
  items[#items+1]=item(plan.target,source,plan.previous)
  local notes=files.commit(items)
  return record,notes
 end
 return M
end
