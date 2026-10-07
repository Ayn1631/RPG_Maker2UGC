-- Regenerate native command metadata from the registered schema and author JS behavior.
local root=(arg[0]:gsub('\\','/'):match('^(.*)/tools/') or '.')..'/'
local loadModule=assert(loadfile(root..'tools/bootstrap.lua'))()(root)
local J=loadModule('contracts.json');local S=loadModule('sdk.schema');local F=loadModule('build.files')
local dir=assert(arg[1],'Usage: texlua tools/sdk-native.lua extensions/sample.quest')
local manifest=J.decode(assert(F.read(dir..'/extension.json')))
local schema=J.decode(assert(F.read(dir..'/'..manifest.schema)))
for _,kind in ipairs({'data','state','config'})do S.validate(schema[kind])end
local lines={'/*:', ' * @target MZ', ' * @plugindesc R2U '..manifest.id..' '..manifest.version..' (MV/MZ)', ' * @help Shared data: data/r2u/'..manifest.id..'/'..manifest.dataFile}
local names={};for name in pairs(schema.commands)do names[#names+1]=name end;table.sort(names)
for _,name in ipairs(names)do
 local cmd=schema.commands[name];S.validate(cmd.args)
 lines[#lines+1]=' * @command '..name;lines[#lines+1]=' * @text '..name
 for _,key in ipairs(cmd.order)do
  local spec=cmd.args.properties[key];local kind=spec.type
  lines[#lines+1]=' * @arg '..key;lines[#lines+1]=' * @type '..((kind=='integer' or kind=='number')and 'number' or kind=='boolean' and 'boolean' or 'string')
  if spec.default~=nil then lines[#lines+1]=' * @default '..tostring(spec.default)end
 end
end
lines[#lines+1]=' */';lines[#lines+1]='(function() {';lines[#lines+1]='const CONTRACT = '..J.encode(schema)..';'
local policies=J.object();local Policy=loadModule('sdk.policy')
for _,p in ipairs(Policy.declarations(schema.policies))do policies[p.name]=Policy.contract(p.name)end
lines[#lines+1]='const POLICIES = '..J.encode(policies)..';'
lines[#lines+1]='const EXTENSION = '..J.encode({id=manifest.id,plugin=manifest.plugin,version=manifest.version,contractVersion=manifest.contractVersion,stateSchemaVersion=manifest.stateSchemaVersion,dataFile=manifest.dataFile})..';'
lines[#lines+1]=assert(F.read(dir..'/preview/behavior.js'))
lines[#lines+1]='})();'
local bytes=table.concat(lines,'\n')..'\n';local seen={};local items={}
for _,path in pairs(manifest.preview)do if not seen[path]then seen[path]=true;items[#items+1]={path=dir..'/'..path,bytes=bytes}end end
F.commit(items);print('Generated native adapters from schema for '..manifest.id)
