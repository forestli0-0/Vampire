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
        hp = 15,
        speed = 60,
        size = 24,
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH',
        attacks = {
            melee = {range = 45, windup = 0.4, cooldown = 1.8, damage = 8, w = 6},
            throw = {range = 200, rangeMin = 60, windup = 0.5, cooldown = 3.0, damage = 6, bulletSpeed = 200, bulletLife = 2, bulletSize = 8, w = 3}
        }
    },
    bat = {
        hp = 8,
        speed = 100,
        size = 18,
        color = {0.6, 0, 1},
        healthType = 'FLESH',
        attacks = {
            melee = {range = 35, windup = 0.25, cooldown = 1.0, damage = 5, w = 5},
            leap = {range = 150, rangeMin = 50, windup = 0.3, distance = 100, speed = 600, cooldown = 2.0, damage = 7, w = 4}
        }
    },
    plant = {
        hp = 45,
        speed = 35,
        size = 32,
        color = {0, 0.7, 0.2},
        healthType = 'INFESTED',
        attacks = {
            burst = {range = 400, rangeMin = 80, windup = 0.6, count = 3, spread = 0.4, bulletSpeed = 180, bulletDamage = 8, bulletLife = 4, bulletSize = 10, cooldown = 3.5, w = 10}
        }
    },
    charger = {
        hp = 27,
        speed = 70,
        size = 24,
        color = {0.95, 0.55, 0.15},
        healthType = 'INFESTED',
        attacks = {
            charge = {range = 320, rangeMin = 80, windup = 0.55, distance = 260, speed = 500, cooldown = 2.4, damage = 18, telegraphWidth = 40, w = 8},
            slam = {range = 80, windup = 0.6, radius = 60, cooldown = 2.0, damage = 12, w = 5}
        }
    },
    spore_mortar = {
        hp = 39,
        speed = 38,
        size = 28,
        color = {0.75, 0.25, 0.95},
        healthType = 'INFESTED',
        attacks = {
            slam = {range = 420, windup = 0.85, radius = 120, cooldown = 3.0, damage = 16, w = 7},
            burst = {range = 500, rangeMin = 150, windup = 0.7, count = 5, spread = 0.6, bulletSpeed = 160, bulletDamage = 6, bulletLife = 3, bulletSize = 8, cooldown = 4.0, w = 5}
        }
    },
    dummy_pole = {
        hp = 800,
        shield = 0,
        armor = 0,
        speed = 0,
        size = 32,
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
        size = 32,
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
        size = 32,
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
        size = 32,
        color = {0.7, 0.9, 0.9},
        healthType = 'CLONED_FLESH',
        shieldType = 'SHIELD',
        armorType = 'FERRITE_ARMOR',
        noContactDamage = true,
        noDrops = true,
        isDummy = true
    },
    shield_lancer = {
        hp = 33,
        shield = 36,
        armor = 22,
        speed = 55,
        size = 24,
        color = {0.2, 0.5, 1},
        healthType = 'CLONED_FLESH',
        shieldType = 'SHIELD',
        armorType = 'FERRITE_ARMOR',
        attacks = {
            melee = {range = 50, windup = 0.5, cooldown = 2.0, damage = 10, w = 5},
            shield_bash = {range = 120, windup = 0.4, distance = 80, speed = 400, cooldown = 3.0, damage = 12, knockback = 100, telegraphWidth = 30, w = 4}
        }
    },
    armored_brute = {
        hp = 120,
        armor = 240,
        speed = 28,
        size = 40,
        color = {0.8, 0.6, 0.1},
        healthType = 'CLONED_FLESH',
        armorType = 'ALLOY_ARMOR',
        attacks = {
            melee = {range = 60, windup = 0.7, cooldown = 2.5, damage = 18, w = 5},
            slam = {range = 100, windup = 1.0, radius = 100, cooldown = 4.0, damage = 25, w = 4}
        }
    },
    boss_treant = {
        hp = 1800,
        shield = 900,
        armor = 180,
        speed = 50,
        size = 64,
        color = {0.9, 0.25, 0.25},
        spawnDistance = 620,
        bulletSpeed = 220,
        bulletDamage = 16,
        bulletLife = 6,
        bulletSize = 14,
        contactDamage = 14,
        tenacity = 0.9,
        hardCcImmune = true,
        attacks = {
            -- 3 readable boss moves: cone burst (ranged), slam (AoE), charge (line dash)
            burst = {rangeMin = 260, range = 1200, w = 5, windup = 0.75, count = 7, spread = 0.95, bulletSpeed = 240, bulletDamage = 14, bulletLife = 6, bulletSize = 14, cooldown = 2.2, telegraphWidth = 58, telegraphLength = 520, interruptible = false},
            slam  = {range = 760, w = 3, windup = 1.25, radius = 150, cooldown = 2.8, damage = 20, interruptible = false},
            charge = {range = 420, w = 3, windup = 0.70, distance = 420, speed = 720, cooldown = 2.6, damage = 24, telegraphWidth = 56, interruptible = false}
        },
        animKey = 'plant',
        isBoss = true,
        noDrops = true,
        healthType = 'FOSSILIZED',
        shieldType = 'PROTO_SHIELD',
        armorType = 'INFESTED_SINEW'
    },
    -- ========== Batch 1: Simple Ranged Enemies (WF-style) ==========
    -- Lancer: Basic ranged rifleman, single accurate shots
    lancer = {
        hp = 18,
        speed = 50,
        size = 22,
        color = {0.6, 0.6, 0.7},
        healthType = 'CLONED_FLESH',
        attacks = {
            shoot = {range = 350, rangeMin = 100, windup = 0.6, cooldown = 1.8, 
                     count = 1, spread = 0.05, bulletSpeed = 320, bulletDamage = 10, 
                     bulletLife = 3, bulletSize = 6, w = 10}
        }
    },
    -- Heavy Gunner: Sustained fire suppression, armored
    heavy_gunner = {
        hp = 75,
        armor = 60,
        speed = 30,
        size = 32,
        color = {0.5, 0.4, 0.3},
        healthType = 'CLONED_FLESH',
        armorType = 'FERRITE_ARMOR',
        attacks = {
            burst = {range = 320, rangeMin = 80, windup = 0.4, cooldown = 2.0,
                     count = 6, spread = 0.35, bulletSpeed = 280, bulletDamage = 6, 
                     bulletLife = 2.5, bulletSize = 5, w = 10}
        }
    },
    -- Ballista: Sniper with long windup, high damage, telegraph line
    ballista = {
        hp = 25,
        speed = 25,
        size = 22,
        color = {0.4, 0.5, 0.6},
        healthType = 'CLONED_FLESH',
        attacks = {
            snipe = {range = 600, rangeMin = 200, windup = 1.2, cooldown = 4.0,
                     count = 1, spread = 0, bulletSpeed = 500, bulletDamage = 35, 
                     bulletLife = 3, bulletSize = 8, 
                     telegraphLength = 400, telegraphWidth = 8, w = 10}
        }
    },
    -- Bombard: Rocket launcher with AOE explosion
    bombard = {
        hp = 55,
        armor = 45,
        speed = 35,
        size = 28,
        color = {0.8, 0.3, 0.2},
        healthType = 'CLONED_FLESH',
        armorType = 'ALLOY_ARMOR',
        attacks = {
            rocket = {range = 400, rangeMin = 120, windup = 0.9, cooldown = 3.5,
                      count = 1, spread = 0, bulletSpeed = 200, bulletDamage = 28, 
                      bulletLife = 4, bulletSize = 14,
                      explosive = true, splashRadius = 70, w = 10}
        }
    }
}

return enemyDefs
