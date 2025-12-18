-- abilities.lua
-- 4-Ability system (Warframe-style)

local abilities = {}

-- Ability definitions structured by class
abilities.catalog = {
    warrior = {
        {
            name = "斩击突进", -- Slash Dash
            cost = 25,
            effect = function(state)
                local p = state.player
                local playerMod = require('player')
                p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5)
                local ang = p.aimAngle or 0
                playerMod.tryDash(state, math.cos(ang), math.sin(ang))
                -- Damage enemies in a line (simplified AoE around player during dash)
                local radius = 80 * (p.stats.abilityRange or 1.0)
                local damage = 50 * (p.stats.abilityStrength or 1.0)
                for _, e in ipairs(state.enemies) do
                    local dx, dy = e.x - p.x, e.y - p.y
                    if dx*dx + dy*dy < radius*radius then
                        e.health = (e.health or 0) - damage
                        if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.5) end
                    end
                end
                if state.playSfx then state.playSfx('shoot') end
                return true
            end
        },
        {
            name = "战争践踏", -- Warcry / Stomp combo
            cost = 50,
            effect = function(state)
                local p = state.player
                local radius = 150 * (p.stats.abilityRange or 1.0)
                local duration = 10 * (p.stats.abilityDuration or 1.0)
                -- Buff armor and slow enemies
                p.stats.armor = (p.stats.armor or 0) + 20
                -- Simple timer to revert armor could be added, but for now let's just do a blast
                for _, e in ipairs(state.enemies) do
                    local dx, dy = e.x - p.x, e.y - p.y
                    if dx*dx + dy*dy < radius*radius then
                        e.health = (e.health or 0) - 30
                        e.frozenTimer = 2.0 -- Stun
                    end
                end
                if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 2.0) end
                return true
            end
        },
        {
            name = "钢化皮肤", -- Iron Skin
            cost = 75,
            effect = function(state)
                local p = state.player
                local amount = 100 * (p.stats.abilityStrength or 1.0)
                p.shield = (p.shield or 0) + amount
                p.invincibleTimer = math.max(p.invincibleTimer or 0, 1.0)
                if state.texts then
                    table.insert(state.texts, {x=p.x, y=p.y-50, text="IRON SKIN", color={0.8, 0.8, 0.4}, life=1.5})
                end
                return true
            end
        },
        {
            name = "显赫之剑", -- Exalted Blade
            cost = 100,
            effect = function(state)
                local weapons = require('weapons')
                local p = state.player
                -- Temporarily boost melee damage and speed
                p.stats.meleeDamageMult = (p.stats.meleeDamageMult or 1) + 1.0
                p.stats.meleeSpeed = (p.stats.meleeSpeed or 1) * 1.5
                p.exaltedTimer = 15 * (p.stats.abilityDuration or 1.0)
                if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 3.0) end
                return true
            end
        }
    },
    mage = {
        {
            name = "火球术", -- Fireball
            cost = 25,
            effect = function(state)
                local p = state.player
                local ang = p.aimAngle or 0
                local target = { x = p.x + math.cos(ang) * 100, y = p.y + math.sin(ang) * 100 }
                -- Spawn a projectile
                local spawnFunc = state.spawnProjectile or (require('weapons').spawnProjectile)
                if spawnFunc then
                    spawnFunc(state, 'fireball', p.x, p.y, target, {damage = 40 * (p.stats.abilityStrength or 1.0)})
                end
                return true
            end
        },
        {
            name = "能量爆发", -- Fire Blast
            cost = 50,
            effect = function(state)
                local p = state.player
                local radius = 200 * (p.stats.abilityRange or 1.0)
                for _, e in ipairs(state.enemies) do
                    local dx, dy = e.x - p.x, e.y - p.y
                    if dx*dx + dy*dy < radius*radius then
                        e.health = (e.health or 0) - 60
                        e.fireTimer = 5.0 -- DoT
                    end
                end
                if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 2.0) end
                return true
            end
        },
        {
            name = "加速增幅", -- Accelerant
            cost = 75,
            effect = function(state)
                local p = state.player
                p.stats.moveSpeed = (p.stats.moveSpeed or 200) * 1.3
                p.stats.abilityStrength = (p.stats.abilityStrength or 1.0) + 0.5
                p.buffTimer = 10 * (p.stats.abilityDuration or 1.0)
                return true
            end
        },
        {
            name = "世界在燃烧", -- World on Fire
            cost = 100,
            effect = function(state)
                local p = state.player
                p.wofRunning = true
                p.wofTimer = 15 * (p.stats.abilityDuration or 1.0)
                if state.texts then table.insert(state.texts, {x=p.x, y=p.y-50, text="WORLD ON FIRE", color={1, 0.4, 0.1}, life=2}) end
                return true
            end
        }
    },
    beastmaster = {
        {
            name = "狩猎标记", -- Hunt
            cost = 25,
            effect = function(state)
                -- Buff pets
                if state.pets then
                    for _, pet in ipairs(state.pets) do
                        pet.damageMult = (pet.damageMult or 1) * 1.5
                    end
                end
                return true
            end
        },
        {
            name = "狂暴怒吼", -- Howl
            cost = 50,
            effect = function(state)
                local p = state.player
                local radius = 250
                for _, e in ipairs(state.enemies) do
                    local dx, dy = e.x - p.x, e.y - p.y
                    if dx*dx + dy*dy < radius*radius then
                        e.stunTimer = 3.0
                    end
                end
                return true
            end
        },
        {
            name = "群体治愈", -- Pack Health
            cost = 75,
            effect = function(state)
                local p = state.player
                p.hp = math.min(p.maxHp, p.hp + 50)
                if state.pets then
                    for _, pet in ipairs(state.pets) do
                        pet.hp = (pet.hp or 100) + 50
                    end
                end
                return true
            end
        },
        {
            name = "幽灵兽群", -- Spectral Pack
            cost = 100,
            effect = function(state)
                -- Spawn temporary extra pets
                local petsModule = require('pets')
                for i=1, 3 do
                    petsModule.spawnPet(state, 'ghost_wolf', state.player.x, state.player.y)
                end
                return true
            end
        }
    }
}

