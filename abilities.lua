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
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                
                p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5)
                local ang = p.aimAngle or 0
                playerMod.tryDash(state, math.cos(ang), math.sin(ang))
                
                -- Damage enemies in a line
                local radius = 80 * rng
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local instance = calc.createInstance({
                        damage = math.floor(50 * str),
                        critChance = 0.15,
                        critMultiplier = 2.0,
                        statusChance = 0.40,
                        elements = {'SLASH'},
                        damageBreakdown = {SLASH = 1},
                        weaponTags = {'ability', 'melee'}
                    })
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local dx, dy = e.x - p.x, e.y - p.y
                            if dx*dx + dy*dy < radius*radius then
                                calc.applyHit(state, e, instance)
                                if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.5) end
                            end
                        end
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
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                local radius = 150 * rng
                -- Buff armor temporarily
                p.stats.armor = (p.stats.armor or 0) + math.floor(20 * str)
                
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local instance = calc.createInstance({
                        damage = math.floor(40 * str),
                        critChance = 0.10,
                        critMultiplier = 1.8,
                        statusChance = 0.60,
                        elements = {'IMPACT'},
                        damageBreakdown = {IMPACT = 1},
                        weaponTags = {'ability', 'area'},
                        effectType = 'STUN',
                        effectData = {duration = 2.0 * dur}
                    })
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local dx, dy = e.x - p.x, e.y - p.y
                            if dx*dx + dy*dy < radius*radius then
                                calc.applyHit(state, e, instance)
                                e.frozenTimer = 2.0 * dur
                            end
                        end
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
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                local radius = 200 * rng
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local instance = calc.createInstance({
                        damage = math.floor(60 * str),
                        critChance = 0.15,
                        critMultiplier = 2.0,
                        statusChance = 0.70,
                        elements = {'HEAT'},
                        damageBreakdown = {HEAT = 1},
                        weaponTags = {'ability', 'area', 'fire'}
                    })
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local dx, dy = e.x - p.x, e.y - p.y
                            if dx*dx + dy*dy < radius*radius then
                                calc.applyHit(state, e, instance)
                                e.fireTimer = (e.fireTimer or 0) + 5.0 * dur
                            end
                        end
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
    },
    volt = {
        {
            name = "电击", -- Shock
            cost = 25,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                
                -- Find nearest enemy (up to a max range)
                local maxRange = 400 * rng
                local maxR2 = maxRange * maxRange
                local nearestEnemy, nearestDist = nil, math.huge
                for _, e in ipairs(state.enemies or {}) do
                    if e and not e.isDummy and e.health and e.health > 0 then
                        local dx, dy = e.x - p.x, e.y - p.y
                        local dist = dx * dx + dy * dy
                        if dist < nearestDist and dist < maxR2 then
                            nearestDist = dist
                            nearestEnemy = e
                        end
                    end
                end
                
                if not nearestEnemy then return false end
                
                local ok, calc = pcall(require, 'calculator')
                local damage = math.floor(50 * str)
                local chainRange = 180 * rng
                local chainR2 = chainRange * chainRange
                local maxChains = math.floor(3 + 2 * rng)  -- 3-5 chains based on range
                
                -- Build chain of targets, recording positions for VFX
                local chainTargets = {nearestEnemy}
                local hit = {[nearestEnemy] = true}
                local current = nearestEnemy
                
                for i = 1, maxChains do
                    local nextEnemy, nextDist = nil, math.huge
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy and not hit[e] and e.health and e.health > 0 then
                            local dx, dy = e.x - current.x, e.y - current.y
                            local dist = dx * dx + dy * dy
                            if dist < chainR2 and dist < nextDist then
                                nextDist = dist
                                nextEnemy = e
                            end
                        end
                    end
                    if nextEnemy then
                        hit[nextEnemy] = true
                        table.insert(chainTargets, nextEnemy)
                        current = nextEnemy
                    else
                        break
                    end
                end
                
                -- Create damage instance
                local instance = nil
                if ok and calc then
                    instance = calc.createInstance({
                        damage = damage,
                        critChance = 0.15,
                        critMultiplier = 2.0,
                        statusChance = 0.80,
                        elements = {'ELECTRIC'},
                        damageBreakdown = {ELECTRIC = 1},
                        weaponTags = {'ability', 'electric'}
                    })
                end
                
                -- Create visual lightning chain effect
                -- Store lightning segments for draw.lua to render
                state.voltLightningChains = state.voltLightningChains or {}
                local chainData = {
                    segments = {},
                    timer = 0.5,  -- Display for 0.5 seconds
                    alpha = 1.0
                }
                
                -- First segment: player to first enemy
                table.insert(chainData.segments, {
                    x1 = p.x, y1 = p.y,
                    x2 = chainTargets[1].x, y2 = chainTargets[1].y,
                    width = 16
                })
                
                -- Apply damage to first target
                if instance and ok and calc then
                    calc.applyHit(state, chainTargets[1], instance)
                else
                    chainTargets[1].health = (chainTargets[1].health or 0) - damage
                end
                if state.spawnEffect then state.spawnEffect('shock', chainTargets[1].x, chainTargets[1].y, 1.0) end
                
                -- Chain segments between enemies
                for i = 2, #chainTargets do
                    local prev = chainTargets[i-1]
                    local curr = chainTargets[i]
                    table.insert(chainData.segments, {
                        x1 = prev.x, y1 = prev.y,
                        x2 = curr.x, y2 = curr.y,
                        width = 12  -- Slightly thinner for chains
                    })
                    -- Apply damage with slight falloff
                    local chainDmg = math.floor(damage * (1 - 0.1 * (i-1)))
                    if instance and ok and calc then
                        local chainInstance = calc.createInstance({
                            damage = chainDmg,
                            critChance = 0.15,
                            critMultiplier = 2.0,
                            statusChance = 0.80,
                            elements = {'ELECTRIC'},
                            damageBreakdown = {ELECTRIC = 1},
                            weaponTags = {'ability', 'electric'}
                        })
                        calc.applyHit(state, curr, chainInstance)
                    else
                        curr.health = (curr.health or 0) - chainDmg
                    end
                    if state.spawnEffect then state.spawnEffect('shock', curr.x, curr.y, 0.8) end
                end
                
                table.insert(state.voltLightningChains, chainData)
                
                if state.playSfx then state.playSfx('shoot') end
                return true
            end
        },
        {
            name = "极速", -- Speed (TEMPORARY buff!)
            cost = 50,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local dur = p.stats.abilityDuration or 1.0
                local rng = p.stats.abilityRange or 1.0
                
                -- Speed buff values
                local speedBonus = 0.50 * str  -- +50% base, scaled by strength
                local duration = 10 * dur
                
                -- Store original speed if not already buffed
                if not p.speedBuffActive then
                    p.originalMoveSpeed = p.stats.moveSpeed or 170
                    p.originalAttackSpeed = p.stats.attackSpeedMult or 1.0
                end
                
                -- Apply TEMPORARY buff
                p.speedBuffActive = true
                p.speedBuffTimer = duration
                p.speedBuffMult = 1 + speedBonus
                p.attackSpeedBuffMult = 1 + (0.30 * str)  -- +30% attack speed
                
                -- Apply speed boost (will be reversed when timer expires)
                p.stats.moveSpeed = p.originalMoveSpeed * (1 + speedBonus)
                p.stats.attackSpeedMult = (p.originalAttackSpeed or 1.0) * (1 + 0.30 * str)
                
                -- Visual: electric aura around player while active
                p.speedAuraRadius = 50
                
                -- Visual feedback
                if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.5) end
                if state.texts then 
                    table.insert(state.texts, {
                        x = p.x, y = p.y - 50, 
                        text = string.format("极速! +%d%% (%ds)", math.floor(speedBonus * 100), math.floor(duration)), 
                        color = {0.3, 0.8, 1}, 
                        life = 2.0
                    }) 
                end
                if state.playSfx then state.playSfx('shoot') end
                return true
            end
        },
        {
            name = "电盾", -- Electric Shield
            cost = 75,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                -- Shield properties (arc-shaped)
                local shieldDuration = 25 * dur
                local shieldDistance = 60             -- Distance from player (arc radius)
                local arcWidth = 1.2                  -- Arc width in radians (~70 degrees)
                
                -- Get shield angle (in front of player based on aim)
                local angle = p.aimAngle or 0
                
                -- Create/update electric shield entity
                p.electricShield = {
                    active = true,
                    timer = shieldDuration,
                    angle = angle,
                    distance = shieldDistance,
                    arcWidth = arcWidth,
                    damageBonus = 0.50 * str,  -- +50% electricity damage to shots through shield
                    blocksProjectiles = true,  -- Key feature: blocks enemy bullets
                    followPlayer = true        -- Shield follows player aim
                }
                
                -- Visual feedback
                if state.texts then 
                    table.insert(state.texts, {
                        x = p.x, y = p.y - 50, 
                        text = string.format("电盾! (%ds)", math.floor(shieldDuration)), 
                        color = {0.4, 0.7, 1}, 
                        life = 2
                    }) 
                end
                if state.playSfx then state.playSfx('shoot') end
                return true
            end
        },
        {
            name = "放电", -- Discharge
            cost = 100,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                -- Discharge properties (NO enemy count limit - hits ALL enemies in range)
                local maxRadius = 350 * rng
                local damage = math.floor(40 * str)  -- Further reduced for balance
                local stunDuration = 4 * dur
                local expandSpeed = 400  -- pixels per second
                local expandDuration = maxRadius / expandSpeed
                
                -- Create expanding discharge wave
                p.dischargeWave = {
                    active = true,
                    x = p.x,
                    y = p.y,
                    currentRadius = 0,
                    maxRadius = maxRadius,
                    expandSpeed = expandSpeed,
                    timer = expandDuration + 0.5,  -- Extra time for lingering
                    hitEnemies = {},  -- Track which enemies have been hit
                    damage = damage,
                    stunDuration = stunDuration,
                    chainDamage = math.floor(damage * 0.3),  -- Secondary chain damage
                    chainRange = 150 * rng,
                    -- TESLA NODE SYSTEM: enemies become nodes that chain damage to each other
                    teslaNodeDuration = stunDuration,
                    teslaNodeDPS = math.floor(15 * str),  -- Damage per second between nodes
                    teslaNodeRange = 120 * rng  -- Range for node-to-node chains
                }
                
                -- Create VFX data for the expanding ring
                state.voltDischargeWaves = state.voltDischargeWaves or {}
                table.insert(state.voltDischargeWaves, {
                    x = p.x,
                    y = p.y,
                    currentRadius = 0,
                    maxRadius = maxRadius,
                    expandSpeed = expandSpeed,
                    timer = expandDuration + 0.3,
                    alpha = 1.0
                })
                
                -- Big visual/audio feedback
                state.shakeAmount = math.max(state.shakeAmount or 0, 10)
                if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 3.0) end
                if state.texts then 
                    table.insert(state.texts, {
                        x = p.x, y = p.y - 50, 
                        text = "放电!", 
                        color = {0.5, 0.8, 1}, 
                        life = 2,
                        scale = 1.5
                    }) 
                end
                if state.playSfx then state.playSfx('hit') end
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
    },
    volt = {
        name = "静电释放",
        desc = "移动速度+15%, 电击伤害+20%, 护盾回复速度+25%",
        icon = "⚡",
        apply = function(state)
            local p = state.player
            if not p or not p.stats then return end
            p.stats.moveSpeed = (p.stats.moveSpeed or 170) * 1.15
            -- Electric damage bonus (stored for calculator to use)
            p.stats.electricDamageBonus = (p.stats.electricDamageBonus or 0) + 0.20
            -- Faster shield regen
            p.stats.shieldRegenRate = (p.stats.shieldRegenRate or 0.25) * 1.25
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
