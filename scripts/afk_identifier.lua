-- local timer = 0
-- local player_last_position = {}
-- local afk_check = {}


-- Net:on("player_connect", function(event)
--     player_last_position[event.player_id] = {afk = false, position = {x = 0,y = 0,z = 0}}
--     print(
--     player_last_position[event.player_id])
-- end)

-- Net:on("player_disconnect", function(event)
--     if player_last_position[event.player_id] ~= nil then
--         player_last_position[event.player_id] = nil
--         print("Player left the server, No longer tracking" ..event.player_id.. "...")
--     end
-- end)

-- function async(p)
--     local co = coroutine.create(p)
--     return Async.promisify(co)
-- end

-- Net:on("player_move", function(event)
--     local floor = math.floor
--     local rounded_pos_x = floor(event.x)
--     local rounded_pos_y = floor(event.y)
--     local rounded_pos_z = floor(event.z)
--     local last_tile = player_last_position[event.player_id]
--     if last_tile then
--         if last_tile.position.x ~= rounded_pos_x or last_tile.position.y ~= rounded_pos_y or last_tile.position.z ~= rounded_pos_z then
--             --player has moved to a different tile
--             player_last_position[event.player_id].position = {x=rounded_pos_x,y=rounded_pos_y,z=rounded_pos_z}
--             print("Player Moved")
--         end
--     end
-- end)


-- Net:on("tick", function(event)
--     timer = timer + event.delta_time
--     local player_last_tile = {}
--     if timer > 7 then
--       for k,v in pairs(player_last_position) do
--         if v.position.x ~= player_last_tile[k] then
--         player_last_tile[k] = Net.get_player_position(k)
--       end
--     end
--     end
--   if timer > 5 then
--     print("checking all players...")
--       for k,v in pairs(player_last_position) do
--         local floor = math.floor
--         local rounded_pos_x = floor(v.position.x)
--         local rounded_pos_y = floor(v.position.y)
--         local rounded_pos_z = floor(v.position.z)

--         if player_last_tile[k] then
--         if floor(player_last_tile[k].x) == rounded_pos_x or floor(player_last_tile[k].y) == rounded_pos_y or floor(player_last_tile[k].z) == rounded_pos_z then
--           Net.set_player_emote(k, 8, false)
--           end
--         end
--       end
--       timer = 0
--   end
-- end)
