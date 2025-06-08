local food_details = {name = "Rush Food", description = "Mysterious food", type = "keyitem"}

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

function handle_object_interaction(player_id, object_id)
  local area = Net.get_player_area(player_id)
  local object = Net.get_object_by_id(area, object_id)
  local floorCords = {object.x, object.y, object.z}

    if not object or not object.type == "RushRoad" then
        print("Not a rush road")
    end
        if object and object.type == "RushRoad" then
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
        print("player has food")
           Net.question_player(player_id, "Would you like to use rush food?")
        
           Net.exclude_object_for_player(player_id, object_id)
        end
        -- ending clause if we get beyond here we don't care.
    else
        print("Not my responsibility!")
    end
end