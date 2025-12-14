local weapons = require('weapons')
local logger = require('logger')

local upgrades = {}

function upgrades.getMaxWeapons(state)
    local max = (state and state.maxWeaponsPerRun) or 6
    max = tonumber(max) or 6
    return math.max(0, math.floor(max))
end

function upgrades.countWeapons(state)
    local n = 0
    for _, _ in pairs(state.inventory.weapons or {}) do
        n = n + 1
    end
    return n
end

function upgrades.getWeaponKeys(state)
    local keys = {}
    for k, _ in pairs(state.inventory.weapons or {}) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

local function canEvolve(state, key)
    local def = state.catalog[key]
    if not def or not def.evolveInfo then return false end
    local w = state.inventory.weapons[key]
    if not w or w.level < def.maxLevel then return false end
    if def.evolveInfo.require and not state.inventory.passives[def.evolveInfo.require] then return false end
    if state.inventory.weapons[def.evolveInfo.target] then return false end
    return true
end

function upgrades.generateUpgradeOptions(state, request, allowFallback)
    if allowFallback == nil then allowFallback = true end
    local poolExisting = {}
    local poolNew = {}
    local evolvePool = {}
    local added = {}
    local function addOption(list, opt)
        local key = opt.key .. (opt.evolveFrom or "")
        if not added[key] then
            table.insert(list, opt)
            added[key] = true
        end
    end

    local function isOwned(itemType, itemKey)
        if itemType == 'weapon' then return state.inventory.weapons[itemKey] ~= nil end
        if itemType == 'passive' then return state.inventory.passives[itemKey] ~= nil end
        if itemType == 'mod' then return state.profile and state.profile.ownedMods and state.profile.ownedMods[itemKey] == true end
        if itemType == 'augment' then return state.inventory.augments and state.inventory.augments[itemKey] ~= nil end
        return false
    end

    local augmentCap = state.maxAugmentsPerRun or 4
    local function countAugments()
        local n = 0
        for _, lvl in pairs(state.inventory.augments or {}) do
            if (lvl or 0) > 0 then n = n + 1 end
        end
        return n
    end

    local function countWeapons()
        return upgrades.countWeapons(state)
    end

    local allowedTypes = request and request.allowedTypes
    local function typeAllowed(t)
        if type(allowedTypes) ~= 'table' then return true end
        if next(allowedTypes) == nil then return true end
        if allowedTypes[t] then return true end
        for _, v in ipairs(allowedTypes) do
            if v == t then return true end
        end
        return false
    end

    local allowInRunMods = state and state.allowInRunMods
    if allowInRunMods == nil then allowInRunMods = false end

    for key, item in pairs(state.catalog) do
        if item and item.type and not typeAllowed(item.type) then
            goto continue_catalog
        end

        -- evolved-only武器不进入随机池；已经进化后隐藏基础武器
        local skip = false
        if item.evolvedOnly then
            skip = true
        elseif item.type == 'weapon' and item.evolveInfo and state.inventory.weapons[item.evolveInfo.target] then
            skip = true
        end

        if not skip then
            -- Mods are loadout-only by default; when enabled, allow drawing owned-but-unequipped mods in-run.
            if item.type == 'mod' then
                if not allowInRunMods then
                    goto continue_catalog
                end
                local owned = state.profile and state.profile.ownedMods and state.profile.ownedMods[key]
                if not owned then
                    goto continue_catalog
                end
            end
            if item.type == 'augment' and not (state.inventory.augments and state.inventory.augments[key]) then
                if countAugments() >= augmentCap then
                    goto continue_catalog
                end
            end
            local currentLevel = 0
            if item.type == 'weapon' and state.inventory.weapons[key] then currentLevel = state.inventory.weapons[key].level end
            if item.type == 'passive' and state.inventory.passives[key] then currentLevel = state.inventory.passives[key] end
            if item.type == 'mod' then
                local profile = state.profile
                local r = profile and profile.modRanks and profile.modRanks[key]
                if r ~= nil then
                    currentLevel = r
                elseif profile and profile.ownedMods and profile.ownedMods[key] then
                    currentLevel = 1
                end
            end
            if item.type == 'augment' and state.inventory.augments and state.inventory.augments[key] then currentLevel = state.inventory.augments[key] end
            if currentLevel < item.maxLevel then
                local opt = {key=key, type=item.type, name=item.name, desc=item.desc, def=item}
                if isOwned(item.type, key) then
                    addOption(poolExisting, opt)
                else
                    addOption(poolNew, opt)
                end
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
        ::continue_catalog::
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

    local function hasType(options, wanted)
        for _, opt in ipairs(options or {}) do
            if opt and opt.type == wanted then return true end
        end
        return false
    end

    local function takeRandomOfType(list, wanted)
        if #list == 0 then return nil end
        local candidates = {}
        for i, opt in ipairs(list) do
            if opt and opt.type == wanted then
                table.insert(candidates, i)
            end
        end
        if #candidates == 0 then return nil end
        local pick = candidates[math.random(#candidates)]
        local opt = list[pick]
        table.remove(list, pick)
        return opt
    end

    if #evolvePool > 0 then
        table.insert(state.upgradeOptions, takeRandom(evolvePool))
    end

    local runLevel = (state.player and state.player.level) or 1
    local preferExistingChance = 0.7
    if runLevel <= 6 then
        preferExistingChance = 0.35
    elseif runLevel <= 12 then
        preferExistingChance = 0.55
    end

    local maxWeapons = upgrades.getMaxWeapons(state)
    local weaponsOwned = countWeapons()
    if maxWeapons > 0 and weaponsOwned >= maxWeapons then
        preferExistingChance = math.min(0.92, preferExistingChance + 0.25)
    end

    -- Early feel: ensure at least one "new route" option (weapon/augment) when possible.
    if #state.upgradeOptions < 3 then
        if typeAllowed('weapon') and weaponsOwned < math.min(2, math.max(1, maxWeapons)) and not hasType(state.upgradeOptions, 'weapon') then
            local forcedWeapon = takeRandomOfType(poolNew, 'weapon')
            if forcedWeapon then
                table.insert(state.upgradeOptions, forcedWeapon)
            end
        end
    end
    if #state.upgradeOptions < 3 and runLevel <= 6 then
        if typeAllowed('augment') and countAugments() == 0 and not hasType(state.upgradeOptions, 'augment') then
            local forcedAug = takeRandomOfType(poolNew, 'augment')
            if forcedAug then
                table.insert(state.upgradeOptions, forcedAug)
            end
        end
    end

    for i = #state.upgradeOptions + 1, 3 do
        local choice = nil
        -- 现有/新选项混合：偏向现有，但保留一定随机新路线
        local preferExisting = (#poolExisting > 0) and (math.random() < preferExistingChance or #poolNew == 0)
        if preferExisting then
            choice = takeRandom(poolExisting)
        else
            choice = takeRandom(poolNew)
        end
        if not choice then choice = takeRandom(poolExisting) end
        if not choice then choice = takeRandom(poolNew) end
        if not choice then choice = takeRandom(evolvePool) end
        if not choice then break end
        table.insert(state.upgradeOptions, choice)
    end

    if runLevel <= 6
        and (typeAllowed('weapon') or typeAllowed('augment'))
        and not (hasType(state.upgradeOptions, 'weapon') or hasType(state.upgradeOptions, 'augment')) then
        local forced = takeRandomOfType(poolNew, 'weapon') or takeRandomOfType(poolNew, 'augment')
        if forced then
            state.upgradeOptions[#state.upgradeOptions] = forced
        end
    end

    if #state.upgradeOptions == 0 and allowFallback and type(allowedTypes) == 'table' and next(allowedTypes) ~= nil then
        return upgrades.generateUpgradeOptions(state, nil, false)
    end

    local ctx = {options = state.upgradeOptions, player = state.player, request = request}
    dispatch(state, 'onUpgradeOptions', ctx)
    if ctx.options and ctx.options ~= state.upgradeOptions then
        state.upgradeOptions = ctx.options
    end
end

function upgrades.queueLevelUp(state, reason, request)
    if state.noLevelUps or state.benchmarkMode then return end

    state.pendingLevelUps = state.pendingLevelUps or 0
    state.pendingUpgradeRequests = state.pendingUpgradeRequests or {}
    request = request or {}
    request.reason = request.reason or reason or 'unknown'

    dispatch(state, 'onUpgradeQueued', {reason = request.reason, player = state.player, request = request})

    if state.gameState == 'LEVEL_UP' then
        state.pendingLevelUps = state.pendingLevelUps + 1
        table.insert(state.pendingUpgradeRequests, request)
        return
    end

    state.activeUpgradeRequest = request
    upgrades.generateUpgradeOptions(state, request)
    state.gameState = 'LEVEL_UP'
end

function upgrades.applyUpgrade(state, opt)
    if opt.evolveFrom then
        -- 直接进化：移除基础武器，添加目标武器
        local carryMods = state.inventory and state.inventory.weaponMods and state.inventory.weaponMods[opt.evolveFrom]
        state.inventory.weapons[opt.evolveFrom] = nil
        weapons.addWeapon(state, opt.key)
        if carryMods and state.inventory and state.inventory.weaponMods then
            state.inventory.weaponMods[opt.key] = carryMods
            state.inventory.weaponMods[opt.evolveFrom] = nil
        end
        logger.upgrade(state, opt, 1)
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
        return
    elseif opt.type == 'weapon' then
        if not state.inventory.weapons[opt.key] then
            weapons.addWeapon(state, opt.key)
            logger.upgrade(state, opt, 1)
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
        else
            local w = state.inventory.weapons[opt.key]
            w.level = w.level + 1
            if opt.def.onUpgrade then opt.def.onUpgrade(w.stats) end
            logger.upgrade(state, opt, w.level)
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = w.level})
        end
    elseif opt.type == 'passive' then
        if not state.inventory.passives[opt.key] then state.inventory.passives[opt.key] = 0 end
        state.inventory.passives[opt.key] = state.inventory.passives[opt.key] + 1
        logger.upgrade(state, opt, state.inventory.passives[opt.key])
        if opt.def.onUpgrade then opt.def.onUpgrade() end
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = state.inventory.passives[opt.key]})
    elseif opt.type == 'mod' then
        -- Mods are loadout-only and apply per-weapon when equipped.
        -- If enabled as an in-run reward (debug), treat this as ranking up the mod and refresh weapon loadouts.
        state.profile = state.profile or {}
        state.profile.modRanks = state.profile.modRanks or {}
        state.profile.ownedMods = state.profile.ownedMods or {}
        state.profile.ownedMods[opt.key] = true

        local cur = state.profile.modRanks[opt.key]
        if cur == nil then cur = 1 end
        cur = cur + 1
        local max = opt.def and opt.def.maxLevel
        if max and cur > max then cur = max end
        state.profile.modRanks[opt.key] = cur
        if state.applyPersistentMods then state.applyPersistentMods() end

        logger.upgrade(state, opt, cur)
        if opt.def.onUpgrade then opt.def.onUpgrade() end
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur})
    elseif opt.type == 'augment' then
        state.inventory.augments = state.inventory.augments or {}
        state.inventory.augmentOrder = state.inventory.augmentOrder or {}
        if not state.inventory.augments[opt.key] then
            state.inventory.augments[opt.key] = 0
            table.insert(state.inventory.augmentOrder, opt.key)
        end
        state.inventory.augments[opt.key] = state.inventory.augments[opt.key] + 1
        logger.upgrade(state, opt, state.inventory.augments[opt.key])
        if opt.def.onUpgrade then opt.def.onUpgrade() end
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = state.inventory.augments[opt.key]})
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
                local carryMods = state.inventory and state.inventory.weaponMods and state.inventory.weaponMods[key]
                state.inventory.weapons[key] = nil
                weapons.addWeapon(state, targetKey)
                if carryMods and state.inventory and state.inventory.weaponMods then
                    state.inventory.weaponMods[targetKey] = carryMods
                    state.inventory.weaponMods[key] = nil
                end
                return targetDef.name
            end
        end
    end
    return nil
end

return upgrades
