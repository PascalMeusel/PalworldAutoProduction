-- Render actual controls, dispatch their actions through base_stats, then
-- inspect the resulting scene. Storage/authority checks live in workstation.lua.
local checks=0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b)) end
local pc={IsValid=function() return true end,GetAddress=function() return 1 end,GetFullName=function() return "Player" end}
UEHelpers={GetPlayerController=function() return pc end}
local row={key="station",station={},station_name="Electric Kitchen",recipe_id="Salad",product="Salad",remaining=0,status="Idle"}
local sample={at=100,camps={{id="test",label="Test",here=true,pals={},producers={row},food_boxes=0,working=0,alerts=0,output=0,history={}}}}
package.loaded.base_data={init=function() end,reset_world=function() end,sample=function() return sample end}
package.loaded.priorities={init=function() end,has_work=function() return false end,store={bases={}},available=function() return true end}
local nodes,action={},nil
local ui={visible=true,widget=pc,render=function(n) nodes=n;return true end,action=function() return action end}
package.loaded.overview_ui=ui
local stats=require("base_stats")
local batch,target,writes=10,0,0
stats.configure({get_batch_size=function() return batch end,get_stock_target=function() return target end,
    set_batch_size=function(r,count) eq(r,row);batch=count;writes=writes+1;return true,"Saved" end,
    set_stock_target=function(r,count) eq(r,row);target=count;writes=writes+1;return true,"Saved" end})
stats.tick({},{})
local function click(id)
    for _,n in ipairs(nodes) do
        if n.id==id then action=assert(n.action);eq(stats.handle_click(),true);return end
    end
    error("Missing control "..id)
end
local function label(id) for _,n in ipairs(nodes) do if n.id==id then return n.text end end end
action={kind="view",view="Production"};stats.handle_click()
click("batch1");eq(label("batch_value"),"10 crafts");eq(label("target_value"),"Unlimited");eq(writes,0)
click("batch_preset1");eq(batch,1);eq(label("batch_value"),"1 craft")
click("batch_plus");eq(batch,2)
click("batch_preset3");eq(batch,10)
click("target_preset3");eq(target,100);eq(label("target_value"),"100 items")
click("target_minus");eq(target,99)
click("target_preset1");eq(target,0);eq(label("target_value"),"Unlimited")
click("batch_back");eq(label("batch_value"),nil)
click("batch1");eq(label("batch_value"),"10 crafts");eq(label("target_value"),"Unlimited")
action={kind="view",view="Pals"};stats.handle_click()
action={kind="view",view="Production"};stats.handle_click();eq(label("batch_value"),nil)
print(string.format("PASS Production settings controls dispatch, rerender and return to the station list; %d assertions",checks))
