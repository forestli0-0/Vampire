-- mods.lua
-- Unified Warframe-style MOD System
-- Supports: Warframe (character), Weapon, Companion (pet)

local mods = {}

-- =============================================================================
-- MOD CATALOG
-- =============================================================================

local defs = require('data.defs.mods')
mods.warframe = defs.warframe
mods.weapon = defs.weapon
mods.companion = defs.companion


-- =============================================================================
-- SLOT SYSTEM
-- =============================================================================

local MAX_SLOTS = 8
local DEFAULT_CAPACITY = 30

local function getRunBaseCapacity(state)
    local cap = state and state.progression and state.progression.modCapacity
    if cap ~= nil then return cap end
    return DEFAULT_CAPACITY
end

local function getWeaponClass(state, weaponKey)
    local def = state and state.catalog and state.catalog[weaponKey]
    if not def then return nil end
    if def.slotType == 'melee' or def.slot == 'melee' then return 'melee' end
    if def.tags then
        for _, tag in ipairs(def.tags) do
            if tag == 'melee' then return 'melee' end
        end
    end
    return 'ranged'
end

local function isWeaponModCompatible(state, weaponKey, modKey, catalog)
    local def = catalog and catalog[modKey]
    if not def or not def.weaponType then return true end
    local weaponClass = getWeaponClass(state, weaponKey)
    if not weaponClass then return false end
    return def.weaponType == weaponClass
end

-- Initialize mod slots for an entity
function mods.initSlots(state, category, key)
    state.modSlots = state.modSlots or {}
    
    if category == 'weapons' then
        state.modSlots.weapons = state.modSlots.weapons or {}
        if not state.modSlots.weapons[key] then
            state.modSlots.weapons[key] = {
                slots = {}, capacity = DEFAULT_CAPACITY, level = 1
            }
        end
        return state.modSlots.weapons[key]
    else
        -- warframe or companion
        if not state.modSlots[category] or not state.modSlots[category].slots then
            state.modSlots[category] = {
                slots = {}, capacity = DEFAULT_CAPACITY, level = 1
            }
        end
        return state.modSlots[category]
    end
end

-- Get catalog for category
function mods.getCatalog(category)
    if category == 'warframe' then return mods.warframe
    elseif category == 'weapons' then return mods.weapon
    elseif category == 'companion' then return mods.companion
    end
    return {}
end

-- Calculate total cost of equipped mods
function mods.getTotalCost(slots, catalog)
    local total = 0
    for _, mod in pairs(slots or {}) do
        if mod and mod.key then
            local def = catalog[mod.key]
            if def and def.cost then
                local rank = math.max(0, math.min(5, mod.rank or 0))
                total = total + (def.cost[rank + 1] or 0)
            end
        end
    end
    return total
end

-- Check if can equip
function mods.canEquip(slotData, modKey, modRank, catalog)
    local currentCost = mods.getTotalCost(slotData.slots, catalog)
    local def = catalog[modKey]
    if not def then return false end
    
    local rank = math.max(0, math.min(5, modRank or 0))
    local newCost = def.cost[rank + 1] or 0
    local capacity = slotData.capacity or DEFAULT_CAPACITY
    
    return (currentCost + newCost) <= capacity
end

-- Equip a mod
function mods.equip(state, category, key, slotIndex, modKey, modRank)
    local slotData
    if category == 'weapons' then
        slotData = mods.initSlots(state, 'weapons', key)
    else
        slotData = mods.initSlots(state, category, nil)
    end
    
    if slotIndex < 1 or slotIndex > MAX_SLOTS then return false end
    
    local catalog = mods.getCatalog(category)
    if category == 'weapons' and not isWeaponModCompatible(state, key, modKey, catalog) then
        return false
    end
    local oldMod = slotData.slots[slotIndex]
    slotData.slots[slotIndex] = nil
    
    if not mods.canEquip(slotData, modKey, modRank, catalog) then
        slotData.slots[slotIndex] = oldMod
        return false
    end
    
    slotData.slots[slotIndex] = {key = modKey, rank = modRank or 0}
    return true
end

-- Unequip
function mods.unequip(state, category, key, slotIndex)
    local slotData
    if category == 'weapons' then
        if state.modSlots and state.modSlots.weapons then
            slotData = state.modSlots.weapons[key]
        end
    else
        slotData = state.modSlots and state.modSlots[category]
    end
    if slotData and slotIndex >= 1 and slotIndex <= MAX_SLOTS then
        slotData.slots[slotIndex] = nil
        return true
    end
    return false
