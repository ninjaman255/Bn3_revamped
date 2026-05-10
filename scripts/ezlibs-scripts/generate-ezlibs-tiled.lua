-- generate_tiled_types_json.lua
-- Generates a Tiled-compatible JSON file containing all custom object types used by ezlibs.
-- Output file: ezlibs-tiled-types.json (or specify path as argument)
-- Run with: lua generate_tiled_types_json.lua [output_path]

local json = require('scripts/ezlibs-scripts/json')

-- ----------------------------------------------------------------------
-- Define all enums used in properties
local Enums = {
    Direction = {
        type = "string",
        values = {"Up", "Down", "Left", "Right", "Up Left", "Up Right", "Down Left", "Down Right"}
    },
    MysteryType = {
        type = "string",
        values = {"keyitem", "item", "money", "random", "quiz", "fragments", "tokens", "encounter"}
    },
    WaypointType = {
        type = "string",
        values = {"first", "random", "before", "after"}
    },
    DialogueType = {
        type = "string",
        values = {"first", "question", "quiz", "random", "itemcheck", "before", "after",
                  "shop", "password", "quest_switch", "quest_event", "item", "email", 
                  "questcheck", "battle_npc"}
    },
    ItemType = {
        type = "string",
        values = {"item", "keyitem", "money", "fragments", "tokens"}
    },
    CurrencyType = {
        type = "string",
        values = {"money", "fragments", "tokens"}
    },
    QuizFailAction = {
        type = "string",
        values = {"retry", "hide_once", "hide_temp", "explode"}
    },
    TriggerShape = {
        type = "string",
        values = {"rect", "ellipse"}
    },
    ButtonBehavior = {
        type = "string",
        values = {"Repeatable", "One-Time", "Dynamic", "Custom", "Timed"}
    },
    KeyType = {
        type = "string",
        values = {"money", "fragments", "tokens", "item", "bossgate"}
    },
    ButtonChainType = {
        type = "string",
        values = {"Any", "Exclusive"}
    }
}

-- ----------------------------------------------------------------------
-- Helper to create a property definition
local function prop(name, typ, default, enumName)
    local p = { name = name, type = typ, value = default }
    if enumName then
        p.propertyType = enumName
    end
    return p
end

