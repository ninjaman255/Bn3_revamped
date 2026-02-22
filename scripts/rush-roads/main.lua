local json           = require("scripts/libs/json")   -- provided json.lua
local Utility        = require("scripts/utils/utility") -- contains EventEmitter and Async

-- Variable setup
        -- legacy (may be deprecated)
local rush_roads     = {}          -- rush_roads[area_id][road_id] = { id, x, y, z, custom_properties, linked_object, group_id, bot_name }
local player_road_state = {}       -- in‑memory active group (cleared on server restart)
local any_player = {}              -- tracks online players (key = player_id, value = "Online")
local player_temp_bots = {}        -- player_temp_bots[player_id][area_id][road_id] = bot_name

-- Persistent data storage
local data_file = "scripts/rush-roads/data.json"
local player_data = {}              -- key = player secret, value = { food = number, cleared = { [area_id] = { [road_id] = true } } }

-- NEW TABLES FOR BOT PRESSURE PLATE
local bot_occupants = {}            -- [bot_name] = { players = { [player_id] = true }, road = road_ref }
local player_last_tile = {}         -- [player_id] = { area = area_id, x = tile_x, y = tile_y }
local player_area = {}              -- [player_id] = current area
local rush_roads_by_tile = {}       -- [area][tile_x][tile_y] = road_id

-- Custom event emitter for tile enter/exit
local tile_events = Utility.EventEmitter.new()

function async(p)
    local co = coroutine.create(p)
    return Async.promisify(co)
end

function await(v) return Async.await(v) end

-- Convert any numeric road IDs in loaded data to strings
local function sanitize_data()
    for secret, pdata in pairs(player_data) do
        if pdata.cleared then
            for area_id, roads in pairs(pdata.cleared) do
                local new_roads = {}
                for road_id, val in pairs(roads) do
                    new_roads[tostring(road_id)] = val
                end
                pdata.cleared[area_id] = new_roads
            end
        end
    end
end

-- Load existing data from file (asynchronously)
local function load_data()
    Async.read_file(data_file).and_then(function(content)
        if content and content ~= "" then
            local ok, decoded = pcall(json.decode, content)
            if ok and type(decoded) == "table" then
                player_data = decoded
                sanitize_data()   -- ensure all road IDs are strings
                print("[Rushy] Loaded persistent data from " .. data_file)
            else
                print("[Rushy] Failed to decode data.json, starting fresh")
                player_data = {}
            end
        else
            print("[Rushy] No existing data file or empty, starting fresh")
            player_data = {}
        end
    end)
end

-- Save current data to file
local function save_data()
    local encoded = json.encode(player_data, true)  -- pretty print
    Async.write_file(data_file, encoded)
end

-- Load data at startup (asynchronous; will populate player_data when ready)
load_data()

-- Standalone item quantity tracking (in‑memory mirror of persistent food count)
local player_item_counts = {}      -- player_item_counts[player_id][base_food_id] = count

-- Rush Food base definition
local base_food_name    = "Rush Food"
local base_food_desc    = "Mysterious food"   -- will be overwritten dynamically
local base_food_type    = "keyitem"
local base_food_id      = "rush_food"   -- base part, we'll append player_id

-- Helper: generate player‑specific item ID and name (name is now constant)
local function get_player_item_ids(player_id)
    local item_id = base_food_id .. "_" .. tostring(player_id)
    local item_name = base_food_name
    return item_id, item_name
end

-- Ensure the player has exactly one key item reflecting their current count
local function update_player_food_item(player_id)
    local count = player_item_counts[player_id] and player_item_counts[player_id][base_food_id] or 0
    local item_id, item_name = get_player_item_ids(player_id)

    -- Remove any existing item with this player‑specific ID
    while true do
        local removed = Net.remove_player_item(player_id, item_id)
        if not removed then break end
    end

    if count > 0 then
        local item_details = {
            name = item_name,
            description = "You have " .. count .. " Rush Food.",
            type = base_food_type
        }
        Net.create_item(item_id, item_details)
        Net.give_player_item(player_id, item_id)
    end
end

-- Give food to a player (increment count, update persistent data)
local function give_food(player_id, amount)
    amount = amount or 1
    local secret = Net.get_player_secret(player_id)
    if not player_data[secret] then
        player_data[secret] = { food = 0, cleared = {} }
    end
    player_data[secret].food = (player_data[secret].food or 0) + amount
    save_data()

    if not player_item_counts[player_id] then
        player_item_counts[player_id] = {}
    end
    player_item_counts[player_id][base_food_id] = player_data[secret].food
    update_player_food_item(player_id)