end

-- Get slots
function mods.getSlots(state, category, key)
    if not state.modSlots then return {} end
    if category == 'weapons' then
        return state.modSlots.weapons and state.modSlots.weapons[key] and state.modSlots.weapons[key].slots or {}
    else
        return state.modSlots[category] and state.modSlots[category].slots or {}
    end
end

-- =============================================================================
-- APPLY BONUSES
-- =============================================================================

-- Apply mods to stats
function mods.applyToStats(baseStats, slots, catalog)
    local stats = {}
    for k, v in pairs(baseStats or {}) do
        stats[k] = v
    end
    
    local multBonuses = {}
    local addBonuses = {}
    
    for _, mod in pairs(slots or {}) do
        if mod and mod.key then
            local def = catalog[mod.key]
            if def and def.value then
                local rank = math.max(0, math.min(5, mod.rank or 0))
                local bonus = def.value[rank + 1] or 0
                local stat = def.stat
                
                if def.type == 'mult' then
                    multBonuses[stat] = (multBonuses[stat] or 0) + bonus
                else
                    addBonuses[stat] = (addBonuses[stat] or 0) + bonus
                end
            end
        end
    end
    
    -- Apply multiplicative
    for stat, bonus in pairs(multBonuses) do
        if stats[stat] ~= nil then
            stats[stat] = stats[stat] * (1 + bonus)
        else
            stats[stat] = (stats[stat] or 0) + bonus
        end
    end
    
    -- Apply additive
    for stat, bonus in pairs(addBonuses) do
        stats[stat] = (stats[stat] or 0) + bonus
    end
    
    return stats
end

-- Convenience: Apply weapon mods with attribute name mapping
function mods.applyWeaponMods(state, weaponKey, baseStats)
    local slots = mods.getSlots(state, 'weapons', weaponKey)
    local stats = mods.applyToStats(baseStats, slots, mods.weapon)
    
    -- Attribute name mapping: MOD stat names -> weapon stat names
    -- fireRate (mult) affects cd inversely: higher fireRate = lower cd
    if stats.fireRate and stats.fireRate > 0 then
        local cdBonus = stats.fireRate  -- e.g., 0.6 means 60% faster
        stats.cd = (stats.cd or 1) / (1 + cdBonus)
        -- stats.fireRate = nil  -- Keep for UI
    end
    
    -- multishot (add) maps to amount
    if stats.multishot then
        stats.amount = (stats.amount or 0) + stats.multishot
        -- stats.multishot = nil -- Keep for UI
    end
    
    -- critMult (add) maps to critMultiplier
    if stats.critMult then
        stats.critMultiplier = (stats.critMultiplier or 1.5) + stats.critMult
        -- stats.critMult = nil -- Keep for UI
    end
    
    -- magSize (mult) maps to magazine/maxMagazine
    if stats.magSize and stats.magSize > 0 then
        local bonus = 1 + stats.magSize
        if stats.magazine then
            stats.magazine = math.floor(stats.magazine * bonus)
        end
        if stats.maxMagazine then
            stats.maxMagazine = math.floor(stats.maxMagazine * bonus)
        end
        -- stats.magSize = nil -- Keep for UI
    end
    
    -- reloadSpeed (mult) affects reloadTime inversely
    if stats.reloadSpeed and stats.reloadSpeed > 0 then
        local bonus = stats.reloadSpeed
        stats.reloadTime = (stats.reloadTime or 1.5) / (1 + bonus)
        -- stats.reloadSpeed = nil -- Keep for UI
    end
    
    -- meleeDamage (mult) maps to damage
    if stats.meleeDamage then
        stats.damage = (stats.damage or 0) * (1 + stats.meleeDamage)
        -- stats.meleeDamage = nil -- Keep for UI
    end
    
    return stats
end

-- Convenience: Apply warframe mods to player
function mods.applyWarframeMods(state, playerStats)
    local slots = mods.getSlots(state, 'warframe', nil)
    return mods.applyToStats(playerStats, slots, mods.warframe)
end

-- Convenience: Apply companion mods
function mods.applyCompanionMods(state, petStats)
    local slots = mods.getSlots(state, 'companion', nil)
    return mods.applyToStats(petStats, slots, mods.companion)
end

-- =============================================================================
-- DEBUG/TEST
-- =============================================================================

