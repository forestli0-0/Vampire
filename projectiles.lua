local util = require('util')
local enemies = require('enemies')
local player = require('player')
local pets = require('pets')
local calculator = require('calculator')

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

local function buildInstanceFromBullet(bullet, effectData, knock, knockForce)
    return calculator.createInstance({
        damage = bullet.damage or 0,
        critChance = bullet.critChance or 0,
        critMultiplier = bullet.critMultiplier or 1.5,
        statusChance = bullet.statusChance or 0,
        effectType = bullet.effectType,
        effectData = effectData,
        elements = bullet.elements,
        damageBreakdown = bullet.damageBreakdown,
        weaponTags = bullet.weaponTags,
        knock = knock,
        knockForce = knockForce
    })
end

local function applyProjectileHit(state, enemy, bullet, effectData, knock, knockForce)
    local instance = buildInstanceFromBullet(bullet, effectData, knock, knockForce)
    return calculator.applyHit(state, enemy, instance)
end

function projectiles.updatePlayerBullets(state, dt)
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
                local instance = buildInstanceFromBullet(b, effectData)
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
            if b.type == 'wand' or b.type == 'holy_wand' or b.type == 'fire_wand' or b.type == 'hellfire' or b.type == 'oil_bottle' or b.type == 'heavy_hammer' or b.type == 'dagger' or b.type == 'thousand_edge' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'debug_effect' or b.type == 'augment_shard' then
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                if b.type ~= 'oil_bottle' then
                    b.rotation = math.atan2(b.vy, b.vx)
                end
            elseif b.type == 'axe' then
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                b.vy = b.vy + 1000 * dt
                b.rotation = b.rotation + 10 * dt
            elseif b.type == 'death_spiral' then
                local ang = math.atan2(b.vy, b.vx) + (b.angularVel or 0) * dt
                local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                b.vx = math.cos(ang) * spd
                b.vy = math.sin(ang) * spd
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                b.rotation = (b.rotation or 0) + 8 * dt
            end

            local world = state.world
            if world and world.enabled and world.segmentHitsWall then
                if world:segmentHitsWall(ox, oy, b.x, b.y) then
                    if state.spawnEffect then state.spawnEffect('hit', b.x, b.y, 0.55) end
                    table.remove(state.bullets, i)
                    goto continue_player_bullet
                end
            end

            b.life = b.life - dt

            local hit = false
            if b.life <= 0 then
                table.remove(state.bullets, i)
            else
                for j = #state.enemies, 1, -1 do
                    local e = state.enemies[j]
                    if util.checkCollision(b, e) then
                        if b.type == 'oil_bottle' then
                            -- Apply oil to target and splash neighbors, then disappear
                            local effectData
                            if b.effectDuration then effectData = {duration = b.effectDuration} end
                            local instance = buildInstanceFromBullet(b, effectData)
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
                        elseif b.type == 'fire_wand' or b.type == 'hellfire' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local effectData
                                if b.effectDuration or b.effectRange or b.chain or b.allowRepeat then
                                    effectData = {duration = b.effectDuration, range = b.effectRange, chain = b.chain, allowRepeat = b.allowRepeat}
                                end
                                local instance = buildInstanceFromBullet(b, effectData)
                                local result = calculator.applyHit(state, e, instance)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                                tryRicochet(state, b, e.x, e.y)
                                -- Ignite nearby oiled enemies in splash radius
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
                                b.pierce = (b.pierce or 1) - 1
                                if b.pierce <= 0 then
                                    table.remove(state.bullets, i)
                                    hit = true
                                    break
                                end
                            end
                        elseif b.type == 'wand' or b.type == 'holy_wand' or b.type == 'heavy_hammer' or b.type == 'dagger' or b.type == 'thousand_edge' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'debug_effect' or b.type == 'augment_shard' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local effectData
                                if b.effectDuration or b.effectRange or b.chain or b.allowRepeat then
                                    effectData = {duration = b.effectDuration, range = b.effectRange, chain = b.chain, allowRepeat = b.allowRepeat}
                                end
                                local instance = buildInstanceFromBullet(b, effectData)
                                local result = calculator.applyHit(state, e, instance)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                                tryRicochet(state, b, e.x, e.y)
                                b.pierce = (b.pierce or 1) - 1
                                if b.pierce <= 0 then
                                    table.remove(state.bullets, i)
                                    hit = true
                                    break
                                end
                            end
                        elseif b.type == 'axe' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local instance = buildInstanceFromBullet(b)
                                local result = calculator.applyHit(state, e, instance)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                            end
                        elseif b.type == 'death_spiral' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local instance = buildInstanceFromBullet(b)
                                local result = calculator.applyHit(state, e, instance)
                                if state and state.augments and state.augments.dispatch then
                                    state.augments.dispatch(state, 'onProjectileHit', {bullet = b, enemy = e, result = result, player = state.player, weaponKey = b.parentWeaponKey or b.type})
                                end
                            end
                        end
                    end
                end
                -- 玩家投射物抵消敌方子弹
                if state.enemyBullets and #state.enemyBullets > 0 then
                    for ebIndex = #state.enemyBullets, 1, -1 do
                        local eb = state.enemyBullets[ebIndex]
                        if util.checkCollision(b, eb) then
                            table.remove(state.enemyBullets, ebIndex)
                            b.pierce = (b.pierce or 1) - 1
                            if b.pierce <= 0 then
                                table.remove(state.bullets, i)
                                hit = true
                            end
                            break
                        end
                    end
                end
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

        if eb.life <= 0 or math.abs(eb.x - state.player.x) > 1500 or math.abs(eb.y - state.player.y) > 1500 then
            table.remove(state.enemyBullets, i)
        elseif state.player.invincibleTimer <= 0 and util.checkCollision(eb, {x=state.player.x, y=state.player.y, size=state.player.size}) then
            player.hurt(state, eb.damage)
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
