local util = require('util')
local enemies = require('enemies')
local player = require('player')
local calculator = require('calculator')

local projectiles = {}

local function buildInstanceFromBullet(bullet, effectData, knock, knockForce)
    return calculator.createInstance({
        damage = bullet.damage or 0,
        critChance = bullet.critChance or 0,
        critMultiplier = bullet.critMultiplier or 1.5,
        statusChance = bullet.statusChance or 0,
        effectType = bullet.effectType,
        effectData = effectData,
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
            if b.type == 'wand' or b.type == 'holy_wand' or b.type == 'fire_wand' or b.type == 'hellfire' or b.type == 'oil_bottle' or b.type == 'heavy_hammer' or b.type == 'dagger' or b.type == 'thousand_edge' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'debug_effect' then
                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt
                b.rotation = math.atan2(b.vy, b.vx)
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
                                calculator.applyHit(state, e, instance)
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
                        elseif b.type == 'wand' or b.type == 'holy_wand' or b.type == 'heavy_hammer' or b.type == 'dagger' or b.type == 'thousand_edge' or b.type == 'static_orb' or b.type == 'thunder_loop' or b.type == 'debug_effect' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local effectData
                                if b.effectDuration or b.effectRange or b.chain or b.allowRepeat then
                                    effectData = {duration = b.effectDuration, range = b.effectRange, chain = b.chain, allowRepeat = b.allowRepeat}
                                end
                                local instance = buildInstanceFromBullet(b, effectData)
                                calculator.applyHit(state, e, instance)
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
                                calculator.applyHit(state, e, instance)
                            end
                        elseif b.type == 'death_spiral' then
                            b.hitTargets = b.hitTargets or {}
                            if not b.hitTargets[e] then
                                b.hitTargets[e] = true
                                local instance = buildInstanceFromBullet(b)
                                calculator.applyHit(state, e, instance)
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
    end
end

function projectiles.updateEnemyBullets(state, dt)
    for i = #state.enemyBullets, 1, -1 do
        local eb = state.enemyBullets[i]
        eb.x = eb.x + eb.vx * dt
        eb.y = eb.y + eb.vy * dt
        eb.life = eb.life - dt
        eb.rotation = math.atan2(eb.vy, eb.vx)

        if eb.life <= 0 or math.abs(eb.x - state.player.x) > 1500 or math.abs(eb.y - state.player.y) > 1500 then
            table.remove(state.enemyBullets, i)
        elseif state.player.invincibleTimer <= 0 and util.checkCollision(eb, {x=state.player.x, y=state.player.y, size=state.player.size}) then
            player.hurt(state, eb.damage)
            table.remove(state.enemyBullets, i)
        end
    end
end

return projectiles