function mods.equipTestMods(state, category, key)
    local slotData
    if category == 'weapons' then
        slotData = mods.initSlots(state, 'weapons', key)
    else
        slotData = mods.initSlots(state, category, nil)
    end
    slotData.capacity = 300  -- High capacity for testing
    
    if category == 'warframe' then
        mods.equip(state, 'warframe', nil, 1, 'vitality', 3)
        mods.equip(state, 'warframe', nil, 2, 'steel_fiber', 2)
        mods.equip(state, 'warframe', nil, 3, 'flow', 2)
        mods.equip(state, 'warframe', nil, 4, 'rush', 3)
    elseif category == 'weapons' then
        mods.equip(state, 'weapons', key, 1, 'serration', 3)
        mods.equip(state, 'weapons', key, 2, 'split_chamber', 2)
        mods.equip(state, 'weapons', key, 3, 'point_strike', 3)
        mods.equip(state, 'weapons', key, 4, 'vital_sense', 2)
    elseif category == 'companion' then
        mods.equip(state, 'companion', nil, 1, 'link_health', 3)
        mods.equip(state, 'companion', nil, 2, 'maul', 2)
        mods.equip(state, 'companion', nil, 3, 'bite', 2)
    end
    
    print(string.format("[MODS] Test mods equipped: %s %s", category, key or ""))
end

-- =============================================================================
-- IN-RUN MOD SYSTEM (Roguelike Integration)
-- =============================================================================

-- Rarity definitions
mods.RARITY = {
    COMMON = { name = "Common", color = {0.7, 0.7, 0.7}, weight = 70 },
    UNCOMMON = { name = "Uncommon", color = {0.3, 0.8, 0.3}, weight = 20 },
    RARE = { name = "Rare", color = {0.3, 0.5, 1.0}, weight = 8 },
    LEGENDARY = { name = "Legendary", color = {1.0, 0.8, 0.2}, weight = 2 }
}

-- Assign rarity to mods (can be overridden per-mod)
local function getModRarity(modKey)
    -- Default rarities based on mod power
    local rarities = {
        -- Warframe - Common
        vitality = 'COMMON', steel_fiber = 'COMMON', redirection = 'COMMON', rush = 'COMMON',
        -- Warframe - Uncommon
        flow = 'UNCOMMON', streamline = 'UNCOMMON', continuity = 'UNCOMMON', stretch = 'UNCOMMON',
        -- Warframe - Rare
        intensify = 'RARE', quick_thinking = 'RARE',
        -- Weapon - Common
        serration = 'COMMON', point_strike = 'COMMON', speed_trigger = 'COMMON', fast_hands = 'COMMON',
        -- Weapon - Uncommon
        split_chamber = 'UNCOMMON', vital_sense = 'UNCOMMON', magazine_warp = 'UNCOMMON', status_matrix = 'UNCOMMON',
        -- Weapon - Rare
        heavy_caliber = 'RARE', pressure_point = 'RARE',
        -- Companion - Common
        link_health = 'COMMON', link_armor = 'COMMON',
        -- Companion - Uncommon
        maul = 'UNCOMMON', bite = 'UNCOMMON',
        -- Companion - Rare
        pack_leader = 'RARE'
    }
    return rarities[modKey] or 'COMMON'
end

mods.REWARD_GROUP = {
    vitality = 'base',
    steel_fiber = 'base',
    redirection = 'base',
    flow = 'base',
    intensify = 'base',
    serration = 'base',
    heavy_caliber = 'base',
    pressure_point = 'base',
    maul = 'base',
    point_strike = 'base',
    vital_sense = 'base',
    link_health = 'base',
    link_armor = 'base',
    bite = 'base',

    rush = 'utility',
    streamline = 'utility',
    continuity = 'utility',
    stretch = 'utility',
    speed_trigger = 'utility',
    magazine_warp = 'utility',
    fast_hands = 'utility',
    status_matrix = 'utility',
    stabilizer = 'utility',

    quick_thinking = 'augment',
    split_chamber = 'augment',
    metal_auger = 'augment',
    guided_ordnance = 'augment',
    pack_leader = 'augment'
}

function mods.getRewardGroup(modKey, def)
    return mods.REWARD_GROUP[modKey] or 'utility'
end