end

-- Remove food from a player (decrement count, update persistent data)
-- Returns remaining count, or -1 if not enough.
local function remove_food(player_id, amount)
    amount = amount or 1
    local secret = Net.get_player_secret(player_id)
    local current = (player_data[secret] and player_data[secret].food) or 0
    if current < amount then
        return -1
    end
    local new_count = current - amount
    player_data[secret].food = new_count
    save_data()

    if new_count == 0 then
        player_item_counts[player_id][base_food_id] = nil
    else
        player_item_counts[player_id][base_food_id] = new_count
    end
    update_player_food_item(player_id)
    return new_count
end

-- Get current food count for a player (from persistent data)
local function count_food(player_id)
    local secret = Net.get_player_secret(player_id)
    return (player_data[secret] and player_data[secret].food) or 0
end

-- Helper: get the size of a group given area and group_id
local function get_group_size(area_id, group_id)
    if not group_id then return 1 end
    local count = 0
    for _, road in pairs(rush_roads[area_id] or {}) do
        if road.group_id == group_id then
            count = count + 1
        end
    end
    return count
end

-- Helper: make an actor visible only to one player, exclude for all others
local function exclude_actor_for_all_others(actor_name, owner_player_id)
    for pid, _ in pairs(any_player) do
        if pid ~= owner_player_id then
            Net.exclude_actor_for_player(pid, actor_name)
        end
    end
    -- ensure owner can see it (in case it was excluded earlier)
    Net.include_actor_for_player(owner_player_id, actor_name)
end

local rush_texture   = "/server/assets/rush-roads/rushy.png"
local rush_animation = "/server/assets/rush-roads/rushy.anim"
local OFFMAP_X = -1000
local OFFMAP_Y = -1000