-- Simple helper to get ability definition
function abilities.getAbilityDef(state, index)
    local p = state.player
    local className = p.class or 'warrior'
    local set = abilities.catalog[className]
    if set and set[index] then
        return set[index]
    end
    return nil
end

-- =============================================================================
-- PASSIVE SKILLS (Warframe-style innate abilities per class)
-- =============================================================================

abilities.passives = {
    warrior = {
        name = "战士之魂",
        desc = "近战伤害+20%, 护甲+15%",
        icon = "⚔️",
        apply = function(state)
            local p = state.player
            if not p or not p.stats then return end
            p.stats.meleeDamageMult = (p.stats.meleeDamageMult or 1) + 0.20
            p.stats.armor = (p.stats.armor or 0) + 15
        end
    },
    mage = {
        name = "能量亲和",
        desc = "能量回复+50%, 技能CD-15%",
        icon = "✨",
        apply = function(state)
            local p = state.player
            if not p then return end
            p.energyRegen = (p.energyRegen or 2) * 1.5
            p.abilityCdMult = (p.abilityCdMult or 1) * 0.85
        end
    },
    beastmaster = {
        name = "野性直觉",
        desc = "移动速度+10%, 暴击率+5%",
        icon = "🐾",
        apply = function(state)
            local p = state.player
            if not p or not p.stats then return end
            p.stats.moveSpeed = (p.stats.moveSpeed or 170) * 1.10
            p.stats.critChance = (p.stats.critChance or 0) + 0.05
        end
    }
}

-- Apply passive for current class
function abilities.applyPassive(state)
    local p = state.player
    if not p then return end
    
    local className = p.class or 'warrior'
    local passive = abilities.passives[className]
    
    if passive and passive.apply then
        passive.apply(state)
        p.passiveApplied = className
        
        -- Show notification
        if state.texts then
            table.insert(state.texts, {
                x = p.x, y = p.y - 60,
                text = passive.icon .. " " .. passive.name,
                color = {0.8, 0.9, 1},
                life = 2.0,
                scale = 1.2
            })
        end
    end
