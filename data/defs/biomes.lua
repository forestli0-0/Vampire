local defs = {
    {
        key = 'forest',
        name = 'Forest',
        boss = 'boss_treant',
        wallColor = {0.10, 0.11, 0.10},
        enemyTiers = {
            [1] = {skeleton = 7, bat = 4, plant = 2, charger = 1},
            [2] = {skeleton = 5, bat = 3, plant = 3, charger = 2, spore_mortar = 2}
        },
        worldExplore = {w = 112, h = 112, roomMin = 10, roomMax = 18, corridorWidth = 2},
        worldBoss = {w = 96, h = 96, roomMin = 34, roomMax = 44, corridorWidth = 2}
    },
    {
        key = 'factory',
        name = 'Factory',
        boss = 'boss_treant',
        wallColor = {0.11, 0.11, 0.13},
        enemyTiers = {
            [1] = {skeleton = 5, bat = 2, shield_lancer = 3, charger = 1},
            [2] = {skeleton = 3, shield_lancer = 4, armored_brute = 2, spore_mortar = 1, charger = 2}
        },
        worldExplore = {w = 112, h = 112, roomMin = 9, roomMax = 18, corridorWidth = 2},
        worldBoss = {w = 96, h = 96, roomMin = 34, roomMax = 44, corridorWidth = 2}
    },
    {
        key = 'void',
        name = 'Void',
        boss = 'boss_treant',
        wallColor = {0.12, 0.10, 0.14},
        enemyTiers = {
            [1] = {skeleton = 4, bat = 3, plant = 2, shield_lancer = 2, charger = 1},
            [2] = {skeleton = 3, bat = 2, plant = 2, shield_lancer = 3, armored_brute = 2, spore_mortar = 2, charger = 2}
        },
        worldExplore = {w = 112, h = 112, roomMin = 9, roomMax = 18, corridorWidth = 2},
        worldBoss = {w = 96, h = 96, roomMin = 34, roomMax = 44, corridorWidth = 2}
    }
}

return defs
