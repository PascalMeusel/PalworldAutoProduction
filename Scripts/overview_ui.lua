local U = require("ap_util")
local scene = require("overview_scene")
local M = {pool = {}, nodes = {}, visible = false}
local tab_click_hooks={}
local text_library
local text_warnings={}
local open_generation=0
local input_session
local MENU_ASSET="/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu"
local TAB_CLICK_EVENT="BndEvt__WBP_MainMenu_Tab_WBP_PalCommonButton_K2Node_ComponentBoundEvent_1_CommonButtonBaseClicked__DelegateSignature"
local function linear(v)
    v=v/255
    return v<=0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4
end
local function color(hex,alpha)
    return {R=linear(tonumber(hex:sub(2,3),16)),G=linear(tonumber(hex:sub(4,5),16)),B=linear(tonumber(hex:sub(6,7),16)),A=alpha or 1}
end
local function make(class, outer)
    local cls=StaticFindObject("/Script/UMG."..class)
    assert(U.valid(cls),class.." class unavailable")
    local object=StaticConstructObject(cls,outer)
    assert(U.valid(object),class.." construction failed")
    return object
end
local function native_text(value,id)
    value=U.truncate_text(value,512)
    if value=="" then return nil end
    if not U.valid(text_library) then text_library=StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end
    local ok,converted=pcall(function() return text_library:Conv_StringToText(value) end)
    if ok then return converted end
    if not text_warnings[id] then
        text_warnings[id]=true
        U.log("Text conversion fallback for overview element "..id..": "..tostring(converted):match("^[^\n]+"))
    end
    -- A rejected label must not stop all following stats/controls rendering.
    local fallback=value:gsub("[\128-\255]","?")
    if fallback==value then fallback="Text unavailable" end
    ok,converted=pcall(function() return text_library:Conv_StringToText(fallback) end)
    return ok and converted or nil
end
local function set_text(widget,value,size,ink,id)
    local text=native_text(value,id)
    -- Empty text never crosses the loader's unsafe FText argument bridge.
    if not text then widget:SetVisibility(1);return end
    widget:SetText(text)
    local font=widget.Font; font.Size=size
    if M.native_font then font.FontObject=M.native_font.FontObject;font.TypefaceFontName=M.native_font.TypefaceFontName
    else font.TypefaceFontName=FName("Regular") end
    widget:SetFont(font)
    widget:SetColorAndOpacity({SpecifiedColor=color(ink),ColorUseRule=0})
    widget:SetVisibility(3)
end
local function box(canvas,child,x,y,w,h)
    local slot=canvas:AddChildToCanvas(child)
    slot:SetPosition({X=x,Y=y}); slot:SetSize({X=w,Y=h}); slot:SetAutoSize(false)
    return slot
end
function M.build()
    if U.valid(M.widget) and U.read(function() return M.widget:IsInViewport() end) then return true end
    local pc=U.controller()
    if not pc then return false end
    local ok,err=pcall(function()
        M.widget=make("UserWidget",pc)
        M.widget:SetOwningPlayer(pc)
        M.tree=make("WidgetTree",M.widget); M.widget.WidgetTree=M.tree
        local root=make("CanvasPanel",M.tree); M.tree.RootWidget=root
        local scale=make("ScaleBox",M.tree); scale:SetStretch(2)
        local size=make("SizeBox",M.tree); size:SetWidthOverride(scene.width); size:SetHeightOverride(scene.height)
        M.canvas=make("CanvasPanel",M.tree); size:SetContent(M.canvas); scale:SetContent(size)
        M.root=root
        M.frame=box(root,scale,0,0,1200,720)
        M.frame:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
        M.frame:SetAlignment({X=0.5,Y=0.5})
        root:SetVisibility(4)
        M.widget.bIsFocusable=false
        M.widget:AddToViewport(20010)
        M.widget:SetVisibility(1)
        M.pool={}
        M.viewport_key=nil
    end)
    if not ok then
        if U.valid(M.widget) then pcall(function() M.widget:RemoveFromParent() end) end
        M.widget=nil;U.log("Overview construction failed: "..tostring(err))
    end
    return ok
