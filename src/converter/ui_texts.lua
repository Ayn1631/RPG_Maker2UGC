-- Static visible-text demand, with provenance. It is not a dynamic-name charset.
return function(deps)
 local json=deps['contracts.json'];local M={}
 local arrayMeta,objectMeta=getmetatable(json.array()),getmetatable(json.object())
 local function fail(code,why,path)error({severity='error',code=code,reason=why,jsonPath=path},0)end
 local function tableData(v,path)
  if type(v)~='table'or rawequal(v,json.null)then fail('E_UI_TEXT_SHAPE','Expected UI data table',path)end
  local m=getmetatable(v);if m~=nil and not rawequal(m,arrayMeta)and not rawequal(m,objectMeta)then fail('E_UI_TEXT_SHAPE','Untrusted UI metatable',path)end
  if m~=nil and (next(m)~=nil or getmetatable(m)~=nil)then fail('E_UI_TEXT_SHAPE','Modified JSON marker metatable',path)end
 end
 local function dense(v,path)
  tableData(v,path);if rawequal(getmetatable(v),objectMeta)then fail('E_UI_TEXT_SHAPE','Expected UI array',path)end
  local count,high=0,0;for k in next,v do
   if type(k)~='number'or k%1~=0 or k<1 or k>100000 then fail('E_UI_TEXT_SHAPE','Invalid UI array key',path)end;count=count+1;high=math.max(high,k)
  end;if count~=high then fail('E_UI_TEXT_SHAPE','Sparse UI array',path)end;return count
 end
 function M.collect(ui,programs)
  tableData(ui,'$.ui');tableData(programs,'$.eventPrograms')
  local seen,texts,bytes={}, {},0.0;local demand={};local cpCount=95;local entries=0
  -- Printable ASCII covers source integer formatting and message substitutions.
  for cp=32,126 do demand[cp]=true end
  local function add(value,path,source)
   entries=entries+1;if entries>100000 then fail('E_UI_TEXT_BUDGET','Too many static text occurrences',path)end
   if type(value)~='string'then fail('E_UI_TEXT_SHAPE','Expected visible text',path)end
   bytes=bytes+#value;if bytes>4194304 then fail('E_UI_TEXT_BUDGET','Static text byte budget exceeded',path)end
   local ok,e=pcall(function()for at,cp in utf8.codes(value)do
    if cp>1114111 or cp>=55296 and cp<=57343 then fail('E_UI_TEXT_ENCODING','Invalid Unicode scalar',path)end
    -- CR/LF/tab control line flow; they are not glyph demands.
    if cp~=9 and cp~=10 and cp~=13 then
     if cp<32 or cp==127 then fail('E_UI_TEXT_ENCODING','Unexpected visible-text control',path)end
     if not demand[cp]then cpCount=cpCount+1;if cpCount>65536 then fail('E_UI_TEXT_BUDGET','Static codepoint budget exceeded',path)end;demand[cp]=true end
    end
   end end)
   if not ok then if type(e)=='table'and e.code then error(e,0)end;fail('E_UI_TEXT_ENCODING','Invalid UTF8 visible text',path)end
   local origin={jsonPath=path}
    if source~=nil then tableData(source,path..'.source');if source.file~=nil then if type(source.file)~='string'then fail('E_UI_TEXT_SHAPE','Invalid source file',path)end;origin.file=source.file end;if source.jsonPath~=nil then if type(source.jsonPath)~='string'then fail('E_UI_TEXT_SHAPE','Invalid source path',path)end;origin.sourceJsonPath=source.jsonPath end end
   local record=seen[value]
   if not record then record={text=value,sources={}};texts[#texts+1]=record;seen[value]=record end
   record.sources[#record.sources+1]=origin
  end
  add(ui.gameTitle,'$.ui.gameTitle');add(ui.currencyUnit,'$.ui.currencyUnit')
  if ui.equipmentTypes~=nil then
   for i=1,dense(ui.equipmentTypes,'$.ui.equipmentTypes')do
    add(ui.equipmentTypes[i],'$.ui.equipmentTypes['..(i-1)..']',{file='data/System.json',jsonPath='$.equipTypes['..(i-1)..']'})
   end
   add('→','$.ui.nativeText.equipmentArrow')
  end
  tableData(ui.terms,'$.ui.terms')
  for _,kind in ipairs({'basic','params','commands'})do local path='$.ui.terms.'..kind;local rows=ui.terms[kind];for i=1,dense(rows,path)do add(rows[i],path..'['..(i-1)..']')end end
  local messages=ui.terms.messages;tableData(messages,'$.ui.terms.messages');local keys={}
  for k in next,messages do if type(k)~='string'then fail('E_UI_TEXT_SHAPE','Message name must be string','$.ui.terms.messages')end;keys[#keys+1]=k end;table.sort(keys)
  for _,key in ipairs(keys)do add(messages[key],'$.ui.terms.messages['..json.encode(key)..']')end
  local defs=ui.presentationDefs;tableData(defs,'$.ui.presentationDefs')
  for _,kind in ipairs({'actors','classes','items','weapons','armors'})do
   local path='$.ui.presentationDefs.'..kind;local rows=defs[kind]
   for i=1,dense(rows,path)do local row=rows[i];tableData(row,path);local p=path..'['..(i-1)..']';add(row.name,p..'.name')
    if kind=='actors'then add(row.nickname,p..'.nickname');add(row.profile,p..'.profile')
    elseif kind~='classes'then add(row.description,p..'.description')end
   end
  end
  keys={};for k in next,programs do if type(k)~='string'then fail('E_UI_TEXT_SHAPE','Program ID must be string','$.eventPrograms')end;keys[#keys+1]=k end;table.sort(keys)
  local instructionsSeen=0
  for _,key in ipairs(keys)do
   local path='$.eventPrograms['..json.encode(key)..']';local program=programs[key];tableData(program,path);local instructions=program.instructions
   instructionsSeen=instructionsSeen+dense(instructions,path..'.instructions');if instructionsSeen>1000000 then fail('E_UI_TEXT_BUDGET','Too many source instructions',path)end
   for i=1,dense(instructions,path..'.instructions')do local ins=instructions[i];local p=path..'.instructions['..(i-1)..']';tableData(ins,p)
    if ins.op=='dialogue'then
     add(ins.speaker,p..'.speaker',ins.source)
     for j=1,dense(ins.lines,p..'.lines')do add(ins.lines[j],p..'.lines['..(j-1)..']',ins.source)end
     if ins.choices~=nil then for j=1,dense(ins.choices,p..'.choices')do add(ins.choices[j],p..'.choices['..(j-1)..']',ins.source)end end
    end
   end
  end
  local codepoints={};for cp in pairs(demand)do codepoints[#codepoints+1]=cp end;table.sort(codepoints)
  if #codepoints>65536 then fail('E_UI_TEXT_BUDGET','Static codepoint budget exceeded')end
  return{kind='r2u.ui-text-demand',schemaVersion=1,texts=texts,codepoints=codepoints,staticOnly=true,dynamicInputCovered=false,stats={textBytes=bytes,uniqueTexts=#texts,textOccurrences=entries,codepoints=#codepoints}}
 end
 return M
end
