
function package_build(mob)
    mob:get_field():tile_at(3, 1):set_state(TileState.Lava)
    mob:get_field():tile_at(4, 3):set_state(TileState.Lava)
    mob:get_field():tile_at(2, 1):set_state(TileState.Holy)
    mob:get_field():tile_at(2, 2):set_state(TileState.Holy)
    mob:get_field():tile_at(2, 3):set_state(TileState.Holy)
    mob:get_field():tile_at(5, 1):set_state(TileState.Holy)
    mob:get_field():tile_at(5, 2):set_state(TileState.Holy)
    mob:get_field():tile_at(5, 3):set_state(TileState.Holy)

    --make_metalcube(mob, 3, 1)
    --make_metalcube(mob, 4, 3)
    mob:spawn_player(1, 1, 1)
    mob:spawn_player(2, math.floor(mob:get_field():width()), math.floor(mob:get_field():height()))

    --[[
    mob
        :create_spawner(character_id, Rank.V1)
        :spawn_at(4, 1)
    mob
        :create_spawner(character_id, Rank.V1)
        :spawn_at(5, 2)

    mob
        :create_spawner(character_id, Rank.V1)
        :spawn_at(6, 3)
        ]]

    mob:set_background(_modpath.."BG.png", _modpath.."BG.animation", 0.09, 0.08)
    mob:stream_music(_modpath.."iego-training.ogg", 2812, 65814)
end