-- ----------------------------------------------------------------------
-- Define all object types
local object_types = {
    {
        name = "Checkpoint",
        color = "#ffaa00",
        members = {
            prop("Password", "string", ""),
            prop("Key Type", "string", "money", "KeyType"),
            prop("Key Item Name", "string", ""),
            prop("Required Keys", "number", 1),
            prop("Consume", "bool", false),
            prop("Once", "bool", false),
            prop("Unlocking Asset Name", "string", "bn5cubegreen_bot"),
            prop("Unlocking Animation Time", "number", 0),
            prop("Unlocking Sound Path", "string", "/server/assets/ezlibs-assets/sfx/panel_change.ogg"),
            prop("Skip Prompt", "bool", false),
            prop("Description", "string", "It's a Security Cube"),
            prop("Unlocked Message", "string", "The Security Cube was unlocked!"),
            prop("Unlock Failed Message", "string", "You were unable to unlock the Security Cube"),
        }
    },
    {
        name = "Mystery Data",
        color = "#00aaff",
        members = {
            prop("Locked", "bool", false),
            prop("Password Locked", "string", ""),
            prop("Once", "bool", false),
            prop("Type", "string", "item", "MysteryType"),
            prop("Name", "string", ""),
            prop("Description", "string", ""),
            prop("Amount", "number", 1),
            prop("Quiz List", "object", ""),
            prop("Failure Message", "string", ""),
            prop("On Fail", "string", "retry", "QuizFailAction"),
            prop("Explosion Count", "number", 3),
            -- Reward properties (used when Type = "quiz")
            prop("Reward Type", "string", "item", "ItemType"),
            prop("Reward Name", "string", ""),
            prop("Reward Amount", "number", 1),
            prop("Reward Description", "string", ""),
            -- Cost properties
            prop("Cost Type", "string", "", "CurrencyType"),
            prop("Cost Amount", "number", 1),
            prop("Cost Failure Message", "string", ""),
            -- Next numbered properties
            prop("Next 1", "object", ""),
            prop("Next 2", "object", ""),
            prop("Next 3", "object", ""),
            prop("Next 4", "object", ""),
            prop("Next 5", "object", ""),
            prop("Next 6", "object", ""),
            prop("Next 7", "object", ""),
            prop("Next 8", "object", ""),
            prop("Next 9", "object", ""),
            prop("Next 10", "object", ""),
        }
    },
    {
        name = "Quiz List",
        color = "#aa66cc",
        members = {
            prop("Next 1", "object", ""),
            prop("Next 2", "object", ""),
            prop("Next 3", "object", ""),
            prop("Next 4", "object", ""),
            prop("Next 5", "object", ""),
            prop("Next 6", "object", ""),
            prop("Next 7", "object", ""),
            prop("Next 8", "object", ""),
            prop("Next 9", "object", ""),
            prop("Next 10", "object", ""),
        }
    },
    {
        name = "Quiz Question",
        color = "#88aa44",
        members = {
            prop("Question", "string", ""),
            prop("Option 1", "string", ""),
            prop("Option 2", "string", ""),
            prop("Option 3", "string", ""),
            prop("Correct Answer", "number", 1),
        }
    },
    {
        name = "Location Trigger",
        color = "#88ff88",
        members = {
            prop("Event Name", "string", ""),
            prop("Name", "string", ""),
        }
    },
    {
        name = "Server Warp",
        color = "#ff8888",
        members = {
            prop("Incoming Data", "string", ""),
            prop("Direction", "string", "Down", "Direction"),
            prop("Warp In", "bool", false),
            prop("Arrival Animation", "string", ""),
            prop("Dont Teleport", "bool", false),
            prop("Address", "string", ""),
            prop("Port", "number", 0),
            prop("Data", "string", ""),
            prop("Warp Out", "bool", false),
        }
    },
    {
        name = "Custom Warp",
        color = "#ff8888",
        members = {
            prop("Incoming Data", "string", ""),
            prop("Direction", "string", "Down", "Direction"),
            prop("Warp In", "bool", false),
            prop("Arrival Animation", "string", ""),
            prop("Dont Teleport", "bool", false),
            prop("Target Area", "string", ""),
            prop("Target Object", "string", ""),
            prop("Leave Animation", "string", ""),
        }
    },
    {
        name = "Interact Warp",
        color = "#ff8888",
        members = {
            prop("Incoming Data", "string", ""),
            prop("Direction", "string", "Down", "Direction"),
            prop("Warp In", "bool", false),
            prop("Arrival Animation", "string", ""),
            prop("Dont Teleport", "bool", false),
            prop("Target Area", "string", ""),
            prop("Target Object", "string", ""),
            prop("Leave Animation", "string", ""),
        }
    },
    {
        name = "Radius Warp",
        color = "#ff8888",
        members = {
            prop("Incoming Data", "string", ""),
            prop("Direction", "string", "Down", "Direction"),
            prop("Warp In", "bool", false),
            prop("Arrival Animation", "string", ""),
            prop("Dont Teleport", "bool", false),
            prop("Activation Radius", "number", 1),
            prop("Target Area", "string", ""),
            prop("Target Object", "string", ""),
            prop("Leave Animation", "string", ""),
        }
    },
    {
        name = "NPC",
        color = "#aaaaaa",
        members = {
            prop("Direction", "string", "Down", "Direction"),
            prop("Asset Name", "string", ""),
            prop("Animation Name", "string", ""),
            prop("Mug Animation Name", "string", ""),
            prop("Dont Face Player", "bool", false),
            prop("Next Waypoint 1", "object", ""),
            prop("Dialogue Type", "string", "", "DialogueType"),
            prop("Mugshot", "string", ""),
            prop("Text 1", "string", ""),
            prop("Text 2", "string", ""),
            prop("Text 3", "string", ""),
            prop("Next 1", "object", ""),
            prop("Next 2", "object", ""),
            prop("Item 1", "object", ""),
            prop("Item 2", "object", ""),
            prop("Take Item", "bool", false),
            prop("Date", "string", ""),
            prop("Quest Name", "string", ""),
            prop("Event Value", "string", ""),
            prop("Dont Notify", "bool", false),
            prop("Encounter Name", "string", ""),
            prop("Failure Message", "string", ""),
            prop("Player Exclusive", "bool", false),
            prop("Quest NPC", "bool", false),
            prop("Quest Exclusive", "string", ""),
            prop("Quest State", "string", "active"),
        }
    },
    {
        name = "Waypoint",
        color = "#55ff55",
        members = {
            prop("Wait Time", "number", 0),
            prop("Direction", "string", "", "Direction"),
            prop("Waypoint Type", "string", "first", "WaypointType"),
            prop("Date", "string", ""),
            prop("Next Waypoint 1", "object", ""),
            prop("Next Waypoint 2", "object", ""),
            prop("Next Waypoint 3", "object", ""),
            prop("Next Waypoint 4", "object", ""),
            prop("Next Waypoint 5", "object", ""),
        }
    },
    {
        name = "Radius Encounter",
        color = "#ff5555",
        members = {
            prop("Radius", "number", 1),
            prop("Name", "string", ""),
            prop("Path", "file", ""),
            prop("Once", "bool", false),
        }
    },
    {
        name = "Water Refill",
        color = "#4444ff",
        members = {}
    },
    {
        name = "Item",
        color = "#ffdd44",
        members = {
            prop("Name", "string", ""),
            prop("Type", "string", "item", "ItemType"),
            prop("Description", "string", ""),
            prop("Amount", "number", 1),
            prop("Price", "number", 999999),
        }
    },
    {
        name = "Dialogue",
        color = "#cc66cc",
        members = {
            prop("Dialogue Type", "string", "first", "DialogueType"),
            prop("Mugshot", "string", ""),
            prop("Text 1", "string", ""),
            prop("Text 2", "string", ""),
            prop("Text 3", "string", ""),
            prop("Next 1", "object", ""),
            prop("Next 2", "object", ""),
            prop("Next 3", "object", ""),
            prop("Next 4", "object", ""),
            prop("Next 5", "object", ""),
            prop("Item 1", "object", ""),
            prop("Item 2", "object", ""),
            prop("Take Item", "bool", false),
            prop("Date", "string", ""),
            prop("Quest Name", "string", ""),
            prop("Event Value", "string", ""),
            prop("Dont Notify", "bool", false),
            -- Email-specific properties
            prop("Email Id", "string", ""),
            prop("Email Icon", "number", 1),
            prop("Email Title", "string", "Mail"),
            prop("Email From", "string", "???"),
            prop("Body 1", "string", ""),
            prop("Body 2", "string", ""),
            prop("Body 3", "string", ""),
            prop("Body 4", "string", ""),
            prop("Body 5", "string", ""),
            prop("Body 6", "string", ""),
            prop("Body 7", "string", ""),
            prop("Body 8", "string", ""),
            prop("Body 9", "string", ""),
            prop("Body 10", "string", ""),
            prop("Notify Delay", "number", 1.5),
            prop("Notify Message", "string", "Looks like you got an e-mail."),
            prop("Mug Texture Path", "string", ""),
            prop("Mug Animation Path", "string", ""),
            prop("Persist", "bool", true),
            -- Battle NPC properties
            prop("Encounter Name", "string", ""),
            prop("Failure Message", "string", ""),
        }
    },
    -- Explosion Trigger
    {
        name = "Explosion Trigger",
        color = "#ff6600",
        members = {
            prop("Target", "string", ""),
            prop("Follow", "bool", false),
            prop("Once", "bool", false),
        }
    },
    -- Rush Road (for ezrushroads)
    {
        name = "Rush Road",
        color = "#ffaa00",
        members = {
            prop("Rush Object", "object", ""),
            prop("Direction", "string", "Down Left", "Direction"),
        }
    },
    -- Compression Tile (for ezpress)
    {
        name = "Compression Tile",
        color = "#88aaff",
        members = {
            prop("Compress", "bool", false),
            prop("Decompress", "bool", false),
        }
    },
    -- Admin Console (for ezusers)
    {
        name = "Admin Console",
        color = "#ffaa00",
        members = {
            -- No custom properties needed (uses global password hash)
        }
    },
    -- Button Bot Details – stores the visual/animation properties for an OW Button
    {
        name = "Button Bot Details",
        color = "#99ddff",
        members = {
            prop("Asset Name", "string", ""),
            prop("Direction", "string", "Down", "Direction"),
            prop("Animation Name", "string", ""),
            prop("Mug Animation Name", "string", ""),
            prop("Active Animation", "string", "ACTIVE"),
            prop("Inactive Animation", "string", "INACTIVE"),
            prop("Activated Animation", "string", ""),
            prop("Deactivated Animation", "string", ""),
            prop("Activation Animation Duration", "number", 0.5),
            prop("Deactivation Animation Duration", "number", 0.5),
        }
    },
    -- OW Button (from ezbuttons)
    {
        name = "OW Button",
        color = "#66ccff",
        members = {
            -- Reference to the Button Bot Details object that defines bot visuals
            prop("Bot Details", "object", ""),
            -- Next button in the chain
            prop("Next 1", "object", ""),
            -- Button behavior
            prop("Button Behavior", "string", "One-Time", "ButtonBehavior"),
            prop("Script Path", "file", ""),
            -- Reference to the Button Trigger object that defines the detection zone
            prop("Trigger Object", "object", ""),
            -- Direct checkpoint unlock when this button (or its chain) is fully activated
            prop("Unlock Checkpoint", "object", ""),
            prop("Unlock Permanently", "bool", false),
            -- Button chain exclusivity mode
            prop("Button Chain Type", "string", "Any", "ButtonChainType"),
            -- Timed behavior duration
            prop("Activated Time", "number", 1),
        }
    },
    -- Button Trigger – defines the detection area for an OW Button
    {
        name = "Button Trigger",
        color = "#aaddff",
        members = {
            prop("Trigger Type", "string", "rect", "TriggerShape"),
        }
    }
}

