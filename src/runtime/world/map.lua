-- Pure map queries over six-layer compiled data, with injected event/collision services.
return function(deps)
  local M={}
  local limit=9007199254740991
  local function integer(v) return type(v)=="number" and v==v and v>=-limit and v<=limit and v%1==0 end
  local function fail(code,reason) error({severity="error",code=code,reason=reason},0) end
  local function direction(d)
    if d~=2 and d~=4 and d~=6 and d~=8 then fail("E_WORLD_ARGUMENT","Direction must be 2, 4, 6 or 8") end
  end
  local function new(def,options,prepared,overrideFlags)
    if type(def)~="table" or not integer(def.id) or def.id<1 or
      not integer(def.width) or def.width<1 or not integer(def.height) or def.height<1 or
      not integer(def.scrollType) or def.scrollType<0 or def.scrollType>3 then
      fail("E_WORLD_MAP","Invalid map id, dimensions or scroll type")
    end
    local width,height=def.width,def.height
    if width>1000000//6 or height>(1000000//6)//width then fail("E_WORLD_MAP","Map exceeds six-layer cell limit") end
    if type(def.tiles)~="table" or type(def.flags)~="table" then fail("E_WORLD_MAP","Map requires tiles and flags") end
    options=options==nil and {} or options
    if type(options)~="table" then fail("E_WORLD_MAP","Map options must be a table") end
    for _,name in ipairs({"tileEventsAt","blocked"}) do
      if options[name]~=nil and type(options[name])~="function" then fail("E_WORLD_MAP","Invalid "..name.." service") end
    end
    local tileEventsAt,blocked=options.tileEventsAt,options.blocked
    local size=6*width*height
    local tiles,flags=prepared and def.tiles or {},prepared and (overrideFlags or def.flags) or {}
    if not prepared then
    for key,value in pairs(def.tiles) do
      if not integer(key) or key<1 or key>size then fail("E_WORLD_MAP","Tiles must be a consecutive six-layer array") end
      if not integer(value) or value<0 then fail("E_WORLD_MAP","Tile values must be nonnegative integers") end
      tiles[key]=value
    end
    for key,value in pairs(def.flags) do
      if not integer(key) or key<1 or not integer(value) or value<0 then fail("E_WORLD_MAP","Invalid tileset flag entry") end
      flags[key]=value
    end
    for index=1,size do
      if tiles[index]==nil then fail("E_WORLD_MAP","Missing six-layer tile entry") end
      -- Shadow bits and region IDs are data, not tile IDs in the tileset.
      if index<=4*width*height and flags[tiles[index]+1]==nil then fail("E_WORLD_MAP","Missing flag for tile "..tiles[index]) end
    end
    end
    local loopX=def.scrollType==2 or def.scrollType==3
    local loopY=def.scrollType==1 or def.scrollType==3
    local S={}
    function S.normalize(x,y)
      if not integer(x) or not integer(y) then fail("E_WORLD_ARGUMENT","Coordinates must be safe integers") end
      if loopX then x=x%width end
      if loopY then y=y%height end
      return x,y,x>=0 and x<width and y>=0 and y<height
    end
    function S.step(x,y,d)
      direction(d); x,y=S.normalize(x,y)
      if d==6 then x=x+1 elseif d==4 then x=x-1 elseif d==2 then y=y+1 else y=y-1 end
      return S.normalize(x,y)
    end
    function S.tile(x,y,z)
      if not integer(z) or z<0 or z>5 then fail("E_WORLD_ARGUMENT","Layer must be 0 through 5") end
      local valid; x,y,valid=S.normalize(x,y)
      if not valid then return 0 end
      return tiles[(z*height+y)*width+x+1]
    end
    function S.layeredTiles(x,y)
      local out={}
      for z=3,0,-1 do out[#out+1]=S.tile(x,y,z) end
      return out
    end
    local function service(fn,...)
      local ok,value=pcall(fn,...)
      if not ok then fail("E_WORLD_SERVICE","Map service failed") end
      return value
    end
    local function flagFor(tileId,code)
      if not integer(tileId) or tileId<0 or flags[tileId+1]==nil then fail(code,"Missing or invalid tile event flag") end
      return flags[tileId+1]
    end
    function S.checkPassage(x,y,mask)
      if not integer(mask) or mask<1 then fail("E_WORLD_ARGUMENT","Passage mask must be a positive integer") end
      local valid; x,y,valid=S.normalize(x,y)
      if not valid then return false end
      local all={}
      if tileEventsAt then
        local events=service(tileEventsAt,x,y)
        if type(events)~="table" then fail("E_WORLD_SERVICE","Tile events service must return an array") end
        local count=0
        for key,id in pairs(events) do
          if not integer(key) or key<1 then fail("E_WORLD_SERVICE","Tile events must be a consecutive array") end
          flagFor(id,"E_WORLD_SERVICE"); count=count+1
        end
        for index=1,count do
          if events[index]==nil then fail("E_WORLD_SERVICE","Tile events must be a consecutive array") end
          all[#all+1]=events[index]
        end
      end
      for z=3,0,-1 do all[#all+1]=tiles[(z*height+y)*width+x+1] end
      for _,id in ipairs(all) do
        local flag=flags[id+1]
        if flag&0x10==0 then
          local passage=flag&mask
          if passage==0 then return true end
          if passage==mask then return false end
        end
      end
      return false
    end
    function S.isPassable(x,y,d)
      direction(d); return S.checkPassage(x,y,1 << (d//2-1))
    end
    local function actorOptions(actor)
      if actor==nil then return false end
      if type(actor)~="table" then fail("E_WORLD_ARGUMENT","Actor must be a table") end
      for _,key in ipairs({"through","debugThrough"}) do
        if actor[key]~=nil and type(actor[key])~="boolean" then fail("E_WORLD_ARGUMENT","Actor "..key.." must be boolean") end
      end
      return actor.through==true or actor.debugThrough==true
    end
    function S.canPass(x,y,d,actor)
      local nx,ny,valid=S.step(x,y,d)
      if not valid then return false end
      local through=actorOptions(actor)
      if through then return true end
      if not S.isPassable(x,y,d) or not S.isPassable(nx,ny,10-d) then return false end
      if blocked then
        local collision=service(blocked,nx,ny,actor)
        if type(collision)~="boolean" then fail("E_WORLD_SERVICE","Collision service must return boolean") end
        return not collision
      end
      return true
    end
    function S.canPassDiagonally(x,y,horizontal,vertical,actor)
      if horizontal~=4 and horizontal~=6 or vertical~=2 and vertical~=8 then fail("E_WORLD_ARGUMENT","Invalid diagonal directions") end
      local nx=S.step(x,y,horizontal)
      local _,ny=S.step(x,y,vertical)
      return S.canPass(x,y,vertical,actor) and S.canPass(x,ny,horizontal,actor)
        or S.canPass(x,y,horizontal,actor) and S.canPass(nx,y,vertical,actor)
    end
    function S.regionId(x,y) return S.tile(x,y,5) end
    function S.shadowBits(x,y) return S.tile(x,y,4) end
    function S.terrainTag(x,y)
      local valid; x,y,valid=S.normalize(x,y)
      if not valid then return 0 end
      for _,id in ipairs(S.layeredTiles(x,y)) do local tag=flags[id+1] >> 12; if tag>0 then return tag end end
      return 0
    end
    local function special(x,y,mask)
      local valid; x,y,valid=S.normalize(x,y)
      if not valid then return false end
      for _,id in ipairs(S.layeredTiles(x,y)) do if flags[id+1]&mask~=0 then return true end end
      return false
    end
    function S.isLadder(x,y) return special(x,y,0x20) end
    function S.isBush(x,y) return special(x,y,0x40) end
    function S.isCounter(x,y) return special(x,y,0x80) end
    function S.isDamageFloor(x,y) return special(x,y,0x100) end
    function S.isBoatPassable(x,y) return S.checkPassage(x,y,0x200) end
    function S.isShipPassable(x,y) return S.checkPassage(x,y,0x400) end
    function S.isAirshipLandOk(x,y) return S.checkPassage(x,y,0x800) and S.checkPassage(x,y,0x0f) end
    function S.distance(x1,y1,x2,y2)
      x1,y1=S.normalize(x1,y1); x2,y2=S.normalize(x2,y2)
      local dx,dy=math.abs(x1-x2),math.abs(y1-y2)
      if loopX then dx=math.min(dx,width-dx) end
      if loopY then dy=math.min(dy,height-dy) end
      return dx+dy
    end
    return S
  end
  function M.new(def,options)return new(def,options,false)end
  function M.fromCompiledCatalog(catalog)
    if type(catalog)~='table' or catalog.kind~='r2u.map-catalog' or catalog.schemaVersion~=1 then fail('E_WORLD_MAP_PROGRAM','Invalid map catalog')end
    local maps=catalog.maps
    return {kind='r2u.map-program',schemaVersion=1,
      get=function(id)return maps[id]end,
      getTileset=function(id)return(catalog.tilesets or {})[string.format('%.0f',id)]end,
      newMap=function(id,options,tilesetId)
        local def=maps[id];if not def then fail('E_WORLD_MAP_PROGRAM','Unknown compiled map')end
        local flags=tilesetId and (catalog.tilesets or {})[string.format('%.0f',tilesetId)]
        if tilesetId and not flags then fail('E_WORLD_MAP_PROGRAM','Unknown compiled tileset')end
        return new(def,options,true,flags)
      end}
  end
  return M
end