end
function M.render(nodes)
    if not M.build() then return false end
    local ok,err=pcall(function()
        local library=StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local pc=U.controller()
        local viewport=U.valid(library) and U.read(function() return library:GetViewportSize(pc) end)
        local dpi=U.valid(library) and U.number(U.read(function() return library:GetViewportScale(pc) end)) or 1
        if viewport and dpi and dpi>0 then
            local w,h=viewport.X/dpi,viewport.Y/dpi
            local key=w..":"..h
            if M.viewport_key~=key then
                M.viewport_key=key
                -- Keep the menu's tab bar and footer outside the content hit area.
                M.frame:SetSize({X=math.max(320,w*0.86),Y=math.max(240,h*0.76)})
                M.frame:SetPosition({X=0,Y=0})
            end
        end
        local active={}; M.nodes=nodes
        for order,n in ipairs(nodes) do
            active[n.id]=true
            local p=M.pool[n.id]
            if n.kind=="scroll" then
                if not p then
                    p={};M.pool[n.id]=p
                    p.widget=make("ScrollBox",M.tree)
                    p.widget:SetOrientation(1)
                    p.widget:SetConsumeMouseWheel(1) -- Always consume, including at the ends.
                    p.widget:SetAllowOverscroll(false)
                    p.widget:SetAnimateWheelScrolling(true)
                    p.widget:SetWheelScrollMultiplier(1.5)
                    p.widget:SetScrollbarThickness({X=6,Y=6})
                    p.widget:SetScrollbarPadding({Left=10,Top=0,Right=0,Bottom=0})
                    pcall(function()
                        local style=p.widget.WidgetBarStyle
                        for _,field in ipairs({"NormalThumbImage","HoveredThumbImage","DraggedThumbImage"}) do
                            local brush=style[field]
                            brush.TintColor={SpecifiedColor=color(scene.colors.blue),ColorUseRule=0};style[field]=brush
                        end
                        p.widget.WidgetBarStyle=style
                    end)
                    p.widget:SetClipping(1)
                    p.widget.bAllowRightClickDragScrolling=false -- Right-click edits priorities.
                    p.size=make("SizeBox",M.tree)
                    p.canvas=make("CanvasPanel",M.tree)
                    p.size:SetContent(p.canvas);p.widget:AddChild(p.size)
                    p.slot=box(M.canvas,p.widget,n.x,n.y,n.w,n.h)
                end
                local geometry=table.concat({n.x,n.y,n.w,n.h,n.content_height},":")
                if p.geometry~=geometry then
                    p.slot:SetPosition({X=n.x,Y=n.y});p.slot:SetSize({X=n.w,Y=n.h})
                    p.size:SetHeightOverride(n.content_height);p.size:SetWidthOverride(n.w-18);p.geometry=geometry
                    pcall(function() p.widget:SetScrollBarVisibility(n.content_height>n.h and 0 or 1) end)
                end
                p.x,p.y,p.h=n.x,n.y,n.h
                if p.key~=n.key then p.widget:ScrollToStart();p.key=n.key end
                if p.hidden or not p.shown then p.widget:SetVisibility(0);p.shown=true end
                p.hidden=false
            else
            if not p then
                p={};M.pool[n.id]=p
                p.widget=make(n.kind=="text" and "TextBlock" or "Border",M.tree)
                p.widget:SetClipping(1) -- ClipToBounds, including native-font and CJK labels.
                if n.kind=="text" then p.widget:SetTextOverflowPolicy(1) end
                if n.kind=="button" then
                    p.label=make("TextBlock",M.tree);p.widget:SetContent(p.label)
                    p.widget:SetHorizontalAlignment(0);p.widget:SetVerticalAlignment(2)
                    p.widget:SetPadding({Left=8,Top=2,Right=8,Bottom=2})
                    p.label:SetJustification(1)
                    p.label:SetTextOverflowPolicy(1)
                end
                local canvas=n.parent and M.pool[n.parent].canvas or M.canvas
                p.slot=box(canvas,p.widget,n.x,n.y,n.w,n.h)
            end
            local x,y=n.x,n.y
            if n.parent then local area=M.pool[n.parent];x=x-area.x;y=y-area.y end
            local geometry=table.concat({n.x,n.y,n.w,n.h,order},":")
            if p.geometry~=geometry then
                p.slot:SetPosition({X=x,Y=y});p.slot:SetSize({X=math.max(0,n.w),Y=n.h});p.slot:SetZOrder(order)
                p.geometry=geometry
            end
            local visual=table.concat({n.text or "",n.size or "",n.color or "",n.ink or "",n.tooltip or "",n.alpha or 1},"|")
            if p.visual~=visual or p.hidden then
            if n.kind=="text" then
                set_text(p.widget,n.text,n.size,n.color,n.id)
                if n.tooltip and n.tooltip~="" then
                    local tip=native_text(n.tooltip,n.id.." tooltip")
                    if tip then p.widget:SetToolTipText(tip) end
                end
            else
                p.widget:SetBrushColor(color(n.color,n.alpha))
                p.widget:SetVisibility(n.id=="background" and 1 or (n.kind=="button" and 0 or 3))
                if p.label then
                    set_text(p.label,n.text,n.size,n.ink,n.id)
                    if n.tooltip and n.tooltip~="" then
                        local tip=native_text(n.tooltip,n.id.." tooltip")
                        if tip then p.widget:SetToolTipText(tip) end
                    end
                end
            end
            p.visual=visual;p.hidden=false
            end
            end
        end
        for id,p in pairs(M.pool) do if not active[id] and not p.hidden then p.widget:SetVisibility(1);p.hidden=true end end
    end)
    if not ok then
        local summary=tostring(err):match("^[^\n]+")
        if M.render_error~=summary then U.log("Overview render failed: "..tostring(err)) end
        M.render_error=summary
    else
        if not M.rendered_first or M.render_error then U.log("Overview rendered "..#nodes.." elements.") end
        M.rendered_first=true;M.render_error=nil
    end
    return ok
end
local function menu_active(menu)
    return U.live(menu) and U.visible(menu) and U.read(function() return menu:IsActivated() end)~=false
end
local function hud_service(pc)
    return U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetHUDService(pc) end)
