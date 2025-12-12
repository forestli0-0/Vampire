--[[
Template for adding new enemies:
enemyDefs.my_enemy = {
    hp = 10,              -- base health
    shield = 0,           -- optional shields (regenerates)
    armor = 0,            -- optional damage reduction
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
    },
    dummy_pole = {
        hp = 800,
        shield = 0,
        armor = 0,
        speed = 0,
        size = 24,
        color = {0.8, 0.8, 0.8},
        noContactDamage = true,
        noDrops = true,
        isDummy = true
    },
    dummy_shield = {
        hp = 600,
        shield = 300,
        armor = 0,
        speed = 0,
        size = 24,
        color = {0.6, 0.8, 1.0},
        noContactDamage = true,
        noDrops = true,
        isDummy = true
    },
    dummy_armor = {
        hp = 600,
        shield = 0,
        armor = 250,
        speed = 0,
        size = 24,
        color = {1.0, 0.9, 0.4},
        noContactDamage = true,
        noDrops = true,
        isDummy = true
    },
    dummy_full = {
        hp = 600,
        shield = 220,
        armor = 150,
        speed = 0,
        size = 24,
        color = {0.7, 0.9, 0.9},
        noContactDamage = true,
        noDrops = true,
        isDummy = true
    },
    shield_lancer = {
        hp = 22,
        shield = 24,
        armor = 15,
        speed = 55,
        size = 18,
        color = {0.2, 0.5, 1}
    },
    armored_brute = {
        hp = 80,
        armor = 160,
        speed = 28,
        size = 24,
        color = {0.8, 0.6, 0.1}
    }
}

return enemyDefs
