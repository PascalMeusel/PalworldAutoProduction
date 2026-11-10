local U = require("ap_util")
local M = {camps = {}, objects = {}, seeded = false, watching = false, error = nil, generation=0}
local telemetry = require("telemetry").new()
local forecast = require("forecast")
local labels = require("display_labels")
local food_values, master = {}, nil
local names = {pals={},items={}}
local pal_metadata, object_kinds = {}, {}
local station_metadata,selected_recipes={},{}
local last_opened_station
local last_food_check
local sickness={[1]="Cold",[2]="Sprain",[3]="Overeating",[4]="Ulcer",[5]="Fracture",[6]="Weakness",[7]="Depressed",[8]="Unwell"}
local food_class="PalMapObjectPalFoodBoxModel"
local seed_classes={}
local seed_generation,verified=0,false
local function sources()
    return {{"PalBaseCampModel",M.camps},{"PalMapObjectConvertItemModel",M.objects},
        {"PalMapObjectProductItemModel",M.objects},{"PalMapObjectPalFoodBoxModel",M.objects}}
end
local function display_name(id, kind, context)
    if names[kind][id] then return names[kind][id] end
    if kind=="items" then
        local label=labels.localized("ItemName",id,context) or labels.humanize(id)
        names.items[id]=label;return label
    end
    local out={}
    local ok=pcall(function()
        StaticFindObject("/Script/Pal.Default__PalUIUtility"):GetDisplayNickName(context,FName(id),FName("None"),out)
    end)
    local name=ok and U.name(out.OutNickName or out.OutText or out.outName or out.OutName) or ""
    local label=name~="" and name or labels.humanize(id)
    names[kind][id]=label
    return label
end
local function cache(cache, object)
    if not U.live(object) then return end
    local address=U.address(object)
    if cache==M.objects then
        local class=U.name(U.read(function() return object:GetClass():GetFName() end)):lower()
        local kind=(class:find("productitem",1,true) or class:find("convertitem",1,true)) and "producer"
            or class:find("foodbox",1,true) and "food"
        if not kind then return end
        object_kinds[address]=kind
    end
    cache[address]=object
end
local function discover(entry)
    if seed_classes[entry[1]] then return end
    for _,object in ipairs(U.read(function() return FindAllOf(entry[1]) end) or {}) do cache(entry[2],object) end
    seed_classes[entry[1]]=true
end
local function warm_discovery()
    -- Bootstrap pre-existing instances in separate frames (normally on the
    -- title screen). Watchers then collect models as the save streams in.
    -- A generation guard prevents an old world's timer from marking a new one ready.
    local generation,entries,n=seed_generation,sources(),1
    local function step()
        if generation~=seed_generation or M.seeded then return end
        discover(entries[n]);n=n+1
        if n<=#entries then U.defer(180,step) else M.seeded=true end
    end
    if M.watching and not M.error then pcall(U.defer,350,step) end
end
function M.init()
    if M.watching then return end
    M.watching = true
    for _, entry in ipairs(sources()) do
        local ok = pcall(function() NotifyOnNewObject("/Script/Pal." .. entry[1], function(obj) cache(entry[2], obj) end) end)
        if not ok then M.error = "Object watcher unavailable; reopen the overview to refresh discovery." end
    end
    warm_discovery()
end
function M.seed(only_food)
    if M.seeded or (only_food and seed_classes[food_class]) then return end
    -- AFK eating does not need a world-wide search for bases and workstations.
    -- Share the one-time food-box discovery with the overview in either order.
    for _, entry in ipairs(sources()) do
        if not seed_classes[entry[1]] and (not only_food or entry[1]==food_class) then
            discover(entry)
        end
    end
    if not only_food then M.seeded=true end
end
function M.rediscover()
    seed_generation=seed_generation+1;seed_classes={};M.seeded=false;verified=false