end
function M.menu_active()
    return menu_active(M.menu)
end
function M.owns_menu_input()
    return input_session~=nil
end
local function watch_input(session)
    -- Keep ownership after leaving Bases for Party/Guild. Cached CommonUI
    -- widgets need not Destruct when closed, so observe this one menu only.
    U.defer(250,function()
        if input_session~=session then return end
        if not U.valid(session.pc) or U.address(U.controller())~=U.address(session.pc) then
            input_session=nil;return -- Never change another world's controller.
        end
        if not menu_active(session.menu) then
            if M.visible and U.address(M.menu)==U.address(session.menu) then M.hide(false) end
            local service=session.service
            if not U.valid(service) then service=hud_service(session.pc);session.service=service end
            -- A close animation or another modal may still own input. Do not
            -- enable gameplay beneath it; retry until the overlay stack clears.
            if U.read(function() return service:IsAnyOverlayUIActive() end)==false then
                local ok,err=pcall(function()
                    StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(session.pc,true)
                    session.pc.bShowMouseCursor=false
                end)
                if ok then
                    input_session=nil
                    U.log("Native menu closed; gameplay input restored.")
                    return
                elseif not session.warned then
                    session.warned=true;U.log("Menu input restoration retry: "..tostring(err))
                end
            end
        end
        watch_input(session)
    end)
