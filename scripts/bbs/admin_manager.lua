-- Admin management for BBS boards
-- Stores admin player secrets in scripts/bbs/admin_list.json
-- Provides functions to check/grant admin status and manage the admin key item

local json = require("scripts/libs/json")
local sha = require('scripts/octo-ranking/sha256')
local admin_pass_hash = require('scripts/bbs/admin_pass_seed')  -- hashed password

local BBS_ADMINS = "scripts/bbs/admin_list.json"
local AdminKeyID = "ADMIN_KEY"
local perm_card_details = {
    name = "Admin Key",
    description = "Gives Admin level access to BBS boards.",
    type = "keyitem"
}

local admin_secrets = {}      -- in‑memory list of admin secrets
local saving = false
local pending_save = false


function async(p)
    local co = coroutine.create(p)
    return Async.promisify(co)
end

function await(v) return Async.await(v) end

-- Ensure the admin key item exists (idempotent)
local function ensure_admin_item()
    Net.create_item(AdminKeyID, perm_card_details)
end

-- Load admin list from file
local function load_admin_list()
    Async.read_file(BBS_ADMINS).and_then(function(value)
        if value and value ~= "" then
            local ok, data = pcall(json.decode, value)
            if ok and type(data) == "table" then
                admin_secrets = data
            else
                print("Failed to decode admin list")
            end
        end
    end)
end

-- Save admin list to file (with pretty print)
local function save_admin_list()
    if saving then
        pending_save = true
        return
    end
    saving = true
    Async.write_file(BBS_ADMINS, json.encode(admin_secrets, true)).and_then(function()
        saving = false
        if pending_save then
            pending_save = false
            save_admin_list()
        end
    end)
end

-- Add a player to the admin list using their secret
local function add_admin(player_id)
    local secret = Net.get_player_secret(player_id)
    if not secret then return false end
    -- Avoid duplicates
    for _, s in ipairs(admin_secrets) do
        if s == secret then return true end
    end
    table.insert(admin_secrets, secret)
    save_admin_list()
    return true
end

-- Check if a player is an admin (by secret)
local function is_admin(player_id)
    local secret = Net.get_player_secret(player_id)
    if not secret then return false end
    for _, s in ipairs(admin_secrets) do
        if s == secret then return true end
    end
    return false
end

-- Called when a player connects: give admin key if they are in the list
local function on_player_connect(player_id)
    if is_admin(player_id) then
        if not Net.player_has_item(player_id, AdminKeyID) then
            Net.give_player_item(player_id, AdminKeyID)
        end
    end
end

-- Verify password attempt; if correct, add to admin list and give item
local function check_password_and_grant(player_id, password_attempt)
    if sha.sha256(password_attempt) == admin_pass_hash then
        add_admin(player_id)
        if not Net.player_has_item(player_id, AdminKeyID) then
            Net.give_player_item(player_id, AdminKeyID)
        end
        return true
    end
    return false
end

-- Initialise: create item and load existing admins
ensure_admin_item()
load_admin_list()

return {
    on_player_connect = on_player_connect,
    check_password_and_grant = check_password_and_grant,
    is_admin = is_admin,
    add_admin = add_admin,
}