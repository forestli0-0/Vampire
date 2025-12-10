local weapons = require('weapons')

local upgrades = {}

function upgrades.generateUpgradeOptions(state)
    local pool = {}
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
                table.insert(pool, {key=key, item=item})
            end
        end
    end

    state.upgradeOptions = {}
    for i = 1, 3 do
        if #pool == 0 then break end
        local rndIdx = math.random(#pool)
        local choice = pool[rndIdx]
        table.insert(state.upgradeOptions, {
            key = choice.key,
            type = choice.item.type,
            name = choice.item.name,
            desc = choice.item.desc,
            def = choice.item
        })
        table.remove(pool, rndIdx)
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
    if opt.type == 'weapon' then
        if not state.inventory.weapons[opt.key] then
            weapons.addWeapon(state, opt.key)
        else
            local w = state.inventory.weapons[opt.key]
            w.level = w.level + 1
            opt.def.onUpgrade(w.stats)
        end
    elseif opt.type == 'passive' then
        if not state.inventory.passives[opt.key] then state.inventory.passives[opt.key] = 0 end
        state.inventory.passives[opt.key] = state.inventory.passives[opt.key] + 1
        opt.def.onUpgrade()
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
