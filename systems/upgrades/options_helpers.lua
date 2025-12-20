local pets = require('gameplay.pets')

local function isOwned(state, itemType, itemKey)
    if itemType == 'weapon' then return state.inventory.weapons[itemKey] ~= nil end

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

local function countAugments(state)
    local n = 0
    for _, lvl in pairs(state.inventory.augments or {}) do
        if (lvl or 0) > 0 then n = n + 1 end
    end
    return n
end

local function buildAllowedTypes(request)
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

    return allowedTypes, allowPets, typeAllowed
end

local function getClassWeight(state, def)
    if not def or not def.classWeight then return 1.0 end
    local classKey = state.player and state.player.class or 'volt'
    return def.classWeight[classKey] or 1.0
end

local function takeRandom(list)
    if #list == 0 then return nil end
    local idx = math.random(#list)
    local opt = list[idx]
    table.remove(list, idx)
    return opt
end

local function takeWeighted(state, list)
    if #list == 0 then return nil end
    local total = 0
    for _, opt in ipairs(list) do
        local w = opt.weight or getClassWeight(state, opt.def)
        total = total + w
    end
    if total <= 0 then return takeRandom(list) end
    local r = math.random() * total
    for i, opt in ipairs(list) do
        local w = opt.weight or getClassWeight(state, opt.def)
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

return {
    isOwned = isOwned,
    countAugments = countAugments,
    buildAllowedTypes = buildAllowedTypes,
    takeRandom = takeRandom,
    takeWeighted = takeWeighted,
    hasType = hasType,
    takeRandomOfType = takeRandomOfType
}
