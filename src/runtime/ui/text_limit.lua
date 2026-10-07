-- Host TextBox limit: cap UTF-16 units conservatively and never split UTF-8.
return function()
 local M={maximum=1000}
 function M.units(codepoint)return codepoint>65535 and 2 or 1 end
 function M.clip(value,limit)
  limit=limit or M.maximum
  if #value<=limit then return value end
  local used,cut=0,1
  for at,cp in utf8.codes(value)do
   local n=M.units(cp)
   if used+n>limit then return value:sub(1,cut-1)..'…' end
   used=used+n
   if used<=limit-1 then cut=at+#utf8.char(cp)end
  end
  return value
 end
 function M.split(value,limit)
  limit=limit or M.maximum;if #value<=limit then return{value}end
  local result,start,used={},1,0
  for at,cp in utf8.codes(value)do local n=M.units(cp)
   if used+n>limit then result[#result+1]=value:sub(start,at-1);start,used=at,0 end
   used=used+n
  end
  result[#result+1]=value:sub(start);return result
 end
 return M
end
