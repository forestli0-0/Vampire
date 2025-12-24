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
        hp = 45,  -- 15 → 45 (3x for early game)
        speed = 60,
        size = 24,
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH',
        attacks = {
            melee = {range = 45, windup = 0.4, cooldown = 1.2, damage = 18, w = 6},  -- +50% dmg
            throw = {range = 200, rangeMin = 60, windup = 0.5, cooldown = 2.0, damage = 15, bulletSpeed = 365, bulletLife = 2, bulletSize = 8, w = 3}  -- +50% dmg
        },
        -- AI行为配置：近战型
        aiBehavior = {
            type = 'melee',
            retreatThreshold = 0.2,
            retreatDuration = 1.0,
        }
    },
    bat = {
        hp = 25,  -- 8 → 25 (3x for early game)
        speed = 100,
        size = 18,
        color = {0.6, 0, 1},
        healthType = 'FLESH',
        attacks = {
            melee = {range = 35, windup = 0.25, cooldown = 0.6, damage = 12, w = 5},  -- +50% dmg
            leap = {range = 150, rangeMin = 50, windup = 0.3, distance = 100, speed = 600, cooldown = 1.4, damage = 18, w = 4}  -- +50% dmg
        }
    },
    plant = {
        hp = 90,  -- 45 → 90 (2x for mid game)
        speed = 35,
        size = 32,
        color = {0, 0.7, 0.2},
        healthType = 'INFESTED',
        attacks = {
            burst = {range = 400, rangeMin = 80, windup = 0.6, count = 3, spread = 0.4, bulletSpeed = 340, bulletDamage = 18, bulletLife = 4, bulletSize = 10, cooldown = 3.5, w = 10}  -- +50% dmg
        },
        -- AI行为配置：远程型（风筝）
        aiBehavior = {
            type = 'ranged',
            preferredRange = 320,
            kiteRange = 140,
            retreatThreshold = 0.2,
            retreatDuration = 0.8,
        }
    },
    charger = {
        hp = 55,  -- 27 → 55 (2x for mid game)
        speed = 70,
        size = 24,
        color = {0.95, 0.55, 0.15},
        healthType = 'INFESTED',
        attacks = {
            charge = {range = 320, rangeMin = 80, windup = 0.55, distance = 260, speed = 500, cooldown = 1.6, damage = 40, telegraphWidth = 40, w = 8},  -- +43% dmg
            slam = {range = 80, windup = 0.6, radius = 60, cooldown = 1.4, damage = 25, w = 5}  -- +39% dmg
        },
        -- AI行为配置：冲锋型（更鲁莽）
        aiBehavior = {
            type = 'charger',
            retreatThreshold = 0.15,
            retreatDuration = 0.6,
        }
    },
    spore_mortar = {
        hp = 80,  -- 39 → 80 (2x for mid game)
        speed = 38,
        size = 28,
        color = {0.75, 0.25, 0.95},
        healthType = 'INFESTED',
        attacks = {
            slam = {range = 420, windup = 0.85, radius = 120, cooldown = 3.0, damage = 22, w = 7},  -- 16 → 22
            burst = {range = 500, rangeMin = 150, windup = 0.7, count = 5, spread = 0.6, bulletSpeed = 310, bulletDamage = 10, bulletLife = 3, bulletSize = 8, cooldown = 4.0, w = 5}  -- 6 → 10
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
        hp = 65,  -- 33 → 65 (2x)
        shield = 70,  -- 36 → 70 (2x)
        armor = 30,  -- 22 → 30
        speed = 55,
        size = 24,
        color = {0.2, 0.5, 1},
        healthType = 'CLONED_FLESH',
        shieldType = 'SHIELD',
        armorType = 'FERRITE_ARMOR',
        attacks = {
            melee = {range = 50, windup = 0.5, cooldown = 2.0, damage = 15, w = 5},  -- 10 → 15
            shield_bash = {range = 120, windup = 0.4, distance = 80, speed = 400, cooldown = 3.0, damage = 18, knockback = 100, telegraphWidth = 30, w = 4}  -- 12 → 18
        }
    },
    armored_brute = {
        hp = 200,  -- 120 → 200 (1.7x)
        armor = 300,  -- 240 → 300
        speed = 28,
        size = 40,
        color = {0.8, 0.6, 0.1},
        healthType = 'CLONED_FLESH',
        armorType = 'ALLOY_ARMOR',
        attacks = {
            melee = {range = 60, windup = 0.7, cooldown = 2.5, damage = 25, w = 5},  -- 18 → 25
            slam = {range = 100, windup = 1.0, radius = 100, cooldown = 4.0, damage = 35, w = 4}  -- 25 → 35
        }
    },
    boss_treant = {
        hp = 3600,  -- 1800 → 3600 (2x)
        shield = 1500,  -- 900 → 1500
        armor = 250,  -- 180 → 250
        speed = 50,
        size = 64,
        color = {0.9, 0.25, 0.25},
        spawnDistance = 620,
        bulletSpeed = 220,
        bulletDamage = 22,  -- 16 → 22
        bulletLife = 6,
        bulletSize = 14,
        contactDamage = 20,  -- 14 → 20
        tenacity = 0.9,
        hardCcImmune = true,
        attacks = {
            -- 3 readable boss moves: cone burst (ranged), slam (AoE), charge (line dash)
            burst = {rangeMin = 260, range = 1200, w = 5, windup = 0.75, count = 7, spread = 0.95, bulletSpeed = 240, bulletDamage = 20, bulletLife = 6, bulletSize = 14, cooldown = 2.2, telegraphWidth = 58, telegraphLength = 520, interruptible = false},  -- 14 → 20
            slam  = {range = 760, w = 3, windup = 1.25, radius = 150, cooldown = 2.8, damage = 30, interruptible = false},  -- 20 → 30
            charge = {range = 420, w = 3, windup = 0.70, distance = 420, speed = 720, cooldown = 2.6, damage = 35, telegraphWidth = 56, interruptible = false}  -- 24 → 35
        },
        animKey = 'plant',
        isBoss = true,
        noDrops = true,
        healthType = 'FOSSILIZED',
        shieldType = 'PROTO_SHIELD',
        armorType = 'INFESTED_SINEW',
        -- AI行为配置：Boss狂暴
        aiBehavior = {
            type = 'boss',
            berserkThreshold = 0.25,
            berserkSpeedMult = 1.5,
            berserkDamageMult = 1.35,
            noRetreat = true,
        }
    },
    -- ========== Batch 1: Simple Ranged Enemies (WF-style) ==========
    -- Lancer: Basic ranged rifleman, single accurate shots
    lancer = {
        hp = 40,  -- 18 → 40 (2.2x)
        speed = 50,
        size = 22,
        color = {0.6, 0.6, 0.7},
        healthType = 'CLONED_FLESH',
        attacks = {
            shoot = {range = 350, rangeMin = 100, windup = 0.6, cooldown = 1.2, 
                     count = 1, spread = 0.05, bulletSpeed = 585, bulletDamage = 15,  -- cooldown 1.8 → 1.2
                     bulletLife = 3, bulletSize = 6, w = 10}
        },
        -- AI行为配置：远程型（风筝）
        aiBehavior = {
            type = 'ranged',
            preferredRange = 280,
            kiteRange = 120,
            retreatThreshold = 0.25,
        }
    },
    -- Heavy Gunner: Sustained fire suppression, armored
    heavy_gunner = {
        hp = 140,  -- 75 → 140 (1.9x)
        armor = 80,  -- 60 → 80
        speed = 30,
        size = 32,
        color = {0.5, 0.4, 0.3},
        healthType = 'CLONED_FLESH',
        armorType = 'FERRITE_ARMOR',
        attacks = {
            burst = {range = 320, rangeMin = 80, windup = 0.4, cooldown = 2.0,
                     count = 6, spread = 0.35, bulletSpeed = 495, bulletDamage = 10,  -- 6 → 10
                     bulletLife = 2.5, bulletSize = 5, w = 10}
        },
        -- AI行为配置：远程型（不风筝，坦克）
        aiBehavior = {
            type = 'ranged',
            preferredRange = 200,
            retreatThreshold = 0.15,  -- 重装不容易逃跑
        }
    },
    -- Ballista: Sniper with long windup, high damage, telegraph line
    ballista = {
        hp = 50,  -- 25 → 50 (2x)
        speed = 25,
        size = 22,
        color = {0.4, 0.5, 0.6},
        healthType = 'CLONED_FLESH',
        attacks = {
            snipe = {range = 600, rangeMin = 200, windup = 1.2, cooldown = 4.0,
                     count = 1, spread = 0, bulletSpeed = 845, bulletDamage = 45,  -- 35 → 45
                     bulletLife = 3, bulletSize = 8, 
                     telegraphLength = 400, telegraphWidth = 8, w = 10}
        }
    },
    -- Bombard: Rocket launcher with AOE explosion
    bombard = {
        hp = 100,  -- 55 → 100 (1.8x)
        armor = 60,  -- 45 → 60
        speed = 35,
        size = 28,
        color = {0.8, 0.3, 0.2},
        healthType = 'CLONED_FLESH',
        armorType = 'ALLOY_ARMOR',
        attacks = {
            rocket = {range = 400, rangeMin = 120, windup = 0.9, cooldown = 3.5,
                      count = 1, spread = 0, bulletSpeed = 390, bulletDamage = 40,  -- 28 → 40
                      bulletLife = 4, bulletSize = 14,
                      explosive = true, splashRadius = 70, w = 10}
        }
    },
    -- ========== Batch 2: Complex Enemies with Special Mechanics ==========
    -- Scorpion: Grapple hook that pulls player closer
    scorpion = {
        hp = 60,  -- 30 → 60 (2x)
        speed = 65,
        size = 24,
        color = {0.9, 0.7, 0.2},
        healthType = 'CLONED_FLESH',
        attacks = {
            grapple = {range = 280, rangeMin = 80, windup = 0.5, cooldown = 5.0,
                       pullDistance = 120, damage = 12, telegraphWidth = 12, w = 6},  -- 8 → 12
            melee = {range = 45, windup = 0.35, cooldown = 1.5, damage = 15, w = 5}  -- 10 → 15
        }
    },
    -- Ancient Healer: Aura that heals nearby enemies
    ancient_healer = {
        hp = 150,  -- 90 → 150 (1.7x)
        speed = 45,
        size = 36,
        color = {0.3, 0.8, 0.4},
        healthType = 'INFESTED',
        healAura = {radius = 160, healRate = 12},  -- heals 12 HP/sec to nearby enemies (8 → 12)
        attacks = {
            melee = {range = 55, windup = 0.6, cooldown = 2.2, damage = 18, w = 10}  -- 12 → 18
        },
        -- AI行为配置：支援型（更容易撤退）
        aiBehavior = {
            type = 'support',
            retreatThreshold = 0.4,  -- 治疗者更容易撤退
            retreatDuration = 1.8,
        }
    },
    -- Volatile Runner: Fast suicidal exploder
    volatile_runner = {
        hp = 20,  -- 12 → 20 (1.7x)
        speed = 110,
        size = 18,
        color = {1.0, 0.4, 0.1},
        healthType = 'INFESTED',
        onDeath = {explosionRadius = 80, damage = 45},  -- 30 → 45
        attacks = {
            suicide = {range = 35, windup = 0.15, cooldown = 999,
                       damage = 50, explosionRadius = 80, w = 10}  -- 35 → 50
        },
        -- AI行为配置：自爆型（不撤退）
        aiBehavior = {
            type = 'suicide',
            noRetreat = true,
        }
    },
    -- Nullifier: Bubble that blocks player abilities
    nullifier = {
        hp = 80,  -- 50 → 80 (1.6x)
        shield = 250,  -- 180 → 250
        speed = 40,
        size = 26,
        color = {0.3, 0.4, 0.8},
        healthType = 'CLONED_FLESH',
        shieldType = 'PROTO_SHIELD',
        nullBubble = {radius = 100},  -- disables abilities in this radius
        attacks = {
            shoot = {range = 280, rangeMin = 60, windup = 0.5, cooldown = 2.0,
                     count = 1, spread = 0.1, bulletSpeed = 415, bulletDamage = 12,  -- 8 → 12
                     bulletLife = 2.5, bulletSize = 6, w = 10}
        }
    }
}

return enemyDefs
