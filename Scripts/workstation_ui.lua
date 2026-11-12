-- Native layout owns the toggle's size and hit region. No cached FGeometry.
local U=require("ap_util")
local M={}
local hooks={}
local function make(class,tree)
    local v=StaticConstructObject(StaticFindObject("/Script/UMG."..class),tree)
    assert(U.valid(v),class.." unavailable")
    return v
end
local function margin(v) return {Left=v.Left,Top=v.Top,Right=v.Right,Bottom=v.Bottom} end
local function point(v) return {X=v.X,Y=v.Y} end
local function slot_layout(slot)
    local kind=U.name(slot:GetClass():GetFName())
    if kind=="CanvasPanelSlot" then
        local d=slot.LayoutData
        return {kind=kind,anchors={Minimum=point(d.Anchors.Minimum),Maximum=point(d.Anchors.Maximum)},
            offsets=margin(d.Offsets),alignment=point(d.Alignment),auto=slot.bAutoSize,z=slot.ZOrder}
    end
    assert(kind=="OverlaySlot" or kind=="HorizontalBoxSlot" or kind=="VerticalBoxSlot"
        or kind=="SizeBoxSlot" or kind=="ScaleBoxSlot" or kind=="BorderSlot","unsupported transport slot "..kind)
    local d={kind=kind,padding=U.read(function() return margin(slot.Padding) end) or {Left=0,Top=0,Right=0,Bottom=0},
        horizontal=slot.HorizontalAlignment,vertical=slot.VerticalAlignment}
    if kind=="HorizontalBoxSlot" or kind=="VerticalBoxSlot" then d.size={SizeRule=slot.Size.SizeRule,Value=slot.Size.Value} end
    return d
end
local function apply_slot(slot,d)
    if d.kind=="CanvasPanelSlot" then
        slot:SetAnchors(d.anchors);slot:SetOffsets(d.offsets);slot:SetAlignment(d.alignment)
        slot:SetAutoSize(d.auto);slot:SetZOrder(d.z)
    else
        slot:SetPadding(d.padding);slot:SetHorizontalAlignment(d.horizontal);slot:SetVerticalAlignment(d.vertical)
        if d.size then slot:SetSize(d.size) end
    end
