-- abilities.lua
-- 4-Ability system (Warframe-style)

local abilities = {}

-- Ability definitions
abilities.catalog = {
    dash_boost = {
        name = "冲刺",
        key = 'q',
        cost = 25,
        cd = 3,
        effect = function(state)
            local p = state.player
            if not p then return false end
            
            local player = require('player')
            -- Enhanced dash: reset dash charges + invincibility
            if p.dash then
                p.dash.charges = p.dash.maxCharges or 1
            end
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5)
            
            -- Try to perform dash
            player.tryDash(state)
            
            if state.spawnEffect then
                state.spawnEffect('shock', p.x, p.y, 1.2)
            end
            if state.playSfx then state.playSfx('shoot') end
            
            return true
        end
    },
    aoe_blast = {
        name = "爆发",
        key = 'e',
        cost = 50,
        cd = 8,
        effect = function(state)
            local p = state.player
            if not p then return false end
            
            local radius = 150 * (p.stats.abilityRange or 1.0)
            local damage = 80 * (p.stats.abilityStrength or 1.0)
            
            -- Damage all enemies in radius
            for _, e in ipairs(state.enemies) do
                if e.health and e.health > 0 then
                    local dx = e.x - p.x
                    local dy = e.y - p.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= radius then
                        e.health = e.health - damage
                        e.hp = e.health
                        if state.texts then
                            table.insert(state.texts, {x=e.x, y=e.y-20, text=math.floor(damage), color={1, 0.5, 0.2}, life=0.5})
                        end
                    end
                end
            end
            
            -- VFX
            if state.spawnEffect then
                state.spawnEffect('blast_hit', p.x, p.y, 2)
            end
            state.shakeAmount = (state.shakeAmount or 0) + 6
            if state.playSfx then state.playSfx('hit') end
            
            return true
        end
    },
    shield_buff = {
        name = "护盾",
        key = 'c',
        cost = 75,
        cd = 15,
        effect = function(state)
            local p = state.player
            if not p then return false end
            
            -- Grant temporary shield
            p.tempShield = (p.tempShield or 0) + 50
            p.tempShieldTimer = 10 * (p.stats.abilityDuration or 1.0)  -- Duration
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.3)
            
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-50, text="+50 护盾", color={0.4, 0.8, 1}, life=1.5})
            end
            if state.spawnEffect then
                state.spawnEffect('shock', p.x, p.y, 1.5)
            end
            if state.playSfx then state.playSfx('gem') end
            
            return true
        end
    },
    ultimate = {
        name = "终极",
        key = 'v',
        cost = 100,
        cd = 30,
        effect = function(state)
            local p = state.player
            if not p then return false end
            
            local radius = 300 * (p.stats.abilityRange or 1.0)
            local damage = 200 * (p.stats.abilityStrength or 1.0)
            
            -- Massive damage to all enemies
            for _, e in ipairs(state.enemies) do
                if e.health and e.health > 0 then
                    local dx = e.x - p.x
                    local dy = e.y - p.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= radius then
                        e.health = e.health - damage
                        e.hp = e.health
                        if state.texts then
                            table.insert(state.texts, {x=e.x, y=e.y-20, text=math.floor(damage), color={1, 0.3, 0.1}, life=0.6, scale=1.3})
                        end
                    end
                end
            end
            
            -- Epic VFX
            if state.spawnEffect then
                state.spawnEffect('blast_hit', p.x, p.y, 3)
            end
            state.shakeAmount = (state.shakeAmount or 0) + 12
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 1.0)
            if state.playSfx then state.playSfx('hit') end
            
            return true
        end
    }
}

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
            p.stats.speed = (p.stats.speed or 100) * 1.10
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
            if modded.speed then p.stats.speed = modded.speed end
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
