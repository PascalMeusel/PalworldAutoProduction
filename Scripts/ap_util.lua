local M = {}
local cached_controller
local flag_check_supported
function M.defer(milliseconds, callback)
    -- Current UE4SS can keep the timer and callback on the game thread.
    -- Avoid recurring async -> game-thread handoffs against the shared Lua
    -- registry. Older loaders retain the compatibility path.
    if type(ExecuteInGameThreadWithDelay)=="function" then
        return ExecuteInGameThreadWithDelay(milliseconds, callback)
    end
    ExecuteWithDelay(milliseconds,function() ExecuteInGameThread(callback) end)
end
function M.unwrap(v)
    if v == nil then return nil end
    local kind=type(v)
    if kind~="userdata" and (kind~="table" or type(v.get)~="function") then return v end
    -- UObject/UScriptStruct/FName values are already unwrapped. Calling :get()
    -- on every one triggers expensive failed reflected-function lookups.
    if kind=="userdata" or type(v.type)=="function" then
        local typed, class=pcall(function() return v:type() end)
        if typed and class~="RemoteUnrealParam" and class~="LocalUnrealParam" then return v end
    end
    local ok, result = pcall(function() return v:get() end)
    return ok and result ~= nil and result or v
end
function M.valid(v)
    if v == nil then return false end
    local ok, result = pcall(function() return v:IsValid() end)
    if not ok or result~=true then return false end
    -- Some loader builds still expose an object during BeginDestroy. Do not
    -- call UI/game methods on it merely because its wrapper is non-null.
    if EObjectFlags and flag_check_supported~=false then
        local mask=(EObjectFlags.RF_BeginDestroyed or 0) | (EObjectFlags.RF_FinishDestroyed or 0)
        if mask~=0 then
            local checked,destroying=pcall(function() return v:HasAnyFlags(mask) end)
            -- Older bridges may expose the constants without the method. Do
            -- not repeat an expensive failed reflection lookup on every read.
            flag_check_supported=checked
            if checked and destroying then return false end
        end
    end
    return true
end
function M.read(fn)
    local ok, result = pcall(fn)
    if ok then return M.unwrap(result) end
end
function M.number(v)
    local n = tonumber(M.unwrap(v))
    if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
end
function M.clean_text(value)
    local s=tostring(value or "")
    -- Native string conversion rejects malformed UTF-8. Preserve complete
    -- characters; replace bad bytes and embedded control bytes individually.
    s=s:gsub("[%z\1-\8\11\12\14-\31\127]","?")
    local parts,start={},1
    while start<=#s do
        local length,bad=utf8.len(s,start)
        if length then parts[#parts+1]=s:sub(start);break end
        parts[#parts+1]=s:sub(start,bad-1)
        parts[#parts+1]="?"
        start=bad+1
    end
    return table.concat(parts)
end
function M.truncate_text(value,limit)
    local s=M.clean_text(value)
    if utf8.len(s)<=limit then return s end
    if limit<=2 then return string.rep(".",math.max(0,limit)) end
    return s:sub(1,utf8.offset(s,limit-1)-1)..".."
end
function M.name(v)
    v = M.unwrap(v)
    if v == nil then return "" end
    if type(v) == "string" then return M.clean_text(v) end
    local text_type
    if type(v)=="userdata" or (type(v)=="table" and type(v.type)=="function") then
        text_type=M.read(function() return v:type() end)
    end
    if text_type=="FText" then
        -- UE4SS ba2efd55's Lua FText:ToString() calls ToFString(), which
        -- aborts on a null TextData pointer (valid empty game text).
        -- Native text-function arguments use the SAME conversion; pcall
        -- cannot contain abort(). Do not pass unknown game FText through
        -- either bridge. Callers fall back to an identifier. FString names
        -- and FName identifiers remain readable without this conversion.
        return ""
    end
    return M.clean_text(M.read(function() return v:ToString() end) or "")
end
function M.guid(v)
    v = M.unwrap(v)
    if v == nil then return nil end
    local parts, nonzero = {}, false
    for _, field in ipairs({"A", "B", "C", "D"}) do
        local n = M.number(M.read(function() return v[field] end))
        if not n then return nil end
        parts[#parts + 1] = string.format("%.0f", n)
        nonzero = nonzero or n ~= 0
    end
    return nonzero and table.concat(parts, "-") or nil
end
function M.address(v)
    if not M.valid(v) then return nil end
    local a = M.read(function() return v:GetAddress() end)
    return a and tostring(a) or nil
end
function M.live(v)
    if not M.valid(v) then return false end
    local name = M.read(function() return v:GetFullName() end) or ""
    return not name:find("Default__", 1, true) and not name:find("REINST_", 1, true)
end
function M.each(array, fn)
    if array == nil then return false end
    if type(array) == "table" then
        for i, v in ipairs(array) do fn(v, i) end
        return true
    end
    return pcall(function()
        array:ForEach(function(i, v) fn(M.unwrap(v), i) end)
    end)
end
function M.controller()
    if M.valid(cached_controller) then return cached_controller end
    local pc = M.read(function() return UEHelpers:GetPlayerController() end)
    if not M.live(pc) then pc = M.read(function() return FindFirstOf("PalPlayerController") end) end
    cached_controller=M.live(pc) and pc or nil
    return cached_controller
end
function M.clear_controller() cached_controller=nil end
function M.visible(widget)
    local current=widget
    for _=1,32 do
        if not M.valid(current) then return false end
        if M.read(function() return current:IsVisible() end)~=true then return false end
        local parent=M.read(function() return current:GetParent() end)
        if not M.valid(parent) then return true end
        current=parent
    end
    return false
end
function M.clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
function M.log(message) print("[PalworldAutoProduction] " .. message .. "\n") end
M.work = {"Kindling", "Watering", "Planting", "Electricity", "Handiwork", "Gathering",
    "Lumbering", "Mining", "Oil extraction", "Medicine", "Cooling", "Transport", "Farming"}
M.short_work = {"Fire", "Water", "Plant", "Power", "Craft", "Gather", "Wood", "Mine", "Oil", "Meds", "Cool", "Carry", "Farm"}
return M
