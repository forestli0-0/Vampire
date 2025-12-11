local weapons = require('weapons')
local logger = require('logger')

local upgrades = {}

local function canEvolve(state, key)
    local def = state.catalog[key]
    if not def or not def.evolveInfo then return false end
    local w = state.inventory.weapons[key]
    if not w or w.level < def.maxLevel then return false end
    if def.evolveInfo.require and not state.inventory.passives[def.evolveInfo.require] then return false end
    if state.inventory.weapons[def.evolveInfo.target] then return false end
    return true
end

function upgrades.generateUpgradeOptions(state)
    local pool = {}
    local evolvePool = {}
    local added = {}
    local function addOption(list, opt)
        local key = opt.key .. (opt.evolveFrom or "")
        if not added[key] then
            table.insert(list, opt)
            added[key] = true
        end
    end

    for key, item in pairs(state.catalog) do
        -- evolved-only武器不进入随机池；已经进化后隐藏基础武器
        local skip = false
        if item.evolvedOnly then
            skip = true
        elseif item.type == 'weapon' and item.evolveInfo and state.inventory.weapons[item.evolveInfo.target] then
            skip = true
        end

        if not skip then
            local currentLevel = 0
            if item.type == 'weapon' and state.inventory.weapons[key] then currentLevel = state.inventory.weapons[key].level end
            if item.type == 'passive' and state.inventory.passives[key] then currentLevel = state.inventory.passives[key] end
            if currentLevel < item.maxLevel then
                addOption(pool, {key=key, type=item.type, name=item.name, desc=item.desc, def=item})
            end
        end

        -- 可进化时将进化体作为额外选项（不会重复出现）
        if item.type == 'weapon' and canEvolve(state, key) then
            local targetKey = item.evolveInfo.target
            local target = state.catalog[targetKey]
            addOption(evolvePool, {
                key = targetKey,
                type = target.type,
                name = target.name,
                desc = "Evolve " .. item.name .. " into " .. target.name,
                def = target,
                evolveFrom = key
            })
        end
    end

    state.upgradeOptions = {}
    -- 若有进化候选，优先保底塞入 1 个
    local function takeRandom(list)
        if #list == 0 then return nil end
        local idx = math.random(#list)
        local opt = list[idx]
        table.remove(list, idx)
        return opt
    end

    if #evolvePool > 0 then
        table.insert(state.upgradeOptions, takeRandom(evolvePool))
    end

    for i = #state.upgradeOptions + 1, 3 do
        local choice = takeRandom(pool)
        if not choice then
            choice = takeRandom(evolvePool)
        end
        if not choice then break end
        table.insert(state.upgradeOptions, choice)
    end
end

function upgrades.queueLevelUp(state)
    state.pendingLevelUps = state.pendingLevelUps + 1
    if state.gameState ~= 'LEVEL_UP' then
        state.pendingLevelUps = state.pendingLevelUps - 1
        upgrades.generateUpgradeOptions(state)
        state.gameState = 'LEVEL_UP'
    end
end

function upgrades.applyUpgrade(state, opt)
    if opt.evolveFrom then
        -- 直接进化：移除基础武器，添加目标武器
        state.inventory.weapons[opt.evolveFrom] = nil
        weapons.addWeapon(state, opt.key)
        logger.upgrade(state, opt, 1)
        return
    elseif opt.type == 'weapon' then
        if not state.inventory.weapons[opt.key] then
            weapons.addWeapon(state, opt.key)
            logger.upgrade(state, opt, 1)
        else
            local w = state.inventory.weapons[opt.key]
            w.level = w.level + 1
            if opt.def.onUpgrade then opt.def.onUpgrade(w.stats) end
            logger.upgrade(state, opt, w.level)
        end
    elseif opt.type == 'passive' then
        if not state.inventory.passives[opt.key] then state.inventory.passives[opt.key] = 0 end
        state.inventory.passives[opt.key] = state.inventory.passives[opt.key] + 1
        logger.upgrade(state, opt, state.inventory.passives[opt.key])
        if opt.def.onUpgrade then opt.def.onUpgrade() end
    end
end

function upgrades.tryEvolveWeapon(state)
    for key, w in pairs(state.inventory.weapons) do
        local def = state.catalog[key]
        if def.evolveInfo and w.level >= def.maxLevel then
            local req = def.evolveInfo.require
            if state.inventory.passives[req] then
                local targetKey = def.evolveInfo.target
                local targetDef = state.catalog[targetKey]
                state.inventory.weapons[key] = nil
                weapons.addWeapon(state, targetKey)
                return targetDef.name
            end
        end
    end
    return nil
end

return upgrades
