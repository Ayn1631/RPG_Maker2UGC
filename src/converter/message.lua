-- Build-time message grammar and style/timing token projection.
return function(deps)
 local flow=deps['runtime.ui.message_flow'];local M={}
 function M.compile(lines,profile,visu)return flow.compile(lines,profile,visu)end
 return M
end