-- ----------------------------------------------------------------------
-- Build the final JSON structure
local function build_tiled_types()
    local output = {}
    local id = 1

    for enum_name, enum in pairs(Enums) do
        table.insert(output, {
            id = id,
            name = enum_name,
            storageType = enum.type,
            type = "enum",
            values = enum.values,
            valuesAsFlags = false
        })
        id = id + 1
    end

    for _, ot in ipairs(object_types) do
        local class = {
            id = id,
            name = ot.name,
            color = ot.color,
            drawFill = true,
            type = "class",
            useAs = { "object" },
            members = ot.members
        }
        table.insert(output, class)
        id = id + 1
    end

    return output
end

-- ----------------------------------------------------------------------
-- Main execution
local function main(output_path, pretty)
    if not output_path then
        output_path = "ezlibs-tiled-types.json"
    end

    local pretty = pretty or false
    local types = build_tiled_types()
    local json_str = json.encode(types, pretty)

    local file, err = io.open(output_path, "w")
    if not file then
        error("Could not open " .. output_path .. " for writing: " .. tostring(err))
    end
    file:write(json_str)
    file:close()
    print("Generated Tiled types: " .. output_path)
end

if arg and arg[0] and arg[0]:find("generate_tiled_types_json.lua") then
    local out = arg[1]
    main(out)
else
    return { generate = main }
end