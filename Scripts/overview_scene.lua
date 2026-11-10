-- Layout shared by the native UMG renderer and the offline visual check.
local U = require("ap_util")
local insights=require("base_insights")
local M = {width = 1200, height = 720}
M.colors = {bg="#0C1B22", rail="#10262E", surface="#1C343D", line="#61828B", text="#ECF7FA",
    muted="#B8CDD3", teal="#00BFF3", blue="#52D6F6", green="#69D696", amber="#F0C96B", red="#ED9A93", off="#526A79"}
local truncate=U.truncate_text
local function percent(v) return v and string.format("%.0f%%", U.clamp(v,0,1)*100) or "Unknown" end
local function amount(v)
    if v>=10000 then return string.format("%.0fk",v/1000) end
    if v>=1000 then return string.format("%.1fk",v/1000) end
    if v>0 and v<10 and v~=math.floor(v) then return string.format("%.1f",v) end
    return string.format("%.0f",v)
end
function M.build(snapshot, state, priorities)
    local nodes, C = {}, M.colors
    local parent,shown_count
    local count_label=insights.count
    local function node(kind, id, x,y,w,h, extra)
        local n = {kind=kind,id=id,x=x,y=y,w=w,h=h,parent=parent}
        for k,v in pairs(extra or {}) do n[k]=v end
        nodes[#nodes+1]=n; return n
    end
    local function rect(id,x,y,w,h,color) return node("rect",id,x,y,w,h,{color=color,alpha=(id=="sidebar" or id=="foodsurface") and 0.65 or 1}) end
    local function text(id,value,x,y,w,size,color,h)
        return node("text",id,x,y,w,h or size*1.7,{text=tostring(value),size=size,color=color or C.text})
    end
    local function button(id,value,x,y,w,h,action,selected,tip)
        return node("button",id,x,y,w,h,{text=value,size=w<70 and 12 or 14,color=selected and C.teal or C.surface,
            ink=C.text,action=action,tooltip=tip})
    end
    local function bar(id,x,y,w,h,value,color)
        rect(id.."bg",x,y,w,h,C.line)
        if value then rect(id.."value",x,y,w*U.clamp(value,0,1),h,color) end
    end
    local function list(id,y,height,count,row_height,key)
        node("scroll",id,256,y,920,height,{content_height=math.max(height,count*row_height-4),key=key})
        parent=id
    end
    local function chart(id,points,field,x,y,w,h,color,max_value,now)
        local axis_x=x
        x,w=x+34,w-34
        local peak = max_value or 1
        if not max_value then for _,p in ipairs(points) do peak=math.max(peak,p[field] or 0) end end
        for i=0,2 do
            rect(id.."grid"..i,x,y+h*i/2,w,1,C.line)
            text(id.."axis"..i,amount(peak*(1-i/2)),axis_x,y+h*i/2-7,32,10,C.muted)
        end
        local slots = 60
        local j=0
        for i=1,slots do
            local t = now - (slots-i)*10
            while points[j+1] and points[j+1].at<=t do j=j+1 end
            local found=points[j] and t-points[j].at<=10 and points[j]
            if found and found[field] ~= nil and found[field]>0 then
                local height = math.max(1,(found[field]/peak)*(h-10))
                rect(id.."bar"..i,x+(i-1)*w/slots,y+h-height,w/slots-2,height,color)
            end
        end
        text(id.."left","10 min ago",x,y+h+7,140,11,C.muted)
        text(id.."right","Now",x+w-35,y+h+7,35,11,C.muted)
    end
    rect("background",0,0,1200,720,C.bg)
    rect("sidebar",0,0,224,720,C.rail)
    rect("accent",223,0,1,720,C.line)
    text("brand","Select a base",28,24,180,20)
    text("scope","Your loaded bases",28,71,180,13,C.muted)
    local camps = snapshot.camps or {}
    local selected
    for _,c in ipairs(camps) do if c.id==state.base then selected=c end end
    selected=selected or camps[1]
    local base_page = state.base_page or 1
    for i=(base_page-1)*6+1,math.min(#camps,base_page*6) do
        local c = camps[i]; local y=114+((i-1)%6)*67
        local b=button("base"..i,truncate(c.label,c.here and 16 or 21)..(c.here and " / Here" or ""),20,y,184,55,{kind="base",id=c.id},selected==c,
            c.label.." | "..#c.pals.." Pals | "..c.alerts.." need attention")
        if c.here then b.size=12 end
    end
    if #camps>6 then
        button("bases_prev","<",20,523,46,32,{kind="base_page",delta=-1})
        text("bases_page",base_page.." / "..math.ceil(#camps/6),76,527,78,12,C.muted)
        button("bases_next",">",158,523,46,32,{kind="base_page",delta=1})
    end
    if priorities.afk then
        local meals=priorities.afk
        local b=button("afk_meals",meals.enabled and "Your AFK meals: ON" or "Your AFK meals: OFF",20,574,184,34,{kind="meals"},false,
            "When idle and hungry in your own base, eat from feed boxes if you carry no food. Click to pause/resume for this session.")
        b.size=11;b.ink=meals.enabled and C.green or C.muted
        local occupied=meals.status=="Paused while occupied"
        text("afk_status",truncate(occupied and "Paused while in menu" or meals.status or "Feed boxes only",28),24,614,188,10,C.muted)
        if occupied and meals.field_status then b.tooltip=b.tooltip.." Last field check: "..meals.field_status.."." end
        text("afk_count",(meals.fullness and percent(meals.fullness) or "--").." full   /   "..count_label(meals.meals or 0,"meal"),24,636,188,10,C.muted)
        if meals.last_meal then b.tooltip=b.tooltip.." Last meal: "..meals.last_meal.."." end
    end
    text("sample","Samples every 5 seconds",24,665,192,11,C.muted)
    text("loaded_only","Visit a base to load its data",24,687,192,11,C.muted)
    button("close","Close  [F8]",1050,24,126,36,{kind="close"})
    text("heading",selected and truncate(selected.label,42) or "Base overview",256,25,770,27)
    text("subtitle","Pals, production and the resources that keep them going",256,69,900,14,C.muted)
    if not selected then
        text("empty_title",snapshot.owned and "No loaded bases yet" or "Waiting for your base data",288,234,850,24)
        text("empty_help","Enter your world and visit one of your guild's bases, then open Bases again.",288,286,830,16,C.muted,80)
        text("empty_warn",snapshot.warning or "Only readable data from your own guild is shown.",288,386,830,13,C.amber)
        return nodes
    end
    local c=selected
    local summary=insights.analyze(c)
    local metrics = {{"Assigned Pals",#c.pals..(c.roster_complete and "" or "+"),C.text},
        {"Working",c.working.." / "..#c.pals,C.teal},
        {"Need attention",c.alerts,c.alerts>0 and C.amber or C.text},
        {"Estimated output",c.output_complete and string.format("%.1f / min",c.output) or (summary.queued==0 and "Idle" or "Measuring"),C.blue}}
    for i,m in ipairs(metrics) do
        local x=256+(i-1)*230
        if i>1 then rect("metricline"..i,x-16,112,1,52,C.line) end
        text("metriclabel"..i,m[1],x,104,218,12,C.muted)
        text("metricvalue"..i,m[2],x,126,220,25,m[3])
    end
    for i,v in ipairs({"Overview","Pals","Production","Priorities"}) do
        button("view"..v,v,256+(i-1)*151,183,140,36,{kind="view",view=v},state.view==v)
    end
    rect("divider",256,229,920,1,C.line)
    local view=state.view or "Overview"
    local filter=state.filters and state.filters[view] or "All"
    local function filtered(rows,choices)
        local result={}
        for _,r in ipairs(rows) do if insights.matches(view,filter,r) then result[#result+1]=r end end
        shown_count=#result
        for i,name in ipairs(choices) do
            local b=button("filter"..view..name,name,871+(i-1)*77,185,74,32,{kind="filter",filter=name},filter==name)
            b.size=10
        end
        return result
    end
    if view=="Overview" then
        local f=c.forecast or {state="unavailable",label="Food data unavailable"}
        local learning=f.seconds_left and (string.format("Learning: %d:%02d remaining",math.floor(f.seconds_left/60),f.seconds_left%60)) or nil
        local warn=f.state=="empty" or (f.minutes and f.minutes<60)
        local mode=state.overview_mode or "Status"
        for i,v in ipairs({"Status","Trends","Stores"}) do
            button(v:lower().."_mode",v,871+(i-1)*103,185,99,32,{kind="overview_mode",mode=v},mode==v).size=12
        end
        if mode=="Stores" then
            local stock=c.food_items or {}
            local boxes=c.food_boxes or 0
            text("stores_title","Feed box reserves",256,244,552,20)
            text("stores_scope",c.food_complete and string.format("%d loaded feed %s   /   %s nutrition in stock",boxes,boxes==1 and "box" or "boxes",amount(c.food_stock))
                or (boxes>0 and "Partial reading: totals and projections unavailable" or "No readable feed boxes at this base"),256,282,904,12,C.muted)
            rect("stores_band",256,320,920,81,C.surface)
            local measured=f.added~=nil
            for i,v in ipairs({
                {"Observed gains",measured and "+"..amount(f.added) or "--",C.green},
                {"Observed losses",measured and "-"..amount(f.removed) or "--",C.amber},
                {"If deliveries stop",insights.duration(f.no_delivery_minutes),C.blue}
            }) do
                local x=272+(i-1)*302
                if i>1 then rect("stores_metricline"..i,x-16,335,1,49,C.line) end
                text("stores_metric"..i,v[1],x,329,286,12,C.muted)
                text("stores_value"..i,v[2],x,351,286,21,v[3])
            end
            text("stores_window",measured and string.format("Last %.1f min. Runway uses observed losses only; eating, spoilage and transfers all count.",f.span/60)
                or learning or "Flow estimates need 2 minutes with the same feed boxes loaded.",256,414,914,11,C.muted)
            for i,v in ipairs({{"Food",270},{"Quantity",646},{"Nutrition",798},{"Share of reserve",950}}) do
                text("stores_col"..i,v[1],v[2],460,190,11,C.muted)
            end
            list("food_list",488,156,#stock,43,c.id)
            for i,v in ipairs(stock) do
                local y=488+(i-1)*43
                rect("stockrow"..i,256,y,902,39,i%2==0 and C.rail or C.bg)
                text("stock_name"..i,truncate(v.name,35),270,y+6,352,13).tooltip=v.name
                text("stock_count"..i,v.count,646,y+6,132,13)
                text("stock_nutrition"..i,amount(v.nutrition),798,y+6,140,13,C.blue)
                local share=c.food_complete and c.food_stock>0 and v.nutrition/c.food_stock or nil
                bar("stock_share"..i,950,y+18,122,5,share,C.teal)
                text("stock_percent"..i,share and percent(share) or "--",1085,y+8,68,11,C.muted)
            end
            parent=nil
            if #stock==0 then text("stores_empty",c.food_complete and "No edible items in these feed boxes." or "Visit the base to read its food supplies.",270,510,860,15,C.muted) end
            text("stores_foot",#stock.." food "..(#stock==1 and "type" or "types").."  /  "..(#stock>3 and "Scroll to browse" or "Feed boxes only"),256,653,900,11,C.muted)
        elseif mode=="Trends" then
            text("output_title","Production pace",256,246,440,18)
            text("output_hint","Estimated items / minute",256,276,440,12,C.muted)
            chart("output",c.history or {},"output",256,309,438,112,C.blue,nil,snapshot.at)
            text("work_title","Base activity",734,246,440,18)
            text("work_hint","Pals reporting work",734,276,440,12,C.muted)
            chart("working",c.history or {},"working",734,309,438,112,C.teal,math.max(1,#c.pals),snapshot.at)
            rect("foodsurface",256,470,920,203,C.surface)
            text("foodtitle","Food reserve",272,482,286,16)
            text("runway",f.label,272,517,280,17,warn and C.amber or C.teal,32)
            text("foodamount",c.food_complete and amount(c.food_stock).." nutrition available" or "Feed boxes unreadable",272,551,282,12,C.muted)
            text("foodtrend",f.net and string.format("Net %+.1f nutrition / min",f.net) or learning or "No trend available",272,577,282,11,C.muted)
            text("foodconfidence",f.confidence or (f.state=="empty" and "Restock the feed boxes" or "Continuous samples needed"),272,602,282,11,C.muted)
            text("foodhistory_title","Measured stock",570,484,270,12,C.blue)
            text("foodfuture_title","Projected stock",884,484,278,12,C.amber)
            chart("foodhistory",c.history or {},"food",570,522,280,102,C.blue,nil,snapshot.at)
            if f.projected then
                local peak=math.max(1,c.food_stock,f.projected[#f.projected])
                text("projection_peak",amount(peak),884,514,48,10,C.muted)
                rect("projection_axis",925,624,235,1,C.line)
                for i,value in ipairs(f.projected) do
                    if value>0 then
                        local h=math.max(1,value/peak*94)
                        local n=rect("projection"..i,925+(i-1)*18,624-h,12,h,C.amber);n.alpha=0.55
                    end
                end
                text("projected_now","Now",925,631,60,10,C.muted)
                text("projected_hour","+60 min",1104,631,64,10,C.muted)
            else
                text("foodlearning",f.state=="variable" and "Restocks or swings make\nthis forecast unreliable."
                    or f.state=="empty" and "Feed boxes are empty.\nRestock to rebuild reserves."
                    or f.state=="unavailable" and "Visit a base with readable\nfeed boxes to collect data."
                    or "Forecast appears after\n2 minutes of steady data.",884,552,278,12,C.muted,64)
            end
            text("foodassumption","Projection assumes the recent net trend continues; future meals and supplies are not guaranteed.",272,653,882,10,C.muted)
        else
            local a=summary.alert
            rect("attention_surface",256,243,920,48,C.surface)
            rect("attention_accent",256,243,3,48,a.urgent and C.amber or C.teal)
            text("attention_title",a.title,270,247,720,13,a.urgent and C.amber or C.text,23)
            text("attention_detail",a.detail,270,271,720,10,C.muted,18)
            button("attention_action","Review",1034,251,126,32,{kind="view",view=a.view,mode=a.mode,filter=a.filter or "All"},false).color=C.rail
            text("foodtitle","Food reserves",256,306,540,18)
            text("runway",f.label,256,338,540,24,warn and C.amber or C.teal)
            text("foodamount",c.food_complete and amount(c.food_stock).." nutrition / "..count_label(c.food_boxes,"feed box","feed boxes")
                or "Feed boxes are not readable yet",256,379,540,12,C.muted)
            text("foodtrend",f.net and string.format("Net %+.1f nutrition/min over %.1f min",f.net,(f.span or 0)/60)
                or learning or "Forecast needs readable feed boxes",256,404,540,11,C.muted)
            for i,minutes in ipairs({15,30,60}) do
                local x=256+(i-1)*182
                local stock=f.projected and f.projected[minutes/5+1]
                text("horizon_label"..i,"In "..minutes.." min",x,440,172,11,C.muted)
                text("horizon_value"..i,stock and amount(stock) or "--",x,461,172,20,stock and stock<=0 and C.amber or C.blue)
            end
            text("foodassumption","Nutrition at the recent net trend; eating, spoilage and transfers included.",256,499,550,10,C.muted)
            rect("wellbeing_divider",812,308,1,206,C.line)
            text("wellbeing_title","Pal wellbeing",832,306,344,18)
            for i,item in ipairs({{"Average sanity",summary.sanity,summary.sanity_n},{"Average fullness",summary.fullness,summary.food_n}}) do
                local y=344+(i-1)*60
                text("care_label"..i,item[1],832,y,224,12,C.muted)
                text("care_value"..i,percent(item[2]),1050,y,126,14,item[2] and item[2]<0.4 and C.amber or C.text)
                bar("care_bar"..i,832,y+30,326,5,item[2],i==1 and C.teal or C.blue)
                if item[3]<summary.pals then text("care_coverage"..i,item[3].." / "..summary.pals.." readable",832,y+37,326,9,C.muted) end
            end
            text("care_counts",summary.hungry.." hungry / "..summary.low_sanity.." low sanity",832,468,344,12,(summary.hungry+summary.low_sanity)>0 and C.amber or C.muted)
            text("care_sick",summary.sick.." sick / "..summary.low_hp.." low HP / "..summary.down.." down",832,493,344,12,(summary.sick+summary.down+summary.low_hp)>0 and C.amber or C.muted)
            rect("status_bottom_line",256,530,920,1,C.line)
            text("production_summary_title","Production at a glance",256,545,540,16)
            for i,item in ipairs({{"Queued",summary.queued},{"Auto ON",summary.auto},{"Waiting",summary.waiting}}) do
                local x=256+(i-1)*182
                text("station_metric_label"..i,item[1],x,578,170,11,C.muted)
                text("station_metric_value"..i,item[2],x,599,170,22,i==3 and item[2]>0 and C.amber or C.blue)
            end
            text("station_totals",summary.crafts.." crafts queued / "..summary.stations.." loaded stations",256,638,540,11,C.muted)
            text("station_stalled",summary.no_output>0 and count_label(summary.no_output,"queued station").." with no output in the last minute" or
                (summary.queued>0 and "No stalled batches detected" or "No batches in progress"),256,660,550,10,summary.no_output>0 and C.amber or C.muted)
            text("workmix_title","Top jobs now",832,545,344,16)
            for i=1,3 do
                local job=summary.jobs[i]
                if job then
                    local y=579+(i-1)*25
                    text("job_name"..i,U.work[job.work],832,y,150,11,C.muted)
                    bar("job_bar"..i,982,y+6,142,5,job.count/math.max(1,summary.pals),C.teal)
                    text("job_count"..i,job.count,1135,y,40,11)
                end
            end
            local idle=summary.idle_pals.." resting / idle"
            if summary.sleeping>0 then idle=idle.." ("..summary.sleeping.." asleep)" end
            if summary.unknown_work>0 then idle=idle.."; "..summary.unknown_work.." unreported" end
            text("workmix_idle",idle,832,660,344,10,C.muted)
        end
    elseif view=="Pals" then
        local pals=filtered(c.pals,{"All","Working","Resting","Care"})
        text("pals_hint",#c.pals.." assigned / "..c.working.." working / "..c.alerts.." need attention",256,246,916,13,C.muted)
        for i,h in ipairs({{"Pal / current activity",268},{"Health",595},{"Sanity",731},{"Fullness",867},{"Condition",1002}}) do
            text("palhead"..i,h[1],h[2],282,math.min(360,1160-h[2]),11,C.muted)
        end
        list("pal_list",310,344,#pals,64,c.id..":"..filter)
        for index,p in ipairs(pals) do
            local y=310+(index-1)*64
            rect("palrow"..index,256,y,902,60,index%2==0 and C.rail or C.bg)
            if p.alert then rect("palalert"..index,256,y,3,60,C.amber) end
            text("palname"..index,truncate(p.name,27),270,y+5,312,15).tooltip=p.name
            text("palwork"..index,p.sleeping and "Sleeping" or (p.work==nil and "Activity not reported" or (U.work[p.work] or "Resting / idle")),270,y+34,310,11,p.working and C.teal or C.muted)
            text("palhp"..index,percent(p.health),595,y+9,125,13)
            bar("palhpbar"..index,595,y+40,112,5,p.health,p.low_hp and C.amber or C.green)
            text("palsan"..index,percent(p.sanity),731,y+9,125,13)
            bar("palsanbar"..index,731,y+40,112,5,p.sanity,p.sanity and p.sanity<0.4 and C.amber or C.teal)
            text("palfood"..index,percent(p.food),867,y+9,125,13)
            bar("palfoodbar"..index,867,y+40,112,5,p.food,p.hungry and C.amber or C.blue)
            text("palstatus"..index,p.alert or (insights.care_readable(p) and "In good condition" or "Not reported"),1002,y+9,150,10,p.alert and C.amber or C.muted)
            text("palassignment"..index,p.fixed and "Fixed assignment" or "",1002,y+34,150,10,C.muted)
        end
        parent=nil
        if #pals==0 then
            local empty=#c.pals==0 and (c.roster_complete and "Assign Pals at your Palbox to see them here." or "Pal roster unavailable on this sample.")
                or (filter=="Care" and "No Pal is reporting a care warning." or "No Pals match this activity.")
            text("nopals",empty,270,340,850,17,C.muted)
        end
    elseif view=="Production" and state.plan and state.plan.base==c.id then
        local p=state.plan
        text("plan_title",truncate(p.product.." supplies",41),256,242,650,21)
        text("plan_station",p.station.."  /  Checked "..os.date("%H:%M:%S",p.at),256,280,650,12,C.muted)
        button("plan_refresh","Refresh",864,245,116,34,{kind="refresh_plan"}).size=12
        button("plan_back","Back to stations",990,245,186,34,{kind="back_stations"}).size=12
        rect("plan_band",256,317,920,77,C.surface)
        for i,v in ipairs({{"Craftable now",p.craftable and count_label(p.craftable,"craft") or "--"},
            {"Auto batch",count_label(p.batch,"craft")},{"Ingredients last",p.coverage==0 and "Out of inputs"
                or (p.minutes and insights.duration(p.minutes)) or (p.coverage and "No rate yet" or "Unknown")}}) do
            local x=272+(i-1)*305
            text("plan_stat_label"..i,v[1],x,325,288,12,C.muted)
            text("plan_stat_value"..i,v[2],x,348,288,20,i==3 and (p.coverage==0 and C.amber or C.blue) or C.text)
        end
        for i,v in ipairs({{"Ingredient",270,230},{"Per craft",520,95},{"Base",630,76},{"Carried",716,88},{"Crafts covered",822,155},{"For full batch",1000,154}}) do
            text("plan_col"..i,v[1],v[2],418,v[3],11,C.muted)
        end
        list("plan_list",447,180,#p.materials,36,p.key)
        for i,m in ipairs(p.materials) do
            local y=447+(i-1)*36
            rect("mat_row"..i,256,y,902,32,i%2==0 and C.rail or C.bg)
            text("mat_name"..i,truncate(m.name,24),270,y+4,239,12).tooltip=m.name
            text("mat_cost"..i,m.cost,520,y+4,100,12)
            text("mat_base"..i,m.base or "--",630,y+4,78,12)
            text("mat_bag"..i,m.bag or "--",716,y+4,95,12)
            text("mat_coverage"..i,(m.crafts or "--")..(m.limiting and " / limiting" or ""),822,y+4,170,12,m.limiting and C.amber or C.muted)
            text("mat_short"..i,m.batch_short==0 and "Ready" or (m.batch_short and "Need "..m.batch_short or "--"),
                1000,y+4,150,12,m.batch_short==0 and C.green or (m.batch_short and C.amber or C.muted))
        end
        parent=nil
        if #p.materials==0 then text("plan_empty","No ingredient breakdown available.",270,471,844,14,C.muted) end
        text("plan_assumption","Input runway uses the recent output rate and current materials. Assumes no deliveries or competing use.",256,647,918,11,C.muted)
        text("plan_scope","Already queued crafts are excluded. Refresh to read current stock; checking never starts production.",256,673,918,10,C.muted)
    elseif view=="Production" and state.picker and state.picker.base==c.id then
        local picker=state.picker
        text("picker_name",picker.name,256,241,650,21)
        text("picker_location",picker.location,256,280,650,12,C.muted)
        button("back_stations","Back to stations",990,245,186,34,{kind="back_stations"},false).size=12
        text("picker_hint","Choose a recipe. Nothing is queued until you enable Auto Produce.",256,312,916,13,C.muted)
        local groups={"A - E","F - J","K - O","P - T","U - Z","Other"}
        local buckets={}
        for _,r in ipairs(picker.choices) do
            local ch=r.label:upper():byte(1) or 0
            local group=ch>=65 and ch<=90 and math.min(5,math.floor((ch-65)/5)+1) or 6
            buckets[group]=buckets[group] or {};table.insert(buckets[group],r)
        end
        local selected=buckets[picker.group] and picker.group or nil
        local recipes=picker.choices
        local top=368
        if #recipes>30 then
            local pos=0
            for i,label in ipairs(groups) do
                if buckets[i] then
                    selected=selected or i
                    button("recipe_group"..i,label.."  ("..#buckets[i]..")",256+pos*133,352,128,30,{kind="recipe_group",group=i},selected==i).size=11
                    pos=pos+1
                end
            end
            recipes=buckets[selected];top=400
        end
        list("recipe_list",top,650-top,math.ceil(#recipes/2),40,picker.key..":"..tostring(selected))
        for i,r in ipairs(recipes) do
            local label=r.label..(r.yield_count>1 and "  x"..r.yield_count or "")
            local b=button("choose_recipe"..i,truncate(label,42),256+((i-1)%2)*452,top+math.floor((i-1)/2)*40,446,36,
                {kind="choose",id=r.id},false,label)
            b.size=12
        end
        parent=nil
        text("picker_count",count_label(#picker.choices,"unlocked recipe").." at this station",256,661,890,11,C.muted)
    elseif view=="Production" then
        local stations=filtered(c.producers,{"All","Queued","Auto","Waiting"})
        text("prod_hint",#c.producers.." stations / "..summary.queued.." queued / "..summary.auto.." Auto ON / "..summary.waiting.." blocked",256,246,920,13,C.muted)
        for i,h in ipairs({{"Station / location",268},{"Recipe / status",560},{"Queue",800},{"Items / min",890},{"Auto Produce",1028}}) do
            text("prodhead"..i,h[1],h[2],283,math.min(190,1176-h[2]),11,C.muted)
        end
        list("production_list",310,344,#stations,68,c.id..":"..filter)
        for index,p in ipairs(stations) do
            local y=310+(index-1)*68
            rect("prodrow"..index,256,y,902,64,index%2==0 and C.rail or C.bg)
            if p.last_opened then rect("prodaccent"..index,256,y,3,64,C.teal) end
            local station=text("prodstation"..index,truncate(p.station_name or "Workstation",29),270,y+6,260,12,p.last_opened and C.teal or C.text,24)
            station.tooltip=(p.station_name or "Workstation").." | "..(p.location or "Location unavailable")..(p.last_opened and " | Last opened" or "")
            text("prodlocation"..index,truncate(p.location or "Location unavailable",35),270,y+37,260,10,C.muted,19)
            local change=c.here and not p.auto and p.remaining==0 and p.recipe_id~=""
            local product=text("prodname"..index,truncate(p.product,change and 19 or 24),560,y+6,change and 156 or 226,13,p.recipe_id=="" and C.muted or C.text)
            product.tooltip=p.product
            if change then button("change_recipe"..index,"Change",720,y+4,68,27,{kind="recipes",station=p}).size=10 end
            text("prodqueue"..index,p.remaining<0 and "--" or string.format("%d",p.remaining),800,y+6,78,15)
            local eta=text("prodeta"..index,insights.duration(insights.queue_minutes(p)),800,y+37,78,9,C.muted,17)
            eta.tooltip="Estimated time for the current batch at its observed output rate. Refills are excluded."
            text("prodrate"..index,p.recipe_id=="" and "--" or (p.rate and string.format("%.1f",p.rate) or (p.remaining>0 and "Learning" or "--")),890,y+17,122,14,C.blue)
            local inspect=c.here and p.recipe_id~=""
            local stat=text("prodstatus"..index,truncate(p.status or "Idle",inspect and 22 or 28),560,y+37,inspect and 154 or 226,10,insights.blocked(p) and C.amber or C.muted)
            stat.tooltip=p.status
            if inspect then button("supplies"..index,"Supplies",720,y+33,68,26,{kind="supplies",station=p}).size=10 end
            if p.recipe_id~="" and (p.auto or c.here) then
                local b=button("auto"..index,p.auto and "ON / Pause" or "OFF / Enable",1028,y+15,118,34,{kind="auto",station=p},false)
                b.size=11;b.ink=p.auto and C.green or C.muted
            elseif c.here and p.remaining==0 then
                button("choose_station"..index,"Choose recipe",1028,y+15,118,34,{kind="recipes",station=p}).size=11
            else text("prodemptynote"..index,"Visit station",1028,y+23,122,10,C.muted) end
        end
        parent=nil
        if #stations==0 then text("nostations",#c.producers==0 and "No recipe workstations are loaded in this base."
            or ({Queued="No stations have a batch queued.",Auto="Auto Produce is off at every loaded station.",Waiting="No automatic stations are reporting a blocked batch."})[filter],270,340,850,17,C.muted) end
    elseif view=="Priorities" then
        local base=priorities.bases[c.id] or {enabled=false,defaults={},pals={},original={}}
        button("manage",base.enabled and "Disable management" or "Enable management",934,243,242,36,{kind="manage",base=c.id},base.enabled)
        text("priority_legend","1 highest   5 lowest   Off disabled   * Pal override",256,246,670,13,C.muted)
        text("priority_help","Left click raises priority; right click lowers it. Hover for skill rank.",256,273,916,12,C.muted)
        text("priority_status",truncate(priorities.status or "",123),256,300,916,12,priorities.ready and C.green or C.amber)
        local x0,step=490,46
        for work=1,13 do text("workhead"..work,U.short_work[work],x0+(work-1)*step,335,48,10,C.muted) end
        text("default_label","Base defaults",266,368,214,14)
        for work=1,13 do
            local v=base.defaults[work] or 3
            button("default"..work,v==0 and "Off" or tostring(v),x0+(work-1)*step,360,42,32,
                {kind="priority",base=c.id,work=work},v==1,U.work[work].." default priority")
        end
        list("priority_list",403,251,#c.pals,42,c.id)
        for index,p in ipairs(c.pals) do
            local y=403+(index-1)*42
            rect("priorityrow"..index,256,y,902,39,index%2==0 and C.rail or C.bg)
            text("prioritypal"..index,truncate(p.name,25),266,y+5,216,13,p.fixed and C.muted or C.text)
            for work=1,13 do
                if p.id and p.skills[work] then
                    local original=base.original[p.id] or p.allowed
                    local value=require("priority_policy").get(base,p.id,work,original[work])
                    local override=base.pals[p.id] and base.pals[p.id][work]~=nil
                    local b=button("cell"..index.."_"..work,(value==0 and "Off" or tostring(value))..(override and "*" or ""),x0+(work-1)*step,y,42,31,
                        {kind="priority",base=c.id,pal=p,work=work},value==1,U.work[work].." | Skill rank "..p.skills[work]..
                        (p.permissions_read and (p.allowed[work] and " | Game: allowed" or " | Game: blocked") or "")..(p.fixed and " | Fixed assignment retained" or ""))
                    if value==0 then b.ink=C.red;b.size=10 elseif value>=4 then b.ink=C.muted end
                else text("unsupported"..index.."_"..work,"-",x0+(work-1)*step+15,y+5,35,13,C.off) end
            end
            if p.id then button("reset"..index,"Reset",1098,y,60,31,{kind="reset_pal",base=c.id,pal=p.id},false,"Use base defaults for this Pal") end
        end
        parent=nil
    end
    local count=view=="Production" and #c.producers or #c.pals
    if view~="Overview" and not (view=="Production" and ((state.picker and state.picker.base==c.id) or (state.plan and state.plan.base==c.id))) then
        text("listinfo",(shown_count and filter~="All" and (shown_count.." of ") or "")..count_label(count,view=="Production" and "station" or "Pal").." in this base",256,661,430,11,C.muted)
        local overflow=(shown_count or count)*(view=="Pals" and 64 or view=="Production" and 68 or 42)-4>(view=="Priorities" and 251 or 344)
        text("scrollhint",overflow and "Scroll to browse" or "All entries shown",1000,661,176,11,C.muted)
    end
    text("footer",state.notice or "Session history, loaded bases only. Output estimates can include queue edits. Food forecasts assume the recent trend continues.",256,691,920,10,C.muted)
    return nodes
end
return M
