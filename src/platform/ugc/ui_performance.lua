-- Optional shared HUD. One textbox, sampled twice a second; no per-control polling.
return function()
 local M={}
 function M.open(host,template,lifecycle)
  local control=host.game.InstantiateClientUIControl(template,host.script.object)
  control.name='R2U performance'
  control:SetAnchorMin(0,1);control:SetAnchorMax(0,1);control:SetPivot(0,1)
  control:SetAnchoredPosition(12,-12);control:SetSizeDelta(630,132)
  control.minimumFontSize=14;control.fontSize=18;control.adaptiveFontSize=false
  control.horizontalAlignment=host.Enum.TextHorizontalAlignment.Left
  control.verticalAlignment=host.Enum.TextVerticalAlignment.Top
  control.bgColor=host.Color.FromRGBA(5,12,20,225)
  control.fontColor=host.Color.FromRGBA(224,247,238,255)
  control:SetActive(true);control:SetVisible(true)
  control.text='R2U 性能统计 · 等待采样'
  local elapsed,frames,work,peak,created,released=0,0,0,0,0,0
  local snapshot,closed={},false
  local api={}
  function api.update(dt,seconds)
   if closed then return end
   local s=lifecycle.stats()
   elapsed=elapsed+math.max(0,dt or 0);frames=frames+1
   if seconds then work=work+seconds;peak=math.max(peak,seconds)end
   created=math.max(created,s.lastFrameCreated or 0)
   released=math.max(released,s.lastFrameReleased or s.lastFrameDestroyed or 0)
   if elapsed<.5 then return end
   snapshot={frameMs=elapsed*1000/frames,luaMs=seconds and work*1000/frames or nil,luaPeakMs=seconds and peak*1000 or nil}
   local timing=seconds and string.format('Lua %.2f ms / 峰值 %.2f ms',snapshot.luaMs,snapshot.luaPeakMs)or 'Lua 耗时：宿主未提供时钟'
   control.text=string.format('R2U 控件池 %d / %d · 命中 %d\n原生存量 %d · 累计创建 %d / 删除 %d\n采样帧峰值：创建 %d / 回收 %d（上限 400）\n待创建 %d · 待回收 %d · 帧间隔 %.1f ms\n%s',
    s.poolIdle or 0,s.poolCapacity or 0,s.poolHits or 0,(s.created or 0)-(s.destroyed or 0),s.created or 0,s.destroyed or 0,
    created,released,s.pendingCreated or 0,s.pendingDestroyed or 0,snapshot.frameMs,timing)
   control:SetAsLastSibling()
   elapsed,frames,work,peak,created,released=0,0,0,0,0,0
  end
  function api.stats()local out={};for k,v in pairs(snapshot)do out[k]=v end;return out end
  function api.close(reclaim)if not closed then closed=true;if reclaim~=false then host.game.DestroyClientUIControl(control)end end end
  return api
 end
 return M
end
