local U=require("ap_util")
local sources=require("base_data")
local M={enabled=true,status="Waiting for your character",meals=0}
local idle_seconds,threshold=60,0.5
local last_check,last_activity,identity,last_base,anchor,rotation,pending,retry_at=0,0,nil,nil,nil,nil,nil,0
local item_manager,item_values
local function value(v,key) return U.number(U.read(function() return v[key] end)) end
local function vector(v)
    local x,y,z=value(v,"X"),value(v,"Y"),value(v,"Z")
    if x and y and z then return {x=x,y=y,z=z} end
end
local function distance(a,b) return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
local function note(message,paused)
    M.status=message
    if not paused then M.field_status=message end
end
function M.activity() last_activity=os.time();M.idle_base=nil end
function M.configure(settings)
    M.enabled=settings.BASE_AUTO_EAT~=false
    idle_seconds=U.clamp(tonumber(settings.AFK_IDLE_SECONDS) or 60,15,600)
    threshold=U.clamp(tonumber(settings.AFK_HUNGER_THRESHOLD) or 0.5,0.1,0.8)
    last_activity=os.time();item_values={}
end
function M.toggle()
    M.enabled=not M.enabled;M.activity();pending=nil
    note(M.enabled and "Stand idle to enable meals" or "Automatic meals paused")
    return M.enabled
end
function M.needs_tick() return M.enabled end
function M.summary()
    return {enabled=M.enabled,status=M.status,field_status=M.field_status,meals=M.meals,fullness=M.fullness,last_meal=M.last_meal,last_meal_at=M.last_meal_at}
end
local function nutrition(slot,pc)
    local item=U.name(U.read(function() return slot.ItemId.StaticId end))
    if item=="" or item=="None" then return nil end
    if not U.valid(item_manager) then
        item_manager=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetItemIDManager(pc) end)
    end
    item_values=item_values or {}
    if item_values[item]==nil then
        local data=U.read(function() return item_manager:GetStaticItemData(FName(item)) end)
        local kind=U.number(U.read(function() return data.TypeA end))
        if kind==8 then item_values[item]=U.number(U.read(function() return data:GetRestoreSatiety() end))
        elseif kind~=nil then item_values[item]=0 end
    end
    return item_values[item],item
end
local function inventory_food(inventory,pc,meal_slot)
    local found,complete,empty=false,true,nil
    for _,kind in ipairs({0,5}) do -- Common inventory and food pouch.
        local out={}
        local ok=U.read(function() return inventory:TryGetContainerFromInventoryType(kind,out) end)
        if ok~=true or not U.valid(out.OutContainer) then
            if kind~=5 or U.read(function() return inventory:GetUnlockedFoodEquipSlotNum() end)~=0 then complete=false end
        else
            local read=U.each(U.read(function() return out.OutContainer.ItemSlotArray end),function(slot)
                local count=U.number(U.read(function() return slot:GetStackCount() end))
                if count==nil then complete=false
                elseif count==0 and kind==0 and not empty then empty=slot
                elseif count>0 and (not meal_slot or U.address(slot)~=U.address(meal_slot)) then
                    local amount=nutrition(slot,pc)
                    if amount==nil then complete=false elseif amount>0 then found=true end
                end
            end)
            if not read then complete=false end
        end
    end
    return found,complete,empty
end
local function failed(now,reason)
    pending=nil;retry_at=now+60
    U.log("AFK meal: "..reason.."; waiting 60 seconds before retrying.")
    note(reason.."; retrying later")
