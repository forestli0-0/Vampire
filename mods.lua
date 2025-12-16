-- mods.lua
-- Warframe-style MOD system (8 slots per weapon)

local mods = {}

-- =============================================================================
-- MOD CATALOG (10 Basic MODs)
-- =============================================================================
-- Each MOD: name, description, stat affected, cost per level, bonus per level

mods.catalog = {
    -- Damage MODs
    serration = {
        name = "膛线",
        desc = "伤害增幅",
        stat = 'damage',
        type = 'mult',  -- multiplicative bonus
        cost = {4, 5, 6, 7, 8, 9},  -- cost at rank 0-5
        value = {0.15, 0.30, 0.45, 0.60, 0.75, 0.90}
    },
    heavy_caliber = {
        name = "重装口径",
        desc = "伤害增幅 (降低精准)",
        stat = 'damage',
        type = 'mult',
        cost = {6, 7, 8, 9, 10, 11},
        value = {0.15, 0.30, 0.45, 0.60, 0.75, 0.90}
    },
    
    -- Multishot MODs
    split_chamber = {
        name = "分裂膛室",
        desc = "多重射击",
        stat = 'multishot',
        type = 'add',
        cost = {5, 6, 7, 8, 9, 10},
        value = {0.15, 0.30, 0.45, 0.60, 0.75, 0.90}
    },
    
    -- Critical MODs
    point_strike = {
        name = "致命一击",
        desc = "暴击几率",
        stat = 'critChance',
        type = 'add',
        cost = {4, 5, 6, 7, 8, 9},
        value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    },
    vital_sense = {
        name = "致命打击",
        desc = "暴击伤害",
        stat = 'critMult',
        type = 'add',
        cost = {4, 5, 6, 7, 8, 9},
        value = {0.20, 0.40, 0.60, 0.80, 1.00, 1.20}
    },
    
    -- Speed MODs
    speed_trigger = {
        name = "速度扳机",
        desc = "射速增加",
        stat = 'fireRate',
        type = 'mult',
        cost = {4, 5, 6, 7, 8, 9},
        value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    },
    shred = {
        name = "撕裂",
        desc = "射速+穿透",
        stat = 'fireRate',
        type = 'mult',
        cost = {5, 6, 7, 8, 9, 10},
        value = {0.05, 0.10, 0.15, 0.20, 0.25, 0.30}
    },
    
    -- Magazine MODs
    magazine_warp = {
        name = "弹匣扭曲",
        desc = "弹匣容量",
        stat = 'magSize',
        type = 'mult',
        cost = {4, 5, 6, 7, 8, 9},
        value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    },
    fast_hands = {
        name = "快手",
        desc = "换弹速度",
        stat = 'reloadSpeed',
        type = 'mult',
        cost = {3, 4, 5, 6, 7, 8},
        value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    },
    
    -- Status MOD
    status_matrix = {
        name = "异常矩阵",
        desc = "异常几率",
        stat = 'statusChance',
        type = 'add',
        cost = {4, 5, 6, 7, 8, 9},
        value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    }
}

-- =============================================================================
-- CAPACITY SYSTEM
-- =============================================================================

-- Calculate weapon mod capacity based on level
function mods.getWeaponCapacity(weaponLevel)
    return (weaponLevel or 1) * 10
end

-- Calculate total cost of equipped mods
function mods.getTotalCost(equippedMods)
    local total = 0
    for _, mod in ipairs(equippedMods or {}) do
        if mod and mod.key then
            local def = mods.catalog[mod.key]
            if def and def.cost then
                local rank = math.max(0, math.min(5, mod.rank or 0))
                total = total + (def.cost[rank + 1] or 0)
            end
        end
    end
    return total
end

-- Check if a mod can be equipped (within capacity)
function mods.canEquip(equippedMods, newModKey, newModRank, capacity)
    local currentCost = mods.getTotalCost(equippedMods)
    local def = mods.catalog[newModKey]
    if not def then return false end
    
    local rank = math.max(0, math.min(5, newModRank or 0))
    local newCost = def.cost[rank + 1] or 0
    
    return (currentCost + newCost) <= capacity
end

-- =============================================================================
-- APPLY MOD BONUSES
-- =============================================================================