end
local function own_menu_input(pc)
    if input_session and U.address(input_session.menu)==U.address(M.menu) and U.address(input_session.pc)==U.address(pc) then return end
    input_session={pc=pc,menu=M.menu,service=hud_service(pc)}
    watch_input(input_session)
end
function M.close_menu()
    if M.opening then M.cancel_open();return true end
    if not M.menu_active() then M.hide(false);return false end
    local service=hud_service(U.controller())
    local id=U.read(function() return M.menu:GetId() end)
    if U.guid(id) and U.read(function() return service:IsTopLayerUI(id) end)==false then return false end
    -- Close the stack entry itself, not just the added content panel. Keep the
    -- content intact until this succeeds; a failed close must not blank the UI.
    local ok,err=pcall(function() M.menu:Close() end)
    if ok then M.hide(false)
    else U.log("Native menu close failed: "..tostring(err)) end
    return ok
end
function M.cancel_open()
    open_generation=open_generation+1
    local pending=M.opening;M.opening=nil
    if pending and U.valid(pending.service) and pending.id then
        pcall(function() pending.service:Close(pending.id) end)
    end
end
function M.open_native_menu(on_ready)
    if M.menu_active() then on_ready();return true end
    if M.opening then return false end
    local ok,err=pcall(function()
        local pc=assert(U.controller(),"local player unavailable")
        local service=StaticFindObject("/Script/Pal.Default__PalUtility"):GetHUDService(pc)
        assert(U.valid(service),"native HUD service unavailable")
        assert(not service:IsAnyOverlayUIActive(),"close the current interaction window before opening Bases")
        local cls=StaticFindObject(MENU_ASSET.."_C")
        if not U.valid(cls) then LoadAsset(MENU_ASSET);cls=StaticFindObject(MENU_ASSET.."_C") end
        assert(U.valid(cls),"native main-menu class unavailable")
        local id=service:Push(cls,nil)
        assert(U.guid(id),"native menu was not opened")
        local request={service=service,id={A=id.A,B=id.B,C=id.C,D=id.D}}
        M.opening=request
        open_generation=open_generation+1
        local generation=open_generation
        local function ready(attempt)
            U.defer(100,function()
                if generation~=open_generation or M.opening~=request then return end
                local menu=U.read(function() return service:GetWidget(request.id) end)
                if U.live(menu) and U.visible(menu) and U.read(function() return menu:IsActivated() end)~=false
                    and M.attach_menu(menu) then
                    M.opening=nil;on_ready();return
                end
                if attempt<20 then ready(attempt+1)
                else M.cancel_open();U.log("Native menu did not become ready; open the normal menu and select Bases.") end
            end)
        end
        ready(1)
    end)
    if not ok then M.cancel_open();U.log("Cannot open Bases: "..tostring(err)) end
    return ok
end
function M.show()
    -- Every entry point must have a real CommonUI menu behind the overview.
    -- Never expose an independently clickable overlay over live gameplay.
    if not M.menu_active() then return false end
    if M.visible then return true end
    if not M.build() then return false end
    local pc=U.controller()
    M.visible=true
    local ok,err=pcall(function()
        -- Let the native overlay install its own consuming cancel bindings.
        -- UE4SS ba2efd55 crashes in push_delegateproperty when a callback is
        -- supplied as a UFunction argument; pcall cannot contain that crash.
        -- ResetCancelAction requires no delegate to cross the Lua bridge.
        M.menu:ResetCancelAction()
        M.native_mode=true
        M.hidden_content=M.menu.CurrentContentWidget
        if U.valid(M.hidden_content) then
            M.content_visibility=M.hidden_content:GetVisibility()
            M.hidden_content:SetVisibility(1)
        end
        M.saved_title=M.menu.WBP_MainMenu_bg.Text_Title:GetText()
        local text=StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        M.menu.WBP_MainMenu_bg:SetText(text:Conv_StringToText("Bases"))
        -- SelfHitTestInvisible: the full-screen host must not swallow native tab clicks.
        M.widget:SetVisibility(4)
        local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        own_menu_input(pc)
        local focus=U.read(function() return M.tab.WBP_PalCommonButton end)
        library:SetInputMode_UIOnlyEx(pc,U.valid(focus) and focus or M.menu,0,true)
        pc.bShowMouseCursor=true
    end)
    if ok then M.select_tab(true) end
    if not ok then M.hide(M.native_mode);U.log("Overview could not open: "..tostring(err)) end
    return ok
