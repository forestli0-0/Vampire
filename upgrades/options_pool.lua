local pets = require('pets')
local helpers = require('upgrades.options_helpers')
local mods = require('mods')
local rewardDefs = require('data.defs.mod_rewards')

local function weightsSignature(weights)
    if type(weights) ~= 'table' then return '' end
    local keys = {}
    for k, _ in pairs(weights) do
        table.insert(keys, k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, k .. ":" .. tostring(weights[k]))
    end
    return table.concat(parts, "|")
end

local function cloneList(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    return out
end

local function getModRewardPool(state)
    local sig = weightsSignature(rewardDefs.weights)
    local cache = state and state.modRewardPoolCache
    if cache and cache.sig == sig and cache.poolNew then
        return cache.poolNew
    end

    local poolNew = {}
    local added = {}
    local pools = mods.buildRewardPools()
    local weights = rewardDefs.weights or {}

    for group, entries in pairs(pools or {}) do
        local groupWeight = weights[group] or 0
        for _, entry in ipairs(entries or {}) do
            local key = entry.key
            if key and not added[key] then
                local weight = (entry.weight or 1) * groupWeight
                if weight > 0 then
                    local def = entry.def or {}
                    table.insert(poolNew, {
                        key = key,
                        type = 'mod',
                        name = def.name or key,
                        desc = def.desc or '',
                        def = def,
                        category = entry.category,
                        rarity = entry.rarity,
                        group = group,
                        weight = weight
                    })
                    added[key] = true
                end
            end
        end
    end

    if state then
        state.modRewardPoolCache = {sig = sig, poolNew = poolNew}
    end

    return poolNew
end

local function hasAllowedType(allowed, want)
    if type(allowed) ~= 'table' then return false end
    if allowed[want] then return true end
    for _, v in ipairs(allowed) do
        if v == want then return true end
    end
    return false
end

local function isModReward(request)
    if not request then return false end
    if request.mode == 'mod' then return true end
    if request.reason == 'mod_drop' then return true end
    return hasAllowedType(request.allowedTypes, 'mod') or hasAllowedType(request.allowedTypes, 'augment')
end

local function buildPools(state, request)
    if isModReward(request) then
        local basePool = getModRewardPool(state)
        local poolNew = cloneList(basePool)

        return {
            mode = 'mod',
            poolExisting = {},
            poolNew = poolNew,
            allowedTypes = request and request.allowedTypes or {},
            typeAllowed = function() return false end
        }
    end

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

    return {
        poolExisting = poolExisting,
        poolNew = poolNew,
        allowedTypes = allowedTypes,
        typeAllowed = typeAllowed
    }
end

return {
    buildPools = buildPools
}
