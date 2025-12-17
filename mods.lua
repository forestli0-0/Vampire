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
        stat = 'speed', type = 'mult',
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
    for _, mod in ipairs(slots or {}) do
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
    
    for _, mod in ipairs(slots or {}) do
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

-- Convenience: Apply weapon mods
function mods.applyWeaponMods(state, weaponKey, baseStats)
    local slots = mods.getSlots(state, 'weapons', weaponKey)
    return mods.applyToStats(baseStats, slots, mods.weapon)
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

return mods
