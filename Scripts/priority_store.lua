-- Data only: never execute a settings file as Lua. Recover interrupted writes from .bak.
local M = {}
local function safe(s) return type(s) == "string" and s:match("^[%w:_%-]+$") ~= nil end
function M.new(path)
    local self = {path = path, bases = {}, error = nil}
    function self:base(id)
        self.bases[id] = self.bases[id] or {enabled = false, defaults = {}, pals = {}, original = {}}
        return self.bases[id]
    end
    function self:decode(text)
        if text:sub(1, 6) ~= "PAP\t1\n" then return false end
        local parsed = {}
        for line in text:gmatch("[^\n]+") do
            local kind, id, pal, work, value = line:match("^(%a)\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)$")
            work, value = tonumber(work), tonumber(value)
            if kind and safe(id) and safe(pal) and work and work <= 13 and value and value <= 5 then
                local b = parsed[id] or {enabled = false, defaults = {}, pals = {}, original = {}}
                parsed[id] = b
                if kind == "E" then b.enabled = value == 1
                elseif kind == "D" and work >= 1 then b.defaults[work] = value
                elseif (kind == "P" or kind == "O") and work >= 1 then
                    local target = kind == "P" and b.pals or b.original
                    target[pal] = target[pal] or {}
                    target[pal][work] = kind == "O" and (value == 1) or value
                    if kind == "O" then target[pal][work] = value == 1 end
                end
            elseif line ~= "PAP\t1" then return false end
        end
        self.bases = parsed
        return true
    end
    function self:encode()
        local lines = {}
        for id, b in pairs(self.bases) do
            if safe(id) then
                lines[#lines + 1] = string.format("E\t%s\t_\t0\t%d", id, b.enabled and 1 or 0)
                for w, v in pairs(b.defaults) do lines[#lines + 1] = string.format("D\t%s\t_\t%d\t%d", id, w, v) end
                for _, entry in ipairs({{"P", b.pals}, {"O", b.original}}) do
                    for pal, values in pairs(entry[2]) do
                        if safe(pal) then
                            for w, v in pairs(values) do
                                if entry[1] == "O" then v = v and 1 or 0 end
                                lines[#lines + 1] = string.format("%s\t%s\t%s\t%d\t%d", entry[1], id, pal, w, v)
                            end
                        end
                    end
                end
            end
        end
        table.sort(lines)
        return "PAP\t1\n" .. table.concat(lines, "\n") .. "\n"
    end
    function self:save()
        if self.load_error then self.error=self.load_error;return false end
        local f, err = io.open(self.path .. ".tmp", "wb")
        if not f then self.error = tostring(err); return false end
        local ok, failure = f:write(self:encode())
        local closed, close_error = f:close()
        if not ok or not closed then self.error = tostring(failure or close_error); return false end
        -- Windows rename will not overwrite an existing destination.
        os.remove(self.path .. ".bak")
        local existing = io.open(self.path, "rb")
        if existing then
            existing:close()
            local moved, move_error = os.rename(self.path, self.path .. ".bak")
            if not moved then self.error = tostring(move_error); return false end
        end
        local moved, move_error = os.rename(self.path .. ".tmp", self.path)
        if not moved then
            os.rename(self.path .. ".bak", self.path)
            self.error = tostring(move_error)
            return false
        end
        self.error = nil
        return true
    end
    for _, candidate in ipairs({path, path .. ".bak"}) do
        local f = io.open(candidate, "rb")
        if f then
            local content = f:read("*a"); f:close()
            if self:decode(content) then self.error = nil; self.load_error=nil; break end
            self.error = "Priority settings are damaged; the file was not loaded."
            self.load_error=self.error
        end
    end
    return self
end
return M
