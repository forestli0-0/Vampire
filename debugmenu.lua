local upgrades = require('upgrades')
local weapons = require('weapons')
local enemies = require('enemies')
local enemyDefs = require('data.defs.enemies')
local progression = require('progression')

local debugmenu = {}

local modes = {'weapon', 'passive', 'augment', 'xp', 'enemy', 'test', 'effect'}
local effectOptions = {
    'NONE','FIRE','FREEZE','STATIC','BLEED','OIL','HEAVY','PUNCTURE','MAGNETIC','CORROSIVE','VIRAL','TOXIN','BLAST','GAS','RADIATION'
}

local function cloneStats(base)
    local copy = {}
    for k, v in pairs(base or {}) do
        if type(v) == 'table' then
            local t = {}
            for kk, vv in pairs(v) do t[kk] = vv end
            copy[k] = t
        else
            copy[k] = v
        end
    end
    if copy.area == nil then copy.area = 1 end
    if copy.pierce == nil then copy.pierce = 1 end
    if copy.amount == nil then copy.amount = 0 end
    return copy
end

local function fireEffectBullet(state, effect)
    local target = enemies.findNearestEnemy(state, 1200)
    local px, py = state.player.x, state.player.y
    local tx, ty
    if target then
        tx, ty = target.x, target.y
    else
        tx, ty = px + 300, py
    end
    local ang = math.atan2((ty or py) - py, (tx or px) - px)
    local speed = 520
    local dmg = state.debug.effectDamage or 0
    local eff = effect or 'NONE'
    local effectData = nil
    local effectType = nil
    if eff ~= 'NONE' then
        effectType = eff
        effectData = {}
        if eff == 'MAGNETIC' or eff == 'VIRAL' or eff == 'TOXIN' or eff == 'GAS' or eff == 'PUNCTURE' then
            effectData.duration = 6.0
        end
        if eff == 'MAGNETIC' then
            effectData.shieldMult = 1.75
        elseif eff == 'STATIC' then
            effectData.duration = 3.0
            effectData.range = 160
        elseif eff == 'FIRE' then
            effectData.heatDuration = 6.0
        elseif eff == 'FREEZE' then
            effectData.duration = 1.2
            effectData.fullFreeze = true
        elseif eff == 'BLAST' then
            effectData.duration = 6.0
        elseif eff == 'GAS' then
            effectData.range = 120
        elseif eff == 'RADIATION' then
            effectData.duration = 12.0
        end
    end
    table.insert(state.bullets, {
        type = 'debug_effect',
        x = px, y = py,
        vx = math.cos(ang) * speed, vy = math.sin(ang) * speed,
        life = 2.0,
        size = 16,
        damage = dmg,
        effectType = effectType,
        effectDuration = effectData and effectData.duration,
        effectRange = effectData and effectData.range,
        chain = effectData and effectData.chain,
        allowRepeat = effectData and effectData.allowRepeat,
        weaponTags = {'debug'},
        statusChance = 1.0,
        critChance = 0,
        critMultiplier = 1.5
    })
end

local function rebuildWeapon(state, key, level)
    local def = state.catalog[key]
    if not def then return end
    if level <= 0 then
        state.inventory.weapons[key] = nil
        return
    end
    local stats = cloneStats(def.base)
    for _ = 2, level do
        if def.onUpgrade then def.onUpgrade(stats) end
    end
    state.inventory.weapons[key] = { level = level, timer = 0, stats = stats }
end

local function downgradePassive(state, key)
    local curLv = state.inventory.passives[key] or 0
    if curLv <= 0 then return end
    local newLv = curLv - 1
    if key == 'boots' then
        -- boots onUpgrade multiplies moveSpeed by 1.1; invert on downgrade
        state.player.stats.moveSpeed = state.player.stats.moveSpeed / 1.1
    elseif key == 'attractorb' then
        state.player.stats.pickupRange = math.max(0, state.player.stats.pickupRange - 40)
    elseif key == 'pummarola' then
        state.player.stats.regen = math.max(0, state.player.stats.regen - 0.25)
    elseif key == 'armor' then
        state.player.stats.armor = math.max(0, state.player.stats.armor - 1)
    end
    if newLv == 0 then
        state.inventory.passives[key] = nil
    else
        state.inventory.passives[key] = newLv
    end
end

