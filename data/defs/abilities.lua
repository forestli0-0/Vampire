local function build(helpers)
    local addBuff = helpers.addBuff

    local function findMagnetizeDetonateTarget(state, maxR2)
        local p = state.player
        if not p or not state.enemies then return nil end
        local best, bestD2 = nil, math.huge
        for _, e in ipairs(state.enemies) do
            if e and e.magnetize and e.magnetize.timer and e.magnetize.timer > 0 then
                local dx, dy = e.x - p.x, e.y - p.y
                local d2 = dx * dx + dy * dy
                if d2 < bestD2 and d2 < (maxR2 or math.huge) then
                    bestD2 = d2
                    best = e
                end
            end
        end
        return best
    end

    local catalog = {
        excalibur = {
            {
                name = "斩击突进", -- Slash Dash
                cost = 25,
                castTime = 0,  -- Instant (dash ability)
                effect = function(state)
                    local p = state.player
                    local playerMod = require('gameplay.player')
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local baseDamage = math.floor(50 * str)
                    local chainRange = 200 * rng
                    local chainRange2 = chainRange * chainRange
                    local maxHits = math.max(1, math.floor(3 + 2 * rng))
                    local ok, calc = pcall(require, 'gameplay.calculator')
                    local enemies = state.enemies or {}
                    local targets = {}
                    local hit = {}
                    local cx, cy = p.x, p.y

                    for _ = 1, maxHits do
                        local best, bestD2 = nil, math.huge
                        for _, e in ipairs(enemies) do
                            if e and not e.isDummy and (e.health or 0) > 0 and not hit[e] then
                                local dx, dy = e.x - cx, e.y - cy
                                local d2 = dx*dx + dy*dy
                                if d2 < chainRange2 and d2 < bestD2 then
                                    best = e
                                    bestD2 = d2
                                end
                            end
                        end
                        if not best then break end
                        table.insert(targets, best)
                        hit[best] = true
                        cx, cy = best.x, best.y
                    end
                
                    p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5 + 0.05 * #targets)

                    if #targets == 0 then
                        local ang = p.aimAngle or 0
                        playerMod.tryDash(state, math.cos(ang), math.sin(ang))
                        local radius = 80 * rng
                        local r2 = radius * radius
                        if ok and calc then
                            local instance = calc.createInstance({
                                damage = baseDamage,
                                critChance = 0.15,
                                critMultiplier = 2.0,
                                statusChance = 0.40,
                                elements = {'SLASH'},
                                damageBreakdown = {SLASH = 1},
                                weaponTags = {'ability', 'melee'}
                            })
                            for _, e in ipairs(enemies) do
                                if e and not e.isDummy then
                                    local dx, dy = e.x - p.x, e.y - p.y
                                    if dx*dx + dy*dy < r2 then
                                        calc.applyHit(state, e, instance)
                                        if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.5) end
                                    end
                                end
                            end
                        end
                    else
                        local instance = nil
                        if ok and calc then
                            instance = calc.createInstance({
                                damage = baseDamage,
                                critChance = 0.15,
                                critMultiplier = 2.0,
                                statusChance = 0.40,
                                elements = {'SLASH'},
                                damageBreakdown = {SLASH = 1},
                                weaponTags = {'ability', 'melee'}
                            })
                        end
                        p.slashDashChain = {
                            active = true,
                            targets = targets,
                            index = 1,
                            speed = 520,
                            pause = 0.06,
                            hitRadius = 18,
                            maxStepTime = 0.55,
                            damage = baseDamage,
                            instance = instance,
                            trailX = p.x,
                            trailY = p.y,
                            lastDx = 0,
                            lastDy = 0
                        }
                        local est = #targets * ((p.slashDashChain.maxStepTime or 0) + (p.slashDashChain.pause or 0))
                        p.invincibleTimer = math.max(p.invincibleTimer or 0, est)
                    end
                    if state.playSfx then state.playSfx('static') end
                    return true
                end
            },
            {
                name = "致盲闪光", -- Radial Blind
                cost = 50,
                castTime = 0.3,
                effect = function(state)
                    local p = state.player
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local radius = 240 * rng
                    local blindTime = 4.0 * dur
                
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local dx, dy = e.x - p.x, e.y - p.y
                            if dx*dx + dy*dy < radius*radius then
                                e.status = e.status or {}
                                e.status.impactTimer = math.max(e.status.impactTimer or 0, blindTime)
                            end
                        end
                    end
                
                    if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.5) end
                    if state.playSfx then state.playSfx('hit') end
                    return true
                end
            },
            {
                name = "辐射标枪", -- Radial Javelin
                cost = 75,
                castTime = 0.5,
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local radius = 260 * rng
                    local damage = math.floor(80 * str)
                    local ok, calc = pcall(require, 'gameplay.calculator')
                    if ok and calc then
                        local inst = calc.createInstance({
                            damage = damage,
                            critChance = 0.1,
                            critMultiplier = 2.0,
                            statusChance = 0.5,
                            elements = {'PUNCTURE'},
                            damageBreakdown = {PUNCTURE = 1},
                            weaponTags = {'ability', 'area', 'physical'}
                        })
                        for _, e in ipairs(state.enemies or {}) do
                            if e and not e.isDummy then
                                local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                                if d2 < radius*radius then
                                    calc.applyHit(state, e, inst)
                                    if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 0.8) end
                                end
                            end
                        end
                    end
                    if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 2.0) end
                    return true
                end
            },
            {
                name = "显赫之剑", -- Exalted Blade
                cost = 100,
                castTime = 0.8,
                toggleId = "excalibur_exalted_blade",
                effect = function(state)
                    local p = state.player
                    if p.exaltedBladeActive then return false end
                
                    local str = p.stats.abilityStrength or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                    local dmgBonus = 1.0 * str
                    local speedBonus = 1.5
                
                    addBuff(state, {
                        id = "excalibur_exalted_blade",
                        timer = 20 * dur,
                        onApply = function(s)
                            local inv = s.inventory
                            s.player.exaltedBladeActive = true
                            s.player.exaltedBladeDamageMult = 1 + dmgBonus
                            s.player.exaltedBladeSpeedMult = speedBonus
                            if inv and inv.weaponSlots and inv.weaponSlots.melee then
                                s.player.exaltedBladePrevSlot = inv.activeSlot or 'ranged'
                                inv.activeSlot = 'melee'
                                s.player.activeSlot = 'melee'
                            end
                        end,
                        onExpire = function(s)
                            local inv = s.inventory
                            s.player.exaltedBladeActive = false
                            s.player.exaltedBladeDamageMult = nil
                            s.player.exaltedBladeSpeedMult = nil
                            if inv and s.player.exaltedBladePrevSlot and inv.weaponSlots and inv.weaponSlots[s.player.exaltedBladePrevSlot] then
                                inv.activeSlot = s.player.exaltedBladePrevSlot
                                s.player.activeSlot = s.player.exaltedBladePrevSlot
                            end
                            s.player.exaltedBladePrevSlot = nil
                        end
                    })
                
                    if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 4.0) end
                    return true
                end
            }
        },
        mag = {
            {
                name = "牵引", -- Pull
                cost = 25,
                castTime = 0.2,
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local radius = 260 * rng
                    local pullDist = 140 * rng
                    local stunTime = 0.6 * dur
                
                    local ok, calc = pcall(require, 'gameplay.calculator')
                    local inst = nil
                    if ok and calc then
                        inst = calc.createInstance({
                            damage = math.floor(30 * str),
                            critChance = 0.1,
                            critMultiplier = 1.8,
                            statusChance = 0.6,
                            elements = {'MAGNETIC'},
                            damageBreakdown = {MAGNETIC = 1},
                            weaponTags = {'ability', 'magnetic'}
                        })
                    end
                
                    local hitAny = false
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local dx, dy = p.x - e.x, p.y - e.y
                            local d2 = dx*dx + dy*dy
                            if d2 < radius*radius then
                                hitAny = true
                                local len = math.sqrt(d2)
                                if len > 0.1 then
                                    local step = math.min(pullDist, math.max(0, len - 20))
                                    local mx = dx / len * step
                                    local my = dy / len * step
                                    if state.world and state.world.moveCircle then
                                        e.x, e.y = state.world:moveCircle(e.x, e.y, (e.size or 16) / 2, mx, my)
                                    else
                                        e.x = e.x + mx
                                        e.y = e.y + my
                                    end
                                end
                                e.status = e.status or {}
                                e.status.impactTimer = math.max(e.status.impactTimer or 0, stunTime)
                                if inst and ok and calc then
                                    calc.applyHit(state, e, inst)
                                else
                                    e.health = (e.health or 0) - math.floor(30 * str)
                                end
                                if state.spawnEffect then state.spawnEffect('static', e.x, e.y, 0.6) end
                            end
                        end
                    end
                
                    if state.playSfx then state.playSfx('shoot') end
                    return hitAny
                end
            },
            {
                name = "磁化球", -- Magnetize
                cost = 50,
                castTime = 0.35,
                recastNoCost = true,
                recastCheck = function(state)
                    local p = state.player
                    local rng = p.stats.abilityRange or 1.0
                    local maxRange = 420 * rng
                    return findMagnetizeDetonateTarget(state, maxRange * maxRange)
                end,
                recastAction = function(state, target)
                    local abilities = require('gameplay.abilities')
                    return abilities.detonateMagnetize(state, target, 'recast')
                end,
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local maxRange = 420 * rng
                    local maxR2 = maxRange * maxRange
                    local target, best = nil, math.huge
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy and e.health and e.health > 0 then
                            local dx, dy = e.x - p.x, e.y - p.y
                            local d2 = dx*dx + dy*dy
                            if d2 < best and d2 < maxR2 then
                                best = d2
                                target = e
                            end
                        end
                    end
                
                    if not target then return false end
                
                    target.magnetize = {
                        timer = 8 * dur,
                        radius = 140 * rng,
                        dps = 20 * str,
                        pullStrength = 160 * rng,
                        tick = 0,
                        storedDamage = 0,
                        absorbMult = 1.0,
                        explosionMult = 1.0 + 0.5 * str
                    }
                
                    if state.spawnEffect then state.spawnEffect('static', target.x, target.y, 1.0) end
                    if state.texts then table.insert(state.texts, {x=target.x, y=target.y-40, text="MAGNETIZE", color={0.7, 0.5, 1}, life=1.2}) end
                    return true
                end
            },
            {
                name = "极化", -- Polarize
                cost = 75,
                castTime = 0.4,
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local radius = 300 * rng
                    local damage = math.floor(45 * str)
                    local debuffTime = 6.0 * dur
                    local ok, calc = pcall(require, 'gameplay.calculator')
                    local enemies = require('gameplay.enemies')
                    local inst = nil
                    if ok and calc then
                        inst = calc.createInstance({
                            damage = damage,
                            critChance = 0.1,
                            critMultiplier = 2.0,
                            statusChance = 0.7,
                            elements = {'MAGNETIC'},
                            damageBreakdown = {MAGNETIC = 1},
                            weaponTags = {'ability', 'area', 'magnetic'}
                        })
                    end
                
                    local hitCount = 0
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                hitCount = hitCount + 1
                                if inst and ok and calc then
                                    calc.applyHit(state, e, inst)
                                else
                                    e.health = (e.health or 0) - damage
                                end
                                enemies.applyStatus(state, e, 'MAGNETIC', damage, nil, {duration = debuffTime})
                                enemies.applyStatus(state, e, 'MAGNETIC', damage, nil, {duration = debuffTime})
                                if state.spawnEffect then state.spawnEffect('static', e.x, e.y, 0.5) end
                            end
                        end
                    end
                
                    if hitCount > 0 then
                        local maxShield = p.maxShield or (p.stats and p.stats.maxShield) or 0
                        if maxShield > 0 then
                            local restore = math.floor(8 * str) * hitCount
                            p.shield = math.min(maxShield, (p.shield or 0) + restore)
                        end
                    end
                
                    if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.8) end
                    return hitCount > 0
                end
            },
            {
                name = "碾压", -- Crush
                cost = 100,
                castTime = 0.6,
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local rng = p.stats.abilityRange or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local radius = 280 * rng
                    local damage = math.floor(70 * str)
                    local stunTime = 2.5 * dur
                    local ok, calc = pcall(require, 'gameplay.calculator')
                    local inst = nil
                    if ok and calc then
                        inst = calc.createInstance({
                            damage = damage,
                            critChance = 0.2,
                            critMultiplier = 2.2,
                            statusChance = 0.6,
                            elements = {'MAGNETIC'},
                            damageBreakdown = {MAGNETIC = 1},
                            weaponTags = {'ability', 'area', 'magnetic'}
                        })
                    end
                
                    for _, e in ipairs(state.enemies or {}) do
                        if e and not e.isDummy then
                            local d2 = (e.x-p.x)^2 + (e.y-p.y)^2
                            if d2 < radius*radius then
                                e.status = e.status or {}
                                e.status.impactTimer = math.max(e.status.impactTimer or 0, stunTime)
                                if inst and ok and calc then
                                    calc.applyHit(state, e, inst)
                                else
                                    e.health = (e.health or 0) - damage
                                end
                                if state.spawnEffect then state.spawnEffect('static', e.x, e.y, 0.8) end
                            end
                        end
                    end
                
                    if state.playSfx then state.playSfx('hit') end
                    if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 2.2) end
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
                
                    local ok, calc = pcall(require, 'gameplay.calculator')
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
                
                    if state.playSfx then state.playSfx('static') end
                    return true
                end
            },
            {
                name = "极速", -- Speed (TEMPORARY buff!)
                cost = 50,
                castTime = 0,  -- Instant cast
                effect = function(state)
                    local p = state.player
                    local str = p.stats.abilityStrength or 1.0
                    local dur = p.stats.abilityDuration or 1.0
                
                    local speedMult = 1 + (0.50 * str)
                    local atkSpeedMult = 1 + (0.30 * str)
                
                    addBuff(state, {
                        id = "volt_speed",
                        timer = 10 * dur,
                        onApply = function(s)
                            s.player.speedBuffActive = true
                            s.player.moveSpeedBuffMult = (s.player.moveSpeedBuffMult or 1) * speedMult
                            s.player.attackSpeedBuffMult = (s.player.attackSpeedBuffMult or 1) * atkSpeedMult
                            s.player.speedAuraRadius = 90 * (s.player.stats.abilityRange or 1.0)
                        end,
                        onExpire = function(s)
                            s.player.speedBuffActive = false
                            s.player.moveSpeedBuffMult = (s.player.moveSpeedBuffMult or 1) / speedMult
                            s.player.attackSpeedBuffMult = (s.player.attackSpeedBuffMult or 1) / atkSpeedMult
                            s.player.speedAuraRadius = nil
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

    local passives = {
        excalibur = {
            name = "剑术大师",
            desc = "近战伤害+15%, 近战速度+10%",
            icon = "⚔️",
            apply = function(state)
                local p = state.player
                if not p or not p.stats then return end
                p.stats.meleeDamageMult = (p.stats.meleeDamageMult or 1) + 0.15
                p.stats.meleeSpeed = (p.stats.meleeSpeed or 1) * 1.10
            end
        },
        mag = {
            name = "磁能掌控",
            desc = "技能范围+15%, 技能效率+10%",
            icon = "🧲",
            apply = function(state)
                local p = state.player
                if not p or not p.stats then return end
                p.stats.abilityRange = (p.stats.abilityRange or 1.0) * 1.15
                p.stats.abilityEfficiency = (p.stats.abilityEfficiency or 1.0) * 1.10
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

    return { catalog = catalog, passives = passives }
end

return { build = build }