end
function M.reset_world()
    M.generation=M.generation+1
    for k in pairs(M.camps) do M.camps[k] = nil end
    for k in pairs(M.objects) do M.objects[k] = nil end
    M.rediscover()
    telemetry = require("telemetry").new()
    food_values, master = {}, nil
    names={pals={},items={}}
    pal_metadata,object_kinds={},{}
    station_metadata,selected_recipes={},{}
    last_opened_station=nil
    last_food_check=nil
    labels.reset()
    warm_discovery()
end
local function group_id(pc)
    -- AController.GetPawn is C++ only. Pawn is the reflected property.
    local pawn = U.read(function() return pc.Pawn end)
    if not U.valid(pawn) then pawn=U.read(function() return pc:K2_GetPawn() end) end
    if not U.valid(pawn) then return nil,"Waiting for your player character." end
    local component = U.read(function() return pawn:GetCharacterParameterComponent() end)
    if not U.valid(component) then return nil,"Cannot read the player character's base connection." end
    local param = U.read(function() return component:GetIndividualParameter() end)
    if not U.valid(param) then return nil,"Cannot read your guild membership." end
    local id=U.guid(U.read(function() return param:GetGroupId() end))
    if id then return id end
    return nil,"The game has not provided your guild ID."
end
M.player_group=group_id
local function read_pal(slot,now,need_skills,need_fixed)
    local handle = U.read(function() return slot.Handle end)
    local param = U.valid(handle) and U.read(function() return handle:TryGetIndividualParameter() end) or nil
    if not U.valid(param) then param = U.read(function() return slot.ReplicateIndividualParameter end) end
    if not U.valid(param) then return nil end
    local raw_id = U.valid(handle) and U.read(function() return handle:GetIndividualID() end) or nil
    local id = U.guid(U.read(function() return raw_id.InstanceId end))
    local name = U.name(U.read(function() return param.SaveParameter.NickName end))
    if name == "" or name == "None" then
        name = display_name(U.name(U.read(function() return param:GetCharacterID() end)),"pals",param)
    end
    local pal = {id = id, name = name ~= "" and name or "Unnamed Pal", param = param, handle = handle,
        raw_id = raw_id, skills = {}, allowed = {}, permissions_read = false, fixed = nil}
    pal.work = U.number(U.read(function() return param:GetCurrentWorkSuitability() end))
    pal.sanity = U.number(U.read(function() return param:GetSanityRate() end))
    pal.food = U.number(U.read(function() return param:GetFullStomachRate() end))
    pal.dead = U.read(function() return param:IsDead() end)
    pal.sick = U.number(U.read(function() return param:GetWorkerSick() end))
    local hunger=U.number(U.read(function() return param:GetHungerType() end))
    if hunger==0 or hunger==1 or hunger==2 then pal.hungry=hunger~=0;pal.starving=hunger==2 end
    if pal.hungry==nil and pal.food~=nil then pal.hungry=pal.food<0.25 end
    if pal.work==0 then pal.sleeping=U.read(function() return param:IsSleeping() end) end
    -- Divide like-for-like fixed-point values; both include the game's scale.
    local hp=U.number(U.read(function() return param:GetHP().Value end))
    local max_hp=U.number(U.read(function() return param:GetMaxHP_withBuff().Value end))
    if hp and hp>=0 and max_hp and max_hp>0 then pal.health=U.clamp(hp/max_hp,0,1) end
    pal.low_hp=pal.dead==false and pal.health~=nil and pal.health<0.35
    local meta=id and pal_metadata[id]
    if need_skills~=false and (not meta or now-meta.at>=60) then
        meta={at=now,skills={}}
        for work = 1, 13 do
            local rank = U.number(U.read(function() return param:GetWorkSuitabilityRankWithCharacterRank(work) end))
            if rank == nil then rank = U.number(U.read(function() return param:GetWorkSuitabilityRank(work) end)) end
            if rank and rank > 0 then meta.skills[work]=rank end
        end
        if id then pal_metadata[id]=meta end
    end
    pal.skills=meta and meta.skills or {}
    if need_skills~=false then
        for work in pairs(pal.skills) do pal.allowed[work]=true end
        local disabled = U.read(function() return param.SaveParameter.WorkSuitabilityOptionInfo.OffWorkSuitabilityList end)
        pal.permissions_read = U.each(disabled, function(w)
            local n=U.number(w);if n then pal.allowed[n] = false end
        end)
    end
    local actor = (need_fixed~=false or need_skills~=false) and U.valid(handle) and U.read(function() return handle:TryGetIndividualActor() end) or nil
    if U.valid(actor) then
        local component = U.read(function() return actor:GetCharacterParameterComponent() end)
        if U.valid(component) then
            local ok, assign = pcall(function() return component:GetWorkAssign() end)
            if ok then
                pal.fixed = false
                if U.valid(assign) then pal.fixed = U.read(function() return assign:IsFixed() end) end
            end
        end
    end
    pal.working = pal.work ~= nil and pal.work > 0 and pal.work <= 13
    pal.alert = pal.dead and "Incapacitated" or (pal.starving and "Starving") or (pal.low_hp and "Low health")
        or sickness[pal.sick] or (pal.hungry and "Hungry")
        or (pal.sanity and pal.sanity < 0.4 and "Low sanity") or nil
    return pal
