-- This module knows nothing about UE4SS. Lower numbers win; zero is Off.
local M = {}
function M.get(base, pal, work, original)
    local override = base.pals[pal] and base.pals[pal][work]
    if override ~= nil then return override end
    if base.defaults[work] ~= nil then return base.defaults[work] end
    return original == false and 0 or 3
end
function M.plan(skills, values, available, current)
    local best = 6
    for work in pairs(skills) do
        local p = values[work] or 3
        if p > 0 and (available[work] or current == work) then best = math.min(best, p) end
    end
    local allowed = {}
    for work in pairs(skills) do
        local p = values[work] or 3
        -- With no known demand allow every non-Off job, so new work can start.
        allowed[work] = p > 0 and (best == 6 or p == best)
    end
    return allowed
end
function M.cycle(value, direction) return (value + (direction or -1)) % 6 end
return M
