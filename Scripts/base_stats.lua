local U = require("ap_util")
local data = require("base_data")
local priorities = require("priorities")
local ui = require("overview_ui")
local scene = require("overview_scene")
local M = {}
local state = {view="Overview",base_page=1}
local snapshot = {at=0,camps={}}
local last_sample, menu_open, sampling_until = 0, false, 0
local get_automation, set_automation, recipe_choices, supply_check, wake
local get_meals,toggle_meals
local products, yields = {}, {}
local session_controller = nil
local last_diagnostic,last_slow= nil,0
local active_sample
local function sync_session(pc)
    local identity=U.address(pc)
    if session_controller and identity~=session_controller then
        active_sample=nil;data.reset_world();priorities.demand={};priorities.messages={};ui.reset()
        snapshot={at=os.time(),camps={}};sampling_until=0;last_sample=0;menu_open=false
        state={view="Overview",base_page=1}
    end
    session_controller=identity
end
local function render()
    local editable,reason=true,nil
    if state.view=="Priorities" then editable,reason=priorities.available() end
    local note=priorities.messages and priorities.messages[state.base]
    return ui.render(scene.build(snapshot,state,{bases=priorities.store.bases,status=editable and (note and note.text or "Set base defaults below, or adjust an individual Pal") or reason,
        ready=editable and (not note or note.ready),afk=get_meals and get_meals()}))
end
function M.configure(options)
    get_automation,set_automation,wake=options.get_automation,options.set_automation,options.wake
    recipe_choices,supply_check=options.recipe_choices,options.supply_check
    get_meals,toggle_meals=options.get_meals,options.toggle_meals
    ui.on_tab_click=function() M.open(products,yields) end
    data.init(); priorities.init(wake)
end
function M.is_open() return ui.visible and U.valid(ui.widget) end
function M.needs_tick() return M.is_open() or os.time()<sampling_until or priorities.has_work() end
function M.close() state.picker=nil;state.plan=nil;ui.cancel_open();ui.hide(menu_open) end
function M.close_menu() return ui.close_menu() end
function M.toggle(recipe_products, recipe_yields)
    sync_session(U.controller())
    if ui.opening or (ui.owns_menu_input() and ui.menu_active()) then M.close_menu();return end
    M.open(recipe_products,recipe_yields)
end
function M.open(recipe_products, recipe_yields)
    sync_session(U.controller())
    products,yields=recipe_products or products,recipe_yields or yields
    if M.is_open() or ui.opening then return end
    if not ui.menu_active() then
        ui.open_native_menu(function() menu_open=true;M.open(products,yields) end)
        return
    end
    U.log("Overview opening.")
    if not ui.show() then return end
    U.log("Overview visible; reading base data.")
    if data.error then data.rediscover() end
    last_sample=0
    local rendered=M.tick(products,yields)
    U.log(rendered and "Overview initial update complete." or "Overview initial display incomplete; see diagnostics above.")
    if wake then wake() end
end
function M.set_menu_visible(visible,menu)
    if visible then sync_session(U.controller()) end
    menu_open=visible==true
    if not menu_open then M.close();return true end
    return ui.attach_menu(menu)
