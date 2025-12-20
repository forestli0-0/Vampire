local pets = require('pets')
local helpers = require('upgrades.options_helpers')

local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

return function(upgrades)
    function upgrades.generateUpgradeOptions(state, request, allowFallback)
        if allowFallback == nil then allowFallback = true end
        local poolExisting = {}
        local poolNew = {}
        local added = {}
        local function addOption(list, opt)
            local key = opt.key .. (opt.evolveFrom or "")
            if not added[key] then
                table.insert(list, opt)
                added[key] = true
            end
        end

        local augmentCap = state.maxAugmentsPerRun or 4

        local allowedTypes, allowPets, typeAllowed = helpers.buildAllowedTypes(request)

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
                    if helpers.countAugments(state) >= augmentCap then
                        goto continue_catalog
                    end
                end
                local currentLevel = 0
                if item.type == 'weapon' and state.inventory.weapons[key] then currentLevel = state.inventory.weapons[key].level end

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
                    if helpers.isOwned(state, item.type, key) then
                        addOption(poolExisting, opt)
                    else
                        addOption(poolNew, opt)
                    end
                end
            end

            ::continue_catalog::
        end

        state.upgradeOptions = {}
        -- 若有进化候选，优先保底塞入 1 个
        local function takeRandom(list)
            return helpers.takeRandom(list)
        end

        -- Class weight system: items with classWeight field are weighted by player's class
        local function takeWeighted(list)
            return helpers.takeWeighted(state, list)
        end

        local function hasType(options, wanted)
            return helpers.hasType(options, wanted)
        end

        local function takeRandomOfType(list, wanted)
            return helpers.takeRandomOfType(list, wanted)
        end

        -- Removed Evolution Pool Logic due to WF system migration

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
        local weaponsOwned = upgrades.countWeapons(state)
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
            if typeAllowed('augment') and helpers.countAugments(state) == 0 and not hasType(state.upgradeOptions, 'augment') then
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
end
