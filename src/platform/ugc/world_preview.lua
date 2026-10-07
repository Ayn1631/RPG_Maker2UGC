-- Diagnostic map presentation; full source art reconstruction is a separate renderer.
return function(deps)
    local textLimit=deps['runtime.ui.text_limit']
    local sceneModule=deps["runtime.ui.world_scene"]
    local mapModule=deps["runtime.world.map"]
    local M={}
    function M.open(host,data,identity,createWorld)
        if not host or not host.game or not host.script or not host.script.object or not data.worldPreview then
            error({severity="error",code="E_PLATFORM_NOT_CONFIGURED",reason="World preview requires a host and template bindings"},0)
        end
        local game,script,enum,color=host.game,host.script,host.Enum,host.Color
        local root,bindings=script.object,data.worldPreview
        local owned,listeners,buttons={}, {},{}
        local scene=sceneModule.new(createWorld)
        local active,remainder,mapId,epoch=true,0,nil,1
        local tileControls,eventControls={},{}
        local player,status,body,bag,title,subtitle
        local choices,confirm,cancel,bagButton={},nil,nil,nil
        local partyButton,partyList,partyDetail,recoverButton,previousActor,nextActor
        local mapButtons={}
        local cell,left,top
        local currentToken,currentScene,currentPartyToken
        local oldCursor=root.showCursor
        local controller={}
        local function rgb(r,g,b,a) return color.FromRGBA(r,g,b,a or 255) end
        local function create(template,name,x,y,w,h,parent)
            parent=parent or root
            local object=game.InstantiateClientUIControl(template,parent)
            if not object then error({severity="error",code="E_PLATFORM_TEMPLATE",reason="Missing template "..template},0) end
            if parent==root then owned[#owned+1]=object end
            object.name=name
            object:SetAnchorMin(0.5,0.5); object:SetAnchorMax(0.5,0.5); object:SetPivot(0.5,0.5)
            object:SetAnchoredPosition(x,y); object:SetSizeDelta(w,h); object:SetActive(true); object:SetVisible(true)
            return object
        end
        local function text(name,value,x,y,w,h,size,parent)
            size=math.max(1,math.floor(size))
            local object=create(bindings.textTemplate,name,x,y,w,h,parent)
            object.text,object.fontSize=textLimit.clip(value),size
            object.fontColor,object.bgColor=rgb(234,240,246),rgb(0,0,0,0)
            object.horizontalAlignment=enum.TextHorizontalAlignment.Middle; object.verticalAlignment=enum.TextVerticalAlignment.Middle
            object.adaptiveFontSize,object.minimumFontSize=true,math.max(12,size-5)
            return object
        end
        local function write(object,value)value=textLimit.clip(value);if object.text~=value then object.text=value end end
        local render
        local function dispatch(action)
            if not active then return end
            scene.dispatch(action); render()
        end
        local function bind(button,action)
            if button.callback then button.object:RemoveCursorEventListener(enum.CursorEventType.CursorClick,button.callback) end
            local generation=epoch
            button.callback=function() if active and generation==epoch then dispatch(action) end end
            button.object:AddCursorEventListener(enum.CursorEventType.CursorClick,button.callback)
        end
        local function button(name,label,x,y,w,action)
            local object=create(bindings.buttonTemplate,name,x,y,w,44)
            object.interactable,object.raycastTarget=true,true
            local value={object=object,label=text(name.." label",label,0,0,w-12,42,18,object)}
            buttons[#buttons+1]=value
            if action then bind(value,action) end
            return value
        end
        local function visible(button,show)
            button.object:SetVisible(show); button.object.interactable=show
        end
        local function buildMap(map)
            mapId=map.id
            for _,object in ipairs(tileControls) do if object.alive then game.DestroyClientUIControl(object) end end
            tileControls={}
            local live={}; for _,object in ipairs(owned) do if object.alive then live[#live+1]=object end end; owned=live
            cell=math.min(60,660/map.width,360/map.height)
            left=-235-map.width*cell/2+cell/2; top=100+map.height*cell/2-cell/2
            local rules=mapModule.new(map)
            for y=0,map.height-1 do
                for x=0,map.width-1 do
                    local object=text("R2U tile "..x..":"..y,"",left+x*cell,top-y*cell,cell-2,cell-2,14)
                    local walk=rules.isPassable(x,y,2) or rules.isPassable(x,y,4) or rules.isPassable(x,y,6) or rules.isPassable(x,y,8)
                    object.bgColor=walk and rgb(42,74,83) or rgb(49,54,68)
                    tileControls[#tileControls+1]=object
                end
            end
            player:SetAsLastSibling()
        end
        render=function()
            local view=scene.view()
            if view.mapId~=mapId then buildMap(scene.mapData()) end
            local p=view.player
            player:SetAnchoredPosition(left+p.realX*cell,top-p.realY*cell)
            player:SetSizeDelta(cell-8,cell-8)
            write(player,({[2]="下",[4]="左",[6]="右",[8]="上"})[p.direction])
            for _,object in pairs(eventControls) do object:SetVisible(false) end
            for _,event in ipairs(view.events) do
                if event.page then
                    local object=eventControls[event.id]
                    if not object then
                        object=text("R2U event "..event.id,"",0,0,cell-6,cell-6,16)
                        eventControls[event.id]=object
                    end
                    object:SetSizeDelta(cell-6,cell-6); object:SetAnchoredPosition(left+event.x*cell,top-event.y*cell)
                    object.bgColor=event.through and rgb(53,93,73) or rgb(123,89,42)
                    write(object,event.name); object:SetVisible(true)
                end
            end
            player:SetAsLastSibling()
            write(status,"地图 "..view.mapId.."   位置 ("..p.x..","..p.y..")   步数 "..view.steps.."\n"..(view.busy and "事件处理中" or "可以移动与交互"))
            local inventory={"金币 "..view.party.gold}
            for _,pair in ipairs({{"items","item"},{"weapons","weapon"},{"armors","armor"}}) do
                for _,record in ipairs(data.world.definitions[pair[1]]) do
                    local count=view.party.inventory[pair[2]][record.id] or 0
                    if count>0 then inventory[#inventory+1]=record.name.." × "..string.format("%.0f",count) end
                end
            end
            if #inventory==1 then inventory[2]="背包为空" end
            write(bag,table.concat(inventory,"\n"))
            local message=view.message
            bag:SetVisible(not message or not message.choices or #message.choices<=3)
            local token=message and (message.generation..":"..message.token) or false
            if token~=currentToken or view.scene~=currentScene then
                currentToken,currentScene=token,view.scene
                for _,choice in ipairs(choices) do visible(choice,false) end
                visible(confirm,false); visible(cancel,false)
                if view.scene~="party" then bind(bagButton,{kind="bag"}) end
                if view.scene=="bag" then
                    write(body,"背包已打开\n地图和事件暂停。\n点击返回地图继续。")
                elseif message then
                    write(body,(message.speaker~="" and message.speaker.."\n" or "")..table.concat(message.lines,"\n"))
                    if message.choices then
                        for index,label in ipairs(message.choices) do
                            local choice=choices[index]; write(choice.label,label); visible(choice,true)
                            bind(choice,{kind="answer",generation=message.generation,taskId=message.taskId,token=message.token,answer={kind="choice",index=index-1}})
                        end
                        if message.cancelChoice~=-1 then
                            visible(cancel,true)
                            bind(cancel,{kind="answer",generation=message.generation,taskId=message.taskId,token=message.token,answer={kind="cancel"}})
                        end
                    else
                        visible(confirm,true)
                        bind(confirm,{kind="answer",generation=message.generation,taskId=message.taskId,token=message.token,answer={kind="confirm"}})
                    end
                else write(body,"方向按钮移动。\n接近事件后点击交互。\n打开背包查看当前物品。") end
            end
            if message and message.choices then
                for index,label in ipairs(message.choices) do
                    write(choices[index].label,(message.selectedChoice==index-1 and "> " or "")..label)
                end
            end
            local partyOpen=view.scene=="party"
            write(bagButton.label,view.scene~="map" and "返回地图" or "打开背包")
            if partyButton then
                visible(partyButton,not partyOpen and not message and #view.party.members>0)
                partyList:SetVisible(partyOpen);partyDetail:SetVisible(partyOpen)
                visible(recoverButton,partyOpen);visible(previousActor,partyOpen);visible(nextActor,partyOpen)
                for _,object in ipairs(tileControls)do object:SetVisible(not partyOpen)end
                if partyOpen then for _,object in pairs(eventControls)do object:SetVisible(false)end end
                player:SetVisible(not partyOpen);status:SetVisible(not partyOpen);body:SetVisible(not partyOpen)
                if partyOpen then bag:SetVisible(false)end
                for _,b in ipairs(mapButtons)do visible(b,not partyOpen)end
                if partyOpen and view.partyActor then
                    local function definition(kind,id)
                        for _,record in ipairs(data.rpg[kind])do if record.id==id then return record end end
                    end
                    local lines={"队伍状态"}
                    for i,id in ipairs(view.party.members)do lines[#lines+1]=(i==view.partyIndex and "> " or "  ")..definition("actors",id).name end
                    write(partyList,table.concat(lines,"\n\n"))
                    local a=view.partyActor;local s=a.state;local stats=a.stats.params
                    local n=function(value)return string.format("%.0f",value)end
                    local detail={definition("actors",s.actorId).name.."  Lv."..n(s.level).."  "..definition("classes",s.classId).name,
                        "HP "..n(s.hp).." / "..n(stats[1]).."    MP "..n(s.mp).." / "..n(stats[2]).."    TP "..n(s.tp),
                        "攻击 "..n(stats[3]).."    防御 "..n(stats[4]),"魔攻 "..n(stats[5]).."    魔防 "..n(stats[6]),
                        "敏捷 "..n(stats[7]).."    幸运 "..n(stats[8]),"装备"}
                    for slot,item in ipairs(a.equipment)do
                        local value=item~=false and definition(item.kind=="weapon" and "weapons" or "armors",item.id).name or "—"
                        detail[#detail+1]=data.rpg.system.equipTypes[a.equipmentSlots[slot]+1].."："..value
                    end
                    write(partyDetail,table.concat(detail,"\n"))
                    local key=view.partyToken..":"..s.actorId
                    if key~=currentPartyToken then
                        currentPartyToken=key
                        bind(recoverButton,{kind="actor_recover",token=view.partyToken,actorId=s.actorId})
                        bind(previousActor,{kind="party_navigate",token=view.partyToken,direction=8})
                        bind(nextActor,{kind="party_navigate",token=view.partyToken,direction=2})
                        bind(bagButton,{kind="party_back",token=view.partyToken})
                    end
                else currentPartyToken=nil
                end
            end
            if #view.errors>0 then
                local reason=view.errors[#view.errors]
                write(body,reason.code.."\n"..reason.reason.."\n"..(reason.file or "").." "..(reason.jsonPath or ""))
            end
        end
        function controller.update(dt)
            if not active then return end
            if type(dt)~="number" or dt~=dt or dt<0 or dt==math.huge then error("Invalid preview dt") end
            remainder=remainder+dt*60
            local frames=math.floor(remainder+0.000000001); remainder=remainder-frames
            scene.tick(frames); render()
        end
        function controller.close(destroy)
            if not active then return end
            active=false; epoch=epoch+1; scene.close()
            for _,button in ipairs(buttons) do
                if button.callback and button.object.alive then button.object:RemoveCursorEventListener(enum.CursorEventType.CursorClick,button.callback) end
            end
            if root.alive then
                for _,listener in ipairs(listeners) do root:RemoveKeyEventListener(listener.kind,listener.callback) end
                root.showCursor=oldCursor
            end
            if destroy then
                script:EnableUpdate(false)
                for index=#owned,1,-1 do if owned[index].alive then game.DestroyClientUIControl(owned[index]) end end
            end
        end
        local ok,reason=pcall(function()
            root.showCursor=true
            local width,height=game.GetUICanvasSize(); local scale=math.min(width/1200,height/820)
            root:SetAnchorMin(0.5,0.5); root:SetAnchorMax(0.5,0.5); root:SetPivot(0.5,0.5)
            root:SetAnchoredPosition(0,0); root:SetSizeDelta(1200,820); root:SetLocalScale(scale,scale,1)
            local background=text("R2U world background","",0,0,1200,820,14); background.bgColor=rgb(15,22,36)
            title=text("R2U world title","地图与事件试玩",0,358,1100,52,30); title.fontColor=rgb(111,224,202)
            subtitle=text("R2U world build","逻辑验收视图 · "..data.engineProfile.." · "..identity:sub(1,12),0,320,1100,30,15)
            body=text("R2U world message","",367,188,350,184,22)
            bag=text("R2U inventory","",367,-208,350,146,18)
            status=text("R2U world status","",-235,-138,680,64,18)
            player=text("R2U player","右",0,0,48,48,28); player.bgColor=rgb(56,167,143)
            for index=1,6 do choices[index]=button("R2U world choice "..(index-1),"",367,60-(index-1)*45,330) end
            confirm=button("R2U world continue","继续",367,60,330)
            cancel=button("R2U world cancel","取消",367,-255,330)
            mapButtons[1]=button("R2U move up","上",-235,-218,96,{kind="navigate",direction=8})
            mapButtons[2]=button("R2U move left","左",-341,-272,96,{kind="navigate",direction=4})
            mapButtons[3]=button("R2U move down","下",-235,-272,96,{kind="navigate",direction=2})
            mapButtons[4]=button("R2U move right","右",-129,-272,96,{kind="navigate",direction=6})
            mapButtons[5]=button("R2U interact","交互",-235,-334,302,{kind="confirm"})
            bagButton=button("R2U bag","打开背包",367,-336,330,{kind="bag"})
            if data.rpg then
                partyButton=button("R2U party","队伍状态",367,-104,330,{kind="party"})
                partyList=text("R2U party members","",-355,100,380,380,26)
                partyDetail=text("R2U party detail","",185,80,650,440,24)
                previousActor=button("R2U party previous","上一位",-440,-220,160)
                nextActor=button("R2U party next","下一位",-260,-220,160)
                recoverButton=button("R2U actor recover","完整恢复（测试）",185,-220,300)
            end
            text("R2U world note","WASD / 方向键单步移动，F 确认，E 背包，X 返回。色块仅用于逻辑验收。",0,-392,1120,28,14)
            local keys={
                {"KeyboardMoveForwardKeyDown","navigate",8},{"KeyboardMoveBackwardKeyDown","navigate",2},
                {"KeyboardMoveLeftKeyDown","navigate",4},{"KeyboardMoveRightKeyDown","navigate",6},
                {"KeyboardCraftspersonKey36Down","navigate",8},{"KeyboardCraftspersonKey37Down","navigate",2},
                {"KeyboardCraftspersonKey38Down","navigate",4},{"KeyboardCraftspersonKey39Down","navigate",6},
                {"KeyboardInteractKeyDown","confirm"},{"KeyboardCharacterSkill1KeyDown","bag"},{"KeyboardDropKeyDown","cancel"},
                {"ControllerCharacterSkill3KeyDown","navigate",8},{"ControllerCraftspersonKey2Down","navigate",2},
                {"ControllerCraftspersonKey1Down","navigate",4},{"ControllerCharacterSkill4KeyDown","navigate",6},
                {"ControllerInteractKeyDown","confirm"},{"ControllerMenuConfirmKeyDown","confirm"},
                {"ControllerMenuBackKeyDown","cancel"},{"ControllerCharacterSkill2KeyDown","bag"},
            }
            for _,binding in ipairs(keys) do
                local key=enum.KeyEventType[binding[1]]
                if key==nil then error({severity="error",code="E_PLATFORM_KEY",reason="Missing documented key enum: "..binding[1]},0) end
                local action={kind=binding[2],direction=binding[3]}
                local callback=function() if active then dispatch(action); return true end; return false end
                root:AddKeyEventListener(key,callback); listeners[#listeners+1]={kind=key,callback=callback}
            end
            scene.tick(0); render(); script:EnableUpdate(true)
        end)
        if not ok then controller.close(true); error(reason,0) end
        return controller
    end
    return M
end
