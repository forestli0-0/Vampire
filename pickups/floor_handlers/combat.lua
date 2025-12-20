local upgrades = require('upgrades')
local logger = require('logger')

local function handleAmmo(state, p, item)
    -- Ammo pickup: refill reserve ammo for all weapons
    local fullRefill = item.fullRefill or false
    local amount = item.amount or 20
    local refilled = false
    local totalGained = 0
    for weaponKey, w in pairs(state.inventory and state.inventory.weapons or {}) do
        if w.reserve ~= nil then
            local def = state.catalog and state.catalog[weaponKey]
            local maxRes = (def and def.base and def.base.maxReserve) or 120
            if w.reserve < maxRes then
                local before = w.reserve
                if fullRefill then
                    w.reserve = maxRes
                else
                    w.reserve = math.min(maxRes, w.reserve + amount)
                end
                totalGained = totalGained + (w.reserve - before)
                refilled = true
            end
        end
    end
    if refilled then
        local msg = fullRefill and "AMMO FULL!" or ("+" .. totalGained .. " AMMO")
        table.insert(state.texts, {x=p.x, y=p.y-30, text=msg, color={0.8, 0.9, 1}, life=1})
        if state.playSfx then state.playSfx('gem') end
        logger.pickup(state, 'ammo')
        return true
    end
    -- All weapons full, don't consume
    return false
end

local function handleEnergy(state, p, item)
    -- Energy pickup for abilities
    local amount = item.amount or 25
    local maxEnergy = p.maxEnergy or 100
    local current = p.energy or 0
    if current < maxEnergy then
        p.energy = math.min(maxEnergy, current + amount)
        local gained = p.energy - current
        table.insert(state.texts, {x=p.x, y=p.y-30, text="+"..math.floor(gained).." ENERGY", color={0.4, 0.7, 1}, life=1})
        if state.playSfx then state.playSfx('gem') end
        logger.pickup(state, 'energy')
        return true
    end
    return false
end

local function handleHealthOrb(state, p, item)
    -- WF-style health orb
    local amt = item.amount or 15
    local ctx = {kind = 'health_orb', amount = amt, player = p, item = item}
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onPickup', ctx)
    end
    if ctx.cancel then
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'pickupCancelled', ctx)
        end
        return false
    end

    amt = ctx.amount or amt
    if p.hp < p.maxHp then
        p.hp = math.min(p.maxHp, p.hp + amt)
        table.insert(state.texts, {x=p.x, y=p.y-30, text="+" .. math.floor(amt) .. " HP", color={0.4, 1, 0.4}, life=1})
        if state.playSfx then state.playSfx('gem') end
        logger.pickup(state, 'health_orb')
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'postPickup', ctx)
        end
        return true
    end
    -- Already at full HP
    return false
end

local function handleEnergyOrb(state, p, item)
    -- WF-style energy orb (restores ability energy)
    local amt = item.amount or 25
    local maxEnergy = p.maxEnergy or 100
    local current = p.energy or 0
    if current < maxEnergy then
        p.energy = math.min(maxEnergy, current + amt)
        local gained = p.energy - current
        table.insert(state.texts, {x=p.x, y=p.y-30, text="+" .. math.floor(gained) .. " ENERGY", color={0.4, 0.6, 1}, life=1})
        if state.playSfx then state.playSfx('gem') end
        logger.pickup(state, 'energy_orb')
        return true
    end
    -- Already at full energy
    return false
end

local function handleModCard(state, p, item)
    -- WF-style MOD card drop - triggers mod selection
    local ctx = {kind = 'mod_card', amount = 1, player = p, item = item}
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onPickup', ctx)
    end
    if ctx.cancel then
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'pickupCancelled', ctx)
        end
        return false
    end
    -- Queue a MOD selection upgrade
    upgrades.queueLevelUp(state, 'mod_drop', {
        allowedTypes = {mod = true, augment = true},
        source = 'enemy_drop'
    })
    table.insert(state.texts, {x=p.x, y=p.y-30, text="MOD ACQUIRED!", color={0.9, 0.8, 0.2}, life=1.2})
    if state.playSfx then state.playSfx('gem') end
    logger.pickup(state, 'mod_card')
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'postPickup', ctx)
    end
    return true
end

return {
    ammo = handleAmmo,
    energy = handleEnergy,
    health_orb = handleHealthOrb,
    energy_orb = handleEnergyOrb,
    mod_card = handleModCard
}
