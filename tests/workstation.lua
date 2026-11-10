-- Real main/UI wiring with native layout slots, permanently unavailable
-- geometry, an overlapping transport input layer, and actual refill requests.
local checks,sequence=0,0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function object(fields)
    sequence=sequence+1
    local v=fields or {};v.address=sequence;v.children={}
    function v:IsValid() return self.valid~=false end
    function v:GetAddress() return self.address end
    function v:GetFullName() return self.name or "Widget instance" end
    function v:GetFName() return self.name or self.class or "Panel" end
    function v:GetClass() local kind=self.class;return {GetFName=function() return kind end} end
    function v:IsVisible() return self.visibility~=1 and self.visibility~=2 end
    function v:GetParent() return self.parent end
    function v:RemoveFromParent() if self.parent then self.parent:RemoveChild(self) end;self.removed=true end
    function v:SetVisibility(value) self.visibility=value end
    function v:SetRenderOpacity(value) self.opacity=value end
    function v:SetIsEnabled(value) self.enabled=value end
    function v:GetIsEnabled() return self.enabled~=false end
    function v:SetToolTipText(value) self.tooltip=value end
    function v:GetCachedGeometry() error("No native geometry is available, even after the recipe window is shown") end
    function v:SetFont(value) self.Font=value end
    function v:SetColorAndOpacity() end
    function v:SetText(value) self.text=value end
    function v:SetIsChecked(value) self.checked=value end
    function v:GetChildIndex(child) for i,c in ipairs(self.children) do if c==child then return i-1 end end;return -1 end
    function v:GetChildAt(i) return self.children[i+1] end
    function v:GetChildrenCount() return #self.children end
    function v:RemoveChild(child)
        local i=self:GetChildIndex(child);if i<0 then return false end
        table.remove(self.children,i+1);child.parent=nil;return true
    end
    function v:AddChild(child)
        assert(not child.parent,"Child already parented")
        child.parent=self;self.children[#self.children+1]=child
        local kind=self.class.."Slot"
        local slot={Padding={Left=2,Top=3,Right=4,Bottom=5},HorizontalAlignment=0,VerticalAlignment=0,
            Size={SizeRule=1,Value=1},LayoutData={Anchors={Minimum={X=0,Y=0},Maximum={X=1,Y=1}},
            Offsets={Left=30,Top=300,Right=600,Bottom=32},Alignment={X=0,Y=0}},bAutoSize=false,ZOrder=10}
        function slot:GetClass() return {GetFName=function() return kind end} end
        for _,field in ipairs({"Padding","HorizontalAlignment","VerticalAlignment","Size","ZOrder"}) do
            slot["Set"..field]=function(self,value) self[field]=value end
        end
        function slot:SetAnchors(value) self.LayoutData.Anchors=value end
        function slot:SetOffsets(value) self.LayoutData.Offsets=value end
        function slot:SetAlignment(value) self.LayoutData.Alignment=value end
        function slot:SetAutoSize(value) self.bAutoSize=value end
        child.Slot=slot;return slot
    end
    v.AddChildToHorizontalBox=v.AddChild;v.AddChildToOverlay=v.AddChild
    return v
end
local pc=object()
local world="TestWorld"
local game_state=object({GetWorldSaveDirectoryName=function() return world end})
local guild={A=1,B=2,C=3,D=4}
local base_id={A=5,B=6,C=7,D=8}
local camp=object({GetId=function() return base_id end,GetGroupIdBelongTo=function() return guild end})
pc.Pawn=object({InsideBaseCampCheckComponent={GetInsideBaseCampModel=function() return camp end},
    GetCharacterParameterComponent=function() return object({GetIndividualParameter=function()
        return object({GetGroupId=function() return guild end}) end}) end})
local here,unlocked=true,true
local tech=object({IsUnlockCraftRecipe=function(_,id) return unlocked and id=="Salad" end})
function pc:GetPalPlayerState() return {GetTechnologyData=function() return tech end} end
package.preload.config=function() return {BASE_AUTO_EAT=false} end
local state_module=require("automation_state")
local new_state=state_module.new
local save_path=os.tmpname();os.remove(save_path)
local saved_state
state_module.new=function() saved_state=new_state(save_path);return saved_state end
UEHelpers={GetPlayerController=function() return pc end}
FName=function(s) return s end
Key={LEFT_MOUSE_BUTTON=1,RIGHT_MOUSE_BUTTON=2,F8=3,ESCAPE=4}
local keybinds={}
function RegisterKeyBind(key,fn) keybinds[key]=fn end
local hooks,watched,delayed,game={}, {}, {}, {}
function RegisterHook(path,fn) hooks[path]=fn end
function NotifyOnNewObject(path,fn) watched[path]=fn end
function ExecuteWithDelay() error("Native timers should not cross the async thread") end
function ExecuteInGameThreadWithDelay(ms,fn) delayed[#delayed+1]=fn;return #delayed end
function ExecuteInGameThread(fn) game[#game+1]=fn end
local function flush_game() local q=game;game={};for _,f in ipairs(q) do f() end end
local function flush_delayed() local q=delayed;delayed={};for _,f in ipairs(q) do f() end;flush_game() end
local click_path="/Game/NativeButton.NativeButton_C:BP_OnClicked"
local base_cls=object()
function base_cls:ForEachFunction(fn)
    fn({GetFName=function() return "BP_OnClicked" end,GetFullName=function() return "Function "..click_path end})
end
local button_cls=object()
function button_cls:ForEachFunction() end
function button_cls:GetSuperStruct() return base_cls end
local classes={}
for _,name in ipairs({"HorizontalBox","Overlay","TextBlock","CheckBox"}) do classes[name]=name end
local text={Conv_StringToText=function(_,s) return s end}
local library={Create=function(_,context,class,owner) eq(context,pc);eq(class,button_cls);eq(owner,pc);return object() end}
local scheduler_class=object()
local starts,blocked,before,after=0,0,0,0
local clock=100;os.time=function() return clock end
local scheduler=object({ProductSettingModel=object()})
local asynchronous=false
function scheduler:Initialize(station) self.station=station end
function scheduler.ProductSettingModel:SelectRecipe(recipe) self.recipe=recipe end
function scheduler.ProductSettingModel:SetProductNumByInput(count) self.count=count end
function scheduler:UpdateProductSetting_TransportToStorage(on) eq(on,true) end
function scheduler:CanStartProduction() return blocked end
function scheduler:StartProduction()
    starts=starts+1
    if asynchronous then return end
    self.station.remaining=self.ProductSettingModel.count
    self.station.recipe=self.ProductSettingModel.recipe
end
local model_path="/Game/Pal/Blueprint/UI/CovertItemMenu/Model/BP_PalUIConvertItemModel.BP_PalUIConvertItemModel_C"
local recipe_reads=0
local recipe_access=object({BP_FindRow=function(_,id,out)
    recipe_reads=recipe_reads+1;out.bResult=id=="Salad";return {Product_Id=id,Product_Count=1}
end})
function StaticFindObject(path)
    if path=="/Script/Pal.Default__PalUtility" then return object({GetPalGameStateInGame=function() return game_state end}) end
    if path=="/Script/Pal.Default__PalMasterDataTablesUtility" then return {GetItemRecipeDataTableAccess=function() return recipe_access end} end
    if path==model_path then return scheduler_class end
    if path=="/Script/Engine.Default__GameplayStatics" then return object({GetGameInstance=function() return pc end}) end
    if path=="/Script/Engine.Default__KismetTextLibrary" then return text end
    if path=="/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
    return assert(classes[path:match("/Script/UMG%.(.+)")],path)
end
function StaticConstructObject(class)
    if class==scheduler_class then return scheduler end
    return object({Font={},class=class})
end
local item_utility=object({CountLocalPlayerInsideBaseCampItemNum64=function(_,_,f) return f=="Lettuce" and 15 or 6 end,
    CountLocalPlayerInventoryItemNum64=function(_,_,f) return f=="Lettuce" and 1 or 0 end})
local old_find=StaticFindObject
StaticFindObject=function(path)
    if path=="/Script/Pal.Default__PalItemUtility" then return item_utility end
    return old_find(path)
end
local recipe_table=object()
function recipe_table:GetRowMap() return {Salad={Product_Id="Salad",Product_Count=1}} end
local master=object({ItemRecipeDataTable=recipe_table})
function FindFirstOf(name) if name=="PalMasterDataTables" then return master end end
function FindAllOf() return {} end
local options,observed_at
package.preload.base_stats=function()
    return {configure=function(o) options=o end,needs_tick=function() return false end,is_open=function() return false end,
        observe_automation=function(_,recipe,remaining) observed_at=clock;eq(recipe,"Salad");assert(remaining>=0) end,
        before_refill=function() before=before+1 end,after_refill=function() after=after+1 end}
end
local workspace_path="/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C"
local food_checks=0
local base_data=require("base_data")
local sample_food=base_data.sample_current_food
base_data.sample_current_food=function(now) food_checks=food_checks+1;return sample_food(now) end
require("main")
eq(keybinds[Key.ESCAPE],nil) -- Escape belongs to the native consuming menu action.
eq(type(keybinds[Key.F8]),"function")
local ui=require("workstation_ui")
local function window(parent_kind)
    local parent=object({class=parent_kind or "CanvasPanel"})
    local native=object({class="Overlay"});parent:AddChild(native)
    local row=object({class="HorizontalBox"});native:AddChild(row)
    local template=object();native:AddChild(template) -- Input drawn ABOVE the transport row.
    function template:GetClass() return button_cls end
    local start=object();parent:AddChild(start)
    local station=object({remaining=0,recipe="None"})
    station.stable=station.address
    function station:GetInstanceId() return {A=self.stable,B=0,C=0,D=0} end
    function station:GetBaseCampIdBelongTo() return base_id end
    function station:GetRecipes() return {"Salad"} end
    function station:GetRemainCreateNum() return self.remaining end
    function station:GetCurrentRecipeId() return self.recipe end
    local selected="None"
    local model=object({ProductSettingModel=object()})
    function model.ProductSettingModel:GetRecipeId() return selected end
    function model:TryGetConcreteModel(out) out.Model=station;return true end
    local owner=object({HorizontalBox_TransportCheckBox=row,WBP_PalInvisibleButton_TransportCheck=template,
        WBP_IngameMenu_StartButton=start,CheckBox={WidgetStyle={marker="native"}},
        BP_PalTextBlock_C_77=object({Font={marker="native",Size=14}}),WidgetTree=object(),["Convert Item Model"]=model})
    return owner,function(value) selected=value end,station,parent,native
end
local owner,select_recipe,station,parent,native=window()
watched[workspace_path](owner);flush_delayed()
-- No saved/active automation, no overview sampling and AFK meals disabled:
-- the main scheduler must still start and keep a background food check alive.
eq(food_checks,1);eq(saved_state:has_saved(),false);eq(#delayed>0,true)
eq(ui.owner,owner);eq(ui.label.text,"Auto Produce: OFF");eq(ui.button.enabled,false)
eq(ui.check.WidgetStyle,owner.CheckBox.WidgetStyle);eq(ui.label.Font,owner.BP_PalTextBlock_C_77.Font)
eq(ui.original,native);eq(ui.wrapper:GetChildAt(0),native);eq(ui.wrapper:GetChildAt(1),ui.root)
eq(parent:GetChildAt(0),ui.wrapper);eq(parent:GetChildAt(1),owner.WBP_IngameMenu_StartButton)
eq(ui.wrapper.Slot.LayoutData.Offsets.Top,300);eq(ui.wrapper.Slot.ZOrder,10)
eq(ui.root.visibility,4);eq(native.Slot.Size.SizeRule,1);eq(ui.root.Slot.Size.SizeRule,0)
eq(ui.button.parent,ui.root);eq(owner.WBP_PalInvisibleButton_TransportCheck.parent,native)
local function context(value) return {get=function() return value end} end
hooks[click_path](context(ui.button));flush_game();eq(ui.check.checked,false)
select_recipe("Salad");hooks[workspace_path..":Update Recipe Detail"](context(owner));flush_game()
eq(ui.button.enabled,true);eq(ui.root.opacity,1)
eq(recipe_reads,1)
hooks[click_path](context(owner.WBP_PalInvisibleButton_TransportCheck));flush_game();eq(ui.check.checked,false)
hooks[click_path](context(ui.button));flush_game();eq(ui.check.checked,true)
flush_delayed();eq(starts,1);eq(station.remaining,10);eq(before,1);eq(after,1)
clock=103;flush_delayed();eq(starts,1) -- No refill while busy.
station.remaining=0;clock=106;blocked=1;flush_delayed();eq(starts,1) -- Ingredients rejected.
clock=109;blocked=0;flush_delayed();eq(starts,1) -- A rejected station does not retry every scan.
clock=111;flush_delayed();eq(starts,2);eq(station.remaining,10)
select_recipe("None");hooks[workspace_path..":Update Recipe Detail"](context(owner));flush_game()
eq(ui.button.enabled,true)
hooks[click_path](context(ui.button));flush_game();eq(ui.check.checked,false);eq(ui.button.enabled,false)
station.remaining=0;clock=112;flush_delayed();eq(starts,2) -- Pausing stops refills.
select_recipe("Salad");hooks[workspace_path..":Update Recipe Detail"](context(owner));flush_game()
local old_button,old_wrapper=ui.button,ui.wrapper
hooks[click_path](context(old_button))
ui.reset();flush_game();eq(ui.root,nil);eq(old_wrapper.parent,nil)
eq(recipe_reads,1) -- Recipe selection, refills and repeated renders reuse one lookup.
eq(parent:GetChildAt(0),native);eq(parent:GetChildAt(1),owner.WBP_IngameMenu_StartButton)
eq(native.Slot.LayoutData.Offsets.Top,300);eq(native.Slot.ZOrder,10);eq(#parent.children,2)
for _,kind in ipairs({"Overlay","VerticalBox","HorizontalBox","SizeBox","ScaleBox","Border"}) do
    local next_owner,next_select,_,next_parent,next_native=window(kind);next_select("Salad")
    watched[workspace_path](next_owner);flush_delayed()
    eq(ui.owner,next_owner);eq(ui.check.checked,false);eq(ui.wrapper.Slot.Padding.Left,2)
    hooks[click_path](context(old_button));flush_game();eq(ui.check.checked,false)
    next_owner.visibility=1
    hooks[click_path](context(ui.button));flush_game();eq(ui.check.checked,false)
    ui.reset();eq(next_parent:GetChildAt(0),next_native);eq(next_native.Slot.Padding.Bottom,5)
end
-- The menu must never start work merely because an unlocked recipe or its supplies were inspected.
local data=require("base_data")
data.can_edit_station=function() return here,"Visit the station's base." end
function station:GetRecipes() return {"Salad","Cake","Salad"} end
local row={key=tostring(station.address),station=station,base_id="home",station_name="Kitchen",rate=2}
local choices=options.recipe_choices(row)
eq(#choices,1);eq(choices[1].id,"Salad")
here=false;eq(options.recipe_choices(row,"Salad"),nil);eq(row.recipe_id,nil)
here=true;unlocked=false;eq(options.recipe_choices(row,"Salad"),nil)
unlocked=true;eq(options.recipe_choices(row,"Salad"),true);eq(row.recipe_id,"Salad");eq(starts,2)
function scheduler.ProductSettingModel:GetRecipeId() return self.recipe end
function scheduler.ProductSettingModel:CalcMaxProductableNum() return 3 end
function scheduler.ProductSettingModel:GetRequiredMaterialInfos(out,one)
    eq(one,true);out[1]={StaticItemId="Lettuce",Num=2};out[2]={StaticItemId="Tomato",Num=2}
end
local plan=options.supply_check(row)
eq(plan.craftable,3);eq(plan.materials[1].base,15);eq(plan.materials[1].bag,1)
eq(plan.materials[1].crafts,8);eq(plan.materials[2].limiting,true);eq(plan.coverage,3)
eq(starts,2);eq(station.remaining,0)
here=false;eq(options.supply_check(row),nil);eq(options.set_automation(row),false)
here=true;unlocked=false;eq(options.set_automation(row),false)
unlocked=true;station.remaining=1;eq(options.recipe_choices(row,"Salad"),nil)
station.remaining=0;asynchronous=true;clock=200
eq(options.set_automation(row),true);flush_delayed();eq(starts,3);eq(after,2)
clock=204;flush_delayed();eq(starts,3)
station.remaining=4;station.recipe="Salad";clock=207;flush_delayed()
eq(starts,3);eq(after,3);eq(options.get_automation(row.key).status,"Producing")
station.remaining=0;clock=210;flush_delayed();eq(starts,4)
clock=221;flush_delayed();eq(options.get_automation(row.key).status,"No queue confirmation");eq(after,3)
clock=235;flush_delayed();eq(starts,4);eq(observed_at,235)
clock=236;flush_delayed();eq(starts,5)
eq(options.set_automation(row),true);clock=300;flush_delayed();eq(starts,5)
station.remaining=-1;eq(options.recipe_choices(row,"Salad"),nil);eq(starts,5)
-- A fresh main module reads the actual file and resumes a different live object
-- with the same permanent station ID, without opening Bases or enabling AFK meals.
station.remaining=0;asynchronous=false;eq(options.set_automation(row),true)
local permanent=station.stable
ui.reset();station.valid=false
delayed={};game={};data.reset_world()
local restart_owner,restart_select,restart_station=window()
restart_station.stable=permanent
data.objects[tostring(restart_station.address)]=restart_station
package.loaded.main=nil;require("main")
clock=310;flush_delayed()
eq(starts,6);eq(restart_station.remaining,10)
local restored=options.get_automation(tostring(restart_station.address))
eq(restored.recipe_id,"Salad");eq(restored.status,"Producing")
-- Opening an unselected station window does not erase its restored recipe.
watched[workspace_path](restart_owner);flush_delayed()
eq(ui.check.checked,true);eq(options.get_automation(tostring(restart_station.address)).recipe_id,"Salad")
hooks[click_path](context(ui.button));flush_game();eq(ui.check.checked,false)
restart_station.remaining=0;clock=320;flush_delayed();eq(starts,6)
local disk=new_state(save_path)
local record=next(disk.store.records);eq(disk.store.records[record].enabled,false)
eq(disk.store.records[record].recipe,"Salad")
-- A complete reload keeps OFF even if its last queue is empty.
delayed={};game={};package.loaded.main=nil;require("main")
clock=330;flush_delayed();eq(options.get_automation(tostring(restart_station.address)),nil);eq(starts,6)
for _,suffix in ipairs({"",".bak",".tmp"}) do os.remove(save_path..suffix) end
print(string.format("PASS Native workstation layout, recipe selection, supplies, delayed queue confirmation and production refills; %d assertions",checks))
