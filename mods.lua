-- mods.lua
-- Unified Warframe-style MOD System
-- Supports: Warframe (character), Weapon, Companion (pet)

local mods = {}

-- =============================================================================
-- MOD CATALOG
-- =============================================================================

-- WARFRAME MODs (Character)
mods.warframe = {
    vitality = {
        name = "生命力", desc = "生命值",
        stat = 'maxHp', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    steel_fiber = {
        name = "钢铁纤维", desc = "护甲值",
        stat = 'armor', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    redirection = {
        name = "重定向", desc = "护盾值",
        stat = 'maxShield', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    flow = {
        name = "流线型", desc = "能量上限",
        stat = 'maxEnergy', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.25,0.50,0.75,1.00,1.25,1.50}
    },
    streamline = {
        name = "精简", desc = "技能效率",
        stat = 'abilityEfficiency', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    intensify = {
        name = "强化", desc = "技能强度",
        stat = 'abilityStrength', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    rush = {
        name = "冲刺", desc = "移动速度",
        stat = 'moveSpeed', type = 'mult',
        cost = {3,4,5,6,7,8}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    quick_thinking = {
        name = "快速思维", desc = "能量回复",
        stat = 'energyRegen', type = 'mult',
        cost = {5,6,7,8,9,10}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    continuity = {
        name = "持续", desc = "技能持续时间",
        stat = 'abilityDuration', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    stretch = {
        name = "伸展", desc = "技能范围",
        stat = 'abilityRange', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.07,0.14,0.21,0.28,0.35,0.42}
    }
}

-- WEAPON MODs
mods.weapon = {
    serration = {
        name = "膛线", desc = "伤害",
        stat = 'damage', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    heavy_caliber = {
        name = "重装口径", desc = "伤害",
        stat = 'damage', type = 'mult',
        cost = {6,7,8,9,10,11}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    split_chamber = {
        name = "分裂膛室", desc = "多重射击",
        stat = 'multishot', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    point_strike = {
        name = "致命一击", desc = "暴击率",
        stat = 'critChance', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    vital_sense = {
        name = "致命打击", desc = "暴击伤害",
        stat = 'critMult', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    speed_trigger = {
        name = "速度扳机", desc = "射速",
        stat = 'fireRate', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    magazine_warp = {
        name = "弹匣扭曲", desc = "弹匣容量",
        stat = 'magSize', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    fast_hands = {
        name = "快手", desc = "换弹速度",
        stat = 'reloadSpeed', type = 'mult',
        cost = {3,4,5,6,7,8}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    status_matrix = {
        name = "异常矩阵", desc = "异常几率",
        stat = 'statusChance', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    pressure_point = {
        name = "压力点", desc = "近战伤害",
        stat = 'meleeDamage', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    metal_auger = {
        name = "金属促退器", desc = "穿透",
        stat = 'pierce', type = 'add',
        cost = {6,7,8,9,10,11}, value = {0.4, 0.8, 1.2, 1.6, 2.0, 2.4}
    },
    stabilizer = {
        name = "稳定器", desc = "降低后坐力",
        stat = 'recoil', type = 'mult',
        cost = {3,4,5,6,7,8}, value = {0.15, 0.30, 0.45, 0.60, 0.75, 0.90}
    },
    guided_ordnance = {
        name = "制导法令", desc = "降低散射",
        stat = 'bloom', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    }
}

-- COMPANION MODs (Pet)
mods.companion = {
    link_health = {
        name = "连接生命", desc = "生命继承",
        stat = 'healthLink', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    link_armor = {
        name = "连接护甲", desc = "护甲继承",
        stat = 'armorLink', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    bite = {
        name = "撕咬", desc = "攻击暴击",
        stat = 'critChance', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    maul = {
        name = "重击", desc = "攻击伤害",
        stat = 'damage', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    pack_leader = {
        name = "群首", desc = "近战吸血",
        stat = 'meleeLeeech', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    }
}

-- =============================================================================
-- SLOT SYSTEM
-- =============================================================================

local MAX_SLOTS = 8
local DEFAULT_CAPACITY = 30

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
        if stats[stat] then
            stats[stat] = stats[stat] * (1 + bonus)
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
    state.runMods = {
        -- Inventory of collected mods: { {key, category, rank, rarity}, ... }
        inventory = {},
        
        -- Equipped slots per category
        warframe = { slots = {}, capacity = 30 },
        weapons = {},  -- weapons[weaponKey] = { slots = {}, capacity = 30 }
        companion = { slots = {}, capacity = 30 },
        
        -- Stats
        totalCollected = 0,
        totalEquipped = 0
    }
end

-- Get run mod slots for category
function mods.getRunSlots(state, category, key)
    if not state.runMods then return {} end
    
    if category == 'weapons' then
        if not state.runMods.weapons[key] then
            state.runMods.weapons[key] = { slots = {}, capacity = 30 }
        end
        return state.runMods.weapons[key].slots
    else
        if not state.runMods[category] then
            state.runMods[category] = { slots = {}, capacity = 30 }
        end
        return state.runMods[category].slots
    end
end

-- Get run mod slot data for capacity
function mods.getRunSlotData(state, category, key)
    if not state.runMods then return nil end
    
    if category == 'weapons' then
        if not state.runMods.weapons[key] then
            state.runMods.weapons[key] = { slots = {}, capacity = 30 }
        end
        return state.runMods.weapons[key]
    else
        if not state.runMods[category] then
            state.runMods[category] = { slots = {}, capacity = 30 }
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
    baseStats.dashCharges = baseStats.dashCharges or 1
    
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
