local MOD_NAME = "PalworldAutoProduction"
local DEFAULTS = {
    ENABLED = true,
    BATCH_SIZE = 10,
    SCAN_INTERVAL_MS = 2000,
}

local ok_config, user_config = pcall(require, "config")
if not ok_config or type(user_config) ~= "table" then
    user_config = DEFAULTS
end

local config = {
    enabled = user_config.ENABLED ~= false,
    batch_size = math.floor(tonumber(user_config.BATCH_SIZE) or DEFAULTS.BATCH_SIZE),
    scan_interval_ms = math.floor(tonumber(user_config.SCAN_INTERVAL_MS) or DEFAULTS.SCAN_INTERVAL_MS),
    fast_refill = user_config.FAST_REFILL ~= false,
}
config.batch_size = math.max(1, math.min(config.batch_size, 9999))
config.scan_interval_ms = math.max(1000, math.min(config.scan_interval_ms, 10000))
local base_stats = require("base_stats")
local U = require("ap_util")
local workstation_ui = require("workstation_ui")
local auto_eat = require("auto_eat")
auto_eat.configure(user_config)
if UEHelpers == nil then pcall(function() UEHelpers = require("UEHelpers") end) end

local UI_MODEL_CLASS_PATH = "/Game/Pal/Blueprint/UI/CovertItemMenu/Model/BP_PalUIConvertItemModel.BP_PalUIConvertItemModel_C"
local WORKSPACE_CLASS_PATH = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/WBP_IngameMenu_WorkSpace.WBP_IngameMenu_WorkSpace_C"
local MAIN_MENU_CLASS_PATH = "/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu_C"
local scheduler_ui_class = nil
local recipe_products = nil
local recipe_product_counts = nil
local active_workspace = nil
local active_convert_ui = nil
local active_station = nil
local auto_button = nil
local auto_button_label = nil
local auto_button_target = nil
local automation_state = require("automation_state").new()
local auto_by_station = automation_state.active
local is_scanning = false
local scan_timer_pending = false
local workspace_event_generation = 0
local main_menu_event_generation = 0
local active_main_menu = nil
local registered_lifecycle_hooks = {}
local schedule_scan
local toggle_active_station
local last_button_notice_at = 0


local function log(message)
    print("[" .. MOD_NAME .. "] " .. message .. "\n")
end

local function valid(object)
    return U.valid(object)
end

local function unwrap(value)
    return U.unwrap(value)
end

local function to_name(value)
    return U.name(value)
end

local function each(array, callback)
    if array == nil then
        return
    end
    if type(array) == "table" then
        for _, value in ipairs(array) do
            callback(value)
        end
        return
    end
    pcall(function()
        array:ForEach(function(_, value)
            callback(value:get())
        end)
    end)
end

