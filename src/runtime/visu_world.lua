-- Small mutable state for the source-used world features of the Visu sample.
return function()
 local M={}
 local function fail(s)error({code='E_VISU_WORLD',reason=s},0)end
 function M.new(config,services)
  local state={battleSystem=config.defaultBattleSystem,lastObject='',lastQuantity=0,save={}}
  local V={}
  function V.execute(ins)
   local action=ins.action
   if action=='gain_all'then
    local amount=math.max(0,services.variable(ins.variableId))
    for _,id in ipairs(ins.ids)do services.gain(ins.itemKind,id,amount)end
   elseif action=='learn_all'then services.learn(ins.ids)
   elseif action=='random_treasure'then
    local id=ins.minimumId+services.randomInt(ins.idCount)
    local amount=ins.minimumAmount+services.randomInt(ins.amountCount)
    services.gain('item',id,amount)
   elseif action=='open_url'then services.signal('R2U_OPEN_URL',ins.url)
   elseif action=='battle_system'then state.battleSystem=ins.value
   elseif action=='choices'then state.choices={columns=ins.columns,rows=ins.rows,lineHeight=ins.lineHeight,align=ins.align}
   elseif action=='save_metadata'then state.save[ins.key]=ins.value
   else fail('Unknown instruction '..tostring(action))end
   return{kind='continue'}
  end
  function V.gained(name,amount)state.lastObject=name;state.lastQuantity=amount end
  function V.battleSystem()return state.battleSystem end
  function V.expand(code)
   if code=='LASTGAINOBJ'then return state.lastObject end
   if code=='LASTGAINOBJQUANTITY'then return string.format('%.0f',state.lastQuantity)end
   fail('Unknown text control '..tostring(code))
  end
  function V.project(message)
   message.choiceLayout=state.choices
   for _,tokens in ipairs({message.flowTokens or {},message.speakerTokens or {}})do for _,token in ipairs(tokens)do
    if token.kind=='visu_gain'then token.kind='text';token.value=V.expand(token.code);token.code=nil end
   end end
   return message
  end
  return V
 end
 return M
end
