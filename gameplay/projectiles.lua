local util = require('core.util')
local enemies = require('gameplay.enemies')
local player = require('gameplay.player')
local pets = require('gameplay.pets')
local calculator = require('gameplay.calculator')

local projectiles = {}

local function findNearestEnemyAt(state, x, y, maxDist, exclude)
    local best = nil
    local bestD2 = (maxDist or 999999) ^ 2
    local world = state and state.world
    local useLos = world and world.enabled and world.segmentHitsWall
    for _, e in ipairs(state.enemies or {}) do
        if e and (e.health or e.hp or 0) > 0 then
            if not (exclude and exclude[e]) then
                local dx = (e.x or 0) - x
                local dy = (e.y or 0) - y
                local d2 = dx * dx + dy * dy
                if d2 < bestD2 then
                    if not (useLos and world:segmentHitsWall(x, y, e.x, e.y)) then
                        bestD2 = d2
                        best = e
                    end
                end
            end
        end
    end
    return best
end

local function steerBullet(b, tx, ty, turnRate, dt)
    if not b or not b.vx or not b.vy then return end
    local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if spd <= 0 then return end
    local curr = math.atan2(b.vy, b.vx)
    local desired = math.atan2((ty or b.y) - b.y, (tx or b.x) - b.x)
    local diff = (desired - curr + math.pi) % (math.pi * 2) - math.pi
    local maxTurn = (turnRate or 0) * (dt or 0)
    if maxTurn <= 0 then return end
    if diff > maxTurn then diff = maxTurn end
    if diff < -maxTurn then diff = -maxTurn end
    local ang = curr + diff
    b.vx = math.cos(ang) * spd
    b.vy = math.sin(ang) * spd
end

local function updateBulletGuidance(state, b, dt)
    if not b or not b.vx or not b.vy then return end
    if b.type == 'absolute_zero' or b.type == 'death_spiral' or b.type == 'axe' then return end

    if b.boomerangTimer ~= nil then
        b.boomerangTimer = (b.boomerangTimer or 0) - dt
        if b.boomerangTimer <= 0 and not b.returnToPlayer then
            b.returnToPlayer = true
            b.hitTargets = nil -- allow a second pass to hit again
            b._homeTarget = nil
        end
    end

    if b.returnToPlayer then
        steerBullet(b, state.player.x, state.player.y, b.returnHoming or 12, dt)
        return
    end

    if b.homing and b.homing > 0 then
        b._homeTimer = (b._homeTimer or 0) - dt
        local target = b._homeTarget
        if b._homeTimer <= 0 or not (target and (target.health or target.hp or 0) > 0) then
            b._homeTimer = 0.12
            target = findNearestEnemyAt(state, b.x, b.y, b.homingRange or 650, b.hitTargets)
            b._homeTarget = target
        end
        if target then
            steerBullet(b, target.x, target.y, b.homing, dt)
        end
    end
end

local function tryRicochet(state, b, fromX, fromY)
    if not b or not b.vx or not b.vy then return false end
    local remaining = b.ricochetRemaining or 0
    if remaining <= 0 then return false end
    local target = findNearestEnemyAt(state, fromX or b.x, fromY or b.y, b.ricochetRange or 420, b.hitTargets)
    if not target then return false end

    b.ricochetRemaining = remaining - 1
    local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if spd <= 0 then return true end
    local ang = math.atan2(target.y - (fromY or b.y), target.x - (fromX or b.x))
    b.vx = math.cos(ang) * spd
    b.vy = math.sin(ang) * spd
    b.rotation = ang
    return true
end


