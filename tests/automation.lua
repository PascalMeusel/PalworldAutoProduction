local Store=require("automation_store")
local checks=0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b)) end
local path=os.tmpname();os.remove(path)
local function clean() for _,suffix in ipairs({"",".bak",".tmp"}) do os.remove(path..suffix) end end
local function write(suffix,value) local f=assert(io.open(path..suffix,"wb"));assert(f:write(value));f:close() end
local function bytes(suffix) local f=assert(io.open(path..suffix,"rb"));local v=f:read("*a");f:close();return v end
local id={world="world one/世界",guild="1-2-3-4",base="5-6-7-8",station="9-10-11-12"}
local key=Store.key(id.world,id.guild,id.base,id.station)
local s=Store.new(path)
eq(s.error,nil);eq(s:set(id,"Salad",true),true)
local first=bytes("")
s=Store.new(path);eq(s.records[key].recipe,"Salad");eq(s.records[key].enabled,true)
eq(s:set(id,"Cake",false),true);eq(bytes(".bak"),first)
s=Store.new(path);eq(s.records[key].recipe,"Cake");eq(s.records[key].enabled,false)
-- Redundant calls do not rewrite the file or rotate its backup.
eq(s:set(id,"Cake",false),true);eq(bytes(".bak"),first)
-- A save never destroys the last valid backup when recovering a bad primary.
write("","PAPA\t1\ntruncated")
s=Store.new(path);eq(s.recovered,true);eq(s.records[key].recipe,"Salad")
eq(s:set(id,"Cake",false),true);eq(bytes(".bak"),first)
eq(Store.new(path).records[key].enabled,false)
-- Interrupted primary replacement is recoverable; failed saves remain dirty.
local rename=os.rename
os.rename=function(from,to) if from==path..".tmp" then return nil,"simulated interrupted rename" end;return rename(from,to) end
eq(s:set(id,"Salad",true),false);eq(s.dirty,true)
os.rename=rename
eq(Store.new(path).records[key].recipe,"Cake")
eq(s:save(),true);eq(Store.new(path).records[key].enabled,true)
-- A valid footer detects complete-line truncation; both corrupt copies are
-- left intact, never silently overwritten with an empty set of settings.
write("",first:gsub("END\t1\n$",""));write(".bak","return os.execute('no')")
s=Store.new(path);eq(s.load_error~=nil,true)
local damaged=bytes("");eq(s:set(id,"Salad",true),false);eq(bytes(""),damaged)
clean();s=Store.new(path)
eq(s:set(id,"None",true),false);eq(s:set(id,"Salad\ninvalid",true),false)
eq(s:set(id,"Salad",true),true)
-- Failure to open a temporary file preserves disk state and can be retried.
local open=io.open
io.open=function(p,mode) if p==path..".tmp" then return nil,"read only",13 end;return open(p,mode) end
eq(s:set(id,"Cake",false),false);eq(Store.new(path).records[key].recipe,"Salad")
io.open=open;eq(s:save(),true);eq(Store.new(path).records[key].recipe,"Cake")
clean()

-- Use real scope resolution and real base ownership checks with native-shaped
-- objects, a different address on every reload, and an actual data file.
local U=require("ap_util")
local data=require("base_data")
local serial=0
local function object(fields)
    local v=fields or {};serial=serial+1;v.address=serial
    function v:IsValid() return self.valid~=false end
    function v:GetAddress() return self.address end
    function v:GetFullName() return "Live instance" end
    return v
end
local function guid(n) return {A=n,B=2,C=3,D=4} end
local world,guild,base="world-a",guid(1),guid(5)
local camp=object({GetId=function() return base end,GetGroupIdBelongTo=function() return guild end})
local pawn=object({InsideBaseCampCheckComponent={GetInsideBaseCampModel=function() return camp end},
    GetCharacterParameterComponent=function() return object({GetIndividualParameter=function()
        return object({GetGroupId=function() return guild end}) end}) end})
local pc=object({Pawn=pawn})
local game_state=object({GetWorldSaveDirectoryName=function() return world end})
UEHelpers={GetPlayerController=function() return pc end};U.clear_controller()
function StaticFindObject(name)
    assert(name=="/Script/Pal.Default__PalUtility")
    return object({GetPalGameStateInGame=function() return game_state end})
end
local discoveries=0
function FindAllOf() discoveries=discoveries+1;return {} end
local native_scans=0
function FindFirstOf() native_scans=native_scans+1 end
local function station(n)
    return object({GetBaseCampIdBelongTo=function() return base end,GetInstanceId=function() return guid(n) end})