local function clampIndex(idx, list)
    if #list == 0 then return 1 end
    if idx < 1 then return #list end
    if idx > #list then return 1 end
    return idx
end

local function buildLists(state)
    local weaponsList, passivesList, augmentList = {}, {}, {}
    for key, item in pairs(state.catalog or {}) do
        if item.type == 'weapon' then table.insert(weaponsList, key) end
        if item.type == 'passive' then table.insert(passivesList, key) end
        if item.type == 'augment' then table.insert(augmentList, key) end
    end
    table.sort(weaponsList)
    table.sort(passivesList)
    table.sort(augmentList)
    state.debug.weaponList = weaponsList
    state.debug.passiveList = passivesList
    state.debug.augmentList = augmentList

    local enemyList, dummyList = {}, {}
    for key, _ in pairs(enemyDefs or {}) do
        table.insert(enemyList, key)
        if key:match("^dummy_") then table.insert(dummyList, key) end
    end
    table.sort(enemyList)
    table.sort(dummyList)
    state.debug.enemyList = enemyList
    state.debug.dummyList = dummyList
    state.debug.effectList = effectOptions
end

local function grantXp(state, amount)
    local p = state.player
    local defs = progression.defs or {}
    local rankCap = defs.rankCap or 30
    local xpGrowth = defs.xpGrowth or 1.5
    local xpCapValue = defs.xpCapValue or 999999999

    p.xp = p.xp + amount
    if state.noLevelUps or state.benchmarkMode then return end
    if p.level >= rankCap then
        p.xp = 0
        p.xpToNextLevel = xpCapValue
        return
    end
    local levelsGained = 0
    while p.xp >= p.xpToNextLevel do
        p.level = p.level + 1
        p.xp = p.xp - p.xpToNextLevel
        p.xpToNextLevel = math.floor(p.xpToNextLevel * xpGrowth)
        levelsGained = levelsGained + 1
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onLevelUp', {level = p.level, player = p})
        end
        upgrades.queueLevelUp(state, 'debug')
        if p.level >= rankCap then
            p.xp = 0
            p.xpToNextLevel = xpCapValue
            break
        end
    end
    if levelsGained > 0 then
        progression.applyRankUp(state)
        p.hp = p.maxHp or (p.stats and p.stats.maxHp) or 100
        p.shield = p.maxShield or (p.stats and p.stats.maxShield) or 100
        p.energy = p.maxEnergy or (p.stats and p.stats.maxEnergy) or 100
    end
end

function debugmenu.init(state)
    state.debug = state.debug or {}
    state.debug.open = false
    state.debug.modeIdx = 1
    state.debug.weaponIdx = 1
    state.debug.passiveIdx = 1
    state.debug.augmentIdx = 1
    state.debug.enemyIdx = 1
    state.debug.xpStep = 50
    state.debug.dummyIdx = 1
    state.debug.effectIdx = 1
    state.debug.effectDamage = 50
    state.debug.fireEffect = fireEffectBullet
    buildLists(state)
end

