-- Development-only event preview. The host is injected at a lifecycle boundary.
return function(deps)
    local textLimit=deps['runtime.ui.text_limit']
    local M = {}
    local function fail(reason)
        error({severity="error",code="E_PLATFORM_NOT_CONFIGURED",reason=reason}, 0)
    end

    function M.open(host, data, identity, new_session)
        if not host or not host.game or not host.script or not host.script.object
            or not host.Enum or not host.Color or not data.eventPreview then
            fail("Event preview requires a host, root control and explicit eventPreview bindings")
        end
        local game, script, enum, color = host.game, host.script, host.Enum, host.Color
        local root, binding = script.object, data.eventPreview
        local controls, listeners, buttons, controller = {}, {}, {}, {}
        local session, task_id, current_message, current_status
        local alive, generation, remainder, last_token, last_status = true, 0, 0, nil, nil
        local prior_cursor = root.showCursor
        local title, subtitle, message_text, speaker, status_text, state_text, hint

        local function rgb(r,g,b,a) return color.FromRGBA(r,g,b,a or 255) end
        local function positioned(control, x, y, width, height)
            control:SetAnchorMin(0.5,0.5); control:SetAnchorMax(0.5,0.5)
            control:SetPivot(0.5,0.5)
            control:SetAnchoredPosition(x,y); control:SetSizeDelta(width,height)
            control:SetActive(true); control:SetVisible(true)
        end
        local function instance(template, parent, name)
            local control = game.InstantiateClientUIControl(template,parent)
            if not control then fail("Cannot instantiate template " .. tostring(template) .. " for " .. name) end
            if parent == root then controls[#controls + 1] = control end
            control.name = name
            return control
        end
        local function text(name, value, x, y, width, height, size, parent)
            size=math.max(1,math.floor(size))
            local control = instance(binding.textTemplate, parent or root, name)
            positioned(control,x,y,width,height)
            control.text, control.fontSize = textLimit.clip(value), size
            control.fontColor, control.bgColor = rgb(232,239,248), rgb(0,0,0,0)
            control.horizontalAlignment = enum.TextHorizontalAlignment.Middle
            control.verticalAlignment = enum.TextVerticalAlignment.Middle
            control.adaptiveFontSize, control.minimumFontSize = true, math.max(14,size-6)
            return control
        end
        local function write(control, value)
            value=textLimit.clip(value)
            if control.text ~= value then control.text = value end
        end
        local function hide(button, hidden)
            button.control:SetVisible(not hidden)
            button.control.interactable = not hidden
        end
        local function bind(button, callback)
            if button.callback then
                button.control:RemoveCursorEventListener(enum.CursorEventType.CursorClick, button.callback)
            end
            local epoch = generation
            button.callback = function()
                if alive and epoch == generation then callback() end
            end
            button.control:AddCursorEventListener(enum.CursorEventType.CursorClick, button.callback)
        end
        local function button(name, caption, x, y, width)
            local control = instance(binding.buttonTemplate,root,name)
            positioned(control,x,y,width,48)
            control.interactable, control.raycastTarget = true,true
            local label = text(name .. " label",caption,0,0,width-24,44,20,control)
            local item = {control=control,label=label}
            buttons[#buttons + 1] = item
            return item
        end
        local function summary()
            local state = session.getState()
            local values = {}
            for _, category in ipairs({"switches","variables","selfSwitches"}) do
                local keys = {}
                for key in pairs(state[category]) do keys[#keys+1] = key end
                table.sort(keys)
                local fields = {}
                for i=1,math.min(#keys,6) do
                    local key = keys[i]
                    fields[#fields+1] = tostring(key) .. "=" .. tostring(state[category][key])
                end
                local labels = {switches="开关",variables="变量",selfSwitches="独立开关"}
                values[#values+1] = labels[category] .. "  " .. (#fields>0 and table.concat(fields,"   ") or "默认值")
            end
            return table.concat(values,"\n")
        end
        local render, begin
        local choices, confirm, cancel, replay, reset = {},nil,nil,nil,nil
        local function answer(message, response)
            if session.respond(message.taskId,message.token,response) then
                session.tick(0)
                render()
            end
        end
        render = function()
            local task = session.getTask(task_id)
            current_message, current_status = session.getMessage(), task.status
            write(state_text, summary())
            write(status_text, "事件状态 · " .. current_status)
            local token = current_message and current_message.token or false
            if token == last_token and current_status == last_status then return end
            last_token, last_status = token, current_status
            for _, item in ipairs(choices) do hide(item,true) end
            hide(confirm,true); hide(cancel,true)
            hide(replay,current_status~="DONE" and current_status~="ERROR")
            if current_message then
                local message = current_message
                write(speaker, message.speaker~="" and message.speaker or "对话")
                write(message_text, table.concat(message.lines,"\n"))
                if message.choices then
                    write(hint,"选择后继续事件。取消策略由源事件决定。")
                    for index, caption in ipairs(message.choices) do
                        local item = choices[index]
                        write(item.label,caption); hide(item,false)
                        bind(item,function() answer(message,{kind="choice",index=index-1}) end)
                    end
                    if message.cancelChoice ~= -1 then
                        hide(cancel,false)
                        bind(cancel,function() answer(message,{kind="cancel"}) end)
                    end
                else
                    write(hint,"点击继续，或按交互键确认。")
                    hide(confirm,false)
                    bind(confirm,function() answer(message,{kind="confirm"}) end)
                end
            elseif current_status == "ERROR" then
                write(speaker,"事件诊断")
                local err = task.diagnostic
                write(message_text,err.code .. "\n" .. err.reason .. "\n" .. (err.file or "") .. " " .. (err.jsonPath or ""))
                write(hint,"此任务已停止。可重置状态后重新测试。")
            elseif current_status == "DONE" then
                write(speaker,"事件结束")
                write(message_text,"本次事件已执行完成。\n再次触发会保留当前状态，重置状态会开始新会话。")
                write(hint,"此界面用于事件链路验收，尚不包含地图、战斗或存档。")
            else
                write(speaker,"事件运行中")
                write(message_text,"正在等待事件继续…")
                write(hint,"按 60 Hz 逻辑时钟处理等待；渲染帧率不改变等待时长。")
            end
        end
        begin = function(reset_state)
            generation = generation + 1
            if task_id then session.cancel(task_id) end
            if reset_state or not session then session = new_session() end
            task_id, remainder, last_token, last_status = session.start(binding.programId),0,nil,nil
            bind(replay,function() begin(false) end)
            bind(reset,function() begin(true) end)
            session.tick(0)
            render()
        end

        function controller.close(destroy)
            if not alive then return end
            alive, generation = false,generation+1
            if session and task_id then session.cancel(task_id) end
            for _, item in ipairs(buttons) do
                if item.callback and item.control.alive then
                    item.control:RemoveCursorEventListener(enum.CursorEventType.CursorClick,item.callback)
                end
            end
            if root.alive then
                for _, item in ipairs(listeners) do root:RemoveKeyEventListener(item.kind,item.callback) end
                root.showCursor = prior_cursor
            end
            if destroy then
                script:EnableUpdate(false)
                for index=#controls,1,-1 do
                    if controls[index].alive then game.DestroyClientUIControl(controls[index]) end
                end
            end
        end
        function controller.update(dt)
            if not alive then return end
            if type(dt)~="number" or dt~=dt or dt<0 or dt==math.huge then
                error({severity="error",code="E_EVENT_CLOCK",reason="Host dt must be finite nonnegative seconds"},0)
            end
            remainder = remainder + dt*60
            local frames = math.floor(remainder+0.000000001)
            remainder = remainder-frames
            session.tick(frames)
            render()
        end

        local ok, reason = pcall(function()
            root.showCursor = true
            local width,height = game.GetUICanvasSize()
            local scale = math.min(width/1200,height/820)
            root:SetAnchorMin(0.5,0.5); root:SetAnchorMax(0.5,0.5); root:SetPivot(0.5,0.5)
            root:SetAnchoredPosition(0,0); root:SetSizeDelta(1200,820); root:SetLocalScale(scale,scale,1)
            local background = text("R2U background","",0,0,1200,820,16)
            background.bgColor = rgb(15,22,36)
            local card = text("R2U panel","",0,12,1080,620,16)
            card.bgColor = rgb(25,36,54)
            title = text("R2U title","事件试玩",0,350,1000,60,34)
            title.fontColor = rgb(113,226,208)
            subtitle = text("R2U build","RPG Maker → Lua  ·  " .. data.engineProfile .. "  ·  " .. identity:sub(1,12),0,310,1040,34,16)
            speaker = text("R2U speaker","",0,248,1000,38,23)
            speaker.fontColor = rgb(113,226,208)
            message_text = text("R2U message","",0,161,960,128,26)
            for index=1,6 do
                local col = (index-1)%2
                local row = math.floor((index-1)/2)
                choices[index] = button("R2U choice " .. (index-1),"",col==0 and -250 or 250,48-row*66,464)
            end
            confirm = button("R2U confirm","继续",0,48,464)
            cancel = button("R2U cancel","取消",0,-156,224)
            state_text = text("R2U state","",0,-233,1000,106,18)
            state_text.fontColor = rgb(185,203,224)
            status_text = text("R2U status","",0,-307,1040,28,15)
            replay = button("R2U replay","再次触发",-250,-349,220)
            reset = button("R2U reset","重置状态",250,-349,220)
            hint = text("R2U hint","",0,-397,1120,28,14)
            local key = enum.KeyEventType.KeyboardInteractKeyDown
            local callback = function()
                if not alive or not current_message or current_message.choices then return false end
                answer(current_message,{kind="confirm"})
                return true
            end
            root:AddKeyEventListener(key,callback)
            listeners[#listeners+1] = {kind=key,callback=callback}
            begin(true)
            script:EnableUpdate(true)
        end)
        if not ok then controller.close(true); error(reason,0) end
        return controller
    end
    return M
end
