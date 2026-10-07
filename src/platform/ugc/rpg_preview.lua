-- Lua scene presentation. Source layouts with platform controls or explicit source pixels.
return function(deps)
    local scenes = deps['runtime.ui.rpg_scene']
    local messageLayout = deps['runtime.ui.rpg_layout']
    local messageFlow=deps['runtime.ui.message_flow']
    local menuLayout = deps['runtime.ui.menu_layout']
    local equipLayout = deps['runtime.ui.equip_layout']
    local battleLayout = deps['runtime.ui.battle_layout']
    local auxLayout = deps['runtime.ui.aux_layout']
    local systemLayout = deps['runtime.ui.system_layout']
    local itemBackground = deps['runtime.ui.item_background']
    local cursorAnimation = deps['runtime.ui.cursor_animation']
    local gaugeLayout = deps['runtime.ui.gauge_layout']
    local windows = deps['platform.ugc.rpg_windows']
    local maps = deps['runtime.world.map']
    local mapViews=deps['platform.ugc.map_view']
    local presentationViews=deps['platform.ugc.presentation']
    local numberText = deps['runtime.ui.number_text']
    local sourceText = deps['runtime.ui.source_text']
    local compiledFonts = deps['generated.ui_fonts']
    local M = {}
    local function rect(x,y,w,h) return {x=x,y=y,width=w,height=h} end
    local function number(n) return string.format('%.0f',n) end
    local function fail(code,reason) error({severity='error',code=code,reason=reason},0) end

    function M.open(host,data,identity,createWorld)
        if not host or not host.game or not host.script or not host.script.object
            or not data.ui or not data.uiSkin or not data.worldPreview then
            fail('E_PLATFORM_NOT_CONFIGURED','Source UI requires a host, skin and source UI configuration')
        end
        local recycling=host.uiLifecycle or deps['platform.ugc.ui_recycle'].new(host.game,host.script.object)
        local localHost={};for k,v in pairs(host)do localHost[k]=v end;localHost.game=recycling.game;host=localHost
        local game,root,enum,color=host.game,host.script.object,host.Enum,host.Color
        local ui,skin=data.ui,data.uiSkin
        local updates=deps['platform.ugc.ui_updates'].new(recycling.retired)
        local bindings={};for key,value in pairs(data.worldPreview)do bindings[key]=value end;bindings.updates=updates
        local mode=bindings.renderMode;if mode==nil then mode='platform' end
        if mode~='platform' and mode~='source' then fail('E_UI_RENDER_MODE','Unknown RPG UI render mode') end
        local platform=mode=='platform'
        local mz=ui.profile=='mz-1.10.0'
        local gaugeFont=not platform and mz and data.uiFonts and data.uiFonts.gauge and numberText.new(data.uiFonts.gauge) or nil
        local mainFont
        local program=not platform and data.uiFonts and data.uiFonts.mainProgram
        if not platform and (program~=nil or data.uiRendering and data.uiRendering.mainFontInitialization=='precompiled') then
            if type(program)~='table' or program.kind~='r2u.font-program' or program.schemaVersion~=1
                or program.moduleId~='generated.ui_fonts' or not compiledFonts or type(compiledFonts.newMain)~='function' then
                fail('E_UI_FONT_PROGRAM','The declared precompiled main-font module is unavailable')
            end
            mainFont=compiledFonts.newMain()
        elseif not platform and data.uiFonts and data.uiFonts.main then mainFont=sourceText.new(data.uiFonts.main) end
        local ground=windows.new(host,root,bindings,ui,skin)
        local deferredBindings={};for k,v in pairs(bindings) do deferredBindings[k]=v end;deferredBindings.deferred=not platform
        local initialWidth,initialHeight=game.GetUICanvasSize()
        deferredBindings.pixelScale=math.min(initialWidth/ui.screen.width,initialHeight/ui.screen.height)
        deferredBindings.pixelOffsetX=(initialWidth-ui.screen.width*deferredBindings.pixelScale)/2
        deferredBindings.pixelOffsetY=(initialHeight-ui.screen.height*deferredBindings.pixelScale)/2
        local base=windows.new(host,root,deferredBindings,ui,skin)
        local overlay=windows.new(host,root,bindings,ui,skin)
        local battleBindings={};for k,v in pairs(bindings) do battleBindings[k]=v end
        battleBindings.renderMode='platform';battleBindings.windowPattern='simple';battleBindings.deferred=false
        local battleSurface=windows.new(host,root,battleBindings,ui,skin)
        local timerSurface=windows.new(host,root,bindings,ui,skin);local timerGroup,timerText
        local mapNameGroup,mapNameText,mapNameBack
        local backgroundSurface=windows.new(host,root,battleBindings,ui,skin)
        -- Validate every window binding before acquiring the World lifecycle.
        local scene=scenes.new(createWorld,ui,data,function()
            if type(game.ServerSignal)~='function'then fail('E_PLATFORM_EXIT','ServerSignal is required for exiting the game')end
            -- Receiver owns leaving the level/game. This request has no payload.
            local signal=game.ServerSignal('R2U_EXIT_GAME')
            signal:SendSignal()
        end)
        local active,remainder=true,0
        local fastKeys={};local scrollTouch=false
        local uiRemainder,cursorScene=0,nil
        local cursorStates,cursorDraws={},{}
        local listeners,areas={},{}
        local oldCursor=root.showCursor
        local oldKeyPassthrough=root.disableKeyEventPassthrough==true
        local blackBackground
        local currentMap,currentStructure,currentToken,lastMessageKey
        local mapGroup,player,eventControls,eventVisibility,screenGroup,layoutState,lastScene,lastFocus
        local mapView
        local presentationView
        local messagePrevious={y=0,choiceFirstVisibleRow=0}
        local commandFirst,memberFirst,itemFirst, itemActorFirst=0,0,0,0
        local battleFirst,battleId,battleDraws=0,nil,nil
        local battleIconFrame=0
        local battleListFirst,battleLastMode=0,nil
        local auxFirst,auxActorFirst,auxTypeFirst=0,0,0
        local extensionDraws,extensionDrawRevision
        local optionDraws={}
        local shopNumberDraws
        local equipmentDraws
        local shopStatusDraw
        local helpState
        local auxRows,auxRowClock={},0
        local itemRows,itemRowClock={},0
        local equipRows,equipRowClock={},0
        local function closeListRows()
            for _,draw in pairs(auxRows)do draw.surface.close()end
            for _,draw in pairs(itemRows)do draw.surface.close()end
            for _,draw in pairs(equipRows)do draw.surface.close()end
            auxRows={};auxRowClock=0
            itemRows={};itemRowClock=0
            equipRows={};equipRowClock=0
            if shopStatusDraw then shopStatusDraw.surface.close();shopStatusDraw=nil end
            if helpState then for _,panel in pairs(helpState.variants)do panel.surface.close()end;helpState=nil end
        end
        local eventItemFirst=0;local systemDraws={}
        local persistentCursor
        local messageDraws
        local dispatch,render
        local auroraPanel,auroraPanelActive,auroraHud
        local auroraLabelSurface,auroraLabelRoot,auroraLabelMap,auroraLabels
        local function closeAuroraLabels()
            if auroraLabelSurface then auroraLabelSurface.close()end
            auroraLabelSurface,auroraLabelRoot,auroraLabelMap,auroraLabels=nil,nil,nil,nil
        end
        local function updateAuroraLabels(view)
            if not data.aurora then return end
            if view.scene~='map'then closeAuroraLabels();return end
            local world=view.world
            if auroraLabelMap~=world.mapId then
                closeAuroraLabels();auroraLabelMap=world.mapId;auroraLabels={}
                auroraLabelSurface=windows.new(host,root,bindings,ui,skin)
                auroraLabelRoot=auroraLabelSurface.group('Aurora map event labels',rect(0,0,ui.screen.width,ui.screen.height))
            end
            local names=data.aurora.eventLabels[tostring(world.mapId)]or{}
            local cx,cy=world.camera.x*48,world.camera.y*48
            auroraLabelSurface.move(auroraLabelRoot,-cx,-cy)
            for _,e in ipairs(world.events)do local label=names[tostring(e.id)]
                if label then
                    local x,y=((e.realX or e.x)+.5)*48,((e.realY or e.y)+1)*48-6-(e.jumpHeight or 0)
                    local visible=e.page~=nil and e.page~=false and y-cy>112 and y-cy<ui.screen.height-25 and x-cx> -90 and x-cx<ui.screen.width+90
                    local g=auroraLabels[e.id]
                    if visible and not g then
                        g=auroraLabelSurface.group('Aurora event label '..e.id,rect(x-110,y-62,220,56),auroraLabelRoot);auroraLabels[e.id]=g
                        local text=auroraLabelSurface.text(g,'Aurora event '..e.id,label,rect(0,0,220,56),20,{255,244,213,255})
                        text.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                    end
                    if g then auroraLabelSurface.move(g,x-110,y-62);auroraLabelSurface.show(g,visible)end
                end
            end
        end
        local api={}
        local errorContext={}
        local function diagnosticText(reason)
            -- Host callback bridges cannot reliably stringify Lua error tables.
            -- Preserve the diagnostic before releasing the failed scene.
            local message=tostring(reason)
            if type(reason)=='table' then
                message=tostring(rawget(reason,'code') or 'E_UI_RUNTIME')..': '..tostring(rawget(reason,'reason') or 'UI callback failed')
                for _,key in ipairs({'file','jsonPath','path'})do
                    if rawget(reason,key)~=nil then message=message..' '..tostring(rawget(reason,key))end
                end
                if not rawget(reason,'code') and not rawget(reason,'reason')then
                    local parts,n={},0
                    for k,v in next,reason do n=n+1;if n>12 then parts[#parts+1]='...';break end
                        parts[#parts+1]=tostring(k)..'='..tostring(v)
                    end
                    message=message..' {'..table.concat(parts,', ')..'}'
                end
            end
            return message
        end
        local function captureError(reason)
            local message=diagnosticText(reason)
            if host.traceback then
                local ok,trace=pcall(host.traceback,message,2)
                if ok and type(trace)=='string'then
                    -- Some host bridges omit/replace the supplied message.
                    -- Keep the original diagnostic even when the trace says <table>.
                    if trace:find(message,1,true)then message=trace else message=message..'\n'..trace end
                end
            end
            return message
        end
        local function abort(reason)
            local message=diagnosticText(reason)
            if host.logError then
                local context='R2U build='..tostring(identity)..' scene='..tostring(errorContext.scene)
                    ..' map='..tostring(errorContext.mapId)..' player=('..tostring(errorContext.x)..','..tostring(errorContext.y)..')'
                    ..' phase='..tostring(errorContext.phase)..' action='..tostring(errorContext.action)..' dt='..tostring(errorContext.dt)
                local mapInfo=' mapControls=unavailable'
                if mapView then
                    local ok,stats=pcall(mapView.stats)
                    if ok then mapInfo=' mapControls='..tostring(stats.live)..' peak='..tostring(stats.peak)end
                end
                context=context..mapInfo
                local operation=updates.failureContext();if operation then context=context..' '..operation end
                pcall(host.logError,context..'\n'..message)
            end
            -- Raising the text reports it to the host. A separate print is
            -- unavailable in the module environment and would mask this error.
            local closed,cleanup=pcall(api.close)
            if not closed then
                message=message..'\nCleanup failed: '..diagnosticText(cleanup)
                if host.logError then pcall(host.logError,'R2U cleanup failed: '..diagnosticText(cleanup))end
                -- close marks the scene inactive before releasing resources;
                -- also stop host updates if resource cleanup was interrupted.
                pcall(function()if host.script.alive then host.script:EnableUpdate(false)end end)
            end
            error(message,0)
        end
        local function measure(text,size)
            if mainFont then return mainFont.measure(text,size or ui.window.fontSize) end
            -- The documented host has no font selection or text-width query. This
            -- provisional metric is intentionally excluded from pixel parity claims.
            local width=0
            for i=1,#text do
                local b=text:byte(i)
                if b<128 then width=width+(size or ui.window.fontSize)*.55
                elseif b>=192 then width=width+(size or ui.window.fontSize) end
            end
            return width
        end
        local messages=messageLayout.new(ui,measure)
        local menus=menuLayout.new(ui,measure)
        local equipmentLayouts=equipLayout.new(ui,measure)
        local battleLayouts=battleLayout.new(ui)
        local auxiliary=auxLayout.new(ui)
        local systemLayouts=systemLayout.new(ui)
        local function sourceRect(r) return rect(r.x+ui.box.offsetX,r.y+ui.box.offsetY,r.width,r.height) end
        local function localRect(r,frame) return rect(r.x-frame.x,r.y-frame.y,r.width,r.height) end
        local function window(name,model)
            local group=base.window(name,sourceRect(model.rect),model.background)
            model.group=group
            model.cursorSibling=group.count-1
            return group
        end
        local function rowBackgrounds(model)
            if not platform or not mz then return end
            local clip=model.clipRect or model.contents
            for _,row in ipairs(model.rows or model.items or {}) do
                local r=row.rect
                local x,y,right,bottom=r.x,r.y,r.x+r.width,r.y+r.height
                if clip then x,y=math.max(x,clip.x),math.max(y,clip.y);right,bottom=math.min(right,clip.x+clip.width),math.min(bottom,clip.y+clip.height) end
                if right>x and bottom>y then local surface=model.surface or base;surface.solid(model.group,'RPG row background '..number(row.index),localRect(rect(x,y,right-x,bottom-y),model.rect),{35,40,55,96}) end
            end
            model.cursorSibling=model.group.count-1
        end
        local function ink(index,disabled)
            local c=skin.textColors[index+1]
            return {c[1],c[2],c[3],disabled and 160 or 255}
        end
        local function text(group,name,value,r,paint,align,size,clip,extended,surface)
            if mainFont then
                size=size or ui.window.fontSize
                clip=clip or rect(ui.window.padding,ui.window.padding,group.width-ui.window.padding*2,group.height-ui.window.padding*2)
                -- A real container retains the logical text bounds for coordinate
                -- input and inspection; its children are the only painted glyphs.
                local target=base.group(name,r,group);group.count=group.count+1
                local localClip=rect(clip.x-r.x,clip.y-r.y,clip.width,clip.height)
                local function line(lineValue,x,y,width,height)
                    local px,py=r.x+x,r.y+y
                    base.enqueueRender(target,function()
                        local mask=mainFont.render(lineValue,{fontSize=size,lineHeight=height,width=width,strokeWidth=ui.window.outlineWidth,
                            align=align=='Right' and 'right' or align=='Middle' and 'center' or 'left',offsetX=px-math.floor(px),offsetY=py-math.floor(py)})
                        base.glyphs(target,name,mask,x,y,paint or ink(0),ui.window.outlineColor,localClip)
                    end)
                end
                if extended then
                    local y=0;local height=mz and ui.window.lineHeight or size+8
                    for part in (value..'\n'):gmatch('(.-)\n') do
                        if mz then line(part,0,y,measure(part,size),height)
                        else
                            local x=0
                            for _,cp in utf8.codes(part) do local c=utf8.char(cp);local w=measure(c,size);line(c,x,y,w*2,height);x=x+w end
                        end
                        y=y+height
                    end
                else line(value,0,0,r.width,r.height) end
                return target.object
            end
            local object=(surface or base).text(group,name,value,r,size,paint,not extended)
            if align then object.horizontalAlignment=enum.TextHorizontalAlignment[align] end
            return object
        end
        local function modelText(model,name,value,r,paint,align,size,extended)
            if mainFont then
                local clip=model.clipRect or model.contents or rect(model.rect.x+ui.window.padding,model.rect.y+ui.window.padding,model.rect.width-ui.window.padding*2,model.rect.height-ui.window.padding*2)
                return text(model.group,name,value,localRect(r,model.rect),paint,align,size,localRect(clip,model.rect),extended)
            end
            local drawing=rect(r.x,r.y,r.width,r.height)
            local vertical
            local clip=model.clipRect
            if clip then
                local font=size or ui.window.fontSize
                drawing.width=math.min(r.x+r.width,clip.x+clip.width)-r.x
                if r.y<clip.y then
                    local bottom=r.y+r.height/2+font/2
                    drawing.y=clip.y;drawing.height=math.min(bottom,clip.y+clip.height)-clip.y
                    vertical='Bottom'
                elseif r.y+r.height>clip.y+clip.height then
                    drawing.y=r.y+(r.height-font)/2
                    drawing.height=clip.y+clip.height-drawing.y;vertical='Top'
                end
                if drawing.width<=0 or drawing.height<=0 then return nil end
            end
            local object=text(model.group,name,value,localRect(drawing,model.rect),paint,align,size,nil,extended,model.surface)
            if vertical then object.verticalAlignment=enum.TextVerticalAlignment[vertical] end
            return object
        end
        local function rememberArea(group,name,r,action,surface)
            local area=(surface or base).area(group,name,r)
            local stable=name:match('^RPG extension ') or name:match('^RPG system ') or name:match('^RPG name key ') or name:match('^RPG event input ') or name:match('^RPG digit button ') or name:match('^RPG choice ') or name:match('^RPG auxiliary hit options ') or name=='RPG message confirm'
            stable=stable or name:match('^RPG shop quantity button hit ')
            stable=stable or name:match('^RPG auxiliary hit skill_')
            stable=stable or name:match('^RPG auxiliary hit shop_') or name=='RPG shop status page hit'
            stable=stable or name:match('^RPG item %d+ hit$')
            stable=stable or name:match('^RPG equip slots %d+ hit$') or name:match('^RPG equip items %d+ hit$')
            local entry={area=area,action=action,stable=not not stable}
            areas[#areas+1]=entry;return entry
        end
        local function cursorActivity(view)
            if cursorScene~=view.scene then cursorScene=view.scene;cursorStates={} end
            local flags={}
            if view.message then flags={choices=view.focus=='choice',eventInput=view.input~=nil}
            elseif view.scene=='menu' then flags={mainCommand=view.focus=='menu',members=view.focus=='actor'}
            elseif view.scene=='item' then flags={category=view.focus=='category',items=view.focus=='item',itemActors=view.focus=='item_actor'}
            elseif view.scene=='equip' then flags={command=view.focus=='equip_command',slots=view.focus=='equip_slot',items=view.focus=='equip_item'}
            elseif view.scene=='skill' then flags={types=view.focus=='skill_type',list=view.focus=='skill_item',itemActors=view.focus=='skill_actor'}
            elseif view.scene=='shop' then flags={command=view.focus=='shop_command',category=view.focus=='shop_category',list=view.focus=='shop_buy' or view.focus=='shop_sell'}
            elseif view.scene=='options' or view.scene=='extension' then flags={list=true}
            elseif view.scene=='title' or view.scene=='gameEnd' then flags={systemCommand=true}
            elseif view.scene=='name' then flags={nameGrid=true}
            elseif view.scene=='battle' then flags={battleCommand=view.battle.mode=='party' or view.battle.mode=='actor',battleList=view.battle.mode=='skill' or view.battle.mode=='item',battleTargets=view.battle.mode=='target',battleResult=view.battle.mode=='result'}
            elseif view.scene=='map' then flags={choices=view.focus=='choice'} end
            for key,isActive in pairs(flags)do
                local entry=cursorStates[key]
                if not entry then entry={clock=cursorAnimation.new(ui.profile)};cursorStates[key]=entry end
                entry.active=isActive
            end
        end
        local function cursorAlpha(entry)return math.max(0,math.min(1,entry.clock.alpha(entry.active,255)))end
        local function animateCursors(frames)
            for _,entry in pairs(cursorStates)do entry.clock.advance(frames,entry.active) end
            for _,entry in ipairs(cursorDraws)do
                if entry.group.object.alive then overlay.paintOpacity(entry.group,cursorAlpha(entry.state)) end
            end
        end
        local function selectCursor(model,row,name,key)
            if not row then return end
            local r=localRect(row,model.rect)
            local g=overlay.group(name,r,model.group,true)
            local clip=model.clipRect and localRect(model.clipRect,row) or nil
            overlay.parts(g,skin.cursor,0,0,r.width,r.height,1,clip)
            local state=cursorStates[key]
            overlay.paintOpacity(g,cursorAlpha(state));cursorDraws[#cursorDraws+1]={group=g,state=state,model=model}
            -- The source border may still be queued. Final ordering is restored
            -- after that queue drains; overlay creation itself remains tiny.
            model.cursorGroup=g
            if base.pending()==0 then g.object:SetSiblingIndex(model.cursorSibling) end
        end
        local function selectedRow(model,index)
            for _,row in ipairs(model.rows or model.items or {}) do
                if row.index==index then return row.rect end
            end
        end
        local function scroll(first,index,rows,cols)
            local row=math.floor(math.max(index,0)/(cols or 1))
            if row<first then return row end
            if row>=first+rows then return row-rows+1 end
            return first
        end
        local function sourceFrame(kind,key)
            local art=data.uiArt
            if not art then return nil end
            for _,entry in ipairs(art[kind] or {}) do
                if entry[kind=='actors' and 'actorId' or 'iconIndex']==key then
                    return entry.frameIndex and art.frames[entry.frameIndex].frame or nil
                end
            end
        end
        local actorArtOverrides={}
        local function faceResourceKey(name,index)return(name or '')..':'..number(index or 0)end
        local function templateEntry(kind,key)
            if kind=='actors' and actorArtOverrides[key]then
                local a=actorArtOverrides[key]
                return{empty=a.faceName=='',templateId=a.faceTemplateId,primitive=data.resources and data.resources.faces and data.resources.faces[faceResourceKey(a.faceName,a.faceIndex)],width=144,height=144}
            end
            for _,entry in ipairs(data.uiArt and data.uiArt[kind] or {}) do
                if entry[kind=='actors' and 'actorId' or 'iconIndex']==key then return entry end
            end
        end
        local function face(model,actorId,r)
            if platform then
                local entry=templateEntry('actors',actorId)
                if not entry then fail('E_UI_ART_TEMPLATE','Missing normalized actor template: '..number(actorId)) end
                if not entry.empty then base.art(model.group,'RPG face '..number(actorId),entry.primitive or entry.templateId,localRect(r,model.rect),model.clipRect and localRect(model.clipRect,model.rect)) end
                return
            end
            local frame=sourceFrame('actors',actorId)
            if not frame then return end
            local target=localRect(r,model.rect)
            -- Native drawFace crops from the centre without stretching the portrait.
            local w,h=math.min(target.width,frame.width),math.min(target.height,frame.height)
            local x=target.x+math.max(0,(target.width-frame.width)/2)
            local y=target.y+math.max(0,(target.height-frame.height)/2)
            local c=model.clipRect and localRect(model.clipRect,model.rect) or rect(x,y,w,h)
            base.blit(model.group,frame,x-(frame.width-w)/2,y-(frame.height-h)/2,frame.width,frame.height,
                1,nil,math.min(x+w,c.x+c.width),math.min(y+h,c.y+c.height),math.max(x,c.x),math.max(y,c.y))
        end
        local function icon(model,index,r,disabled)
            if platform then
                local entry=templateEntry('icons',index)
                if not entry then fail('E_UI_ART_TEMPLATE','Missing normalized icon template: '..number(index)) end
                local p=localRect(r,model.rect)
                local iw,ih=ui.art and ui.art.iconWidth or 32,ui.art and ui.art.iconHeight or 32
                if mz then p.x=p.x+(32-iw)/2;p.y=p.y+(32-ih)/2 end
                p.width,p.height=iw,ih
                local surface=model.surface or base
                surface.art(model.group,'RPG icon '..number(index),entry.primitive or entry.templateId,p,model.clipRect and localRect(model.clipRect,model.rect),disabled,32,32)
                return
            end
            local frame=sourceFrame('icons',index)
            if frame then
                local p=localRect(r,model.rect)
                local x=mz and p.x+(32-frame.width)/2 or p.x
                local y=mz and p.y+(32-frame.height)/2 or p.y
                local c=model.clipRect and localRect(model.clipRect,model.rect)
                base.blit(model.group,frame,x,y,frame.width,frame.height,disabled and 160/255 or 1,nil,
                    c and c.x+c.width,c and c.y+c.height,c and c.x,c and c.y)
            end
        end
        local function gauge(model,member,x,y,kind,width)
            local actor=member.actorView
            if not actor then return end
            local s,p=actor.state,actor.stats.params
            local max=kind=='hp' and p[1] or kind=='mp' and p[2] or 100
            local value=s[kind]
            local valid=not mz or kind~='tp' or actor.preserveTp==true
            local label=ui.terms.basic[kind=='hp' and 4 or kind=='mp' and 6 or 8]
            local c1=kind=='hp' and 20 or kind=='mp' and 22 or 28
            local c2=c1+1
            local gx,gy,gw,gh=x,y+ui.window.lineHeight-8,width,6
            if mz then
                local labelWidth=0
                for _,i in ipairs({4,6,8}) do labelWidth=math.max(labelWidth,measure(ui.terms.basic[i],ui.window.fontSize-2)) end
                gx,gy,gw,gh=x+math.ceil(labelWidth)+6,y+12,128-math.ceil(labelWidth)-6,12
            end
            base.solid(model.group,'Gauge '..kind..' back',localRect(rect(gx,gy,gw,gh),model.rect),ink(19))
            local inset=mz and 1 or 0
            local fill=math.floor((gw-inset*2)*(valid and max>0 and value/max or 0))
            local a,b=ink(c1),ink(c2)
            local segments=platform and math.min(4,fill) or fill
            for n=0,segments-1 do
                local start=math.floor(n*fill/segments);local finish=math.floor((n+1)*fill/segments)
                local f=segments>1 and n/(segments-1) or 0
                local c={a[1]+(b[1]-a[1])*f,a[2]+(b[2]-a[2])*f,a[3]+(b[3]-a[3])*f,255}
                base.solid(model.group,'Gauge '..kind..' fill',localRect(rect(gx+inset+start,gy+inset,finish-start,gh-inset*2),model.rect),c)
            end
            if mz and mainFont then
                -- Sprite_Gauge draws at outlineWidth / 2 inside its 128 x 32 bitmap.
                local clip=rect(x,y,128,32);local c=model.clipRect
                if c then local right,bottom=math.min(x+128,c.x+c.width),math.min(y+32,c.y+c.height);clip.x,clip.y=math.max(x,c.x),math.max(y,c.y);clip.width,clip.height=right-clip.x,bottom-clip.y end
                text(model.group,'Gauge '..kind..' label',label,localRect(rect(x+1.5,y+3,128,24),model.rect),ink(16,not valid),nil,ui.window.fontSize-2,localRect(clip,model.rect))
            elseif platform and mz then
                -- Sprite_Gauge's short bitmap line is not a request to shrink
                -- its font. A taller host box preserves the same text centre.
                modelText(model,'Gauge '..kind..' label',label,rect(x+1.5,y-1,128,32),ink(16,not valid),nil,ui.window.fontSize-2,true)
            else modelText(model,'Gauge '..kind..' label',label,rect(x+(mz and 1 or 0),y+(mz and 3 or 0),44,mz and 24 or 36),ink(16,not valid),nil,mz and ui.window.fontSize-2 or nil) end
            if valid then
                local valueColor=0
                if kind=='hp' then
                    local dead=false;for _,stateId in ipairs(s.stateIds or {})do if stateId==1 then dead=true end end
                    valueColor=dead and 18 or value<max/4 and 17 or 0
                end
                if gaugeFont then
                    local run=gaugeFont.render(number(value),{fontSize=ui.window.fontSize-6,lineHeight=24,width=128,strokeWidth=2})
                    base.number(model.group,'Gauge '..kind..' value',run,localRect(rect(x,y,128,32),model.rect),ink(valueColor),{0,0,0,255},model.clipRect and localRect(model.clipRect,model.rect))
                elseif not mz then
                    local parts=gaugeLayout.currentAndMax({profile=ui.profile,x=x,y=y,width=width,lineHeight=ui.window.lineHeight},function(value)return measure(value,ui.window.fontSize)end)
                    modelText(model,'Gauge '..kind..' value',number(value),parts.currentRect,ink(valueColor),parts.align)
                    if parts.showMax then
                        modelText(model,'Gauge '..kind..' slash','/',parts.slashRect,ink(0),parts.align)
                        modelText(model,'Gauge '..kind..' max',number(max),parts.maxRect,ink(0),parts.align)
                    end
                else modelText(model,'Gauge '..kind..' value',number(value),rect(x,y-(platform and 4 or 0),128,platform and 32 or 24),ink(valueColor),'Right',ui.window.fontSize-6,platform) end
            end
        end
        local function battlerIconIndices(state)
            local resources=data.resources or {};local indices={}
            for _,id in ipairs(state.stateIds or {})do
                local index=resources.stateIcons and resources.stateIcons[number(id)]
                if index and index>0 then indices[#indices+1]=index end
            end
            for param,level in ipairs(state.buffs or {})do
                if level~=0 then indices[#indices+1]=(level>0 and 32 or 48)+(math.abs(level)-1)*8+param-1 end
            end
            return indices
        end
        local function statusIconArt(index)
            local resources=data.resources or {};local entry=templateEntry('icons',index);local key=number(index)
            local art=resources.icons and resources.icons[key] or entry and entry.primitive or resources.statusIconTemplates and resources.statusIconTemplates[key] or entry and entry.templateId
                or bindings.artTemplates and (bindings.artTemplates.icons and bindings.artTemplates.icons[key])
            if not art then fail('E_UI_ART_TEMPLATE','State icon has no compiled template: '..key)end
            return art
        end
        local function actorIcons(model,member,x,y,width)
            local state=member.actorView and member.actorView.state;if not state then return end
            local indices=battlerIconIndices(state)
            local iw,ih=ui.art and ui.art.iconWidth or 32,ui.art and ui.art.iconHeight or 32
            for slot=1,math.min(#indices,math.floor((width or 144)/32))do
                local index=indices[slot];local px=x+(slot-1)*32
                if platform then
                    base.art(model.group,'RPG actor icons '..number(member.actorId)..' slot '..slot,statusIconArt(index),
                        localRect(rect(px+(mz and (32-iw)/2 or 0),y+2,iw,ih),model.rect),model.clipRect and localRect(model.clipRect,model.rect),false,32,32)
                else icon(model,index,rect(px,y+2,32,32))end
            end
        end
        local function basicStatus(model,member,x,y,gaugeWidth)
            local actor=member.actorView
            modelText(model,'Actor name '..number(member.actorId),member.sourceActor.name,rect(x,y,168,36))
            if not actor then return end
            modelText(model,'Actor level label',ui.terms.basic[2],rect(x,y+36,48,36),ink(16))
            modelText(model,'Actor level',number(actor.state.level),rect(x+84,y+36,36,36),nil,'Right')
            actorIcons(model,member,x,y+ui.window.lineHeight*2)
            local class=''
            for _,r in ipairs(ui.presentationDefs.classes) do if r.id==actor.state.classId then class=r.name end end
            modelText(model,'Actor class',class,rect(x+180,y,168,36))
            gauge(model,member,x+180,y+36,'hp',gaugeWidth or 186)
            gauge(model,member,x+180,y+(mz and 60 or 72),'mp',gaugeWidth or 186)
            if mz and ui.optDisplayTp then gauge(model,member,x+180,y+84,'tp',186) end
        end
        local function buildMap(view)
            if mapView then mapView.close();mapView=nil end
            ground.close()
            local cw,ch=game.GetUICanvasSize()
            local scale=math.min(cw/ui.screen.width,ch/ui.screen.height)
            if data.resources then
                local actors={};for _,actor in ipairs(ui.presentationDefs.actors)do actors[actor.id]=actor end
                local map=scene.mapData();currentMap=map.id
                mapView=mapViews.new(host,root,bindings,ui,map,data.resources,actors)
                mapGroup={object=mapView.object,visible=true};mapView.update(view.world)
                local marginX,marginY=math.max(0,(cw/scale-ui.screen.width)/2),math.max(0,(ch/scale-ui.screen.height)/2)
                local bars=ground.group('RPG viewport borders',rect(-marginX,-marginY,cw/scale,ch/scale))
                if marginX>0 then
                    ground.solid(bars,'RPG left border',rect(0,0,marginX,ch/scale),{0,0,0,255})
                    ground.solid(bars,'RPG right border',rect(marginX+ui.screen.width,0,marginX,ch/scale),{0,0,0,255})
                end
                if marginY>0 then
                    ground.solid(bars,'RPG top border',rect(0,0,cw/scale,marginY),{0,0,0,255})
                    ground.solid(bars,'RPG bottom border',rect(0,marginY+ui.screen.height,cw/scale,marginY),{0,0,0,255})
                end
                blackBackground:SetAsFirstSibling();return
            end
            mapGroup=ground.group('RPG map',rect(0,0,ui.screen.width,ui.screen.height))
            local map=scene.mapData()
            currentMap=map.id
            local rules=maps.new(map)
            local cell=48
            -- World art reconstruction is pending; no diagnostic labels enter game UI.
            for y=0,math.min(map.height-1,math.ceil(ui.screen.height/cell)-1) do
                for x=0,math.min(map.width-1,math.ceil(ui.screen.width/cell)-1) do
                    local pass=rules.isPassable(x,y,2) or rules.isPassable(x,y,4) or rules.isPassable(x,y,6) or rules.isPassable(x,y,8)
                    ground.solid(mapGroup,'RPG tile '..x..':'..y,rect(x*cell,y*cell,cell,cell),pass and {42,74,83,255} or {49,54,68,255})
                end
            end
            eventControls,eventVisibility={},{}
            for _,event in ipairs(view.world.events) do
                eventControls[event.id]=ground.solid(mapGroup,'RPG event '..event.id,rect(event.x*cell+6,event.y*cell+6,36,36),{123,89,42,255})
            end
            player=ground.group('RPG player',rect(view.world.player.realX*cell+8,view.world.player.realY*cell+4,32,40),mapGroup)
            ground.solid(player,'RPG player fill',rect(0,0,32,40),{56,167,143,255})
            mapGroup.object:SetAsFirstSibling()
            blackBackground:SetAsFirstSibling()
        end
        local function sourceButtons(view)
            if view.scene=='map'and data.aurora then
                local g=base.group('Aurora map HUD',rect(0,0,ui.screen.width,112))
                base.solid(g,'Aurora HUD back',rect(0,0,ui.screen.width,112),{11,36,50,255})
                base.text(g,'Aurora map name',view.world.mapName.name,rect(20,0,780,56),21,{245,231,189,255})
                auroraHud=base.text(g,'Aurora objective',view.world.auroraHud,rect(20,54,ui.screen.width-50,56),20,{186,217,223,255})
                base.solid(g,'Aurora terminal back',rect(ui.screen.width-160,12,142,48),{49,91,102,255})
                base.text(g,'Aurora terminal label','终端 [X]',rect(ui.screen.width-153,12,126,46),20,{255,242,204,255})
                rememberArea(g,'Aurora terminal hit',rect(ui.screen.width-170,0,170,75),{kind='menu'})
                return
            end
            if view.scene=='map' and view.world.access and view.world.access.menu==false then return end
            if view.scene=='title' or view.scene=='gameover' or view.scene=='name' or view.input and view.input.kind=='number'then return end
            if not mz or not ui.touchUI or not data.uiArt or not data.uiArt.buttons then return end
            local buttonY=view.scene=='battle' and ui.window.lineHeight*2+ui.window.padding*2+2 or 2
            for _,symbol in ipairs(view.scene=='map' and {'menu'} or (view.scene=='status' or view.scene=='equip' and view.equip.pageButtonsEnabled or view.scene=='skill' and not view.skill.targeting or view.scene=='shop' and view.shop.pageButtonsEnabled) and {'cancel','pageup','pagedown'} or {'cancel'}) do
                local entry
                for _,button in ipairs(data.uiArt.buttons) do if button.symbol==symbol then entry=button end end
                local frame=not platform and entry and data.uiArt.frames[entry.coldFrameIndex].frame
                if platform then
                    local bw,bh=entry and entry.width or 48,entry and entry.height or 48
                    local x=(symbol=='pageup' and 4) or (symbol=='pagedown' and 56) or (ui.box.width-bw-4)
                    local group=base.group('RPG button '..symbol,sourceRect(rect(x,buttonY,bw,bh)))
                    base.solid(group,'RPG button '..symbol..' back',rect(0,0,bw,bh),{35,45,75,192})
                    local label=({menu='≡',cancel='×',pageup='‹',pagedown='›'})[symbol]
                    local o=base.text(group,'RPG button '..symbol..' label',label,rect(0,0,bw,bh),28);o.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                    rememberArea(group,'RPG button '..symbol..' hit',rect(0,0,bw,bh),{kind=(symbol=='pageup' or symbol=='pagedown') and 'pageButton' or symbol,direction=symbol=='pageup' and 4 or symbol=='pagedown' and 6 or nil})
                elseif frame then
                    local x=(symbol=='pageup' and 4) or (symbol=='pagedown' and 56) or (ui.box.width-frame.width-4)
                    local group=base.group('RPG button '..symbol,sourceRect(rect(x,buttonY,frame.width,frame.height)))
                    base.blit(group,frame,0,0,frame.width,frame.height,entry.coldOpacity/255)
                    rememberArea(group,'RPG button '..symbol..' hit',rect(0,0,frame.width,frame.height),{kind=(symbol=='pageup' or symbol=='pagedown') and 'pageButton' or symbol,direction=symbol=='pageup' and 4 or symbol=='pagedown' and 6 or nil})
                end
            end
        end
        local function inlineText(w,name,rich,bounds)
            for i,run in ipairs(rich.runs)do
                local width=run.width
                if bounds then
                    local right=bounds.x+bounds.width
                    local nextRun=rich.runs[i+1]
                    if nextRun and nextRun.y==run.y then right=math.min(right,w.contents.x+nextRun.x)end
                    width=math.max(1,right-w.contents.x-run.x)
                end
                modelText(w,name..(i==1 and '' or ' run '..i),run.text,
                    rect(w.contents.x+run.x,w.contents.y+run.y,width,run.height),ink(run.colorIndex),nil,run.fontSize,bounds==nil)
            end
            for i,item in ipairs(rich.icons)do
                local entry=templateEntry('icons',item.iconIndex)
                local art=data.resources and data.resources.icons and data.resources.icons[number(item.iconIndex)] or entry and entry.primitive or item.templateId or entry and entry.templateId
                local r=rect(w.contents.x+item.x,w.contents.y+item.y,item.width,item.height)
                if platform then
                    if not art then fail('E_UI_ART_TEMPLATE','Inline icon has no compiled template: '..number(item.iconIndex))end
                    local surface=w.surface or base
                    surface.art(w.group,name..' icon '..i,art,localRect(r,w.rect),localRect(w.clipRect,w.rect),false,32,32)
                else icon(w,item.iconIndex,rect(r.x-(mz and (32-item.width)/2 or 0),r.y-(mz and (32-item.height)/2 or 0),32,32))end
            end
        end
        local function buildHelp(model,name,value)
            local rich=data.resources and data.resources.richHelp and data.resources.richHelp[value]
            local object=modelText(model,name,platform and rich and '' or value,model.textRect,nil,nil,nil,true)
            if platform then helpState={model=model,name=name,object=object,variants={},clock=0}end
            return object
        end
        local function updateHelp(view)
            local h=helpState;if not h then return end
            local value=view.items and view.items.help or view.equip and view.equip.help or view.skill and view.skill.help or view.shop and view.shop.help or view.battle and view.battle.help or ''
            local tokens=view.helpTokens;local key
            if tokens then
                local parts={};for _,token in ipairs(tokens)do
                    local v=tostring(token.value or '');parts[#parts+1]=token.kind..':'..#v..':'..v..':'..tostring(token.templateId or 0)
                end;key=table.concat(parts,';')
            end
            updates.call(h.object,'SetVisible',tokens==nil)
            if not tokens then base.updateText(h.object,value,h.model.textRect,ui.window.fontSize,true)end
            h.clock=h.clock+1
            if key and not h.variants[key]then
                local surface=windows.new(host,root,bindings,ui,skin)
                local panel={surface=surface};h.variants[key]=panel
                local model=h.model
                panel.group=surface.group(h.name..' rich',rect(0,0,model.rect.width,model.rect.height),model.group)
                local projected={surface=surface,group=panel.group,rect=model.rect,contents=model.contents,clipRect=model.clipRect or model.contents}
                local rich=messageFlow.inline(tokens,ui,measure,model.textRect.x-model.contents.x,model.textRect.y-model.contents.y)
                inlineText(projected,h.name,rich)
            end
            local idle,count={},0
            for id,panel in pairs(h.variants)do
                count=count+1;panel.surface.show(panel.group,id==key)
                if id==key then panel.lastUsed=h.clock else idle[#idle+1]={key=id,panel=panel}end
            end
            table.sort(idle,function(a,b)return a.panel.lastUsed<b.panel.lastUsed end)
            for i=1,count-3 do local entry=idle[i];entry.panel.surface.close();h.variants[entry.key]=nil end
        end
        local function buildMessage(view,layout)
            local m=view.message
            messageDraws={runs={},icons={},revision=-1,page=-1,model=layout.message}
            if m.scroll then
                local w=layout.message
                w.group=base.group('RPG scrolling text',sourceRect(w.rect))
                messageDraws.scroll={group=w.group,runs={},freeRuns={},icons={},freeIcons={}}
                local area=base.area(screenGroup,'RPG scrolling text hold',rect(0,0,ui.screen.width,ui.screen.height))
                base.bindHeld(area,function(value)scrollTouch=value end)
                return
            end
            if layout.message.visible then
                local w=layout.message
                window('RPG message',w)
                local left=ui.window.padding
                if m.faceName and m.faceName~='' then
                    local faceWidth=144
                    local art
                    for _,entry in ipairs(data.uiArt and data.uiArt.faces or {})do if entry.faceName==m.faceName and entry.faceIndex==m.faceIndex then art=entry;break end end
                    local primitive=data.resources and data.resources.faces and data.resources.faces[faceResourceKey(m.faceName,m.faceIndex)]
                    if primitive or m.faceTemplateId then base.art(w.group,'RPG message face',primitive or m.faceTemplateId,rect(left,ui.window.padding,faceWidth,144),nil,false,144,144)
                    elseif art and art.templateId then base.art(w.group,'RPG message face',art.templateId,rect(left,ui.window.padding,faceWidth,144),nil,false,art.width,art.height)
                    elseif art and art.frameIndex and data.uiArt.frames[art.frameIndex]then base.blit(w.group,data.uiArt.frames[art.frameIndex].frame,left,ui.window.padding,faceWidth,144,1)
                    else for _,actor in ipairs(ui.presentationDefs.actors)do if actor.faceName==m.faceName and actor.faceIndex==m.faceIndex then face(w,actor.id,rect(w.contents.x,w.contents.y,144,144));break end end end
                    left=left+164
                end
                rememberArea(w.group,'RPG message confirm',rect(0,0,w.rect.width,w.rect.height),{kind='confirm',focus='message'})
                local pause=base.text(w.group,'RPG message pause','▼',rect(w.rect.width/2-18,w.rect.height-24,36,20),18)
                pause.horizontalAlignment=enum.TextHorizontalAlignment.Middle;messageDraws.pause=pause
            end
            if layout.name then
                local w=layout.name;window('RPG name',w)
                if w.rich then inlineText(w,'RPG speaker',w.rich)
                else modelText(w,'RPG speaker',w.text,rect(w.textX,w.textY,w.rect.width-ui.window.padding*2,36),nil,nil,nil,true)end
            end
            if layout.choices then
                local w=layout.choices;window('RPG choices',w)
                rowBackgrounds(w)
                for _,row in ipairs(w.items) do
                    if row.rich then inlineText(w,'RPG choice '..number(row.index),row.rich,row.textRect)
                    else modelText(w,'RPG choice '..number(row.index),row.label,row.textRect,nil,nil,nil,true)end
                    rememberArea(w.group,'RPG choice '..number(row.index)..' hit',localRect(row.rect,w.rect),{kind='touch',index=row.index,focus='choice'})
                end
            end
            if layout.message.visible then
                local gh=ui.window.lineHeight+(mz and 8 or 0)+ui.window.padding*2
                local gy=layout.message.rect.y>0 and 0 or ui.box.height-gh
                local r=rect(ui.box.width-240,gy,240,gh)
                local gold={rect=r,contents=rect(r.x+ui.window.padding,r.y+ui.window.padding,r.width-ui.window.padding*2,r.height-ui.window.padding*2),visible=true}
                window('RPG message gold',gold);messageDraws.gold=gold
                local gr=localRect(gold.contents,gold.rect)
                messageDraws.goldText=base.text(gold.group,'RPG message gold value','',gr,ui.window.fontSize)
                messageDraws.goldText.horizontalAlignment=enum.TextHorizontalAlignment.Right
                base.show(gold.group,false)
            end
        end
        local function updateScroll(view,d)
            local f=view.messageFlow;local s=d.scroll;local model=d.model;local c=model.contents
            local offset=f.scroll.y;local top=ui.box.offsetY or 0;local height=model.rect.height
            base.move(s.group,ui.box.offsetX or 0,top-offset)
            local visible={}
            for i,run in ipairs(f.runs)do
                local y=c.y+run.y-offset;local h=run.fontSize+ui.window.lineHeight-ui.window.fontSize
                if y<height and y+h>0 and c.x+run.x<c.x+c.width then visible[i]={y=y,height=h}end
            end
            for i,o in pairs(s.runs)do if not visible[i]then updates.call(o,'SetVisible',false);s.freeRuns[#s.freeRuns+1]=o;s.runs[i]=nil end end
            for i,v in pairs(visible)do
                local run=f.runs[i];local o=s.runs[i]
                if not o then o=table.remove(s.freeRuns) or base.text(s.group,'RPG scrolling text run','',rect(0,0,1,1),run.fontSize,nil,false);s.runs[i]=o end
                local cut=math.max(0,-v.y);local h=math.min(v.height-cut,height-math.max(0,v.y));local x=c.x+run.x
                local w=math.max(1,c.x+c.width-x);local y=c.y+run.y+cut
                updates.set(o,'text',run.text);updates.set(o,'fontSize',run.fontSize)
                updates.set(o,'fontColor',color.FromRGBA(table.unpack(ink(run.colorIndex))),run.colorIndex)
                updates.set(o,'verticalAlignment',cut>0 and enum.TextVerticalAlignment.Bottom or enum.TextVerticalAlignment.Top)
                updates.call(o,'SetSizeDelta',w,h)
                updates.call(o,'SetAnchoredPosition',x+w/2-model.rect.width/2,model.rect.height/2-y-h/2)
                updates.call(o,'SetVisible',true)
            end
            local icons={}
            for i,item in ipairs(f.icons)do local y=c.y+item.y-offset;if y>=0 and y+32<=height then icons[i]=true end end
            for i,mount in pairs(s.icons)do if not icons[i]then base.show(mount,false);local id=mount.scrollTemplate;s.freeIcons[id]=s.freeIcons[id] or {};table.insert(s.freeIcons[id],mount);s.icons[i]=nil end end
            for i in pairs(icons)do local item=f.icons[i];local mount=s.icons[i]
                if not mount then
                    local entry=templateEntry('icons',item.iconIndex);local id=data.resources and data.resources.icons and data.resources.icons[tostring(item.iconIndex)] or entry and entry.primitive or item.templateId or entry and entry.templateId
                    if not id then fail('E_UI_ART_TEMPLATE','Scrolling icon needs a template')end
                    local pool=s.freeIcons[id];mount=pool and table.remove(pool) or base.art(s.group,'RPG scrolling icon',id,rect(c.x+item.x,c.y+item.y,32,32),nil,false,32,32)
                    mount.scrollTemplate=id;s.icons[i]=mount
                end
                base.move(mount,c.x+item.x,c.y+item.y);base.show(mount,true)
            end
        end
        local function updateMessage(view,layout)
            local f=view.messageFlow;if not f or not messageDraws then return end
            local d=messageDraws;local model=d.model
            if d.scroll then updateScroll(view,d);return end
            if d.gold then
                base.show(d.gold.group,f.gold)
                if f.gold then updates.set(d.goldText,'text',number(view.world.party.gold)..' '..ui.currencyUnit)end
            end
            if d.pause then updates.call(d.pause,'SetVisible',f.wait==0 and (f.pause=='page' or f.pause=='control' or f.pause=='end'))end
            if layout.choices then base.show(layout.choices.group,f.inputReady)end
            if layout.input then base.show(layout.input.group,f.inputReady)end
            if d.revision==f.revision and d.page==f.page then return end
            d.revision,d.page=f.revision,f.page
            if model.visible then
                local c=model.contents;local bottom=c.y+c.height
                for i,run in ipairs(f.runs)do
                    local drawing=d.runs[i]
                    if not drawing then
                        local o=base.text(model.group,'RPG message run '..i,'',rect(0,0,1,1),run.fontSize,nil,false)
                        o.verticalAlignment=enum.TextVerticalAlignment.Top;drawing={object=o};d.runs[i]=drawing
                    end
                    local x,y=c.x+run.x,c.y+run.y;local width=math.max(0,c.x+c.width-x);local height=math.max(0,math.min(run.fontSize+ui.window.lineHeight-ui.window.fontSize,bottom-y))
                    local visible=width>0 and height>0 and y>=c.y
                    local o=drawing.object
                    updates.set(o,'text',run.text);updates.set(o,'fontSize',run.fontSize)
                    updates.set(o,'fontColor',color.FromRGBA(table.unpack(ink(run.colorIndex))),run.colorIndex)
                    updates.call(o,'SetSizeDelta',math.max(1,width),math.max(1,height))
                    updates.call(o,'SetAnchoredPosition',x-model.rect.x+width/2-model.rect.width/2,model.rect.height/2-(y-model.rect.y)-height/2)
                    updates.call(o,'SetVisible',visible)
                end
                for i=#f.runs+1,#d.runs do updates.call(d.runs[i].object,'SetVisible',false)end
                for i,item in ipairs(f.icons)do
                    local drawing=d.icons[i]
                    if not drawing then drawing={variants={}};d.icons[i]=drawing end
                    local primitive=data.resources and data.resources.icons and data.resources.icons[tostring(item.iconIndex)]
                    local key=primitive or item.templateId or item.iconIndex;local mount=drawing.variants[key]
                    if not mount then
                        local entry=templateEntry('icons',item.iconIndex)
                        local template=primitive or entry and entry.primitive or item.templateId or entry and entry.templateId
                        if not template then fail('E_UI_ART_TEMPLATE','Message icon has no compiled template: '..number(item.iconIndex))end
                        mount=base.art(model.group,'RPG message icon '..i..':'..number(item.iconIndex),template,rect(ui.window.padding,ui.window.padding,32,32),nil,false,32,32)
                        drawing.variants[key]=mount
                    end
                    for candidate,other in pairs(drawing.variants)do base.show(other,candidate==key)end
                    base.move(mount,ui.window.padding+item.x,ui.window.padding+item.y)
                end
                for i=#f.icons+1,#d.icons do for _,mount in pairs(d.icons[i].variants)do base.show(mount,false)end end
            end
        end
        local function hostModelText(model,name,value,r,size,align)
            local o=base.text(model.group,name,value,localRect(r,model.rect),size or ui.window.fontSize)
            if align then o.horizontalAlignment=enum.TextHorizontalAlignment[align]end;return o
        end
        local function buildSystem(view,layout)
            systemDraws={labels={},digits={},commands={}}
            if view.scene=='title' or view.scene=='gameover'then
                local shade=base.group('RPG system backdrop',rect(0,0,ui.screen.width,ui.screen.height))
                base.solid(shade,'RPG system background',rect(0,0,ui.screen.width,ui.screen.height),view.scene=='title' and {20,28,48,255} or {0,0,0,255})
                if view.scene=='title'and data.auroraArt then base.blit(shade,data.auroraArt.title,0,0,ui.screen.width,ui.screen.height)end
                local customTitle=view.scene=='title'and data.aurora~=nil
                local text=base.text(shade,'RPG system title',view.scene=='title' and (not customTitle and ui.optDrawTitle==false and '' or view.system.gameTitle) or 'Game Over',customTitle and rect(0,92,ui.screen.width,68)or sourceRect(layout.title),customTitle and 46 or view.scene=='title' and 72 or 48)
                text.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                if customTitle then
                    local sub=base.text(shade,'Aurora title subtitle','AURORA ECHOES / 60种伙伴 · 8枚徽章 · 一段新的旅途',rect(0,164,ui.screen.width,42),20)
                    sub.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                    local hint=base.text(shade,'Aurora title controls','非商业同人作品 · 非官方 · WASD/方向键移动 · Z/F交谈 · X终端',rect(0,ui.screen.height-58,ui.screen.width,50),20)
                    hint.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                end
                if view.scene=='gameover'then rememberArea(shade,'RPG gameover confirm',rect(0,0,ui.screen.width,ui.screen.height),{kind='confirm'})end
            end
            if layout.command then
                window('RPG system command',layout.command);rowBackgrounds(layout.command)
                for _,row in ipairs(layout.command.rows)do local entry=view.system.rows[row.index+1]
                    local o=hostModelText(layout.command,'RPG system command '..number(row.index),entry.label,row.textRect,nil,'Middle')
                    systemDraws.commands[row.index+1]={object=o,enabled=entry.enabled,paint=o.fontColor}
                    if entry.enabled==false then o.fontColor=color.FromRGBA(255,255,255,128)end
                    rememberArea(layout.command.group,'RPG system command hit '..number(row.index),localRect(row.rect,layout.command.rect),{kind='touch',index=row.index})
                end
            end
            if view.scene=='name'then
                local v=view.input;window('RPG name edit',layout.edit);window('RPG name grid',layout.list)
                face(layout.edit,v.actorId,layout.edit.faceRect)
                local c=layout.edit.contents;local width=math.max(1,math.min(36,(c.width-156)/v.maxLength));local x=c.x+156;local y=c.y+54
                for i=1,v.maxLength do
                    base.solid(layout.edit.group,'RPG name underline '..i,localRect(rect(x+(i-1)*width,y+34,width-2,2),layout.edit.rect),{255,255,255,48})
                    systemDraws.digits[i]=hostModelText(layout.edit,'RPG name char '..i,v.characters[i] or '',rect(x+(i-1)*width,y,width,36),nil,'Middle')
                end
                for _,row in ipairs(layout.list.rows)do
                    systemDraws.labels[row.index+1]=hostModelText(layout.list,'RPG name key '..number(row.index),v.rows[row.index+1].label,row.textRect,nil,'Middle')
                    rememberArea(layout.list.group,'RPG name key hit '..number(row.index),localRect(row.rect,layout.list.rect),{kind='touch',index=row.index,focus='name'})
                end
                systemDraws.value=v.name;systemDraws.page=v.page
            end
        end
        local function buildMessageInput(view,layout)
            local v=view.input;local model=layout.input;window('RPG event input',model);rowBackgrounds(model);systemDraws={digits={}}
            for _,row in ipairs(model.rows)do local entry=v.rows[row.index+1];local r=row.textRect
                if v.kind=='number'then systemDraws.digits[row.index+1]=hostModelText(model,'RPG input digit '..number(row.index),entry.label,r,nil,'Middle')
                else
                    icon(model,entry.iconIndex,rect(r.x,r.y+2,32,32))
                    hostModelText(model,'RPG event item '..number(entry.id),entry.name,rect(r.x+36,r.y,math.max(0,r.width-100),r.height))
                    if entry.showCount then hostModelText(model,'RPG event item count '..number(entry.id),':'..number(entry.count),r,nil,'Right')end
                end
                rememberArea(model.group,'RPG event input hit '..number(row.index),localRect(row.rect,model.rect),{kind='touch',index=row.index,focus=v.kind})
            end
            systemDraws.value=v.value
            if v.kind=='number' and mz and ui.touchUI then
                local c=model.contents;for i,button in ipairs({{label='−',direction=2},{label='+',direction=8},{label=rawget(ui.terms.messages,'inputOk') or 'OK'}})do
                    local r=rect(c.x+(i-1)*c.width/3,c.y+44,c.width/3,44)
                    hostModelText(model,'RPG digit button '..i,button.label,r,nil,'Middle')
                    rememberArea(model.group,'RPG digit button hit '..i,localRect(r,model.rect),{kind=button.direction and 'navigate' or 'confirm',direction=button.direction,focus='number'})
                end
            elseif v.kind=='eventItem' and mz and ui.touchUI then
                local c=model.contents;local r=rect(c.x+c.width-44,c.y-8,44,44)
                hostModelText(model,'RPG event input cancel','×',r,nil,'Middle')
                rememberArea(model.group,'RPG event input cancel hit',localRect(r,model.rect),{kind='cancel',focus='eventItem'})
            end
        end
        local function updateSystem(view)
            if view.scene=='title' or view.scene=='gameEnd'then
                for i,drawing in ipairs(systemDraws.commands or {})do
                    local enabled=view.system.rows[i].enabled
                    if enabled~=drawing.enabled then
                        updates.set(drawing.object,'fontColor',enabled and drawing.paint or color.FromRGBA(255,255,255,128))
                        drawing.enabled=enabled
                    end
                end
            end
            local v=view.input;if not v then return end
            if v.kind=='name'then
                if systemDraws.value~=v.name then for i,o in ipairs(systemDraws.digits or {})do local value=v.characters[i] or '';if o.text~=value then updates.set(o,'text',value)end end;systemDraws.value=v.name end
                if systemDraws.page~=v.page then for i,o in ipairs(systemDraws.labels or {})do local value=v.rows[i].label;if o.text~=value then updates.set(o,'text',value)end end;systemDraws.page=v.page end
            elseif v.kind=='number' and systemDraws.value~=v.value then
                for i,o in ipairs(systemDraws.digits or {})do local value=v.rows[i].label;if o.text~=value then updates.set(o,'text',value)end end;systemDraws.value=v.value
            end
        end
        local function buildMembers(view,model,focus)
            rowBackgrounds(model)
            for _,row in ipairs(model.rows) do
                local member=view.members[row.index+1]
                if row.rect.y<model.contents.y+model.contents.height and row.rect.y+row.rect.height>model.contents.y then
                    face(model,member.actorId,row.faceRect)
                    basicStatus(model,member,row.simpleStatusAnchor.x,row.simpleStatusAnchor.y,row.gaugeWidth)
                    local top=math.max(row.rect.y,model.contents.y)
                    local bottom=math.min(row.rect.y+row.rect.height,model.contents.y+model.contents.height)
                    local name=focus=='actor' and 'RPG member ' or 'RPG item actor '
                    rememberArea(model.group,name..number(member.actorId)..' hit',localRect(rect(row.rect.x,top,row.rect.width,bottom-top),model.rect),{kind='touch',index=row.index,focus=focus})
                end
            end
        end
        local function buildMenu(view,layout)
            for _,key in ipairs({'mainCommand','gold','members'}) do window('RPG '..key,layout[key]) end
            rowBackgrounds(layout.mainCommand)
            for _,row in ipairs(layout.mainCommand.rows) do
                local item=view.menu.commands[row.index+1]
                modelText(layout.mainCommand,'RPG command '..item.symbol,item.label,row.textRect,ink(0,not item.enabled),platform and mz and 'Middle' or nil)
                rememberArea(layout.mainCommand.group,'RPG command '..item.symbol..' hit',localRect(row.rect,layout.mainCommand.rect),{kind='touch',index=row.index,focus='menu'})
            end
            buildMembers(view,layout.members,'actor')
            local r=layout.gold.textRect
            -- Until source glyph rendering is available, one Latin source half-cell
            -- may be narrower than the host glyph. Preserve its right edge but
            -- reserve at least one em so the currency symbol remains readable.
            local unitWidth=ui.currencyUnit=='' and 0 or math.min(80,mainFont and measure(ui.currencyUnit) or math.max(ui.window.fontSize,measure(ui.currencyUnit)))
            modelText(layout.gold,'RPG gold',number(view.world.party.gold),rect(r.x,r.y,r.width-unitWidth-6,r.height),nil,'Right')
            modelText(layout.gold,'RPG currency',ui.currencyUnit,rect(r.x+r.width-unitWidth,r.y,unitWidth,r.height),ink(16),'Right')
        end
        local function buildItem(view,layout)
            window('RPG help',layout.help)
            if layout.category.visible then window('RPG categories',layout.category) end
            window('RPG items',layout.items)
            if layout.category.visible then rowBackgrounds(layout.category) end
            if not platform then rowBackgrounds(layout.items)end
            buildHelp(layout.help,'RPG item help',view.items.help)
            if layout.category.visible then
                for _,row in ipairs(layout.category.rows) do
                    modelText(layout.category,'RPG category '..number(row.index),view.items.categories[row.index+1].label,row.textRect,nil,'Middle')
                    rememberArea(layout.category.group,'RPG category '..number(row.index)..' hit',localRect(row.rect,layout.category.rect),{kind='touch',index=row.index,focus='category'})
                end
            end
            if not platform then for _,row in ipairs(layout.items.rows) do
                if row.rect.y<layout.items.contents.y+layout.items.contents.height and row.rect.y+row.rect.height>layout.items.contents.y then
                    local item=view.items.rows[row.index+1]
                    local iconWidth=ui.art and ui.art.standardIconWidth or 32
                    icon(layout.items,item.iconIndex,rect(row.nameRect.x,row.nameRect.y+2,iconWidth,iconWidth),not item.enabled)
                    local r=row.nameRect
                    modelText(layout.items,'RPG item '..item.kind..':'..number(item.id),item.name,rect(r.x+iconWidth+4,r.y,math.max(0,r.width-iconWidth-4),r.height),ink(0,not item.enabled))
                    if item.showCount then modelText(layout.items,'RPG quantity '..number(item.id),':'..number(item.count),row.quantityRect,ink(0,not item.enabled),'Right') end
                    local top=math.max(row.rect.y,layout.items.contents.y)
                    local bottom=math.min(row.rect.y+row.rect.height,layout.items.contents.y+layout.items.contents.height)
                    rememberArea(layout.items.group,'RPG item '..number(item.id)..' hit',localRect(rect(row.rect.x,top,row.rect.width,bottom-top),layout.items.rect),{kind='touch',index=row.index,focus='item'})
                end
            end end
            if layout.itemActors then
                -- Native WindowLayer masks lower windows beneath the actor window.
                -- Parallel host containers need one opaque rectangle for that mask.
                local r=layout.itemActors.rect
                local occlusion=base.group('RPG item actor occlusion',sourceRect(r))
                base.solid(occlusion,'RPG item actor occlusion fill',rect(0,0,r.width,r.height),{20,26,42,255})
                window('RPG item actors',layout.itemActors)
                buildMembers(view,layout.itemActors,'item_actor')
            end
        end
        local function buildStatus(view,layout)
            window('RPG status',layout.status)
            for _,key in ipairs({'params','equips','profile'}) do
                if layout[key].drawFrame then window('RPG status '..key,layout[key])
                else layout[key].group=layout.status.group;layout[key].rect=layout.status.rect end
            end
            local member=view.status
            local actor=member.actorView
            local source=member.sourceActor
            local head=layout.status.header
            modelText(layout.status,'RPG status name',source.name,head.nameRect)
            modelText(layout.status,'RPG status class',member.sourceClass.name,head.classRect)
            modelText(layout.status,'RPG status nickname',source.nickname,head.nicknameRect)
            face(layout.status,member.actorId,layout.status.faceRect)
            local anchor=layout.status.levelAnchor
            modelText(layout.status,'RPG status level label',ui.terms.basic[2],rect(anchor.x,anchor.y,48,36),ink(16))
            modelText(layout.status,'RPG status level',number(actor.state.level),rect(anchor.x+84,anchor.y,36,36),nil,'Right')
            local iconsAnchor=layout.status.iconsAnchor
            if iconsAnchor then actorIcons(layout.status,member,iconsAnchor.x,iconsAnchor.y)end
            for _,g in ipairs(layout.status.gauges) do gauge(layout.status,member,g.x,g.y,g.kind,g.width or 186) end
            local progression=member.progression
            local current,max=progression.currentExp,progression.isMaxLevel
            local totalLabel=ui.terms.messages.expTotal:gsub('%%1',function()return ui.terms.basic[9]end)
            local nextLabel=ui.terms.messages.expNext:gsub('%%1',function()return ui.terms.basic[1]end)
            modelText(layout.status,'RPG experience label',totalLabel,layout.status.expRows[1],ink(16))
            modelText(layout.status,'RPG experience',max and '-------' or number(current),layout.status.expRows[2],nil,'Right')
            modelText(layout.status,'RPG next level label',nextLabel,layout.status.expRows[3],ink(16))
            local remaining=progression.expRemaining
            modelText(layout.status,'RPG next level',max and '-------' or number(remaining),layout.status.expRows[4],nil,'Right')
            for _,row in ipairs(layout.params.rows) do
                modelText(layout.params,'RPG parameter label '..number(row.paramId),ui.terms.params[row.paramId+1],row.nameRect,ink(16))
                modelText(layout.params,'RPG parameter '..number(row.paramId),number(actor.stats.params[row.paramId+1]),row.valueRect,nil,'Right')
            end
            for _,row in ipairs(layout.equips.rows) do
                if row.index<#actor.equipment then
                    local equipmentTypes=ui.equipmentTypes
                    if equipmentTypes==nil then equipmentTypes=data.rpg.system.equipTypes end
                    if row.slotRect then modelText(layout.equips,'RPG equip slot '..number(row.index),equipmentTypes[actor.equipmentSlots[row.index+1]+1],row.slotRect,ink(16)) end
                    local item=actor.equipment[row.index+1]
                    if item and item~=false then
                        local catalog=ui.presentationDefs[item.kind=='weapon' and 'weapons' or 'armors']
                        for _,record in ipairs(catalog) do if record.id==item.id then
                            local r=row.nameRect
                            icon(layout.equips,record.iconIndex,rect(r.x,r.y+2,32,32))
                            modelText(layout.equips,'RPG equipment '..number(row.index),record.name,rect(r.x+36,r.y,math.max(0,r.width-36),r.height))
                        end end
                    end
                end
            end
            modelText(layout.profile,'RPG actor profile',source.profile,layout.profile.textRect,nil,nil,nil,true)
            for _,r in ipairs(layout.status.separators or {}) do
                local c=ink(0);c[4]=48
                base.solid(layout.status.group,'RPG separator',localRect(r,layout.status.rect),c)
            end
        end
        local function buildEquipment(view,layout)
            local e=view.equip
            equipmentDraws={preview={}}
            for _,key in ipairs({'help','status','command','slots','items'}) do
                if layout[key].visible then window('RPG equip '..key,layout[key]) end
            end
            for _,kind in ipairs({'command','slots','items'}) do if layout[kind].visible and (not platform or kind=='command') then rowBackgrounds(layout[kind]) end end
            if mz and not platform then
                local frames={}
                for _,kind in ipairs({'command','slots','items'}) do
                    local model=layout[kind]
                    if model.visible then
                        local group=base.group('RPG equip '..kind..' contents back',rect(0,0,model.rect.width,model.rect.height),model.group)
                        model.group.count=model.group.count+1
                        model.cursorSibling=model.group.count-1
                        local clip=localRect(model.clipRect,model.rect)
                        for _,row in ipairs(model.rows) do
                            local key=row.rect.width..':'..row.rect.height
                            local drawing=frames[key]
                            if not drawing then drawing=itemBackground.render(row.rect.width,row.rect.height);frames[key]=drawing end
                            local r=localRect(row.rect,model.rect);local frame=drawing.frame
                            base.blit(group,frame,r.x+drawing.originX,r.y+drawing.originY,frame.width,frame.height,1,nil,
                                clip.x+clip.width,clip.y+clip.height,clip.x,clip.y)
                        end
                    end
                end
            end
            buildHelp(layout.help,'RPG equip help',e.help)
            local dead=false;for _,id in ipairs(e.actorView.state.stateIds or {}) do if id==1 then dead=true end end
            local nameColor=dead and 18 or e.actorView.state.hp<e.actorView.stats.params[1]/4 and 17 or 0
            modelText(layout.status,'RPG equip actor',e.sourceActor.name,layout.status.nameRect,ink(nameColor))
            if layout.status.faceRect then face(layout.status,e.actorId,layout.status.faceRect) end
            for _,row in ipairs(layout.status.rows) do
                local p=row.paramId+1
                modelText(layout.status,'RPG equip parameter label '..number(row.paramId),ui.terms.params[p],row.nameRect,ink(16))
                modelText(layout.status,'RPG equip current '..number(row.paramId),number(e.actorView.stats.params[p]),row.currentRect,nil,'Right')
                modelText(layout.status,'RPG equip arrow '..number(row.paramId),'→',row.arrowRect,ink(16),'Middle')
                if row.newVisible then
                    local value=e.previewActor.stats.params[p];local delta=value-e.actorView.stats.params[p]
                    local object=modelText(layout.status,'RPG equip preview '..number(row.paramId),number(value),row.newRect,ink(delta>0 and 24 or delta<0 and 25 or 0),'Right')
                    equipmentDraws.preview[p]={object=object,rect=row.newRect}
                end
            end
            for _,row in ipairs(layout.command.rows) do
                modelText(layout.command,'RPG equip command '..row.symbol,ui.terms.commands[row.index+16],row.textRect,nil,'Middle')
                rememberArea(layout.command.group,'RPG equip command '..row.symbol..' hit',localRect(row.rect,layout.command.rect),{kind='touch',index=row.index,focus='equip_command'})
            end
            if not platform then for _,kind in ipairs({'slots','items'}) do
                local model=layout[kind]
                if model.visible then for _,row in ipairs(model.rows) do
                    local item=e[kind][row.index+1];local top=math.max(row.rect.y,model.clipRect.y);local bottom=math.min(row.rect.y+row.rect.height,model.clipRect.y+model.clipRect.height)
                    if item and bottom>top then
                        if row.slotRect then modelText(model,'RPG equip slot '..number(row.index),ui.equipmentTypes[item.etypeId+1],row.slotRect,ink(16,not item.enabled)) end
                        if item.item then
                            icon(model,item.iconIndex,row.iconRect,not item.enabled)
                            modelText(model,'RPG equip '..kind..' name '..number(row.index),item.name,row.itemTextRect,ink(0,not item.enabled))
                            if row.quantityRect then
                                local r=row.quantityRect
                                modelText(model,'RPG equip count separator '..number(row.index),':',rect(r.x,r.y,r.width-measure('00'),r.height),nil,'Right')
                                modelText(model,'RPG equip count '..number(row.index),number(item.count),r,nil,'Right')
                            end
                        end
                        rememberArea(model.group,'RPG equip '..kind..' '..number(row.index)..' hit',localRect(rect(row.rect.x,top,row.rect.width,bottom-top),model.rect),{kind='touch',index=row.index,focus=kind=='slots' and 'equip_slot' or 'equip_item'})
                    end
                end end
            end end
        end
        local function buildAuxiliary(view,layout)
            local v=view.scene=='skill' and view.skill or view.scene=='shop' and view.shop or view.options
            optionDraws={}
            shopNumberDraws=nil
            for name,model in pairs(layout)do if name~='itemActors' and type(model)=='table' and model.rect then window('RPG '..view.scene..' '..name,model);rowBackgrounds(model)end end
            if layout.help then
                buildHelp(layout.help,'RPG auxiliary help',v.help)
            end
            local function drawRows(model,entries,focus,kind)
                if not model then return end
                for _,row in ipairs(model.rows)do local entry=entries[row.index+1]
                    if entry then
                        local r=row.textRect;local enabled=entry.enabled
                        if entry.useInfo then enabled=entry.useInfo.enabled end
                        local value=entry.label or entry.name or '';local reserve=(kind=='list' or kind=='options') and 100 or 0
                        local x=r.x
                        if entry.iconIndex then icon(model,entry.iconIndex,rect(x,r.y+2,32,32),enabled==false);x=x+36 end
                        modelText(model,'RPG auxiliary '..focus..' '..number(row.index),value,rect(x,r.y,math.max(0,r.width-(x-r.x)-reserve),r.height),ink(0,enabled==false),kind=='command' and 'Middle' or nil)
                        local status
                        if view.scene=='skill' and entry.useInfo then local cost=entry.useInfo.cost or {};local n=(cost.tp or 0)>0 and cost.tp or cost.mp or 0;if n>0 then status=number(n)end
                        elseif kind=='options'then status=entry.status elseif kind=='list'then status=number(entry.price or 0)end
                        if status then
                            local valueRect=rect(r.x+r.width-96,r.y,96,r.height)
                            local object=modelText(model,'RPG auxiliary value '..focus..' '..number(row.index),status,valueRect,ink(16,enabled==false),'Right')
                            if platform and kind=='options' then optionDraws[row.index+1]={object=object,rect=valueRect}end
                        end
                        rememberArea(model.group,'RPG auxiliary hit '..focus..' '..number(row.index),localRect(row.rect,model.rect),{kind='touch',index=row.index,focus=focus})
                    end
                end
            end
            if view.scene=='skill'then
                drawRows(layout.types,v.types,'skill_type','command')
                if not platform then drawRows(layout.list,v.rows,'skill_item','list')end
                local member={actorId=v.actorId,actorView=v.actorView,sourceActor=v.sourceActor}
                local s=layout.status;face(s,v.actorId,s.faceRect);basicStatus(s,member,s.simpleStatusAnchor.x,s.simpleStatusAnchor.y,s.gaugeWidth)
                if layout.itemActors then
                    local r=layout.itemActors.rect
                    local occlusion=base.group('RPG skill actor occlusion',sourceRect(r))
                    base.solid(occlusion,'RPG skill actor occlusion fill',rect(0,0,r.width,r.height),{20,26,42,255})
                    window('RPG skill itemActors',layout.itemActors);buildMembers(view,layout.itemActors,'skill_actor')
                end
            elseif view.scene=='shop'then
                drawRows(layout.command,v.commands,'shop_command','command');drawRows(layout.category,v.categories,'shop_category','command')
                if not platform then drawRows(layout.list,v.rows,'shop_'..v.mode,'list')end
                local c=layout.gold.contents;modelText(layout.gold,'RPG shop gold',number(v.gold)..' '..ui.currencyUnit,c,nil,'Right')
                local r=v.pending or v.rows[v.selectedIndex+1]
                if not platform and layout.status and r then local c=layout.status.contents
                    modelText(layout.status,'RPG shop possession',ui.terms.messages.possession or 'Possession',rect(c.x,c.y,c.width,36),ink(16))
                    modelText(layout.status,'RPG shop possession value',number(r.count),rect(c.x,c.y,c.width,36),nil,'Right')
                    if v.comparison then
                        for i,entry in ipairs(v.comparison.rows)do
                            local y=c.y+ui.window.lineHeight*2+math.floor(ui.window.lineHeight*(i-1)*2.2)
                            modelText(layout.status,'RPG shop actor '..number(entry.actorId),entry.name,rect(c.x,y,c.width-64,36),ink(0,not entry.enabled))
                            if entry.delta~=nil then modelText(layout.status,'RPG shop change '..number(entry.actorId),(entry.delta>0 and '+' or '')..number(entry.delta),rect(c.x+c.width-64,y,64,36),ink(entry.delta>0 and 24 or entry.delta<0 and 25 or 0),'Right')end
                            if entry.equipped then
                                icon(layout.status,entry.equipped.iconIndex,rect(c.x,y+36,32,32),not entry.enabled)
                                modelText(layout.status,'RPG shop equipped '..number(entry.actorId),entry.equipped.name,rect(c.x+36,y+36,c.width-36,36),ink(0,not entry.enabled))
                            end
                        end
                        if v.pageButtonsEnabled then rememberArea(layout.status.group,'RPG shop status page hit',localRect(layout.status.contents,layout.status.rect),{kind='page',direction=6})end
                    end
                end
                if layout.number and r then local c=layout.number.contents;local y=c.y+math.floor(c.height/3)
                    modelText(layout.number,'RPG shop number name',r.name,rect(c.x,y,c.width,36))
                    local qr,tr=rect(c.x,y+36,c.width,36),rect(c.x,y+108,c.width,36)
                    local quantity=modelText(layout.number,'RPG shop quantity','× '..number(v.quantity),qr,nil,'Right')
                    local total=modelText(layout.number,'RPG shop total',number(v.quantity*r.price)..' '..ui.currencyUnit,tr,nil,'Right')
                    if platform then shopNumberDraws={quantity=quantity,total=total,quantityRect=qr,totalRect=tr}end
                    for i,button in ipairs({{label='−10',direction=2},{label='−',direction=4},{label='+',direction=6},{label='+10',direction=8},{label=rawget(ui.terms.messages,'inputOk') or 'OK'}})do
                        local bw=c.width/5;local rr=rect(c.x+(i-1)*bw,c.y+c.height-48,bw,44)
                        modelText(layout.number,'RPG shop quantity button '..i,button.label,rr,nil,'Middle')
                        rememberArea(layout.number.group,'RPG shop quantity button hit '..i,localRect(rr,layout.number.rect),{kind=button.direction and 'navigate' or 'confirm',direction=button.direction,focus='shop_number'})
                    end
                end
            else drawRows(layout.list,v.rows,'options','options')end
        end
        local function retireRows(pool)
            local idle={}
            for id,draw in pairs(pool)do if not draw.used then
                draw.hit.enabled=false;draw.surface.show(draw.group,false);idle[#idle+1]={id=id,draw=draw}
            end end
            table.sort(idle,function(a,b)return a.draw.lastUsed<b.draw.lastUsed end)
            for i=1,#idle-12 do local entry=idle[i];entry.draw.surface.close();pool[entry.id]=nil end
            for i=#areas,1,-1 do if not areas[i].area.object.alive then table.remove(areas,i)end end
        end
        local function updateShopStatus(v,model)
            local item=v.pending or v.rows[v.selectedIndex+1]
            if not model or not item then return end
            local comparison=v.comparison and v.comparison.rows or {}
            local shape={tostring(v.pageButtonsEnabled)}
            for _,entry in ipairs(comparison)do
                local equipped=entry.equipped
                shape[#shape+1]=table.concat({entry.actorId,tostring(entry.enabled),tostring(entry.delta~=nil),equipped and equipped.kind or '',equipped and equipped.id or 0},':')
            end
            shape=table.concat(shape,';')
            if not shopStatusDraw or shopStatusDraw.shape~=shape then
                if shopStatusDraw then shopStatusDraw.surface.close()end
                local surface=windows.new(host,root,bindings,ui,skin)
                shopStatusDraw={surface=surface,shape=shape,rows={}}
                local d=shopStatusDraw;local c=model.contents
                local group=surface.group('RPG shop comparison contents',rect(0,0,model.rect.width,model.rect.height),model.group)
                local m={surface=surface,group=group,rect=model.rect,contents=c,clipRect=model.clipRect}
                local function field(name,r,paint,align)
                    return{object=modelText(m,name,'',r,paint,align),rect=r}
                end
                modelText(m,'RPG shop possession',ui.terms.messages.possession or 'Possession',rect(c.x,c.y,c.width,36),ink(16))
                d.possession=field('RPG shop possession value',rect(c.x,c.y,c.width,36),nil,'Right')
                for i,entry in ipairs(comparison)do
                    local y=c.y+ui.window.lineHeight*2+math.floor(ui.window.lineHeight*(i-1)*2.2)
                    local row={};d.rows[i]=row
                    row.name=field('RPG shop actor '..number(entry.actorId),rect(c.x,y,c.width-64,36),ink(0,not entry.enabled))
                    if entry.delta~=nil then row.delta=field('RPG shop change '..number(entry.actorId),rect(c.x+c.width-64,y,64,36),nil,'Right')end
                    if entry.equipped then
                        icon(m,entry.equipped.iconIndex,rect(c.x,y+36,32,32),not entry.enabled)
                        row.equipped=field('RPG shop equipped '..number(entry.actorId),rect(c.x+36,y+36,c.width-36,36),ink(0,not entry.enabled))
                    end
                end
                if v.pageButtonsEnabled then rememberArea(group,'RPG shop status page hit',localRect(c,model.rect),{kind='page',direction=6},surface)end
                for i=#areas,1,-1 do if not areas[i].area.object.alive then table.remove(areas,i)end end
            end
            local d=shopStatusDraw
            local function set(field,value)base.updateText(field.object,value,field.rect,ui.window.fontSize)end
            set(d.possession,number(item.count))
            for i,entry in ipairs(comparison)do
                local row=d.rows[i];set(row.name,entry.name)
                if row.delta then
                    set(row.delta,(entry.delta>0 and '+' or '')..number(entry.delta))
                    local paint=entry.delta>0 and 24 or entry.delta<0 and 25 or 0
                    updates.set(row.delta.object,'fontColor',color.FromRGBA(table.unpack(ink(paint))),paint)
                end
                if row.equipped then set(row.equipped,entry.equipped.name)end
            end
        end
        local function updateEquipmentRows(view,layout)
            equipRowClock=equipRowClock+1
            for _,draw in pairs(equipRows)do draw.used=false end
            for _,kind in ipairs({'slots','items'})do
                local model=layout[kind];local c=model.clipRect
                if model.visible then for _,row in ipairs(model.rows)do
                    local top,bottom=math.max(row.rect.y,c.y),math.min(row.rect.y+row.rect.height,c.y+c.height)
                    if bottom>top then
                        local item=view.equip[kind][row.index+1]
                        local ih=ui.art and ui.art.iconHeight or 32
                        local iconTop=row.iconRect.y+(mz and (32-ih)/2 or 0)
                        local clipTop=math.max(c.y,math.min(row.rect.y,iconTop))-row.rect.y
                        local clipBottom=math.min(c.y+c.height,math.max(row.rect.y+row.rect.height,iconTop+ih))-row.rect.y
                        local key=table.concat({kind,row.index,clipTop,clipBottom},':')
                        local draw=equipRows[key]
                        if not draw then
                            local surface=windows.new(host,root,bindings,ui,skin)
                            draw={surface=surface};equipRows[key]=draw
                            local y=row.rect.y
                            draw.group=surface.group('RPG equip row '..kind..' '..number(row.index),rect(0,y-model.rect.y,model.rect.width,row.rect.height),model.group)
                            local m={surface=surface,group=draw.group,rect=rect(model.rect.x,y,model.rect.width,row.rect.height),
                                contents=rect(c.x,top,c.width,bottom-top),clipRect=rect(c.x,y+clipTop,c.width,clipBottom-clipTop),rows={row}}
                            rowBackgrounds(m)
                            if row.slotRect then modelText(m,'RPG equip slot '..number(row.index),ui.equipmentTypes[item.etypeId+1],row.slotRect,ink(16,not item.enabled))end
                            if item.item then
                                icon(m,item.iconIndex,row.iconRect,not item.enabled)
                                modelText(m,'RPG equip '..kind..' name '..number(row.index),item.name,row.itemTextRect,ink(0,not item.enabled))
                                if row.quantityRect then
                                    local r=row.quantityRect
                                    modelText(m,'RPG equip count separator '..number(row.index),':',rect(r.x,r.y,r.width-measure('00'),r.height),nil,'Right')
                                    modelText(m,'RPG equip count '..number(row.index),number(item.count),r,nil,'Right')
                                end
                            end
                            draw.hit=rememberArea(draw.group,'RPG equip '..kind..' '..number(row.index)..' hit',rect(row.rect.x-model.rect.x,top-y,row.rect.width,bottom-top),{kind='touch',index=row.index,focus=kind=='slots' and 'equip_slot' or 'equip_item'},surface)
                        end
                        draw.used=true;draw.lastUsed=equipRowClock;draw.hit.enabled=true;draw.hit.action.index=row.index
                        draw.surface.move(draw.group,0,row.rect.y-model.rect.y);draw.surface.show(draw.group,true)
                    end
                end end
            end
            retireRows(equipRows)
        end
        local function updateItemRows(view,layout)
            local model=layout.items;local c=model.clipRect;itemRowClock=itemRowClock+1
            for _,draw in pairs(itemRows)do draw.used=false end
            for _,row in ipairs(model.rows)do
                local top,bottom=math.max(row.rect.y,c.y),math.min(row.rect.y+row.rect.height,c.y+c.height)
                if bottom>top then
                    local item=view.items.rows[row.index+1]
                    local iconHeight=ui.art and ui.art.iconHeight or 32
                    local iconTop=row.nameRect.y+2+(mz and (32-iconHeight)/2 or 0)
                    local clipTop=math.max(c.y,math.min(row.rect.y,iconTop))-row.rect.y
                    local clipBottom=math.min(c.y+c.height,math.max(row.rect.y+row.rect.height,iconTop+iconHeight))-row.rect.y
                    -- Edge rows use separate clipped variants; ordinary scrolling
                    -- moves complete row mounts without rewriting their children.
                    local key=table.concat({item.kind,item.id,clipTop,clipBottom},':')
                    local draw=itemRows[key]
                    if not draw then
                        local surface=windows.new(host,root,bindings,ui,skin)
                        draw={surface=surface};itemRows[key]=draw
                        local y=row.rect.y
                        draw.group=surface.group('RPG item row '..item.kind..':'..number(item.id),rect(0,y-model.rect.y,model.rect.width,row.rect.height),model.group)
                        local rowModel={surface=surface,group=draw.group,rect=rect(model.rect.x,y,model.rect.width,row.rect.height),
                            contents=rect(c.x,top,c.width,bottom-top),clipRect=rect(c.x,y+clipTop,c.width,clipBottom-clipTop),rows={row}}
                        rowBackgrounds(rowModel)
                        local iconWidth=ui.art and ui.art.standardIconWidth or 32
                        icon(rowModel,item.iconIndex,rect(row.nameRect.x,row.nameRect.y+2,iconWidth,iconWidth),not item.enabled)
                        local r=row.nameRect
                        modelText(rowModel,'RPG item '..item.kind..':'..number(item.id),item.name,rect(r.x+iconWidth+4,r.y,math.max(0,r.width-iconWidth-4),r.height),ink(0,not item.enabled))
                        if item.showCount then modelText(rowModel,'RPG quantity '..number(item.id),':'..number(item.count),row.quantityRect,ink(0,not item.enabled),'Right')end
                        draw.hit=rememberArea(draw.group,'RPG item '..number(item.id)..' hit',rect(row.rect.x-model.rect.x,top-y,row.rect.width,bottom-top),{kind='touch',index=row.index,focus='item'},surface)
                    end
                    draw.used=true;draw.lastUsed=itemRowClock;draw.hit.enabled=true;draw.hit.action.index=row.index
                    draw.surface.move(draw.group,0,row.rect.y-model.rect.y);draw.surface.show(draw.group,true)
                end
            end
            retireRows(itemRows)
        end
        local function updateAuxRows(view,layout)
            local model=layout.list;auxRowClock=auxRowClock+1
            local shop,battle=view.scene=='shop',view.scene=='battle'
            local v=battle and view.battle or shop and view.shop or view.skill
            local focus=battle and 'battle_'..v.mode or shop and 'shop_'..v.mode or 'skill_item'
            for _,draw in pairs(auxRows)do draw.used=false end
            for _,row in ipairs(model.rows)do
                local entry=v.rows[row.index+1]
                local key=(shop or battle) and row.index or entry.id
                local draw=auxRows[key]
                local enabled=entry.enabled
                if entry.useInfo then enabled=entry.useInfo.enabled end
                local value=entry.label or entry.name or ''
                if battle then
                    if v.mode=='skill' and entry.cost then
                        if (entry.cost.tp or 0)>0 then value=value..'  '..number(entry.cost.tp)..' TP'
                        elseif (entry.cost.mp or 0)>0 then value=value..'  '..number(entry.cost.mp)..' MP'end
                    elseif v.mode=='item' then value=value..'  :'..number(entry.count or 0)end
                end
                if not draw then
                    local surface=windows.new(host,root,bindings,ui,skin)
                    draw={surface=surface};auxRows[key]=draw
                    local y=row.rect.y
                    draw.group=surface.group('RPG '..view.scene..(battle and ' cached row ' or ' row ')..number(key),rect(0,y-model.rect.y,model.rect.width,row.rect.height),model.group)
                    local r=row.textRect
                    -- These immutable children move only through their row mount.
                    local rowModel={surface=surface,group=draw.group,rect=rect(model.rect.x,y,model.rect.width,row.rect.height)}
                    local x=r.x
                    if not battle and entry.iconIndex then icon(rowModel,entry.iconIndex,rect(x,r.y+2,32,32),enabled==false);x=x+36 end
                    local textRect=rect(x-model.rect.x,r.y-y,math.max(0,r.width-(x-r.x)-(battle and 0 or 100)),r.height)
                    draw.text=surface.text(draw.group,battle and 'RPG battle row '..number(row.index) or 'RPG auxiliary '..focus..' '..number(row.index),value,textRect,ui.window.fontSize,ink(0,enabled==false))
                    draw.textRect=textRect;draw.disabled=enabled==false
                    local cost=entry.useInfo and entry.useInfo.cost or {};local n=(cost.tp or 0)>0 and cost.tp or cost.mp or 0
                    if shop or n>0 then
                        local value=surface.text(draw.group,'RPG auxiliary value '..focus..' '..number(row.index),number(shop and (entry.price or 0) or n),rect(r.x+r.width-96-model.rect.x,r.y-y,96,r.height),ui.window.fontSize,ink(16,enabled==false))
                        value.horizontalAlignment=enum.TextHorizontalAlignment.Right
                    end
                    draw.hit=rememberArea(draw.group,battle and 'RPG battle row '..number(row.index)..' hit' or 'RPG auxiliary hit '..focus..' '..number(row.index),rect(row.rect.x-model.rect.x,0,row.rect.width,row.rect.height),{kind='touch',index=row.index,focus=focus},surface)
                end
                if battle then
                    base.updateText(draw.text,value,draw.textRect,ui.window.fontSize)
                    if draw.disabled~=(enabled==false)then
                        draw.disabled=enabled==false
                        updates.set(draw.text,'fontColor',color.FromRGBA(table.unpack(ink(0,draw.disabled))),draw.disabled)
                    end
                end
                draw.used=true;draw.lastUsed=auxRowClock;draw.hit.enabled=true;draw.hit.action.index=row.index
                draw.surface.move(draw.group,0,row.rect.y-model.rect.y);draw.surface.show(draw.group,true)
            end
            retireRows(auxRows)
        end
        local function buildExtension(view,layout)
            extensionDraws={rows={}};extensionDrawRevision=nil
            for name,model in pairs(layout)do window('RPG extension '..name,model);rowBackgrounds(model)end
            local function field(model,name,r,size,multiline)
                local object=base.text(model.group,'RPG extension '..name,'',localRect(r,model.rect),size or ui.window.fontSize,nil,false)
                if multiline then object.verticalAlignment=enum.TextVerticalAlignment.Top end
                return{object=object,rect=r,size=size or ui.window.fontSize,multiline=multiline}
            end
            extensionDraws.title=field(layout.header,'title',layout.header.contents)
            for _,row in ipairs(layout.list.rows)do
                local r=row.textRect
                extensionDraws.rows[row.index]={label=field(layout.list,'label '..number(row.index),r),
                    status=field(layout.list,'status '..number(row.index),rect(r.x,r.y+ui.window.lineHeight,r.width,ui.window.lineHeight),ui.window.fontSize-4)}
                rememberArea(layout.list.group,'RPG extension row '..number(row.index)..' hit',localRect(row.rect,layout.list.rect),{kind='touch',index=row.index,focus='extension'})
            end
            local c=layout.detail.contents;local line=ui.window.lineHeight
            extensionDraws.heading=field(layout.detail,'heading',rect(c.x,c.y,c.width,line))
            extensionDraws.status=field(layout.detail,'detail status',rect(c.x,c.y+line,c.width,line),ui.window.fontSize-4)
            extensionDraws.description=field(layout.detail,'description',rect(c.x,c.y+line*2,c.width,c.height-line*2),nil,true)
            extensionDraws.action=field(layout.action,'action label',layout.action.contents)
            extensionDraws.action.object.horizontalAlignment=enum.TextHorizontalAlignment.Middle
            rememberArea(layout.action.group,'RPG extension action hit',localRect(layout.action.contents,layout.action.rect),{kind='confirm',focus='extension'})
        end
        local function updateExtension(view)
            local v=view.extension;if extensionDrawRevision==v.revision then return end
            local function set(field,value)base.updateText(field.object,value,field.rect,field.size,field.multiline)end
            set(extensionDraws.title,v.title)
            for index,draw in pairs(extensionDraws.rows)do local row=v.rows[index+1];set(draw.label,row.label);set(draw.status,row.status)end
            local selected=v.rows[v.selectedIndex+1]
            set(extensionDraws.heading,selected and selected.label or 'No entries.')
            local paging=v.detailPages>1 and '  '..number(v.detailPage+1)..'/'..number(v.detailPages)..'  < >' or ''
            set(extensionDraws.status,(selected and selected.status or '')..paging)
            set(extensionDraws.description,v.notice~='' and v.notice or v.description)
            set(extensionDraws.action,selected and selected.action and selected.action.label or '')
            extensionDrawRevision=v.revision
        end
        local function bindAreas(view)
            for _,entry in ipairs(areas) do
                local action=entry.action
                local token=view.token
                if not entry.stable or not entry.bound then
                    base.bind(entry.area,function()
                        if active and entry.enabled~=false and entry.area.object.alive and (not action.focus or lastFocus==action.focus) then
                            dispatch({kind=action.kind,index=action.index,direction=action.direction,token=entry.stable and currentToken or token})
                        end
                    end);entry.bound=true
                end
            end
        end
        local function battleText(model,name,value,r,size,align,fit)
            local o=(model.surface or battleSurface).text(model.group,name,value,localRect(r,model.rect),size or ui.window.fontSize,nil,fit)
            if align then o.horizontalAlignment=enum.TextHorizontalAlignment[align] end
            return o
        end
        local function closeBattleIcons(draw)
            for _,variant in pairs(draw.iconVariants or {})do variant.surface.close()end
            draw.iconVariants={}
        end
        local function closeBattlePortraits(draw)
            for _,variant in pairs(draw.faceVariants or {})do variant.surface.close()end
            draw.faceVariants={}
        end
        local function closeBattleDraws()
            if not battleDraws then return end
            for _,draw in pairs(battleDraws.partyById)do closeBattleIcons(draw);closeBattlePortraits(draw);draw.surface.close()end
            for _,draw in pairs(battleDraws.enemies)do closeBattleIcons(draw);for _,f in pairs(draw.svFrames or {})do f.surface.close()end;draw.surface.close()end
            for _,draw in pairs(battleDraws.actorBodies or {})do for _,f in pairs(draw.svFrames or {})do f.surface.close()end;draw.surface.close()end
        end
        local svMotions={walk=0,wait=1,chant=2,guard=3,damage=4,evade=5,thrust=6,swing=7,missile=8,skill=9,spell=10,item=11,escape=12,victory=13,dying=14,abnormal=15,sleep=16,dead=17}
        local function hueFrame(frame,hue)
            if not hue or hue%360==0 then return frame end
            -- Same RGB -> HSL -> RGB hue rotation as MZ ColorFilter. Geometry
            -- is shared; only a detached palette is allocated for each frame.
            local out={};for k,v in pairs(frame)do out[k]=v end;out.palette={}
            for i,p in ipairs(frame.palette)do
                local r,g,b=p[1]/255,p[2]/255,p[3]/255;local lo,hi=math.min(r,g,b),math.max(r,g,b);local d=hi-lo;local l=(hi+lo)/2;local h,s=0,0
                if d>0 then h=(hi==r and ((g-b)/d)%6 or hi==g and (b-r)/d+2 or (r-g)/d+4)/6;s=d/(1-math.abs(2*l-1))end
                h=(h+hue/360)%1;local c=(1-math.abs(2*l-1))*s;local x=c*(1-math.abs((h*6)%2-1));local m=l-c/2
                if h<1/6 then r,g,b=c,x,0 elseif h<2/6 then r,g,b=x,c,0 elseif h<3/6 then r,g,b=0,c,x elseif h<4/6 then r,g,b=0,x,c elseif h<5/6 then r,g,b=x,0,c else r,g,b=c,0,x end
                out.palette[i]={math.floor((r+m)*255+.5),math.floor((g+m)*255+.5),math.floor((b+m)*255+.5),p[4]}
            end
            return out
        end
        local function updateSvFrame(draw,motion,frame,elapsed)
            if not draw.sv then return end
            local index=svMotions[motion or 'wait'];if index==nil then fail('E_VISU_PRESENTATION','Unknown SV motion '..tostring(motion))end
            local looping=index<=3 or index>=12
            local pattern=frame
            if pattern==nil then local step=math.floor((elapsed or 0)/12);pattern=looping and ({0,1,2,1})[step%4+1]or math.min(2,step)end
            local key=index*3+pattern+1
            if draw.svFrame==key then return end
            local primitive=draw.sv.primitiveFrames[key];if not primitive then fail('E_RESOURCE_BINDING','Missing exact SV motion frame '..key)end
            draw.svFrames=draw.svFrames or {};local old=draw.svFrames[draw.svFrame];if old then old.surface.show(old.group,false)end
            local variant=draw.svFrames[key]
            if not variant then
                local surface=windows.new(host,root,battleBindings,ui,skin)
                local g=surface.art(draw.group,'RPG SV frame '..key,hueFrame(primitive,draw.hue),rect(0,0,draw.group.width,draw.group.height),nil,false,draw.sv.width,draw.sv.height)
                variant={surface=surface,group=g};draw.svFrames[key]=variant
            end
            draw.svStamp=(draw.svStamp or 0)+1;variant.used=draw.svStamp;variant.surface.show(variant.group,true);draw.svFrame=key;draw.version=(draw.version or 0)+1
            local idle={};for k,f in pairs(draw.svFrames)do if k~=key then idle[#idle+1]={key=k,frame=f}end end
            table.sort(idle,function(a,b)return a.frame.used<b.frame.used end)
            for i=1,math.max(0,#idle-5)do local f=idle[i];f.frame.surface.close();draw.svFrames[f.key]=nil end
        end
        local function buildActorBodies(view)
            local config=data.resources and data.resources.visuBattleLayout;if not config then return end
            if config.sourceHome~='visu-sample'then fail('E_RESOURCE_BINDING','Unknown Visu actor home layout')end
            for i,actor in ipairs(view.battle.party)do
                local override=view.world.actorImages and (view.world.actorImages[actor.ref.id]or view.world.actorImages[number(actor.ref.id)])
                local name=override and override.battlerName or config.actorBattlers and config.actorBattlers[number(actor.ref.id)]
                local sv=name and data.resources.visuSvActors[name]
                if not sv then fail('E_RESOURCE_BINDING','Missing exact actor SV binding '..number(actor.ref.id))end
                local surface=windows.new(host,root,battleBindings,ui,skin)
                local x=math.floor(ui.screen.width/2+192+.5)-math.floor((ui.screen.width-ui.box.width)/2)+(i-1)*32
                local y=(ui.screen.height-200)-config.maxBattleMembers*48-math.floor((ui.screen.height-ui.box.height)/2)+(i-1)*48
                local g=surface.group('RPG actor body '..number(actor.ref.id),rect(x-sv.width/2,y-sv.height,sv.width,sv.height),battleDraws.field)
                local draw={group=g,surface=surface,sv=sv,homeX=g.x,homeY=g.y,version=0}
                battleDraws.actorBodies[actor.ref.id]=draw
                battleDraws.centres.actor[actor.ref.id]={x=x,y=y-sv.height/2,width=sv.width,height=sv.height}
                updateSvFrame(draw,'wait',nil,0)
            end
        end
        local function attackMotion(view,actorId)
            local config=data.resources and data.resources.visuBattleLayout;if not config or not config.attackMotions then return nil end
            local wtype=0;local party=view.world.party;local equips=party and party.equipment and (party.equipment[actorId]or party.equipment[number(actorId)])or{}
            for _,entry in ipairs(equips)do if entry and entry.kind=='weapon'then
                wtype=config.weaponTypesById[number(entry.id)];if wtype==nil then fail('E_RESOURCE_BINDING','Missing source weapon motion type '..number(entry.id))end;break
            end end
            local motion=config.attackMotions[wtype+1];if not motion then fail('E_RESOURCE_BINDING','Missing source attack motion '..wtype)end
            return ({[0]='thrust',[1]='swing',[2]='missile'})[motion.type]
        end
        local function transformBattler(ref,state)
            if not battleDraws then return end
            if not ref then
                if state.logVisible~=nil then battleDraws.logVisible=state.logVisible;updates.call(battleDraws.log,'SetVisible',state.logVisible)end
                if state.clearLog then battleDraws.lines={};updates.set(battleDraws.log,'text','')end
                return
            end
            local draw=ref.kind=='actor'and battleDraws.actorBodies[ref.id]or battleDraws.enemies[ref.troopSlot]
            if not draw then fail('E_VISU_PRESENTATION','Missing battle body '..ref.kind..':'..tostring(ref.id or ref.troopSlot))end
            draw.visuState=state
            draw.surface.move(draw.group,draw.homeX+state.x+(draw.collapseShake or 0),draw.homeY+state.y-state.float-state.jump+(draw.collapseOffsetY or 0))
            updates.call(draw.group.object,'SetLocalScale',(ref.kind=='enemy'and draw.sv and -1 or 1)*state.face,draw.collapseScale or 1,1)
            local elapsed=state.motionElapsed or math.max(0,state.clock-state.motionClock)*(state.motionSpeed or 1)
            local lean=not draw.sv and state.motion~='wait'and math.sin(math.min(1,elapsed/36)*math.pi)*12 or 0
            updates.call(draw.group.object,'SetLocalRotation',0,0,-state.angle+lean)
            local motion=state.motion
            if motion=='attack'then motion=draw.attackMotion;if not motion then fail('E_RESOURCE_BINDING','Missing resolved source attack motion')end
            elseif motion=='perform'then
                local action=state.actionRef;local config=data.resources and data.resources.visuBattleLayout
                if not action then fail('E_VISU_PRESENTATION','PerformAction requires actionStart actionRef')end
                if action.kind=='item'then motion='item'
                else
                    local skillType=config and config.skillTypesById and config.skillTypesById[number(action.id)]
                    if skillType==nil then fail('E_RESOURCE_BINDING','Missing source action skill type '..number(action.id))end
                    motion='skill';for _,id in ipairs(config.magicSkillTypes or{})do if id==skillType then motion='spell';break end end
                end
            end
            updateSvFrame(draw,draw.dead and 'dead'or motion,state.frame,elapsed)
            if state.showWeapon and not draw.weapon then
                draw.weapon=draw.surface.group('RPG sequence weapon',rect(draw.group.width*.7,draw.group.height*.3,8,draw.group.height*.65),draw.group)
                draw.surface.solid(draw.weapon,'RPG sequence weapon blade',rect(2,0,4,draw.weapon.height-8),{215,235,255,255})
                draw.surface.solid(draw.weapon,'RPG sequence weapon hilt',rect(0,draw.weapon.height-10,8,4),{220,180,70,255});draw.version=(draw.version or 0)+1
            end
            if draw.weapon then draw.surface.show(draw.weapon,state.showWeapon==true)end
            return draw
        end
        local function updateBattleIcons(draw,battler,owner,r,name,cycle,allowDead)
            local indices=(allowDead or not battler.dead and not battler.hidden) and battlerIconIndices(battler) or {}
            local selected={};local current={}
            for _,index in ipairs(indices)do current[index]=true end
            if cycle then
                draw.iconTicks=(draw.iconTicks or (mz and 40 or 0))+battleIconFrame-(draw.iconLastFrame or battleIconFrame)
                draw.iconLastFrame=battleIconFrame
                local steps=math.floor(draw.iconTicks/40);draw.iconTicks=draw.iconTicks%40
                if #indices==0 then draw.iconIndex=0;draw.iconStarted=false
                elseif steps>0 then draw.iconIndex=((draw.iconIndex or 0)+steps)%#indices;draw.iconStarted=true end
                if draw.iconStarted and #indices>0 then selected[1]=indices[(draw.iconIndex or 0)%#indices+1]end
            else
                for slot=1,math.min(#indices,math.floor(r.width/32))do selected[slot]=indices[slot]end
            end
            draw.iconVariants=draw.iconVariants or {};local wanted={}
            local iw,ih=ui.art and ui.art.iconWidth or 32,ui.art and ui.art.iconHeight or 32
            for slot,index in ipairs(selected)do
                local key=slot..':'..number(index);wanted[key]=true
                if not draw.iconVariants[key]then
                    local surface=windows.new(host,root,battleBindings,ui,skin)
                    -- Register before drawing so error cleanup owns the surface too.
                    local variant={surface=surface,index=index};draw.iconVariants[key]=variant
                    variant.group=surface.art(owner,name..' '..key,statusIconArt(index),rect(r.x+(slot-1)*32+(mz and (32-iw)/2 or 0),r.y+(cycle and (32-ih)/2 or 0),iw,ih),nil,false,32,32)
                end
            end
            for key,variant in pairs(draw.iconVariants)do
                if not current[variant.index]then variant.surface.close();draw.iconVariants[key]=nil
                elseif variant.group then variant.surface.show(variant.group,wanted[key]==true)end
            end
        end
        local function buildEnemySurface(enemy,i,count,layout)
            local old=battleDraws.enemies[i];if old then closeBattleIcons(old);for _,f in pairs(old.svFrames or {})do f.surface.close()end;old.surface.close()end
            local enemySurface=windows.new(host,root,battleBindings,ui,skin)
                local svName=enemy.visu and enemy.visu.sideviewBattler
                local sv=svName and data.resources and data.resources.visuSvActors and data.resources.visuSvActors[svName]
                if svName and not sv then fail('E_RESOURCE_BINDING','Missing exact enemy SV binding '..svName)end
                local template=sv or data.resources and data.resources.enemies and data.resources.enemies[number(enemy.enemyId)]
                if not template then for _,entry in ipairs(data.uiArt and data.uiArt.enemies or {}) do if entry.enemyId==enemy.enemyId then template=entry end end end
                if not template then fail('E_RESOURCE_BINDING','Missing enemy resource: '..number(enemy.enemyId))end
                if enemy.x==nil or enemy.y==nil then fail('E_RESOURCE_BINDING','Missing source troop coordinates: '..number(enemy.enemyId))end
                local w,h=template.width,template.height;local frame=rect(enemy.x-w/2,enemy.y-h,w,h)
                local nameRect=rect(frame.x-24,frame.y-30,w+48,30)
                local g=enemySurface.group('RPG enemy '..number(enemy.index),sourceRect(frame),battleDraws.field)
                local slot=enemy.ref and enemy.ref.troopSlot or enemy.troopSlot or enemy.index+1
                battleDraws.centres.enemy[slot]={x=frame.x+frame.width/2+ui.box.offsetX,y=frame.y+frame.height/2+ui.box.offsetY,width=w,height=h}
                local hue=enemy.visu and enemy.visu.battlerHue or 0
                if not sv and template and not template.empty then enemySurface.art(g,'RPG enemy art '..number(enemy.index),template.primitive and hueFrame(template.primitive,hue)or template.templateId,rect(0,0,w,h),nil,false,template.width,template.height)

                end
                local name=enemySurface.text(g,'RPG enemy name '..number(enemy.index),enemy.name,localRect(nameRect,frame),22);name.horizontalAlignment=enum.TextHorizontalAlignment.Middle
                local iconY=math.max(frame.y+frame.height-math.floor((frame.height+40)*.9+.5),20)-frame.y-16
                battleDraws.enemies[i]={group=g,surface=enemySurface,enemyId=enemy.enemyId,name=name,sv=sv,svName=svName,hue=hue,version=0,iconRect=rect(frame.width/2-16,iconY,32,32),homeX=g.x,homeY=g.y,collapseScale=1}
                if sv then updateSvFrame(battleDraws.enemies[i],'walk',nil,0);updates.call(g.object,'SetLocalScale',-1,1,1)end
        end
        local function updateBattleFace(draw,actorId,row)
            if not row.faceRect then return end
            local art=templateEntry('actors',actorId);local key=art and not art.empty and (art.primitive or art.templateId) or 0
            if draw.faceKey==key then return end
            draw.faceVariants=draw.faceVariants or {};draw.faceClock=(draw.faceClock or 0)+1
            if draw.faceKey and draw.faceVariants[draw.faceKey]then local old=draw.faceVariants[draw.faceKey];old.surface.show(old.group,false)end
            draw.faceKey=key;draw.faceRow=row
            if key~=0 then
                if not draw.faceLayer then
                    draw.faceLayer=draw.surface.group('RPG battle portrait layer '..number(actorId),rect(0,0,draw.model.rect.width,draw.model.rect.height),draw.model.group)
                    draw.faceLayer.object:SetSiblingIndex(0)
                end
                if not draw.faceVariants[key]then
                    local surface=windows.new(host,root,battleBindings,ui,skin)
                    local variant={surface=surface};draw.faceVariants[key]=variant
                    variant.group=surface.art(draw.faceLayer,'RPG battle face '..number(actorId),key,localRect(row.faceRect,draw.model.rect),localRect(draw.model.clipRect,draw.model.rect))
                end
                local variant=draw.faceVariants[key];variant.lastUsed=draw.faceClock
                if variant.group then variant.surface.show(variant.group,true)end
            end
            local idle={};for id,variant in pairs(draw.faceVariants)do if id~=key then idle[#idle+1]={id=id,variant=variant}end end
            table.sort(idle,function(a,b)return a.variant.lastUsed<b.variant.lastUsed end)
            for i=1,math.max(0,#idle-2)do local old=idle[i];old.variant.surface.close();draw.faceVariants[old.id]=nil end
        end
        local function buildBattleBackground(view)
            backgroundSurface.close()
            local names=view.world.battleBackground or {};local field=battleDraws.field
            local group=backgroundSurface.group('RPG battle backgrounds',rect(0,0,ui.screen.width,ui.screen.height),field)
            group.object:SetSiblingIndex(2)
            for i=1,2 do
                local name=names['name'..i];local art=data.resources and data.resources['battlebacks'..i] and data.resources['battlebacks'..i][name]
                if art then backgroundSurface.art(group,'RPG battle background '..i,art.primitive or art.templateId,rect(0,0,ui.screen.width,ui.screen.height),nil,false,art.width,art.height)end
            end
        end
        local function buildBattleActor(view,row,actor)
            local surface=windows.new(host,root,battleBindings,ui,skin)
            local window=battleDraws.status
            local entry={gauges={},row=row,surface=surface,actorId=actor.ref.id}
            battleDraws.partyById[actor.ref.id]=entry
            local status={rect=row.rect,clipRect=window.clipRect,surface=surface}
            status.group=surface.group('RPG battle member '..number(actor.ref.id),localRect(row.rect,window.rect),window.group)
            entry.model=status
            updateBattleFace(entry,actor.ref.id,row)
            local nr=row.nameRect
            if mz and (view.battle.battleSystem or 0)>0 then
                -- Native time gauge sits behind the actor name. The fill's
                -- fixed geometry is scaled from its left edge, one parent write.
                local r=localRect(rect(nr.x,nr.y+12,128,12),status.rect)
                surface.solid(status.group,'RPG battle time back '..number(row.index),r,ink(19))
                local mount=surface.group('RPG battle time fill '..number(row.index),rect(r.x+1,r.y+1,126,10),status.group)
                mount.object:SetPivot(0,.5);mount.object:SetAnchoredPosition(r.x+1-status.rect.width/2,status.rect.height/2-r.y-6)
                local parts={}
                for n=0,1 do parts[#parts+1]=surface.solid(mount,'RPG battle time color '..number(row.index)..':'..n,rect(n*63,0,63,10),ink(26+n))end
                entry.timeGauge={group=mount,parts=parts,flash=false}
            end
            entry.name=battleText(status,'RPG battle actor '..number(row.index),actor.name,rect(nr.x,nr.y,nr.width,mz and 32 or nr.height),ui.window.fontSize,nil,not mz)
            for i,kind in ipairs(ui.optDisplayTp and {'hp','mp','tp'} or {'hp','mp'}) do
                local box=row.gauges and row.gauges[kind]
                local x,y=box and box.x or row.gaugesX,box and box.y or row.gaugesY+(i-1)*24;local width=box and box.width or row.gaugeWidth
                local label=ui.terms.basic[kind=='hp' and 4 or kind=='mp' and 6 or 8]
                local labelWidth=0
                if mz then for _,term in ipairs({4,6,8})do labelWidth=math.max(labelWidth,measure(ui.terms.basic[term],ui.window.fontSize-2))end end
                local gaugeX=mz and x+math.ceil(labelWidth)+6 or x
                local r=localRect(mz and rect(gaugeX,y+12,math.max(1,128-math.ceil(labelWidth)-6),12) or rect(x,y+ui.window.lineHeight-8,width,6),status.rect)
                surface.solid(status.group,'RPG battle '..kind..' back '..number(row.index),r,{16,19,29,255})
                local fill=surface.solid(status.group,'RPG battle '..kind..' fill '..number(row.index),r,kind=='hp' and {96,196,120,255} or kind=='mp' and {94,154,220,255} or {224,188,80,255})
                battleText(status,'RPG battle '..kind..' label '..number(row.index),label,mz and rect(x+1.5,y-1,128,32) or rect(x,y,44,ui.window.lineHeight),mz and ui.window.fontSize-2 or ui.window.fontSize,nil,false)
                local parts=not mz and kind~='tp' and gaugeLayout.currentAndMax({profile=ui.profile,x=x,y=y,width=width,lineHeight=ui.window.lineHeight},function(value)return measure(value,ui.window.fontSize)end)
                local valueRect=mz and rect(x,y-4,128,32) or parts and parts.currentRect or rect(x+width-64,y,64,ui.window.lineHeight)
                local g={fill=fill,rect=r,value=battleText(status,'RPG battle '..kind..' value '..number(row.index),'',valueRect,mz and ui.window.fontSize-6 or ui.window.fontSize,'Right',false)}
                if parts and parts.showMax then
                    battleText(status,'RPG battle '..kind..' slash '..number(row.index),'/',parts.slashRect,ui.window.fontSize,'Right',false)
                    g.maximum=battleText(status,'RPG battle '..kind..' max '..number(row.index),'',parts.maxRect,ui.window.fontSize,'Right',false)
                end
                entry.gauges[kind]=g
            end
            return entry
        end
        local function updateBattleRoster(view)
            local ids={}
            for i,actor in ipairs(view.battle.party)do if i<=4 then ids[#ids+1]=number(actor.ref.id)end end
            local key=table.concat(ids,':')
            local config=data.resources and data.resources.visuBattleLayout
            if config then for _,id in ipairs(ids)do
                local override=view.world.actorImages and (view.world.actorImages[tonumber(id)]or view.world.actorImages[id])
                key=key..'|'..tostring(override and override.battlerName or config.actorBattlers and config.actorBattlers[id])
            end end
            if battleDraws.rosterKey==key then return end
            local wanted={};for _,id in ipairs(ids)do wanted[tonumber(id)]=true end
            for id,draw in pairs(battleDraws.partyById)do
                if not wanted[id]then closeBattleIcons(draw);closeBattlePortraits(draw);draw.surface.close();battleDraws.partyById[id]=nil end
            end
            local rows=battleLayouts.battle({mode='wait',partyCount=#view.battle.party,rowCount=0}).status.rows
            battleDraws.party={};battleDraws.centres.actor={};battleDraws.status.rows=rows
            for _,draw in pairs(battleDraws.actorBodies or {})do for _,f in pairs(draw.svFrames or {})do f.surface.close()end;draw.surface.close()end
            battleDraws.actorBodies={}
            for _,row in ipairs(rows)do
                local actor=view.battle.party[row.index+1]
                local draw=battleDraws.partyById[actor.ref.id] or buildBattleActor(view,row,actor)
                draw.row=row;draw.model.rect=row.rect
                local r=localRect(row.rect,battleDraws.status.rect);draw.surface.move(draw.model.group,r.x,r.y)
                battleDraws.party[row.index+1]=draw
                local face=row.faceRect or row.rect
                battleDraws.centres.actor[actor.ref.id]={x=face.x+face.width/2+ui.box.offsetX,y=face.y+face.height/2+ui.box.offsetY}
            end
            buildActorBodies(view)
            battleDraws.rosterKey=key
        end
        local function buildBattleSurface(view,layout)
            closeBattleDraws()
            backgroundSurface.close();battleSurface.close();battleDraws={party={},partyById={},actorBodies={},enemies={},lines={},sequence=-1,layout=layout};battleId=view.battle.battleId
            local group=battleSurface.group('RPG battlefield',rect(0,0,ui.screen.width,ui.screen.height))
            battleDraws.field=group;battleDraws.centres={actor={},enemy={}}
            battleSurface.solid(group,'RPG battle sky',rect(0,0,ui.screen.width,ui.screen.height),{24,35,54,255})
            battleSurface.solid(group,'RPG battle ground',rect(0,math.floor(layout.field.height*.64),ui.screen.width,ui.screen.height-math.floor(layout.field.height*.64)),{47,64,58,255})
            buildBattleBackground(view)
            for i,enemy in ipairs(view.battle.troop)do buildEnemySurface(enemy,i,#view.battle.troop,layout)end
            local status=layout.status;status.group=battleSurface.window('RPG battle status',sourceRect(status.rect));battleDraws.status=status
            updateBattleRoster(view)
            local log=layout.log;log.group=battleSurface.group('RPG battle log',sourceRect(log.rect));battleDraws.log=battleText(log,'RPG battle log text','',log.textRect,22)
        end
        local function battlerName(b,ref)
            for _,entry in ipairs(b.targets or {}) do if entry.ref.kind==ref.kind and (ref.kind=='actor' and entry.ref.id==ref.id or ref.kind=='enemy' and entry.ref.troopSlot==ref.troopSlot) then return entry.name end end
            return ''
        end
        local function updateBattleSurface(view)
            local b=view.battle
            updateBattleRoster(view)
            -- MZ hides Window_BattleStatus for skill/item and enemy selection.
            -- Friendly selection reuses this mounted party view in place of a
            -- second Window_BattleActor portrait tree. W.show also hides the
            -- separately mounted window background without destroying either.
            battleSurface.show(battleDraws.status.group,not view.message and b.mode~='skill' and b.mode~='item' and b.mode~='result' and not (b.mode=='target' and b.targetSide=='enemy'))
            for i,enemy in ipairs(b.troop)do
                local draw=battleDraws.enemies[i]
                if not draw or draw.enemyId~=enemy.enemyId or draw.svName~=(enemy.visu and enemy.visu.sideviewBattler)or draw.hue~=(enemy.visu and enemy.visu.battlerHue or 0)then buildEnemySurface(enemy,i,#b.troop,battleDraws.layout);draw=battleDraws.enemies[i]end
                if draw.sv and not draw.visuState then updateSvFrame(draw,enemy.dead and 'dead'or'walk',nil,battleIconFrame)end
                draw.dead=enemy.dead
                local config=data.resources and data.resources.visuBattleLayout
                if config and config.attackMotions then local m=config.attackMotions[1];draw.attackMotion=m and ({[0]='thrust',[1]='swing',[2]='missile'})[m.type]end
                local collapses=view.world.presentation and view.world.presentation.collapses
                local slot=enemy.ref and enemy.ref.troopSlot or enemy.troopSlot or enemy.index+1
                local effect=collapses and collapses[number(slot)]
                if effect and effect.kind~=2 or not enemy.dead then
                    -- Simplified collapse: move/scale the existing parent. No
                    -- child repaint or sprite-tree rebuild on animation frames.
                    local progress=effect and math.max(0,1-effect.elapsed/effect.duration) or 1
                    local scale=math.floor(draw.group.height*progress+.5)/draw.group.height
                    local shake=effect and effect.kind==1 and effect.elapsed>0 and ((effect.duration-effect.elapsed)%2*4-2) or 0
                    draw.collapseShake,draw.collapseOffsetY=shake,draw.group.height*(1-scale)/2
                    if draw.collapseScale~=scale then updates.call(draw.group.object,'SetLocalScale',draw.sv and -1 or 1,scale,1);draw.collapseScale=scale end
                    draw.surface.move(draw.group,draw.homeX+shake,draw.homeY+draw.group.height*(1-scale)/2)
                end
                draw.surface.show(draw.group,not enemy.hidden and (not enemy.dead or effect~=nil) and (not effect or effect.kind~=2));updates.set(draw.name,'text',enemy.name)
                updateBattleIcons(draw,enemy,draw.group,draw.iconRect,'RPG enemy state '..number(enemy.index),true,false)
            end
            for i,draw in ipairs(battleDraws.party) do
                local actor=b.party[i];updates.set(draw.name,'text',actor.name)
                local body=battleDraws.actorBodies[actor.ref.id];if body then body.dead=actor.dead;body.attackMotion=attackMotion(view,actor.ref.id);if not body.visuState then updateSvFrame(body,actor.dead and 'dead'or'wait',nil,battleIconFrame)end end
                updateBattleFace(draw,actor.ref.id,draw.row)
                updateBattleIcons(draw,actor,draw.model.group,localRect(draw.row.iconRect,draw.model.rect),'RPG battle state '..number(i-1),draw.row.iconCycle,true)
                if draw.timeGauge then
                    local time=draw.timeGauge;local charge=actor.tpb and actor.tpb.chargeTime or 0
                    local pixels=math.floor(126*math.max(0,math.min(1,charge)))
                    battleSurface.show(time.group,pixels>0)
                    if pixels>0 then updates.call(time.group.object,'SetLocalScale',pixels/126,1,1)end
                    local input=b.input and b.input~=false and b.input.actorRef.id==actor.ref.id and b.mode~='party' and b.mode~='wait' and b.mode~='result'
                    local phase=input and (math.floor(battleIconFrame/15)%2+1) or 0
                    if time.flash~=phase then
                        time.flash=phase
                        for n,part in ipairs(time.parts)do
                            local p=ink(25+n);local alpha=phase==1 and 64/255 or phase==2 and 48/255 or 0
                            local target=phase==1 and {255,255,255} or {0,0,255}
                            updates.set(part,'bgColor',color.FromRGBA(p[1]*(1-alpha)+target[1]*alpha,p[2]*(1-alpha)+target[2]*alpha,p[3]*(1-alpha)+target[3]*alpha,255),phase)
                        end
                    end
                end
                for kind,g in pairs(draw.gauges) do
                    local value=actor[kind];local max=kind=='hp' and actor.mhp or kind=='mp' and actor.mmp or 100
                    updates.set(g.value,'text',number(value))
                    if g.maximum then updates.set(g.maximum,'text',number(max))end
                    local w=math.max(0,math.min(g.rect.width,max>0 and g.rect.width*value/max or 0))
                    updates.call(g.fill,'SetVisible',w>0);updates.call(g.fill,'SetSizeDelta',math.max(1,w),g.rect.height)
                    updates.call(g.fill,'SetAnchoredPosition',g.rect.x+w/2-draw.model.rect.width/2,draw.model.rect.height/2-g.rect.y-g.rect.height/2)
                end
            end
            local lines=battleDraws.lines
            for _,r in ipairs(b.records or {}) do
              if r.sequence and r.sequence>battleDraws.sequence then
                battleDraws.sequence=r.sequence
                if r.kind=='actionStart' then
                    local name=r.actionName or r.actionRef and r.actionRef.name
                    if not name and r.actionRef then for _,entry in ipairs(r.actionRef.kind=='item' and b.items or b.skills or {}) do if entry.id==r.actionRef.id then name=entry.name end end end
                    lines[#lines+1]=battlerName(b,r.subjectRef)..' '..(name or '')
                elseif r.kind=='actionResult' then
                    local value=r.result or {};local detail=value.missed and 'Miss' or value.evaded and 'Evade' or value.hpDamage~=0 and value.hpDamage~=nil and number(-value.hpDamage)..' HP' or value.mpDamage~=0 and value.mpDamage~=nil and number(-value.mpDamage)..' MP' or ''
                    lines[#lines+1]=battlerName(b,r.targetRef)..' '..detail
                elseif r.kind=='visuResource'and r.showPopup then lines[#lines+1]=battlerName(b,r.targetRef)..' '..(r.amount>=0 and '+'or'')..number(r.amount)..' '..r.resource
                elseif r.kind=='escape'then lines[#lines+1]='Escape' end
              end
            end
            while #lines>100 do table.remove(lines,1) end
            local recent={};for i=math.max(1,#lines-2),#lines do recent[#recent+1]=lines[i] end
            updates.set(battleDraws.log,'text',table.concat(recent,'\n'));updates.call(battleDraws.log,'SetVisible',battleDraws.logVisible~=false and b.mode~='skill' and b.mode~='item' and b.mode~='result' and not b.backgroundList)
        end
        local function pendingText(model,name,value,r,paint,align)
            local clip=model.clipRect
            if r.x+r.width<=clip.x or r.x>=clip.x+clip.width then return end
            if platform and r.x<clip.x and align~='Right' then
                -- Host text has no canvas clip API. Whole glyphs outside the
                -- source visible strip are omitted using the host approximation.
                local size=ui.window.fontSize;local x=r.x;local parts={}
                for _,cp in utf8.codes(value) do
                    local glyph=utf8.char(cp);local advance=measure(glyph,size)
                    if x>=clip.x then parts[#parts+1]=glyph end;x=x+advance
                end
                value=table.concat(parts);r=rect(clip.x,r.y,math.min(r.x+r.width,clip.x+clip.width)-clip.x,r.height)
            elseif r.x<clip.x then r=rect(clip.x,r.y,r.x+r.width-clip.x,r.height) end
            if value~='' then modelText(model,name,value,r,paint,align) end
        end
        local function buildPendingBattleList(b,model)
            local s=model.sourceRect;local dx=s.x-model.rect.x;local margin=ui.window.margin
            model.group=base.group('RPG battle list',sourceRect(model.rect))
            base.blit(model.group,skin.back,dx+margin,margin,s.width-margin*2,s.height-margin*2,ui.window.backOpacity/255,ui.window.tone,model.rect.width,model.rect.height,0,0)
            base.parts(model.group,skin.frame,dx,0,s.width,s.height,ui.window.opacity/255,rect(0,0,model.rect.width,model.rect.height))
            rowBackgrounds(model);model.cursorSibling=model.group.count-1
            for _,row in ipairs(model.rows) do
                local entry=b.backgroundList.rows[row.index+1]
                if entry then
                    local r=row.textRect;local costWidth=measure('000')
                    pendingText(model,'RPG battle pending row '..number(row.index),entry.name or '',rect(r.x,r.y,r.width-costWidth,r.height),ink(0,entry.enabled==false))
                    if b.backgroundList.mode=='item' then pendingText(model,'RPG battle pending count '..number(row.index),':'..number(entry.count or 0),r,ink(0,entry.enabled==false),'Right')
                    elseif entry.cost then
                        local cost=(entry.cost.tp or 0)>0 and entry.cost.tp or entry.cost.mp or 0
                        if cost>0 then pendingText(model,'RPG battle pending cost '..number(row.index),number(cost),r,ink(16,entry.enabled==false),'Right') end
                    end
                end
            end
        end
        local function buildBattle(view,layout)
            local b=view.battle
            if battleId~=b.battleId then buildBattleSurface(view,layout) end
            for _,key in ipairs({'command','list','targets','help','result'}) do if layout[key].visible then
                if key=='list' and layout.list.partial then buildPendingBattleList(b,layout.list)
                else window('RPG battle '..key,layout[key]);rowBackgrounds(layout[key]) end
            end end
            if layout.help.visible then
                buildHelp(layout.help,'RPG battle help',b.help)
            end
            local model
            if b.mode=='party' or b.mode=='actor' then model=layout.command elseif b.mode=='skill' or b.mode=='item' then model=layout.list elseif b.mode=='target' then model=layout.targets elseif b.mode=='result' then model=layout.result else model=nil end
            if model and not (platform and (b.mode=='skill' or b.mode=='item')) then
                for _,row in ipairs(model.rows) do
                    local entry=b.rows[row.index+1]
                    if entry then
                        local value=entry.name or ''
                        if b.mode=='skill' and entry.cost then if (entry.cost.tp or 0)>0 then value=value..'  '..number(entry.cost.tp)..' TP' elseif (entry.cost.mp or 0)>0 then value=value..'  '..number(entry.cost.mp)..' MP' end end
                        if b.mode=='item' then value=value..'  :'..number(entry.count or 0) end
                        if b.mode=='result' then
                            text(model.group,'RPG battle row '..number(row.index),value,localRect(row.textRect,model.rect),ink(0),'Right',14)
                        else modelText(model,'RPG battle row '..number(row.index),value,row.textRect,ink(0,entry.enabled==false),(b.mode=='party' or b.mode=='actor') and 'Middle' or nil) end
                        rememberArea(model.group,'RPG battle row '..number(row.index)..' hit',localRect(row.rect,model.rect),{kind='touch',index=row.index,focus='battle_'..b.mode})
                    end
                end
            end
            if layout.result.visible then
                local maxEm=0
                for _,line in ipairs(b.resultLines) do
                    local em=0;for _,cp in utf8.codes(line) do em=em+(cp>=128 and 1.1 or (cp==77 or cp==87 or cp==64 or cp==37) and 1 or .65) end
                    maxEm=math.max(maxEm,em)
                end
                local size=math.max(1,math.floor(math.min(ui.window.fontSize,maxEm>0 and (layout.result.textRect.width-8)/maxEm or ui.window.fontSize)))
                local resultText=modelText(layout.result,'RPG battle result text',b.resultText,layout.result.textRect,nil,nil,size,true)
                if resultText and not mainFont then resultText.verticalAlignment=enum.TextVerticalAlignment.Top end
                rememberArea(layout.result.group,'RPG battle result message hit',localRect(layout.result.contents,layout.result.rect),{kind='touch',index=0,focus='battle_result'})
            end
        end
        render=function(view)
            updates.begin()
            view=view or scene.view()
            errorContext.scene=view.scene;errorContext.mapId=view.world.mapId
            local position=view.world.player or {};errorContext.x,errorContext.y=position.x,position.y
            base.setWindowTone(view.world.windowTone);battleSurface.setWindowTone(view.world.windowTone)
            actorArtOverrides=view.world.actorImages or {}
            cursorActivity(view)
            lastScene,lastFocus=view.scene,view.focus
            if view.scene~='map'then closeAuroraLabels()end
            local opaqueMenu=platform and view.scene~='map' and view.scene~='battle'
            if view.scene=='title' or view.scene=='gameover' or opaqueMenu then
                if mapGroup then
                    if mapView then mapView.close();mapView=nil end
                    ground.close();mapGroup,player,currentMap=nil,nil,nil
                end
            elseif currentMap~=view.world.mapId and (view.scene~='options' or currentMap~=nil) then
                buildMap(view);currentStructure=nil
            end
            -- Translucent source-mode menus retain a frozen backdrop; opaque
            -- platform menus release the covered map above.
            if mapView then
                if view.scene=='map' then mapView.update(view.world)end
            elseif player then
            ground.move(player,view.world.player.realX*48+8,view.world.player.realY*48+4)
            for _,event in ipairs(view.world.events) do
                local control=eventControls[event.id]
                local visible=event.page~=nil and event.page~=false
                if control and eventVisibility[event.id]~=visible then control:SetVisible(visible);eventVisibility[event.id]=visible end
            end end
            if view.scene=='aurora'then
                if not auroraPanelActive then
                    closeListRows();overlay.close();base.close();areas={};cursorDraws={};cursorStates={};layoutState=nil
                    closeBattleDraws();backgroundSurface.close();battleSurface.close();battleId=nil
                    currentStructure='aurora';auroraPanelActive=true
                    if not auroraPanel then auroraPanel=deps['platform.ugc.aurora'].new(host,root,bindings,ui,skin,data.auroraArt,function(action)return dispatch(action)end)end
                end
                currentToken=view.token;auroraPanel.render(view.aurora,currentToken);updates.flush();return
            elseif auroraPanelActive then auroraPanel.close();auroraPanelActive=false;auroraHud=nil end
            local message=view.message
            local messageKey=message and (tostring(message.taskId)..':'..tostring(message.token)) or ''
            if messageKey~=lastMessageKey then messagePrevious.choiceFirstVisibleRow=0;lastMessageKey=messageKey end
            local layout,key
            if message then
                if view.scene=='battle' and battleId~=view.battle.battleId then
                    buildBattleSurface(view,battleLayouts.battle({mode='wait',partyCount=#view.battle.party,rowCount=0}))
                end
                layout=messages.message(message,messagePrevious)
                messagePrevious.y=layout.message.rect.y
                messagePrevious.choiceFirstVisibleRow=layout.choices and layout.choices.firstVisibleRow or 0
                key=(view.scene=='battle' and 'battle-message:'..tostring(view.battle.battleId)..':' or 'message:')..messageKey..':'..messagePrevious.choiceFirstVisibleRow
                if view.input then
                    layout.input=systemLayouts.messageInput(view.input,layout,eventItemFirst)
                    if view.input.kind=='eventItem'then eventItemFirst=scroll(eventItemFirst,view.input.selectedIndex,layout.input.visibleRows,2);layout.input=systemLayouts.messageInput(view.input,layout,eventItemFirst)end
                    local parts={};if view.input.kind=='eventItem'then for _,r in ipairs(view.input.rows)do parts[#parts+1]=r.id..':'..r.count end end
                    key=key..':'..view.input.kind..':'..eventItemFirst..':'..table.concat(parts,';')
                end
            elseif view.scene=='title' or view.scene=='gameEnd' or view.scene=='gameover'then layout=systemLayouts[view.scene]();key=view.scene
            elseif view.scene=='name'then layout=systemLayouts.name(view.input);key='name:'..view.input.actorId..':'..view.input.maxLength
            elseif view.scene=='battle' then
                local b=view.battle;local indices={};for _,r in ipairs(b.rows) do if r.index then indices[#indices+1]=r.index end end
                local background=b.backgroundList
                if battleId~=b.battleId then battleFirst,battleListFirst,battleLastMode=0,0,nil end
                if background and battleLastMode~='target' then battleListFirst=battleFirst end
                if (b.mode=='skill' or b.mode=='item') and battleLastMode=='target' then battleFirst=battleListFirst end
                local backgroundFirst=background and battleListFirst or 0
                local options={mode=b.mode,partyCount=#b.party,rowCount=#b.rows,firstRow=battleFirst,targetSide=b.targetSide,targetIndices=indices,backgroundMode=background and background.mode,backgroundCount=background and #background.rows,backgroundFirstRow=backgroundFirst}
                layout=battleLayouts.battle(options)
                local cols=(b.mode=='party' or b.mode=='actor') and 1 or b.mode=='target' and b.targetSide=='actor' and (mz and 4 or 1) or 2
                battleFirst=scroll(battleFirst,b.selectedIndex,layout.list.visibleRows,cols);options.firstRow=battleFirst;layout=battleLayouts.battle(options)
                battleLastMode=b.mode
                local retainedList=platform and (b.mode=='skill' or b.mode=='item')
                local rowKeys={};if not retainedList then for _,r in ipairs(b.rows) do rowKeys[#rowKeys+1]=table.concat({r.id or r.index or r.command or '',r.name or '',tostring(r.enabled),r.count or '',r.cost and r.cost.mp or '',r.cost and r.cost.tp or ''},'|') end end
                if b.backgroundList then for _,r in ipairs(b.backgroundList.rows)do
                    rowKeys[#rowKeys+1]=table.concat({'pending',r.id or '',r.name or '',tostring(r.enabled),r.count or '',r.cost and r.cost.mp or '',r.cost and r.cost.tp or ''},'|')
                end end
                key=table.concat({'battle',b.battleId,b.mode,retainedList and 0 or battleFirst,#b.rows,platform and '' or b.help,b.result and b.result.code or -1,b.resultPage or 0,table.concat(rowKeys,';')},':')
            elseif view.scene=='menu' then
                layout=menus.menu({actorCount=#view.members,commandCount=#view.menu.commands,commandFirstRow=commandFirst,memberFirstRow=memberFirst})
                commandFirst=scroll(commandFirst,view.menu.selectedIndex,layout.mainCommand.visibleRows)
                memberFirst=scroll(memberFirst,view.memberIndex,layout.members.visibleRows)
                layout=menus.menu({actorCount=#view.members,commandCount=#view.menu.commands,commandFirstRow=commandFirst,memberFirstRow=memberFirst})
                key='menu:'..commandFirst..':'..memberFirst..':'..table.concat(view.world.party.members,',')
            elseif view.scene=='item' then
                layout=menus.item({itemCount=#view.items.rows,categoryCount=#view.items.categories,firstRow=itemFirst})
                itemFirst=scroll(itemFirst,view.items.selectedIndex,layout.items.visibleRows,2)
                local options={itemCount=#view.items.rows,categoryCount=#view.items.categories,firstRow=itemFirst,targeting=view.items.targeting,
                    selectedIndex=view.items.targetItemIndex or view.items.selectedIndex,actorCount=#view.members,actorFirstRow=itemActorFirst}
                layout=menus.item(options)
                if layout.itemActors then
                    itemActorFirst=scroll(itemActorFirst,view.items.targetIndex,layout.itemActors.visibleRows)
                    options.actorFirstRow=itemActorFirst;layout=menus.item(options)
                end
                local items=view.items
                key=table.concat({'item',items.categoryIndex,platform and 0 or itemFirst,platform and '' or items.help,tostring(items.targeting),
                    items.targetItemId or 0,items.targetItemIndex or 0,itemActorFirst,items.revision},':')
            elseif view.scene=='status' then
                layout=menus.status({equipmentCount=#view.status.actorView.equipment})
                key='status:'..view.status.actorId
            elseif view.scene=='equip' then
                local e=view.equip
                local options={mode=e.mode,slotCount=#e.slots,itemCount=#e.items,slotScrollY=e.slotScrollY,itemScrollY=e.itemScrollY,preview=e.previewActor~=nil}
                layout=equipmentLayouts.equip(options)
                local slot=platform and mz and e.mode=='slot' and -1 or e.slotIndex
                key=table.concat({'equip',e.actorId,e.mode,slot,platform and -1 or e.itemIndex,e.revision,platform and 0 or e.slotScrollY,platform and 0 or e.itemScrollY,tostring(e.previewActor~=nil)},':')
            elseif view.scene=='extension'then
                local v=view.extension
                layout=auxiliary.extension(v,auxFirst);auxFirst=scroll(auxFirst,v.selectedIndex,layout.list.visibleRows)
                layout=auxiliary.extension(v,auxFirst)
                key=table.concat({'extension',v.extensionId,v.id,#v.rows,auxFirst},':')
            elseif view.scene=='skill' or view.scene=='shop' or view.scene=='options' then
                local v=view.scene=='skill' and view.skill or view.scene=='shop' and view.shop or view.options
                layout=auxiliary[view.scene](v,auxFirst,auxTypeFirst)
                if view.scene=='skill'then auxTypeFirst=scroll(auxTypeFirst,v.typeIndex,layout.types.visibleRows)end
                auxFirst=scroll(auxFirst,v.selectedIndex,layout.list and layout.list.visibleRows or 1,(view.scene=='skill' or view.scene=='shop' and v.mode=='sell') and 2 or 1)
                layout=auxiliary[view.scene](v,auxFirst,auxTypeFirst)
                if view.scene=='skill' and v.targeting then
                    local actorLayout=menus.item({itemCount=0,categoryCount=0,firstRow=0,targeting=true,selectedIndex=v.selectedIndex,actorCount=#view.members,actorFirstRow=auxActorFirst})
                    auxActorFirst=scroll(auxActorFirst,v.targetIndex,actorLayout.itemActors.visibleRows)
                    actorLayout=menus.item({itemCount=0,categoryCount=0,firstRow=0,targeting=true,selectedIndex=v.selectedIndex,actorCount=#view.members,actorFirstRow=auxActorFirst})
                    layout.itemActors=actorLayout.itemActors
                end
                if platform and view.scene=='options' then
                    -- Selection and values do not change the window structure.
                    -- Keep text controls, hit areas and the cursor alive.
                    local labels={};for _,entry in ipairs(v.rows)do labels[#labels+1]=#entry.label..':'..entry.label end
                    key='options:'..auxFirst..':'..table.concat(labels,';')
                elseif platform and view.scene=='shop' and v.mode=='number' then
                    key=table.concat({'shop-number',v.pendingMode,v.pending.kind,v.pending.id,v.pending.price,v.contentRevision,v.gold,v.comparison and v.comparison.pageIndex or 0},':')
                elseif platform and view.scene=='shop' and (v.mode=='buy' or v.mode=='sell') then
                    key=table.concat({'shop-list',v.mode,v.categoryIndex,v.contentRevision,v.gold,tostring(v.pageButtonsEnabled)},':')
                elseif platform and view.scene=='skill' and v.mode~='actor' then
                    key=table.concat({'skill',v.actorId,v.typeIndex,v.contentRevision,auxTypeFirst},':')
                else key=table.concat({view.scene,v.mode or '',v.actorId or 0,v.revision,v.selectedIndex,v.targetIndex or 0,auxFirst,auxActorFirst,auxTypeFirst,v.help or ''},':')end
            else key='map:'..tostring(view.world.mapId)..':'..tostring(not view.world.access or view.world.access.menu) end
            if key~=currentStructure then
                scrollTouch=false
                closeListRows();overlay.close();cursorDraws={};persistentCursor=nil;base.close();areas={}
                screenGroup=base.group('RPG scene '..view.scene,rect(0,0,ui.screen.width,ui.screen.height))
                if view.scene~='map' and view.scene~='battle' then base.solid(screenGroup,'RPG menu shade',rect(0,0,ui.screen.width,ui.screen.height),platform and {20,26,42,255} or {0,0,0,63}) end
                if message then buildMessage(view,layout)
                elseif view.scene=='battle' then buildBattle(view,layout)
                elseif view.scene=='menu' then buildMenu(view,layout)
                elseif view.scene=='item' then buildItem(view,layout) end
                if view.scene=='status' then buildStatus(view,layout) end
                if view.scene=='equip' then buildEquipment(view,layout) end
                if view.scene=='skill' or view.scene=='shop' or view.scene=='options' then buildAuxiliary(view,layout)end
                if view.scene=='extension'then buildExtension(view,layout)end
                if view.scene=='title' or view.scene=='gameEnd' or view.scene=='gameover' or view.scene=='name'then buildSystem(view,layout)end
                if message and view.input then buildMessageInput(view,layout)end
                if not message then sourceButtons(view) end
                currentStructure=key;layoutState=layout;currentToken=nil
            end
            if auroraHud and auroraHud.alive and view.scene=='map'and auroraHud.text~=view.world.auroraHud then base.updateText(auroraHud,view.world.auroraHud,rect(20,54,ui.screen.width-50,56),20)end
            updateAuroraLabels(view)
            if platform and view.scene=='skill' and not message then
                -- Refresh row coordinates while retaining the window model used by cursors.
                layoutState.list.rows=layout.list.rows
                updateAuxRows(view,layoutState)
            end
            if platform and view.scene=='shop' and not message then
                if layoutState.list then layoutState.list.rows=layout.list.rows;updateAuxRows(view,layoutState)end
                updateShopStatus(view.shop,layoutState.status)
            end
            if platform and view.scene=='item' and not message then
                layoutState.items.rows=layout.items.rows
                updateItemRows(view,layoutState)
            end
            if platform and view.scene=='equip' and not message then
                layoutState.slots.rows=layout.slots.rows;layoutState.items.rows=layout.items.rows
                updateEquipmentRows(view,layoutState)
            end
            if platform and view.scene=='battle' and not message and (view.battle.mode=='skill' or view.battle.mode=='item') then
                layoutState.list.rows=layout.list.rows;updateAuxRows(view,layoutState)
            end
            if view.scene=='battle' then updateBattleSurface(view)
            elseif battleId then closeBattleDraws();backgroundSurface.close();battleSurface.close();battleId,battleDraws=nil,nil end
            if view.world.presentation and (mapGroup or view.scene=='battle') then
                if not presentationView then presentationView=presentationViews.new(host,root,bindings,ui,skin)end
                local battlefield=view.scene=='battle' and battleDraws and battleDraws.field
                local function locate(target)
                    if battlefield and type(target)=='table' then
                        local pool=battleDraws.centres[target.kind];return pool and pool[target.kind=='actor' and target.id or target.troopSlot]
                    end
                    return mapView and mapView.locate(target)
                end
                local parent=battlefield and battlefield.object or mapGroup and mapGroup.object
                presentationView.update(view.world.presentation,view.world,locate,parent,battlefield and transformBattler or nil)
                local screen=view.world.presentation.screen;local shake=screen.shakeX or screen.shake or 0;local shakeY=screen.shakeY or 0
                local group=battlefield or mapGroup
                if group and (group.shake~=shake or group.shakeY~=shakeY)then updates.call(group.object,'SetAnchoredPosition',shake,-shakeY);group.shake,group.shakeY=shake,shakeY end
            elseif presentationView then presentationView.close();presentationView=nil
            end
            updateSystem(view)
            local mapName=view.world.mapName
            local nameVisible=not data.aurora and view.scene=='map' and mapName and mapName.name~='' and mapName.opacity>0
            if nameVisible and not mapNameGroup then
                mapNameGroup=timerSurface.group('RPG map name',rect(0,0,360,60))
                mapNameBack=timerSurface.solid(mapNameGroup,'RPG map name background',rect(0,0,360,60),{0,0,0,128})
                mapNameText=timerSurface.text(mapNameGroup,'RPG map name text','',rect(12,12,336,36),ui.window.fontSize)
                mapNameText.horizontalAlignment=enum.TextHorizontalAlignment.Middle
            end
            if mapNameGroup then
                timerSurface.show(mapNameGroup,nameVisible==true)
                if nameVisible then
                    updates.set(mapNameText,'text',mapName.name)
                    updates.set(mapNameText,'fontColor',color.FromRGBA(255,255,255,mapName.opacity),mapName.opacity)
                    updates.set(mapNameBack,'bgColor',color.FromRGBA(0,0,0,math.floor(mapName.opacity/2)),mapName.opacity)
                    if not mapNameGroup.shown then mapNameGroup.object:SetAsLastSibling()end
                end
                mapNameGroup.shown=nameVisible
            end
            local timer=view.world.timer
            local timerVisible=timer and timer.working and (view.scene=='map' or view.scene=='battle')
            if timerVisible and not timerGroup then
                timerGroup=timerSurface.group('RPG timer',rect(ui.screen.width-96,0,96,48))
                timerSurface.solid(timerGroup,'RPG timer background',rect(0,0,96,48),{0,0,0,128})
                timerText=timerSurface.text(timerGroup,'RPG timer seconds','00:00',rect(0,0,96,48),32)
                timerText.horizontalAlignment=enum.TextHorizontalAlignment.Middle
            end
            if timerGroup then
                timerSurface.show(timerGroup,timerVisible==true)
                if timerVisible then
                    updates.set(timerText,'text',string.format('%02d:%02d',math.floor(timer.seconds/60)%60,timer.seconds%60))
                    if timerGroup.scene~=view.scene then timerGroup.object:SetAsLastSibling();timerGroup.scene=view.scene end
                end
            end
            if message then updateMessage(view,layoutState)end
            if view.scene=='extension' and not message then updateExtension(view)end
            if platform and view.scene=='equip' and not message then
                local e,d=view.equip,equipmentDraws
                for param,drawing in pairs(d.preview)do
                    local value=e.previewActor.stats.params[param];local delta=value-e.actorView.stats.params[param]
                    local colorIndex=delta>0 and 24 or delta<0 and 25 or 0
                    base.updateText(drawing.object,number(value),drawing.rect,ui.window.fontSize)
                    updates.set(drawing.object,'fontColor',color.FromRGBA(table.unpack(ink(colorIndex))),colorIndex)
                end
            end
            if platform and view.scene=='options' and not message then
                for index,drawing in pairs(optionDraws)do
                    base.updateText(drawing.object,view.options.rows[index].status,drawing.rect,ui.window.fontSize)
                end
            end
            if platform and not message then updateHelp(view)end
            if platform and view.scene=='shop' and view.shop.mode=='number' and not message then
                local v,d=view.shop,shopNumberDraws
                base.updateText(d.quantity,'× '..number(v.quantity),d.quantityRect,ui.window.fontSize)
                base.updateText(d.total,number(v.quantity*v.pending.price)..' '..ui.currencyUnit,d.totalRect,ui.window.fontSize)
            end
            if currentToken~=view.token then
                local model,row
                if message and view.input and (not view.messageFlow or view.messageFlow.inputReady) then model=layoutState.input;row=selectedRow(model,view.input.selectedIndex)
                elseif message and layoutState.choices and (not view.messageFlow or view.messageFlow.inputReady) then model=layoutState.choices;row=layout.choices.cursor
                elseif view.scene=='title' or view.scene=='gameEnd'then model=layoutState.command;row=selectedRow(model,view.system.selectedIndex)
                elseif view.scene=='name'then model=layoutState.list;row=selectedRow(model,view.input.selectedIndex)
                elseif view.scene=='extension'then model=layoutState.list;row=selectedRow(model,view.extension.selectedIndex)
                elseif platform and view.scene=='options'then model=layoutState.list;row=selectedRow(model,view.options.selectedIndex)
                elseif platform and view.scene=='battle' and (view.battle.mode=='skill' or view.battle.mode=='item' or view.battle.mode=='party' or view.battle.mode=='actor')then
                    local b=view.battle;model=layoutState[(b.mode=='party' or b.mode=='actor') and 'command' or 'list'];row=selectedRow(model,b.selectedIndex)
                elseif platform and view.scene=='shop' and (view.shop.mode=='buy' or view.shop.mode=='sell')then
                    model=layoutState.list;row=selectedRow(model,view.shop.selectedIndex)
                elseif platform and view.scene=='skill' and view.skill.mode~='actor'then
                    local v=view.skill;model=layoutState[v.mode=='type' and 'types' or 'list']
                    row=selectedRow(model,v.mode=='type' and v.typeIndex or v.selectedIndex)
                elseif platform and view.scene=='item' and view.focus=='item'then
                    model=layoutState.items;row=selectedRow(model,view.items.selectedIndex)
                elseif platform and view.scene=='equip'then
                    local e=view.equip;model=layoutState[e.mode=='command' and 'command' or e.mode=='slot' and 'slots' or 'items']
                    row=selectedRow(model,e.mode=='command' and e.commandIndex or e.mode=='slot' and e.slotIndex or e.itemIndex)
                end
                local retainedCursor=persistentCursor
                if platform and (view.scene=='equip' or view.scene=='item') then for _,drawing in ipairs(cursorDraws)do if drawing.model==model then retainedCursor=drawing;break end end end
                local retained=model and row and retainedCursor and retainedCursor.model==model and retainedCursor.group.object.alive
                retained=retained or platform and view.scene=='shop' and view.shop.mode=='number' and not message
                if retained then
                    if model then
                        local r=localRect(row,model.rect)
                        overlay.move(retainedCursor.group,r.x,r.y)
                    end
                else
                overlay.close();cursorDraws={};persistentCursor=nil
                if message and view.input and (not view.messageFlow or view.messageFlow.inputReady) then selectCursor(layoutState.input,selectedRow(layoutState.input,view.input.selectedIndex),'RPG event input cursor','eventInput')
                elseif message and layoutState.choices and (not view.messageFlow or view.messageFlow.inputReady) then selectCursor(layoutState.choices,layout.choices.cursor,'RPG choice cursor','choices')
                elseif not message and view.scene=='battle' then
                    local b=view.battle;local name=(b.mode=='party' or b.mode=='actor') and 'command' or (b.mode=='skill' or b.mode=='item') and 'list' or b.mode=='target' and 'targets' or b.mode=='result' and 'result'
                    if name then selectCursor(layoutState[name],selectedRow(layoutState[name],b.selectedIndex),'RPG battle cursor',({command='battleCommand',list='battleList',targets='battleTargets',result='battleResult'})[name]) end
                    if b.backgroundList then selectCursor(layoutState.list,selectedRow(layoutState.list,b.backgroundList.selectedIndex),'RPG battle pending cursor','battleList') end
                elseif view.scene=='menu' then
                    selectCursor(layoutState.mainCommand,selectedRow(layoutState.mainCommand,view.menu.selectedIndex),'RPG command cursor','mainCommand')
                    if view.menu.formation and view.menu.pendingIndex>=0 then
                        local model=layoutState.members;local row=selectedRow(model,view.menu.pendingIndex)
                        if row then
                            local c=model.contents;local top,bottom=math.max(row.y,c.y),math.min(row.y+row.height,c.y+c.height)
                            if bottom>top then
                                local pending=overlay.group('RPG formation pending',localRect(rect(row.x,top,row.width,bottom-top),model.rect),model.group)
                                overlay.solid(pending,'RPG formation pending fill',rect(0,0,row.width,bottom-top),{255,255,255,64})
                                pending.object:SetSiblingIndex(model.cursorSibling)
                            end
                        end
                    end
                    if view.focus=='actor' then selectCursor(layoutState.members,selectedRow(layoutState.members,view.memberIndex),'RPG member cursor','members') end
                elseif view.scene=='item' then
                    if layoutState.category.visible then selectCursor(layoutState.category,selectedRow(layoutState.category,view.items.categoryIndex),'RPG category cursor','category') end
                    if view.focus=='item' then selectCursor(layoutState.items,selectedRow(layoutState.items,view.items.selectedIndex),'RPG item cursor','items') end
                    if layoutState.itemActors then
                        if view.items.targetAll then
                            for _,row in ipairs(layoutState.itemActors.rows) do
                                selectCursor(layoutState.itemActors,row.rect,'RPG item actor cursor '..number(row.index),'itemActors')
                            end
                        else selectCursor(layoutState.itemActors,selectedRow(layoutState.itemActors,view.items.targetIndex),'RPG item actor cursor','itemActors') end
                    end
                end
                if view.scene=='equip' then
                    local e=view.equip
                    -- Deactivation retains a Window_Selectable cursor; only
                    -- deselection/hiding removes it in the original scene.
                    selectCursor(layoutState.command,selectedRow(layoutState.command,e.commandIndex),'RPG equip command cursor','command')
                    if layoutState.slots.visible then selectCursor(layoutState.slots,selectedRow(layoutState.slots,e.slotIndex),'RPG equip slot cursor','slots') end
                    if layoutState.items.visible then selectCursor(layoutState.items,selectedRow(layoutState.items,e.itemIndex),'RPG equip item cursor','items') end
                end
                if view.scene=='skill' or view.scene=='shop' or view.scene=='options'then
                    local v=view.scene=='skill' and view.skill or view.scene=='shop' and view.shop or view.options
                    local name,index='list',v.selectedIndex
                    if view.scene=='skill' and v.mode=='type'then name,index='types',v.typeIndex
                    elseif view.scene=='skill' and v.mode=='actor'then name,index='itemActors',v.targetIndex
                    elseif view.scene=='shop' and v.mode=='command'then name,index='command',v.commandIndex
                    elseif view.scene=='shop' and v.mode=='category'then name,index='category',v.categoryIndex
                    elseif view.scene=='shop' and v.mode=='number'then name=nil end
                    if name and layoutState[name]then
                        if v.targetInfo and v.targetInfo.all then for _,row in ipairs(layoutState[name].rows)do selectCursor(layoutState[name],row.rect,'RPG skill all cursor '..number(row.index),name)end
                        else selectCursor(layoutState[name],selectedRow(layoutState[name],index),'RPG auxiliary cursor',name)end
                    end
                end
                if view.scene=='title' or view.scene=='gameEnd'then selectCursor(layoutState.command,selectedRow(layoutState.command,view.system.selectedIndex),'RPG system cursor','systemCommand')end
                if view.scene=='name'then selectCursor(layoutState.list,selectedRow(layoutState.list,view.input.selectedIndex),'RPG name cursor','nameGrid')end
                if view.scene=='extension'then selectCursor(layoutState.list,selectedRow(layoutState.list,view.extension.selectedIndex),'RPG extension cursor','list')end
                if model and row then persistentCursor=cursorDraws[1]end
                end
                -- Cursors belong behind content, otherwise their translucent pixels tint text.
                if not retained then for _,entry in ipairs(areas) do entry.area.object:SetAsLastSibling() end end
                bindAreas(view);currentToken=view.token
            end
            if base.pending()==0 then base.flush(2048) end
            if presentationView then presentationView.raiseVideo()end
            updates.flush()
            -- Normal frame cleanup runs once in updateFrame; render can be
            -- entered inside that transaction or directly from input.
        end
        dispatch=function(action)
            if not active or base.pending()>0 then return false end
            errorContext.phase='input';errorContext.action=action.kind..':'..tostring(action.direction or action.index or '')
            local ok,result=xpcall(function()local accepted,view=scene.dispatch(action);render(view);return accepted end,captureError)
            if not ok then abort(result)end;return result
        end
        local function update(dt)
            if not active then return end
            if type(dt)~='number' or dt~=dt or dt<0 or dt>9007199254740990/60 then fail('E_UI_TIME','Invalid frame delta') end
            uiRemainder=uiRemainder+dt*60
            local uiFrames=math.floor(uiRemainder+.000000001);uiRemainder=uiRemainder-uiFrames
            if mapView and lastScene=='map' then mapView.advance(uiFrames)end
            if base.pending()>0 then
                animateCursors(uiFrames)
                if base.flush(2048) and layoutState then
                    for _,model in pairs(layoutState) do
                        if type(model)=='table' and model.cursorGroup then model.cursorGroup.object:SetSiblingIndex(model.cursorSibling) end
                    end
                    for _,drawing in ipairs(cursorDraws) do drawing.group.object:SetSiblingIndex(drawing.model.cursorSibling) end
                end
                return
            end
            if lastScene=='map' or lastScene=='battle' or lastScene=='aurora' then
                if lastScene=='battle'then battleIconFrame=battleIconFrame+uiFrames end
                remainder=remainder+dt*60
                local frames=math.floor(remainder+.000000001);remainder=remainder-frames
                render(scene.tick(frames,true,scrollTouch or next(fastKeys)~=nil))
            end
            animateCursors(uiFrames)
        end
        local function updateFrame(dt)
            errorContext.phase='control_recycle'
            recycling.flush()
            errorContext.phase='world_update';errorContext.dt=dt
            update(dt)
            errorContext.phase='control_flush'
            updates.flush()
            errorContext.phase='control_prune'
            updates.prune()
        end
        function api.update(dt)
            updates.begin()
            local ok,reason=xpcall(updateFrame,captureError,dt)
            if not ok then abort(reason)end
        end
        function api.stats()return{controlUpdates=updates.stats(),recycling=recycling.stats(),map=mapView and mapView.stats()}end
        function api.close()
            if not active then return end
            active=false
            -- Restore before resource cleanup, which itself may fail.
            if root.alive then root.disableKeyEventPassthrough=oldKeyPassthrough end
            scene.close()
            if auroraPanel then auroraPanel.close();auroraPanel=nil end
            closeAuroraLabels()
            for _,entry in ipairs(listeners) do if root.alive then root:RemoveKeyEventListener(entry.key,entry.callback) end end
            if mapView then mapView.close();mapView=nil end
            if presentationView then presentationView.close();presentationView=nil end
            timerSurface.close()
            backgroundSurface.close()
            closeBattleDraws()
            listeners={};closeListRows();overlay.close();cursorDraws={};cursorStates={};base.close();ground.close();battleSurface.close()
            if blackBackground then game.DestroyClientUIControl(blackBackground);blackBackground=nil end
            if root.alive then root.showCursor=oldCursor end
            if host.script.alive then host.script:EnableUpdate(false) end
            updates.clear()
        end
        local ok,reason=pcall(function()
            -- Consume keys at the script's host container, before listeners are
            -- registered, so WASD/skills do not also control the underlying 3D game.
            root.disableKeyEventPassthrough=true
            root.showCursor=true
            local cw,ch=game.GetUICanvasSize();local scale=math.min(cw/ui.screen.width,ch/ui.screen.height)
            root:SetAnchorMin(.5,.5);root:SetAnchorMax(.5,.5);root:SetPivot(.5,.5)
            root:SetAnchoredPosition(0,0);root:SetSizeDelta(ui.screen.width,ui.screen.height);root:SetLocalScale(scale,scale,1)
            -- One persistent opaque image covers the entire host canvas, including
            -- letterbox margins. It is independent of map/menu reclamation and tone.
            blackBackground=game.InstantiateClientUIControl(bindings.imageTemplate,root)
            if not blackBackground then fail('E_PLATFORM_TEMPLATE','Missing black background image template')end
            blackBackground.name='RPG black background'
            blackBackground:SetImage(enum.ImageSource.StaticReference,bindings.whiteImageId)
            blackBackground.imageColor=color.FromRGBA(0,0,0,255)
            blackBackground.enableMask=false;blackBackground.enableSoftEdge=false;blackBackground:SetFillUnused()
            blackBackground:SetAnchorMin(.5,.5);blackBackground:SetAnchorMax(.5,.5);blackBackground:SetPivot(.5,.5)
            blackBackground:SetAnchoredPosition(0,0);blackBackground:SetSizeDelta(cw/scale,ch/scale)
            blackBackground:SetActive(true);blackBackground:SetVisible(true);blackBackground:SetAsFirstSibling()
            local keys={
                {'KeyboardCraftspersonKey36Down','navigate',8},{'KeyboardCraftspersonKey37Down','navigate',2},
                {'KeyboardCraftspersonKey38Down','navigate',4},{'KeyboardCraftspersonKey39Down','navigate',6},
                {'KeyboardMoveForwardKeyDown','navigate',8},{'KeyboardMoveBackwardKeyDown','navigate',2},
                {'KeyboardMoveLeftKeyDown','navigate',4},{'KeyboardMoveRightKeyDown','navigate',6},
                {'KeyboardCraftspersonKey12Down','confirm'},{'KeyboardJumpKeyDown','confirm'},
                {'KeyboardInteractKeyDown','confirm'},{'KeyboardDropKeyDown','cancel'},
                {'KeyboardCharacterSkill1KeyDown','menu'},{'KeyboardCharacterSkill2KeyDown','page',4},
                {'ControllerMenuConfirmKeyDown','confirm'},{'ControllerMenuBackKeyDown','cancel'},
                {'KeyboardCraftspersonKey40Down',false,nil,'control'},
                {'KeyboardSwitchToWalkOrRunKeyDown',false,nil,'control'},
                {'KeyboardOpenShortcutWheelKeyDown',false,nil,'tab'},
                {'KeyboardCharacterSkill3KeyDown','page',6,'pagedown'},
                {'KeyboardCraftspersonKey41Down',false,nil,'shift'},
            }
            for _,binding in ipairs(keys) do
                local logical=binding[4] or (binding[2]=='navigate' and ({[2]='down',[4]='left',[6]='right',[8]='up'})[binding[3]])
                    or ({confirm='ok',cancel=binding[1]=='KeyboardDropKeyDown' and 'escape' or 'cancel',menu='menu',page='pageup'})[binding[2]]
                local key=enum.KeyEventType[binding[1]]
                if not key then fail('E_PLATFORM_KEY','Missing documented key enum: '..binding[1]) end
                local callback=function()
                    if not active then return false end
                    scene.setButton(binding[1],logical,true)
                    local kind,direction=binding[2],binding[3]
                    if kind=='confirm' then fastKeys[binding[1]]=true end
                    if logical=='shift' then fastKeys.shift=true end
                    if binding[1]=='KeyboardMoveForwardKeyDown' and (lastScene=='status' or lastScene=='equip' or lastScene=='skill' or lastScene=='shop') then kind,direction='page',6 end
                    if kind then dispatch({kind=kind,direction=direction,token=currentToken})end
                    return true
                end
                root:AddKeyEventListener(key,callback);listeners[#listeners+1]={key=key,callback=callback}
                local up=enum.KeyEventType[binding[1]:gsub('Down$','Up')]
                if not up then fail('E_PLATFORM_KEY','Missing documented release enum: '..binding[1])end
                local release=function()
                    if not active then return false end
                    scene.setButton(binding[1],logical,false);fastKeys[binding[1]]=nil
                    if logical=='shift' then fastKeys.shift=nil end
                    return true
                end
                root:AddKeyEventListener(up,release);listeners[#listeners+1]={key=up,callback=release}
            end
            for _,entry in ipairs(scene.extensionShortcuts())do
                if entry.keyEvent and entry.keyEvent~=''then
                    local key=enum.KeyEventType[entry.keyEvent]
                    if not key then fail('E_PLATFORM_KEY','Missing extension key enum: '..entry.keyEvent)end
                    local callback=function()if active then return dispatch({kind='extension_menu',extensionId=entry.extensionId,menuId=entry.id,token=currentToken})end end
                    root:AddKeyEventListener(key,callback);listeners[#listeners+1]={key=key,callback=callback}
                end
            end
            render(scene.tick(0,true));host.script:EnableUpdate(true)
        end)
        if not ok then api.close();error(reason,0) end
        return api
    end
    return M
end