local function buildInstanceFromBullet(bullet, enemy, effectData, knock, knockForce)
    -- Calculate distance from bullet spawn to enemy
    local distance = nil
    if bullet and enemy and bullet.spawnX and bullet.spawnY then
        local dx = enemy.x - bullet.spawnX
        local dy = enemy.y - bullet.spawnY
        distance = math.sqrt(dx * dx + dy * dy)
    end
    
    -- Get base damage, potentially boosted by electric shield
    local damage = bullet.damage or 0
    local elements = bullet.elements
    local damageBreakdown = bullet.damageBreakdown
    
    -- Check if bullet has passed through electric shield (damage boost)
    if bullet.shieldBoosted then
        local bonus = bullet.shieldDamageBonus or 0.5
        damage = math.floor(damage * (1 + bonus))
        -- Add ELECTRIC element if not already present
        if elements then
            local hasElectric = false
            for _, e in ipairs(elements) do
                if e == 'ELECTRIC' then hasElectric = true break end
            end
            if not hasElectric then
                local newElements = {}
                for _, e in ipairs(elements) do table.insert(newElements, e) end
                table.insert(newElements, 'ELECTRIC')
                elements = newElements
            end
        else
            elements = {'ELECTRIC'}
        end
        -- Add electric to damage breakdown
        if damageBreakdown then
            local newBreakdown = {}
            for k, v in pairs(damageBreakdown) do newBreakdown[k] = v end
            newBreakdown.ELECTRIC = (newBreakdown.ELECTRIC or 0) + bonus
            damageBreakdown = newBreakdown
        end
    end
    
    return calculator.createInstance({
        damage = damage,
        critChance = bullet.critChance or 0,
        critMultiplier = bullet.critMultiplier or 1.5,
        statusChance = bullet.statusChance or 0,
        effectType = bullet.effectType,
        effectData = effectData,
        elements = elements,
        damageBreakdown = damageBreakdown,
        weaponTags = bullet.weaponTags,
        knock = knock,
        knockForce = knockForce,
        -- Falloff parameters
        distance = distance,
        falloffStart = bullet.falloffStart,
        falloffEnd = bullet.falloffEnd,
        falloffMin = bullet.falloffMin
    })
end

-- Check if bullet passes through electric shield arc
local function checkShieldBoost(state, bullet, ox, oy, nx, ny)
    local p = state.player
    if not p or not p.electricShield or not p.electricShield.active then return end
    if bullet.shieldBoosted then return end  -- Already boosted
    
    local shield = p.electricShield
    local arcRadius = shield.distance or 60
    local arcWidth = shield.arcWidth or 1.2
    local shieldAngle = shield.angle or 0
    
    -- Check if the bullet path crosses the arc
    -- Simplified: check if new position is at arc radius and within angle
    local dx = nx - p.x
    local dy = ny - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Check if crossing the arc radius (from inside to outside or vice versa)
    local odx = ox - p.x
    local ody = oy - p.y
    local oldDist = math.sqrt(odx * odx + ody * ody)
    
    local tolerance = 15
    local crossingArc = (oldDist < arcRadius - tolerance and dist >= arcRadius - tolerance) or
                        (oldDist <= arcRadius + tolerance and dist > arcRadius + tolerance)
    
    if crossingArc or (math.abs(dist - arcRadius) < tolerance) then
        -- Check if within arc angle
        local bulletAngle = math.atan2(dy, dx)
        local angleDiff = (bulletAngle - shieldAngle + math.pi) % (math.pi * 2) - math.pi
        
        if math.abs(angleDiff) <= arcWidth / 2 then
            -- Bullet passes through shield - apply boost!
            bullet.shieldBoosted = true
            bullet.shieldDamageBonus = shield.damageBonus or 0.5
            
            -- Visual feedback
            if state.spawnEffect then
                state.spawnEffect('shock', nx, ny, 0.4)
            end
        end
    end
end

local function applyProjectileHit(state, enemy, bullet, effectData, knock, knockForce)
    local instance = buildInstanceFromBullet(bullet, enemy, effectData, knock, knockForce)
    return calculator.applyHit(state, enemy, instance)
end

local function addMagnetizeStoredDamage(enemy, result, bullet)
    local m = enemy and enemy.magnetize
    if not m then return end
    local base = 0
    if result and result.damage and result.damage > 0 then
        base = result.damage
    elseif bullet and bullet.damage then
        base = bullet.damage
    end
    if base > 0 then
        local mult = m.absorbMult or 1
        m.storedDamage = (m.storedDamage or 0) + math.floor(base * mult)
    end
end

