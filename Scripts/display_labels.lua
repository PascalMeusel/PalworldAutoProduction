local U=require("ap_util")
local M={}
-- English building labels from Pocketpair's technology ID reference:
-- https://docs.palworldgame.com/settings-and-operation/technologyids/
-- Resolve actual map-object IDs through the running game's build table.
local buildings={
    Workbench="Primitive Workbench",RepairBench="Repair Bench",Crusher="Crusher",IceCrusher="Cryogenic Crusher",FlourMill="Mill",
    Product_Cooking_Grade_01="Campfire",Product_Cooking_Grade_02="Cooking Pot",Product_Cooking_Grade_03="Electric Kitchen",
    Product_Factory_Hard_Grade_01="High-Quality Workbench",Product_Factory_Hard_Grade_02="Production Assembly Line",
    Product_Factory_Hard_Grade_03="Production Assembly Line II",Factory_Hard_04="Advanced Workshop",
    Product_Ingot_Grade_01_Copper="Primitive Furnace",Product_Ingot_Grade_02_Iron="Improved Furnace",
    Product_Ingot_Grade_03_Steal="Electric Furnace",BlastFurnace4="Gigantic Furnace",AncientBlastFurnace="Ancient Furnace",
    Product_Medicine_Grade_01="Medieval Medicine Workbench",Product_Medicine_Grade_02="Electric Medicine Workbench",
    MedicineFacility_03="Advanced Medicine Workbench",Product_WeaponFactory_Dirty_Grade_01="Weapon Workbench",
    Product_WeaponFactory_Dirty_Grade_02="Weapon Assembly Line",Product_WeaponFactory_Dirty_Grade_03="Weapon Assembly Line II",
    WeaponFactory_Dirty_04="Advanced Weapon Assembly Line",Product_WorkBench_SkillUnlock="Pal Gear Workbench",
    Special_SphereFactory_Black_Grade_01="Sphere Workbench",Special_SphereFactory_Black_Grade_02="Sphere Assembly Line",
    Special_SphereFactory_Black_Grade_03="Sphere Assembly Line II",SphereFactory_Black_04="Advanced Sphere Assembly Line",
    HugeKitchen="Large-Scale Stone Oven",AncientCookingStove="Ancient Kitchen",AncientWorkBench="Ancient Workbench",
    AncientMultiProduct="Ancient Material Synthesizer",AncientRelicRecycler="Ancient Relic Recycler",Factory_Money="Gold Coin Assembly Line",
}
local map_names,build_names,attempted,build_access={},{},false,nil
local decorators={}
function M.reset() map_names={};build_names={};attempted=false;build_access=nil;decorators={} end
function M.localized(kind,id,context)
    if id=="" or id=="None" then return nil end
    -- Palworld's own rich-text tags convert FText to FString inside Blueprint.
    -- Lua never sees a game-owned FText (including empty translation results).
    local obj=decorators[kind]
    if obj==false then return nil end
    if not U.valid(obj) then
        local name="BP_PalRichTextDecorator_"..kind
        local package="/Game/Pal/Blueprint/UI/PalTextBlock/"..name
        local asset=package.."."..name
        obj=U.read(function() return StaticFindObject(package..".Default__"..name.."_C") end)
        if not U.valid(obj) then
            local cls=U.read(function() return StaticFindObject(asset.."_C") end)
            if not U.valid(cls) and type(LoadAsset)=="function" then
                pcall(function() LoadAsset(asset) end)
                cls=U.read(function() return StaticFindObject(asset.."_C") end)
            end
            obj=U.read(function() return cls:GetCDO() end)
        end
        decorators[kind]=U.valid(obj) and obj or false
    end
    if not U.valid(obj) then return nil end
    local label=U.name(U.read(function() return obj:GetTextStringInternal(context,FName(id)) end))
    if label~="" and label~="None" then return label end
end
function M.base(value,index)
    local label=U.clean_text(value):match("^%s*(.-)%s*$")
    -- Only the game's template placeholder is discarded. Custom Japanese
    -- names (and all other languages) are legitimate player names.
    if label=="" or label=="None" or label:match("^新規生成拠点テンプレート名%d+%(仮%)$") then return "Base "..index end
    return label
end
function M.humanize(id)
    return U.clean_text(id):gsub("_"," "):gsub("(%l)(%u)","%1 %2"):gsub("(%a)(%d)","%1 %2")
end
function M.station(object)
    local id=U.name(U.read(function() return object:TryGetMapObjectId() end))
    if map_names[id] then return map_names[id] end
    local translated=M.localized("MapObject",id,object)
    if translated then map_names[id]=translated;return translated end
    if not attempted then
        attempted=true
        local pc=U.controller()
        local technology=U.read(function() return pc:GetPalPlayerState():GetTechnologyData() end)
        if U.valid(technology) then
            for id,label in pairs(buildings) do
                local row=U.read(function() return technology:GetRecipeTechlonogy(FName(id)) end)
                U.each(U.read(function() return row.UnlockBuildObjects end),function(build)
                    build_names[U.name(build)]=label
                end)
            end
        end
        local util=U.read(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        build_access=U.read(function() return util:GetBuildObjectDataTableAccess(pc) end)
        if not U.valid(build_access) then
            local rows=U.read(function() return util:GetBuildObjectDataTable(pc):GetRowMap() end)
            if type(rows)=="table" then
                for key,row in pairs(rows) do
                    local build=U.name(key)
                    local label=build_names[build] or buildings[build]
                    if label then map_names[U.name(U.read(function() return row.MapObjectId end))]=label end
                end
            end
        end
    end
    local build=U.name(U.read(function() return object:GetActor().BuildObjectId end))
    local label=map_names[id] or build_names[build] or build_names[id] or buildings[build] or buildings[id]
    if not label and U.valid(build_access) and id~="" and id~="None" then
        local row_name,ok={},{}
        U.read(function() return build_access:BP_FindRowByMapObjectId(FName(id),row_name,ok) end)
        local row=U.name(row_name.OutRowName)
        label=build_names[row] or buildings[row]
    end
    if not label then
        label=M.humanize(build~="" and build~="None" and build or id)
        if label=="" or label=="None" then label="Workstation" end
    end
    if id~="" and id~="None" then map_names[id]=label end
    return label
end
function M.position(object)
    local vector=U.read(function() return object:GetTransform().Translation end)
    if not vector then return nil end
    local x=U.number(U.read(function() return vector.X end))
    local y=U.number(U.read(function() return vector.Y end))
    local z=U.number(U.read(function() return vector.Z end))
    if x and y and z then return {x=x,y=y,z=z} end
end
function M.location(position,origin)
    if not position or not origin then return "Location unavailable" end
    local dx,dy,dz=position.x-origin.x,position.y-origin.y,position.z-origin.z
    local label=string.format("%.0f m from Palbox",math.sqrt(dx*dx+dy*dy)/100)
    if math.abs(dz)>=250 then label=label..string.format(" / %.0f m %s",math.abs(dz)/100,dz>0 and "above" or "below") end
    return label
end
return M
