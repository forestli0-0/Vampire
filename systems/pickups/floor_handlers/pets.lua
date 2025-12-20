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
    elseif (pet.module or 'default') ~= 'default' then
        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "Pet module already installed", color = {1, 0.75, 0.55}, life = 1.0})
        return false
    end
    upgrades.queueLevelUp(state, 'pet_module_chip', {allowedTypes = {pet_module = true}, source = 'pet_chip'})
    logger.pickup(state, 'pet_module_chip')
    return true
end

local function handlePetUpgradeChip(state, p, item)
    local pet = pets.getActive(state)
    if not pet then
        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No active pet", color = {1, 0.6, 0.6}, life = 1.0})
        return false
    end
    upgrades.queueLevelUp(state, 'pet_upgrade_chip', {allowedTypes = {pet_upgrade = true}, source = 'pet_chip'})
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
