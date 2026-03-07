
# ezlibs — Complete Documentation (Formatted for Developers)

> **Developer Reference for ezlibs** — a collection of Lua modules for building interactive server-side features
> in 2D multiplayer games (Net.Games engine). This Markdown file includes headers, tables, Lua code blocks, and
> property reference tables so it renders cleanly in GitHub / VSCode / Markdown viewers.

---

## Table of Contents

- [Introduction](#introduction)
- [Global Utilities (helpers.lua)](#global-utilities-helperslua)
  - [Async / Await](#async--await)
  - [Locking (Anti‑Spam)](#locking-anti-spam)
  - [Table Utilities & Helpers](#table-utilities--helpers)
- [Event System](#event-system)
  - [eventemitter.lua (class)](#eventemitterlua-class)
  - [ezbus — Global Event Bus](#ezbus--global-event-bus)
- [Module: ezmemory](#module-ezmemory)
  - [Player Memory](#player-memory)
  - [Area Memory](#area-memory)
  - [Key Functions (API)](#key-functions-api)
  - [Area Custom Properties (Health & Mystery Data)](#area-custom-properties-health--mystery-data)
- [Module: ezcache](#module-ezcache)
- [Module: eztriggers](#module-eztriggers)
- [Module: ezwarps](#module-ezwarps)
- [Module: eznpcs](#module-eznpcs)
- [Module: ezencounters](#module-ezencounters)
- [Module: ezcheckpoints](#module-ezcheckpoints)
- [Module: ezmystery](#module-ezmystery)
- [Module: ezfarms](#module-ezfarms)
- [Module: ezweather](#module-ezweather)
- [Module: ezquests](#module-ezquests)
- [Module: ezmenus](#module-ezmenus)
- [Item Definition Objects](#item-definition-objects)
- [Configuration (ezconfig.lua)](#configuration-ezconfiglua)
- [Custom Scripting & Plugins](#custom-scripting--plugins)
- [Appendix: Common Patterns](#appendix-common-patterns)

---

## Introduction

**ezlibs** is a set of Lua modules that provide:

- Persistent player and area memory
- Trigger systems (radius, rectangle, interact)
- Warp systems (including cross‑server)
- NPCs with dialogue trees and waypoint movement
- Random encounters / battle hooks
- Collectible *mystery data*
- Checkpoints with locks (password, money, item)
- Farming mechanics
- Weather effects
- Quest framework
- Menu handling with async iterators
- Global event bus for inter‑module communication

All modules are built to be loaded from `scripts/ezlibs-scripts/` and configured via `ezconfig.lua`.
Many behaviors are driven by **Tiled** objects and object properties on your maps.

---

## Global Utilities (helpers.lua)

`helpers.lua` provides reusable utility functions used across ezlibs modules.

### Async / Await

Use the `async` wrapper and `await` helper for coroutine-friendly asynchronous code.

```lua
async(function() ... end)   -- wraps a coroutine, returns a promise
await(promise)              -- yields until the promise resolves
-- Example
local result = await(Async.prompt_player(player_id))
```

### Locking (Anti‑Spam)

Prevent concurrent interactions using locks:

```lua
local lock = helpers.get_lock(player_id, "unique_lock_id", timeout)
if not lock then return end
-- do async work
lock.release()
```

Locks release automatically on player disconnect.

### Table Utilities & Other Helpers (selected)

- `helpers.indexOf(array, value)` → index or `nil`
- `helpers.extract_numbered_properties(object, prefix)` → table of `Next 1`, `Next 2`, ...
- `helpers.clear_table(tbl)`
- `helpers.deep_copy(orig)`
- `helpers.split(string, delimiter)`
- `helpers.get_safe_player_secret(player_id)` → URL-encoded safe filename key
- `helpers.safe_require(script_path)` → require wrapper that logs failures
- `helpers.date_string_to_timestamp(date_string)` → parse cron-like strings to timestamp
- `helpers.is_now_before_date(date_string)` → boolean
- `helpers.position_overlaps_something(position, area_id)`
- `helpers.read_item_information(area_id, item_object_id)` → returns `{name, amount, description, type, price}` or `false`

---

## Event System

### eventemitter.lua (class)

A custom EventEmitter that supports:

- `:on(event, callback)`
- `:once(event, callback)`
- `:on_any(callback)` / `:on_any_once(callback)`
- `:emit(event, ...)`
- `:remove_listener(event, callback)`
- `:async_iter(event)` → returns an async iterator for `event`
- `:async_iter_all()` → async iterator for all events
- `:destroy()` → cleanup

Used by `eztriggers`, `ezmenus`, and the global bus.

### ezbus — Global Event Bus

`ezbus.lua` exports a single EventEmitter instance for global broadcasts. Typical usage:

```lua
local ezbus = require('scripts/ezlibs-scripts/ezbus')
ezbus:on("lock_attempt", function(player_id, lock_type, success)
    print(player_id, lock_type, success)
end)
```

Common events: `"lock_attempt"`, `"item_gained"`, `"money_spent"`, `"encounter_started"`, `"encounter_finished"`

The bus is destroyed automatically on server shutdown.

---

## Module: ezmemory

Handles persistent storage: items, money, quest flags, hidden objects, area-specific state.

### Player Memory (structure)

Stored per player (keyed by safe secret) under `PLAYER_PATH_FOLDER`. Example structure:

```lua
{
  items = { [item_id] = quantity },
  money = number,
  meta = { joins = number },
  area_memory = { [area_id] = { hidden_objects = { [object_id] = true } } },
  max_health = number,
  health = number,
  quests = { [quest_name] = { [flag] = value } },
  -- modules may add custom fields
}
```

### Area Memory

Stored per area in `AREA_PATH_FOLDER`. Example fields:

```lua
{
  hidden_objects = { [object_id] = true },
  tile_states = { ... } -- used by ezfarms
}
```

### Item Memory

Items are stored globally in `ITEMS_PATH`. Example item record:

```lua
{
  name = string,
  description = string,
  key_item = boolean, -- appears in key item menu if true
}
```

Items are created on-demand via `ezmemory.create_or_update_item` or `ezmemory.get_or_create_item`.

### Area Custom Properties (Health & Mystery Data)

These can be set as Tiled map properties. Common area properties include:

| Property | Type | Description |
|---|---:|---|
| Forced Base HP | number | Overrides player's max HP to this value |
| Honor HPMem | bool | If true, add 20 HP per HPMem item the player has |
| Honor Saved HP | bool | If true, load player's saved HP from memory |
| Full Heal | bool | If true, fully heal player on area entry |
| Mystery Data Minimum | number | Minimum mystery data to show |
| Mystery Data Maximum | number | Maximum mystery data to show |

### Key Functions (API highlights)

- `ezmemory.get_player_memory(safe_secret)`
- `ezmemory.get_area_memory(area_id)`
- `ezmemory.give_player_item(player_id, item_name, amount)`
- `ezmemory.remove_player_item(player_id, item_name, amount)`
- `ezmemory.spend_player_money(player_id, amount)`
- `ezmemory.count_player_item(player_id, item_name)`
- `ezmemory.hide_object_from_player(player_id, area_id, object_id)`
- `ezmemory.hide_object_from_player_till_disconnect(...)`
- `ezmemory.object_is_hidden_from_player(...)`
- `ezmemory.set_player_max_health(player_id, new_max, should_heal_by_increase)`
- `ezmemory.set_player_health(player_id, new_health)`
- `ezmemory.open_shop_async(player_id, shop_items, mugshot_texture, mugshot_animation)`

---

## Module: ezcache

Provides `get_object_by_id_cached(area_id, object_id)` — caches frequently used object definitions (NPCs, Waypoints, Dialogues, Shop Items, Mystery Options) and removes them from the map to save bandwidth. Cached types: `"NPC"`, `"Waypoint"`, `"Dialogue"`, `"Shop Item"`, `"Mystery Option"`.

---

## Module: eztriggers

Creates collision-based triggers that emit events for player enter/leave.

### Location Trigger Object

- **Type**: `Location Trigger`
- **Geometry**: ellipse or rectangle based on object shape in Tiled.
- **Custom Properties**:

| Property | Required | Description |
|---|:---:|---|
| Event Name | yes | name of an event registered via `eztriggers.add_event()` |
| Name | no | descriptive name for logging |

When a player **enters**, emitter emits `"entered"` with `{ player_id, object }`; when they **leave**, emits `"departed"`.

### Registering Events

An event is a Lua table `{ name = "...", action = function(player_id, object) ... end }` and should return a promise (or nil). Example:

```lua
eztriggers.add_event({
  name = "my_event",
  action = function(player_id, object)
    return async(function()
      await(Async.message_player(player_id, "You entered!"))
    end)
  end
})
```

---

## Module: ezwarps

Handles warping players between areas and servers.

### Common Warp Properties

| Property | Type | Description |
|---|---:|---|
| Incoming Data | string | unique landing string for cross-server joins |
| Direction | string | `Up`, `Down`, `Left`, `Right`, `Up Left`, ... default `Down` |
| Warp In | bool | play warp-in effect |
| Arrival Animation | string | animation name to play on arrival |
| Dont Teleport | bool | only play leave animation, do not teleport |

### Warp Types

**Server Warp** (`Type: "Server Warp"`) — warps to another server.

| Property | Required | Description |
|---|:---:|---|
| Address | yes | IP or hostname |
| Port | yes | port number |
| Data | no | custom data string |
| Warp Out | no | play warp-out effect |

**Custom Warp** (`Type: "Custom Warp"`) — warps to an object/area in the same or another area.

| Property | Required | Description |
|---|:---:|---|
| Target Area | yes | destination area ID |
| Target Object | yes | object ID of landing point |
| Leave Animation | no | animation to play before leaving |

**Interact Warp** — warps on "A"/interact; same properties as Custom Warp.

**Radius Warp** — triggers when player enters radius.

| Property | Required | Description |
|---|:---:|---|
| Activation Radius | number | radius in tiles (plus common warp properties) |

### Incoming Data / Landings

When `Net.transfer_server` is used with custom data, `ezwarps.handle_player_request` matches `Incoming Data` values to landing points and places players at the correct location and animation state.

### Arrival & Leave Animations (examples)

- `fall_in`, `lev_beast_in`, `lev_beast_out`
- `arrow_up_left_in`, `arrow_up_right_in`, `arrow_down_left_out`, ...
- `log_in` (jack‑in), `log_out` (jack‑out)

Create custom animations using `arrow_animation_factory.lua` pattern and register them in `ezwarps/main.lua`.

---

## Module: eznpcs

Creates NPC bots from placeholder objects, handles dialogues and waypoint movement.

### NPC Placeholder Object

- **Type**: `NPC`
- Replaced by a bot at server start; placeholder is removed (cached).
- **Required Properties**:

| Property | Type | Description |
|---|---:|---|
| Direction | string | facing direction |
| Asset Name | string | base name of the sprite sheet (in `NPC_ASSET_FOLDER/sheet/`) |

- **Optional Properties**: `Animation Name`, `Mug Animation Name`, `Dont Face Player`, `Next Waypoint 1`

### Dialogue System Overview

Dialogues can be defined by objects (often `Dialogue` type) placed in the area. The NPC's *first dialogue* can be the placeholder object itself if it contains dialogue properties (design choice supported by code). `Next 1`, `Next 2`, ... link to other dialogue objects by ID.

#### Dialogue Node Properties (common)

- `Dialogue Type` — node kind (see types below)
- `Mugshot` — override mugshot (use `"player"` to show player mug)
- Additional fields depend on type (e.g., `Text 1`, `Item 1`, `Next 1`...)

#### Dialogue Types Reference (summary)

| Type | Typical Properties | Behavior |
|---|---|---|
| `first` | `Text 1`, `Next 1` | Linear message |
| `question` | `Text 1`, `Next 1` (Yes), `Next 2` (No) | Yes/No prompt |
| `quiz` | `Text 1`, `Text 2`/`Text 3`, `Next 1`, `Next 2` | Two-choice quiz |
| `random` | `Text 1..n`, `Next 1..n` | Randomly pick a message |
| `itemcheck` | `Item 1..n`, `Take Item`, `Next 1/2` | Check or consume items |
| `before` / `after` | `Text 1`, `Text 2`, `Date` | Branch by date |
| `shop` | `Item 1..n`, `Next 1` | Open a shop |
| `password` | `Text 1`, `Next 1`, `Next 2` | Prompt for password |
| `quest_switch` / `quest_event` | quest-specific props | Branch or trigger quest events |
| `item` | `Item 1..n`, `Dont Notify`, `Next 1` | Give items to player |

> **Note:** `Next` references are object IDs. Item references point to Item Definition Objects (see below). Numbered properties can go to at least 20 entries.

### Waypoint System

NPCs can move along waypoints (`Type: "Waypoint"`). Waypoint properties:

| Property | Type | Description |
|---|---:|---|
| Wait Time | number | seconds to wait at waypoint |
| Direction | string | facing while waiting |
| Waypoint Type | string | `"first"`, `"random"`, `"before"`, `"after"` |
| Date | string | cron-style date for conditional paths |
| Next Waypoint 1..n | string | object IDs of next waypoints |

Custom dialogue types can be added with `eznpcs.add_event(event_object)` where `event_object.action` returns a promise and resolves to the next dialogue ID (or `nil`). Example:

```lua
eznpcs.add_event({
  name = "my_custom_type",
  action = function(npc, player_id, dialogue, relay)
    return async(function()
      await(Async.message_player(player_id, "Custom!"))
      return dialogue.custom_properties["Next 1"]
    end)
  end
})
```

---

## Module: ezencounters

Manages random and radius-triggered encounters.

### Encounter Tables (Lua)

Define per-area encounter tables (path set in `CONFIG.ENCOUNTERS_PATH`). Example table:

```lua
return {
  minimum_steps_before_encounter = 5,
  encounter_chance_per_step = 0.1,
  encounters = {
    {
      name = "mettaur",
      path = "/path/to/mob.package",
      weight = 10,
      results_callback = function(player_id, encounter_info, battle_results)
        -- handle results
      end
    },
    -- ...
  }
}
```

### Radius Encounter Object (`Type: "Radius Encounter"`)

| Property | Type | Required | Description |
|---|---:|:---:|---|
| Radius | number | yes | radius in tiles |
| Name | string | * | named encounter from table |
| Path | string | * | direct path to mob package (if no name) |
| Once | bool | no | hide after completion if true |

Random encounters are tracked via player steps and the encounter table settings. `results_callback` is invoked after battles if defined.

---

## Module: ezcheckpoints

Checkpoints unlockable via password, money, or items.

### Checkpoint Object (`Type: "Checkpoint"`)

| Custom Property | Type | Description |
|---|---:|---|
| Password | string | overrides other lock types; prompts for password |
| Key Name | string | name of item or `"money"` (default `"money"`) |
| Required Keys | number | required amount (default `1`) |
| Consume | bool | consume on success |
| Once | bool | hide permanently when unlocked |
| Unlocking Asset Name | string | animation asset base name (default `"bn5cubegreen_bot"`) |
| Unlocking Animation Time | number | seconds (default `0`) |
| Unlocking Sound Path | string | sound file path (default `.../panel_change.ogg`) |
| Skip Prompt | bool | skip confirmation prompt |
| Description | string | text before lock prompt |
| Unlocked Message | string | after success |
| Unlock Failed Message | string | on failed unlock |

Unlock animation plays by spawning a temporary bot with the `UNLOCKING` animation and playing it for `Unlocking Animation Time` seconds.

---
## Module: ezmystery

Mystery Data are collectible objects that can yield items, money, or link to other mystery items.

### Mystery Data Object (`Type: "Mystery Data"` / `"Mystery Datum"`)

| Property | Type | Description |
|---|---:|---|
| Locked | bool | requires `"Unlocker"` item if true |
| Password Locked | string | requires password to obtain item. |
| Once | bool | hide permanently after collection |
| Type | string | `"keyitem"`, `"item"`, `"money"`, `"random"` |
| Name | string | item name (if Type is item/keyitem) |
| Description | string | (for keyitem) |
| Amount | number | (if Type is money) |
| Next 1..n | string | object IDs for nested random types |

**Random Mystery Data:** If `Type == "random"`, pick one of `Next 1..n` randomly and collect that instead — allows nested randomness.

> **Unlocker item requirement:** The system expects an item named `"Unlocker"` defined in items to open locked mystery data.

---

## Module: ezfarms

Implements farming features: tilling, planting, watering, growth, harvesting, weather interaction.

### Concepts & Tile States

Tile states tracked in area memory: `Dirt` (tilled), `DirtWet` (watered), `Grass` (untilled), plus **plant** growth stages.

Plants defined in `PlantData` with properties: `price`, `growth_time_multiplier`, `local GID`, `harvest range`.

Growth stages:
- `0` — seed
- `1..3` — growing
- `4` — ready
- `5` — dead

Use `FARM_TIMESCALE` (from config) to speed up or slow growth (multiplies real time).

### Special Objects & Tools

- **Water Refill** (`Type: "Water Refill"`) — refills `CyberWtrCan` to 50 water when interacting with tool
- **Reference Seed** — tile object used to detect first plant GID

Tools:
- `CyberHoe` — till / harvest
- `CyberWtrCan` — water
- `CyberScythe` — remove dead plants
- `GigFreez` — toggle weather (rain → snow → clear)
- **Seeds** named `<plant> seed` (e.g., `Parsnip seed`)

Tools selected via a BBS menu and stored in `player_tools`.

---

## Module: ezweather

Controls area weather by modifying area custom properties (animations, parallax, tint).

### Weather Types

- `rain` — foreground rain animation + blue camera tint
- `snow` — foreground snow + white tint
- `fog` — fog foreground, no tint
- `clear` — restore original values

### Area Properties Used by Weather

When weather starts, the following area properties are read and applied:

| Property | Used For |
|---|---|
| Rain Song | rain |
| Snow Song | snow |
| Foreground Animation | animation to set |
| Foreground Texture | texture path |
| Foreground Parallax | parallax value |
| Foreground Vel X / Vel Y | velocity |

Functions:

```lua
ezweather.start_rain_in_area(area_id)
ezweather.start_snow_in_area(area_id)
ezweather.start_fog_in_area(area_id)
ezweather.clear_weather_in_area(area_id)
ezweather.get_area_weather(area_id)
```

---

## Module: ezquests

Simple quest framework.

### Quest Definition (table)

A quest should be a Lua table:

```lua
local quest = {
  name = "Quest Name",
  handle_event_async = function(self, player_id, event_value) end,
  determine_state = function(self, player_id) return "state_string" end
}
```

Register with `ezquests.add_quest(quest)`.

### Player quest storage

Quest flags stored in `player_memory.quests[quest_name]` as a dictionary of flags. API includes:

- `ezquests.set_player_quest_flag(player_id, quest_name, flag_name, flag_state)`
- `ezquests.get_player_quest_flag(player_id, quest_name, flag_name)`
- `ezquests.clear_player_quest_flags(player_id, quest_name)`
- `ezquests.get_player_quest_state(player_id, quest_name)`
- `ezquests.quest_event(player_id, quest_name, event_value)`

**Example quest snippet**:

```lua
local quest_get_punched = {
  name = "Get Punched",
  handle_event_async = function(self, player_id, event_value)
    return async(function()
      local accepted = ezquests.get_player_quest_flag(player_id, self.name, 'accepted')
      if accepted or event_value == "accepted" then
        ezquests.set_player_quest_flag(player_id, self.name, event_value, true)
      end
      if event_value == 'reset' then
        ezquests.clear_player_quest_flags(player_id, self.name)
      end
    end)
  end,
  determine_state = function(self, player_id)
    if ezquests.get_player_quest_flag(player_id, self.name, 'punched') then
      return "punched"
    end
    if ezquests.get_player_quest_flag(player_id, self.name, 'accepted') then
      return "accepted"
    end
    return "unaccepted"
  end
}
```

---

## Module: ezmenus

Simplifies BBS menu handling with async iterators.

### Key features

- `ezmenus.open_menu(player_id, board_name, color, posts)` returns an emitter wrapping the board
- `:selection_once()` — async wait for a single selection, returns post ID
- `:async_iter("post_selection")` — iterate multiple selections
- Menu cleans up automatically on close

Example usage:

```lua
local menu = ezmenus.open_menu(player_id, "Choose", {r=255,g=255,b=255}, posts)
local choice = await(menu:selection_once())
```

---

## Item Definition Objects

Items are defined as map objects (commonly `"Shop Item"` or `"Item"`) and cached by `ezcache`.

| Property | Type | Required | Description |
|---|---:|:---:|---|
| Name | string | yes | internal item name used by memory & scripts |
| Type | string | yes | `"item"`, `"keyitem"`, `"money"` |
| Description | string | if `keyitem` | description for key item menu |
| Amount | number | if `money` | amount of zenny |
| Price | number | optional | price for shops |

Use object IDs to reference these in dialogues, shops, checks, and mystery data.

---

## Configuration (`ezconfig.lua`)

`ezconfig.lua` lives in the server root and defines paths and feature flags. Example:

```lua
return {
  -- Paths
  PLAYERS_PATH = "./memory/players",
  ITEMS_PATH = "./memory/items",
  AREA_PATH_FOLDER = "./memory/area/",
  PLAYER_PATH_FOLDER = "./memory/player/",
  NPC_ASSET_FOLDER = "/server/assets/ezlibs-assets/eznpcs/",
  NPC_EVENTS_SCRIPT_PATH = "scripts/ezlibs-custom/eznpcs_events",
  ENCOUNTERS_PATH = "scripts/ezlibs-custom/encounters/",

  -- Farm settings
  FARM_MAP = "farm",
  FARM_TIMESCALE = 1.0,

  -- Feature flags
  EZFARMS_ENABLED = true,
  EZCHRISTMAS_ENABLED = false,
}
```

---

## Custom Scripting & Plugins

Place custom plugins under `scripts/ezlibs-custom/` and require them in `custom.lua`. The main script will load `custom.lua` automatically if present.

A plugin can implement handlers (e.g., `handle_player_join`, `on_tick`, etc.) — check `main.lua` in the source for the full list.

### Listening & Emitting Global Events

Use `ezbus` to react to cross-module events or emit your own:

```lua
local ezbus = require('scripts/ezlibs-scripts/ezbus')
ezbus:on("lock_attempt", function(player_id, lock_type, success)
  if success then
    -- increment counter
  end
end)

ezbus:on("encounter_finished", function(player_id, stats)
  if not stats.ran and stats.health > 0 then
    -- award victory
  end
end)

ezbus:emit("my_event", ...)
```

---

## Appendix: Common Patterns

### Locks (Anti-Spam)

Always use locks to prevent duplicate interactions:

```lua
local lock = helpers.get_lock(player_id, "unique_lock_id")
if not lock then return end
-- do async work
lock.release()
```

Locks are released on disconnect.

### Async/Await Pattern

Wrap player-interaction code in `async` and use `await` for prompts/messages:

```lua
return async(function()
  local input = await(Async.prompt_player(player_id))
  -- ...
end)
```

---

## Notes & Next Steps

- This file is optimized for Markdown preview — headings, code blocks, and tables are intentionally formatted for GitHub / VSCode.
- If you want **anchor links per-function**, **a developer API table**, or **per-module README files**, tell me which one to generate next and I will create them.
- If any specific section needs expansion with code references from the source files, I can extract and embed them as examples.

---

*End of formatted developer reference.*
