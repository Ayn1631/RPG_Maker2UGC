-- MV Window_Base.drawCurrentAndMax geometry; source font measurement is supplied.
return function()
 local M={}
 local function fail(why)error({severity='error',code='E_UI_GAUGE_LAYOUT',reason=why},0)end
 local function number(v,lo,hi)
  if type(v)~='number'or v~=v or v<lo or v>hi then fail('Invalid finite gauge number')end
  return v*1.0
 end
 local function rect(x,y,w,h)return{x=x,y=y,width=w,height=h}end
 function M.currentAndMax(options,measure)
  if type(options)~='table'or getmetatable(options)~=nil then fail('Expected plain gauge options')end
  for k in next,options do if k~='profile'and k~='x'and k~='y'and k~='width'and k~='lineHeight'then fail('Unknown gauge option')end end
  if options.profile~='mv-1.5.1'then fail('Unsupported current/max gauge profile')end
  if type(measure)~='function'then fail('Source text measurement service required')end
  local x,y,w=number(options.x,-32768,32768),number(options.y,-32768,32768),number(options.width,0,32768)
  local h=options.lineHeight;if h==nil then h=36 end;h=number(h,1,32768)
  -- Native reserves four digits even when current/max have different lengths.
  -- Its HP label width is also used for MP, regardless of localized label text.
  local labelWidth=number(measure('HP'),0,32768)
  local valueWidth=number(measure('0000'),0,32768)
  local slashWidth=number(measure('/'),0,32768)
  local x1=x+w-valueWidth;local x2=x1-slashWidth;local x3=x2-valueWidth
  local showMax=x3>=x+labelWidth
  local out={showMax=showMax,align='Right',labelWidth=labelWidth,valueWidth=valueWidth,slashWidth=slashWidth,currentRect=rect(showMax and x3 or x1,y,valueWidth,h)}
  if showMax then out.slashRect=rect(x2,y,slashWidth,h);out.maxRect=rect(x1,y,valueWidth,h)end
  return out
 end
 return M
end
