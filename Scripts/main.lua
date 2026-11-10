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
local scheduler_ui = nil
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
    if object == nil then
        return false
    end
    local ok, result = pcall(function()
        return object:IsValid()
    end)
    return ok and result == true
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

local function save_automation(station,recipe,on)
    local saved,reason=automation_state:save(station,recipe,on)
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
    scheduler_ui=nil
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
    if not valid(auto_button) or not valid(active_station) then
        return
    end
    local key = station_key(active_station)
    local automation = auto_by_station[key]
    local recipe_id = selected_supported_recipe()

    -- Reopening a native window can select its default recipe. The enabled
    -- automation keeps its saved choice until the player pauses and enables anew.
    require("base_data").remember_recipe(active_station,automation and automation.recipe_id or recipe_id)

    local is_enabled = automation ~= nil
    workstation_ui.refresh(is_enabled,recipe_id~=nil,automation and automation.recipe_id,automation_state:save_warning())
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

    if not valid(scheduler_ui) then
        local player = player_controller()
        local gameplay = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local game_instance = nil
        if valid(player) and valid(gameplay) then
            pcall(function()
                game_instance = gameplay:GetGameInstance(player)
            end)
        end
        if not valid(game_instance) then
            return nil
        end
        pcall(function()
            scheduler_ui = StaticConstructObject(
                scheduler_ui_class,
                game_instance,
                0,
                0,
                0x0E000000,
                false,
                false,
                nil,
                nil,
                nil
            )
        end)
    end

    if not valid(scheduler_ui) then
        return nil
    end
    local initialized = false
    pcall(function()
        scheduler_ui:Initialize(station)
        initialized = true
    end)
    return initialized and scheduler_ui or nil
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
    if now - (automation.last_status_at or 0) >= 30 then
        automation.last_status_at = now
        log("AutoProduce is waiting for " .. automation.product_id .. ": " .. message)
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

local function confirm_batch(automation,remain,recipe,now)
    if remain and remain>0 and recipe==automation.request_recipe then
        base_stats.after_refill(station_key(automation.station),recipe,remain,now)
        automation.status="Producing"
        log("Game confirmed "..remain.." queued craft(s) of "..automation.product_id..".")
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
        batch=config.batch_size,yield_count=row.yield_count or 1,rate=row.rate,materials={},
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
        if confirm_batch(automation,remain,current_recipe,now) then return end
        if now-automation.request_at<10 then return end
        automation.request_at,automation.request_recipe=nil,nil
        automation.status="No queue confirmation"
        automation.retry_after=now+15
        report_start_wait(automation,"no matching queue was confirmed; retrying in 15 seconds")
        return
    end
    if not idle then
        automation.status = remain and remain > 0 and "Producing" or "Queue unavailable"
        if remain==nil then report_start_wait(automation,"queue state unavailable") end
        return
    end
    if not station_has_recipe(station, automation.recipe_id) then
        automation.status = "Recipe unavailable"
        auto_by_station[station_key(station)]=nil
        log("AutoProduce stopped because the station no longer supports its saved recipe.")
        return
    end
    if not recipe_unlocked(automation.recipe_id) then
        automation.status="Waiting for recipe unlock"
        automation.retry_after=now+5
        return
    end

    local ui = get_scheduler_ui(station)
    if not valid(ui) or not valid(ui.ProductSettingModel) then
        automation.status = "Waiting for station"
        report_start_wait(automation, "workstation production interface is not ready")
        return
    end

    local started = false
    local can_start_code = nil
    local ok_start, start_error = pcall(function()
        ui.ProductSettingModel:SelectRecipe(FName(automation.recipe_id))
        ui.ProductSettingModel:SetProductNumByInput(config.batch_size)
        ui:UpdateProductSetting_TransportToStorage(true)
        can_start_code = ui:CanStartProduction()
        if can_start_code == 0 then
            base_stats.before_refill(station_key(station), automation.recipe_id, remain,
                (recipe_product_counts or {})[automation.recipe_id] or 1, now)
            ui:StartProduction()
            started = true
        end
    end)
    if started then
        automation.request_at,automation.request_recipe=now,automation.recipe_id
        automation.status="Confirming queue"
        local _,new_remaining,new_recipe=station_is_idle(station)
        confirm_batch(automation,new_remaining,new_recipe,now)
    elseif not ok_start then
        automation.status = "Start request failed"
        report_start_wait(automation, "game rejected the start request: " .. tostring(start_error))
    elseif can_start_code ~= nil then
        automation.status = ({[1]="Recipe not selected",[2]="Station unavailable",[3]="Power unit unavailable",
            [4]="Waiting for resources",[5]="Waiting for power"})[can_start_code] or "Start blocked by game"
        automation.retry_after=now+math.max(5,config.scan_interval_ms/1000)
        report_start_wait(automation, "normal recipe checks blocked the start (code " .. tostring(can_start_code) .. ")")
    else
        report_start_wait(automation, "game did not confirm the start request")
    end
end

local function clean_automations()
    for key, automation in pairs(auto_by_station) do
        if not automation_state:valid(automation) then
            auto_by_station[key] = nil
            automation_state.applied[key] = nil
        end
    end
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
    }
    save_automation(active_station,recipe_id,true)
    refresh_button()
    log("AutoProduce enabled for " .. product_id .. ". It will keep refilling while the game accepts the normal start request.")
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

local function scan()
    if not config.enabled or is_scanning then
        return
    end
    is_scanning = true
    local ok_scan, err = pcall(function()
        if next(auto_by_station)~=nil or base_stats.needs_tick() then load_game_data() end
        auto_eat.tick()
        restore_automations()
        refresh_button()
        if next(auto_by_station) ~= nil then
            clean_automations()
            for _, automation in pairs(auto_by_station) do
                start_batch(automation)
            end
        end
        if base_stats.needs_tick() then
            base_stats.tick(recipe_products, recipe_product_counts,true)
        else
            require("base_data").sample_current_food(os.time())
        end
    end)
    is_scanning = false
    if not ok_scan then
        log("Scan stopped safely after an error: " .. tostring(err))
    end
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
            auto_by_station[key] = {station=row.station, recipe_id=row.recipe_id, product_id=recipe_products[row.recipe_id], status="Starting"}
            local saved,reason=save_automation(row.station,row.recipe_id,true)
            refresh_button()
            schedule_scan(250)
            return true, "Auto Produce enabled for " .. tostring(row.product) .. "."..(saved and "" or " "..reason)
        end,
        wake = function() schedule_scan(250) end,
    })
    log("Loaded. Open Bases in the main menu or press F8. Built-in priorities and food forecasts are available in the overview.")

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