function projectiles.updatePlayerBullets(state, dt)
    local magnetizeTargets = nil
    if state.enemies then
        for _, e in ipairs(state.enemies) do
            local m = e and e.magnetize
            if m and m.timer and m.timer > 0 and m.radius and m.radius > 0 then
                magnetizeTargets = magnetizeTargets or {}
                table.insert(magnetizeTargets, {enemy = e, data = m})
            end
        end
    end

    for i = #state.bullets, 1, -1 do
        local b = state.bullets[i]
        local handled = false

        if b.type == 'absolute_zero' then
            handled = true
            b.life = b.life - dt
            b.tick = (b.tick or 0) - dt
            if b.tick <= 0 then
                b.tick = 0.35
                local radius = b.radius or (b.size or 0)
                local r2 = radius * radius
                local effectData = {duration = b.effectDuration or 1.2}
                local instance = buildInstanceFromBullet(b, e, effectData)
                for _, e in ipairs(state.enemies) do
                    local dx = e.x - b.x
                    local dy = e.y - b.y
                    if dx*dx + dy*dy <= r2 then
                        calculator.applyHit(state, e, instance)
                    end
                end
            end
            if b.life <= 0 then
                table.remove(state.bullets, i)
            end
        end

        if not handled then
            local ox, oy = b.x, b.y
            updateBulletGuidance(state, b, dt)

            if magnetizeTargets and b.vx and b.vy and not b.noMagnetize and b.type ~= 'absolute_zero' and b.type ~= 'death_spiral' and b.type ~= 'axe' and b.type ~= 'oil_bottle' then
                local bestTarget = nil
                local bestD2 = math.huge
                for _, t in ipairs(magnetizeTargets) do
                    local e = t.enemy
                    local m = t.data
                    if e and m then
                        local dx = e.x - b.x
                        local dy = e.y - b.y
                        local r = m.radius or 0
                        local d2 = dx * dx + dy * dy
                        if r > 0 and d2 <= r * r and d2 < bestD2 then
                            bestD2 = d2
                            bestTarget = e
                        end
                    end
                end
                if bestTarget then
                    local spd = math.sqrt((b.vx or 0) * (b.vx or 0) + (b.vy or 0) * (b.vy or 0))
                    if spd > 0 then
                        local ang = math.atan2(bestTarget.y - b.y, bestTarget.x - b.x)
                        b.vx = math.cos(ang) * spd
                        b.vy = math.sin(ang) * spd
                        b.rotation = ang
                    end
                end
            end
            
            -- Special projectiles with unique movement patterns
            if b.type == 'axe' then
                -- Axe: arcing projectile with gravity
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                b.vy = b.vy + 1000 * dt
                b.rotation = b.rotation + 10 * dt
            elseif b.type == 'death_spiral' then
                -- Death Spiral: spinning radial projectile
                local ang = math.atan2(b.vy, b.vx) + (b.angularVel or 0) * dt
                local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                b.vx = math.cos(ang) * spd
                b.vy = math.sin(ang) * spd
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                b.rotation = (b.rotation or 0) + 8 * dt
            else
                -- Default: linear movement for all other projectiles
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                if b.type ~= 'oil_bottle' then
                    b.rotation = math.atan2(b.vy, b.vx)
                end
            end

            local world = state.world
            if world and world.enabled and world.segmentHitsWall then
                if world:segmentHitsWall(ox, oy, b.x, b.y) then
                    if state.spawnEffect then state.spawnEffect('hit', b.x, b.y, 0.55) end
                    table.remove(state.bullets, i)
                    goto continue_player_bullet
                end
            end
            
            -- Check if bullet passes through Electric Shield (damage boost)
            checkShieldBoost(state, b, ox, oy, b.x, b.y)

            b.life = b.life - dt

            local hit = false
            if b.life <= 0 then
                table.remove(state.bullets, i)
            else
                for j = #state.enemies, 1, -1 do
                    local e = state.enemies[j]
                    -- 跳过正在死亡的敌人，它们不应该阻挡子弹
                    if e.isDying then goto continue_enemy_check end
                    if util.checkCollision(b, e) then
                        -- Special weapon-specific collision handling
                        if b.type == 'oil_bottle' then
                            -- Apply oil to target and splash neighbors, then disappear
                            local effectData
                            if b.effectDuration then effectData = {duration = b.effectDuration} end
                            local instance = buildInstanceFromBullet(b, e, effectData)
                            calculator.applyStatus(state, e, instance)
                            local splash = b.splashRadius or 0
                            if splash > 0 then
                                local splashSq = splash * splash
                                for jj, o in ipairs(state.enemies) do
                                    if jj ~= j then
                                        local dx = o.x - e.x
                                        local dy = o.y - e.y
                                        if dx*dx + dy*dy <= splashSq then
                                            calculator.applyStatus(state, o, instance)
                                        end
                                    end
                                end
                            end

                            -- Ground cover: persistent oil field (visual-only)
                            if state.spawnAreaField then
                                local r = (splash > 0 and splash) or ((b.size or 16) * 4)
                                local dur = (b.effectDuration or 2.0)
                                state.spawnAreaField('oil', e.x, e.y, r, dur, 1)
                            end

                            table.remove(state.bullets, i)
                            hit = true
                            break
                        elseif b.type == 'death_spiral' then
                            -- Death spiral: multi-hit without pierce reduction
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local instance = buildInstanceFromBullet(b, e)
                                local result = calculator.applyHit(state, e, instance)
                                addMagnetizeStoredDamage(e, result, b)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                            end
                        elseif b.type == 'axe' then
                            -- Axe: multi-hit without pierce reduction
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local instance = buildInstanceFromBullet(b, e)
                                local result = calculator.applyHit(state, e, instance)
                                addMagnetizeStoredDamage(e, result, b)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                            end
                        else
                            -- Default collision handling for all other projectiles
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local effectData
                                if b.effectDuration or b.effectRange or b.chain or b.allowRepeat then
                                    effectData = {duration = b.effectDuration, range = b.effectRange, chain = b.chain, allowRepeat = b.allowRepeat}
                                end
                                local instance = buildInstanceFromBullet(b, e, effectData)
                                local result = calculator.applyHit(state, e, instance)
                                addMagnetizeStoredDamage(e, result, b)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                                tryRicochet(state, b, e.x, e.y)
                                
                                -- Special handling for fire weapons with splash
                                if b.type == 'fire_wand' or b.type == 'hellfire' then
                                    local splash = b.splashRadius or 0
                                    if splash > 0 then
                                        local splashSq = splash * splash
                                        for jj, o in ipairs(state.enemies) do
                                            if jj ~= j then
                                                local dx = o.x - e.x
                                                local dy = o.y - e.y
                                                if dx*dx + dy*dy <= splashSq then
                                                    if o.status and o.status.oiled then
                                                        calculator.applyStatus(state, o, instance, 1)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                b.pierce = (b.pierce or 1) - 1
                                if b.pierce <= 0 then
                                    table.remove(state.bullets, i)
                                    hit = true
                                    break
                                end
                            end
                        end
                    end
                    ::continue_enemy_check::
                end
                -- [[ Bullet-to-bullet cancellation removed: Only melee attacks should cancel bullets ]]

                if not hit and b.type == 'axe' and b.y > state.player.y + 600 then
                    table.remove(state.bullets, i)
                end
            end
        end

        ::continue_player_bullet::
    end
