-- abilities.lua
-- 4-Ability system (Warframe-style)

local abilities = {}

-- Ability definitions structured by class
abilities.catalog = {
    warrior = {
        {
            name = "斩击突进", -- Slash Dash
            cost = 25,
            castTime = 0,  -- Instant (dash ability)
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
            name = "战争践踏", -- Warcry / Stomp
            cost = 50,
            castTime = 0.5,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                local bonus = math.floor(30 * str)
                abilities.addBuff(state, {
                    id = "warrior_stomp_armor",
                    timer = 15 * dur,
                    onApply = function(s) s.player.stats.armor = (s.player.stats.armor or 0) + bonus end,
                    onExpire = function(s) s.player.stats.armor = (s.player.stats.armor or 0) - bonus end
                })
                
                local radius = 200 * rng
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local inst = calc.createInstance({damage=math.floor(40*str), elements={'IMPACT'}, weaponTags={'ability','area'}})
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                calc.applyHit(state, e, inst)
                                e.frozenTimer = 3.0 * dur
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
            castTime = 0.3,
            effect = function(state)
                local p = state.player
                local amount = 150 * (p.stats.abilityStrength or 1.0)
                p.shield = (p.shield or 0) + amount
                p.invincibleTimer = math.max(p.invincibleTimer or 0, 1.5)
                if state.texts then table.insert(state.texts, {x=p.x, y=p.y-50, text="IRON SKIN", color={0.8, 0.8, 0.4}, life=1.5}) end
                return true
            end
        },
        {
            name = "显赫之剑", -- Exalted Blade
            cost = 100,
            castTime = 0.8,
            effect = function(state)
                local p = state.player
                if p.exaltedBladeActive then return false end
                
                local str = p.stats.abilityStrength or 1.0
                local dur = p.stats.abilityDuration or 1.0
                local dmgBonus = 1.0 * str
                local speedBonus = 1.5
                
                abilities.addBuff(state, {
                    id = "warrior_exalted_blade",
                    timer = 20 * dur,
                    onApply = function(s)
                        s.player.exaltedBladeActive = true
                        s.player.stats.meleeDamageMult = (s.player.stats.meleeDamageMult or 1) + dmgBonus
                        s.player.stats.meleeSpeed = (s.player.stats.meleeSpeed or 1) * speedBonus
                    end,
                    onExpire = function(s)
                        s.player.exaltedBladeActive = false
                        s.player.stats.meleeDamageMult = (s.player.stats.meleeDamageMult or 1) - dmgBonus
                        s.player.stats.meleeSpeed = (s.player.stats.meleeSpeed or 1) / speedBonus
                    end
                })
                
                if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 4.0) end
                return true
            end
        }
    },
    mage = {
        {
            name = "火球术",
            castTime = 0.25,
            cost = 25,
            effect = function(state)
                local p = state.player
                local ang = p.aimAngle or 0
                local target = { x = p.x + math.cos(ang) * 100, y = p.y + math.sin(ang) * 100 }
                local weapons = require('weapons')
                weapons.spawnProjectile(state, 'fireball', p.x, p.y, target, {damage = 50 * (p.stats.abilityStrength or 1.0)})
                return true
            end
        },
        {
            name = "能量爆发", -- Fire Blast
            cost = 50,
            castTime = 0.4,
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local radius = 220 * rng
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local inst = calc.createInstance({damage=math.floor(70*str), elements={'HEAT'}, weaponTags={'ability','fire'}})
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                calc.applyHit(state, e, inst)
                                e.fireTimer = (e.fireTimer or 0) + 6.0
                            end
                        end
                    end
                end
                if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 2.5) end
                return true
            end
        },
        {
            name = "加速增幅", -- Accelerant
            cost = 75,
            castTime = 0.3,
            effect = function(state)
                local p = state.player
                local dur = p.stats.abilityDuration or 1.0
                local str = p.stats.abilityStrength or 1.0
                local moveBonus = 0.4 * str
                local powerBonus = 0.5 * str
                
                abilities.addBuff(state, {
                    id = "mage_accelerant",
                    timer = 12 * dur,
                    onApply = function(s) 
                        s.player.stats.moveSpeed = (s.player.stats.moveSpeed or 170) * (1 + moveBonus)
                        s.player.stats.abilityStrength = (s.player.stats.abilityStrength or 1.0) + powerBonus
                    end,
                    onExpire = function(s)
                        s.player.stats.moveSpeed = (s.player.stats.moveSpeed or 170) / (1 + moveBonus)
                        s.player.stats.abilityStrength = (s.player.stats.abilityStrength or 1.0) - powerBonus
                    end
                })
                return true
            end
        },
        {
            name = "世界在燃烧", -- World on Fire
            cost = 100,
            castTime = 0.75,
            effect = function(state)
                local p = state.player
                if p.wofRunning then return false end
                local dur = p.stats.abilityDuration or 1.0
                abilities.addBuff(state, {
                    id = "mage_world_on_fire",
                    timer = 15 * dur,
                    onApply = function(s)
                        s.player.wofRunning = true
                        s.player.wofPulseTimer = 0
                    end,
                    onExpire = function(s)
                        s.player.wofRunning = false
                        if s.texts then table.insert(s.texts, {x=s.player.x, y=s.player.y-30, text="火焰熄灭", color={0.6,0.6,0.6}, life=1}) end
                    end
                })
                if state.texts then table.insert(state.texts, {x=p.x, y=p.y-50, text="WORLD ON FIRE", color={1, 0.4, 0.1}, life=2}) end
                return true
            end
        }
    },

    beastmaster = {
        {
            name = "狩猎标记", -- Hunt
            cost = 25,
            castTime = 0.2,  -- Quick mark
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
            castTime = 0.6,  -- Roar animation
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
            castTime = 0.4,  -- Healing channel
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
            castTime = 1.0,  -- Summoning takes time
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
            castTime = 0,  -- Instant like WF Volt
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
            castTime = 0.4,  -- Quick buff animation
            effect = function(state)
                local p = state.player
                local str = p.stats.abilityStrength or 1.0
                local dur = p.stats.abilityDuration or 1.0
                
                local speedMult = 1 + (0.50 * str)
                local atkSpeedMult = 1 + (0.30 * str)
                
                abilities.addBuff(state, {
                    id = "volt_speed",
                    timer = 10 * dur,
                    onApply = function(s)
                        s.player.speedBuffActive = true
                        s.player.stats.moveSpeed = (s.player.stats.moveSpeed or 170) * speedMult
                        s.player.stats.attackSpeedMult = (s.player.stats.attackSpeedMult or 1.0) * atkSpeedMult
                    end,
                    onExpire = function(s)
                        s.player.speedBuffActive = false
                        s.player.stats.moveSpeed = (s.player.stats.moveSpeed or 170) / speedMult
                        s.player.stats.attackSpeedMult = (s.player.stats.attackSpeedMult or 1.0) / atkSpeedMult
                    end
                })
                
                if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.5) end
                if state.texts then 
                    table.insert(state.texts, {
                        x = p.x, y = p.y - 50, 
                        text = string.format("极速! +%d%%", math.floor(0.5 * str * 100)), 
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
            castTime = 0.35,  -- Shield deploy
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
            castTime = 0.6,  -- Ultimate charge up
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

-- =============================================================================
-- BUFF SYSTEM
-- =============================================================================

function abilities.addBuff(state, buff)
    local p = state.player
    if not p then return end
    p.buffs = p.buffs or {}
    
    -- If a buff with the same id exists, remove it first (refresh)
    if buff.id then
        for i = #p.buffs, 1, -1 do
            if p.buffs[i].id == buff.id then
                if p.buffs[i].onExpire then p.buffs[i].onExpire(state) end
                table.remove(p.buffs, i)
            end
        end
    end
    
    table.insert(p.buffs, buff)
    if buff.onApply then buff.onApply(state) end
end

function abilities.updateBuffs(state, dt)
    local p = state.player
    if not p or not p.buffs then return end
    
    for i = #p.buffs, 1, -1 do
        local b = p.buffs[i]
        b.timer = b.timer - dt
        if b.timer <= 0 then
            if b.onExpire then b.onExpire(state) end
            table.remove(p.buffs, i)
        end
    end
end

function abilities.removeBuff(state, id)
    local p = state.player
    if not p or not p.buffs then return end
    for i = #p.buffs, 1, -1 do
        if p.buffs[i].id == id then
            if p.buffs[i].onExpire then p.buffs[i].onExpire(state) end
            table.remove(p.buffs, i)
        end
    end
end


-- Get ability definition by index (1-4) for current player class
function abilities.getAbilityByIndex(state, index)
    local p = state.player
    if not p then return nil end
    
    local className = p.class or 'warrior'
    local classAbilities = abilities.catalog[className]
    if not classAbilities then return nil end
    
    return classAbilities[index]
end

-- Check if ability can be used (abilityIndex is 1, 2, 3, or 4)
function abilities.canUse(state, abilityIndex)
    local p = state.player
    if not p then return false end
    
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    -- Cannot use during casting animation
    if p.isCasting then return false end
    
    -- Check energy (with efficiency preview)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    if (p.energy or 0) < cost then return false end
    
    -- WF-style: Most abilities have NO cooldown, only energy limits
    -- Only check CD if explicitly set (rare cases like Helminth abilities)
    if def.cd and def.cd > 0 then
        p.abilityCooldowns = p.abilityCooldowns or {}
        if (p.abilityCooldowns[abilityIndex] or 0) > 0 then return false end
    end
    
    return true
end

-- Get cast time for an ability (affected by Natural Talent)
function abilities.getCastTime(state, def)
    local p = state.player
    if not def then return 0 end
    
    local baseCast = def.castTime or 0
    if baseCast <= 0 then return 0 end  -- Instant cast
    
    -- Natural Talent effect: reduce cast time
    local castSpeedMult = (p.stats and p.stats.castSpeed) or 1.0
    return baseCast / castSpeedMult
end

-- Try to activate ability (WF-style: no CD, with cast time)
-- abilityIndex is 1, 2, 3, or 4
function abilities.tryActivate(state, abilityIndex)
    if not abilities.canUse(state, abilityIndex) then return false end
    
    local p = state.player
    local def = abilities.getAbilityByIndex(state, abilityIndex)
    if not def then return false end
    
    -- Consume energy (Efficiency reduces cost)
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    p.energy = (p.energy or 0) - cost
    
    -- Get cast time
    local castTime = abilities.getCastTime(state, def)
    
    if castTime > 0 then
        -- Start casting animation
        p.isCasting = true
        p.castTimer = castTime
        p.castDef = def
        p.castAbilityIndex = abilityIndex
        p.castProgress = 0
        
        -- Store original speed for slowing during cast
        if not p.castOriginalSpeed then
            p.castOriginalSpeed = p.stats.moveSpeed or 170
        end
        
        -- Slow movement during cast (50% speed)
        p.stats.moveSpeed = p.castOriginalSpeed * 0.5
        
        -- Visual feedback: casting started
        if state.texts then
            table.insert(state.texts, {
                x = p.x, y = p.y - 40, 
                text = "施法中...", 
                color = {0.6, 0.8, 1, 0.8}, 
                life = castTime,
                scale = 0.8
            })
        end
        
        return true  -- Cast started
    else
        -- Instant cast: execute immediately
        local success = def.effect(state)
        
        -- Set CD only if explicitly defined (WF-style: most have none)
        if def.cd and def.cd > 0 then
            p.abilityCooldowns = p.abilityCooldowns or {}
            p.abilityCooldowns[abilityIndex] = def.cd
        end
        
        return success
    end
end

-- Interrupt casting (called when stunned, knocked down, etc.)
function abilities.interruptCast(state, reason)
    local p = state.player
    if not p or not p.isCasting then return false end
    
    -- Refund partial energy (50% if interrupted)
    if p.castDef then
        local eff = p.stats and p.stats.abilityEfficiency or 1.0
        local cost = math.floor(p.castDef.cost / eff)
        local refund = math.floor(cost * 0.5)
        p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + refund)
    end
    
    -- Restore movement speed
    if p.castOriginalSpeed then
        p.stats.moveSpeed = p.castOriginalSpeed
        p.castOriginalSpeed = nil
    end
    
    -- Visual feedback
    if state.texts then
        table.insert(state.texts, {
            x = p.x, y = p.y - 30, 
            text = reason or "施法被打断!", 
            color = {1, 0.4, 0.4}, 
            life = 0.8
        })
    end
    
    -- Clear casting state
    p.isCasting = false
    p.castTimer = nil
    p.castDef = nil
    p.castAbilityIndex = nil
    p.castProgress = nil
    
    return true
end

-- Get ability index for keyboard input (1, 2, 3, 4)
function abilities.getAbilityForKey(key)
    local keyMap = {
        ['1'] = 1,
        ['2'] = 2,
        ['3'] = 3,
        ['4'] = 4
    }
    return keyMap[key]
end


-- Alias for backward compatibility (used by HUD)
abilities.getAbilityDef = abilities.getAbilityByIndex

-- Update casting, cooldowns and energy regen
function abilities.update(state, dt)
    local p = state.player
    if not p then return end
    
    -- Apply passive on first frame if not applied
    if not p.passiveApplied then
        abilities.applyPassive(state)
    end
    
    -- Buffs and Active Effects
    abilities.updateBuffs(state, dt)
    abilities.updateActiveEffects(state, dt)
    
    -- Apply warframe MODs on first frame if not applied
    if not p.warframeModsApplied then
        local mods = require('mods')
        local slots = mods.getSlots(state, 'warframe', nil)
        local hasModsEquipped = false
        for _, m in ipairs(slots) do if m then hasModsEquipped = true break end end
        
        if hasModsEquipped then
            p.stats = p.stats or {}
            local modded = mods.applyWarframeMods(state, p.stats)
            for k, v in pairs(modded) do
                p.stats[k] = v
            end
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
    
    -- === CASTING SYSTEM ===
    if p.isCasting and p.castTimer then
        p.castTimer = p.castTimer - dt
        local totalCast = abilities.getCastTime(state, p.castDef)
        p.castProgress = totalCast > 0 and (1 - (p.castTimer / totalCast)) or 1
        
        local interrupted = (p.stunTimer and p.stunTimer > 0) or (p.knockdownTimer and p.knockdownTimer > 0) or (p.frozenTimer and p.frozenTimer > 0)
        if interrupted then
            abilities.interruptCast(state, "被控制打断!")
        elseif p.castTimer <= 0 then
            if p.castDef and p.castDef.effect then p.castDef.effect(state) end
            if p.castDef and p.castDef.cd and p.castDef.cd > 0 then
                p.abilityCooldowns = p.abilityCooldowns or {}
                p.abilityCooldowns[p.castAbilityIndex] = p.castDef.cd
            end
            if p.castOriginalSpeed then
                p.stats.moveSpeed = p.castOriginalSpeed
                p.castOriginalSpeed = nil
            end
            p.isCasting, p.castTimer, p.castDef, p.castAbilityKey, p.castProgress = false, nil, nil, nil, nil
        end
    end
    
    -- Energy regen
    local regen = (p.stats and p.stats.energyRegen) or p.energyRegen or 2
    if p.isCasting then regen = regen * 0.5 end
    p.energy = math.min(p.maxEnergy or 100, (p.energy or 0) + regen * dt)
    
    -- Cooldown tick
    p.abilityCooldowns = p.abilityCooldowns or {}
    for key, cd in pairs(p.abilityCooldowns) do
        if cd > 0 then p.abilityCooldowns[key] = cd - dt end
    end
    
    -- Temp shield decay
    if p.tempShieldTimer and p.tempShieldTimer > 0 then
        p.tempShieldTimer = p.tempShieldTimer - dt
        if p.tempShieldTimer <= 0 then p.tempShield, p.tempShieldTimer = 0, nil end
    end
end

-- Unified function for persistent ability updates (Volt chains, WoF, Exalted Blade drain, etc.)
function abilities.updateActiveEffects(state, dt)
    local p = state.player
    if not p then return end
    
    -- 1. Volt Lightning VFX
    if state.voltLightningChains then
        for i = #state.voltLightningChains, 1, -1 do
            local c = state.voltLightningChains[i]
            c.timer = c.timer - dt
            c.alpha = math.max(0, c.timer / 0.5)
            if c.timer <= 0 then table.remove(state.voltLightningChains, i) end
        end
    end
    
    -- 2. Mage: World on Fire (Channeling/Timer)
    if p.wofRunning then
        p.energy = (p.energy or 0) - 2.5 * dt
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "mage_world_on_fire")
        else
            p.wofPulseTimer = (p.wofPulseTimer or 0) + dt
            if p.wofPulseTimer >= 0.4 then
                p.wofPulseTimer = 0
                local str = p.stats.abilityStrength or 1.0
                local rng = p.stats.abilityRange or 1.0
                local radius = 250 * rng
                local ok, calc = pcall(require, 'calculator')
                if ok and calc then
                    local inst = calc.createInstance({damage=math.floor(30*str), elements={'HEAT'}, weaponTags={'ability','fire'}})
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                calc.applyHit(state, e, inst)
                                if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.6) end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if p.exaltedBladeActive then
        p.energy = (p.energy or 0) - 2.5 * dt -- Energy drain
        if p.energy <= 0 then
            p.energy = 0
            abilities.removeBuff(state, "warrior_exalted_blade")
            if state.texts then table.insert(state.texts, {x=p.x, y=p.y-30, text="能量竭尽", color={1,0,0}, life=1}) end
        end
    end
    
    
    if p.electricShield and p.electricShield.active then
        p.electricShield.timer = p.electricShield.timer - dt
        if p.electricShield.timer <= 0 then 
            p.electricShield.active = false
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-30, text="电盾消散", color={0.6,0.6,0.8}, life=1})
            end
        elseif p.electricShield.followPlayer then
            local ang = p.aimAngle or 0
            local dst = p.electricShield.distance or 60
            p.electricShield.x, p.electricShield.y, p.electricShield.angle = p.x + math.cos(ang)*dst, p.y + math.sin(ang)*dst, ang
        end
    end

    -- 5. Volt: Discharge & Tesla Nodes
    if p.dischargeWave and p.dischargeWave.active then
        local wave = p.dischargeWave
        wave.timer = wave.timer - dt
        
        local oldRadius = wave.currentRadius
        wave.currentRadius = wave.currentRadius + wave.expandSpeed * dt
        local effNew = math.min(wave.currentRadius, wave.maxRadius)
        local effOld = math.min(oldRadius, wave.maxRadius)
        
        if effOld < wave.maxRadius then
            local ok, calc = pcall(require, 'calculator')
            for _, e in ipairs(state.enemies or {}) do
                if e and not e.isDummy and not wave.hitEnemies[e] then
                    local dx, dy = e.x - wave.x, e.y - wave.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= effNew and dist >= effOld then
                        wave.hitEnemies[e] = true
                        if ok and calc then
                            local inst = calc.createInstance({
                                damage = wave.damage,
                                critChance = 0.2, critMultiplier = 2.5, statusChance = 1.0,
                                elements = {'ELECTRIC'}, weaponTags = {'ability', 'area', 'electric'}
                            })
                            calc.applyHit(state, e, inst)
                        else
                            e.health = (e.health or 0) - wave.damage
                        end
                        e.frozenTimer = wave.stunDuration
                        e.teslaNode = {
                            active = true,
                            timer = wave.teslaNodeDuration or wave.stunDuration,
                            dps = wave.teslaNodeDPS or 15,
                            range = wave.teslaNodeRange or 120,
                            damageTickTimer = 0
                        }
                        if state.spawnEffect then state.spawnEffect('shock', e.x, e.y, 1.0) end
                    end
                end
            end
        end
        if wave.timer <= 0 then p.dischargeWave = nil end
    end

    -- Discharge Wave VFX update
    if state.voltDischargeWaves then
        for i = #state.voltDischargeWaves, 1, -1 do
            local w = state.voltDischargeWaves[i]
            w.timer = w.timer - dt
            if w.currentRadius < w.maxRadius then
                w.currentRadius = math.min(w.maxRadius, w.currentRadius + w.expandSpeed * dt)
            end
            w.alpha = math.max(0, w.timer * 2)
            if w.timer <= 0 then table.remove(state.voltDischargeWaves, i) end
        end
    end

    -- Tesla Node Network
    local nodes = {}
    for _, e in ipairs(state.enemies or {}) do
        if e and e.teslaNode and e.teslaNode.active then table.insert(nodes, e) end
    end
    if #nodes > 0 then
        local ok, calc = pcall(require, 'calculator')
        state.teslaArcs = {}
        for i, e1 in ipairs(nodes) do
            local n1 = e1.teslaNode
            n1.timer = n1.timer - dt
            n1.damageTickTimer = n1.damageTickTimer + dt
            if n1.timer <= 0 then
                n1.active = false
                e1.teslaNode = nil
            else
                local r2 = n1.range * n1.range
                for j = i + 1, #nodes do
                    local e2 = nodes[j]
                    if e2.teslaNode and e2.teslaNode.active then
                        local d2 = (e2.x-e1.x)^2 + (e2.y-e1.y)^2
                        if d2 <= r2 then
                            table.insert(state.teslaArcs, {x1=e1.x, y1=e1.y, x2=e2.x, y2=e2.y, alpha=0.7 + 0.3*math.sin(love.timer.getTime()*10)})
                            if n1.damageTickTimer >= 0.5 then
                                local dmg = math.floor(n1.dps * 0.5)
                                if ok and calc then
                                    local inst = calc.createInstance({damage=dmg, statusChance=0.5, elements={'ELECTRIC'}, weaponTags={'ability','electric','tesla'}})
                                    calc.applyHit(state, e1, inst); calc.applyHit(state, e2, inst)
                                else
                                    e1.health = (e1.health or 0) - dmg
                                    e2.health = (e2.health or 0) - dmg
                                end
                            end
                        end
                    end
                end
                if n1.damageTickTimer >= 0.5 then n1.damageTickTimer = 0 end
                if e1.frozenTimer and e1.frozenTimer < 0.2 then e1.frozenTimer = 0.2 end
            end
        end
    end
end


return abilities