end
local function publish(result,now)
    snapshot=result
    local pals,stations,feed_boxes=0,0,0
    for _,camp in ipairs(snapshot.camps) do
        pals=pals+#camp.pals;stations=stations+#camp.producers;feed_boxes=feed_boxes+camp.food_boxes
    end
    local diagnostic=table.concat({#snapshot.camps,pals,stations,feed_boxes,tostring(snapshot.warning)},":")
    if diagnostic~=last_diagnostic then
        last_diagnostic=diagnostic
        U.log(string.format("Base data: %d owned base(s), %d Pals, %d recipe station(s), %d feed box(es). %s",
            #snapshot.camps,pals,stations,feed_boxes,snapshot.warning or "Connected."))
    end
    if M.is_open() then sampling_until=now+600 end
    if priorities.has_work() then priorities.tick(snapshot,now) end
    local found=false
    for _,c in ipairs(snapshot.camps) do
        if c.id==state.base then
            found=true
            break
        end
    end
    if not found then
        state.base=snapshot.camps[1] and snapshot.camps[1].id
        for i,camp in ipairs(snapshot.camps) do
            if camp.here then state.base=camp.id;state.base_page=math.ceil(i/6);break end
        end
    end
    state.base_page=math.min(state.base_page,math.max(1,math.ceil(#snapshot.camps/6)))
    local rendered=true
    if M.is_open() then rendered=render() end
    return rendered
end
function M.tick(recipe_products,recipe_yields,spread)
    products,yields=recipe_products or products,recipe_yields or yields
    local now=os.time()
    local pc=U.controller()
    sync_session(pc)
    if not pc or now-last_sample<5 or (spread and active_sample) then return end
    last_sample=now
    active_sample=nil -- Explicit refreshes supersede any unfinished old pass.
    local started=os.clock()
    local skills=priorities.has_work() or (M.is_open() and state.view=="Priorities")
    local fixed=M.is_open() and state.view=="Pals"
    if not spread then
        local shown=publish(data.sample(products,yields,get_automation,now,skills,nil,fixed),now)
        local elapsed=(os.clock()-started)*1000
        if elapsed>25 then U.log(string.format("Base update took %.1f ms (%d base(s), immediate refresh).",elapsed,#snapshot.camps)) end
        return shown
    end
    local job={cpu=0,peak=0,frames=0,controller=U.address(pc),generation=data.generation}
    active_sample=job
    local advance
    local function resume()
        if active_sample~=job then return end
        if job.controller~=U.address(U.controller()) or job.generation~=data.generation then active_sample=nil;return end
        job.start=os.clock()
        local ok,result=pcall(function()
            advance=advance or data.prepare_sample(products,yields,get_automation,now,skills,fixed)
            repeat
                local sample=advance()
                if sample then return sample end
            until os.clock()-job.start>=0.004
        end)
        if not ok then active_sample=nil;U.log("Base sampling interrupted: "..tostring(result));return end
        local done=result~=nil
        if done then active_sample=nil;publish(result,now) end
        local ms=(os.clock()-job.start)*1000
        job.cpu,job.peak,job.frames=job.cpu+ms,math.max(job.peak,ms),job.frames+1
        if not done then U.defer(1,resume)
        elseif now-last_slow>=60 then
            last_slow=now;U.log(string.format("Periodic base sample: %.1f ms work across %d slices, longest %.1f ms.",job.cpu,job.frames,job.peak))
        end
    end
    resume()
end
function M.handle_click(recipe_products,recipe_yields,direction)
    if not M.is_open() and ui.tab_hovered() then M.toggle(recipe_products,recipe_yields);return true end
    if not M.is_open() then return false end
    local action=ui.action()
    if not action then
        if ui.tab_hovered() then M.close() end
        return true
    end
    if direction==1 and action.kind~="priority" then return true end
    if action.kind=="close" then M.close_menu();return true
    elseif action.kind=="base" then state.base=action.id;state.filters={};state.notice=nil;state.picker=nil;state.plan=nil
    elseif action.kind=="view" then
        state.view=action.view;state.picker=nil;state.plan=nil
        state.notice=nil
        if action.filter then state.filters=state.filters or {};state.filters[state.view]=action.filter end
        if action.mode then state.overview_mode=action.mode end
        if state.view=="Priorities" or state.view=="Pals" then
            last_sample=0
            if M.tick(recipe_products,recipe_yields) then return true end
        end
    elseif action.kind=="filter" then state.filters=state.filters or {};state.filters[state.view]=action.filter;state.notice=nil
    elseif action.kind=="overview_mode" then state.overview_mode=action.mode
    elseif action.kind=="base_page" then state.base_page=U.clamp(state.base_page+action.delta,1,math.max(1,math.ceil(#snapshot.camps/6)))
    elseif action.kind=="meals" and toggle_meals then toggle_meals()
    elseif action.kind=="manage" then priorities.toggle(action.base)
    elseif action.kind=="priority" then priorities.set(action.base,action.pal and action.pal.id,action.work,direction or -1,action.pal)
    elseif action.kind=="reset_pal" then priorities.reset_pal(action.base,action.pal)
    elseif action.kind=="recipes" and recipe_choices then
        local choices,reason=recipe_choices(action.station)
        if choices then
            state.picker={base=state.base,key=action.station.key,name=action.station.station_name,
                location=action.station.location,choices=choices,group=1}
        end
        state.notice=reason
    elseif action.kind=="recipe_group" and state.picker then state.picker.group=action.group
    elseif action.kind=="supplies" and supply_check then
        state.plan,state.notice=supply_check(action.station)
    elseif action.kind=="refresh_plan" and state.plan and supply_check then
        local prior=state.plan
        state.plan=nil;state.notice="Station or recipe changed. Check the current station list."
        for _,camp in ipairs(snapshot.camps) do
            if camp.id==prior.base then
                for _,row in ipairs(camp.producers) do
                    if row.key==prior.key and row.recipe_id==prior.recipe then state.plan,state.notice=supply_check(row);break end
                end
            end
        end
    elseif action.kind=="back_stations" then state.picker=nil;state.plan=nil;state.notice=nil
    elseif action.kind=="choose" and recipe_choices and state.picker then
        local ok,reason
        for _,camp in ipairs(snapshot.camps) do
            if camp.id==state.picker.base then
                for _,row in ipairs(camp.producers) do
                    if row.key==state.picker.key then ok,reason=recipe_choices(row,action.id);break end
                end
            end
        end
        state.picker=nil;state.notice=reason or "Station is no longer available."
    elseif action.kind=="auto" and set_automation then
        local ok,message=set_automation(action.station)
        state.notice=message
        if ok then action.station.auto=not action.station.auto;action.station.status=action.station.auto and "Starting" or (action.station.remaining>0 and "Producing" or "Idle") end
    end
    render()
    if wake then wake() end
    return true
end
function M.before_refill(key,recipe,remaining,yield,now) data.observe_station(key,recipe,remaining,yield,now) end
M.observe_automation=M.before_refill
function M.after_refill(key,recipe,remaining,now) data.refilled(key,recipe,remaining,now) end
return M
