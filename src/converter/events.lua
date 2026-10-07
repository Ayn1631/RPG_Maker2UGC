return function(deps)
  local json = deps["contracts.json"]
  local diagnostic = deps["contracts.diagnostic"]
  local movement=deps['converter.movement']
  local messageCompiler=deps['converter.message']
  local maxCommands, maxNesting, maxInteger = 100000, 64, 9007199254740991
  local function object(v) return type(v)=="table" and v~=json.null and not json.is_array(v) end
  local function integer(v) return type(v)=="number" and v==v and v>=-maxInteger and v<=maxInteger and v%1==0 end
  local function idText(v) return string.format("%d",v) end
  local function array(v)
    if not json.is_array(v) then return false end
    local count,highest=0,0
    for key in pairs(v) do
      if not integer(key) or key<1 then return false end
      count=count+1; highest=math.max(highest,key)
    end
    return count==highest
  end
  local function clone(v)
    if type(v)~="table" or v==json.null then return v end
    local result=json.is_array(v) and json.array() or json.object()
    for key,value in pairs(v) do result[key]=clone(value) end
    return result
  end
  local function compile(index,extensions)
    local diagnostics, programs, specs, commonIds = json.array(),json.object(),{},{}
    local sequenceOnly={};for _,id in ipairs(index.visuGameplay and index.visuGameplay.sequenceCommonEventIds or {})do sequenceOnly[id]=true end
    local function add(code,reason,file,path)
      diagnostics[#diagnostics+1]=diagnostic.new(code,reason,{file=file,jsonPath=path})
    end
    local function fail(code,reason,file,path) diagnostic.raise(code,reason,{file=file,jsonPath=path}) end
    local function finish()
      table.sort(diagnostics,function(a,b)
        for _,key in ipairs({"file","jsonPath","code","reason"}) do
          local av,bv=a[key] or "",b[key] or ""
          if av~=bv then return av<bv end
        end
        return false
      end)
      if #diagnostics>0 then return {ok=false,package=nil,diagnostics=diagnostics} end
      local package=clone(index)
      package.kind="r2u.event-package"; package.schemaVersion=1; package.stage="M1a"
      package.capabilities=object(package.capabilities) and package.capabilities or json.object()
      package.capabilities.playable=false; package.capabilities.publishable=false; package.capabilities.assetsConverted=false
      package.capabilities.eventExecution=true; package.eventPrograms=programs
      return {ok=true,package=package,diagnostics=diagnostics}
    end
    if not object(index) or not object(index.database) or not array(index.maps) then
      add("E_EVENT_SHAPE","Source index requires database object and maps array",nil,"$")
      return finish()
    end
    local function register(id,context,list,file,path)
      specs[#specs+1]={id=id,context=context,list=list,file=file,path=path}
    end
    local function pages(record,idPrefix,context,file,path)
      if not array(record.pages) then add("E_EVENT_SHAPE","Event pages must be an array",file,path..".pages"); return end
      for pageSlot,page in ipairs(record.pages) do
        local pagePath=path..".pages["..(pageSlot-1).."]"
        if not object(page) then add("E_EVENT_SHAPE","Event page must be an object",file,pagePath)
        else
          local ctx=clone(context); ctx.page=pageSlot
          local sourcePath=pagePath
          for _,origin in ipairs(record.visuBaseTroopSources or {})do if origin.pageIndex==pageSlot-1 then
            sourcePath='$['..origin.sourceTroopId..'].pages['..origin.sourcePageIndex..']'
          end end
          register(idPrefix..":page:"..pageSlot,ctx,page.list,file,sourcePath..".list")
        end
      end
    end
    for mapSlot,map in ipairs(index.maps) do
      if not object(map) or not integer(map.id) or map.id<1 then
        add("E_EVENT_SHAPE","Map requires a positive integer id",nil,"$.maps["..(mapSlot-1).."]")
      else
        local file=object(map.sourceLocation) and type(map.sourceLocation.file)=="string" and map.sourceLocation.file
          or string.format("data/Map%03d.json",map.id)
        if not array(map.events) then add("E_EVENT_SHAPE","Map events must be an array",file,"$.events")
        else
          for slot,event in ipairs(map.events) do
            if event~=json.null then
              local path="$.events["..(slot-1).."]"
              if not object(event) or not integer(event.id) or event.id<1 or event.id~=slot-1 then
                add("E_EVENT_SHAPE","Event id must equal its positive zero-based source slot",file,path)
              else pages(event,"map:"..idText(map.id)..":event:"..idText(event.id),json.object({mapId=map.id,eventId=event.id}),file,path) end
            end
          end
        end
      end
    end
    for _,name in ipairs({"CommonEvents","Troops"}) do
      local tableIndex=index.database[name]
      local file="data/"..name..".json"
      if tableIndex~=nil then
        if not object(tableIndex) or not array(tableIndex.records) then add("E_EVENT_SHAPE",name.." records must be an array",file,"$")
        else
          for slot,record in ipairs(tableIndex.records) do
            if record~=json.null then
              local path="$["..(slot-1).."]"
              if not object(record) or not integer(record.id) or record.id<1 or record.id~=slot-1 then
                add("E_EVENT_SHAPE","Record id must equal its positive zero-based source slot",file,path)
              elseif name=="CommonEvents" and not sequenceOnly[record.id] then
                commonIds[record.id]=true
                register("common:"..idText(record.id),json.object({commonEventId=record.id}),record.list,file,path..".list")
              elseif name=='Troops' then pages(record,"troop:"..idText(record.id),json.object({troopId=record.id}),file,path) end
            end
          end
        end
      end
    end
    local system=object(index.database.System) and index.database.System.records or nil
    local function compileProgram(spec)
      local list,file,path=spec.list,spec.file,spec.path
      local function errorAt(code,reason,slot)
        fail(code,reason,file,slot and path.."["..(slot-1).."]" or path)
      end
      if not array(list) then errorAt("E_EVENT_SHAPE","Event list must be an array") end
      if #list>maxCommands then errorAt("E_EVENT_SHAPE","Program exceeds maxCommands guard (100000)",1) end
      for slot,cmd in ipairs(list) do
        if not object(cmd) or not integer(cmd.code) or cmd.code<0 or not integer(cmd.indent) or cmd.indent<0
          or not array(cmd.parameters) then
          errorAt("E_EVENT_SHAPE","Command requires integer code/indent and a dense parameters array",slot)
        end
      end
      local out, cursor, loops = json.array(),1,{}
      local labels,labelJumps={},{}
      local function source(slot)
        return json.object({file=file,jsonPath=path.."["..(slot-1).."]",commandIndex=slot-1})
      end
      local function emit(op,slot,fields)
        local ins=json.object(fields or {}); ins.op=op; ins.source=source(slot); out[#out+1]=ins
        return #out,ins
      end
      local function shape(ok,reason,slot) if not ok then errorAt("E_EVENT_SHAPE",reason,slot) end end
      local function structure(ok,reason,slot) if not ok then errorAt("E_EVENT_STRUCTURE",reason,slot) end end
      local function supported(ok,reason,slot) if not ok then errorAt("E_EVENT_UNSUPPORTED",reason,slot) end end
      local function parameters(cmd,count,slot)
        shape(#cmd.parameters==count,"Command "..cmd.code.." requires "..count.." parameters",slot)
        return cmd.parameters
      end
      local function enum(v,first,last,slot)
        shape(integer(v) and v>=first and v<=last,"Parameter is outside its integer range",slot)
      end
      local function text(v,slot,messageLine)
        shape(type(v)=="string","Text parameter must be a string",slot)
        local valid=pcall(function()
          for _,cp in utf8.codes(v) do assert(cp<=1114111 and not (cp>=55296 and cp<=57343)) end
        end)
        shape(valid,"Text must be valid UTF-8",slot)
        local controls=v:gsub('\\\\',''):gsub('\\[VvNnPp]%[%d+%]',''):gsub('\\[Gg]','')
        if not messageLine then supported(not controls:find('\\',1,true),'Text style/control token is not implemented here',slot) end
        return v
      end
      local function reference(kind,id,slot)
        local names=object(system) and system[kind] or nil
        shape(integer(id),"Referenced id must be a finite safe integer",slot)
        if id<1 or not array(names) or id>#names-1 then
          errorAt("E_EVENT_REFERENCE","Referenced "..kind.." id is outside System source indices",slot)
        end
        return id
      end
      local function operand(kind,value,slot)
        shape(integer(kind),"Operand type must be an integer",slot)
        supported(kind==0 or kind==1,"Only constant and variable operands are supported",slot)
        if kind==0 then shape(integer(value),"Constant operand must be a finite safe integer",slot)
        else reference("variables",value,slot) end
        return json.object({kind=kind==0 and "constant" or "variable",value=value})
      end
      local function databaseReference(name,id,slot)
        shape(integer(id) and id>0,"Database id must be a positive safe integer",slot)
        local database=index.database[name]
        local record=object(database) and array(database.records) and database.records[id+1]
        if not object(record) or record.id~=id then errorAt("E_EVENT_REFERENCE","Missing "..name.." id "..id,slot) end
        return id
      end
      local function script(source,kind,slot)
        supported(extensions~=nil and type(extensions.script)=='function','Scripts require an explicit registered SDK adapter',slot)
        local ok,value=pcall(extensions.script,source,kind)
        if not ok then errorAt(type(value)=='table' and value.code or 'E_EXTENSION_SCRIPT',type(value)=='table' and value.reason or tostring(value),slot)end
        return value
      end
      local function condition(cmd,slot)
        local p=cmd.parameters
        shape(integer(p[1]),"Condition type must be an integer",slot)
        supported(p[1]>=0 and p[1]<=13,"Unknown condition type",slot)
        if p[1]==0 then
          parameters(cmd,3,slot); reference("switches",p[2],slot); enum(p[3],0,1,slot)
          return json.object({kind="switch",id=p[2],value=p[3]==0})
        elseif p[1]==1 then
          parameters(cmd,5,slot); reference("variables",p[2],slot); enum(p[5],0,5,slot)
          return json.object({kind="variable",id=p[2],comparison=p[5],operand=operand(p[3],p[4],slot)})
        elseif p[1]==2 then
          parameters(cmd,3,slot); shape(p[2]=="A" or p[2]=="B" or p[2]=="C" or p[2]=="D","Self-switch key must be A/B/C/D",slot)
          enum(p[3],0,1,slot); return json.object({kind="self_switch",key=p[2],value=p[3]==0})
        elseif p[1]==3 then
          parameters(cmd,3,slot);enum(p[2],0,149130);enum(p[3],0,1,slot)
          return json.object({kind='timer',seconds=p[2],comparison=p[3]})
        elseif p[1]==5 then
          enum(p[2],0,10000,slot);enum(p[3],0,1,slot);parameters(cmd,p[3]==0 and 3 or 4,slot)
          if p[3]==1 then databaseReference('States',p[4],slot)end
          return json.object({kind='enemy',index=p[2],stateId=p[3]==1 and p[4] or nil})
        elseif p[1]==6 then
          parameters(cmd,3,slot);enum(p[2],-1,100000,slot)
          shape(p[3]==2 or p[3]==4 or p[3]==6 or p[3]==8,'Direction must be cardinal',slot)
          return json.object({kind='direction',characterId=p[2],direction=p[3]})
        elseif p[1]==4 then
          enum(p[3],0,6,slot);parameters(cmd,p[3]==0 and 3 or 4,slot); databaseReference("Actors",p[2],slot)
          if p[3]==0 then return json.object({kind='actor',id=p[2]})end
          if p[3]==1 then shape(type(p[4])=='string','Actor name comparison must be text',slot)
          else databaseReference(({[2]='Classes',[3]='Skills',[4]='Weapons',[5]='Armors',[6]='States'})[p[3]],p[4],slot)end
          return json.object({kind='actor',id=p[2],test=p[3],value=p[4]})
        elseif p[1]==11 then
          local mz=index.engineProfile~='mv-turn'
          shape(#p==2 or mz and #p==3,'Button condition has an invalid parameter count',slot)
          shape(({ok=true,cancel=true,menu=true,escape=true,shift=true,control=true,tab=true,pageup=true,pagedown=true,up=true,down=true,left=true,right=true})[p[2]]==true,'Unknown logical button name',slot)
          local mode=p[3] or 0;enum(mode,0,2,slot)
          return json.object({kind='button',button=p[2],mode=mode})
        elseif p[1]==12 then
          parameters(cmd,2,slot);return json.object(script(p[2],'boolean',slot))
        elseif p[1]==13 then
          parameters(cmd,2,slot);enum(p[2],0,2,slot)
          return json.object({kind='vehicle',vehicleType=p[2]})
        elseif p[1]==7 then
          parameters(cmd,3,slot); shape(integer(p[2]) and p[2]>=0,"Gold condition value must be nonnegative",slot); enum(p[3],0,2,slot)
          return json.object({kind="gold",value=p[2],comparison=p[3]})
        else
          local names={[8]="Items",[9]="Weapons",[10]="Armors"}
          local kinds={[8]="item",[9]="weapon",[10]="armor"}
          parameters(cmd,p[1]==8 and 2 or 3,slot); databaseReference(names[p[1]],p[2],slot)
          if p[1]~=8 then shape(type(p[3])=="boolean","Include equipped must be boolean",slot) end
          return json.object({kind="inventory",itemKind=kinds[p[1]],id=p[2],includeEquip=p[1]~=8 and p[3] or false})
        end
      end
      local tails={[401]=true,[408]=true,[402]=true,[403]=true,[404]=true,[411]=true,[412]=true,[413]=true,
        [505]=true,[601]=true,[602]=true,[603]=true,[604]=true,[657]=true}
      local block, choices, battle
      local function nesting(depth,slot) structure(depth<=maxNesting,"Program exceeds maxNesting guard (64)",slot) end
      choices=function(indent,depth,dialogue,mergedExits)
        local slot,cmd=cursor,list[cursor]; nesting(depth+1,slot)
        local p=parameters(cmd,5,slot)
        shape(array(p[1]) and #p[1]>=1 and #p[1]<=6,"Choices must be an array with 1..6 entries",slot)
        local options=json.array(); for i,value in ipairs(p[1]) do options[i]=text(value,slot,true) end
        shape(integer(p[2]) and p[2]>=-2,"Cancel choice must be an integer >= -2",slot)
        shape(integer(p[3]) and p[3]>=-1 and p[3]<#options,"Default choice must be -1 or a valid index",slot)
        enum(p[4],0,2,slot); enum(p[5],0,2,slot)
        if not dialogue then
          local _,ins=emit("dialogue",slot,{lines=json.array(),speaker="",background=0,position=2}); dialogue=ins
        end
        local offset=mergedExits and #dialogue.choices or 0
        local localCancel=p[2]>=#options and -2 or p[2]
        if not mergedExits then
          dialogue.choices=json.array();dialogue.choiceTargets=json.array();dialogue.defaultChoice=-1;dialogue.cancelChoice=-1
          dialogue.choicePosition=p[4];dialogue.choiceBackground=p[5]
        end
        for _,value in ipairs(options)do dialogue.choices[#dialogue.choices+1]=value end
        if p[3]>=0 then dialogue.defaultChoice=offset+p[3]end
        if localCancel~=-1 then dialogue.cancelChoice=localCancel>=0 and offset+localCancel or localCancel end
        if index.visuWorld then dialogue.extendedChoices=true end
        cursor=cursor+1
        local seen,exits,cancel={},mergedExits or {},false
        while cursor<=#list do
          local marker,at=list[cursor],cursor
          structure(marker.indent==indent,"Choice branch marker indentation mismatch",at)
          if marker.code==404 then
            parameters(marker,0,at)
            for i=1,#options do structure(seen[i],"Every choice must have exactly one matching 402 branch",at) end
            structure((localCancel==-2)==cancel,"Independent cancel requires 403; mapped/disabled cancel forbids it",at)
            emit("nop",at); cursor=cursor+1
            if index.visuWorld and list[cursor] and list[cursor].indent==indent and list[cursor].code==102 then
              shape(#dialogue.choices<128,'Extended choices exceed 128 entries',cursor)
              choices(indent,depth,dialogue,exits);return
            end
            for _,exit in ipairs(exits) do exit.target=#out+1 end
            return
          end
          structure(marker.code==402 or marker.code==403,"Expected 402/403/404 choice marker",at)
          local target=emit("nop",at)
          if marker.code==402 then
            local mp=parameters(marker,2,at); enum(mp[1],0,#options-1,at); text(mp[2],at,true)
            structure(not seen[mp[1]+1] and mp[2]==options[mp[1]+1],"Choice branch index/text must be unique and match options",at)
            seen[mp[1]+1]=true; dialogue.choiceTargets[offset+mp[1]+1]=target
          else
            -- Some MZ editor revisions store [6,null] on the cancel marker.
            -- Game_Interpreter.command403 ignores these editor parameters.
            if #marker.parameters~=0 then
              shape(index.engineProfile~='mv-turn' and #marker.parameters==2 and marker.parameters[1]==6 and marker.parameters[2]==json.null,'Invalid cancel marker metadata',at)
            end
            structure(localCancel==-2 and not cancel,"Unexpected or duplicate cancel branch",at)
            cancel=true; dialogue.cancelTarget=target
          end
          cursor=cursor+1; block(indent+1,depth+1,{[402]=true,[403]=true,[404]=true},indent)
          local _,exit=emit("jump",at); exits[#exits+1]=exit
        end
        errorAt("E_EVENT_STRUCTURE","Choice block is missing 404",slot)
      end
      local function inputCommand(dialogue)
        local slot,cmd=cursor,list[cursor];local p=parameters(cmd,2,slot)
        reference('variables',p[1],slot)
        if not dialogue then local _;_,dialogue=emit('dialogue',slot,{lines=json.array(),speaker='',background=0,position=2})end
        if cmd.code==103 then enum(p[2],1,8,slot);dialogue.numberInput=json.object({variableId=p[1],digits=p[2]})
        else enum(p[2],1,4,slot);dialogue.itemChoice=json.object({variableId=p[1],itemType=p[2]})end
        cursor=cursor+1
      end
      battle=function(indent,depth)
        local slot,cmd=cursor,list[cursor];local p=parameters(cmd,4,slot)
        enum(p[1],0,2,slot)
        if p[1]==0 then databaseReference("Troops",p[2],slot) elseif p[1]==1 then reference("variables",p[2],slot)end
        shape(type(p[3])=="boolean" and type(p[4])=="boolean","Battle escape and lose flags must be boolean",slot)
        local _,ins=emit("battle",slot,{troopOperand=p[1]==2 and json.object({kind='encounter',value=0}) or operand(p[1],p[2],slot),canEscape=p[3],canLose=p[4],resultTargets=json.array()})
        cursor=cursor+1
        local exits,last={},600
        if list[cursor] and list[cursor].indent==indent and list[cursor].code>=601 and list[cursor].code<=604 then
          nesting(depth+1,slot)
          while cursor<=#list do
            local marker,at=list[cursor],cursor
            structure(marker.indent==indent,"Battle branch marker indentation mismatch",at)
            if marker.code==604 then
              parameters(marker,0,at);emit("nop",at);cursor=cursor+1;break
            end
            structure(marker.code>=601 and marker.code<=603 and marker.code>last,"Expected unique ordered 601/602/603/604 battle markers",at)
            parameters(marker,0,at);last=marker.code
            ins.resultTargets[marker.code-600]=emit("nop",at)
            cursor=cursor+1;block(indent+1,depth+1,{[601]=true,[602]=true,[603]=true,[604]=true},indent)
            local _,exit=emit("jump",at);exits[#exits+1]=exit
            structure(list[cursor]~=nil,"Battle block is missing 604",slot)
          end
        end
        ins.skipTarget=#out+1
        for i=1,3 do if not ins.resultTargets[i] then ins.resultTargets[i]=ins.skipTarget end end
        for _,exit in ipairs(exits) do exit.target=ins.skipTarget end
      end
      block=function(indent,depth,stops,stopIndent,endOnDedent)
        while cursor<=#list do
          local slot,cmd=cursor,list[cursor]
          if endOnDedent and cmd.indent<indent then return end
          if stops and stops[cmd.code] then
            structure(cmd.indent==stopIndent,"Structural marker indentation mismatch",slot); return
          end
          structure(cmd.indent==indent,"Command indentation does not match its containing block",slot)
          structure(not tails[cmd.code],"Orphaned continuation or structural marker",slot)
          local code,p=cmd.code,cmd.parameters
          if code==0 or code==115 then
            parameters(cmd,0,slot); emit(code==0 and "nop" or "return",slot); cursor=cursor+1
          elseif code==109 then
            parameters(cmd,0,slot);supported(index.engineProfile~='mv-turn','Skip 109 requires MZ',slot)
            nesting(depth+1,slot);local _,skip=emit('jump',slot);cursor=cursor+1
            -- Keep the body in the program so explicit label jumps into it work.
            if list[cursor] and list[cursor].indent>indent then block(indent+1,depth+1,nil,nil,true)end
            skip.target=#out+1
          elseif code==108 then
            parameters(cmd,1,slot); shape(type(p[1])=="string","Comment must be a string",slot)
            emit("nop",slot); cursor=cursor+1
            while list[cursor] and list[cursor].code==408 do
              local nextCmd=list[cursor]; structure(nextCmd.indent==indent,"Comment continuation indentation mismatch",cursor)
              local cp=parameters(nextCmd,1,cursor); shape(type(cp[1])=="string","Comment must be a string",cursor); cursor=cursor+1
            end
          elseif code==118 or code==119 then
            parameters(cmd,1,slot);shape(type(p[1])=='string','Label must be text',slot)
            local at,ins=emit(code==118 and 'nop' or 'jump',slot)
            if code==118 then if labels[p[1]]==nil then labels[p[1]]=at end
            else labelJumps[#labelJumps+1]={name=p[1],instruction=ins}end
            cursor=cursor+1
          elseif code==101 then
            local mz=type(index.engineProfile)=="string" and index.engineProfile:match("^mz%-")
            shape(#p==4 or (mz and #p==5),"101 requires four MV or four/five MZ parameters",slot)
            shape(type(p[1])=="string","Face name must be a string",slot)
            shape(integer(p[2]) and p[2]>=0,"Face index must be a nonnegative integer",slot)
            enum(p[3],0,2,slot); enum(p[4],0,2,slot)
            local speaker=#p==5 and text(p[5],slot,true) or ""
            local _,dialogue=emit("dialogue",slot,{lines=json.array(),speaker=speaker,background=p[3],position=p[4],faceName=p[1],faceIndex=p[2]})
            cursor=cursor+1
            while list[cursor] and list[cursor].code==401 do
              local nextCmd=list[cursor]; structure(nextCmd.indent==indent,"Text continuation indentation mismatch",cursor)
              local tp=parameters(nextCmd,1,cursor); dialogue.lines[#dialogue.lines+1]=text(tp[1],cursor,true); cursor=cursor+1
            end
            if list[cursor] and list[cursor].indent==indent then
              if list[cursor].code==102 then choices(indent,depth,dialogue)
              elseif list[cursor].code==103 or list[cursor].code==104 then inputCommand(dialogue)end
            end
          elseif code==355 then
            parameters(cmd,1,slot);shape(type(p[1])=='string','Script must be text',slot)
            local lines={p[1]};cursor=cursor+1
            while list[cursor] and list[cursor].code==655 do
              structure(list[cursor].indent==indent,'Script continuation indentation mismatch',cursor)
              local sp=parameters(list[cursor],1,cursor);shape(type(sp[1])=='string','Script continuation must be text',cursor)
              lines[#lines+1]=sp[1];cursor=cursor+1
            end
            local value=script(table.concat(lines,'\n'),'command',slot)
            emit(value.op or 'extension',slot,value)
          elseif code==356 or code==357 then
            supported(extensions~=nil,'Plugin commands require a registered extension',slot)
            parameters(cmd,code==356 and 1 or 4,slot)
            shape(type(p[1])=='string','Plugin name/command must be text',slot)
            if code==357 then supported(index.engineProfile~='mv-turn','MZ command is unavailable in MV',slot);shape(type(p[2])=='string' and type(p[3])=='string' and object(p[4]),'Invalid MZ plugin command',slot)end
            local ok,value=pcall(extensions.command,code,p,spec.context)
            if not ok then errorAt(type(value)=='table' and value.code or 'E_EXTENSION_COMMAND',type(value)=='table' and value.reason or tostring(value),slot)end
            emit(value.op or 'extension',slot,value);cursor=cursor+1
            -- MZ 657 rows are editor descriptions of the preceding 357 args.
            -- Execution remains entirely in the registered plugin command.
            if code==357 then while list[cursor] and list[cursor].code==657 do
              structure(list[cursor].indent==indent,'Plugin argument description indentation mismatch',cursor)
              local cp=parameters(list[cursor],1,cursor);shape(type(cp[1])=='string','Plugin argument description must be text',cursor)
              cursor=cursor+1
            end end
          elseif code==105 then
            parameters(cmd,2,slot);enum(p[1],1,8,slot);shape(type(p[2])=='boolean','Scrolling text no-fast flag must be boolean',slot)
            local _,dialogue=emit('dialogue',slot,{lines=json.array(),speaker='',background=2,position=0,scroll=json.object({speed=p[1],noFast=p[2]})})
            cursor=cursor+1
            while list[cursor] and list[cursor].code==405 do
              structure(list[cursor].indent==indent,'Scrolling text continuation indentation mismatch',cursor)
              local tp=parameters(list[cursor],1,cursor);dialogue.lines[#dialogue.lines+1]=text(tp[1],cursor,true);cursor=cursor+1
            end
          elseif code==102 then choices(indent,depth)
          elseif code==103 or code==104 then inputCommand()
          elseif code==303 then
            parameters(cmd,2,slot);databaseReference('Actors',p[1],slot);enum(p[2],1,16,slot)
            emit('name_input',slot,{actorId=p[1],maxLength=p[2]});cursor=cursor+1
          elseif code==353 or code==354 then
            parameters(cmd,0,slot);emit(code==353 and 'game_over' or 'return_title',slot);cursor=cursor+1
          elseif code==111 then
            nesting(depth+1,slot); local _,branch=emit("branch",slot,{condition=condition(cmd,slot)})
            cursor=cursor+1; block(indent+1,depth+1,{[411]=true,[412]=true},indent)
            structure(list[cursor]~=nil,"Conditional is missing 412",slot)
            local ending=list[cursor]
            if ending.code==411 then
              parameters(ending,0,cursor); local _,exit=emit("jump",cursor); cursor=cursor+1
              branch.otherwise=#out+1; block(indent+1,depth+1,{[412]=true},indent)
              structure(list[cursor]~=nil,"Conditional is missing 412",slot)
              parameters(list[cursor],0,cursor); emit("nop",cursor); cursor=cursor+1; exit.target=#out+1
            else
              parameters(ending,0,cursor); emit("nop",cursor); cursor=cursor+1; branch.otherwise=#out+1
            end
          elseif code==112 then
            parameters(cmd,0,slot); nesting(depth+1,slot); local head=emit("nop",slot)
            local loop={breaks={}}; loops[#loops+1]=loop; cursor=cursor+1
            block(indent+1,depth+1,{[413]=true},indent)
            structure(list[cursor]~=nil,"Loop is missing 413",slot)
            parameters(list[cursor],0,cursor); emit("jump",cursor,{target=head}); cursor=cursor+1
            for _,exit in ipairs(loop.breaks) do exit.target=#out+1 end
            loops[#loops]=nil
          elseif code==113 then
            parameters(cmd,0,slot); structure(#loops>0,"Break requires an enclosing loop",slot)
            local _,exit=emit("jump",slot); local breaks=loops[#loops].breaks; breaks[#breaks+1]=exit; cursor=cursor+1
          elseif code==117 then
            parameters(cmd,1,slot)
            shape(integer(p[1]),"Common event id must be a finite safe integer",slot)
            if not commonIds[p[1]] then errorAt("E_EVENT_REFERENCE","Common event does not exist",slot) end
            emit("call",slot,{programId="common:"..idText(p[1])}); cursor=cursor+1
          elseif code==121 or code==122 then
            if code==122 then
              shape(integer(p[3]),"Variable operation must be an integer",slot)
              supported(p[3]>=0 and p[3]<=5,"Variable operation is unsupported",slot)
              shape(integer(p[4]),"Operand type must be an integer",slot)
              supported(p[4]>=0 and p[4]<=4,"Unknown variable operand type",slot)
            end
            parameters(cmd,code==121 and 3 or p[4]==2 and 6 or p[4]==3 and 7 or 5,slot)
            reference(code==121 and "switches" or "variables",p[1],slot)
            reference(code==121 and "switches" or "variables",p[2],slot)
            shape(p[1]<=p[2],"Range first id must not exceed last id",slot)
            if code==121 then enum(p[3],0,1,slot); emit("switches",slot,{first=p[1],last=p[2],value=p[3]==0})
            else
              local value
              if p[4]==4 then value=json.object(script(p[5],'integer',slot))
              elseif p[4]==2 then
                shape(integer(p[5]) and integer(p[6]),'Random bounds must be safe integers',slot)
                local span=math.max(1,p[6]-p[5]+1)
                shape(span<=2147483647,'Random range exceeds supported integer span',slot)
                value=json.object({kind='random',minimum=p[5],span=span})
              elseif p[4]==3 then
                enum(p[5],0,index.engineProfile=='mv-turn' and 7 or 8,slot)
                shape(integer(p[6]) and integer(p[7]),'Game data selectors must be integers',slot)
                if p[5]<=2 then databaseReference(({'Items','Weapons','Armors'})[p[5]+1],p[6],slot)
                elseif p[5]==3 then databaseReference('Actors',p[6],slot);enum(p[7],0,12,slot)
                elseif p[5]==4 then enum(p[6],0,maxInteger,slot);enum(p[7],0,10,slot)
                elseif p[5]==5 then enum(p[6],-1,maxInteger,slot);enum(p[7],0,4,slot)
                elseif p[5]==6 then enum(p[6],0,maxInteger,slot)
                elseif p[5]==8 then enum(p[6],0,5,slot)
                else enum(p[6],0,9,slot) end
                value=json.object({kind='game_data',type=p[5],id=p[6],field=p[7]})
              else value=operand(p[4],p[5],slot)end
              emit("variables",slot,{first=p[1],last=p[2],operation=p[3],operand=value})
            end
            cursor=cursor+1
          elseif code==124 then
            parameters(cmd,2,slot);enum(p[1],0,1,slot);enum(p[2],0,math.floor(maxInteger/60),slot)
            emit('timer',slot,{action=p[1]==0 and 'start' or 'stop',seconds=p[2]});cursor=cursor+1
          elseif code==123 then
            parameters(cmd,2,slot); shape(p[1]=="A" or p[1]=="B" or p[1]=="C" or p[1]=="D","Self-switch key must be A/B/C/D",slot)
            enum(p[2],0,1,slot); emit("self_switch",slot,{key=p[1],value=p[2]==0}); cursor=cursor+1
          elseif code==125 or code==126 or code==127 or code==128 then
            local count=code==125 and 3 or (code==126 and 4 or 5)
            parameters(cmd,count,slot)
            local offset=code==125 and 0 or 1
            enum(p[offset+1],0,1,slot)
            local value=operand(p[offset+2],p[offset+3],slot)
            local fields={operation=p[offset+1],operand=value}
            if code~=125 then
              local names={[126]="Items",[127]="Weapons",[128]="Armors"}
              local kinds={[126]="item",[127]="weapon",[128]="armor"}
              fields.id=databaseReference(names[code],p[1],slot); fields.itemKind=kinds[code]
              if code~=126 then shape(type(p[5])=="boolean","Include equipped must be boolean",slot) end
              fields.includeEquip=code~=126 and p[5] or false
            end
            emit(code==125 and "gold" or "inventory",slot,fields); cursor=cursor+1
          elseif code==129 then
            parameters(cmd,3,slot); databaseReference("Actors",p[1],slot); enum(p[2],0,1,slot)
            shape(type(p[3])=="boolean","Actor initialization option must be boolean",slot)
            emit("party_member",slot,{id=p[1],remove=p[2]==1,initialize=p[2]==0 and p[3]}); cursor=cursor+1
          elseif code==301 then battle(indent,depth)
          elseif code==302 then
            parameters(cmd,5,slot);shape(type(p[5])=='boolean','Purchase only must be boolean',slot)
            local goods=json.array();local function good(params,at)
              enum(params[1],0,2,at);enum(params[3],0,1,at)
              local names={'Items','Weapons','Armors'};local kinds={'item','weapon','armor'}
              local id=databaseReference(names[params[1]+1],params[2],at)
              shape(integer(params[4]) and params[4]>=0,'Shop price must be a nonnegative safe integer',at)
              goods[#goods+1]=json.object({kind=kinds[params[1]+1],id=id,price=params[3]==1 and params[4] or nil})
            end
            good(p,slot);local purchaseOnly=p[5];cursor=cursor+1
            while cursor<=#list and list[cursor].code==605 do
              local follow=list[cursor];structure(follow.indent==indent,'Shop goods indentation differs',cursor)
              good(parameters(follow,4,cursor),cursor);cursor=cursor+1
            end
            emit('shop',slot,{goods=goods,purchaseOnly=purchaseOnly})
          elseif code==241 or code==245 or code==249 or code==250 or code==132 or code==133 or code==139 then
            parameters(cmd,1,slot);local cue=p[1]
            shape(object(cue) and type(cue.name)=='string','Audio requires a source audio object',slot)
            shape(integer(cue.volume) and cue.volume>=0 and cue.volume<=100,'Audio volume must be 0..100',slot)
            shape(integer(cue.pitch) and cue.pitch>=50 and cue.pitch<=150,'Audio pitch must be 50..150',slot)
            shape(integer(cue.pan) and cue.pan>=-100 and cue.pan<=100,'Audio pan must be -100..100',slot)
            local channels={[241]='bgm',[245]='bgs',[249]='me',[250]='se',[132]='bgm',[133]='me',[139]='me'}
            emit('audio',slot,{action=code<200 and 'system' or 'play',channel=channels[code],cue=clone(cue),
              field=({[132]='battleBgm',[133]='victoryMe',[139]='defeatMe'})[code]});cursor=cursor+1
          elseif code==242 or code==246 then
            parameters(cmd,1,slot);shape(integer(p[1]) and p[1]>=0,'Audio fade seconds must be nonnegative',slot)
            emit('audio',slot,{action='fade',channel=code==242 and 'bgm' or 'bgs',seconds=p[1]});cursor=cursor+1
          elseif code==243 or code==244 or code==251 then
            parameters(cmd,0,slot);emit('audio',slot,{action=code==243 and 'save' or code==244 and 'replay' or 'stop',channel=code==251 and 'se' or 'bgm'});cursor=cursor+1
          elseif code==331 or code==332 or code==342 then
            parameters(cmd,code==331 and 5 or 4,slot)
            shape(integer(p[1]) and p[1]>=-1,"Enemy selector must be a safe integer >= -1",slot)
            enum(p[2],0,1,slot)
            local fields={enemyIndex=p[1],operation=p[2],operand=operand(p[3],p[4],slot)}
            if code==331 then shape(type(p[5])=="boolean","Allow death must be boolean",slot);fields.allowDeath=p[5] end
            emit(({[331]="enemy_hp",[332]="enemy_mp",[342]="enemy_tp"})[code],slot,fields);cursor=cursor+1
          elseif code==333 then
            parameters(cmd,3,slot);shape(integer(p[1]) and p[1]>=-1,"Enemy selector must be a safe integer >= -1",slot)
            enum(p[2],0,1,slot);databaseReference("States",p[3],slot)
            emit("enemy_state",slot,{enemyIndex=p[1],operation=p[2],stateId=p[3]});cursor=cursor+1
          elseif code==334 or code==335 then
            parameters(cmd,1,slot);shape(integer(p[1]) and p[1]>=-1,"Enemy selector must be a safe integer >= -1",slot)
            emit(code==334 and "enemy_recover" or "enemy_appear",slot,{enemyIndex=p[1]});cursor=cursor+1
          elseif code==336 then
            parameters(cmd,2,slot);shape(integer(p[1]) and p[1]>=-1,"Enemy selector must be a safe integer >= -1",slot)
            databaseReference("Enemies",p[2],slot)
            emit('enemy_transform',slot,{enemyIndex=p[1],enemyId=p[2]});cursor=cursor+1
          elseif code==337 then
            parameters(cmd,3,slot);shape(integer(p[1]) and p[1]>=-1,"Enemy selector must be a safe integer >= -1",slot)
            databaseReference("Animations",p[2],slot);shape(type(p[3])=="boolean","All enemies must be boolean",slot)
            emit("enemy_animation",slot,{enemyIndex=p[1],animationId=p[2],allEnemies=p[3]});cursor=cursor+1
          elseif code==339 then
            parameters(cmd,4,slot);enum(p[1],0,1,slot)
            shape(integer(p[2]) and p[2]>=(p[1]==0 and -1 or 0),"Forced battler selector is outside its safe integer range",slot)
            if p[1]==1 and p[2]>0 then databaseReference("Actors",p[2],slot) end
            databaseReference("Skills",p[3],slot)
            shape(integer(p[4]) and p[4]>=-2,"Forced target selector must be a safe integer >= -2",slot)
            emit("force_action",slot,{battlerType=p[1],battlerId=p[2],skillId=p[3],targetIndex=p[4]});cursor=cursor+1
          elseif code==340 then
            parameters(cmd,0,slot);emit("abort_battle",slot);cursor=cursor+1
          elseif code==311 or code==312 or code==313 or code==317 or code==318 or code==326 then
            parameters(cmd,(code==311 or code==317) and 6 or (code==313 or code==318) and 4 or 5,slot)
            enum(p[1],0,1,slot)
            if p[1]==0 then shape(integer(p[2]) and p[2]>=0,'Invalid actor selector',slot);if p[2]>0 then databaseReference('Actors',p[2],slot)end
            else reference('variables',p[2],slot)end
            local fields={actorMode=p[1],actorSelector=p[2]}
            if code==313 or code==318 then
              enum(p[3],0,1,slot);fields.operation=p[3]
              local key=code==313 and 'stateId' or 'skillId';fields[key]=databaseReference(code==313 and 'States' or 'Skills',p[4],slot)
            else
              local offset=code==317 and 1 or 0
              enum(p[3+offset],0,1,slot);fields.operation=p[3+offset];fields.operand=operand(p[4+offset],p[5+offset],slot)
              if code==317 then enum(p[3],0,7,slot);fields.paramId=p[3]end
              if code==311 then shape(type(p[6])=='boolean','Allow death must be boolean',slot);fields.allowDeath=p[6]end
            end
            emit(({[311]='actor_hp',[312]='actor_mp',[313]='actor_state',[317]='actor_param',[318]='actor_skill',[326]='actor_tp'})[code],slot,fields);cursor=cursor+1
          elseif code==319 then
            parameters(cmd,3,slot);databaseReference('Actors',p[1],slot)
            enum(p[2],1,object(system) and array(system.equipTypes) and #system.equipTypes-1 or 1000,slot);enum(p[3],0,maxInteger,slot)
            emit('change_equipment',slot,{actorId=p[1],slot=p[2],itemId=p[3]});cursor=cursor+1
          elseif code==320 or code==324 or code==325 then
            parameters(cmd,2,slot);databaseReference('Actors',p[1],slot)
            emit('actor_text',slot,{actorId=p[1],field=({[320]='name',[324]='nickname',[325]='profile'})[code],value=text(p[2],slot,true)});cursor=cursor+1
          elseif code==281 then
            parameters(cmd,1,slot);enum(p[1],0,1,slot);emit('map_name',slot,{enabled=p[1]==0});cursor=cursor+1
          elseif code==282 then
            parameters(cmd,1,slot);databaseReference('Tilesets',p[1],slot);emit('tileset',slot,{id=p[1]});cursor=cursor+1
          elseif code==283 then
            parameters(cmd,2,slot);emit('battle_background',slot,{name1=text(p[1],slot,true),name2=text(p[2],slot,true)});cursor=cursor+1
          elseif code==138 then
            parameters(cmd,1,slot);shape(array(p[1]) and #p[1]==4,'Window tone requires four source channels',slot)
            for i,v in ipairs(p[1])do enum(v,i==4 and 0 or -255,255,slot)end
            emit('window_tone',slot,{tone=clone(p[1])});cursor=cursor+1
          elseif code==322 then
            parameters(cmd,6,slot);databaseReference('Actors',p[1],slot);text(p[2],slot,true);enum(p[3],0,7,slot);text(p[4],slot,true);enum(p[5],0,7,slot);text(p[6],slot,true)
            emit('actor_image',slot,{actorId=p[1],characterName=p[2],characterIndex=p[3],faceName=p[4],faceIndex=p[5],battlerName=p[6]});cursor=cursor+1
          elseif code==323 then
            parameters(cmd,3,slot);enum(p[1],0,2,slot);text(p[2],slot,true);enum(p[3],0,7,slot)
            emit('vehicle_image',slot,{vehicleType=p[1],characterName=p[2],characterIndex=p[3]});cursor=cursor+1
          elseif code==140 then
            parameters(cmd,2,slot);enum(p[1],0,2,slot);shape(object(p[2]),'Vehicle audio requires a cue',slot)
            emit('vehicle_bgm',slot,{vehicleType=p[1],cue=clone(p[2])});cursor=cursor+1
          elseif code==204 then
            parameters(cmd,index.engineProfile=='mv-turn' and 3 or 4,slot)
            shape(p[1]==2 or p[1]==4 or p[1]==6 or p[1]==8,'Invalid scroll direction',slot);enum(p[2],0,100000,slot);enum(p[3],1,6,slot)
            if index.engineProfile~='mv-turn'then shape(type(p[4])=='boolean','Scroll wait must be boolean',slot)end
            emit('scroll_map',slot,{direction=p[1],distance=p[2],speed=p[3],wait=p[4]==true});cursor=cursor+1
          elseif code==284 then
            parameters(cmd,5,slot);text(p[1],slot,true)
            shape(type(p[2])=='boolean' and type(p[3])=='boolean','Parallax loop flags must be boolean',slot);enum(p[4],-32768,32768,slot);enum(p[5],-32768,32768,slot)
            emit('parallax',slot,{name=p[1],loopX=p[2],loopY=p[3],sx=p[4],sy=p[5]});cursor=cursor+1
          elseif code==285 then
            parameters(cmd,5,slot);reference('variables',p[1],slot);enum(p[2],0,6,slot);enum(p[3],0,2,slot)
            if p[3]==1 then reference('variables',p[4],slot);reference('variables',p[5],slot)
            else shape(integer(p[4]) and integer(p[5]),'Location coordinates must be integers',slot);if p[3]==2 then enum(p[4],-1,maxInteger,slot)end end
            emit('location_info',slot,{variableId=p[1],kind=p[2],mode=p[3],x=p[4],y=p[5]});cursor=cursor+1
          elseif code==351 then
            parameters(cmd,0,slot);emit('open_menu',slot);cursor=cursor+1
          elseif code==321 then
            parameters(cmd,3,slot);databaseReference('Actors',p[1],slot);databaseReference('Classes',p[2],slot)
            shape(type(p[3])=='boolean','Keep EXP must be boolean',slot)
            emit('actor_class',slot,{actorMode=0,actorSelector=p[1],classId=p[2],keepExp=p[3]});cursor=cursor+1
          elseif code==314 or code==315 or code==316 then
            parameters(cmd,code==314 and 2 or 6,slot); enum(p[1],0,1,slot)
            if p[1]==0 then
              shape(integer(p[2]) and p[2]>=0,"Actor selector must be a nonnegative safe integer",slot)
              if p[2]>0 then databaseReference("Actors",p[2],slot) end
            else reference("variables",p[2],slot) end
            local fields={actorMode=p[1],actorSelector=p[2]}
            if code~=314 then
              enum(p[3],0,1,slot); fields.operation=p[3]; fields.operand=operand(p[4],p[5],slot)
              shape(type(p[6])=="boolean","Show level up option must be boolean",slot)
              fields.showLevelUp=p[6]
            end
            local ops={[314]="actor_recover",[315]="actor_exp",[316]="actor_level"}
            emit(ops[code],slot,fields); cursor=cursor+1
          elseif code==214 then
            parameters(cmd,0,slot); emit("erase_event",slot); cursor=cursor+1
          elseif code==201 then
            parameters(cmd,6,slot); enum(p[1],0,1,slot)
            if p[1]==0 then
              local found
              for _,map in ipairs(index.maps) do if map.id==p[2] then found=map end end
              if not found then errorAt("E_EVENT_REFERENCE","Transfer map does not exist",slot) end
              shape(integer(p[3]) and p[3]>=0 and p[3]<found.width and integer(p[4]) and p[4]>=0 and p[4]<found.height,"Transfer coordinate outside target map",slot)
            else for i=2,4 do reference("variables",p[i],slot) end end
            shape(p[5]==0 or p[5]==2 or p[5]==4 or p[5]==6 or p[5]==8,"Transfer direction must be retained or cardinal",slot)
            enum(p[6],0,2,slot)
            emit("transfer",slot,{mode=p[1],mapId=p[2],x=p[3],y=p[4],direction=p[5],fade=p[6]}); cursor=cursor+1
          elseif code==202 then
            parameters(cmd,5,slot);enum(p[1],0,2,slot);enum(p[2],0,1,slot)
            if p[2]==1 then for i=3,5 do reference('variables',p[i],slot)end
            else for i=3,5 do shape(integer(p[i]),'Vehicle position must use integers',slot)end end
            emit('vehicle_location',slot,{vehicleType=p[1],mode=p[2],mapId=p[3],x=p[4],y=p[5]});cursor=cursor+1
          elseif code==206 then parameters(cmd,0,slot);emit('vehicle_toggle',slot);cursor=cursor+1
          elseif code==136 then parameters(cmd,1,slot);enum(p[1],0,1,slot);emit('encounters',slot,{enabled=p[1]==1});cursor=cursor+1
          elseif code==135 or code==137 then
            parameters(cmd,1,slot);enum(p[1],0,1,slot)
            emit('access',slot,{target=code==135 and 'menu' or 'formation',enabled=p[1]==1});cursor=cursor+1
          elseif code==205 then
            parameters(cmd,2,slot);shape(integer(p[1]) and p[1]>=-1,'Invalid route character selector',slot)
            emit('move_route',slot,{characterId=p[1],route=movement.compile(p[2],source(slot))});cursor=cursor+1
            -- 505 duplicates the route for the editor. Never execute it twice.
            local routeIndex=1
            while list[cursor] and list[cursor].code==505 do
              structure(list[cursor].indent==indent,'Movement continuation indentation mismatch',cursor)
              local cp=parameters(list[cursor],1,cursor)
              local original=p[2].list[routeIndex]
              shape(object(cp[1]) and original and original.code~=0 and json.encode(cp[1])==json.encode(original),
                'Movement continuation differs from its route',cursor)
              routeIndex=routeIndex+1;cursor=cursor+1
            end
          elseif code==203 then
            parameters(cmd,5,slot);shape(integer(p[1]) and p[1]>=0,'Invalid event selector',slot);enum(p[2],0,2,slot)
            if p[2]==1 then reference('variables',p[3],slot);reference('variables',p[4],slot)
            else shape(integer(p[3]) and integer(p[4]),'Event location requires integer values',slot)end
            shape(p[5]==0 or p[5]==2 or p[5]==4 or p[5]==6 or p[5]==8,'Invalid event location direction',slot)
            emit('event_location',slot,{eventId=p[1],mode=p[2],x=p[3],y=p[4],direction=p[5]});cursor=cursor+1
          elseif code==211 or code==216 then
            parameters(cmd,1,slot);enum(p[1],0,1,slot)
            emit(code==211 and 'transparency' or 'followers',slot,code==211 and {transparent=p[1]==0} or {visible=p[1]==0});cursor=cursor+1
          elseif code==217 then
            parameters(cmd,0,slot);emit('gather_followers',slot);cursor=cursor+1
          elseif code==221 or code==222 then
            parameters(cmd,0,slot);emit('screen',slot,{action='fade',brightness=code==221 and 0 or 255,duration=24,wait=true});cursor=cursor+1
          elseif code==223 or code==224 then
            parameters(cmd,3,slot);shape(array(p[1]) and #p[1]==4,'Tone/color must have four channels',slot)
            for i,v in ipairs(p[1])do enum(v,code==223 and i<4 and -255 or 0,255,slot)end
            enum(p[2],0,360000,slot);shape(type(p[3])=='boolean','Presentation wait must be boolean',slot)
            local fields={action=code==223 and 'tint' or 'flash',duration=p[2],wait=p[3]};fields[code==223 and 'tone' or 'color']=clone(p[1])
            emit('screen',slot,fields);cursor=cursor+1
          elseif code==225 then
            parameters(cmd,4,slot);enum(p[1],0,9,slot);enum(p[2],0,9,slot);enum(p[3],0,360000,slot);shape(type(p[4])=='boolean','Shake wait must be boolean',slot)
            emit('screen',slot,{action='shake',power=p[1],speed=p[2],duration=p[3],wait=p[4]});cursor=cursor+1
          elseif code==236 then
            parameters(cmd,4,slot);shape(p[1]=='none' or p[1]=='rain' or p[1]=='storm' or p[1]=='snow','Invalid weather kind',slot)
            enum(p[2],0,9,slot);enum(p[3],0,360000,slot);shape(type(p[4])=='boolean','Weather wait must be boolean',slot)
            emit('screen',slot,{action='weather',kind=p[1],power=p[1]=='none' and 0 or p[2],duration=p[3],wait=p[4]});cursor=cursor+1
          elseif code==231 or code==232 then
            shape(code==231 and #p==10 or code==232 and (#p==12 or #p==13),'Picture command parameter count differs',slot)
            enum(p[1],1,100,slot);enum(p[3],0,1,slot);enum(p[4],0,1,slot)
            if p[4]==1 then reference('variables',p[5],slot);reference('variables',p[6],slot)
            else shape(integer(p[5]) and integer(p[6]),'Picture position must be safe integers',slot)end
            enum(p[7],-10000,10000,slot);enum(p[8],-10000,10000,slot);enum(p[9],0,255,slot);enum(p[10],0,3,slot)
            local fields={id=p[1],action=code==231 and 'show' or 'move',origin=p[3],mode=p[4],x=p[5],y=p[6],scaleX=p[7],scaleY=p[8],opacity=p[9],blend=p[10]}
            if code==231 then shape(type(p[2])=='string','Picture name must be text',slot);fields.name=p[2]
            else enum(p[11],0,360000,slot);shape(type(p[12])=='boolean','Picture wait must be boolean',slot);enum(p[13] or 0,0,3,slot);fields.duration,fields.wait,fields.easing=p[11],p[12],p[13] or 0 end
            emit('picture',slot,fields);cursor=cursor+1
          elseif code==233 then
            parameters(cmd,2,slot);enum(p[1],1,100,slot);enum(p[2],-90,90,slot)
            emit('picture',slot,{action='rotate',id=p[1],speed=p[2]});cursor=cursor+1
          elseif code==234 then
            parameters(cmd,4,slot);enum(p[1],1,100,slot);shape(array(p[2]) and #p[2]==4,'Picture tone requires four channels',slot)
            for i,v in ipairs(p[2])do enum(v,i<4 and -255 or 0,255,slot)end;enum(p[3],0,360000,slot);shape(type(p[4])=='boolean','Picture wait must be boolean',slot)
            emit('picture',slot,{action='tint',id=p[1],tone=clone(p[2]),duration=p[3],wait=p[4]});cursor=cursor+1
          elseif code==235 then
            parameters(cmd,1,slot);enum(p[1],1,100,slot);emit('picture',slot,{action='erase',id=p[1]});cursor=cursor+1
          elseif code==212 or code==213 then
            parameters(cmd,3,slot);shape(integer(p[1]) and p[1]>=-1,'Invalid character selector',slot)
            if code==212 then databaseReference('Animations',p[2],slot)else enum(p[2],1,15,slot)end
            shape(type(p[3])=='boolean','Animation wait must be boolean',slot)
            local fields={characterId=p[1],wait=p[3]};fields[code==212 and 'animationId' or 'balloonId']=p[2]
            emit(code==212 and 'animation' or 'balloon',slot,fields);cursor=cursor+1
          elseif code==261 then
            parameters(cmd,1,slot);shape(type(p[1])=='string' and #p[1]<=1024 and not p[1]:find('[%z\r\n]'),'Video name must be bounded text',slot)
            if p[1]==''then emit('nop',slot)else emit('video',slot,{name=p[1]})end;cursor=cursor+1
          elseif code==230 then
            parameters(cmd,1,slot); shape(integer(p[1]) and p[1]>=0,"Wait frames must be a nonnegative safe integer",slot)
            emit("wait",slot,{frames=p[1]}); cursor=cursor+1
          else errorAt("E_EVENT_UNSUPPORTED","Unsupported RPG Maker command "..code,slot) end
        end
      end
      block(0,0)
      local _,ending=emit("return",math.max(1,#list)); ending.source.synthetic=true
      if #list==0 then ending.source.jsonPath=path end
      for _,jump in ipairs(labelJumps)do
        if labels[jump.name]then jump.instruction.target=labels[jump.name]
        else jump.instruction.op='nop'end
      end
      for _,ins in ipairs(out) do if ins.op=='dialogue' then
        local ok,tokens=pcall(messageCompiler.compile,ins.lines,index.engineProfile=='mv-turn' and 'mv-1.5.1' or 'mz-1.10.0',index.visuWorld)
        if not ok then fail(type(tokens)=='table' and tokens.code or 'E_UI_MESSAGE_CONTROL',type(tokens)=='table' and tokens.reason or tostring(tokens),file,ins.source.jsonPath) end
        ins.flowTokens=json.array(tokens)
        if ins.speaker~='' then
          local valid,speaker=pcall(messageCompiler.compile,{ins.speaker},index.engineProfile=='mv-turn' and 'mv-1.5.1' or 'mz-1.10.0',index.visuWorld)
          if not valid then fail(type(speaker)=='table' and speaker.code or 'E_UI_MESSAGE_CONTROL',type(speaker)=='table' and speaker.reason or tostring(speaker),file,ins.source.jsonPath)end
          ins.speakerTokens=json.array(speaker)
        end
        if ins.choices then
          ins.choiceTokens=json.array()
          if ins.extendedChoices then ins.choiceEnabled=json.array()end
          for i,label in ipairs(ins.choices)do
            if ins.extendedChoices then
              ins.choiceEnabled[i]=not label:lower():find('<disable>',1,true)
              label=label:gsub('<[Dd][Ii][Ss][Aa][Bb][Ll][Ee]>',''):gsub('</?[Cc][Oo][Ll][Oo][Rr][Ll][Oo][Cc][Kk]>','')
              ins.choices[i]=label
            end
            local valid,choice=pcall(messageCompiler.compile,{label},index.engineProfile=='mv-turn' and 'mv-1.5.1' or 'mz-1.10.0',index.visuWorld)
            if not valid then fail(type(choice)=='table' and choice.code or 'E_UI_MESSAGE_CONTROL',type(choice)=='table' and choice.reason or tostring(choice),file,ins.source.jsonPath)end
            ins.choiceTokens[i]=json.array(choice)
          end
        end
      end end
      return json.object({id=spec.id,context=spec.context,instructions=out})
    end
    for _,spec in ipairs(specs) do
      local ok,result=pcall(compileProgram,spec)
      if ok then programs[spec.id]=result
      elseif diagnostic.is(result) then diagnostics[#diagnostics+1]=result
      else error(result,0) end
    end
    return finish()
  end
  return {compile=compile}
end