function debugmenu.keypressed(state, key)
    if key == 'f3' then
        state.debug.open = not state.debug.open
        return true
    end

    if not state.debug or not state.debug.open then return false end

    local mode = modes[state.debug.modeIdx]

    if key == 'tab' then
        state.debug.modeIdx = state.debug.modeIdx % #modes + 1
        return true
    end

    if mode == 'weapon' then
        if key == 'up' then
            state.debug.weaponIdx = clampIndex(state.debug.weaponIdx - 1, state.debug.weaponList)
            return true
        elseif key == 'down' then
            state.debug.weaponIdx = clampIndex(state.debug.weaponIdx + 1, state.debug.weaponList)
            return true
        elseif key == 'left' or key == 'backspace' then
            local keyName = state.debug.weaponList[state.debug.weaponIdx]
            local curLv = (state.inventory.weapons[keyName] and state.inventory.weapons[keyName].level) or 0
            if curLv > 0 then
                rebuildWeapon(state, keyName, curLv - 1)
            end
            return true
        elseif key == 'right' or key == 'return' then
            local keyName = state.debug.weaponList[state.debug.weaponIdx]
            local def = state.catalog[keyName]
            if def then upgrades.applyUpgrade(state, {key=keyName, type=def.type, def=def}) end
            return true
        end
    elseif mode == 'passive' then
        if key == 'up' then
            state.debug.passiveIdx = clampIndex(state.debug.passiveIdx - 1, state.debug.passiveList)
            return true
        elseif key == 'down' then
            state.debug.passiveIdx = clampIndex(state.debug.passiveIdx + 1, state.debug.passiveList)
            return true
        elseif key == 'left' or key == 'backspace' then
            local keyName = state.debug.passiveList[state.debug.passiveIdx]
            downgradePassive(state, keyName)
            return true
        elseif key == 'right' or key == 'return' then
            local keyName = state.debug.passiveList[state.debug.passiveIdx]
            local def = state.catalog[keyName]
            if def then upgrades.applyUpgrade(state, {key=keyName, type=def.type, def=def}) end
            return true
        end
    elseif mode == 'augment' then
        if key == 'up' then
            state.debug.augmentIdx = clampIndex(state.debug.augmentIdx - 1, state.debug.augmentList)
            return true
        elseif key == 'down' then
            state.debug.augmentIdx = clampIndex(state.debug.augmentIdx + 1, state.debug.augmentList)
            return true
        elseif key == 'left' or key == 'backspace' then
            local keyName = state.debug.augmentList[state.debug.augmentIdx]
            if keyName and state.inventory and state.inventory.augments and state.inventory.augments[keyName] then
                state.inventory.augments[keyName] = nil
                local order = state.inventory.augmentOrder or {}
                for i = #order, 1, -1 do
                    if order[i] == keyName then
                        table.remove(order, i)
                    end
                end
                if state.augmentState then state.augmentState[keyName] = nil end
            end
            return true
        elseif key == 'right' or key == 'return' then
            local keyName = state.debug.augmentList[state.debug.augmentIdx]
            local def = keyName and state.catalog[keyName]
            if def then upgrades.applyUpgrade(state, {key=keyName, type=def.type, def=def, name=def.name, desc=def.desc}) end
            return true
        end
    elseif mode == 'xp' then
        if key == 'up' then
            state.debug.xpStep = state.debug.xpStep + 10
            return true
        elseif key == 'down' then
            state.debug.xpStep = math.max(10, state.debug.xpStep - 10)
            return true
        elseif key == 'right' or key == 'return' then
            grantXp(state, state.debug.xpStep)
            return true
        end
    elseif mode == 'enemy' then
        if key == 'up' then
            state.debug.enemyIdx = clampIndex(state.debug.enemyIdx - 1, state.debug.enemyList)
            return true
        elseif key == 'down' then
            state.debug.enemyIdx = clampIndex(state.debug.enemyIdx + 1, state.debug.enemyList)
            return true
        elseif key == 'right' or key == 'return' then
            local keyName = state.debug.enemyList[state.debug.enemyIdx]
            if keyName then
                enemies.spawnEnemy(state, keyName, false)
                -- Move spawned enemy near player for quick testing
                local spawned = state.enemies[#state.enemies]
                if spawned then
                    spawned.x = state.player.x + math.random(-80, 80)
                    spawned.y = state.player.y + math.random(-80, 80)
                end
            end
            return true
        end
    elseif mode == 'test' then
        if key == 'up' then
            state.debug.dummyIdx = clampIndex(state.debug.dummyIdx - 1, state.debug.dummyList)
            return true
        elseif key == 'down' then
            state.debug.dummyIdx = clampIndex(state.debug.dummyIdx + 1, state.debug.dummyList)
            return true
        elseif key == 'left' or key == 'backspace' then
            state.testArena = not state.testArena
            if not state.testArena then state.debug.selectedDummy = nil end
            return true
        elseif key == 'right' or key == 'return' then
            local keyName = state.debug.dummyList[state.debug.dummyIdx] or 'dummy_pole'
            state.debug.selectedDummy = keyName
            for i = #state.enemies, 1, -1 do table.remove(state.enemies, i) end
            enemies.spawnEnemy(state, keyName, false, state.player.x + 140, state.player.y)
            state.testArena = true
            return true
        end
    elseif mode == 'effect' then
        if key == 'up' then
            state.debug.effectIdx = clampIndex(state.debug.effectIdx - 1, state.debug.effectList)
            return true
        elseif key == 'down' then
            state.debug.effectIdx = clampIndex(state.debug.effectIdx + 1, state.debug.effectList)
            return true
        elseif key == 'left' or key == 'backspace' then
            state.debug.effectDamage = math.max(0, (state.debug.effectDamage or 0) - 10)
            return true
        elseif key == 'right' then
            state.debug.effectDamage = (state.debug.effectDamage or 0) + 10
            return true
        elseif key == 'return' then
            local effect = state.debug.effectList[state.debug.effectIdx] or 'NONE'
            if state.debug.fireEffect then state.debug.fireEffect(state, effect) end
            return true
        end
    end

    return false
end

function debugmenu.draw(state)
    if not state.debug or not state.debug.open then return end
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle('fill', 10, 10, w - 20, 140)
    love.graphics.setColor(1, 1, 1)
    local mode = modes[state.debug.modeIdx]
    local y = 20
    love.graphics.print("DEBUG MENU (F3 to close) | Tab: cycle mode | Up/Down: select/adjust | Right/Enter: apply", 20, y)
    y = y + 20
    love.graphics.print("Mode: " .. mode, 20, y)
    y = y + 20

    if mode == 'weapon' then
        local list = state.debug.weaponList
        local keyName = list[state.debug.weaponIdx] or "N/A"
        local def = state.catalog[keyName] or {}
        local curLv = (state.inventory.weapons[keyName] and state.inventory.weapons[keyName].level) or 0
        love.graphics.print(string.format("Weapon: [%s]  Lv %d / %s  (%s)", keyName, curLv, def.maxLevel or "?", def.desc or ""), 20, y)
        y = y + 20
        love.graphics.print("Up/Down to pick, Right/Enter to add or level up", 20, y)
    elseif mode == 'passive' then
        local list = state.debug.passiveList
        local keyName = list[state.debug.passiveIdx] or "N/A"
        local def = state.catalog[keyName] or {}
        local curLv = state.inventory.passives[keyName] or 0
        love.graphics.print(string.format("Passive: [%s]  Lv %d / %s  (%s)", keyName, curLv, def.maxLevel or "?", def.desc or ""), 20, y)
        y = y + 20
        love.graphics.print("Up/Down to pick, Right/Enter to add or level up", 20, y)
    elseif mode == 'augment' then
        local list = state.debug.augmentList or {}
        local keyName = list[state.debug.augmentIdx] or "N/A"
        local def = state.catalog[keyName] or {}
        local curLv = (state.inventory.augments and state.inventory.augments[keyName]) or 0
        love.graphics.print(string.format("Augment: [%s]  Lv %d / %s  (%s)", keyName, curLv, def.maxLevel or "?", def.desc or ""), 20, y)
        y = y + 20
        love.graphics.print("Up/Down pick | Right/Enter add | Left/Backspace remove", 20, y)
    elseif mode == 'xp' then
        love.graphics.print(string.format("XP Step: %d  | Player Lv: %d  XP: %d / %d", state.debug.xpStep, state.player.level, state.player.xp, state.player.xpToNextLevel), 20, y)
        y = y + 20
        love.graphics.print("Up/Down to change step, Right/Enter to grant XP (triggers level-ups)", 20, y)
    elseif mode == 'enemy' then
        local list = state.debug.enemyList
        local keyName = list[state.debug.enemyIdx] or "N/A"
        love.graphics.print(string.format("Enemy: [%s] | Up/Down to pick, Right/Enter to spawn near player", keyName), 20, y)
    elseif mode == 'test' then
        local list = state.debug.dummyList
        local keyName = list[state.debug.dummyIdx] or "N/A"
        love.graphics.print(string.format("Test Arena: %s | Dummy: [%s]", state.testArena and "ON" or "OFF", keyName), 20, y)
        y = y + 20
        love.graphics.print("Right/Enter: clear & spawn dummy near player (enables test arena)", 20, y)
        y = y + 20
        love.graphics.print("Left/Backspace: toggle test arena on/off (spawns only selected dummy when on)", 20, y)
    elseif mode == 'effect' then
        local list = state.debug.effectList
        local keyName = list[state.debug.effectIdx] or "N/A"
        love.graphics.print(string.format("Effect Shot: [%s] | Damage: %d", keyName, state.debug.effectDamage or 0), 20, y)
        y = y + 20
        love.graphics.print("Up/Down select effect | Left/Backspace -10 dmg | Right +10 dmg | Enter: fire test bullet", 20, y)
    end
end

return debugmenu
