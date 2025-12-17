local weapons = require('weapons')
local logger = require('logger')
local pets = require('pets')

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
        if itemType == 'pet' then
            local pet = pets.getActive(state)
            return pet and pet.key == itemKey
        end
        if itemType == 'pet_module' then
            local pet = pets.getActive(state)
            if not pet then return false end
            local def = state.catalog and state.catalog[itemKey]
            local modId = def and def.moduleId
            if not modId then return false end
            return (pet.module or 'default') == modId
        end
        if itemType == 'pet_upgrade' then
            local ps = state and state.pets or nil
            local ups = ps and ps.upgrades or nil
            return ups and (ups[itemKey] or 0) > 0
        end
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
    local allowPets = false
    if type(allowedTypes) == 'table' then
        if allowedTypes.pet then allowPets = true end
        for _, v in ipairs(allowedTypes) do
            if v == 'pet' then allowPets = true break end
        end
    end
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
        if item and item.type == 'pet' and not allowPets then
            goto continue_catalog
        end
        -- Pet modules/upgrades only make sense when you have an active pet.
        if item and (item.type == 'pet_module' or item.type == 'pet_upgrade') then
            local pet = pets.getActive(state)
            if not pet then
                goto continue_catalog
            end
            if item.type == 'pet_module' then
                if item.requiresPetKey and pet.key ~= item.requiresPetKey then
                    goto continue_catalog
                end
                -- non-replaceable: only offer modules when still on default
                if (pet.module or 'default') ~= 'default' then
                    goto continue_catalog
                end
            end
        end
        if item and item.type and not typeAllowed(item.type) then
            goto continue_catalog
        end

        -- Skip hidden/deprecated items (VS-style passives, etc.)
        if item.hidden or item.deprecated then
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
            if item.type == 'pet' then
                local pet = pets.getActive(state)
                if pet and pet.key == key then currentLevel = 1 end
                if request and request.excludePetKey and request.excludePetKey == key then
                    goto continue_catalog
                end
            end
            if item.type == 'pet_module' then
                local pet = pets.getActive(state)
                local modId = item.moduleId
                if pet and modId and (pet.module or 'default') == modId then
                    currentLevel = 1
                else
                    currentLevel = 0
                end
            end
            if item.type == 'pet_upgrade' then
                local ps = state and state.pets or nil
                local ups = ps and ps.upgrades or nil
                currentLevel = ups and (ups[key] or 0) or 0
            end
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
    
    -- Class weight system: items with classWeight field are weighted by player's class
    local function getClassWeight(def)
        if not def or not def.classWeight then return 1.0 end
        local classKey = state.player and state.player.class or 'warrior'
        return def.classWeight[classKey] or 1.0
    end
    
    local function takeWeighted(list)
        if #list == 0 then return nil end
        local total = 0
        for _, opt in ipairs(list) do
            local w = getClassWeight(opt.def)
            total = total + w
        end
        if total <= 0 then return takeRandom(list) end
        local r = math.random() * total
        for i, opt in ipairs(list) do
            local w = getClassWeight(opt.def)
            r = r - w
            if r <= 0 then
                table.remove(list, i)
                return opt
            end
        end
        return table.remove(list, #list)
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
    
    -- Starting guarantee: first 2 upgrades prioritize class-preferred items
    local upgradeCount = state.upgradeCount or 0
    if upgradeCount < 2 then
        local classKey = state.player and state.player.class or 'warrior'
        local classDef = state.classes and state.classes[classKey]
        local preferred = classDef and classDef.preferredUpgrades
        if preferred then
            -- Try to find a preferred item in the pools
            local function takePreferred(list)
                for _, prefKey in ipairs(preferred) do
                    for i, opt in ipairs(list) do
                        if opt.key == prefKey then
                            return table.remove(list, i)
                        end
                    end
                end
                return nil
            end
            -- Add one preferred item if not already in options
            local found = takePreferred(poolNew) or takePreferred(poolExisting)
            if found and #state.upgradeOptions < 3 then
                table.insert(state.upgradeOptions, found)
            end
        end
    end

    local runLevel = 1
    if state and state.runMode == 'rooms' and state.rooms then
        runLevel = tonumber(state.rooms.roomIndex) or 1
    else
        runLevel = (state.player and state.player.level) or 1
    end
    runLevel = math.max(1, math.floor(runLevel))
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
        -- Use weighted selection for class-based preferences
        local preferExisting = (#poolExisting > 0) and (math.random() < preferExistingChance or #poolNew == 0)
        if preferExisting then
            choice = takeWeighted(poolExisting)
        else
            choice = takeWeighted(poolNew)
        end
        if not choice then choice = takeWeighted(poolExisting) end
        if not choice then choice = takeWeighted(poolNew) end
        if not choice then choice = takeRandom(evolvePool) end  -- Evolve pool stays random
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
    -- Track upgrade count for starting guarantee system
    state.upgradeCount = (state.upgradeCount or 0) + 1
    
    if opt.evolveFrom then
        -- 直接进化：移除基础武器，添加目标武器
        local carryMods = state.inventory and state.inventory.weaponMods and state.inventory.weaponMods[opt.evolveFrom]
        local owner = state.inventory and state.inventory.weapons and state.inventory.weapons[opt.evolveFrom] and state.inventory.weapons[opt.evolveFrom].owner
        state.inventory.weapons[opt.evolveFrom] = nil
        weapons.addWeapon(state, opt.key, owner)
        if carryMods and state.inventory and state.inventory.weaponMods then
            state.inventory.weaponMods[opt.key] = carryMods
            state.inventory.weaponMods[opt.evolveFrom] = nil
        end
        logger.upgrade(state, opt, 1)
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
        return
    elseif opt.type == 'weapon' then
        if not state.inventory.weapons[opt.key] then
            weapons.addWeapon(state, opt.key, opt.assignOwner)
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
    elseif opt.type == 'pet_module' then
        local pet = pets.getActive(state)
        local def = opt.def or (state.catalog and state.catalog[opt.key]) or nil
        local modId = def and def.moduleId
        if pet and modId and (pet.module or 'default') == 'default' then
            pet.module = modId
            logger.upgrade(state, opt, 1)
            if state.texts then
                table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = "PET MODULE: " .. tostring(def.name or opt.key), color = {0.85, 0.95, 1.0}, life = 1.3})
            end
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
        end
    elseif opt.type == 'pet_upgrade' then
        state.pets = state.pets or {}
        state.pets.upgrades = state.pets.upgrades or {}
        local cur = state.pets.upgrades[opt.key] or 0
        cur = cur + 1
        local max = opt.def and opt.def.maxLevel
        if max and cur > max then cur = max end
        state.pets.upgrades[opt.key] = cur
        logger.upgrade(state, opt, cur)
        if pets and pets.recompute then pets.recompute(state) end
        dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur})
    elseif opt.type == 'pet' then
        local pet = pets.setActive(state, opt.key, {swap = true})
        if pet then
            logger.upgrade(state, opt, 1)
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
        end
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
                local owner = w and w.owner
                state.inventory.weapons[key] = nil
                weapons.addWeapon(state, targetKey, owner)
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