end
function M.hide(menu_open)
    if U.valid(M.widget) then pcall(function() M.widget:SetVisibility(1) end) end
    if M.visible then
        if U.valid(M.hidden_content) and U.address(M.hidden_content)==U.address(U.read(function() return M.menu.CurrentContentWidget end)) then
            pcall(function() M.hidden_content:SetVisibility(M.content_visibility or 0) end)
        end
        if M.saved_title and U.visible(M.menu) then
            pcall(function()
                -- Use the current native selection; it may have changed on the same click.
                M.menu:SetupBgText(M.menu.CurrentTabType)
            end)
        end
        M.hidden_content,M.saved_title=nil,nil
        -- Input ownership outlives the content panel. watch_input releases it
        -- only after the menu and any replacement overlays have closed.
    end
    M.visible=false
    M.select_tab(false)
end
function M.action()
    if not M.visible then return nil end
    local offsets={}
    for i=#M.nodes,1,-1 do
        local n=M.nodes[i]
        if n.action then
            local inside=true
            if n.parent then
                local area=M.pool[n.parent]
                if offsets[n.parent]==nil then offsets[n.parent]=U.number(U.read(function() return area.widget:GetScrollOffset() end)) or 0 end
                local top=n.y-area.y-offsets[n.parent]
                inside=top+n.h>0 and top<area.h
            end
            -- ScrollBox:IsHovered() is false when Slate routes hover to a child.
            -- Use the child's native hit test, plus viewport clipping, instead.
            if inside and U.read(function() return M.pool[n.id].widget:IsHovered() end)==true then return n.action end
        end
    end
end
function M.attach_menu(menu)
    if not U.live(menu) then return false end
    if M.menu==menu and U.valid(M.tab) and U.valid(U.read(function() return M.tab:GetParent() end)) then return true end
    if U.valid(M.tab) then pcall(function() M.tab:RemoveFromParent() end) end
    local ok,err=pcall(function()
        local native=menu.WBP_MainMenu
        local tabs=native.HorizontalBox_Tab
        assert(U.valid(tabs),"native tab row unavailable")
        local template=native.WBP_Tab_00
        assert(U.valid(template),"native tab template unavailable")
        M.native_font=template.Text_Main.Font
        local cls=template:GetClass()
        local path=cls:GetFullName():match("^[^ ]+ (.+)$")
        assert(path,"native tab class path unavailable")
        if not tab_click_hooks[path] then
            RegisterHook(path..":"..TAB_CLICK_EVENT,function(context)
                local tab=U.unwrap(context)
                if not U.valid(tab) or not U.valid(M.tab) then return end
                if U.address(tab)~=U.address(M.tab) then
                    local current_tabs=U.read(function() return M.menu.WBP_MainMenu.HorizontalBox_Tab end)
                    if M.visible and U.address(U.read(function() return tab:GetParent() end))==U.address(current_tabs) then
                        ExecuteInGameThread(function() M.hide(true) end)
                    end
                    return
                end
                ExecuteInGameThread(function()
                    if U.address(tab)==U.address(M.tab) and U.visible(M.menu) and M.on_tab_click then M.on_tab_click() end
                end)
            end)
            tab_click_hooks[path]=true
        end
        -- Create initializes the game's Blueprint tree, material brushes, font,
        -- button sounds and animations. A plain Border cannot reproduce these.
        local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local pc=U.controller()
        M.tab=library:Create(pc,cls,pc)
        assert(U.valid(M.tab) and U.valid(M.tab.Text_Main),"native tab creation failed")
        local text=StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        M.tab.Text_Main:SetText(text:Conv_StringToText("Bases"))
        M.tab:SetToolTipText(text:Conv_StringToText("Base overview  [F8]"))
        M.tab:SetEnableAttentionDot(false)
        if U.valid(M.tab.WBP_PalCommonNewMark_0) then M.tab.WBP_PalCommonNewMark_0:SetVisibility(1) end
        local slot=tabs:AddChildToHorizontalBox(M.tab)
        local original=template.Slot
        slot:SetPadding(original.Padding)
        slot:SetSize(original.Size)
        slot:SetHorizontalAlignment(original.HorizontalAlignment)
        slot:SetVerticalAlignment(original.VerticalAlignment)
        M.menu=menu
        M.tab_selected=M.visible
        M.tab:AnmEvent_FirstOpen(M.visible)
    end)
    if not ok then
        if U.valid(M.tab) then pcall(function() M.tab:RemoveFromParent() end) end
        M.tab=nil
        U.log("Bases menu entry unavailable: "..tostring(err))
    end
    return ok
