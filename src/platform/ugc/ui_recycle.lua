-- One shared destruction queue for all scene surfaces, including map changes.
-- Hide immediately; remove descendants before their parent so a single native
-- Destroy cannot secretly free thousands of controls in one host frame.
return function()
 local M={}
 local owners=setmetatable({},{__mode='k'})
 function M.new(game,owner)
  if owner and owners[owner]then return owners[owner]end
  local queue,head,stack,marked={},1,{},{}
  local stats={pendingRoots=0,destroyed=0,lastFrameDestroyed=0,peakFrameDestroyed=0}
  local R={};local facade=setmetatable({},{__index=game})
  function facade.DestroyClientUIControl(o)
   if marked[o]or o.alive==false then return end
   o:SetActive(false);o:SetVisible(false)
   marked[o]=true;queue[#queue+1]=o;stats.pendingRoots=stats.pendingRoots+1
  end
  function R.retired(o)return marked[o]==true end
  function R.flush()
   local removed,visits=0,0
   while removed<400 and visits<800 do
    if #stack==0 then
     if head>#queue then queue,head={},1;break end
     local o=queue[head];queue[head]=false;head=head+1
     stats.pendingRoots=stats.pendingRoots-1;stack[1]={object=o}
    end
    local entry=stack[#stack];local o=entry.object;visits=visits+1
    if o.alive==false then marked[o]=nil;stack[#stack]=nil
    else
     if not entry.children then entry.children=o:GetChildren();entry.index=1 end
     local child=entry.children[entry.index]
     if child then entry.index=entry.index+1;stack[#stack+1]={object=child}
     else
      game.DestroyClientUIControl(o);marked[o]=nil;stack[#stack]=nil
      removed=removed+1;stats.destroyed=stats.destroyed+1
     end
    end
   end
   stats.lastFrameDestroyed=removed;stats.peakFrameDestroyed=math.max(stats.peakFrameDestroyed,removed)
   return removed
  end
  function R.stats()local s={};for k,v in pairs(stats)do s[k]=v end;s.pending=stats.pendingRoots+#stack;return s end
  R.game=facade;if owner then owners[owner]=R end;return R
 end
 return M
end
