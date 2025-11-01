local logger         = require('/scripts/debug-logger/main')
local json           = require("scripts/libs/json")
-- Variable setup
local cleared_paths  = {}
local food_details   = { name = "Rush Food", description = "Mysterious food", type = "keyitem" }
local rush_roads     = {}
local rush_texture   = "/server/assets/rushy/rushy.png"
local rush_animation = "/server/assets/rushy/rushy.anim"

function async(p)
    local co = coroutine.create(p)
    return Async.promisify(co)
end

--Shorthand for await
function await(v) return Async.await(v) end

local function handle_item_gen()
    local food = Net.create_item("rush_food", food_details)
    DBGLogger("Rushy", Level.information,
        "Details :" .. json.encode(food_details))
end

handle_item_gen()

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
                    rush_roads[area_id] = object
                    print("Rush road added to table!")
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

function handle_player_connect(player_id)
    local player_name = Net.get_player_name(player_id)
    if (player_name == "D3str0y3d") then
        Net.give_player_item(player_id, "rush_food")
        print(player_name == "D3str0y3d")
    end
    if cleared_paths[player_id] ~= true then
        return
    else
        if cleared_paths[player_id] == true then
            Net.include_actor_for_player(player_id, "rush")
            Net.create_bot("rush",
                {
                    name = "Rush",
                    area_id = "default",
                    warp_in = true,
                    texture_path = rush_texture,
                    animation_path =
                        rush_animation,
                    animation = "FED_DR",
                    x = rush_roads["default"].x + .5,
                    y = rush_roads["default"].y + .5,
                    z =
                        rush_roads["default"].z - 1,
                    solid = false
                })
            --Net.animate_bot("rush", "FED_DR", true)
            Net.exclude_object_for_player(player_id, rush_roads["default"].id)
        end
    end
end

local function summon_rush(player_id)
    Net.create_bot("rush",
        {
            name = "Rush",
            area_id = "default",
            warp_in = true,
            texture_path = rush_texture,
            animation_path =
                rush_animation,
            animation = "IDLE_D",
            x = rush_roads["default"].x + .2,
            y = rush_roads["default"].y + .2,
            z =
                rush_roads["default"].z - 1,
            solid = false
        })
    Net.include_actor_for_player(player_id, "rush")
    Net.animate_bot("rush", "IDLE_D", true)
    local keyframes = { { properties = { { property = "Animation", value = "IDLE_D" }, { property = "X", ease = "In", value = (rush_roads["default"].x + .2) }, { property = "Y", ease = "In", value = (rush_roads["default"].y + .2) } }, duration = 1.0 } }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "WIND_UP" }, { property = "X", ease = "In", value = (rush_roads["default"].x - .2) }, { property = "Y", ease = "In", value = (rush_roads["default"].y - .2) } }, duration = 0.2 }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "LAUNCH" }, { property = "X", ease = "In", value = (rush_roads["default"].x - .4) }, { property = "Y", ease = "In", value = (rush_roads["default"].y - .4) } }, duration = 0.2 }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "In", value = (rush_roads["default"].x - .6) }, { property = "Y", ease = "In", value = (rush_roads["default"].y - .6) } }, duration = 0.2 }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (rush_roads["default"].x - .2) }, { property = "Y", ease = "Out", value = (rush_roads["default"].y - .2) } }, duration = 0.2 }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (rush_roads["default"].x + .2) }, { property = "Y", ease = "Out", value = (rush_roads["default"].y + .2) } }, duration = 0.2 }
    keyframes[#keyframes + 1] = { properties = { { property = "Animation", value = "FED_DR" }, { property = "X", ease = "Out", value = (rush_roads["default"].x + .5) }, { property = "Y", ease = "Out", value = (rush_roads["default"].y + .5) } }, duration = 0.2 }
    Net.animate_bot_properties("rush", keyframes)
    Net.exclude_object_for_player(player_id, rush_roads["default"].id)
    cleared_paths[player_id] = true
end

function handle_textbox_response(player_id, response)
    if response == 0 then
        return
    else
        summon_rush(player_id)
    end
end

function handle_object_interaction(player_id, object_id)
    local area = Net.get_player_area(player_id)
    local object = Net.get_object_by_id(area, object_id)
    local floorCords = { object.x, object.y, object.z }

    if not object or not object.type == "Rush Road" then
        print("Not a rush road")
    end
    if object and object.type == "Rush Road" then
        print("This is a rush road")
        local player_items = Net.get_player_items(player_id)
        print(player_items)
        local index = 0
        for i = #player_items, 1, -1 do
            index = i
            if (player_items[i] == "rush_food") then
                print("Loop " .. index .. ": " .. player_items[i])
                break
            end
        end
        if (player_items[index] ~= nil) then
            print("player has food")
            Net.question_player(player_id, "Would you like to use rush food?")
        end
        -- ending clause if we get beyond here we don't care.
    else
        print("Not my responsibility!")
    end
end
