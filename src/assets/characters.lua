-- Standard MV/MZ character sheet coordinates; offline only.
return function(deps)
 local D=deps['contracts.diagnostic'];local M={}
 local function integer(n,lo,hi)return type(n)=='number' and n%1==0 and n>=lo and n<=hi end
 local function fail(reason)D.raise('E_CHARACTER_EXPORT',reason)end
 function M.layout(name,index,width,height)
  if type(name)~='string' or name=='' or not integer(index,0,7) or not integer(width,1,4096) or not integer(height,1,4096)then fail('Invalid character sheet identity or dimensions')end
  local filename=name:match('[^/\\]+$') or '';local prefix=filename:match('^[!$]+') or ''
  local big=prefix:find('$',1,true)~=nil;local cols,rows=big and 3 or 12,big and 4 or 8
  if width%cols~=0 or height%rows~=0 then fail('Character sheet dimensions must divide evenly into '..cols..' x '..rows..' frames')end
  local w,h=width/cols,height/rows;local bx,by=big and 0 or index%4*3,big and 0 or math.floor(index/4)*4
  local frames={}
  for dir=0,3 do for pattern=0,2 do frames[#frames+1]={direction=(dir+1)*2,pattern=pattern,x=(bx+pattern)*w,y=(by+dir)*h,width=w,height=h}end end
  return{width=w,height=h,bigCharacter=big,objectCharacter=prefix:find('!',1,true)~=nil,frames=frames}
 end
 function M.crop(image,r)
  if not integer(r.x,0,image.width-1) or not integer(r.y,0,image.height-1) or not integer(r.width,1,image.width-r.x) or not integer(r.height,1,image.height-r.y)then fail('Character frame outside image')end
  local rows={};for y=r.y,r.y+r.height-1 do local at=(y*image.width+r.x)*4+1;rows[#rows+1]=image.rgba:sub(at,at+r.width*4-1)end
  return{width=r.width,height=r.height,rgba=table.concat(rows)}
 end
 function M.splitBush(frame,depth)
  if not integer(depth,1,frame.height)then fail('Bush depth must be an integer no larger than character height')end
  local cut=(frame.height-depth)*frame.width*4
  return{width=frame.width,height=frame.height,rgba=frame.rgba:sub(1,cut)..string.rep('\0',#frame.rgba-cut)},
   {width=frame.width,height=frame.height,rgba=string.rep('\0',cut)..frame.rgba:sub(cut+1)}
 end
 return M
end