-- Group roads in an area based on cardinal adjacency (up, down, left, right) within one tile
local function group_rush_roads_in_area(area_id)
    local roads = rush_roads[area_id]
    if not roads then return end

    local road_ids = {}
    for id, _ in pairs(roads) do
        table.insert(road_ids, id)
    end

    local visited = {}
    local group_counter = 0

    local function dfs(start_id, group_id)
        local stack = {start_id}
        visited[start_id] = true
        roads[start_id].group_id = group_id

        while #stack > 0 do
            local current_id = table.remove(stack)
            local current = roads[current_id]
            local cx = math.floor(current.x + 0.5)
            local cy = math.floor(current.y + 0.5)

            for _, other_id in ipairs(road_ids) do
                if not visited[other_id] then
                    local other = roads[other_id]
                    local ox = math.floor(other.x + 0.5)
                    local oy = math.floor(other.y + 0.5)

                    local dx = math.abs(cx - ox)
                    local dy = math.abs(cy - oy)

                    if (dx == 1 and dy == 0) or (dx == 0 and dy == 1) then
                        visited[other_id] = true
                        other.group_id = group_id
                        table.insert(stack, other_id)
                    end
                end
            end
        end
    end

    for _, id in ipairs(road_ids) do
        if not visited[id] then
            group_counter = group_counter + 1
            dfs(id, group_counter)
        end
    end

    print("Grouped " .. #road_ids .. " rush roads in area " .. area_id .. " into " .. group_counter .. " groups (cardinal adjacency)")
end

function find_rush_roads()
    local areas = Net.list_areas()
    for _, area_id in next, areas do
        area_id = tostring(area_id)
        if not rush_roads[area_id] then
            rush_roads[area_id] = {}
            local objects = Net.list_objects(area_id)
            for _, object_id in next, objects do
                local object = Net.get_object_by_id(area_id, object_id)
                if object.type == "Rush Road" then
                    print("rush road in " .. area_id)

                    rush_roads[area_id][object.id] = {
                        id = object.id,
                        x = object.x,
                        y = object.y,
                        z = object.z,
                        custom_properties = object.custom_properties,
                        linked_object = nil,
                        group_id = nil,
                        bot_name = nil   -- will be set if a linked object exists
                    }

                    -- Attach linked object if present and create a permanent bot at its location
                    local linked_id = object.custom_properties["Rush Object"]
                    if linked_id then
                        local linked_obj = Net.get_object_by_id(area_id, linked_id)
                        if linked_obj then
                            -- Store linked object info for position reference
                            rush_roads[area_id][object.id].linked_object = {
                                id = linked_obj.id,
                                x = linked_obj.x,
                                y = linked_obj.y,
                                z = linked_obj.z,
                                type = linked_obj.type,
                                custom_properties = linked_obj.custom_properties
                            }

                            -- Determine animation based on road's Direction property
                            local direction = object.custom_properties["Direction"] or "Down Left"
                            local anim_state
                            if direction == "Down Right" then
                                anim_state = "FED_DR"
                            elseif direction == "Down Left" then
                                anim_state = "FED_DL"
                            else
                                anim_state = "IDLE_D"  -- fallback
                            end

                            -- Create a permanent bot at the linked object's location
                            local bot_name = "rush_bot_" .. area_id .. "_" .. object.id
                            local bot_x = linked_obj.x - 0.5
                            local bot_y = linked_obj.y - 0.5
                            local success, err = pcall(Net.create_bot, bot_name, {
                                name = "Rush Bot",
                                area_id = area_id,
                                warp_in = true,
                                texture_path = rush_texture,
                                animation_path = rush_animation,
                                animation = anim_state,
                                x = bot_x,
                                y = bot_y,
                                z = linked_obj.z - 1,
                                solid = false
                            })
                            if success then
                                rush_roads[area_id][object.id].bot_name = bot_name
                                -- store original X and Y for pressure plate effect
                                rush_roads[area_id][object.id].original_x = bot_x
                                rush_roads[area_id][object.id].original_y = bot_y

                                -- Initialize bot_occupants entry with road reference
                                bot_occupants[bot_name] = {
                                    players = {},
                                    road = rush_roads[area_id][object.id]
                                }

                                print("Created rush bot " .. bot_name .. " for road " .. object.id)
                            else
                                print("Failed to create rush bot for road " .. object.id .. ": " .. tostring(err))
                            end
                        else
                            print("Warning: Rush Object " .. tostring(linked_id) .. " not found in area " .. area_id)
                        end
                    end

                    print("Rush road added to table!")
                end
            end
            group_rush_roads_in_area(area_id)
        end
    end
end

find_rush_roads()

-- Build tile index for quick lookup
local function build_tile_map()
    for area_id, roads in pairs(rush_roads) do
        rush_roads_by_tile[area_id] = rush_roads_by_tile[area_id] or {}
        for road_id, road in pairs(roads) do
            local tx = math.floor(road.x + 0.5)   -- road.x is likely integer, but floor for safety
            local ty = math.floor(road.y + 0.5)
            rush_roads_by_tile[area_id][tx] = rush_roads_by_tile[area_id][tx] or {}
            rush_roads_by_tile[area_id][tx][ty] = road_id
        end
    end
end
build_tile_map()

-- Clean up any existing rush state for a player (remove bots) – in‑memory only
local function cleanup_player_state(player_id)
    local state = player_road_state[player_id]
    if state then
        for road_id, bot_name in pairs(state.roads) do
            Net.remove_bot(bot_name)
            -- Do NOT unhide the road – it stays hidden after clearing
        end
        player_road_state[player_id] = nil
    end
end

-- Hide all roads that this player has cleared in the given area
local function hide_cleared_roads(player_id, area_id)
    local secret = Net.get_player_secret(player_id)
    local cleared = player_data[secret] and player_data[secret].cleared
    if cleared and cleared[area_id] then
        for road_id, _ in pairs(cleared[area_id]) do
            Net.exclude_object_for_player(player_id, road_id)   -- road_id is already a string
        end
    end
end

-- Update visibility of permanent bots based on cleared status
local function update_bot_visibility_for_player(player_id, area_id)
    local secret = Net.get_player_secret(player_id)
    local cleared = player_data[secret] and player_data[secret].cleared
    local roads = rush_roads[area_id]
    if not roads then return end

    for road_id, road in pairs(roads) do
        local road_id_str = tostring(road_id)
        local is_cleared = cleared and cleared[area_id] and cleared[area_id][road_id_str]
        if road.bot_name then
            if is_cleared then
                Net.include_actor_for_player(player_id, road.bot_name)
            else
                Net.exclude_actor_for_player(player_id, road.bot_name)
            end
        end
    end
end

-- Called when player changes area (also on initial connect)
function handle_player_transfer(player_id)
    local area = Net.get_player_area(player_id)
    hide_cleared_roads(player_id, area)
    update_bot_visibility_for_player(player_id, area)
end

-- Create temporary animation bots for a player for all roads
local function create_temp_bots_for_player(player_id)
    if player_temp_bots[player_id] then return end  -- already created
    player_temp_bots[player_id] = {}

    for area_id, roads in pairs(rush_roads) do
        player_temp_bots[player_id][area_id] = {}
        for road_id, road in pairs(roads) do
            local bot_name = "rush_temp_" .. player_id .. "_" .. area_id .. "_" .. road_id
            local success, err = pcall(Net.create_bot, bot_name, {
                name = "Rush Temp",
                area_id = area_id,
                warp_in = true,
                texture_path = rush_texture,
                animation_path = rush_animation,
                animation = "IDLE_D",
                x = OFFMAP_X,
                y = OFFMAP_Y,
                z = road.z,
                solid = false
            })
            if success then
                -- Hide from everyone except this player
                exclude_actor_for_all_others(bot_name, player_id)
                player_temp_bots[player_id][area_id][road_id] = bot_name
                print("Created temp bot " .. bot_name .. " for player " .. player_id)
            else
                print("Failed to create temp bot for player " .. player_id .. ", road " .. road_id .. ": " .. tostring(err))
            end
        end
    end
end

-- Remove temporary bots for a player
local function remove_temp_bots_for_player(player_id)
    if not player_temp_bots[player_id] then return end
    for area_id, roads in pairs(player_temp_bots[player_id]) do
        for road_id, bot_name in pairs(roads) do
            Net.remove_bot(bot_name)
        end
    end
    player_temp_bots[player_id] = nil
end

Net:on("player_connect",function(event)
    local player_id = event.player_id
    local secret = Net.get_player_secret(player_id)
    local player_name = Net.get_player_name(player_id)

    -- Mark player online
    any_player[player_id] = "Online"

    -- Load persistent data for this player
    if not player_data[secret] then
        player_data[secret] = { food = 0, cleared = {} }
    end

    -- Sync in‑memory count with persistent data
    if not player_item_counts[player_id] then
        player_item_counts[player_id] = {}
    end
    player_item_counts[player_id][base_food_id] = player_data[secret].food
    update_player_food_item(player_id)

    -- Special case: D3str0y3d gets 6 food on connect
    if player_name == "D3str0y3d" then
        give_food(player_id, 6)
        print("Gave Rush Food to D3str0y3d")
    end

    -- Create temporary animation bots for this player (one per road)
    create_temp_bots_for_player(player_id)

    -- Hide cleared roads and update bot visibility in current area
    handle_player_transfer(player_id)

    -- Note: active rush state is not restored; cleared roads will show bots immediately
end)

Net:on("player_join", function (event)
    local player_id = event.player_id
    any_player[player_id] = "Online"
end)

Net:on("player_disconnect", function (event)
    local player_id = event.player_id

    -- Remove player from any bot they were standing on
    local last = player_last_tile[player_id]
    if last then
        local area = last.area
        local tx = last.x
        local ty = last.y
        local road_id = rush_roads_by_tile[area] and rush_roads_by_tile[area][tx] and rush_roads_by_tile[area][tx][ty]
        if road_id then
            local road = rush_roads[area] and rush_roads[area][road_id]
            if road and road.bot_name then
                -- Emit exit event (this player is leaving)
                tile_events:emit("player_exited_tile", {
                    player_id = player_id,
                    area = area,
                    tile_x = tx,
                    tile_y = ty,
                    road_id = road_id,
                    bot_name = road.bot_name
                })
            end
        end
        player_last_tile[player_id] = nil
    end
    player_area[player_id] = nil

    any_player[player_id] = nil
    cleanup_player_state(player_id)
    player_item_counts[player_id] = nil
    remove_temp_bots_for_player(player_id)
end)

local function summon_rush(player_id, area_id, object_id, required_amount)
    -- Lock player input immediately
    Net.lock_player_input(player_id)

    -- Consume the required amount of Rush Food
    local remaining = remove_food(player_id, required_amount)
    if remaining < 0 then
        print("Error: failed to remove Rush Food (insufficient)")
        Net.unlock_player_input(player_id)
        return
    end

    local road = rush_roads[area_id] and rush_roads[area_id][object_id]
    if not road then
        print("Error: road not found in summon_rush")
        Net.unlock_player_input(player_id)
        return
    end

    -- Clean up any previously active rush for this player (in‑memory)
    cleanup_player_state(player_id)

    local group_id = road.group_id
    if not group_id then
        print("Warning: road has no group, treating as solo")
    end

    local roads_in_group = {}
    for id, r in pairs(rush_roads[area_id]) do
        if group_id and r.group_id == group_id then
            roads_in_group[id] = r
        elseif not group_id and id == object_id then
            roads_in_group[id] = r
        end
    end

    -- Mark all these roads as cleared for this player (persistent)
    local secret = Net.get_player_secret(player_id)
    if not player_data[secret].cleared then
        player_data[secret].cleared = {}
    end
    if not player_data[secret].cleared[area_id] then
        player_data[secret].cleared[area_id] = {}
    end
    for id, _ in pairs(roads_in_group) do
        player_data[secret].cleared[area_id][tostring(id)] = true   -- store as string
    end
    save_data()

    -- Generate a unique sequence number for this animation
    local seq = (player_road_state[player_id] and player_road_state[player_id].seq or 0) + 1

    local new_state = {
        area = area_id,
        group_id = group_id,
        seq = seq,
        roads = {}
    }

    for id, r in pairs(roads_in_group) do
        local x = r.x + 0.5
        local y = r.y + 0.5
        local bot_name = player_temp_bots[player_id][area_id][id]   -- get pre-created temp bot
        if not bot_name then
            print("Error: temp bot not found for player " .. player_id .. ", road " .. id)
            -- fallback: create a new one on the fly (shouldn't happen)
            bot_name = "rush_" .. area_id .. "_" .. object_id .. "_" .. id .. "_" .. player_id
            Net.create_bot(bot_name, {
                name = "Rush",
                area_id = area_id,
                warp_in = true,
                texture_path = rush_texture,
                animation_path = rush_animation,
                animation = "IDLE_D",
                x = OFFMAP_X,
                y = OFFMAP_Y,
                z = r.z,
                solid = false
            })
            exclude_actor_for_all_others(bot_name, player_id)
        end

        -- Move bot to road location instantly (zero-duration keyframe)
        local move_in_keyframes = {
            { properties = { { property = "X", value = x }, { property = "Y", value = y } }, duration = 0 }
        }
        Net.animate_bot_properties(bot_name, move_in_keyframes)

        -- Now start the full animation sequence
        local keyframes = {
            { properties = { { property = "Animation", value = "IDLE_D" }, { property = "X", ease = "In", value = x }, { property = "Y", ease = "In", value = y } }, duration = 1.0 },
            { properties = { { property = "Animation", value = "WIND_UP" }, { property = "X", ease = "In", value = (x - .2) }, { property = "Y", ease = "In", value = (y - .2) } }, duration = 0.1 },
            { properties = { { property = "Animation", value = "LAUNCH" }, { property = "X", ease = "In", value = (x - .4) }, { property = "Y", ease = "In", value = (y - .4) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "In", value = (x - .6) }, { property = "Y", ease = "In", value = (y - .6) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x - .8) }, { property = "Y", ease = "Out", value = (y - .8) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x - 1) }, { property = "Y", ease = "Out", value = (y - 1) } }, duration = 1.0 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x) - .8}, { property = "Y", ease = "Out", value = (y - .8) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x) - .6}, { property = "Y", ease = "Out", value = (y - .6) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x) - .4}, { property = "Y", ease = "Out", value = (y - .4) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x) - .2}, { property = "Y", ease = "Out", value = (y - .2) } }, duration = 0.1 },
            { properties = { { property = "Animation", value = "SPIN" }, { property = "X", ease = "Out", value = (x)}, { property = "Y", ease = "Out", value = (y) } }, duration = 0.2 },
            { properties = { { property = "Animation", value = "END" }, { property = "X", ease = "Out", value = (x) }, { property = "Y", ease = "Out", value = (y) } }, duration = 0.2 }
        }

        Net.animate_bot_properties(bot_name, keyframes)
        -- Do NOT exclude the road object yet – wait until after animation
        -- Net.exclude_object_for_player(player_id, id)   -- removed from here

        new_state.roads[id] = bot_name
    end

    player_road_state[player_id] = new_state

    -- After animation, move bots back off‑map, show permanent bots, hide road objects, and unlock input
    async(function()
        await(Async.sleep(3.6))  -- total animation duration

        -- Only proceed if this animation is still the active one for the player
        local current_state = player_road_state[player_id]
        if current_state and current_state.seq == seq then
            if Net.get_player_name(player_id) then
                for id, bot_name in pairs(new_state.roads) do
                    -- Move temp bot back off‑map
                    local move_out_keyframes = {
                        { properties = { { property = "X", value = OFFMAP_X }, { property = "Y", value = OFFMAP_Y } }, duration = 0 }
                    }
                    Net.animate_bot_properties(bot_name, move_out_keyframes)

                    -- Show the permanent bot for this road if it exists
                    local road = rush_roads[area_id] and rush_roads[area_id][id]
                    if road and road.bot_name then
                        Net.include_actor_for_player(player_id, road.bot_name)
                    end

                    -- Finally, hide the road object itself for this player
                    Net.exclude_object_for_player(player_id, id)
                end
                Net.unlock_player_input(player_id)
            else
                -- Player disconnected, but bots are per‑player and will be cleaned up on disconnect
                -- No need to move them, they'll be removed.
            end
            player_road_state[player_id] = nil
        else
            -- This animation was superseded; do nothing (bots already moved by newer animation)
        end
    end)
