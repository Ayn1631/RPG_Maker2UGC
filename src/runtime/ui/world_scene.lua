-- Lua UI state; the platform only consumes the view and dispatches logical actions.
return function()
    local M={}
    function M.new(createWorld)
        local world=createWorld()
        local scene="map"
        local generation=1
        local partyIndex,partyEpoch=1,0
        local function partyToken() return generation..":"..partyEpoch end
        local selectionToken,selectionTask,selected
        local function messageView()
            local message=world.getMessage()
            if message then
                if message.token~=selectionToken or message.taskId~=selectionTask then
                    selectionToken,selectionTask=message.token,message.taskId
                    selected=message.choices and message.defaultChoice or nil
                end
                message.generation=generation; message.selectedChoice=selected
            else selectionToken,selectionTask,selected=nil,nil,nil end
            return message
        end
        local M={}
        function M.tick(frames) if scene=="map" then world.tick(frames) end end
        function M.dispatch(action)
            if action.kind=="reset" then
                world.close(); world=createWorld(); scene="map"; generation=generation+1.0
                partyIndex,partyEpoch=1,0
                selectionToken,selectionTask,selected=nil,nil,nil
            elseif action.kind=="party" then
                local view=world.snapshot()
                if not world.isBusy() and not view.player.motion and view.actors and #view.party.members>0 then
                    scene=scene=="party" and "map" or "party";partyIndex=1;partyEpoch=partyEpoch+1.0
                end
            elseif action.kind=="bag" then
                if not world.isBusy() and not world.snapshot().player.motion then scene=scene=="bag" and "map" or "bag" end
            elseif action.kind=="cancel" and scene~="map" then scene="map"
            elseif scene=="party" then
                local members=world.snapshot().party.members
                if #members==0 then scene="map";return end
                if action.kind=="navigate" or action.kind=="party_navigate" and action.token==partyToken() then
                    local step=(action.direction==2 or action.direction==6) and 1 or (action.direction==8 or action.direction==4) and -1 or 0
                    if step~=0 then partyIndex=(partyIndex-1+step)%#members+1;partyEpoch=partyEpoch+1.0 end
                elseif action.kind=="party_back" and action.token==partyToken() then scene="map"
                elseif action.kind=="actor_recover" and action.token==partyToken() and action.actorId==members[partyIndex] then
                    world.actorCommand({op="recoverAll",actorId=action.actorId})
                    partyEpoch=partyEpoch+1.0
                end
            elseif scene=="map" then
                local message=messageView()
                if action.kind=="navigate" then
                    if message and message.choices then
                        if action.direction==2 then selected=(selected+1)%#message.choices
                        elseif action.direction==8 then selected=(selected<=0 and #message.choices or selected)-1 end
                    elseif not message then world.move(action.direction,action.dash) end
                elseif action.kind=="move" then world.move(action.direction,action.dash)
                elseif action.kind=="confirm" then
                    if message and not message.choices then world.respond(message.taskId,message.token,{kind="confirm"})
                    elseif message and selected and selected>=0 then world.respond(message.taskId,message.token,{kind="choice",index=selected})
                    elseif not message then world.confirm() end
                elseif action.kind=="cancel" and message then
                    world.respond(message.taskId,message.token,{kind=message.choices and "cancel" or "confirm"})
                elseif action.kind=="answer" and action.generation==generation then world.respond(action.taskId,action.token,action.answer) end
                world.tick(0)
            end
        end
        function M.view()
            local view=world.snapshot();view.scene=scene;view.message=messageView()
            if scene=="party" and #view.party.members>0 then
                partyIndex=math.min(partyIndex,#view.party.members)
                view.partyActor=world.getActor(view.party.members[partyIndex]);view.partyIndex=partyIndex;view.partyToken=partyToken()
            end
            return view
        end
        function M.mapData() return world.mapData() end
        function M.close() world.close() end
        return M
    end
    return M
end