local function load_game_data()
    if recipe_products ~= nil then
        return true
    end
    local util=U.read(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
    local function accessor()
        return U.read(function() return util:GetItemRecipeDataTableAccess(U.controller()) end)
    end
    local access=accessor()
    if valid(access) then
        -- Most bases have only a handful of active recipes. Resolve just those
        -- IDs, and share the cached answer between product names and yields.
        local misses={}
        local function lookup(id)
            if not id or id=="" or id=="None" or misses[id] then return end
            if not valid(access) then access=accessor() end
            if not valid(access) then return end
            local out={}
            local row=U.read(function() return access:BP_FindRow(FName(id),out) end)
            if out.bResult==false then misses[id]=true;return end
            local product=U.name(U.read(function() return row.Product_Id end))
            local count=U.number(U.read(function() return row.Product_Count end))
            if product~="" and product~="None" then
                rawset(recipe_products,id,product)
                rawset(recipe_product_counts,id,math.max(1,math.floor(count or 1)))
            end
        end
        local index={__index=function(t,id) lookup(id);return rawget(t,id) end}
        recipe_products,recipe_product_counts=setmetatable({},index),setmetatable({},index)
        return true
    end
    -- Older game builds without the native keyed accessor retain the table path.
    local master = FindFirstOf("PalMasterDataTables")
    if not valid(master) then
        return false
    end

    local recipe_table = nil
    local ok_tables = pcall(function()
        recipe_table = master.ItemRecipeDataTable
    end)
    if not ok_tables or not valid(recipe_table) then
        return false
    end

    local recipe_rows = nil
    local ok_rows = pcall(function()
        recipe_rows = recipe_table:GetRowMap()
    end)
    if not ok_rows or type(recipe_rows) ~= "table" then
        return false
    end

    local found_products = {}
    local found_product_counts = {}
    for row_name, row in pairs(recipe_rows) do
        local recipe_id = to_name(row_name)
        local product_id = ""
        local product_count = 1
        pcall(function()
            product_id = to_name(row.Product_Id)
        end)
        -- FPalItemRecipe.Product_Count is the number of items yielded by one
        -- completed craft. Keep a safe 1-item fallback for older game data.
        pcall(function()
            local parsed = tonumber(unwrap(row.Product_Count))
            if parsed ~= nil and parsed > 0 then
                product_count = math.max(1, math.floor(parsed))
            end
        end)
        if recipe_id ~= "" and recipe_id ~= "None" and product_id ~= "" and product_id ~= "None" then
            found_products[recipe_id] = product_id
            found_product_counts[recipe_id] = product_count
        end
    end
    if next(found_products) == nil then
        return false
    end
    recipe_products = found_products
    recipe_product_counts = found_product_counts
    return true
end

local function station_has_recipes(station)
    if not valid(station) then
        return false
    end
    local found = false
    pcall(function()
        each(station:GetRecipes(), function(recipe_value)
            local recipe_id = to_name(recipe_value)
            if recipe_id~="" and recipe_id~="None" then
                found = true
            end
        end)
    end)
    return found
end

local function station_has_recipe(station, recipe_id)
    if not valid(station) or recipe_id == "" or recipe_id == "None" then
        return false
    end
    local found = false
    pcall(function()
        each(station:GetRecipes(), function(recipe_value)
            if to_name(recipe_value) == recipe_id then
                found = true
            end
        end)
    end)
    return found
end

local function station_key(station)
    local ok, address = pcall(function()
        return station:GetAddress()
    end)
    if ok and address ~= nil then
        return tostring(address)
    end
    return tostring(station)
end

local function player_controller()
    return U.controller()
end

local function recipe_unlocked(recipe)
    return U.read(function() return player_controller():GetPalPlayerState():GetTechnologyData():IsUnlockCraftRecipe(FName(recipe)) end)==true
end

local function restore_automations(force)
    local context=automation_state:sync()
    if context and automation_state:has_saved() and load_game_data() then
        automation_state:restore(recipe_products,station_has_recipe,recipe_unlocked,force)
    end
end

local function batch_size(station)
    local active=auto_by_station[station_key(station)]
    return (active and active.batch_size) or automation_state:batch_size(station,config.batch_size)
end

local function stock_target(station)
    local active=auto_by_station[station_key(station)]
    return (active and active.stock_target) or automation_state:stock_target(station)
end

local function save_automation(station,recipe,on,batch,target)
    local saved,reason=automation_state:save(station,recipe,on,batch,target)
    if not saved then log(reason) end
    return saved,reason
end

local function remove_widget(widget)
    if valid(widget) then
        pcall(function()
            widget:RemoveFromParent()
        end)
    end
end

local function resolve_workspace(candidate)
    if not valid(candidate) then
        return nil, nil
    end
    local visible = false
    pcall(function()
        visible = candidate:IsVisible() == true
    end)
    if not visible then
        return nil, nil
    end
    local convert_model = nil
    pcall(function()
        convert_model = candidate["Convert Item Model"]
    end)
    if not valid(convert_model) then
        return nil, nil
    end
    local result = {}
    local ok = false
    pcall(function()
        ok = convert_model:TryGetConcreteModel(result)
    end)
    local station = unwrap(result.Model)
    if ok ~= true or not valid(station) then
        return nil, nil
    end
    return convert_model, station
end

local function sync_workspace(candidate)
    local convert_model, station = resolve_workspace(candidate)
    if not valid(convert_model) or not valid(station) then
        return false
    end
    active_convert_ui = convert_model
    active_station = station
    return true
end

local function release_workspace()
    workstation_ui.reset()
    active_workspace = nil
    active_convert_ui = nil
    active_station = nil
    auto_button = nil
    auto_button_label = nil
    auto_button_target = nil
end

automation_state.on_session_change=function()
    scheduler_ui_class=nil
    recipe_products,recipe_product_counts=nil,nil
    release_workspace()
end

local function current_recipe()
    local recipe_id = ""
    pcall(function()
        if valid(active_convert_ui) and valid(active_convert_ui.ProductSettingModel) then
            recipe_id = to_name(active_convert_ui.ProductSettingModel:GetRecipeId())
        end
    end)
    return recipe_id
end

local function selected_supported_recipe()
    local recipe_id = current_recipe()
    local product_id = recipe_id~="" and recipe_id~="None" and load_game_data() and recipe_products[recipe_id] or nil
    if product_id ~= nil
        and station_has_recipe(active_station, recipe_id)
    then
        return recipe_id, product_id
    end
    return nil, nil
end

local function refresh_button()
    if not U.visible(active_workspace) or not valid(auto_button) or not valid(active_station) then
        return
    end
    local key = station_key(active_station)
    local automation = auto_by_station[key]
    local recipe_id = selected_supported_recipe()

    -- Reopening a native window can select its default recipe. The enabled
    -- automation keeps its saved choice until the player pauses and enables anew.
    require("base_data").remember_recipe(active_station,automation and automation.recipe_id or recipe_id)

    local is_enabled = automation ~= nil
    workstation_ui.refresh(is_enabled,recipe_id~=nil,automation and automation.recipe_id,automation_state:save_warning(),automation and automation.status)
end

local function install_button(candidate)
    restore_automations(true)
    if not sync_workspace(candidate) or not station_has_recipes(active_station) then
        return false, "station or recipe data is not ready"
    end
    local button, button_label = workstation_ui.attach(candidate,function() toggle_active_station() end)
    if not valid(button) then
        return false, button_label or "native button could not be created"
    end

    active_workspace = candidate
    auto_button = button
    auto_button_label = button_label
    auto_button_target = nil -- CommonUI owns click dispatch.
    refresh_button()
    log("AutoProduce button attached to the compatible station.")
    return true
end

local function get_scheduler_ui(station)
    if not U.live(station) then return nil end
    if not valid(scheduler_ui_class) then
        scheduler_ui_class = StaticFindObject(UI_MODEL_CLASS_PATH)
        if not valid(scheduler_ui_class) then
            pcall(function() LoadAsset((UI_MODEL_CLASS_PATH:gsub("_C$",""))) end)
            scheduler_ui_class=StaticFindObject(UI_MODEL_CLASS_PATH)
        end
    end
    if not valid(scheduler_ui_class) then
        return nil
    end

    local player = player_controller()
    local gameplay = U.read(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
    local game_instance = U.read(function() return gameplay:GetGameInstance(player) end)
    if not valid(player) or not valid(game_instance) then return nil end
    -- One synchronous game-thread operation owns this model. Never cache a
    -- Lua-only UObject across ticks, rebind it to another station, or force
    -- Native/Async/AsyncLoading flags to keep it alive. The engine can collect
    -- it normally after the inspection/start request returns.
    local ui = U.read(function() return StaticConstructObject(scheduler_ui_class,game_instance) end)
    if not valid(ui) then return nil end
    local ok = pcall(function() ui:Initialize(station) end)
    if not ok then return nil end
    local out={}
    if U.read(function() return ui:TryGetConcreteModel(out) end)~=true
        or not U.live(out.Model) or U.address(out.Model)~=U.address(station) then return nil end
    return ui
end

local function can_refill(station)
    return require("base_data").can_edit_station({station=station,
        base_id=U.guid(U.read(function() return station:GetBaseCampIdBelongTo() end)),
        station_id=U.guid(U.read(function() return station:GetInstanceId() end)) or U.address(station)})
end

local function station_is_idle(station)
    local idle = false
    local remain = nil
    local recipe_id = ""
    local ok = pcall(function()
        remain = tonumber(unwrap(station:GetRemainCreateNum()))
        recipe_id = to_name(station:GetCurrentRecipeId())
    end)
    if ok and type(remain) == "number" then
        -- Palworld may retain the last selected recipe after its queue drains.
        -- A zero queue is idle even when GetCurrentRecipeId still has that ID.
        -- A special negative quantity is not an empty queue.
        idle = remain == 0
    end
    return idle, remain, recipe_id
end

local function report_start_wait(automation, message)
    local now = os.time()
    if not automation.last_status_at or now - automation.last_status_at >= 30 then
        automation.last_status_at = now
        log("AutoProduce [station="..station_key(automation.station)..", recipe="..automation.recipe_id
            ..", batch="..tostring(automation.request_count or batch_size(automation.station)).."]: "..message)
    end
end

-- Choosing a recipe saves a paused preference. Query both the
-- station's recipe list and the player's unlocks again when accepting it.
local function recipe_choices(row,chosen)
    local data=require("base_data")
    local allowed,reason=data.can_edit_station(row)
    if not allowed then return nil,reason end
    if auto_by_station[row.key] or not station_is_idle(row.station) then return nil,"Pause Auto Produce and let the current batch finish first." end
    if not load_game_data() then return nil,"Recipe data is not ready." end
    local technology=U.read(function() return player_controller():GetPalPlayerState():GetTechnologyData() end)
    if not valid(technology) then return nil,"Your recipe unlocks are not available." end
    local choices,seen={},{}
    local ok=U.each(U.read(function() return row.station:GetRecipes() end),function(value)
        local id=to_name(value)
        if id~="" and id~="None" and (not chosen or chosen==id) and not seen[id] then
            seen[id]=true
            if U.read(function() return technology:IsUnlockCraftRecipe(FName(id)) end)==true then
                local product=recipe_products[id]
                if product then
                    choices[#choices+1]={id=id,label=data.item_label(product,row.station),yield_count=recipe_product_counts[id] or 1}
                end
            end
        end
    end)
    if not ok or #choices==0 then return nil,"No unlocked recipes found for this station." end
    if chosen then
        data.select_recipe(row,choices[1])
        local saved,reason=save_automation(row.station,choices[1].id,false)
        return true,"Recipe set to "..choices[1].label..". Enable Auto Produce to start."..(saved and "" or " "..reason)
    end
    table.sort(choices,function(a,b) return a.label==b.label and a.id<b.id or a.label<b.label end)
    return choices
end

local function output_count(station)
    local slot=U.read(function() return station:GetProductSlot() end)
    if not valid(slot) then return nil end
    local count=U.number(U.read(function() return slot:GetStackCount() end))
    return count and count>=0 and count or nil
end

-- A lazy budget for one scan/event drain. Read inventory once per product and
-- reserve known automatic queues once per pass, including unconfirmed starts.
-- Unlimited stations incur none of these extra inventory reads.
local production_pass={}
local function stock_key(station,product)
    local base=U.guid(U.read(function() return station:GetBaseCampIdBelongTo() end))
    return base and (base..":"..product)
end
local function stock_allowance(automation)
    local target=stock_target(automation.station)
    if target<=0 then return math.huge end
    local key=stock_key(automation.station,automation.product_id)
    if not key then return nil end
    if not production_pass.queued then
        local queued={}
        production_pass.queued=queued
        production_pass.unknown_products={}
        for _,a in pairs(auto_by_station) do
            if valid(a.station) then
                local _,remain,recipe=station_is_idle(a.station)
                local output=output_count(a.station)
                local pending=remain==0 and output==0 and a.request_at and (a.request_count or batch_size(a.station)) or 0
                if pending>0 then recipe=a.request_recipe or a.recipe_id end
                local product=recipe_products and recipe_products[recipe] or a.product_id
                local k=stock_key(a.station,product)
                local yield=(recipe_product_counts or {})[recipe] or 1
                if k then
                    if not remain or remain<0 or output==nil
                        or ((remain>0 or output>0) and (recipe=="" or recipe=="None")) then queued[k]=false
                    elseif queued[k]~=false then
                        queued[k]=(queued[k] or 0)+remain*yield+output+pending*yield
                    end
                else production_pass.unknown_products[product]=true end
            end
        end
        production_pass.stock={}
    end
    if production_pass.queued[key]==false or production_pass.unknown_products[automation.product_id] then return nil end
    local stock=production_pass.stock[key]
    if stock==nil then
        local utility=U.read(function() return StaticFindObject("/Script/Pal.Default__PalItemUtility") end)
        stock=U.number(U.read(function() return utility:CountLocalPlayerInsideBaseCampItemNum64(player_controller(),FName(automation.product_id)) end))
        production_pass.stock[key]=stock and stock>=0 and stock or false
    end
    if stock==false or not stock or stock<0 then return nil end
    return math.max(0,math.ceil((target-stock-(production_pass.queued[key] or 0))/((recipe_product_counts or {})[automation.recipe_id] or 1)))
end

local function reserve_batch(automation)
    if not production_pass.queued then return end
    local key=stock_key(automation.station,automation.product_id)
    if key and production_pass.queued[key]~=false then
        production_pass.queued[key]=(production_pass.queued[key] or 0)+automation.request_count*((recipe_product_counts or {})[automation.recipe_id] or 1)
    end
end

local function confirm_batch(automation,remain,recipe,now,completed)
    if remain and (remain>0 or completed) and recipe==automation.request_recipe then
        base_stats.after_refill(station_key(automation.station),recipe,remain,now)
        automation.status="Producing"
        -- One-craft batches should not turn successful refills into a log flood.
        if not automation.last_confirm_log_at or now-automation.last_confirm_log_at>=30 then
            automation.last_confirm_log_at=now
            log(completed and ("Game completed the requested batch of "..automation.product_id.." before the next scan.")
                or ("Game confirmed "..remain.." queued craft(s) of "..automation.product_id.."."))
        end
        automation.request_at,automation.request_recipe=nil,nil
        return true
    end
end

local function supply_check(row)
    local data=require("base_data")
    local allowed,reason=data.can_edit_station(row)
    if not allowed then return nil,reason end
    local pc=player_controller()
    if not row.recipe_id or not station_has_recipe(row.station,row.recipe_id) then return nil,"Recipe is no longer available." end
    local ui=get_scheduler_ui(row.station)
    local model=U.read(function() return ui.ProductSettingModel end)
    if not valid(model) then return nil,"The game's recipe information is not ready." end
    local ok=pcall(function() model:SelectRecipe(FName(row.recipe_id)) end)
    if not ok or U.name(U.read(function() return model:GetRecipeId() end))~=row.recipe_id then return nil,"The recipe could not be inspected." end
    -- This separate UI model never starts a batch while inspecting materials.
    local plan={at=os.time(),base=row.base_id,key=row.key,recipe=row.recipe_id,product=row.product,station=row.station_name,
        batch=batch_size(row.station),yield_count=row.yield_count or 1,rate=row.rate,materials={},
        craftable=U.number(U.read(function() return model:CalcMaxProductableNum() end))}
    local utility=U.read(function() return StaticFindObject("/Script/Pal.Default__PalItemUtility") end)
    local function add(id,cost)
        if id=="" or id=="None" or not cost or cost<=0 then return end
        local f=FName(id)
        local base=U.number(U.read(function() return utility:CountLocalPlayerInsideBaseCampItemNum64(pc,f) end))
        local bag=U.number(U.read(function() return utility:CountLocalPlayerInventoryItemNum64(pc,f) end))
        plan.materials[#plan.materials+1]={id=id,name=data.item_label(id,row.station),cost=cost,
            base=base and base>=0 and base or nil,bag=bag and bag>=0 and bag or nil}
    end
    local out={}
    pcall(function() model:GetRequiredMaterialInfos(out,true) end)
    U.each(out,function(v) add(U.name(U.read(function() return v.StaticItemId end)),U.number(U.read(function() return v.Num end))) end)
    if #plan.materials==0 then
        local recipe=U.read(function() return model:GetRecipe() end)
        for i=1,5 do add(U.name(U.read(function() return recipe["Material"..i.."_Id"] end)),
            U.number(U.read(function() return recipe["Material"..i.."_Count"] end))) end
    end
    require("base_insights").supply_outlook(plan)
    return plan
end

local function start_batch(automation)
    local now = os.time()
    local station = automation.station
    if not valid(station) then
        return
    end
    local idle, remain, current_recipe = station_is_idle(station)
    -- Reuse the queue read the refiller already needs. An enabled station can
    -- keep its own rate warm after the full dashboard sampler goes to sleep.
    if remain and remain>=0 and (current_recipe==automation.recipe_id or remain==0) then
        base_stats.observe_automation(station_key(station),automation.recipe_id,remain,
            (recipe_product_counts or {})[automation.recipe_id] or 1,now)
    end
    -- A retry delay controls *requests*. Keep observing the queue so an
    -- acknowledgment or a pickup during a backoff doesn't break the rate history.
    if now < (automation.retry_after or 0) then return end
    automation.retry_after = now + config.scan_interval_ms / 1000
    if automation.request_at then
        local completed=remain==0 and (automation.completion_seen or (output_count(station) or 0)>0)
        if confirm_batch(automation,remain,current_recipe,now,completed) then
            automation.completion_seen=nil
            -- A one-craft batch may finish and be collected between scans.
            -- Continue immediately if the finish event confirmed it.
            if not completed then return end
        else
            if now-automation.request_at<10 then return end
            automation.request_at,automation.request_recipe=nil,nil
            automation.status="No queue confirmation"
            automation.retry_after=now+15
            report_start_wait(automation,"no matching queue was confirmed; retrying in 15 seconds")
            return
        end
    end
    if not idle then
        automation.status = remain and remain > 0 and "Producing" or "Queue unavailable"
        if remain==nil then report_start_wait(automation,"queue state unavailable") end
        return
    end
    if not station_has_recipe(station, automation.recipe_id) then
        automation.status = "Recipe unavailable"
        automation.retry_after=now+5
        report_start_wait(automation,"recipe data unavailable; keeping ON and retrying")
        return
    end
    if not can_refill(station) then
        automation.status="Visit base to resume"
        automation.retry_after=now+5
        report_start_wait(automation,"visit this station's guild base to refill")
        return
    end
    local output=output_count(station)
    if output==nil or output>0 then
        automation.status=output==nil and "Output unavailable" or "Waiting for pickup"
        automation.retry_after=now+5
        report_start_wait(automation,output==nil and "output slot is not ready" or "finished products must be collected by Pals or the player")
        return
    end
    if not recipe_unlocked(automation.recipe_id) then
        automation.status="Waiting for recipe unlock"
        automation.retry_after=now+5
        return
    end

    local allowance=stock_allowance(automation)
    if not allowance or allowance==0 then
        automation.status=allowance==0 and "Stock target reached" or "Stock check unavailable"
        automation.retry_after=now+5
        return
    end

    local ui = get_scheduler_ui(station)
    local model=U.read(function() return ui.ProductSettingModel end)
    if not valid(ui) or not valid(model) then
        automation.status = "Waiting for station"
        automation.retry_after=now+5
        report_start_wait(automation, "workstation production interface is not ready")
        return
    end

    local started = false
    local can_start_code = nil
    local ok_start, start_error = pcall(function()
        model:SelectRecipe(FName(automation.recipe_id))
        if to_name(model:GetRecipeId())~=automation.recipe_id then
            automation.status="Recipe not selected"
            return
        end
        local maximum=U.number(model:CalcMaxProductableNum())
        if not maximum or maximum<0 then
            automation.status="Supplies unavailable"
            return
        end
        local count=math.min(batch_size(station),math.floor(maximum),allowance)
        if count<1 then automation.status="Waiting for resources";return end
        model:SetProductNumByInput(count)
        -- Fail closed if another native callback changes the recipe/quantity.
        local selected_count=U.number(model:GetProductNum())
        if to_name(model:GetRecipeId())~=automation.recipe_id or not selected_count
            or selected_count<1 or selected_count>count or selected_count%1~=0 then
            automation.status="Recipe not selected"
            return
        end
        automation.request_count=selected_count
        ui:UpdateProductSetting_TransportToStorage(true)
        can_start_code = U.number(ui:CanStartProduction())
        if can_start_code == 0 then
            base_stats.before_refill(station_key(station), automation.recipe_id, remain,
                (recipe_product_counts or {})[automation.recipe_id] or 1, now)
            ui:StartProduction()
            started = true
        end
    end)
    if started then
        reserve_batch(automation)
        automation.completion_seen=nil
        automation.request_at,automation.request_recipe=now,automation.recipe_id
        automation.status="Confirming queue"
        local _,new_remaining,new_recipe=station_is_idle(station)
        confirm_batch(automation,new_remaining,new_recipe,now)
    elseif not ok_start then
        automation.status = "Start request failed"
        automation.retry_after=now+15
        report_start_wait(automation, "game rejected the start request: " .. tostring(start_error))
    elseif can_start_code ~= nil then
        automation.status = ({[1]="Recipe not selected",[2]="Station unavailable",[3]="Power unit unavailable",
            [4]="Waiting for resources",[5]="Waiting for power"})[can_start_code] or "Start blocked by game"
        automation.retry_after=now+math.max(5,config.scan_interval_ms/1000)
        report_start_wait(automation, "normal recipe checks blocked the start (code " .. tostring(can_start_code) .. ")")
    else
        automation.retry_after=now+5
        report_start_wait(automation,automation.status or "game did not confirm the start request")
    end
end

-- Fast path for this station only; it does not sample food, redraw the menu,
-- discover objects or inspect other bases. Finish/pickup bursts are coalesced
-- into one callback, rate limited per station, and drained two stations at a
-- time. Periodic polling remains the fallback if a game build lacks a hook.
local event_pending,event_timer={},false
local function drain_station_events()
    event_timer=false
    production_pass={}
    local synced,context=pcall(function() return automation_state:sync() end)
    if not synced or not context then event_pending={};return end
    local count=0
    for key,entry in pairs(event_pending) do
        event_pending[key]=nil
        local automation=entry.automation
        local ok,err=pcall(function()
            if auto_by_station[key]==automation and automation_state:valid(automation) then
                local status=automation.status
                if status=="Producing" or status=="Waiting for pickup" or status=="Confirming queue"
                    or status=="Starting" or status=="Resuming" then automation.retry_after=0 end
                start_batch(automation)
            end
        end)
        if not ok then
            automation.status="Start request failed";automation.retry_after=os.time()+15
            report_start_wait(automation,tostring(err))
        end
        count=count+1
        if count>=2 then break end
    end
    if next(event_pending) and not event_timer then
        event_timer=true;U.defer(100,drain_station_events)
    end
end
local function station_changed(context,finished)
    if not config.enabled or next(auto_by_station)==nil then return end
    local station=U.unwrap(context)
    local key=U.address(station)
    local automation=key and auto_by_station[key]
    if not automation then return end
    local now=os.time()
    -- No recipe, inventory or queue calls in the notification itself. A finish
    -- signal only confirms a pending request if the later queue read matches.
    if finished and automation.request_at then automation.completion_seen=true end
    if (event_pending[key] and event_pending[key].automation==automation) or now<(automation.event_after or 0) then return end
    automation.event_after=now+1
    event_pending[key]={automation=automation}
    if not event_timer then event_timer=true;U.defer(100,drain_station_events) end
end

local function set_station_settings(row,count,target)
    restore_automations(true)
    local allowed,reason=require("base_data").can_edit_station(row)
    if not allowed then return false,reason end
    if count~=nil and (type(count)~="number" or count~=count or count<1 or count>9999 or count%1~=0) then return false,"Choose 1 to 9999 crafts." end
    if target~=nil and (type(target)~="number" or target~=target or target<0 or target>999999 or target%1~=0) then return false,"Choose a stock target from 0 to 999999; 0 is unlimited." end
    local automation=auto_by_station[station_key(row.station)]
    local recipe=automation and automation.recipe_id or row.recipe_id
    if not recipe or recipe=="" or recipe=="None" or not station_has_recipe(row.station,recipe) then return false,"Choose an available recipe first." end
    if automation then
        automation.batch_size=count or automation.batch_size
        automation.stock_target=target or automation.stock_target
    end
    local saved,warning=save_automation(row.station,recipe,automation~=nil,count,target)
    row.batch_size,row.stock_target=batch_size(row.station),stock_target(row.station)
    return true,"Saved for the next refill. The current queue is unchanged."..(saved and "" or " "..warning)
end

local function hovered(target)
    if not valid(target) then
        return false
    end
    local result = false
    pcall(function()
        result = target:IsHovered()
    end)
    return result == true
end

toggle_active_station = function()
    restore_automations(true)
    if not valid(active_workspace) or not valid(auto_button) or not sync_workspace(active_workspace) then
        return
    end
    local key = station_key(active_station)
    if auto_by_station[key] ~= nil then
        local recipe=auto_by_station[key].recipe_id
        save_automation(active_station,recipe,false)
        auto_by_station[key] = nil
        refresh_button()
        log("AutoProduce disabled for this station. Its current batch can finish.")
        return
    end

    if not load_game_data() then
        return
    end
    local recipe_id, product_id = selected_supported_recipe()
    if recipe_id == nil then
        log("Select a recipe supported by this production station first.")
        return
    end
    if not recipe_unlocked(recipe_id) then log("This recipe is not unlocked for your character.");return end
    auto_by_station[key] = {
        station = active_station,
        recipe_id = recipe_id,
        product_id = product_id,
        status = "Starting",
        batch_size = batch_size(active_station),
        stock_target = stock_target(active_station),
    }
    save_automation(active_station,recipe_id,true)
    refresh_button()
    log("AutoProduce enabled for " .. product_id .. ". It will keep refilling while the game accepts the normal start request.")
    station_changed(active_station,false)
    schedule_scan()
end

local function queue_workspace_check(candidate, generation, attempt)
    U.defer(200, function()
            if generation ~= workspace_event_generation or not valid(candidate) then
                return
            end

            local box = nil
            pcall(function()
                box = candidate.HorizontalBox_TransportCheckBox
            end)
            local convert_model, station = resolve_workspace(candidate)
            if valid(box) and valid(convert_model) and valid(station) and station_has_recipes(station) then
                if candidate ~= active_workspace then
                    release_workspace()
                elseif valid(auto_button) then
                    active_convert_ui = convert_model
                    active_station = station
                    refresh_button()
                    return
                else
                    remove_widget(auto_button)
                end

                active_convert_ui = convert_model
                active_station = station
                local installed, reason = install_button(candidate)
                if installed then
                    return
                end
                if attempt >= 5 then
                    local now = os.time()
                    if now - last_button_notice_at >= 30 then
                        last_button_notice_at = now
                        log("AutoProduce button was not attached: " .. tostring(reason))
                    end
                    return
                end
            elseif attempt >= 5 then
                local now = os.time()
                if now - last_button_notice_at >= 30 then
                    last_button_notice_at = now
                    log("AutoProduce could not attach because the workstation UI was not ready after retries.")
                end
                return
            end

            queue_workspace_check(candidate, generation, attempt + 1)
    end)
end

local function on_workspace_construct(context)
    local candidate = nil
    pcall(function()
        candidate = context:get()
    end)
    if not valid(candidate) then
        return
    end
    workspace_event_generation = workspace_event_generation + 1
    queue_workspace_check(candidate, workspace_event_generation, 1)
end

local function on_workspace_destruct(context)
    local candidate = nil
    pcall(function()
        candidate = context:get()
    end)
    workspace_event_generation = workspace_event_generation + 1
    if not valid(candidate) or candidate ~= active_workspace then
        return
    end
    local generation = workspace_event_generation
    U.defer(250, function()
            if generation ~= workspace_event_generation or candidate ~= active_workspace then
                return
            end
            local visible = false
            pcall(function()
                visible = candidate:IsVisible() == true
            end)
            if not visible then
                release_workspace()
            end
    end)
end

local function observe_widget_class(class_path, construct_callback, destruct_callback)
    local state = registered_lifecycle_hooks[class_path]
    if state == nil then
        state = { construct = false, destruct = false }
        registered_lifecycle_hooks[class_path] = state
    end
    if not state.construct then
        local ok, err = pcall(function()
            RegisterHook(class_path .. ":Construct", construct_callback)
        end)
        state.construct = ok
        if not ok then
            log("Could not hook Construct for " .. class_path .. ": " .. tostring(err))
        end
    end
    if not state.destruct then
        local ok, err = pcall(function()
            RegisterHook(class_path .. ":Destruct", destruct_callback)
        end)
        state.destruct = ok
        if not ok then
            log("Could not hook Destruct for " .. class_path .. ": " .. tostring(err))
        end
    end
end

local function menu_is_visible(candidate)
    return U.live(candidate) and U.visible(candidate) and U.read(function() return candidate:IsActivated() end)~=false
end

local function queue_menu_check(candidate, generation, attempt)
    U.defer(200, function()
            if generation ~= main_menu_event_generation or not valid(candidate) then
                return
            end
            if menu_is_visible(candidate) and base_stats.set_menu_visible(true, candidate) then
                active_main_menu = candidate
                return
            end
            if attempt < 5 then
                queue_menu_check(candidate, generation, attempt + 1)
            end
    end)
end

local function on_main_menu_construct(context)
    local candidate = nil
    pcall(function()
        candidate = context:get()
    end)
    if not valid(candidate) then
        return
    end
    main_menu_event_generation = main_menu_event_generation + 1
    active_main_menu = candidate
    queue_menu_check(candidate, main_menu_event_generation, 1)
end

local function on_main_menu_destruct(context)
    local candidate = nil
    pcall(function()
        candidate = context:get()
    end)
    if candidate ~= active_main_menu then
        return
    end
    main_menu_event_generation = main_menu_event_generation + 1
    local generation = main_menu_event_generation
    U.defer(250, function()
            if generation ~= main_menu_event_generation or candidate ~= active_main_menu then
                return
            end
            if menu_is_visible(candidate) then
                queue_menu_check(candidate, generation, 1)
                return
            end
            active_main_menu = nil
            base_stats.set_menu_visible(false)
    end)
end

local function observe_workspace_object(candidate)
    if not valid(candidate) then
        return
    end
    observe_widget_class(WORKSPACE_CLASS_PATH, on_workspace_construct, on_workspace_destruct)
    local state=registered_lifecycle_hooks[WORKSPACE_CLASS_PATH]
    if not state.recipe then
        local ok,err=pcall(function()
            RegisterHook(WORKSPACE_CLASS_PATH..":Update Recipe Detail",function(context)
                local owner=unwrap(context)
                ExecuteInGameThread(function()
                    if U.valid(owner) and U.address(owner)==U.address(active_workspace) then refresh_button() end
                end)
            end)
        end)
        state.recipe=ok
        if not ok then log("Could not observe recipe selection: "..tostring(err)) end
    end
    if not state.setup then
        state.setup=pcall(function() RegisterHook(WORKSPACE_CLASS_PATH..":OnSetup",on_workspace_construct) end)
    end
    workspace_event_generation = workspace_event_generation + 1
    queue_workspace_check(candidate, workspace_event_generation, 1)
end

local function observe_main_menu_object(candidate)
    if not U.live(candidate) then
        return
    end
    observe_widget_class(MAIN_MENU_CLASS_PATH, on_main_menu_construct, on_main_menu_destruct)
    local state = registered_lifecycle_hooks[MAIN_MENU_CLASS_PATH]
    if not state.setup then
        state.setup = pcall(function() RegisterHook(MAIN_MENU_CLASS_PATH .. ":OnSetup", on_main_menu_construct) end)
    end
    if not state.cancel then
        state.cancel = pcall(function()
            RegisterHook(MAIN_MENU_CLASS_PATH .. ":OnCancelAction", function(context)
                local candidate=unwrap(context)
                -- Cancel can be declined (for example by a native confirmation).
                -- Don't blank Bases until the menu actually leaves the stack.
                U.defer(100,function()
                    if U.address(candidate)==U.address(active_main_menu) and not menu_is_visible(candidate) then
                        main_menu_event_generation=main_menu_event_generation+1
                        active_main_menu=nil
                        base_stats.set_menu_visible(false)
                    end
                end)
            end)
        end)
    end
    if not state.select then
        state.select = pcall(function()
            RegisterHook(MAIN_MENU_CLASS_PATH .. ":OnNextTabAction", function()
                ExecuteInGameThread(function() base_stats.close() end)
            end)
            RegisterHook(MAIN_MENU_CLASS_PATH .. ":OnPrevTabAction", function()
                ExecuteInGameThread(function() base_stats.close() end)
            end)
            RegisterHook(MAIN_MENU_CLASS_PATH .. ":On Changed Tab Index Event", function()
                ExecuteInGameThread(function() if base_stats.is_open() then base_stats.close() end end)
            end)
        end)
    end
    main_menu_event_generation = main_menu_event_generation + 1
    active_main_menu = candidate
    queue_menu_check(candidate, main_menu_event_generation, 1)
end

local scan_errors={}
local function scan_job(label,fn,on_error)
    local ok,err=pcall(fn)
    if ok then return true end
    if on_error then on_error() end
    local now=os.time()
    if not scan_errors[label] or now-scan_errors[label]>=30 then
        scan_errors[label]=now
        log(label.." failed; other jobs continue: "..tostring(err))
    end
    return false
end

local function scan()
    if not config.enabled or is_scanning then
        return
    end
    is_scanning = true
    production_pass={}
    scan_job("Recipe data",function()
        if next(auto_by_station)~=nil or base_stats.needs_tick() then load_game_data() end
    end)
    -- A menu/meal/statistics error must never starve every production station.
    local restored=scan_job("Automation restore",restore_automations)
    if restored and next(auto_by_station)~=nil then
        for key, automation in pairs(auto_by_station) do
            scan_job("Production",function()
                local current=automation_state:valid(automation)
                if current==false then
                    auto_by_station[key]=nil
                    automation_state.applied[key]=nil
                    return
                end
                if not current then
                    automation.status="Waiting for station"
                    automation.retry_after=os.time()+5
                    return
                end
                start_batch(automation)
            end,function()
                automation.status="Start request failed"
                automation.retry_after=os.time()+15
            end)
        end
    end
    scan_job("Workstation control",refresh_button)
    scan_job("Automatic meals",auto_eat.tick)
    scan_job("Base statistics",function()
        if base_stats.needs_tick() then
            base_stats.tick(recipe_products, recipe_product_counts,true)
        else
            require("base_data").sample_current_food(os.time())
        end
    end)
    is_scanning = false
end

local function has_scan_work()
    -- Keep the cheap current-base food check alive even with no automations,
    -- AFK meals disabled and the ten-minute full statistics window expired.
    return config.enabled
end

local function next_scan_delay()
    if next(auto_by_station)==nil then return 5000 end
    local earliest_retry = nil
    local now = os.time()
    for _, automation in pairs(auto_by_station) do
        local retry_at = tonumber(automation.retry_after)
        if retry_at ~= nil then
            local remaining = math.max(0, retry_at - now)
            if earliest_retry == nil or remaining < earliest_retry then
                earliest_retry = remaining
            end
        end
    end
    local delay = earliest_retry and math.max(250, math.floor(earliest_retry * 1000)) or config.scan_interval_ms
    -- Even with AFK meals disabled and Bases asleep, keep the active
    -- station's measurement interval below the telemetry gap threshold.
    return math.min(delay,5000)
end

schedule_scan = function(delay_ms)
    if not config.enabled or scan_timer_pending or not has_scan_work() then
        return
    end
    scan_timer_pending = true
    U.defer(delay_ms or next_scan_delay(), function()
            scan_timer_pending = false
            scan()
            if has_scan_work() then
                schedule_scan()
            end
    end)
end

RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
    if not config.enabled then return end
    ExecuteInGameThread(function()
        auto_eat.activity()
        if base_stats.handle_click(recipe_products, recipe_product_counts) then
            schedule_scan()
            return
        end
        if hovered(auto_button_target) then
            toggle_active_station()
        end
    end)
end)

RegisterKeyBind(Key.F8, function()
    if not config.enabled then return end
    ExecuteInGameThread(function()
        auto_eat.activity()
        load_game_data()
        base_stats.toggle(recipe_products, recipe_product_counts)
        schedule_scan()
    end)
end)

RegisterKeyBind(Key.RIGHT_MOUSE_BUTTON, function()
    if not config.enabled then return end
    ExecuteInGameThread(function()
        auto_eat.activity()
        if base_stats.is_open() then base_stats.handle_click(recipe_products, recipe_product_counts, 1); schedule_scan() end
    end)
end)

if not config.enabled then
    log("Disabled in Scripts/config.lua.")
else
    base_stats.configure({
        get_batch_size=batch_size,
        set_batch_size=function(row,count) return set_station_settings(row,count,nil) end,
        get_stock_target=stock_target,
        set_stock_target=function(row,target) return set_station_settings(row,nil,target) end,
        recipe_choices=recipe_choices,
        supply_check=supply_check,
        get_meals=function() return auto_eat.summary() end,
        toggle_meals=function() auto_eat.toggle();schedule_scan(250) end,
        get_automation = function(key) return auto_by_station[key] end,
        set_automation = function(row)
            restore_automations(true)
            if not valid(row.station) then return false, "Station is no longer loaded." end
            local key = station_key(row.station)
            if auto_by_station[key] then
                local saved,reason=save_automation(row.station,auto_by_station[key].recipe_id,false)
                auto_by_station[key] = nil
                refresh_button()
                return true, "Auto Produce paused. The current batch can finish."..(saved and "" or " "..reason)
            end
            local allowed,reason=require("base_data").can_edit_station(row)
            if not allowed then return false,reason end
            if not load_game_data() or not recipe_products[row.recipe_id] or not station_has_recipe(row.station, row.recipe_id) then
                return false, "Select a supported recipe at this station first."
            end
            if U.read(function() return player_controller():GetPalPlayerState():GetTechnologyData():IsUnlockCraftRecipe(FName(row.recipe_id)) end)~=true then
                return false, "This recipe is not unlocked for your character."
            end
            auto_by_station[key] = {station=row.station, recipe_id=row.recipe_id, product_id=recipe_products[row.recipe_id], status="Starting",
                batch_size=batch_size(row.station),stock_target=stock_target(row.station)}
            local saved,reason=save_automation(row.station,row.recipe_id,true)
            refresh_button()
            station_changed(row.station,false)
            schedule_scan(250)
            return true, "Auto Produce enabled for " .. tostring(row.product) .. "."..(saved and "" or " "..reason)
        end,
        wake = function() schedule_scan(250) end,
    })
    log("Loaded 0.1.0-beta.2. Batch limit="..config.batch_size..", scan interval="..config.scan_interval_ms.."ms. Open Bases or press F8.")

    local fast_hooks=0
    for _,event in ipairs(config.fast_refill and {{"OnFinishWorkInServer",true},{"OnUpdateContainerContentInServer",false},
        {"OnRep_RemainProductNum",false},{"PickupProduct_ServerInternal",false}} or {}) do
        local finished=event[2]
        local ok,err=pcall(function()
            RegisterHook("/Script/Pal.PalMapObjectConvertItemModel:"..event[1],function() end,
                function(context) station_changed(context,finished) end)
        end)
        if ok then fast_hooks=fast_hooks+1 else log("Fast refill hook "..event[1].." unavailable; polling retained: "..tostring(err)) end
    end
    log("Fast refill notifications: "..fast_hooks.."/4. Polling fallback remains enabled.")

    local workspace_watch_ok, workspace_watch_error = pcall(function()
        NotifyOnNewObject(WORKSPACE_CLASS_PATH, function(candidate)
            observe_workspace_object(candidate)
        end)
    end)
    if workspace_watch_ok then
        log("Workstation lifecycle watcher armed.")
    else
        log("Workstation lifecycle watcher could not be armed: " .. tostring(workspace_watch_error))
    end

    local menu_watch_ok, menu_watch_error = pcall(function()
        NotifyOnNewObject(MAIN_MENU_CLASS_PATH, function(candidate)
            observe_main_menu_object(candidate)
        end)
    end)
    if menu_watch_ok then
        log("Main menu lifecycle watcher armed.")
    else
        log("Main menu lifecycle watcher could not be armed: " .. tostring(menu_watch_error))
    end

    -- A one-time check covers widgets that existed before UE4SS registered
    -- these listeners. After startup, discovery remains event-driven.
    local existing_workspace = nil
    pcall(function()
        existing_workspace = FindFirstOf("WBP_IngameMenu_WorkSpace_C")
    end)
    observe_workspace_object(existing_workspace)

    for _, existing_main_menu in ipairs(U.read(function() return FindAllOf("WBP_InGameMainMenu_C") end) or {}) do
        observe_main_menu_object(existing_main_menu)
    end
    if has_scan_work() then schedule_scan(5000) end
end