end
-- AddChild only appends. Preserve following siblings' slots and order too.
local function replace(parent,old,new)
    local index=parent:GetChildIndex(old)
    assert(index>=0,"transport container is detached")
    local following={}
    for i=index,parent:GetChildrenCount()-1 do
        local child=parent:GetChildAt(i)
        assert(U.valid(child),"transport sibling is no longer live")
        following[#following+1]={child=child,layout=slot_layout(child.Slot)}
    end
    for _,entry in ipairs(following) do parent:RemoveChild(entry.child) end
    local ok,err=pcall(function()
        apply_slot(parent:AddChild(new),following[1].layout)
        for i=2,#following do local entry=following[i];apply_slot(parent:AddChild(entry.child),entry.layout) end
    end)
    if not ok then
        parent:RemoveChild(new)
        for _,entry in ipairs(following) do parent:RemoveChild(entry.child) end
        for _,entry in ipairs(following) do apply_slot(parent:AddChild(entry.child),entry.layout) end
        error(err)
    end
end
local function contains(parent,child)
    for _=1,32 do
        if not U.valid(child) then return false end
        if U.address(parent)==U.address(child) then return true end
        child=child:GetParent()
    end
    return false
end
local function click_function(cls)
    for _=1,20 do
        if not U.valid(cls) then break end
        local path
        cls:ForEachFunction(function(fn)
            if U.name(fn:GetFName())=="BP_OnClicked" then path=fn:GetFullName():match("^[^ ]+ (.+)$");return true end
        end)
        if path then return path end
        cls=cls:GetSuperStruct()
    end
end
function M.reset()
    if U.valid(M.owner) and U.valid(M.wrapper) and U.valid(M.original) and U.valid(M.parent)
        and U.address(U.read(function() return M.wrapper:GetParent() end))==U.address(M.parent)
        and U.address(U.read(function() return M.original:GetParent() end))==U.address(M.wrapper) then
        local ok,err=pcall(function()
            M.original:RemoveFromParent()
            replace(M.parent,M.wrapper,M.original)
        end)
        if not ok then U.log("Could not restore transport layout: "..tostring(err)) end
    end
    M.root,M.wrapper,M.original,M.button,M.owner,M.on_click=nil,nil,nil,nil,nil,nil
    M.parent,M.label,M.check=nil,nil,nil
end
function M.attach(owner,on_click)
    M.reset()
    local ok,err=pcall(function()
        local row=owner.HorizontalBox_TransportCheckBox
        local template=owner.WBP_PalInvisibleButton_TransportCheck
        assert(U.valid(row) and U.valid(template),"native transport controls unavailable")
        -- Wrap their common container: the transport button must not cover
        -- Auto Produce's hit area. Both controls remain native siblings.
        local original=row
        for _=1,32 do
            if not U.valid(original) or contains(original,template) then break end
            original=original:GetParent()
        end
        assert(U.valid(original) and contains(original,template),"transport container unavailable")
        assert(not contains(original,owner.WBP_IngameMenu_StartButton),"transport container includes Start Production")
        local parent=original:GetParent()
        assert(U.valid(parent),"transport parent unavailable")
        local cls=template:GetClass()
        local path=assert(click_function(cls),"native CommonUI click event unavailable")
        if not hooks[path] then
            RegisterHook(path,function(context)
                local button=U.unwrap(context)
                if not U.valid(M.button) or U.address(button)~=U.address(M.button) then return end
                ExecuteInGameThread(function()
                    if U.valid(M.button) and U.address(button)==U.address(M.button)
                        and U.visible(M.root) and U.visible(M.owner)
                        and M.button:GetIsEnabled()==true and M.on_click then M.on_click() end
                end)
            end)
            hooks[path]=true
        end
        local tree=owner.WidgetTree
        local wrapper=make("HorizontalBox",tree);wrapper:SetVisibility(4)
        local root=make("Overlay",tree);root:SetVisibility(4)
        local visual=make("HorizontalBox",tree);visual:SetVisibility(3)
        local label=make("TextBlock",tree)
        label:SetFont(owner.BP_PalTextBlock_C_77.Font)
        label:SetColorAndOpacity({SpecifiedColor={R=0.9,G=0.96,B=1,A=1},ColorUseRule=0})
        label:SetVisibility(3)
        local label_slot=visual:AddChildToHorizontalBox(label);label_slot:SetVerticalAlignment(2)
        local check=make("CheckBox",tree);check.WidgetStyle=owner.CheckBox.WidgetStyle;check:SetVisibility(3)
        local check_slot=visual:AddChildToHorizontalBox(check)
        check_slot:SetVerticalAlignment(2);check_slot:SetPadding({Left=10,Top=0,Right=0,Bottom=0})
        root:AddChildToOverlay(visual)
        local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local pc=U.controller()
        local button=library:Create(pc,cls,pc)
        assert(U.valid(button),"native checkbox input construction failed")
        button:SetVisibility(0)
        button:SetToolTipText(StaticFindObject("/Script/Engine.Default__KismetTextLibrary"):
            Conv_StringToText("Repeat the selected recipe while ingredients are available. Turn off to stop refilling."))
        local input_slot=root:AddChildToOverlay(button)
        input_slot:SetHorizontalAlignment(0);input_slot:SetVerticalAlignment(0)
        -- All slot types are validated before changing the native hierarchy.
        replace(parent,original,wrapper)
        M.owner,M.parent,M.original,M.wrapper=owner,parent,original,wrapper
        M.root,M.label,M.check,M.button,M.on_click=root,label,check,button,on_click
        local transport_slot=wrapper:AddChildToHorizontalBox(original)
        transport_slot:SetSize({SizeRule=1,Value=1});transport_slot:SetVerticalAlignment(0)
        local auto_slot=wrapper:AddChildToHorizontalBox(root)
        auto_slot:SetSize({SizeRule=0,Value=1});auto_slot:SetVerticalAlignment(2)
        auto_slot:SetPadding({Left=20,Top=0,Right=0,Bottom=0})
        U.log("AutoProduce joined native transport layout ("..U.name(parent:GetFName())..").")
    end)
    if not ok then M.reset();return nil,tostring(err) end
    return M.root,M.label
end
function M.refresh(enabled,has_recipe,recipe,save_warning,status)
    if not U.visible(M.owner) or not U.valid(M.root) or not U.valid(M.label)
        or not U.valid(M.check) or not U.valid(M.button) then return end
    local text=StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    M.label:SetText(text:Conv_StringToText(enabled and "Auto Produce: ON" or "Auto Produce: OFF"))
    M.label:SetColorAndOpacity({SpecifiedColor=enabled
        and {R=0.18,G=0.9,B=0.32,A=1}
        or {R=0.9,G=0.96,B=1,A=1},ColorUseRule=0})
    M.check:SetIsChecked(enabled)
    M.button:SetIsEnabled(enabled or has_recipe)
    M.root:SetRenderOpacity((enabled or has_recipe) and 1 or 0.55)
    M.button:SetToolTipText(text:Conv_StringToText(save_warning or (enabled
        and ("Repeating "..tostring(recipe or "the saved recipe")..". "..tostring(status or "Starting")
            ..". Refills batches automatically; ten is not a total limit. Pause before changing recipe. Saved across world restarts.")
        or "Repeat the selected recipe while ingredients are available. Your choice is saved across world restarts.")))
end
return M
