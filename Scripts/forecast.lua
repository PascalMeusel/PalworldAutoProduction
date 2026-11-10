-- Food is normalized to nutrition, not item count (one berry is not one meal).
local M = {}
function M.food(points, now, stock, complete)
    if not complete or stock == nil then return {state = "unavailable", label = "Food data unavailable"} end
    if stock <= 0 then return {state = "empty", label = "Feed boxes empty", minutes = 0, stock = 0} end
    local samples = {}
    for _, p in ipairs(points or {}) do
        if now - p.at <= 300 then
            local last=samples[#samples]
            if p.food == nil or (last and (p.at-last.at>12 or p.at<=last.at or p.food_source~=last.food_source)) then samples={} end
            if p.food ~= nil then samples[#samples + 1] = p end
        end
    end
    local span = #samples > 1 and samples[#samples].at - samples[1].at or 0
    if #samples < 12 or span < 120 or now-samples[#samples].at>12 then
        if #samples==0 or now-samples[#samples].at>12 then span=0 end
        return {state = "measuring", label = "Learning food trend", stock = stock, span = span,seconds_left=math.max(0,120-span)}
    end
    local sx, sy, sxx, sxy = 0, 0, 0, 0
    local added,removed,drops,last=0,0,0,nil
    for _, p in ipairs(samples) do
        local x = (p.at - samples[1].at) / 60
        sx, sy, sxx, sxy = sx + x, sy + p.food, sxx + x*x, sxy + x*p.food
        if last then
            local delta=p.food-last
            if delta>0 then added=added+delta elseif delta<0 then removed=removed-delta;drops=drops+1 end
        end
        last=p.food
    end
    local n = #samples
    local slope = (n*sxy - sx*sy) / (n*sxx - sx*sx)
    local mean, intercept = sy/n, (sy - slope*sx)/n
    local residual, variance = 0, 0
    for _, p in ipairs(samples) do
        residual = residual + (p.food - intercept - slope*(p.at-samples[1].at)/60)^2
        variance = variance + (p.food - mean)^2
    end
    local fit = variance > 0 and math.max(0, 1 - residual/variance) or 1
    local result = {stock = stock, net = slope, span = span, fit = fit, confidence = fit >= 0.7 and "steady trend" or "variable trend"}
    -- These are changes between samples, not an item transaction log. A
    -- delivery that offsets a meal in the same interval cannot be separated.
    result.added,result.removed=added,removed
    result.draw_rate=removed*60/span
    result.no_delivery_minutes=drops>=2 and stock/result.draw_rate or nil
    if fit < 0.7 then
        result.state, result.label = "variable", "Restock / variable trend"
    elseif math.abs(slope) < 0.1 then
        result.state, result.label = "balanced", "No depletion observed"
    elseif slope > 0 then
        result.state, result.label = "growing", "Food stocks growing"
    else
        result.state, result.minutes = "declining", stock / -slope
        result.label = result.minutes < 60 and string.format("~%d min of food", math.max(1, math.floor(result.minutes)))
            or string.format("~%.1f hours of food", result.minutes/60)
    end
    if result.state~="variable" then
        result.projected = {}
        for i = 0, 12 do result.projected[#result.projected + 1] = math.max(0, stock + slope * i * 5) end
    end
    return result
end
return M
