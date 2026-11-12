-- Versioned data, never executable Lua. Stable identities are encoded losslessly.
local M = {}
local function field(s)
    return type(s)=="string" and #s>0 and #s<=1024 and utf8.len(s)~=nil and not s:find("[%c]")
end
local function hex(s) return (s:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end
local function unhex(s)
    if #s==0 or #s>2048 or #s%2~=0 or s:find("[^%da-f]") then return end
    local decoded=s:gsub("..",function(pair) return string.char(tonumber(pair,16)) end)
    if field(decoded) then return decoded end
end
function M.key(world,guild,base,station)
    if not (field(world) and field(guild) and field(base) and field(station)) then return end
    return table.concat({world,guild,base,station},"\t")
end
local function encode(records)
    local lines={}
    for _,r in pairs(records) do
        lines[#lines+1]=table.concat({hex(r.world),hex(r.guild),hex(r.base),hex(r.station),hex(r.recipe),r.enabled and "1" or "0",r.batch_size or 0,r.stock_target or 0},"\t")
    end
    table.sort(lines)
    -- A required footer/count detects truncated writes, including at line boundaries.
    return "PAPA\t2\n"..(#lines>0 and table.concat(lines,"\n").."\n" or "").."END\t"..#lines.."\n"
end
local function decode(text)
    if type(text)~="string" then return end
    local version,body,count=text:match("^PAPA\t([12])\n(.*)END\t(%d+)\n$")
    if not body then return end
    local records,n={},0
    for line in body:gmatch("([^\n]*)\n") do
        local batch,target
        if version=="2" then
            line,target=line:match("^(.*)\t(%d+)$")
            target=tonumber(target)
            if not line or not target or target>999999 then return end
            line,batch=line:match("^(.*)\t(%d+)$")
            batch=tonumber(batch)
            if not line or not batch or batch>9999 then return end
            if batch==0 then batch=nil end -- use config default, including migrated v1
        end
        local w,g,b,s,r,on=line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([01])$")
        if not w then return end
        w,g,b,s,r=unhex(w),unhex(g),unhex(b),unhex(s),unhex(r)
        local key=M.key(w,g,b,s)
        if not key or not r or r=="None" or records[key] then return end
        records[key]={world=w,guild=g,base=b,station=s,recipe=r,enabled=on=="1",batch_size=batch,stock_target=target or 0};n=n+1
    end
    if n~=tonumber(count) or (body~="" and body:sub(-1)~="\n") then return end
    return records
end
local function read(path)
    local f,err,code=io.open(path,"rb")
    if not f then return nil,code==2 and "missing" or tostring(err) end
    local value=f:read("*a");f:close()
    return decode(value),"Invalid automation settings"
end
function M.new(path)
    local self={path=path,records={},dirty=false}
    local records,err=read(path)
    if records then self.records=records
    else
        local backup,backup_error=read(path..".bak")
        if backup then self.records=backup;self.recovered=true
        elseif err~="missing" or backup_error~="missing" then
            self.load_error="Cannot load automation settings: "..(err~="missing" and err or backup_error)
            self.error=self.load_error
        end
    end
    function self:save()
        if self.load_error then self.error=self.load_error;return false end
        if not self.dirty then return true end
        local f,err=io.open(self.path..".tmp","wb")
        if not f then self.error=tostring(err);return false end
        local written,failure=f:write(encode(self.records))
        local closed,close_error=f:close()
        if not written or not closed then self.error=tostring(failure or close_error);return false end
        local previous,why=read(self.path)
        if previous then
            -- Only a verified primary may replace the last good backup.
            os.remove(self.path..".bak")
            local moved,err=os.rename(self.path,self.path..".bak")
            if not moved then self.error=tostring(err);return false end
        elseif why~="missing" then
            -- Recovery keeps .bak intact until the new complete file is installed.
            local removed,err=os.remove(self.path)
            if not removed then self.error=tostring(err);return false end
        end
        local moved,err=os.rename(self.path..".tmp",self.path)
        if not moved then
            self.error=tostring(err);return false -- .bak remains recoverable.
        end
        self.dirty,self.error,self.recovered=false,nil,nil
        return true
    end
    function self:set(identity,recipe,enabled,batch_size,stock_target)
        local key=M.key(identity.world,identity.guild,identity.base,identity.station)
        if not key or not field(recipe) or recipe=="None" or type(enabled)~="boolean" then return false,"Invalid automation setting" end
        local old=self.records[key]
        if batch_size~=nil and (type(batch_size)~="number" or batch_size~=batch_size
            or batch_size<1 or batch_size>9999 or batch_size%1~=0) then return false,"Invalid batch size" end
        batch_size=batch_size or (old and old.batch_size)
        if stock_target~=nil and (type(stock_target)~="number" or stock_target~=stock_target
            or stock_target<0 or stock_target>999999 or stock_target%1~=0) then return false,"Invalid stock target" end
        -- A new product must not inherit another product's stock target.
        stock_target=stock_target or (old and old.recipe==recipe and old.stock_target) or 0
        if not old or old.recipe~=recipe or old.enabled~=enabled or old.batch_size~=batch_size or old.stock_target~=stock_target then
            self.records[key]={world=identity.world,guild=identity.guild,base=identity.base,station=identity.station,recipe=recipe,enabled=enabled,batch_size=batch_size,stock_target=stock_target}
            self.dirty=true
        end
        return self:save(),self.error
    end
    return self
end
return M
