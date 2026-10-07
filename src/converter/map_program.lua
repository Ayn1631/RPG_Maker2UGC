return function(deps)
 local Map,serialize=deps['runtime.world.map'],deps['build.serialize'];local M={}
 function M.compile(world)
  local catalog={kind='r2u.map-catalog',schemaVersion=1,maps={},tilesets={}};local cells,count=0,0
  for id,flags in pairs(world.tilesets or {})do catalog.tilesets[id]=flags end
  local mapSources={}
  for _,map in ipairs(world.maps)do
   -- Existing public parser performs the complete six-layer/flag validation here.
   Map.new(map)
   for _,flags in pairs(catalog.tilesets)do
    local variant={};for k,v in pairs(map)do variant[k]=v end;variant.flags=flags
    Map.new(variant)
   end
   assert(not catalog.maps[map.id],'Duplicate map in normalized world')
   catalog.maps[map.id]=map;cells=cells+map.width*map.height;count=count+1
   local key=string.format('%.0f',map.tilesetId or map.id)
   catalog.tilesets[key]=catalog.tilesets[key] or map.flags
   local view={};for k,v in pairs(map)do if k~='flags'then view[k]=v end end
   local literal=serialize.literal(view)
   mapSources[#mapSources+1]='['..string.format('%.0f',map.id)..']='..literal:sub(1,-2)..',["flags"]=tilesets['..serialize.literal(key)..']}'
  end
  local source="-- Offline validated maps and shared tileset flags. No runtime source preparation.\nreturn function(deps)\n local tilesets="..serialize.literal(catalog.tilesets).."\n return deps['runtime.world.map'].fromCompiledCatalog({kind='r2u.map-catalog',schemaVersion=1,tilesets=tilesets,maps={"..table.concat(mapSources,',').."}})\nend\n"
  return{kind='r2u.map-program',schemaVersion=1,moduleId='generated.map_program',dependencies={'runtime.world.map'},source=source,stats={maps=count,cells=cells,bytes=#source}}
 end
 return M
end
