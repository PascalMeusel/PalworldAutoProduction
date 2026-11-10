-- Pure, bounded session telemetry. Unknown intervals never become zero output.
local M = {}
function M.new(window, retention)
    local self = {stations = {}, histories = {}, window = window or 60, retention = retention or 600}
    function self:observe(key, recipe, remaining, yield_count, now)
        if remaining<0 then self.stations[key]=nil;return nil,0 end
        local s = self.stations[key]
        if not s or s.recipe ~= recipe or now - s.at > 12 or now < s.at then
            s = {recipe = recipe, remaining = remaining, start = now, at = now, events = {}}
            self.stations[key] = s
        elseif remaining < s.remaining then
            s.events[#s.events + 1] = {at = now, count = s.remaining - remaining}
        end
        s.remaining, s.at = remaining, now
        local crafts = 0
        for i = #s.events, 1, -1 do
            if s.events[i].at <= now - self.window then table.remove(s.events, i)
            else crafts = crafts + s.events[i].count end
        end
        if now - s.start < self.window then return nil, now - s.start end
        return crafts * yield_count * 60 / self.window, self.window
    end
    -- A mod refill is a known discontinuity; sample before it and reset the baseline after it.
    function self:baseline(key, recipe, remaining, now)
        local s = self.stations[key]
        if s and s.recipe == recipe then s.remaining, s.at = remaining, now end
    end
    function self:push(base_id, point)
        local h = self.histories[base_id] or {}
        self.histories[base_id] = h
        if #h > 0 and point.at <= h[#h].at then return end
        h[#h + 1] = point
        while #h > 121 or (#h > 0 and h[1].at < point.at - self.retention) do table.remove(h, 1) end
    end
    function self:prune(now)
        for k, s in pairs(self.stations) do if now - s.at > self.retention then self.stations[k] = nil end end
        for k, h in pairs(self.histories) do
            if #h == 0 or now - h[#h].at > self.retention then self.histories[k] = nil end
        end
    end
    return self
end
return M
