local util = require('util')
local enemies = require('enemies')
local player = require('player')

local projectiles = {}

function projectiles.updatePlayerBullets(state, dt)
    for i = #state.bullets, 1, -1 do
        local b = state.bullets[i]

        if b.type == 'wand' or b.type == 'holy_wand' or b.type == 'fire_wand' or b.type == 'oil_bottle' or b.type == 'heavy_hammer' or b.type == 'dagger' then
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
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
                    if b.type == 'wand' or b.type == 'holy_wand' or b.type == 'fire_wand' or b.type == 'oil_bottle' or b.type == 'heavy_hammer' or b.type == 'dagger' then
                        enemies.applyStatus(state, e, b.effectType, b.damage, b.weaponTags)
                        if (b.damage or 0) > 0 then enemies.damageEnemy(state, e, b.damage, false, 0) end
                        b.pierce = (b.pierce or 1) - 1
                        if b.pierce <= 0 then
                            table.remove(state.bullets, i)
                            hit = true
                            break
                        end
                    elseif b.type == 'axe' then
                        b.hitTargets = b.hitTargets or {}
                        if not b.hitTargets[e] then
                            b.hitTargets[e] = true
                            enemies.applyStatus(state, e, b.effectType, b.damage, b.weaponTags)
                            enemies.damageEnemy(state, e, b.damage, false, 0)
                        end
                    elseif b.type == 'death_spiral' then
                        b.hitTargets = b.hitTargets or {}
                        if not b.hitTargets[e] then
                            b.hitTargets[e] = true
                            enemies.applyStatus(state, e, b.effectType, b.damage, b.weaponTags)
                            enemies.damageEnemy(state, e, b.damage, false, 0)
                        end
                    end
                end
            end
            if not hit and b.type == 'axe' and b.y > state.player.y + 600 then
                table.remove(state.bullets, i)
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

        if eb.life <= 0 or math.abs(eb.x - state.player.x) > 1500 or math.abs(eb.y - state.player.y) > 1500 then
            table.remove(state.enemyBullets, i)
        elseif state.player.invincibleTimer <= 0 and util.checkCollision(eb, {x=state.player.x, y=state.player.y, size=state.player.size}) then
            player.hurt(state, eb.damage)
            table.remove(state.enemyBullets, i)
        end
    end
end

return projectiles
