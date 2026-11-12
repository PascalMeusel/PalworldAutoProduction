-- Durable choices are separate from live UObject handles and queue telemetry.
local U=require("ap_util")
local Store=require("automation_store")
local data=require("base_data")
local M={}
local directory=debug.getinfo(1,"S").source:gsub("^@",""):match("^(.*[/\\])") or ""
local function context()
    local pc=U.controller()
    if not pc then return end
    local state=U.read(function() return StaticFindObject("/Script/Pal.Default__PalUtility"):GetPalGameStateInGame(pc) end)
    if not U.live(state) then return end
    local world=U.name(U.read(function() return state:GetWorldSaveDirectoryName() end))
    local guild=data.player_group(pc)
    if world=="" or world=="None" or not guild then return end
    return {world=world:lower():gsub("\\","/"),guild=guild,
        session=tostring(U.address(pc))..":"..tostring(U.address(state))}
end
local function identity(station,c)
    if not c or not U.live(station) then return end
    local base=U.guid(U.read(function() return station:GetBaseCampIdBelongTo() end))
    local id=U.guid(U.read(function() return station:GetInstanceId() end))
    if not base or not id then return end
    return {world=c.world,guild=c.guild,base=base,station=id}
end
function M.new(path)
    local self={store=Store.new(path or directory.."automations.tsv"),active={},applied={},next_restore=0}
    function self:sync()
        local c=context()
        local previous=self.context
        if previous and (not c or c.world~=previous.world or c.guild~=previous.guild or c.session~=previous.session) then
            for key in pairs(self.active) do self.active[key]=nil end
            self.applied={};self.next_restore=0
            data.reset_world()
            if self.on_session_change then self.on_session_change() end
        end
        self.context=c
        return c
    end
    function self:has_saved() return next(self.store.records)~=nil end
    function self:batch_size(station,default)
        local id=identity(station,self.context)
        local record=id and self.store.records[Store.key(id.world,id.guild,id.base,id.station)]
        return record and record.batch_size or default
    end
    function self:stock_target(station)
        local id=identity(station,self.context)
        local record=id and self.store.records[Store.key(id.world,id.guild,id.base,id.station)]
        return record and record.stock_target or 0
    end
    function self:save(station,recipe,enabled,batch_size,stock_target)
        local c=self:sync()
        local id=identity(station,c)
        if not id then
            self.save_notice="World or station identity is not ready; this choice is session only."
            return false,self.save_notice
        end
        self.save_notice=nil
        local ok,err=self.store:set(id,recipe,enabled,batch_size,stock_target)
        local address=U.address(station)
        local key=Store.key(id.world,id.guild,id.base,id.station)
        self.applied[address]=key
        if self.active[address] then self.active[address].identity=key end
        if not ok then return false,"Could not save Auto Produce: "..tostring(err)..". This choice is session only until saving succeeds." end
        return true
    end
    function self:restore(products,supports,unlocked,force)
        local c=self:sync()
        if not c then return end
        local now=os.time()
        if not force and now<self.next_restore then return end
        self.next_restore=now+5
        if self.store.dirty and now>=(self.retry_save_at or 0) then
            self.retry_save_at=now+30
            if not self.store:save() then U.log("Automation settings could not be saved: "..tostring(self.store.error)) end
        end
        if not self:has_saved() then return end
        if self.generation~=data.generation then self.applied={};self.generation=data.generation end
        data.seed()
        for address,station in pairs(data.objects) do
            local id=identity(station,c)
            if id then
                local key=Store.key(id.world,id.guild,id.base,id.station)
                -- Address reuse must not transfer an old building's automation.
                if self.applied[address] and self.applied[address]~=key then
                    self.applied[address]=nil;self.active[address]=nil
                end
                if self.applied[address]~=key then
                    local r=self.store.records[key]
                    local row={station=station,base_id=id.base,station_id=id.station,key=address}
                    if r and data.can_edit_station(row) and products[r.recipe] and supports(station,r.recipe) and unlocked(r.recipe) then
                        data.select_recipe(row,{id=r.recipe,label=r.recipe,yield_count=1})
                        if r.enabled and not self.active[address] then
                            self.active[address]={station=station,recipe_id=r.recipe,product_id=products[r.recipe],status="Resuming",identity=key,batch_size=r.batch_size,stock_target=r.stock_target}
                            U.log("Restored AutoProduce for "..r.recipe..".")
                        end
                        self.applied[address]=key
                    end
                end
            end
        end
        for address in pairs(self.applied) do
            if not U.live(data.objects[address]) and not self.active[address] then self.applied[address]=nil end
        end
    end
    function self:valid(automation)
        local id=identity(automation.station,self.context)
        if not U.live(automation.station) then return false end
        if not automation.identity then return true end -- unsaved, newly enabled station
        return id and Store.key(id.world,id.guild,id.base,id.station)==automation.identity
    end
    function self:save_warning()
        return self.save_notice or (self.store.error and "Could not save Auto Produce. This choice is session only until saving succeeds.")
    end
    if self.store.error then U.log(self.store.error) end
    return self
end
return M