-- Apply mods to weapon stats
function mods.applyToWeapon(baseStats, equippedMods)
    local stats = {}
    for k, v in pairs(baseStats or {}) do
        stats[k] = v
    end
    
    -- Collect bonuses
    local multBonuses = {}
    local addBonuses = {}
    
    for _, mod in ipairs(equippedMods or {}) do
        if mod and mod.key then
            local def = mods.catalog[mod.key]
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
    
    -- Apply multiplicative bonuses (e.g., damage)
    if multBonuses.damage then
        stats.damage = (stats.damage or 10) * (1 + multBonuses.damage)
    end
    if multBonuses.fireRate then
        stats.cd = (stats.cd or 1) / (1 + multBonuses.fireRate)
    end
    if multBonuses.magSize then
        stats.maxMagazine = math.floor((stats.maxMagazine or 30) * (1 + multBonuses.magSize))
        stats.magazine = math.min(stats.magazine or 0, stats.maxMagazine)
    end
    if multBonuses.reloadSpeed then
        stats.reloadTime = (stats.reloadTime or 1.5) / (1 + multBonuses.reloadSpeed)
    end
    
    -- Apply additive bonuses
    if addBonuses.multishot then
        stats.multishot = (stats.multishot or 0) + addBonuses.multishot
    end
    if addBonuses.critChance then
        stats.critChance = (stats.critChance or 0.05) + addBonuses.critChance
    end
    if addBonuses.critMult then
        stats.critMultiplier = (stats.critMultiplier or 1.5) + addBonuses.critMult
    end
    if addBonuses.statusChance then
        stats.statusChance = (stats.statusChance or 0) + addBonuses.statusChance
    end
    
    return stats
end

-- =============================================================================
-- EQUIP/UNEQUIP
-- =============================================================================

-- Initialize weapon mod slots (8 slots)
function mods.initWeaponMods(state, weaponKey)
    state.weaponMods = state.weaponMods or {}
    if not state.weaponMods[weaponKey] then
        state.weaponMods[weaponKey] = {
            slots = {},  -- 8 slots: {key, rank}
            level = 1    -- weapon level for capacity
        }
    end
    return state.weaponMods[weaponKey]
end

-- Equip a mod to a weapon slot
function mods.equipMod(state, weaponKey, slotIndex, modKey, modRank)
    local wm = mods.initWeaponMods(state, weaponKey)
    local capacity = mods.getWeaponCapacity(wm.level)
    
    -- Check slot bounds (1-8)
    if slotIndex < 1 or slotIndex > 8 then return false end
    
    -- Temporarily remove existing mod from slot
    local oldMod = wm.slots[slotIndex]
    wm.slots[slotIndex] = nil
    
    -- Check capacity
    if not mods.canEquip(wm.slots, modKey, modRank, capacity) then
        wm.slots[slotIndex] = oldMod  -- restore old mod
        return false
    end
    
    -- Equip new mod
    wm.slots[slotIndex] = {key = modKey, rank = modRank or 0}
    return true
end

-- Unequip a mod from a weapon slot
function mods.unequipMod(state, weaponKey, slotIndex)
    local wm = mods.initWeaponMods(state, weaponKey)
    if slotIndex >= 1 and slotIndex <= 8 then
        wm.slots[slotIndex] = nil
        return true
    end
    return false
end

-- Get list of mods for a weapon
function mods.getWeaponMods(state, weaponKey)
    if not state.weaponMods or not state.weaponMods[weaponKey] then
        return {}
    end
    return state.weaponMods[weaponKey].slots or {}
end

-- =============================================================================
-- DEBUG/TEST FUNCTION
-- =============================================================================

-- Test function: Equip sample mods to a weapon
function mods.equipTestMods(state, weaponKey)
    mods.initWeaponMods(state, weaponKey)
    state.weaponMods[weaponKey].level = 30  -- Max level for testing
    
    -- Equip some test mods
    mods.equipMod(state, weaponKey, 1, 'serration', 3)      -- 60% damage
    mods.equipMod(state, weaponKey, 2, 'split_chamber', 2)  -- 45% multishot
    mods.equipMod(state, weaponKey, 3, 'point_strike', 3)   -- 40% crit
    mods.equipMod(state, weaponKey, 4, 'vital_sense', 2)    -- 60% crit mult
    
    print(string.format("[MODS] Equipped test mods to %s", weaponKey))
end

return mods