end

-- Get current passive info
function abilities.getPassiveInfo(state)
    local p = state.player
    if not p then return nil end
    
    local className = p.class or 'warrior'
    return abilities.passives[className]
end

-- Check if ability can be used
function abilities.canUse(state, abilityKey)
    local p = state.player
    if not p then return false end
    
    local def = abilities.catalog[abilityKey]
    if not def then return false end
    
    -- Check energy
    if (p.energy or 0) < def.cost then return false end
    
    -- Check cooldown
    p.abilityCooldowns = p.abilityCooldowns or {}
    if (p.abilityCooldowns[abilityKey] or 0) > 0 then return false end
    
    return true
end

-- Try to activate ability
function abilities.tryActivate(state, abilityKey)
    if not abilities.canUse(state, abilityKey) then return false end
    
    local p = state.player
    local def = abilities.catalog[abilityKey]
    
    -- Consume energy (Efficiency reduces cost)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    p.energy = (p.energy or 0) - cost
    
    -- Set cooldown (Duration could affect this, but standard WF is fixed CD or affected by Streamline in some games. Here we keep it fixed but could add Duration scaling if needed)
    p.abilityCooldowns = p.abilityCooldowns or {}
    p.abilityCooldowns[abilityKey] = def.cd
    
    -- Execute effect
    local success = def.effect(state)
    
    return success
end

-- Get ability key for keyboard input
function abilities.getAbilityForKey(key)
    for abilityKey, def in pairs(abilities.catalog) do
        if def.key == key then
            return abilityKey
        end
    end
    return nil
end

-- Update cooldowns and energy regen
function abilities.update(state, dt)
    local p = state.player
    if not p then return end
    
    -- Apply passive on first frame if not applied
    if not p.passiveApplied then
        abilities.applyPassive(state)
    end
    
    -- Apply warframe MODs on first frame if not applied
    if not p.warframeModsApplied then
        local mods = require('mods')
        local slots = mods.getSlots(state, 'warframe', nil)
        local hasModsEquipped = false
        for _, m in ipairs(slots) do if m then hasModsEquipped = true break end end
        
        if hasModsEquipped then
            p.stats = p.stats or {}
            -- Apply warframe mods to player stats
            local modded = mods.applyWarframeMods(state, p.stats)
            for k, v in pairs(modded) do
                p.stats[k] = v
            end
            -- Also apply to direct player fields
            if modded.maxHp then p.maxHp = modded.maxHp end
            if modded.maxEnergy then p.maxEnergy = modded.maxEnergy end
            if modded.energyRegen then p.energyRegen = modded.energyRegen end
            if modded.moveSpeed then p.stats.moveSpeed = modded.moveSpeed end
            if modded.armor then p.stats.armor = modded.armor end
            
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-40, text="角色MOD已生效", color={0.5, 0.8, 1}, life=1.5})
            end
        end
        p.warframeModsApplied = true
    end
    
    -- Energy regen (with MOD bonus)
    local regen = (p.stats and p.stats.energyRegen) or p.energyRegen or 2
    p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + regen * dt)
    
    -- Apply ability CD multiplier if mage passive is active
    local cdMult = p.abilityCdMult or 1
    
    -- Cooldown tick
    p.abilityCooldowns = p.abilityCooldowns or {}
    for key, cd in pairs(p.abilityCooldowns) do
        if cd > 0 then
            p.abilityCooldowns[key] = cd - dt
        end
    end
    
    -- Temp shield decay
    if p.tempShieldTimer and p.tempShieldTimer > 0 then
        p.tempShieldTimer = p.tempShieldTimer - dt
        if p.tempShieldTimer <= 0 then
            p.tempShield = 0
            p.tempShieldTimer = nil
        end
    end
end

return abilities
