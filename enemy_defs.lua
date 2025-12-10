--[[
Template for adding new enemies:
enemyDefs.my_enemy = {
    hp = 10,              -- base health
    speed = 50,           -- movement speed toward player
    size = 16,            -- hitbox size (square)
    color = {1, 1, 1},    -- draw color
    spawnDistance = 500,  -- optional spawn radius from player
    -- Optional shooting behavior (omit for melee-only enemies)
    shootInterval = 3,    -- seconds between shots
    bulletSpeed = 180,
    bulletDamage = 10,
    bulletLife = 5,
    bulletSize = 10
}
]]

local enemyDefs = {
    skeleton = {
        hp = 10,
        speed = 50,
        size = 16,
        color = {0.8, 0.8, 0.8}
    },
    bat = {
        hp = 5,
        speed = 150,
        size = 12,
        color = {0.6, 0, 1}
    },
    plant = {
        hp = 35,
        speed = 30,
        size = 22,
        color = {0, 0.7, 0.2},
        shootInterval = 3,
        bulletSpeed = 180,
        bulletDamage = 10,
        bulletLife = 5,
        bulletSize = 10
    }
}

return enemyDefs
