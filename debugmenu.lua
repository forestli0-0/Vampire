local upgrades = require('upgrades')
local weapons = require('weapons')
local enemies = require('enemies')
local enemyDefs = require('enemy_defs')

local debugmenu = {}

local modes = {'weapon', 'passive', 'xp', 'enemy'}

local function cloneStats(base)
    local copy = {}
    for k, v in pairs(base or {}) do copy[k] = v end
    return copy
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
    local weaponsList, passivesList = {}, {}
    for key, item in pairs(state.catalog or {}) do
        if item.type == 'weapon' then table.insert(weaponsList, key) end
        if item.type == 'passive' then table.insert(passivesList, key) end
    end
    table.sort(weaponsList)
    table.sort(passivesList)
    state.debug.weaponList = weaponsList
    state.debug.passiveList = passivesList

    local enemyList = {}
    for key, _ in pairs(enemyDefs or {}) do
        table.insert(enemyList, key)
    end
    table.sort(enemyList)
    state.debug.enemyList = enemyList
end

local function grantXp(state, amount)
    local p = state.player
    p.xp = p.xp + amount
    while p.xp >= p.xpToNextLevel do
        p.level = p.level + 1
        p.xp = p.xp - p.xpToNextLevel
        p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.5)
        upgrades.queueLevelUp(state)
    end
end

function debugmenu.init(state)
    state.debug = state.debug or {}
    state.debug.open = false
    state.debug.modeIdx = 1
    state.debug.weaponIdx = 1
    state.debug.passiveIdx = 1
    state.debug.enemyIdx = 1
    state.debug.xpStep = 50
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
    elseif mode == 'xp' then
        love.graphics.print(string.format("XP Step: %d  | Player Lv: %d  XP: %d / %d", state.debug.xpStep, state.player.level, state.player.xp, state.player.xpToNextLevel), 20, y)
        y = y + 20
        love.graphics.print("Up/Down to change step, Right/Enter to grant XP (triggers level-ups)", 20, y)
    elseif mode == 'enemy' then
        local list = state.debug.enemyList
        local keyName = list[state.debug.enemyIdx] or "N/A"
        love.graphics.print(string.format("Enemy: [%s] | Up/Down to pick, Right/Enter to spawn near player", keyName), 20, y)
    end
end

return debugmenu