end

Net:on("object_interaction", function (event)
    local player_id = event.player_id
    local object_id = event.object_id
    local area = Net.get_player_area(player_id)
    local object = Net.get_object_by_id(area, object_id)

    if not object or object.type ~= "Rush Road" then
        print("Not a rush road")
        return
    end

    print("This is a rush road")

    -- Determine the group and its size
    local road_data = rush_roads[area] and rush_roads[area][object.id]
    if not road_data then
        print("Error: road data not found")
        return
    end

    local group_id = road_data.group_id
    local group_size = get_group_size(area, group_id)
    print("Group size: " .. group_size)

    -- Get current food count from persistent data
    local food_count = count_food(player_id)
    print("Player has " .. food_count .. " Rush Food")

    if food_count >= group_size then
        async(function()
            local response = await(Async.question_player(player_id, "Would you like to use " .. group_size .. " Rush Food to activate this group?"))
            if response == 0 then
                return
            else
                summon_rush(player_id, area, object.id, group_size)
            end
        end)
    else
        Net.message_player(player_id, "You don't have enough Rush Food...")
    end
end)

-- ============================================================================
-- EVENT-DRIVEN PRESSURE PLATE LOGIC (with tick verification)
-- ============================================================================

-- Helper to count entries in a dictionary table
local function table_count(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Handle player entering a bot tile
tile_events:on("player_entered_tile", function(event)
    local player_id = event.player_id
    local bot_name = event.bot_name
    local area = event.area
    local road_id = event.road_id
    local tile_x = event.tile_x
    local tile_y = event.tile_y

    local occ = bot_occupants[bot_name]
    if occ then
        if not occ.players[player_id] then
            occ.players[player_id] = true
            -- If this is the first occupant, press the bot down (move up‑right)
            if table_count(occ.players) == 1 then
                local road = occ.road
                if road.original_x and road.original_y then
                    local keyframes = {
                        {
                            properties = {
                                { property = "X", value = road.original_x + 0.1 },
                                { property = "Y", value = road.original_y + 0.1 }
                            },
                            duration = 0.2
                        }
                    }
                    Net.animate_bot_properties(bot_name, keyframes)
                end
            end
        end
    end
end)

-- Handle player leaving a bot tile
tile_events:on("player_exited_tile", function(event)
    local player_id = event.player_id
    local bot_name = event.bot_name
    local area = event.area
    local road_id = event.road_id

    local occ = bot_occupants[bot_name]
    if occ and occ.players[player_id] then
        occ.players[player_id] = nil
        -- If no occupants left, return bot to original position
        if not next(occ.players) then
            bot_occupants[bot_name] = nil   -- clean up
            local road = occ.road
            if road.original_x and road.original_y then
                local keyframes = {
                    {
                        properties = {
                            { property = "X", value = road.original_x },
                            { property = "Y", value = road.original_y }
                        },
                        duration = 0.2
                    }
                }
                Net.animate_bot_properties(bot_name, keyframes)
            end
        end
    end
end)

-- Tick verification: ensure players are still on the tiles they are registered to
Net:on("tick", function(event)
    for player_id, _ in pairs(any_player) do
        local area = Net.get_player_area(player_id)
        if area then
            -- Get player's current position (assuming Net.get_player_position exists)
            local x, y, z = Net.get_player_position(player_id)
            if x and y then
                local tx = math.floor(x)
                local ty = math.floor(y)

                -- Determine which bot (if any) is at the current tile
                local current_bot = nil
                local road_id = rush_roads_by_tile[area] and rush_roads_by_tile[area][tx] and rush_roads_by_tile[area][tx][ty]
                if road_id then
                    local road = rush_roads[area] and rush_roads[area][road_id]
                    if road then
                        current_bot = road.bot_name
                    end
                end

                -- Check all bots for this player
                for bot_name, occ in pairs(bot_occupants) do
                    if occ.players[player_id] then
                        -- If player is not on this bot's tile, remove them
                        if bot_name ~= current_bot then
                            occ.players[player_id] = nil
                            if not next(occ.players) then
                                bot_occupants[bot_name] = nil
                                -- Revert the bot
                                local road = occ.road
                                if road.original_x and road.original_y then
                                    local keyframes = {
                                        {
                                            properties = {
                                                { property = "X", value = road.original_x },
                                                { property = "Y", value = road.original_y }
                                            },
                                            duration = 0.2
                                        }
                                    }
                                    Net.animate_bot_properties(bot_name, keyframes)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- REWRITTEN player_move HANDLER (emits events instead of direct animation)
-- ============================================================================
Net:on("player_move", function(event)
    local player_id = event.player_id
    local x = event.x
    local y = event.y
    local area = Net.get_player_area(player_id)
    if not area then return end

    local current_tile_x = math.floor(x)
    local current_tile_y = math.floor(y)

    -- Detect area change
    local prev_area = player_area[player_id]
    player_area[player_id] = area

    -- Get previous tile info
    local prev = player_last_tile[player_id]
    local prev_tile_x, prev_tile_y, prev_area_id
    if prev then
        prev_tile_x = prev.x
        prev_tile_y = prev.y
        prev_area_id = prev.area
    end

    -- Helper to get road_id and bot_name from tile coordinates
    local function get_tile_info(area_id, tx, ty)
        local road_id = rush_roads_by_tile[area_id] and
                        rush_roads_by_tile[area_id][tx] and
                        rush_roads_by_tile[area_id][tx][ty]
        if not road_id then return nil, nil end
        local road = rush_roads[area_id] and rush_roads[area_id][road_id]
        return road_id, road and road.bot_name
    end

    -- If area changed, treat as leaving the previous tile in the old area
    if prev_area_id and prev_area_id ~= area then
        if prev_tile_x and prev_tile_y then
            local prev_road_id, prev_bot = get_tile_info(prev_area_id, prev_tile_x, prev_tile_y)
            if prev_bot then
                tile_events:emit("player_exited_tile", {
                    player_id = player_id,
                    area = prev_area_id,
                    tile_x = prev_tile_x,
                    tile_y = prev_tile_y,
                    road_id = prev_road_id,
                    bot_name = prev_bot
                })
            end
        end
        -- Clear previous for the new area
        prev = nil
        prev_tile_x, prev_tile_y = nil, nil
    end

    -- Get current tile info
    local current_road_id, current_bot = get_tile_info(area, current_tile_x, current_tile_y)

    -- Handle movement off previous tile (same area)
    if prev_area_id == area and prev_tile_x and prev_tile_y and (prev_tile_x ~= current_tile_x or prev_tile_y ~= current_tile_y) then
        local prev_road_id, prev_bot = get_tile_info(area, prev_tile_x, prev_tile_y)
        if prev_bot then
            tile_events:emit("player_exited_tile", {
                player_id = player_id,
                area = area,
                tile_x = prev_tile_x,
                tile_y = prev_tile_y,
                road_id = prev_road_id,
                bot_name = prev_bot
            })
        end
    end

    -- Handle entry onto current tile
    if current_bot and (not prev or prev.area ~= area or prev_tile_x ~= current_tile_x or prev_tile_y ~= current_tile_y) then
        tile_events:emit("player_entered_tile", {
            player_id = player_id,
            area = area,
            tile_x = current_tile_x,
            tile_y = current_tile_y,
            road_id = current_road_id,
            bot_name = current_bot
        })
    end

    -- Update last tile
    player_last_tile[player_id] = { area = area, x = current_tile_x, y = current_tile_y }
end)