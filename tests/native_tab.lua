-- Contract checks for lifecycle and click routing around the game's tab Blueprint.
-- These do not substitute for checking its rendering in Palworld.
local checks=0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b)) end
local sequence=0
local function object(fields)
    sequence=sequence+1
    local v=fields or {};v.address=sequence
    function v:IsValid() return true end
    function v:GetAddress() return self.address end
    function v:GetFullName() return self.name or "Widget instance" end
    function v:IsVisible() return self.visible~=false and self.visibility~=1 end
    function v:SetVisibility(value) self.visibility=value end
    function v:GetVisibility() return self.visibility or 0 end
    function v:GetParent() return self.parent end
    function v:RemoveFromParent() self.parent=nil end
    return v
end
local pc=object({bShowMouseCursor=false})
FName=function(s) return s end
UEHelpers={GetPlayerController=function() return pc end}
local cls=object({name="WidgetBlueprintGeneratedClass /Game/NativeTab.NativeTab_C"})
local template=object({Text_Main={Font={}},Slot={Padding={},Size={},HorizontalAlignment=2,VerticalAlignment=2}})
function template:GetClass() return cls end
function template:AnmEvent_FocusToNormal() self.selected=false end
function template:AnmEvent_NormalToFocus() self.selected=true end
local added,created,callback,calls,fail=0,0,nil,0,false
local pending={}
local delayed={}
function ExecuteWithDelay() error("Native timers should not cross the async thread") end
function ExecuteInGameThreadWithDelay(ms,fn) assert(ms==1 or ms==100 or ms==250);delayed[#delayed+1]=fn;return #delayed end
local function flush_delayed()
    local queue=delayed;delayed={};for _,fn in ipairs(queue) do fn() end
    queue=pending;pending={};for _,fn in ipairs(queue) do fn() end
end
function ExecuteInGameThread(fn) pending[#pending+1]=fn end
function RegisterHook(path,fn) eq(path,"/Game/NativeTab.NativeTab_C:BndEvt__WBP_MainMenu_Tab_WBP_PalCommonButton_K2Node_ComponentBoundEvent_1_CommonButtonBaseClicked__DelegateSignature");calls=calls+1;callback=fn end
local library={}
local input_changes=0
local ui_only_calls,ui_focus=0,nil
function library:SetInputMode_UIOnlyEx(context,focus,lock,flush)
    eq(context,pc);eq(flush,true);ui_focus=focus;ui_only_calls=ui_only_calls+1
end
function library:SetInputMode_GameAndUIEx() input_changes=input_changes+1 end
function library:SetInputMode_GameOnly(context,flush) eq(context,pc);eq(flush,true);input_changes=input_changes+1 end
function library:Create(context,class,owner)
    eq(context,pc);eq(class,cls);eq(owner,pc)
    created=created+1
    if fail then return nil end
    local tab=object({Text_Main=object({font="native"}),WBP_PalCommonButton=object()})
    function tab.WBP_PalCommonButton:SetUserFocus(context) eq(context,pc);ui_focus=self end
    function tab.Text_Main:SetText(s) self.text=s end
    function tab:SetToolTipText(s) self.tooltip=s end
    function tab:SetEnableAttentionDot(v) self.dot=v end
    function tab:AnmEvent_FirstOpen(v) self.selected=v end
    function tab:AnmEvent_NormalToFocus() self.selected=true end
    function tab:AnmEvent_FocusToNormal() self.selected=false end
    return tab
end
local reject_text
local text={Conv_StringToText=function(_,s)
    assert(s~="","Empty FText must not cross the loader bridge")
    assert(utf8.len(s)~=nil,"bad conversion")
    if s==reject_text then error("bad conversion") end
    return s
end}
local viewport=object({GetViewportSize=function() return {X=1920,Y=1080} end,GetViewportScale=function() return 1 end})
local hud_service,menu_class,menu_loaded
local blocked=false
hud_service=object()
function hud_service:IsAnyOverlayUIActive() return blocked end
function hud_service:ActivateFocusCursor(widget) self.focus_cursor=widget end
function StaticFindObject(path)
    if path=="/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
    if path=="/Script/Engine.Default__KismetTextLibrary" then return text end
    if path=="/Script/UMG.Default__WidgetLayoutLibrary" then return viewport end
    if path=="/Script/Pal.Default__PalUtility" then return {GetHUDService=function() return hud_service end} end
    if path=="/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu_C" then return menu_loaded and menu_class or nil end
    if path:match("^/Script/UMG%.[^_]+$") then return object() end
    error("Unexpected class: "..path)
end
local tabs=object()
local added_tab
function tabs:AddChildToHorizontalBox(tab)
    added_tab=tab
    tab.parent=self;added=added+1
    local slot={}
    for _,field in ipairs({"Padding","Size","HorizontalAlignment","VerticalAlignment"}) do
        slot["Set"..field]=function(_,value) eq(value,template.Slot[field]) end
    end
    return slot
end
function tabs:GetChildAt(index) return index==1 and added_tab or template end
function tabs:GetChildIndex(tab) return tab==added_tab and 1 or 0 end
local menu=object({WBP_MainMenu={HorizontalBox_Tab=tabs,WBP_Tab_00=template,NowFocusChildIndex=0}})
local esc_binding,esc_binds
esc_binds=0
function menu:OverrideCancelActionByType()
    error("Unsafe delegate argument crossed the loader bridge")
end
function menu:ResetCancelAction()
    esc_binding={Object=self,FunctionName="Close"};esc_binds=esc_binds+1
end
local ui=require("overview_ui")
local clicks=0;ui.on_tab_click=function() clicks=clicks+1 end
eq(ui.attach_menu(menu),true)
eq(ui.tab.Text_Main.text,"Bases");eq(ui.tab.Text_Main.font,"native")
eq(ui.tab.tooltip,"Base overview  [F8]");eq(ui.tab.dot,false)
eq(ui.attach_menu(menu),true);eq(created,1);eq(added,1);eq(calls,1)
callback(template);eq(#pending,0)
callback(nil);eq(#pending,0)
callback(ui.tab);eq(#pending,1);pending[1]();pending={};eq(clicks,1)
callback(ui.tab);menu.visible=false;pending[1]();pending={};eq(clicks,1)
menu.visible=true
ui.select_tab(true);eq(ui.tab.selected,true);eq(template.selected,false)
eq(ui_focus,ui.tab.WBP_PalCommonButton);eq(hud_service.focus_cursor,ui.tab)
eq(menu.WBP_MainMenu.NowFocusChildIndex,1)
ui.select_tab(false);eq(ui.tab.selected,false);eq(template.selected,true);eq(menu.WBP_MainMenu.NowFocusChildIndex,0)
ui.select_tab(true);menu.WBP_MainMenu.NowFocusChildIndex=3
ui.select_tab(false);eq(menu.WBP_MainMenu.NowFocusChildIndex,3) -- Preserve a new native selection.
menu.WBP_MainMenu.NowFocusChildIndex=0
callback(ui.tab)
ui.reset();pending[1]();pending={};eq(clicks,1)
fail=true;eq(ui.attach_menu(menu),false);eq(ui.tab,nil);eq(calls,1)
fail=false;eq(ui.attach_menu(menu),true);eq(calls,1)
eq(ui.tab_hovered(),false) -- Do not also toggle via the global mouse keybind.

-- A fullscreen host must let the game's tab bar receive mouse input. UI-only
-- input must remain in place when switching from Bases to another native tab.
local panel=object({visibility=4})
menu.CurrentContentWidget=panel
menu.CurrentTabType="Party"
menu.WBP_MainMenu_bg={Text_Title={GetText=function() return "Party" end},SetText=function(self,v) self.title=v end}
function menu:SetupBgText(value) self.WBP_MainMenu_bg.title=value end
ui.widget=object()
function ui.widget:IsInViewport() return true end
eq(ui.show(),true);eq(ui.widget.visibility,4);eq(input_changes,0);eq(ui_only_calls,1);eq(ui_focus,ui.tab.WBP_PalCommonButton)
eq(panel.visibility,1);eq(menu.WBP_MainMenu_bg.title,"Bases")
ui.hide(true);eq(panel.visibility,4);eq(input_changes,0);eq(menu.WBP_MainMenu_bg.title,"Party")

-- Clicking the same native tab still closes Bases, and replacing content
-- during a switch must never resurrect the old panel.
template.parent=tabs
eq(ui.show(),true)
callback(template);eq(#pending,1);pending[1]();pending={}
eq(ui.visible,false);eq(panel.visibility,4);eq(input_changes,0)
eq(ui.show(),true)
local new_panel=object()
menu.CurrentContentWidget=new_panel;menu.CurrentTabType="Guild"
callback(template);eq(#pending,1);pending[1]();pending={}
eq(ui.visible,false);eq(panel.visibility,1);eq(new_panel:GetVisibility(),0)
eq(menu.WBP_MainMenu_bg.title,"Guild");eq(input_changes,0)

-- Sampling an unchanged scene should perform no Slate property mutations.
local mutations=0
local function setter() mutations=mutations+1 end
local function slot() return {SetPosition=setter,SetSize=setter,SetAutoSize=setter,SetZOrder=setter,SetAnchors=setter,SetAlignment=setter} end
function StaticConstructObject()
    local w=object({Font={}})
    for _,name in ipairs({"SetFont","SetColorAndOpacity","SetBrushColor","SetVisibility",
        "SetHorizontalAlignment","SetVerticalAlignment","SetPadding","SetJustification","SetClipping","SetTextOverflowPolicy",
        "SetOrientation","SetConsumeMouseWheel","SetAllowOverscroll","SetAnimateWheelScrolling","SetWheelScrollMultiplier",
        "SetScrollbarThickness","SetScrollbarPadding","SetHeightOverride","SetWidthOverride","SetStretch","SetOwningPlayer"}) do w[name]=setter end
    function w:AddToViewport() self.in_viewport=true end
    function w:IsInViewport() return self.in_viewport==true end
    function w:ScrollToStart() self.offset=0;self.resets=(self.resets or 0)+1;setter() end
    function w:AddChild(child) self.content=child;setter() end
    function w:AddChildToCanvas() return slot() end
    function w:SetText(value) self.text=value;setter() end
    function w:SetContent(child) self.content=child;setter() end
    function w:SetToolTipText(value) self.tooltip=value;setter() end
    return w
end
FName=function(s) return s end
ui.canvas={AddChildToCanvas=function() return slot() end};ui.frame=slot()
local nodes={{id="background",kind="rect",x=0,y=0,w=1200,h=720,color="#001122"},
    {id="heading",kind="text",x=10,y=10,w=200,h=32,color="#FFFFFF",text="Bases",size=20}}
eq(ui.render(nodes),true)
local before=mutations
eq(ui.render(nodes),true);eq(mutations,before)
nodes[2].text="Base activity";eq(ui.render(nodes),true);eq(mutations>before,true)
nodes[2].text="";eq(ui.render(nodes),true)
eq(ui.render({nodes[1]}),true);before=mutations
eq(ui.render({nodes[1]}),true);eq(mutations,before)

-- Reproduce a label rejected by native conversion. Later metrics and controls
-- must still be present, and an unchanged fallback must not be retried forever.
reject_text="Rejected label"
local label_nodes={
    {id="badbase",kind="button",x=20,y=20,w=184,h=55,color="#001122",ink="#FFFFFF",text=reject_text,size=14,tooltip=reject_text},
    {id="goodmetric",kind="text",x=256,y=120,w=220,h=32,color="#FFFFFF",text="14 Pals",size=20},
    {id="invalidbytes",kind="text",x=256,y=160,w=220,h=32,color="#FFFFFF",text="A"..string.char(255).."B",size=20}}
eq(ui.render(label_nodes),true)
eq(ui.pool.badbase.label.text,"Text unavailable")
eq(ui.pool.badbase.widget.tooltip,"Text unavailable")
eq(ui.pool.goodmetric.widget.text,"14 Pals");eq(ui.pool.invalidbytes.widget.text,"A?B")
before=mutations;eq(ui.render(label_nodes),true);eq(mutations,before)
reject_text=nil

-- Actual scene layout with long multibyte base/Pal/product labels in every view.
local long_name=string.rep("A",18).."ö拠点🔥rest"
local fixture={at=180,camps={{id="base",label=long_name,roster_complete=true,working=1,alerts=0,
    output=0,output_complete=false,food_complete=false,food_stock=0,food_boxes=0,history={},
    pals={{id="pal",name=long_name,skills={[5]=4},allowed={[5]=true}}},
    producers={{recipe_id="Salad",product=long_name,remaining=2,status="Producing"}}}}}
for _,view in ipairs({"Overview","Trends","Pals","Production","Priorities"}) do
    local all=require("overview_scene").build(fixture,{view=view=="Trends" and "Overview" or view,overview_mode=view=="Trends" and "Trends" or "Status"},{bases={}})
    eq(ui.render(all),true)
    eq(ui.pool.metricvalue1.widget.text,"1")
    eq(ui.pool.base1.label.text,string.rep("A",18).."ö..")
end
print(string.format("PASS Native tab lifecycle, styling, menu input and unchanged scene rendering; %d assertions",checks))

-- Long rosters/station lists have all rows in a clipped native scroll area.
-- Data refreshes preserve the user's offset; switching base resets it.
local scroll_fixture={at=180,camps={{id="scrollbase",label="Scroll base",roster_complete=true,working=20,alerts=0,
    output=0,output_complete=false,food_complete=false,food_stock=0,food_boxes=0,history={},pals={},producers={}}}}
for i=1,30 do
    scroll_fixture.camps[1].pals[i]={id="p"..i,name="Pal "..i,skills={[5]=2},allowed={[5]=true},food=.8,sanity=.9,sick=0}
    scroll_fixture.camps[1].producers[i]={key="s"..i,station_name="Station "..i,recipe_id="Salad",product="Salad",remaining=3,status="Producing"}
end
for _,view in ipairs({"Pals","Production","Priorities"}) do
    local all=require("overview_scene").build(scroll_fixture,{view=view},{bases={}})
    local area
    for _,n in ipairs(all) do
        if n.kind=="scroll" then area=n end
        eq(n.id=="previous" or n.id=="next",false)
    end
    eq(area.content_height>area.h,true);eq(ui.render(all),true)
    local scroll=ui.pool[area.id].widget
    scroll.offset=175
    local resets=scroll.resets
    before=mutations;eq(ui.render(all),true);eq(mutations,before);eq(scroll.offset,175);eq(scroll.resets,resets)
    area.key="different_base";eq(ui.render(all),true);eq(scroll.offset,0);eq(scroll.resets,resets+1)
end
eq(ui.pool.prioritypal30~=nil,true);eq(ui.pool.prodstation30~=nil,true);eq(ui.pool.palname30~=nil,true)
-- A clipped descendant cannot activate just because a stale hover was reported.
local visible_before=ui.visible;ui.visible=true
ui.pool.priority_list.widget.IsHovered=function() return false end
ui.pool.priority_list.widget.GetScrollOffset=function(self) return self.offset end
ui.pool.cell30_5.widget.IsHovered=function() return true end
eq(ui.action(),nil)
ui.pool.priority_list.widget.offset=29*42
eq(ui.action().pal.id,"p30");ui.visible=visible_before

-- F8 must push the real menu and wait for activation; standalone overlays
-- and GameAndUI mode would leak pointer input into the weapon controls.
local pushes,closes,ready,loads=0,0,0,0
local returned_menu
menu_class=object()
function hud_service:Push(class,parameter)
    eq(class,menu_class);eq(parameter,nil);pushes=pushes+1;return {A=1,B=2,C=3,D=4}
end
function hud_service:GetWidget(id) eq(id.A,1);return returned_menu end
function hud_service:Close(id) eq(id.D,4);closes=closes+1 end
function LoadAsset(path)
    eq(path,"/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu")
    loads=loads+1;menu_loaded=true
end
ui.hide(true);menu.visible=false
flush_delayed();eq(input_changes,1);eq(ui.owns_menu_input(),false);eq(pc.bShowMouseCursor,false)
eq(ui.show(),false);eq(ui.visible,false) -- Never show over gameplay.
local function on_ready() ready=ready+1;eq(ui.show(),true) end
eq(ui.open_native_menu(on_ready),true);eq(pushes,1);eq(loads,1);eq(ui.visible,false)
eq(ui.open_native_menu(on_ready),false);eq(pushes,1) -- No duplicate pushes.
flush_delayed();eq(ready,0);eq(ui.visible,false)
returned_menu=menu;menu.visible=true;menu.IsActivated=function() return false end
flush_delayed();eq(ready,0)
menu.IsActivated=function() return true end
flush_delayed();eq(ready,1);eq(ui.visible,true);eq(ui_focus,ui.tab.WBP_PalCommonButton);eq(ui.opening,nil)
ui.hide(true);eq(input_changes,1) -- A tab change must retain UI-only input.
menu.visible=false;returned_menu=nil
eq(ui.open_native_menu(on_ready),true);eq(pushes,2)
ui.cancel_open();flush_delayed();eq(ready,1);eq(closes,1);eq(ui.visible,false)
blocked=true;eq(ui.open_native_menu(on_ready),false);eq(pushes,2)
blocked=false
eq(ui.open_native_menu(on_ready),true)
for _=1,20 do flush_delayed() end
eq(ui.opening,nil);eq(ui.visible,false);eq(ready,1);eq(closes,2)
print(string.format("PASS F8 native menu activation, UI-only input, cancellation and modal guard; %d total assertions",checks))

-- Reproduce the reported failures with a cached menu that never Destructs:
-- closing must remove the native stack entry, and input ownership must survive
-- a prior switch away from Bases. A close animation/modal must still block play.
local activated=true
menu.IsActivated=function() return activated end
function menu:GetId() return {A=1,B=2,C=3,D=4} end
local top=true
function hud_service:IsTopLayerUI() return top end
local native_closes=0
function menu:Close() native_closes=native_closes+1;activated=false end
local function reopen()
    menu.visible=true;activated=true;blocked=true;top=true
    menu.CurrentContentWidget=new_panel;new_panel:SetVisibility(4)
    eq(ui.show(),true);eq(ui.owns_menu_input(),true);eq(pc.bShowMouseCursor,true)
end
reopen()
local restore_count=input_changes
eq(ui.show(),true) -- Re-selecting Bases must not overwrite saved panel visibility.
eq(ui.close_menu(),true);eq(native_closes,1);eq(ui.visible,false);eq(new_panel:GetVisibility(),4)
flush_delayed();eq(input_changes,restore_count);eq(ui.owns_menu_input(),true)
-- Animation finishes while the widget remains cached and visible.
blocked=false;flush_delayed()
eq(input_changes,restore_count+1);eq(ui.owns_menu_input(),false);eq(pc.bShowMouseCursor,false)
flush_delayed();eq(input_changes,restore_count+1);eq(#delayed,0)

reopen();restore_count=input_changes
callback(template);pending[1]();pending={};eq(ui.visible,false)
eq(ui.owns_menu_input(),true);flush_delayed();eq(input_changes,restore_count)
-- Native X / Escape closes Party: no overview-close or Destruct callback.
menu.visible=false;activated=false
flush_delayed();eq(input_changes,restore_count) -- Another overlay still owns input.
blocked=false;flush_delayed();eq(input_changes,restore_count+1);eq(pc.bShowMouseCursor,false)

reopen();restore_count=input_changes
top=false;eq(ui.close_menu(),false);eq(ui.visible,true);eq(native_closes,1)
top=true
local real_close=menu.Close
menu.Close=function() error("close failed") end
eq(ui.close_menu(),false);eq(ui.visible,true);eq(new_panel:GetVisibility(),1)
menu.Close=real_close
eq(ui.close_menu(),true);eq(native_closes,2)
-- Reopen before the queued close check: never return to gameplay underneath it.
reopen();flush_delayed();eq(input_changes,restore_count);eq(ui.visible,true)
eq(ui.close_menu(),true);blocked=false;flush_delayed();eq(input_changes,restore_count+1)

-- A transient reflected-call failure retries, rather than abandoning input.
reopen();restore_count=input_changes;eq(ui.close_menu(),true);blocked=false
local game_only=library.SetInputMode_GameOnly
library.SetInputMode_GameOnly=function() error("temporary native call failure") end
flush_delayed();eq(ui.owns_menu_input(),true);eq(input_changes,restore_count)
library.SetInputMode_GameOnly=game_only
flush_delayed();eq(ui.owns_menu_input(),false);eq(input_changes,restore_count+1)

-- Exercise the real dashboard coordinator: F8 and Close exit the whole menu;
-- selecting Bases twice is idempotent, whereas a native tab only hides content.
local world_resets=0
package.loaded.base_data={init=function() end,reset_world=function() world_resets=world_resets+1 end,sample=function(_,_,_,now) return {at=now,camps={}} end}
package.loaded.priorities={store={bases={}},init=function() end,has_work=function() return false end}
local stats=require("base_stats")
stats.configure({})
menu.visible=true;activated=true;blocked=true
local old_closes=native_closes
stats.toggle({},{});eq(stats.is_open(),true)
ui.on_tab_click();eq(stats.is_open(),true);eq(native_closes,old_closes)
stats.toggle();eq(stats.is_open(),false);eq(native_closes,old_closes+1)
blocked=false;flush_delayed();eq(ui.owns_menu_input(),false)
menu.visible=true;activated=true;blocked=true
stats.open();stats.close();eq(stats.is_open(),false);eq(activated,true)
stats.toggle();eq(native_closes,old_closes+2);eq(activated,false) -- F8 after Party.
blocked=false;flush_delayed()
menu.visible=true;activated=true;blocked=true
stats.open()
local original_action=ui.action
ui.action=function() return {kind="close"} end
eq(stats.handle_click(),true);eq(native_closes,old_closes+3)
ui.action=original_action;blocked=false;flush_delayed()

-- Reproduce F8 -> Escape in a consuming native input router. It must close
-- exactly once, without falling through to the gameplay Escape/Options action.
local other_menu_opens=0
local function press_escape()
    if top==false then return end -- A modal above the main menu consumes Back.
    local consumed=false
    if activated and menu.visible and esc_binding then
        local action=esc_binding -- Native dispatch owns this event even after Close.
        consumed=true
        action.Object[action.FunctionName](action.Object)
    end
    if not consumed then other_menu_opens=other_menu_opens+1 end
end
menu.visible=false;activated=false;blocked=false;returned_menu=menu
stats.toggle();eq(ui.opening~=nil,true)
menu.visible=true;activated=true;blocked=true;flush_delayed()
eq(stats.is_open(),true)
local binds_before=esc_binds
ui.on_tab_click();eq(esc_binds,binds_before) -- No duplicate binding on re-selection.
local closes_before=native_closes
press_escape();eq(native_closes,closes_before+1);eq(other_menu_opens,0)
blocked=false;flush_delayed()
eq(stats.is_open(),false);eq(ui.owns_menu_input(),false);eq(pc.bShowMouseCursor,false)
press_escape();eq(other_menu_opens,1) -- Escape still works normally back in gameplay.

-- The native action is scoped to the menu, including after leaving Bases.
reopen();stats.close();eq(activated,true)
top=false;press_escape();eq(activated,true);eq(other_menu_opens,1)
top=true;press_escape();eq(activated,false);eq(other_menu_opens,1)
blocked=false;flush_delayed();eq(ui.owns_menu_input(),false)

-- World replacement must discard the old controller token without resetting
-- input on either an obsolete controller or the newly joined world's menu.
reopen();restore_count=input_changes
local old_pc=pc
old_pc.IsValid=function() return false end
pc=object()
flush_delayed();eq(ui.owns_menu_input(),false);eq(input_changes,restore_count);eq(#delayed,0)
menu.visible=false;activated=false;blocked=false;returned_menu=menu
stats.toggle();eq(world_resets,1);eq(ui.opening~=nil,true)
menu.visible=true;activated=true;blocked=true;flush_delayed()
eq(stats.is_open(),true);eq(world_resets,1);eq(ui.pool.empty_title.widget:IsValid(),true)
-- Model a large roster: each native operation costs a frame budget and refuses
-- any Lua state other than the one registered by the game. No transient empty
-- scene should publish, even if the player respawns in the middle of sampling.
local old_time,old_clock,old_render=os.time,os.clock,ui.render
local now,elapsed,steps,published=old_time()+10,0,0,0
os.time=function() return now end;os.clock=function() return elapsed end
local dataset=package.loaded.base_data
dataset.generation=1
dataset.prepare_sample=function()
    return function()
        local _,main=coroutine.running();assert(main,"unregistered Lua state")
        elapsed=elapsed+0.005;steps=steps+1
        if steps%4==0 then return {at=now,camps={}} end
    end
end
ui.render=function() published=published+1;return true end
stats.tick({},{},true);eq(steps,1);eq(published,0)
flush_delayed();flush_delayed();eq(steps,3);eq(published,0)
flush_delayed();eq(steps,4);eq(published,1)
now=now+6;stats.tick({},{},true);eq(steps,5)
dataset.generation=2;flush_delayed();eq(steps,5);eq(published,1)
os.time,os.clock,ui.render=old_time,old_clock,old_render
print(string.format("PASS Menu exit, tab-switch ownership, focus cursor, close races and world replacement; %d total assertions",checks))
