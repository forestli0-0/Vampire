local helpers = require('systems.upgrades.options_helpers')

local function applyStartingGuarantee(state, pools)
    if pools and pools.mode == 'mod' then return end
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
            local found = takePreferred(pools.poolNew) or takePreferred(pools.poolExisting)
            if found and #state.upgradeOptions < 3 then
                table.insert(state.upgradeOptions, found)
            end
        end
    end
end

local function computeRunState(state, upgrades)
    local runLevel = 1
    if state and state.runMode == 'rooms' and state.rooms then
        runLevel = tonumber(state.rooms.roomIndex) or 1
    else
        runLevel = (state.player and state.player.level)
        if runLevel == nil then runLevel = 1 end
    end
    runLevel = math.max(0, math.floor(runLevel))
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

    return runLevel, preferExistingChance, maxWeapons, weaponsOwned
end

local function applyEarlyRoute(state, pools, runLevel, maxWeapons, weaponsOwned)
    if pools and pools.mode == 'mod' then return end
    -- Early feel: ensure at least one "new route" option (weapon/augment) when possible.
    if #state.upgradeOptions < 3 then
        if pools.typeAllowed('weapon') and weaponsOwned < math.min(2, math.max(1, maxWeapons)) and not helpers.hasType(state.upgradeOptions, 'weapon') then
            local forcedWeapon = helpers.takeRandomOfType(pools.poolNew, 'weapon')
            if forcedWeapon then
                table.insert(state.upgradeOptions, forcedWeapon)
            end
        end
    end
    if #state.upgradeOptions < 3 and runLevel <= 6 then
        if pools.typeAllowed('augment') and helpers.countAugments(state) == 0 and not helpers.hasType(state.upgradeOptions, 'augment') then
            local forcedAug = helpers.takeRandomOfType(pools.poolNew, 'augment')
            if forcedAug then
                table.insert(state.upgradeOptions, forcedAug)
            end
        end
    end
end

local function applyLowLevelForce(state, pools, runLevel)
    if pools and pools.mode == 'mod' then return end
    if runLevel <= 6
        and (pools.typeAllowed('weapon') or pools.typeAllowed('augment'))
        and not (helpers.hasType(state.upgradeOptions, 'weapon') or helpers.hasType(state.upgradeOptions, 'augment')) then
        local forced = helpers.takeRandomOfType(pools.poolNew, 'weapon') or helpers.takeRandomOfType(pools.poolNew, 'augment')
        if forced then
            state.upgradeOptions[#state.upgradeOptions] = forced
        end
    end
end

return {
    applyStartingGuarantee = applyStartingGuarantee,
    computeRunState = computeRunState,
    applyEarlyRoute = applyEarlyRoute,
    applyLowLevelForce = applyLowLevelForce
}