end
function M.select_tab(selected)
    if not U.valid(M.tab) or M.tab_selected==selected then return end
    M.tab_selected=selected
    pcall(function()
        if selected then
            local native=M.menu.WBP_MainMenu
            M.previous_index=native.NowFocusChildIndex
            M.previous_tab=native.HorizontalBox_Tab:GetChildAt(M.previous_index)
            M.tab_index=native.HorizontalBox_Tab:GetChildIndex(M.tab)
            -- Update the selector without dispatching a built-in tab enum for
            -- Bases. Next/Previous now start at the actual highlighted tab.
            if M.tab_index>=0 then native.NowFocusChildIndex=M.tab_index end
            if U.valid(M.previous_tab) and U.address(M.previous_tab)~=U.address(M.tab) then
                M.previous_tab:AnmEvent_FocusToNormal()
            end
            M.tab:AnmEvent_NormalToFocus()
            -- The moving rectangle is the HUD focus cursor, separate from the
            -- tab's blue selection animation. Move actual focus as well.
            local pc=U.controller()
            local button=M.tab.WBP_PalCommonButton
            if U.valid(button) then button:SetUserFocus(pc) end
            local service=hud_service(pc)
            if U.valid(service) then service:ActivateFocusCursor(M.tab) end
        else
            M.tab:AnmEvent_FocusToNormal()
            -- The native menu may have changed its selected tab while closing.
            local native=M.menu.WBP_MainMenu
            if native.NowFocusChildIndex==M.tab_index and M.previous_index~=nil then
                native.NowFocusChildIndex=M.previous_index
            end
            local current=native.HorizontalBox_Tab:GetChildAt(native.NowFocusChildIndex)
            if U.valid(current) and U.address(current)~=U.address(M.tab) then current:AnmEvent_NormalToFocus() end
            M.previous_tab,M.previous_index,M.tab_index=nil,nil,nil
        end
    end)
end
-- Native CommonUI dispatch handles tab clicks, independently of global mouse binds.
function M.tab_hovered() return false end
function M.reset()
    M.cancel_open()
    M.hide(false)
    -- Any pending restoration still refers to the original menu/controller;
    -- its watcher checks world identity before touching input.
    if U.valid(M.widget) then pcall(function() M.widget:RemoveFromParent() end) end
    if U.valid(M.tab) then pcall(function() M.tab:RemoveFromParent() end) end
    M.widget,M.tab,M.menu,M.tab_selected,M.previous_tab=nil,nil,nil,nil,nil
    M.previous_index,M.tab_index=nil,nil
    M.native_font,M.viewport_key,M.native_mode=nil,nil,nil
    M.rendered_first,M.render_error=nil,nil
    text_warnings={}
    M.pool,M.nodes={},{}
end
return M