end

function projectiles.updateEnemyBullets(state, dt)
    -- global safety cap to avoid bullet flood in long runs
    local maxEnemyBullets = 120
    if state.enemyBullets and #state.enemyBullets > maxEnemyBullets then
        local excess = #state.enemyBullets - maxEnemyBullets
        for _ = 1, excess do
            table.remove(state.enemyBullets, 1)
        end
    end

    local magnetizeTargets = nil
    if state.enemies then
        for _, e in ipairs(state.enemies) do
            local m = e and e.magnetize
            if m and m.timer and m.timer > 0 and m.radius and m.radius > 0 then
                magnetizeTargets = magnetizeTargets or {}
                table.insert(magnetizeTargets, {enemy = e, data = m})
            end
        end
    end
    
    -- Helper function to check if a point is within the electric shield arc
    local function isInShieldArc(px, py, bx, by, shield)
        if not shield or not shield.active then return false end
        
        local arcRadius = shield.distance or 60
        local arcWidth = shield.arcWidth or 1.2
        local shieldAngle = shield.angle or 0
        
        -- Calculate distance from player to bullet
        local dx = bx - px
        local dy = by - py
        local dist = math.sqrt(dx * dx + dy * dy)
        
        -- Check if within arc radius range (some tolerance)
        local tolerance = 20
        if dist < arcRadius - tolerance or dist > arcRadius + tolerance then
            return false
        end
        
        -- Check if within arc angle range
        local bulletAngle = math.atan2(dy, dx)
        local angleDiff = (bulletAngle - shieldAngle + math.pi) % (math.pi * 2) - math.pi
        
        return math.abs(angleDiff) <= arcWidth / 2
    end
    
    for i = #state.enemyBullets, 1, -1 do
        local eb = state.enemyBullets[i]
        local ox, oy = eb.x, eb.y
        eb.x = eb.x + eb.vx * dt
        eb.y = eb.y + eb.vy * dt
        eb.life = eb.life - dt
        eb.rotation = math.atan2(eb.vy, eb.vx)

        local world = state.world
        if world and world.enabled and world.segmentHitsWall then
            if world:segmentHitsWall(ox, oy, eb.x, eb.y) then
                table.remove(state.enemyBullets, i)
                goto continue_enemy_bullet
            end
        end

        if magnetizeTargets and eb.vx and eb.vy and not eb.noMagnetize then
            local bestTarget = nil
            local bestD2 = math.huge
            local absorbRadius = nil
            for _, t in ipairs(magnetizeTargets) do
                local e = t.enemy
                local m = t.data
                if e and m then
                    local dx = e.x - eb.x
                    local dy = e.y - eb.y
                    local r = m.radius or 0
                    local pullRange = r * 1.4
                    local d2 = dx * dx + dy * dy
                    if r > 0 and d2 <= pullRange * pullRange and d2 < bestD2 then
                        bestD2 = d2
                        bestTarget = e
                        absorbRadius = r
                    end
                end
            end
            if bestTarget then
                steerBullet(eb, bestTarget.x, bestTarget.y, 14, dt)
                if absorbRadius and bestD2 <= absorbRadius * absorbRadius then
                    addMagnetizeStoredDamage(bestTarget, nil, eb)
                    if state.spawnEffect then state.spawnEffect('static', eb.x, eb.y, 0.4) end
                    table.remove(state.enemyBullets, i)
                    goto continue_enemy_bullet
                end
            end
        end
        
        -- Check if blocked by Volt's Electric Shield
        local p = state.player
        if p and p.electricShield and p.electricShield.active then
            if isInShieldArc(p.x, p.y, eb.x, eb.y, p.electricShield) then
                -- Bullet blocked by shield!
                if state.spawnEffect then
                    state.spawnEffect('shock', eb.x, eb.y, 0.6)
                end
                -- Create small lightning VFX
                state.voltLightningChains = state.voltLightningChains or {}
                table.insert(state.voltLightningChains, {
                    segments = {{
                        x1 = eb.x, y1 = eb.y,
                        x2 = eb.x + (math.random() - 0.5) * 30,
                        y2 = eb.y + (math.random() - 0.5) * 30,
                        width = 6
                    }},
                    timer = 0.15,
                    alpha = 0.8
                })
                table.remove(state.enemyBullets, i)
                goto continue_enemy_bullet
            end
        end

        if eb.life <= 0 or math.abs(eb.x - state.player.x) > 1500 or math.abs(eb.y - state.player.y) > 1500 then
            -- Check if explosive bullet expired near targets (detonation)
            if eb.explosive and eb.splashRadius and eb.splashRadius > 0 then
                local splashR = eb.splashRadius
                local splashR2 = splashR * splashR
                local px, py = state.player.x, state.player.y
                local dx, dy = eb.x - px, eb.y - py
                if dx*dx + dy*dy <= splashR2 and state.player.invincibleTimer <= 0 then
                    player.hurt(state, eb.damage * 0.6)  -- Reduced splash damage
                end
                local pet = pets.getActive(state)
                if pet and not pet.downed then
                    local pdx, pdy = eb.x - (pet.x or 0), eb.y - (pet.y or 0)
                    if pdx*pdx + pdy*pdy <= splashR2 then
                        pets.hurt(state, pet, eb.damage * 0.6)
                    end
                end
                if state.spawnEffect then state.spawnEffect('blast_hit', eb.x, eb.y, 1.2) end
            end
            table.remove(state.enemyBullets, i)
        elseif state.player.invincibleTimer <= 0 and util.checkCollision(eb, {x=state.player.x, y=state.player.y, size=state.player.size}) then
            player.hurt(state, eb.damage)
            -- Handle explosive splash damage on direct hit
            if eb.explosive and eb.splashRadius and eb.splashRadius > 0 then
                local splashR = eb.splashRadius
                if state.spawnEffect then state.spawnEffect('blast_hit', eb.x, eb.y, 1.2) end
                -- Also hurt pet if in splash radius
                local pet = pets.getActive(state)
                if pet and not pet.downed then
                    local pdx = eb.x - (pet.x or 0)
                    local pdy = eb.y - (pet.y or 0)
                    if pdx*pdx + pdy*pdy <= splashR * splashR then
                        pets.hurt(state, pet, eb.damage * 0.6)
                    end
                end
            end
            table.remove(state.enemyBullets, i)
        else
            local pet = pets.getActive(state)
            if pet and not pet.downed and (pet.invincibleTimer or 0) <= 0 then
                if util.checkCollision(eb, {x = pet.x, y = pet.y, size = pet.size or 18}) then
                    pets.hurt(state, pet, eb.damage)
                    table.remove(state.enemyBullets, i)
                end
            end
        end
        ::continue_enemy_bullet::
    end
end

return projectiles
