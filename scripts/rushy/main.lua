local food_details = {name = "Rush Food", description = "Mysterious food", type = "keyitem"}
local rush_roads = {}
local rush_texture = "/server/assets/rushy/rushy.png"
local rush_animation = "/server/assets/rushy/rushy.anim"

local function handle_item_gen()
  local food = Net.create_item("rush_food", food_details)
  print("made rush food")
  end

handle_item_gen()

function handle_player_connect(player_id)
local player_name = Net.get_player_name(player_id)
if (player_name == "D3str0y3d") then 
    Net.give_player_item(player_id, "rush_food") 
    print(player_name == "D3str0y3d")
    end
end

function find_rush_roads()
 local areas = Net.list_areas()
    --Check every area
    for i, area_id in next, areas do
        area_id = tostring(area_id)
         if not rush_roads[area_id] then
            rush_roads[area_id] = {}
        --Loop over all objects in area, spawning trains for each train object.
        local objects = Net.list_objects(area_id)
            for i, object_id in next, objects do    
                local object = Net.get_object_by_id(area_id, object_id)
                object_id = tostring(object_id)
            if object.type == "Rush Road" then 
                print("rush road in " .. area_id)
            end
            if object.custom_properties.Next1 ~= nil then
            local next1 = object.custom_properties.Next1
            local nextobject = Net.get_object_by_id(area_id, next1)
            print(object.custom_properties.Next1)
            print(nextobject.custom_properties.Name)
        end
        end
    end
end
end

find_rush_roads()

function summon_rush_roads()
end

function handle_object_interaction(player_id, object_id)
  local area = Net.get_player_area(player_id)
  local object = Net.get_object_by_id(area, object_id)
  local floorCords = {object.x, object.y, object.z}

    if not object or not object.type == "Rush Road" then
        print("Not a rush road")
    end
        if object and object.type == "Rush Road" then
        print("This is a rush road")
        local player_items = Net.get_player_items(player_id)
        print(player_items)
        local index = 0
        for i=#player_items, 1, -1 do
            index = i
            if (player_items[i] == "rush_food") then
            print("Loop " ..index.. ": "..player_items[i])
        break    
        end
        end
        if (player_items[index] ~= nil) then
            local y_adjust = object.y + 0.3
            local x_adjust = object.x + .15
            local windup_keyframes = {properties = { {property = "Animation", value = "WIND_UP"},}, duration = 5 }
        print("player has food")

           --Net.question_player(player_id, "Would you like to use rush food?")
           
           Net.create_bot("rush", { "Rush", area, true, rush_texture, rush_animation, "IDLE_D", object.x, object.y, object.z, "Down", false })
           Net.move_bot("rush", object.x, y_adjust, object.z)
           Net.animate_bot_properties("rush", windup_keyframes)
           --Net.exclude_object_for_player(player_id, object_id)
        end
        -- ending clause if we get beyond here we don't care.
    else
        print("Not my responsibility!")
    end
end