function mods.buildRewardPools()
    local pools = {base = {}, utility = {}, augment = {}}
    local categories = {'warframe', 'weapons', 'companion'}
    for _, category in ipairs(categories) do
        local pool = mods.buildDropPool(category)
        for _, entry in ipairs(pool or {}) do
            entry.category = category
            entry.group = mods.getRewardGroup(entry.key, entry.def)
            if pools[entry.group] then
                table.insert(pools[entry.group], entry)
            end
        end
    end
    return pools
end

-- Build drop pool for a category
function mods.buildDropPool(category)
    local catalog = mods.getCatalog(category)
    if not catalog then return {} end
    
    local pool = {}
    for key, def in pairs(catalog) do
        local rarity = getModRarity(key)
        local rarityDef = mods.RARITY[rarity] or mods.RARITY.COMMON
        table.insert(pool, {
            key = key,
            category = category,
            rarity = rarity,
            weight = rarityDef.weight,
            def = def
        })
    end
    return pool
end

-- Roll a random mod from pool
function mods.rollMod(pool, bonusRareChance)
    if not pool or #pool == 0 then return nil end
    
    bonusRareChance = bonusRareChance or 0
    
    -- Calculate total weight
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        local w = entry.weight or 1
        -- Bonus rare chance boosts RARE and LEGENDARY
        if bonusRareChance > 0 and (entry.rarity == 'RARE' or entry.rarity == 'LEGENDARY') then
            w = w * (1 + bonusRareChance)
        end
        totalWeight = totalWeight + w
    end
    
    if totalWeight <= 0 then return pool[1] end
    
    -- Roll
    local roll = math.random() * totalWeight
    for _, entry in ipairs(pool) do
        local w = entry.weight or 1
        if bonusRareChance > 0 and (entry.rarity == 'RARE' or entry.rarity == 'LEGENDARY') then
            w = w * (1 + bonusRareChance)
        end
        roll = roll - w
        if roll <= 0 then
            return entry
        end
    end
    
    return pool[#pool]
end

-- Initialize run mods state (call at run start)
function mods.initRunMods(state)
    local baseCap = getRunBaseCapacity(state)
    state.runMods = {
        -- Inventory of collected mods: { {key, category, rank, rarity}, ... }
        inventory = {},
        
        -- Equipped slots per category
        warframe = { slots = {}, capacity = baseCap },
        weapons = {},  -- weapons[weaponKey] = { slots = {}, capacity = baseCap }
        companion = { slots = {}, capacity = baseCap },
        
        -- Stats
        totalCollected = 0,
        totalEquipped = 0
    }

    -- Dev convenience: prefill run inventory with all mods by category.
    if state and state.prefillRunMods then
        local categories = {'warframe', 'weapons', 'companion'}
        for _, category in ipairs(categories) do
            local catalog = mods.getCatalog(category)
            for key, _ in pairs(catalog or {}) do
                mods.addToRunInventory(state, key, category, 0, nil)
            end
        end
    end
end

-- Get run mod slots for category
function mods.getRunSlots(state, category, key)
    if not state.runMods then return {} end
    local baseCap = getRunBaseCapacity(state)
    
    if category == 'weapons' then
        if not state.runMods.weapons[key] then
            state.runMods.weapons[key] = { slots = {}, capacity = baseCap }
        end
        return state.runMods.weapons[key].slots
    else
        if not state.runMods[category] then
            state.runMods[category] = { slots = {}, capacity = baseCap }
        end
        return state.runMods[category].slots
    end
end

-- Get run mod slot data for capacity
function mods.getRunSlotData(state, category, key)
    if not state.runMods then return nil end
    local baseCap = getRunBaseCapacity(state)
    
    if category == 'weapons' then
        if not state.runMods.weapons[key] then
            state.runMods.weapons[key] = { slots = {}, capacity = baseCap }
        end
        return state.runMods.weapons[key]
    else
        if not state.runMods[category] then
            state.runMods[category] = { slots = {}, capacity = baseCap }
        end
        return state.runMods[category]
    end
end

-- Add mod to run inventory
function mods.addToRunInventory(state, modKey, category, rank, rarity)
    if not state.runMods then mods.initRunMods(state) end
    
    rank = rank or 0
    rarity = rarity or getModRarity(modKey)
    
    table.insert(state.runMods.inventory, {
        key = modKey,
        category = category,
        rank = rank,
        rarity = rarity
    })
    
    state.runMods.totalCollected = (state.runMods.totalCollected or 0) + 1
    return true
end

-- Check if mod can be equipped to run slots
function mods.canEquipToRun(state, category, key, modKey, modRank)
    local slotData = mods.getRunSlotData(state, category, key)
    if not slotData then return false end
    
    local catalog = mods.getCatalog(category)
    if not catalog then return false end
    
    local def = catalog[modKey]
    if not def then return false end
    if category == 'weapons' and not isWeaponModCompatible(state, key, modKey, catalog) then
        return false
    end
    
    -- Check slot count
    local usedSlots = 0
    for _, slot in pairs(slotData.slots or {}) do
        if slot then usedSlots = usedSlots + 1 end
    end
    if usedSlots >= MAX_SLOTS then return false end
    
    -- Check capacity
    local currentCost = mods.getTotalCost(slotData.slots, catalog)
    local rank = math.max(0, math.min(5, modRank or 0))
    local newCost = def.cost and def.cost[rank + 1] or 4
    
    return (currentCost + newCost) <= (slotData.capacity or DEFAULT_CAPACITY)
end

-- Equip mod from run inventory to slot
function mods.equipToRunSlot(state, category, key, slotIndex, modKey, modRank)
    if not state.runMods then return false end
    
    local slotData = mods.getRunSlotData(state, category, key)
    if not slotData then return false end
    
    if slotIndex < 1 or slotIndex > MAX_SLOTS then return false end
    
    local catalog = mods.getCatalog(category)
    if not catalog or not catalog[modKey] then return false end
    
    -- Check capacity
    local oldMod = slotData.slots[slotIndex]
    slotData.slots[slotIndex] = nil
    
    if not mods.canEquipToRun(state, category, key, modKey, modRank) then
        slotData.slots[slotIndex] = oldMod
        return false
    end
    
    slotData.slots[slotIndex] = { key = modKey, rank = modRank or 0 }
    state.runMods.totalEquipped = (state.runMods.totalEquipped or 0) + 1
    return true
end

-- Unequip mod from run slot
function mods.unequipFromRunSlot(state, category, key, slotIndex)
    local slotData = mods.getRunSlotData(state, category, key)
    if not slotData then return false end
    
    if slotIndex >= 1 and slotIndex <= MAX_SLOTS then
        local old = slotData.slots[slotIndex]
        slotData.slots[slotIndex] = nil
        if old then
            state.runMods.totalEquipped = math.max(0, (state.runMods.totalEquipped or 0) - 1)
        end
        return old ~= nil
    end
    return false
end

-- Apply run mods to weapon stats (call from weapons.lua)
function mods.applyRunWeaponMods(state, weaponKey, baseStats)
    if not state.runMods then return baseStats end
    
    local slots = mods.getRunSlots(state, 'weapons', weaponKey)
    local stats = mods.applyToStats(baseStats, slots, mods.weapon)
    
    -- Same attribute mapping as applyWeaponMods
    if stats.fireRate and stats.fireRate > 0 then
        local cdBonus = stats.fireRate
        stats.cd = (stats.cd or 1) / (1 + cdBonus)
        -- stats.fireRate = nil
    end
    
    if stats.multishot then
        stats.amount = (stats.amount or 0) + stats.multishot
        -- stats.multishot = nil
    end
    
    if stats.critMult then
        stats.critMultiplier = (stats.critMultiplier or 1.5) + stats.critMult
        -- stats.critMult = nil
    end
    
    if stats.magSize and stats.magSize > 0 then
        local bonus = 1 + stats.magSize
        if stats.magazine then stats.magazine = math.floor(stats.magazine * bonus) end
        if stats.maxMagazine then stats.maxMagazine = math.floor(stats.maxMagazine * bonus) end
        -- stats.magSize = nil
    end
    
    if stats.reloadSpeed and stats.reloadSpeed > 0 then
        local bonus = stats.reloadSpeed
        stats.reloadTime = (stats.reloadTime or 1.5) / (1 + bonus)
        -- stats.reloadSpeed = nil
    end
    
    -- meleeDamage (mult) maps to damage
    if stats.meleeDamage then
        stats.damage = (stats.damage or 0) * (1 + stats.meleeDamage)
        -- stats.meleeDamage = nil
    end
    
    return stats
end

-- Apply run mods to player stats (call from player.lua)
function mods.applyRunWarframeMods(state, playerStats)
    if not state.runMods then return playerStats end
    
    local slots = mods.getRunSlots(state, 'warframe', nil)
    return mods.applyToStats(playerStats, slots, mods.warframe)
end

-- Apply run mods to companion stats
function mods.applyRunCompanionMods(state, petStats)
    if not state.runMods then return petStats end
    
    local slots = mods.getRunSlots(state, 'companion', nil)
    return mods.applyToStats(petStats, slots, mods.companion)
end

-- Count mods in inventory by category
function mods.countRunInventory(state, category)
    if not state.runMods or not state.runMods.inventory then return 0 end
    
    if not category then return #state.runMods.inventory end
    
    local count = 0
    for _, mod in ipairs(state.runMods.inventory) do
        if mod.category == category then count = count + 1 end
    end
    return count
end

-- Get inventory mods filtered by category
function mods.getRunInventoryByCategory(state, category)
    if not state.runMods or not state.runMods.inventory then return {} end
    
    local result = {}
    for _, mod in ipairs(state.runMods.inventory) do
        if mod.category == category then
            table.insert(result, mod)
        end
    end
    return result
end

-- =============================================================================
-- REFRESH ACTIVE STATS
-- =============================================================================

function mods.refreshActiveStats(state)
    local p = state.player
    if not p then return end
    
    -- 1. Determine base stats from class
    local classKey = p.class or 'warrior'
    local classDef = state.classes and state.classes[classKey]
    local baseStats = {}
    
    if classDef and classDef.baseStats then
        for k, v in pairs(classDef.baseStats) do
            baseStats[k] = v
        end
    end
    
    -- Fill in missing defaults if needed (ensure no nils)
    baseStats.maxHp = baseStats.maxHp or 100
    baseStats.maxShield = baseStats.maxShield or 100
    baseStats.maxEnergy = baseStats.maxEnergy or 100
    baseStats.moveSpeed = baseStats.moveSpeed or 110
    baseStats.armor = baseStats.armor or 0
    baseStats.energyRegen = baseStats.energyRegen or 2.0
    baseStats.abilityStrength = baseStats.abilityStrength or 1.0
    baseStats.abilityEfficiency = baseStats.abilityEfficiency or 1.0
    baseStats.abilityDuration = baseStats.abilityDuration or 1.0
    baseStats.abilityRange = baseStats.abilityRange or 1.0
    baseStats.dashCharges = baseStats.dashCharges or (p.stats and p.stats.dashCharges) or 1
    baseStats.dashCooldown = baseStats.dashCooldown or (p.stats and p.stats.dashCooldown) or 3
    baseStats.dashDuration = baseStats.dashDuration or (p.stats and p.stats.dashDuration) or 0.14
    baseStats.dashDistance = baseStats.dashDistance or (p.stats and p.stats.dashDistance) or 56
    baseStats.dashInvincible = baseStats.dashInvincible or (p.stats and p.stats.dashInvincible) or 0.14

    local bonuses = state.progression and state.progression.rankBonuses or {}
    baseStats.maxHp = (baseStats.maxHp or 0) + (bonuses.maxHp or 0)
    baseStats.maxShield = (baseStats.maxShield or 0) + (bonuses.maxShield or 0)
    baseStats.maxEnergy = (baseStats.maxEnergy or 0) + (bonuses.maxEnergy or 0)
    
    -- 2. Apply persistent mods (Warframe category)
    -- [Implementation note: arsenal-persistent mods for character are handled here if implemented]
    
    -- 3. Apply run mods
    local activeStats = mods.applyRunWarframeMods(state, baseStats)
    
    -- 4. Update player object
    p.stats = activeStats
    
    -- Sync physical fields for HUD and physics
    p.maxHp = activeStats.maxHp or 100
    p.hp = math.min(p.hp or p.maxHp, p.maxHp)
    
    p.maxShield = activeStats.maxShield or 100
    p.shield = math.min(p.shield or p.maxShield, p.maxShield)
    
    p.maxEnergy = activeStats.maxEnergy or 100
    p.energy = math.min(p.energy or p.maxEnergy, p.maxEnergy)
    
    -- Sync dash
    if p.dash then
        p.dash.maxCharges = activeStats.dashCharges or 1
        p.dash.charges = math.min(p.dash.charges or p.dash.maxCharges, p.dash.maxCharges)
    end
    
    -- 5. Refresh Pet Stats if active
    local pets = require('pets')
    pets.recompute(state)
    
    print("[MODS] Active stats refreshed for player and pet")
end

return mods
