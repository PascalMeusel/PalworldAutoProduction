local tests, checks = 0, 0
local function eq(a,b,message) checks=checks+1; assert(a==b,(message or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function near(a,b) checks=checks+1;assert(math.abs(a-b)<0.001,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local policy=require("priority_policy")
test("Deferred work stays on the native game-thread timer, with an older-loader fallback",function()
    local U=require("ap_util")
    local calls,queued={},{}
    local old_native,old_async,old_game=ExecuteInGameThreadWithDelay,ExecuteWithDelay,ExecuteInGameThread
    ExecuteInGameThreadWithDelay=function(ms,fn) eq(ms,250);queued[#queued+1]=fn;return 42 end
    ExecuteWithDelay=function() error("Unexpected async handoff") end
    eq(U.defer(250,function() calls[#calls+1]="native" end),42)
    eq(#calls,0);queued[1]();eq(calls[1],"native")
    ExecuteInGameThreadWithDelay=nil
    ExecuteWithDelay=function(ms,fn) eq(ms,100);queued={fn} end
    ExecuteInGameThread=function(fn) queued={fn} end
    U.defer(100,function() calls[#calls+1]="fallback" end)
    eq(#calls,1);queued[1]();eq(#calls,1);queued[1]();eq(calls[2],"fallback")
    ExecuteInGameThreadWithDelay,ExecuteWithDelay,ExecuteInGameThread=old_native,old_async,old_game
end)
test("UI text preserves Unicode and repairs invalid bytes before native conversion",function()
    local U=require("ap_util")
    local name=string.rep("A",18).."örest"
    eq(utf8.len(name:sub(1,19)..".."),nil) -- Reproduces the old byte-cut failure.
    eq(U.truncate_text(name,21),string.rep("A",18).."ö..")
    eq(U.truncate_text("拠点の生産ライン",6),"拠点の生..")
    eq(U.truncate_text("🔥🌿⚒ base",5),"🔥🌿⚒..")
    eq(U.clean_text("München / 東京 / 🔥"),"München / 東京 / 🔥")
    eq(U.clean_text("bad"..string.char(255,192,128).."end"),"bad???end")
    eq(U.clean_text("A"..string.char(0).."B"),"A?B")
    eq(U.clean_text("line 1\nline 2\tend"),"line 1\nline 2\tend")
    eq(U.truncate_text("abcdef",2),"..");eq(U.truncate_text("abc",0),"")
    for byte=0,255 do
        local repaired=U.clean_text(string.char(byte))
        checks=checks+1;assert(utf8.len(repaired)~=nil,"unsafe UTF-8 byte "..byte)
    end
end)
local text_reads=0
local text_meta={__eq=function() error("Do not depend on the loader's FText equality binding") end}
local function game_text(value)
    return setmetatable({value=value,type=function() return "FText" end,ToString=function(self)
        text_reads=text_reads+1
        assert(self.value~=nil and self.value~="","Fatal UE4SS empty-FText conversion must be avoided")
        return self.value
    end},text_meta)
end
test("Game localized text never reaches UE4SS's aborting conversion bridge",function()
    local U=require("ap_util")
    local previous=StaticFindObject
    StaticFindObject=function() error("Native FText parameters also use the aborting bridge") end
    eq(U.name(game_text(nil)),"");eq(text_reads,0)
    eq(U.name(game_text("")),"");eq(text_reads,0)
    eq(U.name(game_text("Anubis")),"");eq(text_reads,0)
    eq(U.name(game_text("Jörmuntide")),"");eq(text_reads,0)
    eq(U.name({type=function() return "FString" end,ToString=function() return "My base" end}),"My base")
    eq(U.name({type=function() return "FName" end,ToString=function() return "Salad" end}),"Salad")
    StaticFindObject=previous
end)
test("Parameter wrappers avoid reflected get calls on native values",function()
    local U=require("ap_util")
    local native={type=function() return "UObject" end,get=function() error("Native values must not be unwrapped") end}
    eq(U.unwrap(native),native)
    for _,class in ipairs({"RemoteUnrealParam","LocalUnrealParam"}) do
        eq(U.unwrap({type=function() return class end,get=function() return native end}),native)
    end
    eq(U.unwrap(1),1);eq(U.unwrap(false),false);eq(U.unwrap("test"),"test")
end)
test("Priority order, ties, Off, idle fallback and inheritance",function()
    local skills={[1]=2,[5]=3,[12]=1}
    local p=policy.plan(skills,{[1]=3,[5]=1,[12]=0},{[1]=true,[5]=true},nil)
    eq(p[1],false);eq(p[5],true);eq(p[12],false)
    p=policy.plan(skills,{[1]=1,[5]=1,[12]=0},{[1]=true},nil)
    eq(p[1],true);eq(p[5],true);eq(p[12],false)
    p=policy.plan(skills,{[1]=3,[5]=1,[12]=0},{},nil)
    eq(p[1],true);eq(p[5],true);eq(p[12],false)
    p=policy.plan(skills,{[1]=1,[5]=3,[12]=0},{[5]=true},1)
    eq(p[1],true);eq(p[5],false)
    local base={defaults={[5]=2},pals={a={[5]=4}},original={}}
    eq(policy.get(base,"a",5,true),4);eq(policy.get(base,"b",5,true),2)
    eq(policy.get(base,"b",12,false),0);eq(policy.get(base,"b",1,true),3)
    eq(policy.cycle(1,-1),0);eq(policy.cycle(0,-1),5);eq(policy.cycle(5,1),0)
end)
test("Production yield, refill, recipe change and sample gaps",function()
    local t=require("telemetry").new()
    eq(t:observe("a","ingot",100,3,0),nil)
    local rate
    for i=1,12 do rate=t:observe("a","ingot",100-i,3,i*5) end
    near(rate,36)
    t:baseline("a","ingot",100,60)
    rate=t:observe("a","ingot",99,3,65);near(rate,36)
    eq(t:observe("a","salad",50,1,70),nil)
    eq(t:observe("a","salad",40,1,100),nil)
    eq(#t.stations.a.events,0)
    for i=1,200 do t:push("b",{at=i*5,output=i}) end
    eq(#t.histories.b,121)
    t:prune(1800);eq(t.histories.b,nil);eq(t.stations.a,nil)
end)
test("Food decline, replenishment, empty stores and unknown reads",function()
    local f=require("forecast")
    local h={}
    for t=0,180,5 do h[#h+1]={at=t,food=1000-t} end
    local r=f.food(h,180,820,true)
    eq(r.state,"declining");near(r.net,-60);near(r.minutes,820/60)
    eq(r.projected[#r.projected],0)
    eq(f.food(h,180,0,true).state,"empty")
    eq(f.food(h,180,0,false).state,"unavailable")
    eq(f.food({{at=1,food=90}},1,90,true).state,"measuring")
    for _,p in ipairs(h) do p.food=1000+p.at end
    eq(f.food(h,180,1180,true).state,"growing")
    for _,p in ipairs(h) do p.food=1000 end
    r=f.food(h,180,1000,true);eq(r.state,"balanced");eq(r.minutes,nil)
    h[#h-1].food=nil
    eq(f.food(h,180,1000,true).state,"measuring")
    h={{at=0,food=100},{at=180,food=90}}
    eq(f.food(h,180,90,true).state,"measuring")
    h={}
    for t=0,180,5 do h[#h+1]={at=t,food=1000-t+(t>=150 and 800 or 0)} end
    r=f.food(h,180,h[#h].food,true)
    eq(r.state,"variable");eq(r.minutes,nil);eq(r.projected,nil)
    eq(r.added,795);eq(r.removed,175);near(r.no_delivery_minutes,1620/(175/3))
    h[#h].food_source="newly loaded feed box";r=f.food(h,180,1620,true)
    eq(r.state,"measuring");eq(r.no_delivery_minutes,nil);eq(r.net,nil)
    for _,p in ipairs(h) do p.food_source="same";p.food=p.at<90 and 1000 or 500 end
    r=f.food(h,180,500,true);eq(r.removed,500);eq(r.no_delivery_minutes,nil)
    eq(f.food(h,200,500,true).state,"measuring")
end)

test("Base insights distinguish unknown care, queued work and current-batch estimates",function()
    local insights=require("base_insights")
    local camp={roster_complete=true,forecast={state="growing"},pals={
        {sanity=0.2,food=0.1,health=1,sick=1,dead=false,work=5},
        {sanity=1,dead=false,sick=0},
        {food=0.8,dead=true,sick=0,work=0}},
        producers={{remaining=10,rate=5,yield_count=2,warmup=60,auto=true,status="Producing"},
            {remaining=0,rate=0,auto=true,status="Waiting for resources"},
            {remaining=3,rate=0,warmup=60,status="Producing"}}}
    local s=insights.analyze(camp)
    near(s.sanity,0.6);near(s.fullness,0.45);eq(s.sanity_n,2);eq(s.food_n,2)
    eq(s.hungry,1);eq(s.sick,1);eq(s.down,1);eq(s.low_sanity,1);eq(s.care_unknown,2)
    eq(s.queued,2);eq(s.auto,2);eq(s.waiting,1);eq(s.no_output,1);eq(s.crafts,13)
    eq(s.jobs[1].work,5);eq(s.idle_pals,1);eq(s.unknown_work,1)
    near(insights.queue_minutes(camp.producers[1]),4)
    eq(insights.queue_minutes(camp.producers[2]),nil);eq(insights.queue_minutes(camp.producers[3]),nil)
    eq(s.alert.title,"1 Pal incapacitated");eq(s.alert.view,"Pals");eq(s.alert.filter,"Care")
    eq(insights.matches("Pals","Care",{alert="Hungry"}),true);eq(insights.matches("Pals","Resting",{work=nil}),false)
    camp.forecast={state="empty"};eq(insights.analyze(camp).alert.title,"Feed boxes are empty")
    eq(insights.analyze(camp).alert.mode,"Stores")
    local healthy={roster_complete=true,forecast={state="balanced"},pals={{health=1,sanity=1,food=1,dead=false,sick=0,work=0}},producers=camp.producers}
    eq(insights.care_readable(healthy.pals[1]),true)
    healthy.pals[1].health=nil;eq(insights.care_readable(healthy.pals[1]),false);healthy.pals[1].health=1
    eq(insights.analyze(healthy).alert.title,"1 automatic station waiting to start")
    eq(insights.analyze(healthy).alert.filter,"Waiting")
    eq(insights.matches("Production","Waiting",camp.producers[2]),true);eq(insights.matches("Production","Waiting",camp.producers[1]),false)
    eq(insights.matches("Production","Waiting",{auto=true,status="Waiting for power"}),true)
    healthy.producers={camp.producers[3]}
    eq(insights.analyze(healthy).alert.title,"1 queued station with no observed output")
    healthy.producers={};healthy.pals[1].food=nil
    s=insights.analyze(healthy);eq(s.fullness,nil);eq(s.food_n,0);eq(s.alert.title,"Some Pal readings are unavailable")
    eq(insights.duration(0.3),"<1 min");eq(insights.duration(4),"~4 min");eq(insights.duration(120),"~2.0 hr")
end)
test("Data-only persistence, restart, rollback and corrupt-file protection",function()
    local path=os.tmpname();os.remove(path)
    local store=require("priority_store").new(path)
    local b=store:base("base-123");b.enabled=true;b.defaults[5]=2;b.pals.pal1={[5]=0};b.original.pal1={[1]=false,[5]=true}
    eq(store:save(),true)
    local read=require("priority_store").new(path)
    eq(read.bases["base-123"].original.pal1[1],false)
    eq(read.bases["base-123"].original.pal1[5],true)
    eq(read.bases["base-123"].pals.pal1[5],0)
    eq(read.bases["base-123"].enabled,true)
    eq(read:decode("return os.execute('anything')"),false)
    eq(read:decode("PAP\t1\nP\t../bad\tpal\t1\t5\n"),false)
    b.defaults[5]=1;eq(store:save(),true)
    local f=assert(io.open(path,"w"));f:write("broken");f:close()
    read=require("priority_store").new(path);eq(read.bases["base-123"].defaults[5],2)
    os.remove(path..".bak")
    read=require("priority_store").new(path);eq(read:save(),false)
    os.remove(path);os.remove(path..".bak");os.remove(path..".tmp")
end)
test("Supply outlook checks all ingredients, shared stock, tied limits and output yield",function()
    local insights=require("base_insights")
    local plan=insights.supply_outlook({rate=12,yield_count=3,batch=10,materials={
        {cost=2,base=10,bag=2},{cost=3,base=20,bag=0},{cost=7,base=70,bag=0}}})
    eq(plan.coverage,6);near(plan.minutes,1.5);eq(plan.materials[1].limiting,true);eq(plan.materials[2].limiting,true)
    eq(plan.materials[3].limiting,false)
    eq(plan.materials[1].batch_short,8);eq(plan.materials[2].batch_short,10);eq(plan.materials[3].batch_short,0)
    eq(insights.supply_outlook({rate=10,materials={{cost=2,base=nil,bag=4}}}).minutes,nil)
    eq(insights.supply_outlook({rate=0,materials={{cost=2,base=10,bag=0}}}).minutes,nil)
end)
local address=0
local function object(name,fields)
    address=address+1;local id=address
    local o=fields or {}
    o.IsValid=function() return o.valid~=false end
    o.GetFullName=function() return name end
    o.GetAddress=function() return id end
    return o
end
local function guid(a) return {A=a,B=2,C=3,D=4} end
local U=require("ap_util")
test("Typed GUID identity rejects a full InstanceID and CDOs",function()
    eq(U.guid(guid(1)),"1-2-3-4")
    eq(U.guid({InstanceId=guid(1),PlayerUId=guid(2)}),nil)
    eq(U.guid({A=0,B=0,C=0,D=0}),nil)
    eq(U.live(object("Default__PalBaseCampModel")),false)
end)
local fixture
test("Base placeholders, custom Unicode names and station location labels",function()
    local labels=require("display_labels")
    eq(labels.base("新規生成拠点テンプレート名1(仮)",1),"Base 1")
    eq(labels.base("新規生成拠点テンプレート名2(仮)",2),"Base 2")
    eq(labels.base("None",3),"Base 3");eq(labels.base(" ",4),"Base 4")
    eq(labels.base("東京の拠点",1),"東京の拠点")
    eq(labels.base("  Müller’s kitchen  ",1),"Müller’s kitchen")
    eq(labels.location({x=300,y=400,z=300},{x=0,y=0,z=0}),"5 m from Palbox / 3 m above")
    eq(labels.location(nil,{}),"Location unavailable")
    local old_lookup,old_fname=StaticFindObject,FName
    FName=function(id) return id end
    StaticFindObject=function(path)
        if path:find("Default__BP_PalRichTextDecorator_ItemName_C",1,true) then
            return object("ItemDecorator",{GetTextStringInternal=function(_,context,key)
                eq(context,"kitchen");return key=="Pan" and "Bread" or ""
            end})
        end
    end
    labels.reset();eq(labels.localized("ItemName","Pan","kitchen"),"Bread")
    eq(labels.localized("ItemName","Missing","kitchen"),nil)
    StaticFindObject,FName=old_lookup,old_fname;labels.reset()
end)
test("Loaded guild data, pre-existing objects, weighted food and stable Pal IDs",function()
    local group=guid(11)
    local rank_reads,controller_reads=0,0
    local parameter=object("PalIndividualCharacterParameter",{
        GetGroupId=function() return group end,GetCharacterID=function() return "Anubis" end,
        GetCurrentWorkSuitability=function() return 5 end,GetSanityRate=function() return 0.8 end,
        GetFullStomachRate=function() return 0.2 end,IsDead=function() return false end,
        GetWorkSuitabilityRankWithCharacterRank=function(_,w) rank_reads=rank_reads+1;return w==5 and 4 or 0 end,
        SaveParameter={NickName="Stone",WorkSuitabilityOptionInfo={OffWorkSuitabilityList={}}}})
    local component=object("CharacterParameter",{GetIndividualParameter=function() return parameter end,GetWorkAssign=function() return nil end})
    local actor=object("PalCharacter",{GetCharacterParameterComponent=function() return component end})
    local handle=object("Handle",{TryGetIndividualParameter=function() return parameter end,
        GetIndividualID=function() return {InstanceId=guid(42),PlayerUId=guid(17)} end,TryGetIndividualActor=function() return actor end})
    local slot=object("Slot",{Handle=handle,IsEmpty=function() return false end})
    local container=object("Container",{SlotArray={slot}})
    local director=object("Director",{CharacterContainer=container})
    local camp=object("Base",{GetId=function() return guid(1) end,GetGroupIdBelongTo=function() return group end,
        GetBaseCampName=function() return "Verdant foothills" end,WorkerDirector=director,
        GetTransform=function() return {Translation={X=1000,Y=1000,Z=0}} end})
    local foreign=object("ForeignBase",{GetId=function() return guid(2) end,GetGroupIdBelongTo=function() return guid(99) end})
    local foodslots={}
    for _,food in ipairs({{"Berry",10},{"Salad",2}}) do
        foodslots[#foodslots+1]=object("ItemSlot",{ItemId={StaticId=food[1]},GetStackCount=function() return food[2] end})
    end
    local foodcontainer=object("FoodContainer",{ItemSlotArray=foodslots})
    local module=object("Module",{GetContainer=function() return foodcontainer end})
    local foodbox=object("Foodbox",{GetClass=function() return {GetFName=function() return "PalMapObjectPalFoodBoxModel" end} end,
        GetBaseCampIdBelongTo=function() return guid(1) end,GetItemContainerModule=function() return module end})
    local item_manager=object("ItemManager",{GetStaticItemData=function(_,id)
        return object("Food",{TypeA=8,GetRestoreSatiety=function() return id=="Berry" and 15 or 80 end}) end})
    local utility=object("PalUtility",{GetItemIDManager=function() return item_manager end})
    local build_reads=0
    function utility:GetBuildObjectDataTable()
        build_reads=build_reads+1
        return {GetRowMap=function() return {ActualKitchenBuildId={MapObjectId="CookingStove2"}} end}
    end
    function utility:GetRecipeTechlonogy(id)
        return {UnlockBuildObjects=id=="Product_Cooking_Grade_03" and {"ActualKitchenBuildId"} or {}}
    end
    local function kitchen(id,x)
        return object("Station",{GetClass=function() return {GetFName=function() return "PalMapObjectConvertItemModel" end} end,
            GetBaseCampIdBelongTo=function() return guid(1) end,TryGetMapObjectId=function() return "CookingStove2" end,
            GetInstanceId=function() return guid(id) end,GetCurrentRecipeId=function() return "None" end,
            GetRemainCreateNum=function() return 0 end,GetTransform=function() return {Translation={X=x,Y=1000,Z=0}} end})
    end
    local first,second=kitchen(31,2000),kitchen(32,3000)
    local pc=object("Controller",{Pawn=actor,GetPalPlayerState=function() return {GetTechnologyData=function() return utility end} end})
    U.clear_controller()
    UEHelpers={GetPlayerController=function() controller_reads=controller_reads+1;return pc end}
    FName=function(v) return v end
    StaticFindObject=function() return utility end
    local scans=0
    FindAllOf=function(name)
        assert(name~="PalMapObjectConcreteModelBase","must not enumerate every world object")
        scans=scans+1
        return name=="PalBaseCampModel" and {camp,foreign} or name=="PalMapObjectPalFoodBoxModel" and {foodbox,foodbox}
            or name=="PalMapObjectConvertItemModel" and {second,first} or {}
    end
    NotifyOnNewObject=function(path) assert(not path:find("ConcreteModelBase"),"no broad world-object hook") end
    local data=require("base_data");data.init()
    local s=data.sample({},{},nil,0)
    eq(#s.camps,1);eq(s.camps[1].food_stock,310);eq(s.camps[1].food_complete,true)
    eq(#s.camps[1].food_items,2);eq(s.camps[1].food_items[1].id,"Salad");eq(s.camps[1].food_items[1].count,2)
    eq(s.camps[1].food_items[1].nutrition,160);eq(s.camps[1].food_items[2].nutrition,150)
    eq(s.camps[1].pals[1].id,"42-2-3-4");eq(s.camps[1].pals[1].alert,"Hungry")
    eq(s.camps[1].pals[1].fixed,false);eq(s.camps[1].working,1)
    eq(scans,4);eq(rank_reads,13)
    eq(#s.camps[1].producers,2);eq(s.camps[1].producers[1].station,first)
    eq(s.camps[1].producers[1].station_name,"Electric Kitchen #1")
    eq(s.camps[1].producers[2].station_name,"Electric Kitchen #2")
    eq(s.camps[1].producers[1].location,"10 m from Palbox")
    eq(s.camps[1].producers[1].product,"No recipe selected");eq(build_reads,1)
    data.remember_recipe(second,"Salad")
    local remembered=data.sample({Salad="Salad"},{},nil,0)
    eq(remembered.camps[1].producers[2].recipe_id,"Salad")
    eq(remembered.camps[1].producers[2].last_opened,true)
    eq(remembered.camps[1].producers[1].last_opened,false)
    eq(build_reads,1)
    parameter.SaveParameter.NickName=""
    local localized=game_text(nil)
    function utility:GetDisplayNickName(context,id,unique,out)
        eq(context,parameter);eq(id,"Anubis");eq(unique,"None")
        out.OutNickName="Anubis (localized)"
    end
    local before=text_reads
    eq(data.sample({},{},nil,1).camps[1].pals[1].name,"Anubis (localized)");eq(text_reads,before)
    localized=game_text("Gilded Anubis")
    data.sample({},{},nil,5);eq(scans,4);eq(rank_reads,13);eq(controller_reads,1)
    eq(data.sample({},{},nil,6).camps[1].pals[1].name,"Anubis (localized)");eq(text_reads,before)
    foodcontainer.valid=false
    s=data.sample({},{},nil,10);eq(s.camps[1].food_complete,false)
    eq(s.camps[1].forecast.state,"unavailable")
    foodcontainer.valid=true
    for now=15,180,5 do s=data.sample({},{},nil,now) end
    eq(scans,4);eq(controller_reads,1);eq(rank_reads,52)
    pc.Pawn=nil
    local missing=data.sample({},{},nil,185);eq(#missing.camps,0);eq(missing.warning,"Waiting for your player character.")
    pc.Pawn=actor
    fixture=s
    -- Keep the visual fixture's measured history at its own snapshot time;
    -- later retention tests intentionally evict live telemetry points.
    fixture.camps[1].history={table.unpack(fixture.camps[1].history)}
    local ranks_before=rank_reads
    local lightweight=data.sample({},{},nil,250,false)
    eq(rank_reads,ranks_before);eq(lightweight.camps[1].pals[1].skills[5],4)
    eq(lightweight.camps[1].pals[1].permissions_read,false)
    local advance=data.prepare_sample({},{},nil,251,false,false)
    local n,result=0,nil
    repeat result=advance();n=n+1 until result
    assert(n>=6,"roster and objects must be interruptible between entries")
    eq(result.camps[1].food_stock,310);eq(result.camps[1].pals[1].fixed,nil)
    local campid=result.camps[1].id
    for t=256,381,5 do data.food_sample(campid,t) end
    local idledata=data.sample({},{},nil,386,false)
    eq(idledata.camps[1].forecast.state,"balanced")
    local prior=idledata.camps[1].history[#idledata.camps[1].history-1]
    eq(prior.food,310);eq(prior.working,nil);eq(prior.output,nil)
    data.sample({},{},nil,255,true);eq(rank_reads,ranks_before+13)
    first.GetRemainCreateNum=function() return 5 end
    local fast=data.sample({},{},nil,265,false);eq(fast.camps[1].output_complete,false);eq(fast.camps[1].producers[1].product,"Recipe unavailable")
    parameter.GetFullStomachRate=function() return 0.44 end
    parameter.GetHungerType=function() return 2 end
    parameter.IsSleeping=function() return true end
    parameter.GetCurrentWorkSuitability=function() return 0 end
    parameter.GetHP=function() return {Value=33000} end
    parameter.GetMaxHP_withBuff=function() return {Value=110000} end
    local current=data.sample({},{},nil,390,false).camps[1]
    local pal=current.pals[1]
    eq(pal.alert,"Starving");near(pal.health,0.3);eq(pal.sleeping,true)
    local insights=require("base_insights")
    eq(insights.analyze(current).alert.title,"1 Pal starving")
    eq(insights.analyze(current).low_hp,1);eq(insights.analyze(current).sleeping,1)
    parameter.GetHungerType=function() return 0 end
    parameter.GetFullStomachRate=function() return 0.2 end
    current=data.sample({},{},nil,395,false).camps[1]
    eq(current.pals[1].alert,"Low health");eq(insights.analyze(current).hungry,0)
    parameter.GetMaxHP_withBuff=function() return {Value=0} end
    eq(data.sample({},{},nil,400,false).camps[1].pals[1].health,nil)
    -- Reproduce playing for twenty minutes with Bases closed, past the full
    -- sampler's ten-minute expiry. Background reads must keep the forecast ready
    -- without enumerating Pals, workstations or world objects again.
    local here=camp
    actor.InsideBaseCampCheckComponent={GetInsideBaseCampModel=function() return here end}
    local roster_reads,queue_reads,food_reads=0,0,0
    local is_empty=slot.IsEmpty
    slot.IsEmpty=function(self) roster_reads=roster_reads+1;return is_empty(self) end
    local remaining=first.GetRemainCreateNum
    first.GetRemainCreateNum=function(self) queue_reads=queue_reads+1;return remaining(self) end
    local stack=foodslots[1].GetStackCount
    foodslots[1].GetStackCount=function(self) food_reads=food_reads+1;return stack(self) end
    local scans_before=scans
    for now=405,1605 do data.sample_current_food(now) end
    eq(scans,scans_before);eq(roster_reads,0);eq(queue_reads,0);eq(food_reads,241)
    local resumed=data.sample({},{},nil,1610,false).camps[1]
    eq(resumed.forecast.state,"balanced");eq(resumed.forecast.span,300)
    eq(resumed.forecast.seconds_left,nil)
    local last=resumed.history[#resumed.history-1]
    eq(last.at,1605);eq(last.food,310);eq(last.output,nil);eq(last.working,nil)
    -- Outside/foreign bases never get fabricated measurements. A real absence
    -- or an unreadable container still requires a fresh observation window.
    local reads_before=food_reads
    here=nil;data.sample_current_food(1620);eq(food_reads,reads_before)
    here=foreign;data.sample_current_food(1625);eq(food_reads,reads_before)
    here=camp;data.sample_current_food(1790)
    eq(data.sample({},{},nil,1795,false).camps[1].forecast.state,"measuring")
    for now=1800,1920,5 do data.sample_current_food(now) end
    eq(data.sample({},{},nil,1925,false).camps[1].forecast.state,"balanced")
    foodcontainer.valid=false;data.sample_current_food(1930)
    eq(data.sample({},{},nil,1935,false).camps[1].forecast.state,"unavailable")
    foodcontainer.valid=true;data.sample_current_food(1940)
    eq(data.sample({},{},nil,1945,false).camps[1].forecast.state,"measuring")
end)
test("All dashboard views have unique IDs, bounded geometry and real controls",function()
    local scene=require("overview_scene")
    for _,view in ipairs({"Overview","Trends","Stores","Pals","Production","Priorities","Settings"}) do
        local settings=view=="Settings"
        local nodes=scene.build(fixture,{view=settings and "Production" or ((view=="Trends" or view=="Stores") and "Overview" or view),overview_mode=view,
            batch=settings and {base=fixture.camps[1].id,row={station_name="Electric Kitchen"},count=9999,target=999999} or nil},{bases={},status="Ready"})
        local ids,areas={},{};local buttons=0
        for _,n in ipairs(nodes) do
            eq(ids[n.id],nil,"duplicate node");ids[n.id]=true
            if n.kind=="scroll" then areas[n.id]=n end
            local a=n.parent and assert(areas[n.parent]) or {x=0,y=0,w=1200,content_height=720}
            checks=checks+1;assert(n.x>=a.x and n.y>=a.y and n.x+n.w<=a.x+a.w+0.1 and n.y+n.h<=a.y+a.content_height+0.1,"bounds "..n.id)
            if n.kind=="button" then buttons=buttons+1;checks=checks+1;assert(n.action) end
        end
        checks=checks+1;assert(buttons>=5)
    end
end)
test("Priority runtime requires host authority and confirms restoration",function()
    local path=os.tmpname();os.remove(path)
    local real_store=require("priority_store")
    package.loaded.priority_store={new=function() return real_store.new(path) end}
    package.loaded.priorities=nil
    local sent={}
    local network=object("BaseCampNetwork",{RequestChangeWorkSuitability_ToServer=function(_,id,work,on)
        sent[#sent+1]={id=id,work=work,on=on}
    end})
    local transmitter=object("Transmitter",{GetBaseCamp=function() return network end})
    local pc=object("LocalController",{Transmitter=transmitter})
    U.clear_controller()
    UEHelpers={GetPlayerController=function() return pc end}
    local mode=object("GameMode")
    local gameplay=object("GameplayStatics",{GetGameMode=function() return mode end})
    StaticFindObject=function() return gameplay end
    RegisterHook=function() end
    local priorities=require("priorities");priorities.init(function() end)
    eq(priorities.available(),true)
    local b=priorities.store:base("one");b.enabled=true;b.defaults={[5]=1,[8]=4}
    local pal={id="p",raw_id={InstanceId=guid(10),PlayerUId=guid(2)},skills={[5]=4,[8]=2},
        allowed={[5]=true,[8]=true},permissions_read=true,fixed=false,dead=false,work=5}
    local snap={camps={{id="one",pals={pal}}}}
    priorities.tick(snap,100)
    eq(#sent,1);eq(sent[1].work,8);eq(sent[1].on,false)
    eq(b.original.p[8],true)
    local disk=real_store.new(path);eq(disk.bases.one.original.p[8],true)
    pal.allowed[8]=false
    priorities.tick(snap,105);eq(#sent,1,"already applied must not resend")
    b.enabled=false
    priorities.tick(snap,110);eq(#sent,2);eq(sent[2].on,true)
    eq(b.original.p[8],true,"retain recovery until acknowledged")
    pal.allowed[8]=true
    priorities.tick(snap,115);eq(b.original.p,nil);eq(priorities.has_work(),false)
    eq(priorities.messages.one.text,"Management off; original work permissions restored")
    b.enabled=true;pal.fixed=true
    priorities.tick(snap,120);eq(#sent,2,"fixed assignment untouched")
    pal.fixed=nil
    priorities.tick(snap,125);eq(#sent,2,"unknown assignment untouched")
    pal.fixed=false;mode.valid=false
    priorities.tick(snap,130);eq(#sent,2,"client cannot schedule")
    mode.valid=true
    local save=priorities.store.save;priorities.store.save=function() return false end
    priorities.tick(snap,135);eq(#sent,2,"no writes without a saved recovery baseline")
    priorities.store.save=save
    package.loaded.priority_store=real_store
    os.remove(path);os.remove(path..".bak");os.remove(path..".tmp")
end)
print(string.format("%d suites passed; %d assertions",tests,checks))
