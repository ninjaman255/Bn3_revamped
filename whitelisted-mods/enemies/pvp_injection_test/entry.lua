local package_id = "pvp_field"

function package_init(package)
  package:declare_package_id(package_id)
  package:set_name("Canodumb")
  package:set_description("Canodumb lua port!")
  -- package:set_speed(999)
  -- package:set_attack(999)
  -- package:set_health(9999)
  package:set_preview_texture_path(_modpath.."preview.png")
end

function package_build(player1_id, player2_id)
  player1_id
    :create_spawner(character_id, Rank.V2)
    :spawn_at(4, 2)

  player2_id
    :create_spawner(character_id, Rank.V1)
    :spawn_at(1, 1)
end
