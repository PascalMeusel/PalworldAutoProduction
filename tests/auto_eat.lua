local checks=0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b)) end
local sequence=0
local function object(fields)
    sequence=sequence+1
    local o=fields or {};o.address=sequence
    function o:IsValid() return self.valid~=false end
    function o:GetAddress() return self.address end
    function o:GetFullName() return "Object instance "..self.address end
    function o:GetClass() return {GetFName=function() return self.class or "Object" end} end
    return o
end
local function guid(n) return {A=n,B=0,C=0,D=0} end
FName=function(s) return s end
local function fixture()
    package.loaded.auto_eat=nil;package.loaded.base_data=nil
    require("ap_util").clear_controller()
    local f={time=100,full=20,pos={X=0,Y=0,Z=0},velocity={X=0,Y=0,Z=0},yaw=0,pitch=0,
        inside=true,own=true,dead=false,riding=false,overlay=false,requests=0,scans=0,inventory_reads=0,response="success"}
    os.time=function() return f.time end
    local target={PlayerUId=guid(77),InstanceId=guid(88),DebugName="Local player"}
    local function slot(item,count)
        local s=object({ItemId={StaticId=item},count=count,allowed=true})
        function s:GetSlotId() return {ContainerId={ID=guid(self.address)},SlotIndex=0} end
        function s:GetStackCount() return self.count end
        function s:CanUseItemToCharacter(id) eq(id,target);return self.allowed end
        function s:RequestUseToCharacter(id,num)
            eq(id,target);eq(num,1);eq(self,f.empty);f.uses=(f.uses or 0)+1
            if f.response=="error" then error("native request failure") end
            if f.response=="success" then self.count=self.count-1;f.full=f.full+30 end
        end
        return s
    end
    f.empty=slot("None",0)
    f.common=object({ItemSlotArray={slot("Wood",1),f.empty}})
    f.pouch=object({ItemSlotArray={}})
    f.food=slot("Salad",20)
    local function box(base,food,class)
        local c=object({ItemSlotArray={slot("Wood",3),food}})
        return object({class=class or "PalMapObjectPalFoodBoxModel",
            GetBaseCampIdBelongTo=function() return guid(base) end,
            GetItemContainerModule=function() return object({GetContainer=function() return c end}) end})
    end
    f.own_box=box(1,f.food)
    f.foreign_box=box(2,slot("Salad",100))
    f.chest=box(1,slot("Salad",100),"PalMapObjectItemContainerModel")
    local camp=object({GetId=function() return guid(1) end,GetGroupIdBelongTo=function() return guid(f.own and 10 or 20) end})
    local param=object({GetGroupId=function() return guid(10) end,IsDead=function() return f.dead end,
        GetFullStomach=function() return f.full end,GetFullStomachRate=function() return f.full/100 end})
    f.pawn=object({bIsBattleMode=false,InsideBaseCampCheckComponent=object({GetInsideBaseCampModel=function() return f.inside and camp or nil end}),
        GetCharacterParameterComponent=function() return object({GetIndividualParameter=function() return param end}) end,
        K2_GetActorLocation=function() return f.pos end,GetVelocity=function() return f.velocity end})
    f.inventory=object({TryGetContainerFromInventoryType=function(_,kind,out)
        f.inventory_reads=f.inventory_reads+1
        out.OutContainer=kind==0 and f.common or f.pouch
        return out.OutContainer~=nil
    end,GetUnlockedFoodEquipSlotNum=function() return f.unlocked or 5 end})
    f.pc=object({Pawn=f.pawn,GetDefaultPlayerCharacter=function() return f.pawn end,
        GetControlRotation=function() return {Pitch=f.pitch,Yaw=f.yaw,Roll=0} end,
        IsRiding=function() return f.riding end,
        GetPalPlayerState=function() return object({GetInventoryData=function() return f.inventory end}) end})
    local network=object({RequestMove_ToServer=function(_,request,to,from)
        eq(request.A,61);eq(to.ContainerId.ID.A,f.empty.address);eq(from[1].SlotId.ContainerId.ID.A,f.food.address)
        eq(from[1].Num,1);eq(#from,1);f.requests=f.requests+1
        if f.transfer=="error" then error("failed transfer") end
        if f.transfer~="delay" then
            f.food.count=f.food.count-1;f.empty.count=1;f.empty.ItemId.StaticId="Salad"
        end
    end})
    f.pc.Transmitter=object({GetItem=function() return network end})
    UEHelpers={GetPlayerController=function() return f.pc end}
    local manager=object({GetStaticItemData=function(_,name)
        if name=="Unknown" then return nil end
        return object({TypeA=name=="Salad" and 8 or 1,GetRestoreSatiety=function() return 30 end})
    end})
    local utility=object({GetItemIDManager=function() return manager end,
        GetHUDService=function() return object({IsAnyOverlayUIActive=function() return f.overlay end}) end,
        GetIndividualIDByActor=function(p,pawn) eq(pawn,f.pawn);return target end})
    StaticFindObject=function(path)
        if path=="/Script/Engine.Default__KismetGuidLibrary" then return {NewGuid=function() return guid(61) end} end
        eq(path,"/Script/Pal.Default__PalUtility");return utility
    end
    FindAllOf=function(class)
        f.scans=f.scans+1
        if class=="PalMapObjectPalFoodBoxModel" then return {f.own_box,f.foreign_box,f.chest} end
        return {}
    end
    NotifyOnNewObject=function() end
    f.module=require("auto_eat");f.module.configure({})
    f.module.tick(f.time)
    function f:advance(seconds)
        for _=5,seconds,5 do self.time=self.time+5;self.module.tick(self.time) end
    end
    f.slot=slot
    return f
end

local f=fixture()
f:advance(55);eq(f.requests,0);eq(f.inventory_reads,0);eq(f.scans,0)
f:advance(5);eq(f.requests,1);eq(f.food.count,19);eq(f.full,20);eq(f.scans,1)
f:advance(5);eq(f.full,50);eq(f.uses,1)
f:advance(5);eq(f.module.meals,1)
f:advance(120);eq(f.requests,1);eq(f.scans,1)
f.full=20;f:advance(5);eq(f.requests,2);eq(f.scans,1)

for _,kind in ipairs({"common","pouch"}) do
    f=fixture();f[kind].ItemSlotArray={f.slot("Salad",1)}
    f:advance(120);eq(f.requests,0);eq(f.module.status,"Food already in your inventory");eq(f.scans,0)
end
f=fixture();f.common.ItemSlotArray={f.slot("Unknown",1)}
f:advance(120);eq(f.requests,0);eq(f.module.status,"Inventory reading incomplete")
f=fixture();f.common.valid=false;f:advance(120);eq(f.requests,0)
f=fixture();f.pouch=nil;f.unlocked=0;f:advance(60);eq(f.requests,1) -- No unlocked pouch yet.

for _,flag in ipairs({"outside","foreign","dead","mounted","combat","menu"}) do
    f=fixture()
    if flag=="outside" then f.inside=false elseif flag=="foreign" then f.own=false
    elseif flag=="dead" then f.dead=true elseif flag=="mounted" then f.riding=true
    elseif flag=="combat" then f.pawn.bIsBattleMode=true else f.overlay=true end
    f:advance(120);eq(f.requests,0);eq(f.scans,0)
end
f=fixture();f:advance(50);f.pos={X=20,Y=0,Z=0};f:advance(10);eq(f.requests,0)
f:advance(55);eq(f.requests,1)
f=fixture();f:advance(50);f.yaw=15;f:advance(10);eq(f.requests,0)
f:advance(55);eq(f.requests,1)
f=fixture();f:advance(50);f.module.activity();f:advance(55);eq(f.requests,0)
f:advance(5);eq(f.requests,1)
f=fixture();f.velocity={X=50,Y=0,Z=0};f:advance(120);eq(f.requests,0)

f=fixture();f.food.count=0;f:advance(120);eq(f.requests,0);eq(f.module.status,"No usable food in feed boxes")
f=fixture();f.food.allowed=false;f:advance(120);eq(f.requests,0)
-- An unrelated hunger increase, a stale response or a menu transition cannot
-- falsely confirm a request against the original feed-box slot.
f=fixture();f.response="delay";f:advance(65);f.full=60;f:advance(15);eq(f.module.meals,0)
f=fixture();f.response="delay";f:advance(65);f.full=60;f.empty.count=0;f.time=f.time+30;f.module.tick(f.time);eq(f.module.meals,0)
f=fixture();f:advance(65);f.overlay=true;f:advance(5);eq(f.module.meals,1);eq(f.module.summary().last_meal,"Salad")
for _,response in ipairs({"delay","error"}) do
    f=fixture();f.transfer=response;f:advance(60);eq(f.requests,1)
    f:advance(75);eq(f.requests,1);eq(f.module.meals,0)
    f.transfer="success";f:advance(5);eq(f.requests,2)
    f:advance(10);eq(f.module.meals,1)
    f=fixture();f.response=response;f:advance(180);eq(f.requests,1);eq(f.uses,1);eq(f.empty.count,1);eq(f.module.meals,0)
end
f=fixture();f.common.ItemSlotArray={f.slot("Wood",8)};f:advance(90);eq(f.requests,0);eq(f.module.status,"Need a free inventory slot")
f=fixture();f:advance(60);f.module.activity();f:advance(120);eq(f.uses,nil);eq(f.empty.count,1);eq(f.requests,1)
f=fixture();f:advance(60);f.empty.ItemId.StaticId="Wood";f:advance(15);eq(f.uses,nil);eq(f.module.meals,0)
f=fixture();f:advance(60);f.own=false;f:advance(30);eq(f.uses,nil);eq(f.empty.count,1)
f=fixture();f.module.toggle();eq(f.module.needs_tick(),false);f:advance(120);eq(f.requests,0)
f.module.toggle();f:advance(55);eq(f.requests,0);f:advance(5);eq(f.requests,1)
f=fixture();f:advance(50);f.pawn.address=f.pawn.address+10000;f:advance(10);eq(f.requests,0)
f:advance(55);eq(f.requests,1)
f=fixture();f.module.configure({BASE_AUTO_EAT=false});f:advance(120);eq(f.requests,0)
print(string.format("PASS AFK meals: real stock, idle gates, carried food, feed-box ownership, confirmation and backoff; %d assertions",checks))
