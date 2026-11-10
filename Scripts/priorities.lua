local U = require("ap_util")
local policy = require("priority_policy")
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = source:match("^(.*[/\\])") or "./"
local store = require("priority_store").new(directory .. "priorities.tsv")
local M = {store = store, status = "Set base defaults below, or adjust an individual Pal", messages={}, demand = {}, hook_ready = false}
local function say(id,text,ready)
    M.messages[id]={text=text,ready=ready};M.status=text
end
local wake, last_tick = nil, 0
local management_enabled=false
for _,base in pairs(store.bases) do if base.enabled then management_enabled=true;break end end
local definitions, manager_identity, definition_retry = {}, nil, 0
-- EPalWorkType is a different enum from EPalWorkSuitability. Never cast between them.
local work_types = {[3]=5,[4]=5,[5]=6,[7]=12,[8]=3,[9]=2,[10]=1,[11]=12,[13]=5,
    [14]=1,[15]=10,[16]=12,[17]=6,[18]=7,[19]=8,[20]=7,[21]=8,[22]=4,[23]=1,
    [26]=13,[27]=2,[28]=11,[29]=2}
local function suitability(work)
    local utility=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    local manager=U.valid(utility) and U.read(function() return utility:GetWorkProgressManager(work) end)
    local identity=U.address(manager)
    if identity and (manager_identity~=identity or (next(definitions)==nil and os.time()>=definition_retry)) then
        definitions={};manager_identity=identity
        definition_retry=os.time()+30
        pcall(function()
            local function add(key,value)
                local d=U.unwrap(value)
                local s=U.number(U.read(function() return d.WorkSuitability end))
                if s and s>=1 and s<=13 then definitions[U.name(key)]=s end
            end
            local map=manager.WorkAssignDefineMap
            if type(map)=="table" then for key,value in pairs(map) do add(key,value) end
            else map:ForEach(add) end
        end)
    end
    local id=U.name(U.read(function() return work.AssignDefineDataId end))
    return definitions[id] or work_types[U.number(U.read(function() return work.OverrideWorkType end))]
end
local function conflict()
    local mods = directory .. "../../mods.txt"
    local f = io.open(mods, "r")
    if f then
        local text = f:read("*a"); f:close()
        for line in text:gmatch("[^\r\n]+") do
            local enabled = line:match("^%s*PalWorkPriority%s*:%s*([01])")
            if enabled then return enabled == "1" end
        end
    end
    local other = io.open(directory .. "../../PalWorkPriority/enabled.txt", "r")
    if other then other:close(); return true end
    return false
