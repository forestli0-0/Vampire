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
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH'
    },
    bat = {
        hp = 5,
        speed = 120,
        size = 12,
        color = {0.6, 0, 1},
        healthType = 'FLESH'
    },
    plant = {
        hp = 30,
        speed = 35,
        size = 22,
        color = {0, 0.7, 0.2},
        healthType = 'INFESTED',
        shootInterval = 4,
        bulletSpeed = 180,
        bulletDamage = 10,
        bulletLife = 4,
        bulletSize = 10
    },
    charger = {
        hp = 18,
        speed = 70,
        size = 18,
        color = {0.95, 0.55, 0.15},
        healthType = 'INFESTED',
        contactDamage = 8,
        attacks = {
            charge = {range = 320, windup = 0.55, distance = 260, speed = 560, cooldown = 2.4, damage = 18, telegraphWidth = 36}
        }
    },
    spore_mortar = {
        hp = 26,
        speed = 38,
        size = 20,
        color = {0.75, 0.25, 0.95},
        healthType = 'INFESTED',
        attacks = {
            slam = {range = 420, windup = 0.85, radius = 120, cooldown = 3.0, damage = 16}
        }
    },
    dummy_pole = {
        hp = 800,
        shield = 0,
        armor = 0,
        speed = 0,
        size = 24,
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH',
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
        healthType = 'FLESH',
        shieldType = 'SHIELD',
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
        healthType = 'FLESH',
        armorType = 'FERRITE_ARMOR',
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
        healthType = 'CLONED_FLESH',
        shieldType = 'SHIELD',
        armorType = 'FERRITE_ARMOR',
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
        color = {0.2, 0.5, 1},
        healthType = 'CLONED_FLESH',
        shieldType = 'SHIELD',
        armorType = 'FERRITE_ARMOR'
    },
    armored_brute = {
        hp = 80,
        armor = 160,
        speed = 28,
        size = 24,
        color = {0.8, 0.6, 0.1},
        healthType = 'CLONED_FLESH',
        armorType = 'ALLOY_ARMOR'
    },
    boss_treant = {
        hp = 1200,
        shield = 600,
        armor = 120,
        speed = 35,
        size = 48,
        color = {0.9, 0.25, 0.25},
        spawnDistance = 620,
        shootInterval = 1.6,
        bulletSpeed = 220,
        bulletDamage = 16,
        bulletLife = 6,
        bulletSize = 14,
        animKey = 'plant',
        isBoss = true,
        noDrops = true,
        healthType = 'FOSSILIZED',
        shieldType = 'PROTO_SHIELD',
        armorType = 'INFESTED_SINEW'
    }
}

return enemyDefs
