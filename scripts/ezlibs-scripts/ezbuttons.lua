-- ezbuttons.lua
-- Creates trigger‑based buttons (non‑solid NPCs) that can be chained together.
-- When all buttons in a chain become active, a callback is invoked.
-- Supports five interaction behaviors: Repeatable, One-Time, Dynamic, Custom, Timed.
-- Supports exclusive chains: only one button can be active at a time.
-- Supports area‑wide unlock/relock via "Area Wide" flag on Unlock/Relock Behavior objects.

local object_registry = require('scripts/ezlibs-scripts/object_registry')
local eznpcs = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local eztriggers = require('scripts/ezlibs-scripts/eztriggers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezbus = require('scripts/ezlibs-scripts/ezbus')
local helpers = require('scripts/ezlibs-scripts/helpers')
local ezcheckpoints = require('scripts/ezlibs-scripts/ezcheckpoints')

function async(p)
    local co = coroutine.create(p)
    return Async.promisify(co)
end

function await(v) return Async.await(v) end


local ezbuttons = {}

local button_asset_folder = '/server/assets/ezlibs-assets/ezbuttons/'
local TILE_SIZE = 32

-- Cache for custom behavior scripts
local custom_script_cache = {}

-- Global table to keep strong references to all button triggers
local button_triggers = {}


local function object_to_tile_pos(object)
    local x = tonumber(object.x) or 0
    local y = tonumber(object.y) or 0
    local z = tonumber(object.z or 0) or 0
    return x, y, z
end

-- Internal data
local button_placeholders = {}          -- area_id -> [object_id] = placeholder_info
local button_bots = {}                  -- bot_id -> placeholder_info
local chain_roots = {}                  -- root_placeholder_id -> list of placeholder_ids
local placeholder_to_chain_root = {}    -- placeholder_id -> root_placeholder_id
local chain_callbacks = {}              -- root_placeholder_id -> function(player_id)
local chains_built = false

-- Chain type: "Any" (default) or "Exclusive" – stored per root
local chain_type = {}                   -- root_placeholder_id -> string

-- Checkpoint binding: root_button_id -> { area_id, object_id, once, area_wide }
local checkpoint_bindings = {}

-- Temporary storage for checkpoints referenced by individual buttons (before chains are built)
-- Fields: area_id, checkpoint_object_id, once, area_wide
local button_to_checkpoint = {}

-- Forward declarations
local is_button_active
local perform_activation
local perform_deactivation
local deactivate_button_internal

-- Helper: hide the original Tiled placeholder object for a player
local function hide_button_placeholder_for_player(player_id, area_id, object_id)
    if not player_id or not area_id or not object_id then return end
    local ok_area, player_area = pcall(Net.get_player_area, player_id)
    if not ok_area or player_area ~= area_id then return end
    pcall(Net.exclude_object_for_player, player_id, tostring(object_id))
end

local function hide_button_placeholders_for_player(player_id)
    if not player_id then return end
    local ok_area, area_id = pcall(Net.get_player_area, player_id)
    if not ok_area or not area_id then return end
    local area_table = button_placeholders[area_id]
    if not area_table then return end
    for object_id, _ in pairs(area_table) do
        hide_button_placeholder_for_player(player_id, area_id, object_id)
    end
end

local function set_button_animation(bot_id, anim_state, loop)
    if not bot_id or not anim_state then return end
    if loop == nil then loop = true end
    local ok, err = pcall(Net.animate_bot, bot_id, anim_state, loop)
    if not ok then
        print("[ezbuttons] animate failed bot=", tostring(bot_id), " anim=", tostring(anim_state), " err=", tostring(err))
    end
end

-- Sync all button animations in an area for a specific player
local function sync_button_animations_for_player(player_id)
    if not player_id then return end
    local ok_area, area_id = pcall(Net.get_player_area, player_id)
    if not ok_area or not area_id then return end
    local area_table = button_placeholders[area_id]
    if not area_table then return end

    for object_id, info in pairs(area_table) do
        local bot_id = info.bot_id
        if bot_id then
            local is_active = is_button_active(area_id, object_id)
            local anim = is_active and info.active_anim or info.inactive_anim
            set_button_animation(bot_id, anim, true)
        end
    end
end

-- Apply any area‑wide unlock flags to a player who just entered the area
local function apply_area_wide_unlocks(player_id, area_id)
    if not player_id or not area_id then return end
    local area_mem = ezmemory.get_area_memory(area_id)
    if not area_mem.area_wide_unlock then return end

    for _, entry in pairs(area_mem.area_wide_unlock) do
        -- entry contains { area_id = checkpoint_area_id, checkpoint_object_id, once }
        pcall(ezcheckpoints.force_unlock_checkpoint, player_id, entry.area_id, entry.checkpoint_object_id, entry.once)
    end
end

Net:on("player_join", function(event)
    hide_button_placeholders_for_player(event.player_id)
    sync_button_animations_for_player(event.player_id)
    local ok, area_id = pcall(Net.get_player_area, event.player_id)
    if ok and area_id then
        apply_area_wide_unlocks(event.player_id, area_id)
    end
end)

Net:on("player_area_transfer", function(event)
    hide_button_placeholders_for_player(event.player_id)
    sync_button_animations_for_player(event.player_id)
    apply_area_wide_unlocks(event.player_id, event.new_area_id)
end)

-- Helper: create a non‑solid bot for the button
local function create_button_bot(area_id, asset_name, x, y, z, direction,
                                 bot_name, animation_name, mug_animation_name,
                                 initial_anim)
    local texture_path = button_asset_folder  .. asset_name .. ".png"
    local animation_path = button_asset_folder  .. asset_name .. ".animation"

    if animation_name then
        animation_path = button_asset_folder .. animation_name .. ".animation"
    end

    local npc_data = {
        asset_name = asset_name,
        bot_id = nil,
        name = bot_name,
        area_id = area_id,
        texture_path = texture_path,
        animation_path = animation_path,
        x = x,
        y = y,
        z = z,
        solid = false,
        size = 0.2,
        speed = 1,
        dont_face_player = true,
        warp_in = true,
    }

    local bot_id = Net.create_bot(npc_data)
    if not bot_id then
        print("[ezbuttons] Failed to create bot for button", asset_name)
        return nil
    end
    print("[ezbuttons] created button bot id:", bot_id, "at", x, y, z)
    return bot_id
end

-- Active state from memory
is_button_active = function(area_id, object_id)
    local area_mem = ezmemory.get_area_memory(area_id)
    area_mem.buttons = area_mem.buttons or {}
    return area_mem.buttons[tostring(object_id)] == true
end

local function set_button_active_state(area_id, object_id, bot_id, active_anim, inactive_anim, active)
    local area_mem = ezmemory.get_area_memory(area_id)
    area_mem.buttons = area_mem.buttons or {}
    area_mem.buttons[tostring(object_id)] = active
    ezmemory.save_area_memory(area_id)

    local new_anim = active and active_anim or inactive_anim
    set_button_animation(bot_id, new_anim, true)
end

-- Trigger creation
local function create_button_trigger(area_id, object, width_px, height_px, trigger_id)
    if width_px < 4 then width_px = 4 end
    if height_px < 4 then height_px = 4 end

    print(string.format("[ezbuttons] Creating trigger: area=%s, obj_id=%s, size=%dx%d px, id=%s",
          area_id, tostring(object.id), width_px, height_px, trigger_id))

    local emitter = eztriggers.add_rectangle_trigger(area_id, object, width_px, height_px, trigger_id)
    if emitter then
        button_triggers[trigger_id] = emitter
        print("[ezbuttons] ✅ Trigger created successfully: " .. trigger_id)
    else
        print("[ezbuttons] ❌ FAILED to create trigger for " .. trigger_id)
    end
    return emitter
end

-- Build chains from "Next 1" links and read chain type from stored property
local function build_chains()
    if chains_built then return end

    local all_placeholders = {}
    local next_to_prev = {}

    for area_id, area_table in pairs(button_placeholders) do
        for obj_id, info in pairs(area_table) do
            all_placeholders[obj_id] = info
            if info.next_id then next_to_prev[info.next_id] = obj_id end
        end
    end

    local roots = {}
    for obj_id, info in pairs(all_placeholders) do
        if not next_to_prev[obj_id] then table.insert(roots, obj_id) end
    end

    for _, root_id in ipairs(roots) do
        local chain = {}
        local current_id = root_id
        while current_id do
            local info = all_placeholders[current_id]
            if not info then break end
            table.insert(chain, current_id)
            current_id = info.next_id
        end
        chain_roots[root_id] = chain
        for _, id in ipairs(chain) do
            placeholder_to_chain_root[id] = root_id
        end

        local root_info = all_placeholders[root_id]
        if root_info and root_info.chain_type then
            chain_type[root_id] = root_info.chain_type
            print("[ezbuttons] Chain root", root_id, "has stored chain_type =", chain_type[root_id])
        else
            chain_type[root_id] = "Any"
            print("[ezbuttons] Chain root", root_id, "defaulting to Any")
        end
    end

    -- Transfer button_to_checkpoint entries to checkpoint_bindings per root
    for button_id, cp_info in pairs(button_to_checkpoint) do
        local root_id = placeholder_to_chain_root[button_id] or button_id
        if not checkpoint_bindings[root_id] then
            checkpoint_bindings[root_id] = cp_info
            print("[ezbuttons] Auto‑bound checkpoint " .. cp_info.checkpoint_object_id .. " to chain root " .. root_id)
        end
    end

    chains_built = true
    print("[ezbuttons] Built", #roots, "button chains from 'Next 1' properties")
end

-- Helper to check if a chain is fully active
local function is_chain_fully_active(area_id, chain_ids)
    for _, id in ipairs(chain_ids) do
        if not is_button_active(area_id, id) then
            return false
        end
    end
    return true
end

-- ============================================================
-- PERFORM ACTIVATION (with checkpoint unlocking, area-wide support)
-- ============================================================
perform_activation = function(area_id, object_id, player_id, info)
    if is_button_active(area_id, object_id) then
        return false
    end

    -- Remember who activated this button
    info.last_activator = player_id

    local root_id = placeholder_to_chain_root[object_id] or object_id
    -- Exclusive chain handling
    if chain_type[root_id] == "Exclusive" then
        local chain_ids = chain_roots[root_id] or { root_id }
        for _, other_id in ipairs(chain_ids) do
            if tostring(other_id) ~= tostring(object_id) then
                local other_area_id = nil
                local other_info = nil
                for aid, atable in pairs(button_placeholders) do
                    local oinfo = atable[tostring(other_id)]
                    if oinfo then
                        other_area_id = aid
                        other_info = oinfo
                        break
                    end
                end
                if other_area_id and other_info then
                    if is_button_active(other_area_id, other_id) then
                        if other_info.is_animating then
                            other_info.is_animating = false
                            set_button_animation(other_info.bot_id, other_info.inactive_anim, true)
                        end
                        perform_deactivation(other_area_id, other_id, other_info)
                    end
                end
            end
        end
    end

    set_button_active_state(area_id, object_id, info.bot_id, info.active_anim, info.inactive_anim, true)
    print("[ezbuttons] Button", object_id, "activated by player", player_id)

    -- Ensure chain data exists
    if not chain_roots[root_id] then
        chain_roots[root_id] = { root_id }
        placeholder_to_chain_root[root_id] = root_id
    end

    local chain_ids = chain_roots[root_id]
    local all_active = is_chain_fully_active(area_id, chain_ids)

    if all_active then
        local binding = checkpoint_bindings[root_id]
        if binding then
            local cp_area = binding.area_id
            local cp_id   = binding.checkpoint_object_id
            local once    = binding.once
            local area_wide = binding.area_wide

            if area_wide then
                -- Unlock for all players currently in the checkpoint's area
                local players = Net.list_players(cp_area) or {}
                for _, pid in ipairs(players) do
                    pcall(ezcheckpoints.force_unlock_checkpoint, pid, cp_area, cp_id, once)
                end
                -- Save persistent flag so future joiners auto‑unlock
                local cp_area_mem = ezmemory.get_area_memory(cp_area)
                cp_area_mem.area_wide_unlock = cp_area_mem.area_wide_unlock or {}
                cp_area_mem.area_wide_unlock[tostring(root_id)] = {
                    area_id = cp_area,
                    checkpoint_object_id = cp_id,
                    once = once
                }
                ezmemory.save_area_memory(cp_area)
                print("[ezbuttons] Area‑wide unlock applied to checkpoint " .. cp_id .. " in area " .. cp_area)
            else
                -- Single‑player unlock
                local ok, err = pcall(ezcheckpoints.force_unlock_checkpoint, player_id, cp_area, cp_id, once)
                if not ok then
                    print("[ezbuttons] Failed to unlock checkpoint: " .. tostring(err))
                else
                    print("[ezbuttons] Checkpoint " .. cp_id .. " unlocked for player " .. player_id)
                    if not once then
                        -- Store in area memory for future relock
                        local area_mem = ezmemory.get_area_memory(area_id)
                        area_mem.timed_button_unlock_info = area_mem.timed_button_unlock_info or {}
                        area_mem.timed_button_unlock_info[tostring(root_id)] = {
                            player_id = player_id,
                            area_id = cp_area,
                            checkpoint_object_id = cp_id
                        }
                        ezmemory.save_area_memory(area_id)
                        print("   [DEBUG] chain_unlock_state saved to area memory: root=" .. root_id .. " player=" .. player_id .. " cp=" .. cp_id)
                    else
                        print("   [DEBUG] Unlock Permanently is TRUE, will NOT relock later")
                    end
                end
            end
        end

        local callback = chain_callbacks[root_id]
        if callback then
            print("[ezbuttons] Chain", root_id, "fully unlocked! Calling callback.")
            callback(player_id)
        else
            ezbus:emit("ezbuttons.chain_unlocked", {
                player_id = player_id,
                chain_root = root_id,
                area_id = area_id
            })
        end
    end
    return true
end

-- ============================================================
-- PERFORM DEACTIVATION (with optional explicit Relock Behavior, area-wide support)
-- ============================================================
perform_deactivation = function(area_id, object_id, info)
    if not is_button_active(area_id, object_id) then
        return false
    end

    local root_id = placeholder_to_chain_root[object_id] or object_id
    local chain_ids = chain_roots[root_id] or { root_id }
    local was_fully_active = is_chain_fully_active(area_id, chain_ids)

    set_button_active_state(area_id, object_id, info.bot_id, info.active_anim, info.inactive_anim, false)
    print("[ezbuttons] Button", object_id, "deactivated")

    local now_fully_active = is_chain_fully_active(area_id, chain_ids)
    print(string.format("   [DEBUG] was_fully_active=%s, now_fully_active=%s", tostring(was_fully_active), tostring(now_fully_active)))

    -- Automatic relock (chain became incomplete)
    if was_fully_active and not now_fully_active then
        local area_mem = ezmemory.get_area_memory(area_id)
        area_mem.timed_button_unlock_info = area_mem.timed_button_unlock_info or {}

        -- Check for area‑wide unlock flag first
        local cp_area_mem = ezmemory.get_area_memory(area_id)  -- area_id is the button's area, could be same as checkpoint's area
        if cp_area_mem and cp_area_mem.area_wide_unlock and cp_area_mem.area_wide_unlock[tostring(root_id)] then
            local entry = cp_area_mem.area_wide_unlock[tostring(root_id)]
            local players = Net.list_players(entry.area_id) or {}
            for _, pid in ipairs(players) do
                pcall(ezcheckpoints.relock_checkpoint, pid, entry.area_id, entry.checkpoint_object_id)
            end
            -- Clear the flag
            cp_area_mem.area_wide_unlock[tostring(root_id)] = nil
            ezmemory.save_area_memory(entry.area_id)
            print("[ezbuttons] Area‑wide relock applied to checkpoint " .. entry.checkpoint_object_id .. " in area " .. entry.area_id)
        else
            -- Per‑player automatic relock
            local unlock_info = area_mem.timed_button_unlock_info[tostring(root_id)]
            if unlock_info then
                print("   [DEBUG] calling relock_checkpoint: player=" .. unlock_info.player_id .. " cp=" .. unlock_info.checkpoint_object_id .. " area=" .. unlock_info.area_id)
                local ok, err = pcall(ezcheckpoints.relock_checkpoint, unlock_info.player_id, unlock_info.area_id, unlock_info.checkpoint_object_id)
                if not ok then
                    print("[ezbuttons] Failed to relock checkpoint: " .. tostring(err))
                else
                    print("[ezbuttons] Checkpoint " .. unlock_info.checkpoint_object_id .. " relocked for player " .. unlock_info.player_id)
                end
                area_mem.timed_button_unlock_info[tostring(root_id)] = nil
                ezmemory.save_area_memory(area_id)
            end
        end
    end

    -- Explicit Relock Behavior (independent of automatic)
    if info.relock_target then
        if info.relock_area_wide then
            -- Area‑wide explicit relock
            local players = Net.list_players(info.area_id) or {}
            for _, pid in ipairs(players) do
                pcall(ezcheckpoints.relock_checkpoint, pid, info.area_id, info.relock_target)
            end
            print("[ezbuttons] Explicit area‑wide relock for checkpoint " .. info.relock_target .. " in area " .. info.area_id)
        else
            -- Per‑player explicit relock
            if info.last_activator then
                print("[ezbuttons] Explicit Relock Behavior: relocking " .. info.relock_target .. " for player " .. info.last_activator)
                pcall(ezcheckpoints.relock_checkpoint, info.last_activator, info.area_id, info.relock_target)
            else
                print("[ezbuttons] No last_activator for explicit relock; cannot relock")
            end
        end
    end

    return true
end

-- Internal deactivation helper
deactivate_button_internal = function(area_id, object_id, info, skip_exclusive)
    if not info then
        info = button_placeholders[area_id] and button_placeholders[area_id][tostring(object_id)]
        if not info then
            print("[ezbuttons] No button info for", object_id)
            return false
        end
    end

    if info.is_animating then
        print("[ezbuttons] Button", object_id, "is already animating, ignoring deactivation")
        return false
    end

    if not is_button_active(area_id, object_id) then
        print("[ezbuttons] Button", object_id, "already inactive")
        return false
    end

    -- Cancel any pending Timed deactivation
    info.timed_cancel = true

    local deactivation_anim = info.deactivation_anim
    local deactivation_duration = info.deactivation_duration or 0.5

    local old_skip = info._skip_exclusive
    if skip_exclusive then
        info._skip_exclusive = true
    end

    local function finish_deactivation()
        if skip_exclusive then
            info._skip_exclusive = nil
        else
            info._skip_exclusive = old_skip
        end
        perform_deactivation(area_id, object_id, info)
    end

    if deactivation_anim and deactivation_anim ~= "" then
        info.is_animating = true
        async(function()
            set_button_animation(info.bot_id, deactivation_anim, false)
            await(Async.sleep(deactivation_duration))
            info.is_animating = false
            finish_deactivation()
        end)
        return true
    else
        finish_deactivation()
        return true
    end
end

-- Start a timer that will deactivate the button after its activated_time
local function start_timed_deactivation(area_id, object_id, info)
    info.timed_cancel = true
    info.timed_cancel = false

    local delay = info.activated_time
    print(string.format("   [DEBUG] Timed deactivation scheduled for button %s in %.2f seconds", tostring(object_id), delay))

    async(function()
        await(Async.sleep(delay))
        if info.timed_cancel then
            print("   [DEBUG] Timed deactivation CANCELLED for button " .. tostring(object_id))
            return
        end
        if is_button_active(area_id, object_id) then
            print("   [DEBUG] Timed deactivation FIRING for button " .. tostring(object_id))
            deactivate_button_internal(area_id, object_id, info, false)
        else
            print("   [DEBUG] Button " .. tostring(object_id) .. " already inactive, skipping timed deactivation")
        end
    end)
end

-- Public activate with optional animation
local function activate_button(area_id, object_id, player_id)
    build_chains()
    object_id = tostring(object_id)
    local info = button_placeholders[area_id] and button_placeholders[area_id][object_id]
    if not info then
        print("[ezbuttons] No button info for", object_id)
        return false
    end

    if info.is_animating then
        print("[ezbuttons] Button", object_id, "is already animating, ignoring trigger")
        return false
    end

    if is_button_active(area_id, object_id) then
        print("[ezbuttons] Button", object_id, "already active")
        return false
    end

    local activation_anim = info.activation_anim
    local activation_duration = info.activation_duration or 0.5

    if activation_anim and activation_anim ~= "" then
        info.is_animating = true
        async(function()
            set_button_animation(info.bot_id, activation_anim, false)
            await(Async.sleep(activation_duration))
            info.is_animating = false
            perform_activation(area_id, object_id, player_id, info)
        end)
        return true
    else
        return perform_activation(area_id, object_id, player_id, info)
    end
end

-- Public deactivate with optional animation
local function deactivate_button(area_id, object_id, skip_exclusive)
    build_chains()
    object_id = tostring(object_id)
    local info = button_placeholders[area_id] and button_placeholders[area_id][object_id]
    if not info then
        print("[ezbuttons] No button info for", object_id)
        return false
    end

    if not skip_exclusive and info._skip_exclusive then
        return false
    end

    return deactivate_button_internal(area_id, object_id, info, skip_exclusive or false)
end

-- Load custom behavior script
local function load_custom_script(script_path)
    if not script_path or script_path == "" then
        return nil, "No script path provided"
    end
    if custom_script_cache[script_path] then
        return custom_script_cache[script_path], nil
    end
    local module_path = script_path:gsub("%.lua$", "")
    local ok, module = pcall(require, module_path)
    if not ok then
        return nil, "Failed to load script: " .. tostring(module)
    end
    if type(module.on_enter) ~= "function" then
        return nil, "Custom script must provide an on_enter function"
    end
    custom_script_cache[script_path] = module
    return module, nil
end

-- ============================================================
-- OBJECT REGISTRY HANDLER FOR "OW BUTTON"
-- ============================================================
object_registry.register_handler("OW Button", function(area_id, object)
    local props = object.custom_properties or {}

    -- Bot Details
    local bot_details_obj_id = props["Bot Details"]
    if not bot_details_obj_id or bot_details_obj_id == "" then
        print("[ezbuttons] OW Button missing Bot Details reference, skipping", object.id)
        return
    end

    local bot_details_obj = Net.get_object_by_id(area_id, tostring(bot_details_obj_id))
    if not bot_details_obj then
        print("[ezbuttons] OW Button Bot Details object not found in area", area_id, "for button", object.id)
        return
    end

    local details_props = bot_details_obj.custom_properties or {}
    local asset_name = details_props["Asset Name"]
    local direction = details_props["Direction"]
    if not asset_name or not direction then
        print("[ezbuttons] OW Button Bot Details missing Asset Name or Direction, skipping button", object.id)
        return
    end

    local animation_name = details_props["Animation Name"]
    local mug_animation_name = details_props["Mug Animation Name"]
    local active_anim = details_props["Active Animation"] or "ACTIVE"
    local inactive_anim = details_props["Inactive Animation"] or "INACTIVE"
    local activation_anim = details_props["Activated Animation"] or nil
    local deactivation_anim = details_props["Deactivated Animation"] or nil
    local activation_duration = tonumber(details_props["Activation Animation Duration"]) or 0.5
    local deactivation_duration = tonumber(details_props["Deactivation Animation Duration"]) or 0.5

    local bot_name = object.name
    local next_id = props["Next 1"]

    -- Behavior properties
    local behavior = props["Button Behavior"] or "One-Time"
    local script_path = props["Script Path"] or nil
    local chain_type_prop = props["Button Chain Type"] or "Any"
    local activated_time = tonumber(props["Activated Time"]) or 1

    -- ====== Unlock Behavior (activation) ======
    local unlock_checkpoint_obj = nil
    local unlock_permanently = true
    local unlock_area_wide = false
    local behavior_obj_id = props["Button Activated Behavior"]
    if behavior_obj_id and behavior_obj_id ~= "" then
        local behavior_obj = Net.get_object_by_id(area_id, tostring(behavior_obj_id))
        if behavior_obj then
            local beh_props = behavior_obj.custom_properties or {}
            unlock_checkpoint_obj = beh_props["Unlock This"]
            if beh_props["Unlock Permanently"] ~= nil then
                local val = beh_props["Unlock Permanently"]
                if type(val) == "boolean" then
                    unlock_permanently = val
                elseif type(val) == "string" then
                    unlock_permanently = (val:lower() == "true")
                end
            end
            -- Area Wide flag
            if beh_props["Area Wide"] ~= nil then
                local val = beh_props["Area Wide"]
                if type(val) == "boolean" then
                    unlock_area_wide = val
                elseif type(val) == "string" then
                    unlock_area_wide = (val:lower() == "true")
                end
            end
            print(string.format("   [DEBUG] Button %s: Unlock Behavior -> checkpoint=%s, permanent=%s, area_wide=%s",
                  tostring(object.id), tostring(unlock_checkpoint_obj), tostring(unlock_permanently), tostring(unlock_area_wide)))
        else
            print("[ezbuttons] Warning: Unlock Behavior object", behavior_obj_id, "not found in area", area_id)
        end
    end

    -- ====== Relock Behavior (deactivation) ======
    local relock_target = nil
    local relock_area_wide = false
    local deactivated_behavior_id = props["Button Deactivated Behavior"]
    if deactivated_behavior_id and deactivated_behavior_id ~= "" then
        local relock_obj = Net.get_object_by_id(area_id, tostring(deactivated_behavior_id))
        if relock_obj then
            local relock_props = relock_obj.custom_properties or {}
            relock_target = relock_props["Relock This"]
            -- Area Wide flag
            if relock_props["Area Wide"] ~= nil then
                local val = relock_props["Area Wide"]
                if type(val) == "boolean" then
                    relock_area_wide = val
                elseif type(val) == "string" then
                    relock_area_wide = (val:lower() == "true")
                end
            end
            if relock_target and relock_target ~= "" then
                print("[ezbuttons] Button " .. tostring(object.id) .. " will relock checkpoint " .. relock_target .. " on deactivation (area_wide=" .. tostring(relock_area_wide) .. ")")
            else
                print("[ezbuttons] Warning: Relock Behavior object " .. deactivated_behavior_id .. " does not have a valid Relock This property")
                relock_target = nil
            end
        else
            print("[ezbuttons] Warning: Relock Behavior object", deactivated_behavior_id, "not found in area", area_id)
        end
    end

    -- Bot creation
    local bot_x, bot_y, bot_z = object_to_tile_pos(object)
    local bot_id = create_button_bot(area_id, asset_name, bot_x, bot_y,
                                     bot_z, direction, bot_name,
                                     animation_name, mug_animation_name,
                                     inactive_anim)
    if not bot_id then return end

    -- Restore saved active state
    local was_active = is_button_active(area_id, object.id)
    if was_active then
        set_button_animation(bot_id, active_anim, true)
    else
        set_button_animation(bot_id, inactive_anim, true)
    end

    -- Store placeholder info
    if not button_placeholders[area_id] then
        button_placeholders[area_id] = {}
    end

    -- Determine trigger source
    local trigger_source_obj = object
    local trigger_type = "rect"
    local trigger_width_px = 4
    local trigger_height_px = 4

    local trigger_obj_id = props["Trigger Object"]
    if trigger_obj_id and trigger_obj_id ~= "" then
        local trigger_obj = Net.get_object_by_id(area_id, trigger_obj_id)
        if trigger_obj then
            trigger_source_obj = trigger_obj
            trigger_type = (trigger_obj.custom_properties and trigger_obj.custom_properties["Trigger Type"]) or "rect"
            trigger_width_px = tonumber(trigger_obj.width) or trigger_width_px
            trigger_height_px = tonumber(trigger_obj.height) or trigger_height_px
        else
            trigger_type = props["Trigger Type"] or "rect"
            trigger_width_px = props["Trigger Width"] or 4
            trigger_height_px = props["Trigger Height"] or 4
        end
    else
        trigger_type = props["Trigger Type"] or "rect"
        trigger_width_px = props["Trigger Width"] or 4
        trigger_height_px = props["Trigger Height"] or 4
    end

    -- Build info table (including relock_target, relock_area_wide, last_activator)
    local info = {
        area_id = area_id,
        object_id = object.id,
        bot_id = bot_id,
        next_id = next_id,
        active_anim = active_anim,
        inactive_anim = inactive_anim,
        behavior = behavior,
        script_path = script_path,
        bot_x = bot_x,
        bot_y = bot_y,
        bot_z = bot_z,
        activation_anim = activation_anim,
        activation_duration = activation_duration,
        deactivation_anim = deactivation_anim,
        deactivation_duration = deactivation_duration,
        is_animating = false,
        trigger_x = trigger_source_obj.x,
        trigger_y = trigger_source_obj.y,
        trigger_z = trigger_source_obj.z or 0,
        trigger_half_w = (TILE_SIZE / trigger_width_px) * 0.5,
        trigger_half_h = (TILE_SIZE / trigger_height_px) * 0.5,
        chain_type = chain_type_prop,
        activated_time = activated_time,
        timed_cancel = false,
        relock_target = relock_target,
        relock_area_wide = relock_area_wide,
        last_activator = nil,
    }

    button_placeholders[area_id][tostring(object.id)] = info
    button_bots[bot_id] = info

    -- Hide original object
    for _, player_id in ipairs(Net.list_players(area_id) or {}) do
        hide_button_placeholder_for_player(player_id, area_id, object.id)
    end

    -- Create trigger
    local trigger_id = "button_" .. area_id .. "_" .. tostring(object.id)
    local emitter
    if trigger_type == "ellipse" then
        local center_x = trigger_source_obj.x
        local center_y = trigger_source_obj.y
        emitter = eztriggers.add_radius_trigger(area_id, trigger_source_obj, trigger_width_px,
                                                trigger_height_px, center_x, center_y, trigger_id)
    else
        emitter = create_button_trigger(area_id, trigger_source_obj, trigger_width_px, trigger_height_px, trigger_id)
    end

    if not emitter then
        print("[ezbuttons] ❌ CRITICAL: Trigger creation failed for button", object.id)
        return
    end

    -- Custom script handlers
    local custom_handlers = nil
    if behavior == "Custom" then
        local mod, err = load_custom_script(script_path)
        if not mod then
            print("[ezbuttons] Custom script error for button", object.id, ":", err, "- falling back to One-Time")
            behavior = "One-Time"
        else
            custom_handlers = mod
        end
    end

    info.behavior = behavior
    info.custom_handlers = custom_handlers

    -- Enter handler
    emitter:on("entered", function(event)
        local player_id = event.player_id
        if not player_id then return end
        print("[ezbuttons] 🟢 TRIGGER ENTERED: button=", tostring(object.id), " player=", tostring(player_id), " behavior=", behavior)

        if behavior == "Repeatable" then
            if not is_button_active(area_id, object.id) then
                activate_button(area_id, object.id, player_id)
            end
        elseif behavior == "One-Time" then
            if not is_button_active(area_id, object.id) then
                activate_button(area_id, object.id, player_id)
            end
        elseif behavior == "Dynamic" then
            if is_button_active(area_id, object.id) then
                deactivate_button(area_id, object.id)
            else
                activate_button(area_id, object.id, player_id)
            end
        elseif behavior == "Timed" then
            if not is_button_active(area_id, object.id) then
                if activate_button(area_id, object.id, player_id) then
                    start_timed_deactivation(area_id, object.id, info)
                end
            end
        elseif behavior == "Custom" and custom_handlers and custom_handlers.on_enter then
            custom_handlers.on_enter(player_id, info)
        end
    end)

    -- Depart handler
    emitter:on("departed", function(event)
        local player_id = event.player_id
        if not player_id then return end
        print("[ezbuttons] 🔴 TRIGGER DEPARTED: button=", tostring(object.id), " player=", tostring(player_id), " behavior=", behavior)

        if behavior == "Repeatable" then
            if is_button_active(area_id, object.id) then
                deactivate_button(area_id, object.id)
            end
        elseif behavior == "One-Time" then
            -- do nothing
        elseif behavior == "Dynamic" then
            -- do nothing (deactivation happens on next enter via toggle)
        elseif behavior == "Timed" then
            -- Timer handles deactivation, do nothing on depart
        elseif behavior == "Custom" and custom_handlers and custom_handlers.on_exit then
            custom_handlers.on_exit(player_id, info)
        end
    end)

    info.trigger_info = emitter
    print("[ezbuttons] ✅ OW Button fully initialized:", object.id, "behavior=", behavior, "trigger size=", trigger_width_px, "x", trigger_height_px)

    -- Store checkpoint binding info (for chain activation unlock)
    if unlock_checkpoint_obj and unlock_checkpoint_obj ~= "" then
        button_to_checkpoint[tostring(object.id)] = {
            area_id = area_id,
            checkpoint_object_id = tostring(unlock_checkpoint_obj),
            once = unlock_permanently,
            area_wide = unlock_area_wide,
        }
        print("[ezbuttons] Button", object.id, "will unlock checkpoint", unlock_checkpoint_obj, "when its chain is fully activated (area_wide=" .. tostring(unlock_area_wide) .. ")")
    end
end)

-- Public API
function ezbuttons.on_chain_unlocked(root_button_id, callback)
    if type(callback) ~= "function" then
        error("ezbuttons.on_chain_unlocked: callback must be a function")
    end
    root_button_id = tostring(root_button_id)
    print("[ezbuttons] registered chain callback for root=", root_button_id)
    chain_callbacks[root_button_id] = callback
end

function ezbuttons.build_chains() build_chains() end

function ezbuttons.is_button_active(area_id, object_id)
    return is_button_active(area_id, object_id)
end

function ezbuttons.activate_button(area_id, object_id, player_id)
    activate_button(area_id, object_id, player_id)
end

function ezbuttons.deactivate_button(area_id, object_id)
    deactivate_button(area_id, object_id, false)
end

function ezbuttons.reset_button(area_id, object_id)
    local info = button_placeholders[area_id] and button_placeholders[area_id][tostring(object_id)]
    if info then
        set_button_active_state(area_id, object_id, info.bot_id, info.active_anim, info.inactive_anim, false)
    end
end

function ezbuttons.reset_chain(root_object_id)
    local chain = chain_roots[root_object_id]
    if chain then
        for _, id in ipairs(chain) do
            for area_id, area_table in pairs(button_placeholders) do
                local info = area_table[tostring(id)]
                if info then
                    ezbuttons.reset_button(area_id, id)
                    break
                end
            end
        end
    end
end

function ezbuttons.bind_checkpoint_to_chain(root_button_id, checkpoint_area_id, checkpoint_object_id, once)
    root_button_id = tostring(root_button_id)
    checkpoint_bindings[root_button_id] = {
        area_id = checkpoint_area_id,
        checkpoint_object_id = tostring(checkpoint_object_id),
        once = (once == nil) and true or once
    }
    print("[ezbuttons] Bound checkpoint " .. checkpoint_object_id .. " to chain root " .. root_button_id)
end

print("[ezbuttons] Loaded (async animations, exclusive chains, timed behavior, area‑wide unlock/relock support)")
return ezbuttons