end
local State=require("automation_state")
local products={Salad="Salad",Cake="Cake"}
local supported,unlocked=true,true
local function supports() return supported end
local function unlocks() return unlocked end
local function restore(manager) manager:restore(products,supports,unlocks,true) end
local a=station(9)
local manager=State.new(path)
eq(manager:save(a,"Salad",true),true)
-- Reload into a different object address without opening a menu.
a.valid=false;a=station(9);data.objects={[U.address(a)]=a}
manager=State.new(path);restore(manager)
eq(manager.active[U.address(a)].recipe_id,"Salad")
eq(manager:valid(manager.active[U.address(a)]),true)
eq(discoveries,4) -- one bootstrap of the existing typed base caches
local discovered=discoveries
for _=1,10 do restore(manager) end
eq(discoveries,discovered) -- subsequent restore passes never rescan all UObjects
-- Visiting the same-ID station in a different world cannot restore it.
world="world-b";data.objects={[U.address(a)]=a};restore(manager)
eq(next(manager.active),nil)
data.objects={[U.address(a)]=a};restore(manager);eq(next(manager.active),nil)
eq(manager:save(a,"Cake",false),true)
world="world-a";restore(manager);data.objects={[U.address(a)]=a};restore(manager)
eq(manager.active[U.address(a)].recipe_id,"Salad")
-- Paused preferences and selected recipe survive their own restart.
eq(manager:save(a,"Cake",false),true);manager.active[U.address(a)]=nil
manager=State.new(path);restore(manager);eq(next(manager.active),nil)
local world_a=Store.key("world-a",U.guid(guild),U.guid(base),U.guid(guid(9)))
eq(manager.store.records[world_a].recipe,"Cake");eq(manager.store.records[world_a].enabled,false)
eq(manager:save(a,"Salad",true),true)
-- Locked/unsupported recipes wait without deleting their saved choice.
manager=State.new(path);unlocked=false;restore(manager);eq(next(manager.active),nil)
unlocked=true;supported=false;restore(manager);eq(next(manager.active),nil)
supported=true;restore(manager);eq(manager.active[U.address(a)].recipe_id,"Salad")
-- Foreign guilds and bases away from the character cannot start production.
guild=guid(99);restore(manager);data.objects={[U.address(a)]=a};restore(manager);eq(next(manager.active),nil)
guild=guid(1);restore(manager)
local saved_camp=camp;camp=object({GetId=function() return guid(77) end,GetGroupIdBelongTo=function() return guild end})
data.objects={[U.address(a)]=a};restore(manager);eq(next(manager.active),nil)
camp=saved_camp;restore(manager);eq(manager.active[U.address(a)].recipe_id,"Salad")
-- Address reuse, demolition and a different permanent ID never inherit ON.
local old=manager.active[U.address(a)]
function a:GetInstanceId() return guid(800) end
eq(manager:valid(old),false);restore(manager);eq(next(manager.active),nil)
-- Delayed replication and station streaming can complete later.
manager=State.new(path);data.objects={};restore(manager);eq(next(manager.active),nil)
local b=station(9);data.objects={[U.address(b)]=b};restore(manager)
eq(manager.active[U.address(b)].recipe_id,"Salad")
-- A title screen or changed game state clears handles even if the world name
-- and controller address are reused when loading the same world again.
game_state.valid=false;restore(manager);eq(next(manager.active),nil)
game_state=object({GetWorldSaveDirectoryName=function() return world end})
restore(manager);data.objects={[U.address(b)]=b};restore(manager)
eq(manager.active[U.address(b)].recipe_id,"Salad")
game_state=object({GetWorldSaveDirectoryName=function() return world end})
restore(manager);eq(next(manager.active),nil)
data.objects={[U.address(b)]=b};restore(manager);eq(manager.active[U.address(b)].recipe_id,"Salad")
-- Transient inability to save OFF must not resurrect ON from disk this session.
io.open=function(p,mode) if p==path..".tmp" then return nil,"read only",13 end;return open(p,mode) end
eq(manager:save(b,"Salad",false),false);manager.active[U.address(b)]=nil
eq(manager:save_warning()~=nil,true)
restore(manager);eq(next(manager.active),nil)
io.open=open;eq(manager.store:save(),true)
eq(manager:save_warning(),nil)
eq(State.new(path).store.records[world_a].enabled,false)
eq(native_scans,0) -- the restore loop never performs global object searches.
clean()
print(string.format("PASS Durable automation files, interrupted writes, restarts, world/guild isolation and delayed restoration; %d assertions",checks))