end
local function roster_slots(camp)
    local director=U.read(function() return camp.WorkerDirector end)
    local container=U.valid(director) and U.read(function() return director.CharacterContainer end)
    local slots=U.valid(container) and U.read(function() return container.SlotArray end)
    local refs={}
    local ok=U.each(slots,function(slot) refs[#refs+1]=slot end)
    return refs,ok
end
local function append_slot(camp,slot,now,need_skills,need_fixed)
    if U.valid(slot) then
        local empty=U.read(function() return slot:IsEmpty() end)
        if empty==true then return end
        if empty==false then
            local pal=read_pal(slot,now,need_skills,need_fixed)
            if pal then
                camp.pals[#camp.pals+1]=pal
                if pal.working then camp.working=camp.working+1 end
                if pal.alert then camp.alerts=camp.alerts+1 end
                return
            end
        end
    end
    camp.roster_complete=false
end
local function sort_pals(pals)
    table.sort(pals,function(a,b) return a.name==b.name and (a.id or "")<(b.id or "") or a.name<b.name end)
end
function M.roster(camp,now,need_skills,step,need_fixed)
    local slots,ok=roster_slots(camp)
    local c={pals={},working=0,alerts=0,roster_complete=ok}
    for _,slot in ipairs(slots) do
        if step then step() end
        append_slot(c,slot,now or os.time(),need_skills,need_fixed)
    end
    sort_pals(c.pals)
    return c.pals,c.roster_complete
end
local function food_in(object, item_manager)
    local module = U.read(function() return object:GetItemContainerModule() end)
    if not U.valid(module) then return nil end
    local container = U.read(function() return module:GetContainer() end)
    if not U.valid(container) then return nil end
    local slots = U.read(function() return container.ItemSlotArray end)
    local total, complete, items = 0, true, {}
    local ok = U.each(slots, function(slot)
        if not U.valid(slot) then complete = false; return end
        local count = U.number(U.read(function() return slot:GetStackCount() end))
        if not count then complete = false; return end
        if count <= 0 then return end
        local item = U.name(U.read(function() return slot.ItemId.StaticId end))
        if item == "" or item == "None" then complete = false; return end
        if food_values[item] == nil then
            local static = U.valid(item_manager) and U.read(function() return item_manager:GetStaticItemData(FName(item)) end)
            if U.valid(static) then
                local item_type = U.number(U.read(function() return static.TypeA end))
                if item_type == 8 then
                    food_values[item] = U.number(U.read(function() return static:GetRestoreSatiety() end))
                elseif item_type ~= nil then food_values[item] = 0 end
            end
        end
        local value=food_values[item]
        if value==nil then complete=false
        elseif value>0 then
            total=total+count*value
            items[item]=(items[item] or 0)+count
        end
    end)
    return ok and complete and total or nil, U.address(container), items
end
local function entries(objects)
    local copy={}
    for key,obj in pairs(objects) do copy[#copy+1]={key,obj} end
    return copy
end
-- Each invocation of advance runs one unit on UE4SS's registered game-thread
-- Lua state. Coroutines cannot safely invoke this loader's reflected APIs.
function M.prepare_sample(products,yields,automation,now,need_skills,need_fixed)
    local tasks={}
    local function schedule(fn) tasks[#tasks+1]=fn end
    local pc = U.controller()
    local my_group,connection_error
    if pc then my_group,connection_error=group_id(pc) else connection_error="Waiting for the local player." end
    local result = {at = now, camps = {}, warning = connection_error or M.error, owned = my_group ~= nil}
    if not my_group then return function() return result end end
    local cold=not verified
    local begin=os.clock()
    if not verified and M.seeded then
        -- A loader can miss constructors during seamless travel. If its cache
        -- missed even the known current camp, recover using the proven typed searches.
        local inside=U.read(function() return pc.Pawn.InsideBaseCampCheckComponent:GetInsideBaseCampModel() end)
        local address=U.address(inside)
        if not next(M.camps) or (address and (not M.camps[address] or not next(M.objects))) then M.rediscover() end
    end
    M.seed()
    verified=true
    local seeded_at=os.clock()
    local here=U.guid(U.read(function() return pc.Pawn.InsideBaseCampCheckComponent:GetInsideBaseCampModel():GetId() end))
    local by_id = {}
    for _,entry in ipairs(entries(M.camps)) do
        local address,object=entry[1],entry[2]
        if not U.live(object) then M.camps[address] = nil
        else
            local id = U.guid(U.read(function() return object:GetId() end))
            local group = U.guid(U.read(function() return object:GetGroupIdBelongTo() end))
            if id and my_group and group == my_group and not by_id[id] then
                local slots,complete=roster_slots(object)
                local label = U.name(U.read(function() return object:GetBaseCampName() end))
                local camp = {id = id, object = object, pals = {}, roster_complete = complete,
                    label = label, position=labels.position(object), producers = {}, working = 0, alerts = 0, food_stock = 0, food_boxes = 0,
                    here=id==here,food_complete = true, food_seen = {},food_counts={},food_items={},output = 0, output_complete = true}
                for _,slot in ipairs(slots) do
                    schedule(function() append_slot(camp,slot,now,need_skills,need_fixed) end)
                end
                result.camps[#result.camps+1], by_id[id] = camp, camp
            end
        end
    end
    table.sort(result.camps, function(a,b) return a.id < b.id end)
    for i, c in ipairs(result.camps) do c.label=labels.base(c.label,i) end
    local roster_at
    schedule(function() roster_at=os.clock() end)
    if not U.valid(master) then
        local utility = U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
        if U.valid(utility) then master = U.read(function() return utility:GetItemIDManager(pc) end) end
    end
    for _,entry in ipairs(entries(M.objects)) do
        schedule(function()
            local address,object=entry[1],entry[2]
            if not U.live(object) then M.objects[address] = nil;station_metadata[address]=nil;selected_recipes[address]=nil
            else
                local id = U.guid(U.read(function() return object:GetBaseCampIdBelongTo() end))
                local camp = by_id[id]
                if camp then
                    if object_kinds[address]=="producer" then
                        local recipe = U.name(U.read(function() return object:GetCurrentRecipeId() end))
                        local remaining = U.number(U.read(function() return object:GetRemainCreateNum() end))
                        if remaining ~= nil then
                            local auto = automation and automation(address) or nil
                            if recipe=="None" then recipe="" end
                            if remaining==0 then recipe=(auto and auto.recipe_id) or selected_recipes[address] or recipe end
                            local meta=station_metadata[address]
                            if not meta then
                                meta={name=labels.station(object),id=U.guid(U.read(function() return object:GetInstanceId() end)) or address}
                                station_metadata[address]=meta
                            end
                            local yield = yields[recipe] or 1
                            local rate, warmup
                            if recipe ~= "" then rate, warmup = telemetry:observe(address, recipe, remaining, yield, now) end
                            local row = {key = address, station = object, station_id=meta.id, station_type=meta.name, base_id=id,
                                location=labels.location(labels.position(object),camp.position),recipe_id = recipe,
                                last_opened=address==last_opened_station,
                                product = display_name(products[recipe] or recipe,"items",object),
                                remaining = remaining, rate = rate, warmup = warmup or 0, yield_count = yield, auto = auto ~= nil,
                                status = auto and auto.status or (remaining<0 and "Game-managed queue" or remaining>0 and "Producing" or "Idle")}
                            if row.product == "" then row.product = remaining>0 and "Recipe unavailable" or "No recipe selected" end
                            camp.producers[#camp.producers+1] = row
                            if rate then camp.output = camp.output + rate elseif recipe ~= "" or remaining>0 then camp.output_complete = false end
                        end
                    elseif object_kinds[address]=="food" then
                        camp.food_boxes = camp.food_boxes + 1
                        local amount, container,items = food_in(object, master)
                        if amount==nil then camp.food_complete=false end
                        if container and not camp.food_seen[container] then
                            camp.food_seen[container]=true
                            camp.food_stock=camp.food_stock+(amount or 0)
                            for item,count in pairs(items or {}) do camp.food_counts[item]=(camp.food_counts[item] or 0)+count end
                        end
                    end
                end
            end
        end)
    end
    local function finish()
        for _, camp in ipairs(result.camps) do
            sort_pals(camp.pals)
            table.sort(camp.producers, function(a,b)
                return a.station_type==b.station_type and a.station_id<b.station_id or a.station_type<b.station_type
            end)
            local counts,numbers={},{}
            for _,row in ipairs(camp.producers) do counts[row.station_type]=(counts[row.station_type] or 0)+1 end
            for _,row in ipairs(camp.producers) do
                numbers[row.station_type]=(numbers[row.station_type] or 0)+1
                row.station_name=row.station_type..(counts[row.station_type]>1 and " #"..numbers[row.station_type] or "")
            end
            -- No discovered box is unknown, not an assertion that a remote base has no food.
            if camp.food_boxes == 0 then camp.food_complete = false end
            for item,count in pairs(camp.food_counts) do
                camp.food_items[#camp.food_items+1]={id=item,name=display_name(item,"items",camp.object),
                    count=count,each=food_values[item],nutrition=count*food_values[item]}
            end
            table.sort(camp.food_items,function(a,b) return a.nutrition==b.nutrition and a.id<b.id or a.nutrition>b.nutrition end)
            local sources_seen={}
            for key in pairs(camp.food_seen) do sources_seen[#sources_seen+1]=key end
            table.sort(sources_seen)
            telemetry:push(camp.id, {at = now, working = camp.roster_complete and camp.working or nil,
                output = camp.output_complete and camp.output or nil,
                food = camp.food_complete and camp.food_stock or nil,food_source=table.concat(sources_seen,";")})
            camp.history = telemetry.histories[camp.id]
            camp.forecast = forecast.food(camp.history, now, camp.food_stock, camp.food_complete)
        end
        telemetry:prune(now)
        if cold then U.log(string.format("First base sample: discovery %.1f ms, rosters %.1f ms, stations and supplies %.1f ms.",
            (seeded_at-begin)*1000,(roster_at-seeded_at)*1000,(os.clock()-roster_at)*1000)) end
        return result
    end
    local i=0
    return function()
        i=i+1
        if tasks[i] then tasks[i]();return nil end
        return finish()
    end
end
function M.sample(products,yields,automation,now,need_skills,step,need_fixed)
    local advance=M.prepare_sample(products,yields,automation,now,need_skills,need_fixed)
    repeat
        if step then step() end
        local result=advance()
        if result then return result end
    until false
end
function M.observe_station(key, recipe, remaining, yield, now) return telemetry:observe(key, recipe, remaining, yield, now) end
function M.refilled(key, recipe, remaining, now) telemetry:baseline(key, recipe, remaining, now) end
function M.item_label(id,context) return display_name(id,"items",context) end
function M.can_edit_station(row)
    local pc=U.controller()
    if not pc or not U.live(row.station) then return false,"Station is no longer loaded." end
    local camp=U.read(function() return pc.Pawn.InsideBaseCampCheckComponent:GetInsideBaseCampModel() end)
    local guild=group_id(pc)
    if not guild or not U.live(camp) or U.guid(U.read(function() return camp:GetGroupIdBelongTo() end))~=guild
        or U.guid(U.read(function() return camp:GetId() end))~=row.base_id
        or U.guid(U.read(function() return row.station:GetBaseCampIdBelongTo() end))~=row.base_id
        or (U.guid(U.read(function() return row.station:GetInstanceId() end)) or U.address(row.station))~=row.station_id then
        return false,"Visit this station's base to change production."
    end
    return true
end
function M.select_recipe(row,recipe)
    selected_recipes[row.key]=recipe.id
    row.recipe_id,row.product,row.yield_count=recipe.id,recipe.label,recipe.yield_count
    row.rate,row.warmup=nil,0
end
function M.remember_recipe(station,recipe)
    local key=U.address(station)
    if key then last_opened_station=key end
    if key and recipe and recipe~="" and recipe~="None" then selected_recipes[key]=recipe end
end
function M.feed_boxes(base_id)
    M.seed(true)
    local boxes={}
    for address,object in pairs(M.objects) do
        if not U.live(object) then M.objects[address]=nil;object_kinds[address]=nil
        elseif object_kinds[address]=="food" and U.guid(U.read(function() return object:GetBaseCampIdBelongTo() end))==base_id then
            boxes[#boxes+1]=object
        end
    end
    table.sort(boxes,function(a,b) return U.address(a)<U.address(b) end)
    return boxes
end
-- Keep only the current base's food history warm when the full dashboard sleeps.
-- Missing production/roster measurements remain gaps in their own charts.
function M.food_sample(base_id,now)
    local previous=telemetry.histories[base_id]
    if previous and previous[#previous] and now-previous[#previous].at<5 then return end
    local pc=U.controller()
    if not pc then return end
    if not U.valid(master) then master=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetItemIDManager(pc) end) end
    local seen,keys,stock,complete={},{},0,true
    for _,box in ipairs(M.feed_boxes(base_id)) do
        local amount,container=food_in(box,master)
        if not amount or not container then complete=false
        elseif not seen[container] then seen[container]=true;keys[#keys+1]=container;stock=stock+amount end
    end
    table.sort(keys)
    telemetry:push(base_id,{at=now,food=complete and #keys>0 and stock or nil,food_source=table.concat(keys,";")})
    telemetry:prune(now)
end
function M.sample_current_food(now)
    -- This path is independent of AFK meals, player movement, hunger, carried
    -- food and menu state. Faster production polling must not multiply reads.
    if last_food_check and now>=last_food_check and now-last_food_check<5 then return end
    last_food_check=now
    local pc=U.controller()
    if not pc then return end
    local camp=U.read(function() return pc.Pawn.InsideBaseCampCheckComponent:GetInsideBaseCampModel() end)
    if not U.live(camp) then return end
    local base_id=U.guid(U.read(function() return camp:GetId() end))
    local group=group_id(pc)
    if not base_id or not group or group~=U.guid(U.read(function() return camp:GetGroupIdBelongTo() end)) then return end
    M.food_sample(base_id,now)
end
return M
