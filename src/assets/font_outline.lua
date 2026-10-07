-- Offline unhinted TrueType outlines; never execute glyph instructions.
return function(deps)
 local S=deps['assets.font_sfnt'];local M={};local SAFE=9007199254740991
 local caps={depth=32,components=1024,points=262144,contours=8192,instructionBytes=1048576,work=8388608}
 local function fail(code,reason)error({severity='error',code=code,reason=reason},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_FONT_OUTLINE_SHAPE','Expected plain outline options')end end
 local function integer(v,lo,hi,code)if type(v)~='number'or v~=v or v%1~=0 or v<lo or v>hi then fail(code or 'E_FONT_OUTLINE_SHAPE','Integer outside outline bounds')end;return v*1.0 end
 local function open(provider,options)
  if options==nil then options={}end;plain(options);for k in next,options do if k~='sfntLimits'and k~='limits'then fail('E_FONT_OUTLINE_SHAPE','Unknown outline option')end end
  local supplied=rawget(options,'limits');if supplied==nil then supplied={}end;plain(supplied);for k in next,supplied do if not caps[k]then fail('E_FONT_OUTLINE_SHAPE','Unknown outline limit')end end
  local limits={};for k,v in pairs(caps)do limits[k]=rawget(supplied,k)~=nil and integer(rawget(supplied,k),1,v)or v end
  local sfnt=provider(rawget(options,'sfntLimits'))
  local function bad(code,reason,tag,p)sfnt.bad(code,reason,sfnt.locations[tag]and sfnt.locations[tag]+1 or 1,p)end
  local h16,h32=sfnt.tableReader('head',54);if h32(1)~=65536 or h32(13)~=1594834165 or h16(53)~=0 then bad('E_FONT_OUTLINE_HEAD','Invalid head outline header','head',1)end
  local units,format=h16(19),h16(51);if units<16 or units>16384 or format~=0 and format~=1 then bad('E_FONT_OUTLINE_HEAD','Invalid units or loca format','head',19)end
  local m16,m32=sfnt.tableReader('maxp',32);local n=m16(5);if m32(1)~=65536 or n<1 then bad('E_FONT_OUTLINE_HEAD','Invalid maxp outline header','maxp',1)end
  if n>sfnt.cap.glyphs then bad('E_FONT_OUTLINE_BUDGET','Glyph count exceeds container limit','maxp',5)end
  local l16,l32=sfnt.tableReader('loca',(n+1.0)*(format==0 and 2 or 4));sfnt.tableReader('glyf',0);local offsets={};local previous=0.0
  for id=0,n do sfnt.charge(1);local v=format==0 and l16(id*2.0+1)*2.0 or l32(id*4.0+1);if v<previous or v>#sfnt.tables.glyf then bad('E_FONT_OUTLINE_LOCA','Invalid glyph location sequence','loca',id*(format==0 and 2 or 4)+1)end;offsets[id+1]=v;previous=v end
  local F={unitsPerEm=units,numGlyphs=n}
  function F.glyph(glyphId)
   glyphId=integer(glyphId,0,n-1,'E_FONT_OUTLINE_REFERENCE');local used={depth=0,components=0,points=0,contours=0,instructionBytes=0,work=0};local stack={};local instructionRecords={}
   local function reserve(key,amount,id,p)
    used[key]=used[key]+amount;if used[key]>limits[key]then bad('E_FONT_OUTLINE_BUDGET','Outline '..key..' budget exceeded','glyf',offsets[id+1]+(p or 1))end
   end
   local function work(amount,id,p)reserve('work',amount,id,p);sfnt.charge(amount)end
   local function safe(v,id,p)if v~=v or v< -SAFE or v>SAFE then bad('E_FONT_OUTLINE_BOUNDS','Outline arithmetic exceeds safe53 finite domain','glyf',offsets[id+1]+p)end;return v*1.0 end
   local function decode(id,depth)
    if depth>limits.depth then bad('E_FONT_OUTLINE_BUDGET','Outline depth budget exceeded','glyf',offsets[id+1]+1)end
    if stack[id]then bad('E_FONT_OUTLINE_CYCLE','Cyclic compound glyph reference','glyf',offsets[id+1]+1)end
    stack[id]=true;work(1,id,1)
    local off,last=offsets[id+1],offsets[id+2];local g={kind='r2u.font-outline',schemaVersion=1,glyphId=id,unitsPerEm=units,sourceKind='empty',contours={},pointCount=0,components={},instructions={own={},components={}},hintingApplied=false,instructionsExecuted=false}
    if off==last then stack[id]=nil;return g end
    local data=sfnt.tables.glyf:sub(off+1,last);local u16,u32,i16,bounds=sfnt.reader(data,sfnt.locations.glyf,off);bounds(1,10)
    local count=i16(1);g.declaredBounds={xMin=i16(3),yMin=i16(5),xMax=i16(7),yMax=i16(9)}
    if g.declaredBounds.xMin>g.declaredBounds.xMax or g.declaredBounds.yMin>g.declaredBounds.yMax then bad('E_FONT_OUTLINE_GLYF','Reversed glyph bounding box','glyf',off+3)end
    local p=11.0
    local function instructions()
     local length=u16(p);p=p+2.0;bounds(p,length);reserve('instructionBytes',length,id,p);work(length,id,p);local out={};for at=p,p+length-1 do out[#out+1]=data:byte(at)end;p=p+length
     g.instructions.own=out;instructionRecords[#instructionRecords+1]={glyphId=id,bytes=out,depth=depth}
    end
    if count>=0 then
     g.sourceKind='simple';reserve('contours',count,id,p);work(count,id,p);local ends={};local old=-1.0
     for c=1,count do local ending=u16(p);p=p+2.0;if ending<=old then bad('E_FONT_OUTLINE_GLYF','Contour endpoints must increase','glyf',off+p-2)end;ends[c]=ending;old=ending end
     local points=count>0 and ends[count]+1.0 or 0.0;reserve('points',points,id,p)
     if count>0 or p<=#data then instructions()end
     local flags={};while #flags<points do bounds(p,1);local flag=data:byte(p);p=p+1.0;work(1,id,p-1)
      if flag&128~=0 then bad('E_FONT_OUTLINE_GLYF','Reserved simple glyph flag','glyf',off+p-1)end
      local repeats=0.0;if flag&8~=0 then bounds(p,1);repeats=data:byte(p);p=p+1.0 end
      if #flags+repeats+1>points then bad('E_FONT_OUTLINE_GLYF','Repeated flags exceed contour point count','glyf',off+p)end
      for _=0,repeats do flags[#flags+1]=flag;work(1,id,p)end
     end
     local xs,ys={},{};for axis,list in ipairs({xs,ys})do local value=0.0;local short=axis==1 and 2 or 4;local same=axis==1 and 16 or 32
      for i,flag in ipairs(flags)do local delta=0.0;if flag&short~=0 then bounds(p,1);delta=data:byte(p)*1.0;p=p+1.0;if flag&same==0 then delta=-delta end elseif flag&same==0 then delta=i16(p);p=p+2.0 end;value=safe(value+delta,id,p);list[i]=value;work(1,id,p)end
     end
     local first=1;for _,ending in ipairs(ends)do local contour={points={}};for i=first,ending+1 do contour.points[#contour.points+1]={x=xs[i],y=ys[i],onCurve=flags[i]&1~=0}end;g.contours[#g.contours+1]=contour;first=ending+2 end;g.pointCount=points
    else
     g.sourceKind='compound';local more=true;local hasInstructions=false;local parentPoints={}
     while more do
      reserve('components',1,id,p);work(1,id,p);local flags,childId=u16(p),u16(p+2);p=p+4.0
      if flags&0xe010~=0 or flags&0x1800==0x1800 then bad('E_FONT_OUTLINE_GLYF','Reserved or conflicting component flags','glyf',off+p-4)end
      if childId>=n then bad('E_FONT_OUTLINE_REFERENCE','Component references missing glyph','glyf',off+p-2)end
      local xy=flags&2~=0;local a,b
      if flags&1~=0 then a=xy and i16(p)or u16(p);b=xy and i16(p+2)or u16(p+2);p=p+4.0
      else bounds(p,2);a,b=data:byte(p,p+1);if xy then if a>=128 then a=a-256 end;if b>=128 then b=b-256 end end;p=p+2.0 end
      if #g.components==0 and not xy then bad('E_FONT_OUTLINE_GLYF','First component must use XY placement','glyf',off+p)end
      local transformCount=(flags&8~=0 and 1 or 0)+(flags&64~=0 and 1 or 0)+(flags&128~=0 and 1 or 0)
      if transformCount>1 then bad('E_FONT_OUTLINE_GLYF','Conflicting component transformations','glyf',off+p)end
      local xx,xyScale,yx,yy=1.0,0.0,0.0,1.0
      if flags&8~=0 then xx=i16(p)/16384.0;yy=xx;p=p+2.0
      elseif flags&64~=0 then xx=i16(p)/16384.0;yy=i16(p+2)/16384.0;p=p+4.0
      elseif flags&128~=0 then xx=i16(p)/16384.0;xyScale=i16(p+2)/16384.0;yx=i16(p+4)/16384.0;yy=i16(p+6)/16384.0;p=p+8.0 end
      local child=decode(childId,depth+1);reserve('points',child.pointCount,id,p);reserve('contours',#child.contours,id,p)
      local transformed={};for contourIndex,contour in ipairs(child.contours)do local out={points={}};for _,point in ipairs(contour.points)do
       local x=safe(safe(xx*point.x,id,p)+safe(yx*point.y,id,p),id,p);local y=safe(safe(xyScale*point.x,id,p)+safe(yy*point.y,id,p),id,p)
       local q={x=x,y=y,onCurve=point.onCurve};out.points[#out.points+1]=q;transformed[#transformed+1]=q;work(1,id,p)
      end;child.contours[contourIndex]=out end
      local dx,dy=a*1.0,b*1.0
      if xy then if flags&0x0800~=0 then dx=safe(xx*a+yx*b,id,p);dy=safe(xyScale*a+yy*b,id,p)end
      else
       local parentPoint=parentPoints[a+1]
       local childPoint=transformed[b+1]
       if not parentPoint or not childPoint then
        if not parentPoint and a>=g.pointCount and a<g.pointCount+4 or not childPoint and b>=child.pointCount and b<child.pointCount+4 then bad('E_FONT_OUTLINE_UNSUPPORTED','Phantom-point attachment requires metrics and grid-fitting rules','glyf',off+p)end
        bad('E_FONT_OUTLINE_REFERENCE','Attachment point outside contours','glyf',off+p)
       end;dx=safe(parentPoint.x-childPoint.x,id,p);dy=safe(parentPoint.y-childPoint.y,id,p)
      end
      for _,c in ipairs(child.contours)do for _,point in ipairs(c.points)do point.x=safe(point.x+dx,id,p);point.y=safe(point.y+dy,id,p);parentPoints[#parentPoints+1]=point;work(1,id,p)end;g.contours[#g.contours+1]=c end
      g.pointCount=g.pointCount+child.pointCount
      g.components[#g.components+1]={glyphId=childId,flags=flags,argument1=a,argument2=b,argsAreXY=xy,transform={xx=xx,xy=xyScale,yx=yx,yy=yy},offset={x=dx,y=dy},roundXYToGrid=xy and flags&4~=0,useMyMetrics=flags&512~=0,overlap=flags&1024~=0}
      more=flags&32~=0;hasInstructions=hasInstructions or flags&256~=0
     end
     if hasInstructions then instructions()end
    end
    if p<=#data then work(#data-p+1,id,p);for at=p,#data do if data:byte(at)~=0 then bad('E_FONT_OUTLINE_GLYF','Unexpected trailing glyph data','glyf',off+at)end end end
    local bbox;for _,contour in ipairs(g.contours)do for _,q in ipairs(contour.points)do work(1,id,p);if not bbox then bbox={xMin=q.x,yMin=q.y,xMax=q.x,yMax=q.y}else bbox.xMin=math.min(bbox.xMin,q.x);bbox.yMin=math.min(bbox.yMin,q.y);bbox.xMax=math.max(bbox.xMax,q.x);bbox.yMax=math.max(bbox.yMax,q.y)end end end;g.bounds=bbox
    stack[id]=nil;return g
   end
   local result=decode(glyphId,0);for _,record in ipairs(instructionRecords)do if record.depth>0 then result.instructions.components[#result.instructions.components+1]=record end end
   result.stats={pointsAllocated=used.points,contoursAllocated=used.contours,components=used.components,instructionBytes=used.instructionBytes,work=used.work}
   if sfnt.variableBase then result.variableBase=true;result.variationApplied=false end;return result
  end
  return F
 end
 function M.open(bytes,origin,options)return open(function(limits)return S.open(bytes,origin,limits)end,options)end
 function M.openBaseVariable(container,options)
  return open(function(limits)
   if limits~=nil then fail('E_FONT_OUTLINE_SHAPE','Shared variable container limits cannot be replaced')end
   return S.verifyVariableContainer(container)
  end,options)
 end
 return M
end
