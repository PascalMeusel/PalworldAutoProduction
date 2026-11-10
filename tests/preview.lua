local camp={id="preview",label="Verdant foothills",pals={},producers={},roster_complete=true,working=11,alerts=2,
    food_stock=1900,food_boxes=2,food_complete=true,output=42,output_complete=true,history={}}
local names={"Anubis","Jormuntide","Lyleen","Orserk","Wumpo Botan","Jormuntide Ignis","Frostallion","Verdash","Digtoise","Petallia","Reptyro","Beegarde","Tanzee","Elizabee"}
camp.here=true
camp.food_items={{name="Salad",count=15,each=84,nutrition=1260},{name="Baked Berries",count=25,each=21,nutrition=525},{name="Red Berries",count=7,each=15,nutrition=105},{name="Small ration",count=1,each=10,nutrition=10}}
for i,name in ipairs(names) do
    local p={id="pal"..i,name=name,work=i<12 and (i-1)%13+1 or 0,working=i<12,sanity=i==4 and 0.31 or 0.8,food=i==8 and 0.18 or 0.91,
        skills={[5]=4,[8]=3,[12]=2,[i%13+1]=2},allowed={},fixed=i==2,dead=false,sick=0}
    p.health=i==8 and 0.71 or 1
    if i==4 then p.alert="Low sanity" elseif i==8 then p.alert="Hungry";p.hungry=true end
    p.sleeping=i==14
    camp.pals[i]=p
end
local stations={"Electric Furnace","Sphere Assembly Line II","Electric Kitchen #1","Production Assembly Line II","Electric Kitchen #2"}
for i,name in ipairs({"Refined Ingot","Pal Sphere","Salad","Carbon Fiber","No recipe selected"}) do
    camp.producers[i]={key=tostring(i),station_name=stations[i],location=(i*4).." m from Palbox",last_opened=i==3,
        product=name,recipe_id=i==5 and "" or name,remaining=i==5 and 0 or 15+i*3,rate=i<5 and 6+i*2 or nil,auto=i~=2 and i~=5,status=i~=2 and i~=5 and "Producing" or "Idle"}
end
for i=0,120 do
    camp.history[#camp.history+1]={at=i*5,output=34+math.sin(i/6)*7+i/15,working=9+math.floor(math.sin(i/8)*2),food=2500-i*5}
end
camp.forecast=require("forecast").food(camp.history,600,1900,true)
local other={id="mine",label="Obsidian quarry",pals={},producers={},alerts=0}
local store={bases={preview={enabled=true,defaults={[5]=1,[12]=2},pals={pal1={[8]=2}},original={}}},status="Priorities active; fixed assignments stay with the game"}
store.afk={enabled=true,status="Not hungry",meals=3}
local picker={base="preview",key="3",name="Electric Kitchen #1",location="12 m from Palbox",group=1,choices={}}
for _,label in ipairs({"Baked Berries","Baked Mushroom","Bread","Broiled Dumud","Cake","Carbonara","Chikipi Sauté","Pancake","Pizza","Salad"}) do
    picker.choices[#picker.choices+1]={id=label,label=label,yield_count=1}
end
local plan={at=600,base="preview",key="3",product="Salad",recipe="Salad",station="Electric Kitchen #1",batch=10,
    craftable=405,yield_count=1,rate=6,materials={{id="Lettuce",name="Lettuce",base=845,bag=0,cost=2},
    {id="Tomato",name="Tomato",base=810,bag=0,cost=2}}}
require("base_insights").supply_outlook(plan)
return {snapshot={at=600,camps={camp,other}},priorities=store,picker=picker,plan=plan}
