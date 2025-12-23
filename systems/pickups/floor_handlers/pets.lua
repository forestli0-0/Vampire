local upgrades = require('systems.upgrades')
local logger = require('core.logger')
local pets = require('gameplay.pets')

local function handlePetContract(state, p, item)
    local current = pets.getActive(state)
    upgrades.queueLevelUp(state, 'pet_contract', {
        allowedTypes = {pet = true},
        excludePetKey = current and current.key or nil,
        source = 'special_room',
        roomKind = item.roomKind
    })
    logger.pickup(state, 'pet_contract')
    return true
end

local function handlePetModuleChip(state, p, item)
    local pet = pets.getActive(state)
    if not pet then
        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No active pet", color = {1, 0.6, 0.6}, life = 1.0})
        return false
    end

    -- Check if already has an augment mod installed in the run
    local modsModule = require('systems.mods')
    local runSlots = modsModule.getRunSlots(state, 'companion', nil)
    local hasAugment = false
    local catalog = modsModule.companion
    for _, slot in pairs(runSlots or {}) do
        if slot and slot.key then
            local def = catalog[slot.key]
            if def and def.group == 'augment' then
                hasAugment = true
                break
            end
        end
    end

    if hasAugment then
        -- Convert to Gold
        local gain = 250
        if state.gainGold then
            state.gainGold(gain, {source = 'pickup', x = p.x, y = p.y - 20})
        else
            state.runCurrency = (state.runCurrency or 0) + gain
            table.insert(state.texts, {x = p.x, y = p.y - 20, text = "+" .. gain .. " GOLD", color = {0.95, 0.9, 0.45}, life = 0.8})
        end
        table.insert(state.texts, {x = p.x, y = p.y - 45, text = "PET MODULE CONVERTED", color = {1, 0.8, 0.4}, life = 1.2})
        return true
    end

    upgrades.queueLevelUp(state, 'pet_module_chip')
    logger.pickup(state, 'pet_module_chip')
    return true
end

local function handlePetUpgradeChip(state, p, item)
    local pet = pets.getActive(state)
    if not pet then
        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No active pet", color = {1, 0.6, 0.6}, life = 1.0})
        return false
    end
    upgrades.queueLevelUp(state, 'pet_upgrade_chip')
    logger.pickup(state, 'pet_upgrade_chip')
    return true
end

local function handlePetRevive(state, p, item)
    local revived = pets.reviveLost(state)
    if revived then
        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "Pet revived: " .. tostring(revived.name), color = {0.75, 0.95, 1.0}, life = 1.2})
        logger.pickup(state, 'pet_revive')
        return true
    end
    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No pet to revive", color = {1, 0.6, 0.6}, life = 1.0})
    return false
end

return {
    pet_contract = handlePetContract,
    pet_module_chip = handlePetModuleChip,
    pet_upgrade_chip = handlePetUpgradeChip,
    pet_revive = handlePetRevive
}
