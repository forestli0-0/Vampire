local weapons = require('weapons')
local enemies = require('enemies')

local scenarios = {}

local function cloneTable(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do
        if type(v) == 'table' then
            out[k] = cloneTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function clearList(list)
    if type(list) ~= 'table' then return end
    for i = #list, 1, -1 do
        table.remove(list, i)
    end
end

local function clearCombat(state)
    clearList(state.enemies)
    clearList(state.bullets)
    clearList(state.enemyBullets)
    state.areaFields = {}
    state.hitEffects = {}
    state.screenWaves = {}
    state._screenWaveCooldown = {}
    state.lightningLinks = {}
    state.chainLinks = {}
end

local function setWeaponLevel(state, key, level)
    local def = state.catalog and state.catalog[key]
    if not def then return false end

    state.inventory.weapons = state.inventory.weapons or {}

    if level <= 0 then
        state.inventory.weapons[key] = nil
        return true
    end

    local stats = cloneTable(def.base or {})
    for _ = 2, level do
        if def.onUpgrade then def.onUpgrade(stats) end
    end

    state.inventory.weapons[key] = { level = level, timer = 0, stats = stats }
    return true
end

local function spawnDummy(state, keyName, x, y)
    local k = keyName or 'dummy_pole'
    enemies.spawnEnemy(state, k, false, x, y)
end

local function aroundPlayer(state, dx, dy)
    local px, py = state.player.x, state.player.y
    return px + (dx or 0), py + (dy or 0)
end

scenarios.list = {
    {
        id = 'quake_stun',
        name = 'Earthquake: stun + ring sync',
        desc = 'Earthquake vs dummy; quick reset for tuning.'
    },
    {
        id = 'volt_chain',
        name = 'Volt: chain lightning',
        desc = 'Multiple dummies to see links + shock behavior.'
    },
    {
        id = 'freeze_shatter',
        name = 'Freeze -> Shatter',
        desc = 'Ice Ring stacks Freeze; Warhammer shatters.'
    },
    {
        id = 'oil_fire_gas',
        name = 'Oil + Fire + Gas fields',
        desc = 'Oil Bottle + Fire Wand interactions.'
    },
    {
        id = 'damage_showcase',
        name = 'Damage 2.0 Showcase',
        desc = 'Shield Lancer (Blue) & Armored Brute (Yellow) & Boss (Mix).'
    },
}

function scenarios.apply(state, id)
    state.noLevelUps = true
    state.benchmarkMode = false

    clearCombat(state)

    local px, py = aroundPlayer(state, 0, 0)

    if id == 'quake_stun' then
        state.testArena = true
        state.scenarioNoDirector = true
        state.debug = state.debug or {}
        state.debug.selectedDummy = 'dummy_pole'

        setWeaponLevel(state, 'earthquake', 1)
        local x, y = aroundPlayer(state, 160, 0)
        spawnDummy(state, 'dummy_pole', x, y)
        return true
    end

    if id == 'volt_chain' then
        state.testArena = false
        state.scenarioNoDirector = true

        setWeaponLevel(state, 'thunder_loop', 1)

        local x1, y1 = aroundPlayer(state, 160, -60)
        local x2, y2 = aroundPlayer(state, 240, 0)
        local x3, y3 = aroundPlayer(state, 160, 60)
        local x4, y4 = aroundPlayer(state, 320, 0)
        spawnDummy(state, 'dummy_pole', x1, y1)
        spawnDummy(state, 'dummy_pole', x2, y2)
        spawnDummy(state, 'dummy_pole', x3, y3)
        spawnDummy(state, 'dummy_pole', x4, y4)
        return true
    end

    if id == 'freeze_shatter' then
        state.testArena = true
        state.scenarioNoDirector = true
        state.debug = state.debug or {}
        state.debug.selectedDummy = 'dummy_pole'

        setWeaponLevel(state, 'ice_ring', 5)
        setWeaponLevel(state, 'heavy_hammer', 5)

        local x, y = aroundPlayer(state, 160, 0)
        spawnDummy(state, 'dummy_pole', x, y)
        return true
    end

    if id == 'oil_fire_gas' then
        state.testArena = true
        state.scenarioNoDirector = true
        state.debug = state.debug or {}
        state.debug.selectedDummy = 'dummy_pole'

        setWeaponLevel(state, 'oil_bottle', 5)
        setWeaponLevel(state, 'hellfire', 1)

        local x, y = aroundPlayer(state, 160, 0)
        spawnDummy(state, 'dummy_pole', x, y)
        return true
    end

    if id == 'damage_showcase' then
        state.testArena = true
        state.scenarioNoDirector = true
        state.debug = state.debug or {}
        state.debug.selectedDummy = 'dummy_pole'

        setWeaponLevel(state, 'wand', 1)
        
        -- Skeleton (Flesh)
        local x1, y1 = aroundPlayer(state, 120, -120)
        enemies.spawnEnemy(state, 'skeleton', false, x1, y1, {suppressSpawnText=true})
        
        -- Shield Lancer (Shield + Flesh)
        local x2, y2 = aroundPlayer(state, 240, -60)
        enemies.spawnEnemy(state, 'shield_lancer', false, x2, y2, {suppressSpawnText=true})
        
        -- Armored Brute (Armor + Flesh)
        local x3, y3 = aroundPlayer(state, 240, 60)
        enemies.spawnEnemy(state, 'armored_brute', false, x3, y3, {suppressSpawnText=true})
        
        -- Boss (Shield + Armor + Flesh)
        local x4, y4 = aroundPlayer(state, 120, 120)
        -- Spawning boss as regular enemy (not elite) but with boss type stats
        enemies.spawnEnemy(state, 'boss_treant', false, x4, y4, {suppressSpawnText=true})

        return true
    end

    return false
end

return scenarios