end
local function tick(now)
    M.idle_base=nil
    local pc=U.controller()
    local pawn=U.read(function() return pc:GetDefaultPlayerCharacter() end)
    if not U.valid(pawn) then pawn=U.read(function() return pc.Pawn end) end
    if not U.live(pawn) then last_activity=now;pending=nil;M.fullness=nil;note("Waiting for your character");return end
    local current=tostring(U.address(pc))..":"..tostring(U.address(pawn))
    if identity~=current then
        if identity then sources.reset_world() end
        identity=current;last_activity=now;anchor=nil;rotation=nil;pending=nil;last_base=nil;retry_at=0
        item_manager=nil;item_values={};M.fullness=nil;M.last_meal=nil;M.last_meal_at=nil;M.meals=0;M.field_status=nil
    end
    local param=U.read(function() return pawn:GetCharacterParameterComponent():GetIndividualParameter() end)
    local camp=U.read(function() return pawn.InsideBaseCampCheckComponent:GetInsideBaseCampModel() end)
    local base_id=U.guid(U.read(function() return camp:GetId() end))
    local group=U.guid(U.read(function() return param:GetGroupId() end))
    if not base_id or not group or group~=U.guid(U.read(function() return camp:GetGroupIdBelongTo() end)) then
        last_activity=now;last_base=nil;pending=nil;note("Only in your own base");return
    end
    if last_base~=base_id then last_base=base_id;last_activity=now;anchor=nil;rotation=nil;pending=nil end
    local rate=U.number(U.read(function() return param:GetFullStomachRate() end))
    M.fullness=rate and rate>=0 and rate<=1 and rate or nil
    if pending and pending.phase=="eating" then
        local fullness=U.number(U.read(function() return param:GetFullStomach() end))
        local count=U.valid(pending.slot) and U.number(U.read(function() return pending.slot:GetStackCount() end))
        if now-pending.at<=15 and fullness and fullness>pending.fullness and count and count<pending.count then
            M.meals=M.meals+1;M.last_meal=pending.item;M.last_meal_at=now
            U.log(string.format("AFK meal confirmed: %s from a feed box (carried stack %d -> %d, fullness %.1f -> %.1f).",pending.item,pending.count,count,pending.fullness,fullness))
            pending=nil
        elseif now-pending.at<15 then note("Waiting for meal confirmation");return
        else
            failed(now,"Meal not confirmed");return
        end
    end
    if pending and now-pending.at>15 then failed(now,"Transfer not confirmed");return end
    local pos=vector(U.read(function() return pawn:K2_GetActorLocation() end))
    local velocity=vector(U.read(function() return pawn:GetVelocity() end))
    local facing=U.read(function() return pc:GetControlRotation() end)
    local pitch,yaw=value(facing,"Pitch"),value(facing,"Yaw")
    if not pos or not velocity or not pitch or not yaw then last_activity=now;note("Waiting for movement data");return end
    local turned=rotation and (math.abs((yaw-rotation.yaw+180)%360-180)>2 or math.abs(pitch-rotation.pitch)>2)
    if not anchor or distance(pos,anchor)>100 or distance(velocity,{x=0,y=0,z=0})>25 or turned then
        last_activity=now;anchor=pos;rotation={pitch=pitch,yaw=yaw}
    end
    local hud=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetHUDService(pc) end)
    if U.read(function() return param:IsDead() end)~=false or U.read(function() return pc:IsRiding() end)~=false
        or U.read(function() return pawn.bIsBattleMode end)~=false
        or U.read(function() return hud:IsAnyOverlayUIActive() end)~=false then
        last_activity=now;note("Paused while occupied",true);return
    end
    if now-last_activity<idle_seconds then note("Stand idle for "..math.ceil(idle_seconds-(now-last_activity)).."s");return end
    M.idle_base=base_id
    if not M.fullness then note("Hunger reading unavailable");return end
    if rate>=threshold then note("Not hungry");return end
    if now<retry_at then note("Meal not confirmed; retrying later");return end
    local fullness=U.number(U.read(function() return param:GetFullStomach() end))
    if not fullness then note("Hunger reading unavailable");return end
    local inventory=U.read(function() return pc:GetPalPlayerState():GetInventoryData() end)
    if not U.valid(inventory) then note("Inventory unavailable");return end
    local carried,complete,empty=inventory_food(inventory,pc,pending and pending.slot)
    if carried then pending=nil;note("Food already in your inventory");return end
    if not complete then note("Inventory reading incomplete");return end
    local target=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetIndividualIDByActor(pawn) end)
    if not U.guid(U.read(function() return target.InstanceId end)) or not U.guid(U.read(function() return target.PlayerUId end)) then
        note("Player identity unavailable");return
    end
    if pending then
        local count=U.number(U.read(function() return pending.slot:GetStackCount() end))
        local item=U.name(U.read(function() return pending.slot.ItemId.StaticId end))
        if count~=1 or item~=pending.item then note("Waiting for food transfer");return end
        local source_count=U.number(U.read(function() return pending.source:GetStackCount() end))
        if not source_count or source_count>=pending.source_count then note("Checking feed box transfer");return end
        if U.read(function() return pending.slot:CanUseItemToCharacter(target) end)~=true then failed(now,"Transferred food unavailable");return end
        pending.phase="eating";pending.at=now;pending.fullness=fullness;pending.count=count
        U.log(string.format("AFK meal: received one %s (feed box %d -> %d); requesting use.",item,pending.source_count,source_count))
        pending.slot:RequestUseToCharacter(target,1)
        note("Eating "..item.." from a feed box");return
    end
    if not U.valid(empty) then note("Need a free inventory slot");return end
    for _,box in ipairs(sources.feed_boxes(base_id)) do
        local container=U.read(function() return box:GetItemContainerModule():GetContainer() end)
        local candidate,item,before
        U.each(U.read(function() return container.ItemSlotArray end),function(slot)
            if candidate then return end
            local count=U.number(U.read(function() return slot:GetStackCount() end))
            if count and count>0 then
                local amount,name=nutrition(slot,pc)
                if amount and amount>0 and U.read(function() return slot:CanUseItemToCharacter(target) end)==true then candidate=slot;item=name;before=count end
            end
        end)
        if candidate then
            -- A storage slot can report CanUse=true while the game's use
            -- request silently refuses it. Move exactly one item through the
            -- player's normal inventory network component, then eat only the
            -- identified item in that previously empty slot once it arrives.
            local net=U.read(function() return pc.Transmitter:GetItem() end)
            local from=U.read(function() return candidate:GetSlotId() end)
            local to=U.read(function() return empty:GetSlotId() end)
            local request=U.read(function() return StaticFindObject("/Script/Engine.Default__KismetGuidLibrary"):NewGuid() end)
            if not U.valid(net) or not U.guid(request) or not U.guid(U.read(function() return from.ContainerId.ID end))
                or not U.guid(U.read(function() return to.ContainerId.ID end)) then note("Food transfer unavailable");return end
            pending={phase="moving",at=now,item=item,slot=empty,source=candidate,source_count=before}
            net:RequestMove_ToServer(request,to,{{SlotId=from,Num=1}})
            note("Getting a meal from a feed box")
            return
        end
    end
    note("No usable food in feed boxes")
end
function M.tick(now)
    now=now or os.time()
    if not M.enabled or now-last_check<5 then return end
    last_check=now
    local ok,err=pcall(tick,now)
    if not ok then
        note("Automatic meal check unavailable")
        local message=tostring(err):match("^[^\n]+")
        if M.error~=message then U.log("AFK meal check: "..message) end
        M.error=message
    else M.error=nil end
end
return M
