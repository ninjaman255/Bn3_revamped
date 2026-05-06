-- scripts/ezlibs-scripts/eznpcs/eznpc_spawner.lua
local helpers = require('scripts/ezlibs-scripts/helpers')
local ezcache = require('scripts/ezlibs-scripts/ezcache')
local object_registry = require('scripts/ezlibs-scripts/object_registry')
local eznpcs = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local eztriggers = require('scripts/ezlibs-scripts/eztriggers')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local ezbus = require('scripts/ezlibs-scripts/ezbus')

local spawners = {}          -- area_id -> { spawner_id -> spawner_data }
local active_npcs = {}       -- bot_id -> { spawner_id, area_id, npc_data, trigger_info }
local player_battling_npc = {} -- player_id -> bot_id

local TILE_WIDTH = 64
local TILE_HEIGHT = 32

local function random_position_in_range(center_x, center_y, max_tiles)
    local offset_x = (math.random() * 2 - 1) * max_tiles * TILE_WIDTH
    local offset_y = (math.random() * 2 - 1) * max_tiles * TILE_HEIGHT
    return center_x + offset_x, center_y + offset_y
end

-- Waypoint behaviour (from eznpcs.lua)
local function waypoint_follow_behaviour(first_waypoint_id)
    return {
        type = 'on_tick',
        initialize = function(npc)
            local waypoint = ezcache.get_object_by_id_cached(npc.area_id, first_waypoint_id)
            if waypoint then npc.next_waypoint = waypoint end
        end,
        action = function(npc, delta_time)
            if not npc.next_waypoint then return end
            local area_id = npc.area_id
            local wp = npc.next_waypoint
            local dx = wp.x - npc.x
            local dy = wp.y - npc.y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < npc.size then
                local next_wp_id = nil
                local wp_type = wp.custom_properties["Waypoint Type"] or "first"
                local next_wps = helpers.extract_numbered_properties(wp, "Next Waypoint ")
                if wp_type == "first" then
                    next_wp_id = next_wps[1]
                elseif wp_type == "random" and #next_wps > 0 then
                    next_wp_id = next_wps[math.random(#next_wps)]
                elseif wp_type == "before" then
                    local date = wp.custom_properties['Date']
                    local is_before = date and helpers.is_now_before_date(date)
                    next_wp_id = is_before and next_wps[1] or next_wps[2]
                elseif wp_type == "after" then
                    local date = wp.custom_properties['Date']
                    local is_after = date and not helpers.is_now_before_date(date)
                    next_wp_id = is_after and next_wps[1] or next_wps[2]
                end
                if next_wp_id then
                    npc.next_waypoint = ezcache.get_object_by_id_cached(area_id, next_wp_id)
                end
                if wp.custom_properties['Wait Time'] then
                    npc.wait_time = tonumber(wp.custom_properties['Wait Time'])
                end
                if wp.custom_properties['Direction'] then
                    npc.direction = wp.custom_properties['Direction']
                    Net.set_bot_direction(npc.bot_id, wp.custom_properties['Direction'])
                end
                return
            end
            if npc.wait_time and npc.wait_time > 0 then
                npc.wait_time = npc.wait_time - delta_time
                return
            end
            local angle = math.atan2(dy, dx)
            local vel_x = math.cos(angle) * npc.speed
            local vel_y = math.sin(angle) * npc.speed
            local new_x = npc.x + vel_x * delta_time
            local new_y = npc.y + vel_y * delta_time
            local temp_pos = {x=new_x, y=new_y, z=npc.z, size=npc.size}
            if not helpers.position_overlaps_something(temp_pos, area_id) then
                Net.move_bot(npc.bot_id, new_x, new_y, npc.z)
                npc.x = new_x
                npc.y = new_y
                if active_npcs[npc.bot_id] and active_npcs[npc.bot_id].trigger_info then
                    local trig = active_npcs[npc.bot_id].trigger_info
                    trig.center_x = npc.x
                    trig.center_y = npc.y
                end
            end
        end
    }
end

-- Function to handle NPC defeat (called directly from the trigger)
local function on_npc_defeated(bot_id, spawner_id, area_id)
    if not active_npcs[bot_id] then return end

    -- Remove trigger
    local trigger_id = "npc_trigger_" .. tostring(bot_id)
    if eztriggers.radius_triggers[area_id] then
        eztriggers.radius_triggers[area_id][trigger_id] = nil
    end
    Net.remove_bot(bot_id)
    active_npcs[bot_id] = nil

    -- Clear battle association
    for pid, npc_id in pairs(player_battling_npc) do
        if npc_id == bot_id then player_battling_npc[pid] = nil end
    end

    -- Update spawner and respawn
    local spawner = spawners[area_id] and spawners[area_id][spawner_id]
    if spawner then
        for i, id in ipairs(spawner.active_npcs) do
            if id == bot_id then
                table.remove(spawner.active_npcs, i)
                break
            end
        end
        async(function()
            await(Async.sleep(5))
            if #spawner.active_npcs < spawner.max_spawn_count then
                create_spawner_npc(spawner)
            end
        end)
    end
end

-- Create a dynamic radius trigger that follows the NPC
local function create_following_trigger(npc, spawner_id, area_id, encounter_name)
    local trigger_id = "npc_trigger_" .. tostring(npc.bot_id)
    local trigger_object = {
        id = trigger_id,
        x = npc.x,
        y = npc.y,
        z = npc.z,
        width = TILE_WIDTH,
        height = TILE_HEIGHT,
        name = "NPC Trigger",
        custom_properties = {}
    }
    local emitter = eztriggers.add_radius_trigger(area_id, trigger_object, TILE_WIDTH, TILE_HEIGHT, 0, 0)
    if not emitter then return nil end

    local trigger_info = eztriggers.radius_triggers[area_id] and eztriggers.radius_triggers[area_id][trigger_id]
    if not trigger_info then return nil end

    trigger_info.center_x = npc.x
    trigger_info.center_y = npc.y

    emitter:on("entered", function(event)
        local player_id = event.player_id
        if player_battling_npc[player_id] or not active_npcs[npc.bot_id] then return end
        player_battling_npc[player_id] = npc.bot_id

        async(function()
            local stats = await(ezencounters.begin_encounter_by_name(player_id, encounter_name))
            if not stats then
                player_battling_npc[player_id] = nil
                return
            end
            local won = (stats.reason == 1) and (stats.health and stats.health > 0)
            if won then
                on_npc_defeated(npc.bot_id, spawner_id, area_id)
            else
                player_battling_npc[player_id] = nil
            end
        end):catch(function(err)
            print("[eznpc_spawner] encounter error:", err)
            player_battling_npc[player_id] = nil
        end)
    end)

    return trigger_info
end

-- Create a single NPC from a spawner
local function create_spawner_npc(spawner)
    local area_id = spawner.area_id
    local asset_name = spawner.asset_name
    local spawn_x, spawn_y = random_position_in_range(spawner.x, spawner.y, spawner.max_spawn_distance)
    local z = spawner.z or 0

    local npc_data = {
        asset_name = asset_name,
        bot_id = nil,
        name = spawner.name or asset_name,
        area_id = area_id,
        texture_path = "/server/assets/ezlibs-assets/eznpcs/sheet/" .. asset_name .. ".png",
        animation_path = "/server/assets/ezlibs-assets/eznpcs/sheet/" .. asset_name .. ".animation",
        mug_animation_path = "/server/assets/ezlibs-assets/eznpcs/mug/mug.animation",
        x = spawn_x,
        y = spawn_y,
        z = z,
        direction = "Down",
        solid = true,
        size = 0.2,
        speed = 1,
        dont_face_player = false,
        warp_in = true,
    }

    local bot_id = Net.create_bot(npc_data)
    if not bot_id then return nil end
    npc_data.bot_id = bot_id

    if spawner.first_waypoint_id then
        local wp = waypoint_follow_behaviour(spawner.first_waypoint_id)
        wp.initialize(npc_data)
        npc_data.on_tick = wp
    end

    local trigger_info = nil
    if spawner.encounter_name then
        trigger_info = create_following_trigger(npc_data, spawner.id, area_id, spawner.encounter_name)
    end

    table.insert(spawner.active_npcs, bot_id)
    active_npcs[bot_id] = {
        spawner_id = spawner.id,
        area_id = area_id,
        npc_data = npc_data,
        trigger_info = trigger_info
    }

    print("[eznpc_spawner] spawned NPC", bot_id, "for spawner", spawner.id)
    return npc_data
end

-- Object registry handler
object_registry.register_handler("NPC Spawner", function(area_id, object)
    if not object.custom_properties then return end
    local props = object.custom_properties

    local asset_name = props["Asset Name"]
    if not asset_name then
        print("[eznpc_spawner] Spawner missing Asset Name at", object.id)
        return
    end

    local max_dist = tonumber(props["Max Spawn Distance"]) or 1
    local max_count = tonumber(props["Max Spawn Count"]) or 1
    local encounter_name = props["Encounter Path"]
    local first_waypoint_id = props["Waypoint 1"]

    local spawner_id = tostring(object.id)
    if not spawners[area_id] then spawners[area_id] = {} end
    local spawner = {
        id = spawner_id,
        area_id = area_id,
        x = object.x,
        y = object.y,
        z = object.z,
        asset_name = asset_name,
        max_spawn_distance = max_dist,
        max_spawn_count = max_count,
        encounter_name = encounter_name,
        first_waypoint_id = first_waypoint_id,
        active_npcs = {},
        name = object.name,
    }
    spawners[area_id][spawner_id] = spawner

    for i = 1, max_count do
        create_spawner_npc(spawner)
    end
end)

print("[eznpc_spawner] loaded")