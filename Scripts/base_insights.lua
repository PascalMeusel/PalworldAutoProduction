-- Derived from the existing five-second snapshot; no additional game scans.
local U=require("ap_util")
local M={}
function M.count(n,one,many) return n.." "..(n==1 and one or (many or one.."s")) end
local blocked={["Waiting for resources"]=true,["Waiting for power"]=true,["Power unit unavailable"]=true,
    ["Start request failed"]=true,["Recipe not selected"]=true,["Station unavailable"]=true,["No queue confirmation"]=true,
    ["Waiting for station"]=true,["Queue unavailable"]=true,["Start blocked by game"]=true}
function M.blocked(row) return row.auto==true and blocked[row.status]==true end
function M.care_readable(p)
    return p.health~=nil and p.food~=nil and p.sanity~=nil and p.dead~=nil and p.sick~=nil
end
function M.matches(view,filter,row)
    if not filter or filter=="All" then return true end
    if view=="Pals" then
        if filter=="Working" then return row.working==true end
        if filter=="Resting" then return row.work==0 end
        if filter=="Care" then return row.alert~=nil end
    elseif view=="Production" then
        if filter=="Queued" then return (row.remaining or 0)>0 end
        if filter=="Auto" then return row.auto==true end
        if filter=="Waiting" then return M.blocked(row) end
    end
    return false
end
function M.duration(minutes)
    if not minutes then return "--" end
    if minutes<1 then return "<1 min" end
    if minutes<60 then return "~"..math.ceil(minutes).." min" end
    return string.format("~%.1f hr",minutes/60)
end
function M.queue_minutes(station)
    if not station.rate or station.rate<=0 or (station.remaining or 0)<=0 then return nil end
    return station.remaining*(station.yield_count or 1)/station.rate
end
function M.supply_outlook(plan)
    local lowest,complete=nil,#plan.materials>0
    for _,m in ipairs(plan.materials) do
        if m.base and m.bag and m.cost>0 then
            m.crafts=math.floor((m.base+m.bag)/m.cost)
            if plan.batch then m.batch_short=math.max(0,m.cost*plan.batch-m.base-m.bag) end
            lowest=math.min(lowest or m.crafts,m.crafts)
        else complete=false end
    end
    if complete then
        plan.coverage=lowest
        for _,m in ipairs(plan.materials) do m.limiting=m.crafts==lowest end
        if plan.rate and plan.rate>0 then plan.minutes=lowest*(plan.yield_count or 1)/plan.rate end
    end
    return plan
end
function M.analyze(camp)
    local s={pals=#(camp.pals or {}),hungry=0,starving=0,low_hp=0,sleeping=0,low_sanity=0,sick=0,down=0,care_unknown=0,
        sanity_sum=0,sanity_n=0,food_sum=0,food_n=0,work={},idle_pals=0,unknown_work=0,
        stations=#(camp.producers or {}),queued=0,auto=0,waiting=0,no_output=0,idle_stations=0,crafts=0}
    for _,p in ipairs(camp.pals or {}) do
        if p.sanity~=nil then s.sanity_sum=s.sanity_sum+U.clamp(p.sanity,0,1);s.sanity_n=s.sanity_n+1 end
        if p.food~=nil then s.food_sum=s.food_sum+U.clamp(p.food,0,1);s.food_n=s.food_n+1 end
        if p.hungry or (p.hungry==nil and p.food and p.food<0.25) then s.hungry=s.hungry+1 end
        if p.starving then s.starving=s.starving+1 end
        if p.low_hp then s.low_hp=s.low_hp+1 end
        if p.sleeping then s.sleeping=s.sleeping+1 end
        if p.sanity and p.sanity<0.4 then s.low_sanity=s.low_sanity+1 end
        if p.sick and p.sick>0 then s.sick=s.sick+1 end
        if p.dead then s.down=s.down+1 end
        if not M.care_readable(p) then s.care_unknown=s.care_unknown+1 end
        if U.work[p.work] then s.work[p.work]=(s.work[p.work] or 0)+1
        elseif p.work==0 then s.idle_pals=s.idle_pals+1 else s.unknown_work=s.unknown_work+1 end
    end
    s.sanity=s.sanity_n>0 and s.sanity_sum/s.sanity_n or nil
    s.fullness=s.food_n>0 and s.food_sum/s.food_n or nil
    s.jobs={}
    for work,count in pairs(s.work) do s.jobs[#s.jobs+1]={work=work,count=count} end
    table.sort(s.jobs,function(a,b) return a.count==b.count and a.work<b.work or a.count>b.count end)
    for _,p in ipairs(camp.producers or {}) do
        if p.auto then s.auto=s.auto+1 end
        if (p.remaining or 0)>0 then s.queued=s.queued+1;s.crafts=s.crafts+p.remaining
        else s.idle_stations=s.idle_stations+1 end
        if M.blocked(p) then s.waiting=s.waiting+1 end
        if (p.remaining or 0)>0 and p.rate==0 and (p.warmup or 0)>=60 then s.no_output=s.no_output+1 end
    end
    local f=camp.forecast or {state="unavailable"}
    local function alert(title,detail,view,urgent,mode,filter)
        s.alert={title=title,detail=detail,view=view,urgent=urgent,mode=mode,filter=filter}
    end
    if f.state=="empty" then alert("Feed boxes are empty","Put food in a loaded feed box so Pals can eat.","Overview",true,"Stores")
    elseif s.down>0 then alert(M.count(s.down,"Pal").." incapacitated","Review affected Pals before relying on their work.","Pals",true,nil,"Care")
    elseif s.starving>0 then alert(M.count(s.starving,"Pal").." starving","Check the affected Pals and whether they can reach a stocked feed box.","Pals",true,nil,"Care")
    elseif s.low_hp>0 then alert(M.count(s.low_hp,"Pal").." below 35% health","Open the care list to see who needs recovery.","Pals",true,nil,"Care")
    elseif s.hungry>0 then alert(M.count(s.hungry,"Pal").." hungry","Check food availability and access to feed boxes.","Pals",true,nil,"Care")
    elseif f.state=="declining" and f.minutes and f.minutes<60 then
        alert("Food reserve: "..M.duration(f.minutes),"See which foods remain and how much has left the feed boxes.","Overview",true,"Stores")
    elseif s.sick>0 or s.low_sanity>0 then
        alert(s.sick.." sick / "..s.low_sanity.." with low sanity","Review care, rest and workload before increasing production.","Pals",true,nil,"Care")
    elseif s.waiting>0 then alert(M.count(s.waiting,"automatic station").." waiting to start","Review the station status for missing materials, power or queue confirmation.","Production",true,nil,"Waiting")
    elseif s.no_output>0 then alert(M.count(s.no_output,"queued station").." with no observed output","No queue decrease in the last minute. Check workers and power.","Production",true,nil,"Queued")
    elseif not camp.roster_complete or s.care_unknown>0 then alert("Some Pal readings are unavailable","Averages include readable Pals only; missing values are not zero.","Pals",false)
    elseif f.state=="unavailable" then alert("Food reserve is unknown","Visit this base to load its feed boxes.","Overview",false,"Stores")
    else alert("No immediate care or production warnings","Review food trends before leaving this base unattended.","Overview",false,"Trends") end
    return s
end
return M