end
function M.available()
    if store.load_error then return false, "Priority settings could not be read; restore priorities.tsv from its backup." end
    if conflict() then return false, "Disable Pal Work Priority and restart to use built-in priorities." end
    local pc = U.controller()
    if not pc then return false, "Waiting for the local player" end
    local gameplay = U.read(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
    local mode = U.valid(gameplay) and U.read(function() return gameplay:GetGameMode(pc) end) or nil
    if not U.live(mode) then return false, "Priority scheduling requires the world host (single-player or co-op host)." end
    local tx = U.read(function() return pc.Transmitter end)
    local component = U.valid(tx) and U.read(function() return tx:GetBaseCamp() end) or nil
    if not U.valid(component) then return false, "Waiting for the base management connection" end
    if not M.hook_ready then return false, "Work-demand hook unavailable on this game build." end
    return true, component
end
function M.init(on_wake)
    wake = on_wake
    local ok, err = pcall(function()
        RegisterHook("/Script/Pal.PalBaseCampWorkerDirector:OnRequiredAssignWork_ServerInternal", function(_, remote_work)
            if not management_enabled then return end
            local work = U.unwrap(remote_work)
            if not U.live(work) then return end
            local base = U.guid(U.read(function() return work.BaseCampIdBelongTo end))
            if not base or not store.bases[base] or not store.bases[base].enabled then return end
            local key = U.guid(U.read(function() return work:GetWorkId() end))
            local suit = suitability(work)
            if key and suit then
                M.demand[base] = M.demand[base] or {}
                M.demand[base][key] = {suit = suit, at = os.time(), object = work}
                if wake then wake() end
            end
        end)
    end)
    M.hook_ready = ok
    if not ok then U.log("Built-in priority demand hook unavailable: " .. tostring(err)) end
end
function M.has_work()
    for _, base in pairs(store.bases) do
        if base.enabled or next(base.original) ~= nil then return true end
    end
    return false
end
function M.get(base_id, pal, work)
    local base = store:base(base_id)
    local original = base.original[pal.id] or pal.allowed
    return policy.get(base, pal.id, work, original[work])
end
function M.set(base_id, pal_id, work, direction, pal)
    if not M.available() then return false end
    local base = store:base(base_id)
    local target = base.defaults
    if pal_id then base.pals[pal_id] = base.pals[pal_id] or {}; target = base.pals[pal_id] end
    local previous = target[work]
    local value = pal and M.get(base_id, pal, work) or previous or 3
    target[work] = policy.cycle(value, direction)
    if not store:save() then target[work] = previous; say(base_id,"Could not save priorities: " .. tostring(store.error)); return false end
    last_tick = 0
    say(base_id,base.enabled and "Priority saved; applies on the next work pass" or "Priority saved; enable management to apply it",true)
    if wake then wake() end
    return true
end
function M.toggle(base_id)
    local ok, reason = M.available()
    if not ok then say(base_id,reason); return false end
    local base = store:base(base_id)
    base.enabled = not base.enabled
    if not store:save() then base.enabled = not base.enabled; say(base_id,"Could not save settings: " .. tostring(store.error)); return false end
    management_enabled=false
    for _,entry in pairs(store.bases) do if entry.enabled then management_enabled=true;break end end
    say(base_id,base.enabled and "Built-in priorities enabled" or (next(base.original) and "Restoring the original work permissions" or "Management off; no work permissions to restore"),true)
    last_tick = 0
    if wake then wake() end
    return true
end
function M.reset_pal(base_id, pal_id)
    if not M.available() then return false end
    local base = store:base(base_id)
    local old = base.pals[pal_id]; base.pals[pal_id] = nil
    if not store:save() then base.pals[pal_id] = old; say(base_id,"Could not save Pal settings");return false end
    last_tick = 0
    say(base_id,"Pal priorities reset to this base's defaults",true)
    if wake then wake() end
    return true
end
function M.tick(snapshot, now)
    if now - last_tick < 5 then return end
    last_tick = now
    local ok, component = M.available()
    if not ok then M.status = component; return end
    local staged={}
    local function stage(original,pal_id,value)
        staged[#staged+1]={original,pal_id,original[pal_id]}
        original[pal_id]=value
    end
    -- A moved Pal retains its identity. Carry the original permissions to its new base
    -- so temporary restrictions are never mistaken for a new vanilla baseline.
    for _,camp in ipairs(snapshot.camps) do
        for _,pal in ipairs(camp.pals) do
            if pal.id then
                for old_id,old in pairs(store.bases) do
                    if old_id~=camp.id and old.original[pal.id] then
                        stage(store:base(camp.id).original,pal.id,old.original[pal.id])
                        stage(old.original,pal.id,nil)
                    end
                end
                local base=store.bases[camp.id]
                if base and base.enabled and pal.raw_id and pal.permissions_read and pal.fixed==false and pal.dead==false and not base.original[pal.id] then
                    local original={}
                    for work in pairs(pal.skills) do original[work]=pal.allowed[work] end
                    if next(original) then stage(base.original,pal.id,original) end
                end
            end
        end
    end
    -- One durable snapshot per pass, before sending any permission requests.
    if #staged>0 and not store:save() then
        for i=#staged,1,-1 do local s=staged[i];s[1][s[2]]=s[3] end
        for _,c in ipairs(snapshot.camps) do say(c.id,"Could not save recovery data; no work permissions changed") end
        return
    end
    local cleared={}
    for _, camp in ipairs(snapshot.camps) do
        local base = store.bases[camp.id]
        if base and (base.enabled or next(base.original)) then
            local failures,changes,managed,fixed=0,0,0,0
            local pending = {}
            for key, d in pairs(M.demand[camp.id] or {}) do
                if now - d.at > 15 or not U.live(d.object) then M.demand[camp.id][key] = nil
                elseif U.number(U.read(function() return d.object.CurrentState end)) == 1 then pending[d.suit] = true end
            end
            for _, pal in ipairs(camp.pals) do
                if pal.id and pal.raw_id and pal.permissions_read then
                    local original = base.original[pal.id]
                    local eligible = pal.fixed == false and pal.dead == false
                    if pal.fixed then fixed=fixed+1 end
                    if eligible and original then managed=managed+1 end
                    if original then
                        local desired = original
                        if base.enabled and eligible then
                            local values = {}
                            for work in pairs(pal.skills) do values[work] = M.get(camp.id, pal, work) end
                            desired = policy.plan(pal.skills, values, pending, pal.work)
                        end
                        local acknowledged = true
                        for work, enabled in pairs(desired) do
                            if pal.allowed[work] ~= enabled then
                                acknowledged = false
                                local sent = pcall(function()
                                    component:RequestChangeWorkSuitability_ToServer({PlayerUId = pal.raw_id.PlayerUId,
                                        InstanceId = pal.raw_id.InstanceId, DebugName = ""}, work, enabled)
                                end)
                                if sent then changes = changes + 1 else failures = failures + 1 end
                            end
                        end
                        if acknowledged and (not base.enabled or not eligible) then
                            cleared[#cleared+1]={base.original,pal.id,original,camp.id};base.original[pal.id]=nil
                        end
                    end
                end
            end
            local message
            if failures>0 then message="Some permission changes failed; retrying"
            elseif changes>0 then message=string.format("%s %d work permissions; awaiting game confirmation",base.enabled and "Applying" or "Restoring",changes)
            elseif base.enabled then message=string.format("Managing %d / %d Pals   /   %d fixed assignments retained",managed,#camp.pals,fixed)
            elseif next(base.original) then message="Waiting for remaining Pals to load and confirm their permissions"
            else message="Management off; original work permissions restored" end
            say(camp.id,message,failures==0 and changes==0 and (base.enabled or not next(base.original)))
        end
    end
    if #cleared>0 and not store:save() then
        for _,s in ipairs(cleared) do s[1][s[2]]=s[3];say(s[4],"Could not save recovery completion; will retry") end
    end
end
return M
