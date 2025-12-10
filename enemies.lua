local player = require('player')
local enemyDefs = require('enemy_defs')

local enemies = {}

local function ensureStatus(e)
    if not e.status then
        e.status = {
            frozen = false,
            oiled = false,
            static = false,
            bleedStacks = 0,
            burnTimer = 0
        }
    end
    e.baseSpeed = e.baseSpeed or e.speed
    e.maxHp = e.maxHp or e.hp
end

function enemies.applyStatus(state, e, effectType, baseDamage, weaponTags)
    if not effectType or not e then return end
    if type(effectType) ~= 'string' then return end
    ensureStatus(e)

    local effect = string.upper(effectType)
    if effect == 'FREEZE' then
        e.status.frozen = true
        e.speed = 0
    elseif effect == 'OIL' then
        e.status.oiled = true
    elseif effect == 'BLEED' then
        e.status.bleedStacks = (e.status.bleedStacks or 0) + 1
        if e.status.bleedStacks >= 10 then
            local boom = math.floor((e.maxHp or e.hp or 0) * 0.2)
            if boom > 0 then enemies.damageEnemy(state, e, boom, false, 0) end
            e.status.bleedStacks = 0
        end
    elseif effect == 'FIRE' then
        if e.status.oiled then
            e.status.burnTimer = 5
            e.status.oiled = false
            e.status.burnDps = math.max(1, (e.maxHp or e.hp or 0) * 0.05)
        end
    elseif effect == 'HEAVY' then
        if e.status.frozen then
            local extra = math.floor((baseDamage or 0) * 2)
            if extra > 0 then enemies.damageEnemy(state, e, extra, false, 0) end
            e.status.frozen = false
            e.speed = e.baseSpeed or e.speed
            if state.playSfx then state.playSfx('glass') end
        end
    elseif effect == 'STATIC' then
        e.status.static = true
    end
end

function enemies.spawnEnemy(state, type, isElite)
    local def = enemyDefs[type] or enemyDefs.skeleton
    local color = def.color and {def.color[1], def.color[2], def.color[3]} or {1,1,1}
    local hp = def.hp
    local size = def.size
    local speed = def.speed

    local ang = math.random() * 6.28
    local d = def.spawnDistance or 500

    if isElite then
        hp = hp * 5
        size = size * 1.5
        color = {1, 0, 0}
    end

    table.insert(state.enemies, {
        x = state.player.x + math.cos(ang) * d,
        y = state.player.y + math.sin(ang) * d,
        hp = hp,
        speed = speed,
        color = color,
        size = size,
        isElite = isElite,
        kind = type,
        shootInterval = def.shootInterval,
        shootTimer = def.shootInterval,
        bulletSpeed = def.bulletSpeed,
        bulletDamage = def.bulletDamage,
        bulletLife = def.bulletLife,
        bulletSize = def.bulletSize,
        facing = 1
    })
    if state.loadMoveAnimationFromFolder then
        local anim = state.loadMoveAnimationFromFolder(type, 4, 8)
        if anim then state.enemies[#state.enemies].anim = anim end
    end
    ensureStatus(state.enemies[#state.enemies])
end

function enemies.findNearestEnemy(state, maxDist)
    local t, m = nil, (maxDist or 999999) ^ 2
    for _, e in ipairs(state.enemies) do
        local d = (state.player.x - e.x)^2 + (state.player.y - e.y)^2
        if d < m then m = d; t = e end
    end
    return t
end

function enemies.damageEnemy(state, e, dmg, knock, kForce)
    e.hp = e.hp - dmg
    e.flashTimer = 0.1
    if state.playSfx then state.playSfx('hit') end
    table.insert(state.texts, {x=e.x, y=e.y-20, text=dmg, color={1,1,1}, life=0.5})
    if knock then
        local a = math.atan2(e.y - state.player.y, e.x - state.player.x)
        e.x = e.x + math.cos(a) * (kForce or 10)
        e.y = e.y + math.sin(a) * (kForce or 10)
    end
end

function enemies.update(state, dt)
    local p = state.player
    state.chainLinks = {}
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        ensureStatus(e)

        if e.flashTimer and e.flashTimer > 0 then
            e.flashTimer = e.flashTimer - dt
            if e.flashTimer < 0 then e.flashTimer = 0 end
        end

        if e.anim then e.anim:update(dt) end

        if e.status.burnTimer and e.status.burnTimer > 0 then
            e.status.burnTimer = e.status.burnTimer - dt
            local dps = math.max(1, e.status.burnDps or ((e.maxHp or e.hp or 0) * 0.05))
            e.status._burnAcc = (e.status._burnAcc or 0) + dps * dt
            if e.status._burnAcc >= 1 then
                local burnDmg = math.floor(e.status._burnAcc)
                e.status._burnAcc = e.status._burnAcc - burnDmg
                if burnDmg > 0 then enemies.damageEnemy(state, e, burnDmg, false, 0) end
            end
            if e.status.burnTimer < 0 then e.status.burnTimer = 0 end
        end

        if e.status.static then
            e.status.staticTimer = (e.status.staticTimer or 0) - dt
            if e.status.staticTimer <= 0 then
                local nearest, dist2 = nil, 30 * 30
                for j, o in ipairs(state.enemies) do
                    if i ~= j then
                        local dx = o.x - e.x
                        local dy = o.y - e.y
                        local d2 = dx*dx + dy*dy
                        if d2 < dist2 then
                            dist2 = d2
                            nearest = o
                        end
                    end
                end
                if nearest then
                    local staticDmg = math.max(1, math.floor((e.maxHp or 10) * 0.05))
                    enemies.damageEnemy(state, e, staticDmg, false, 0)
                    enemies.damageEnemy(state, nearest, staticDmg, false, 0)
                    table.insert(state.chainLinks, {x1=e.x, y1=e.y, x2=nearest.x, y2=nearest.y})
                    e.status.staticTimer = 0.5
                end
            end
        end

        local pushX, pushY = 0, 0
        if #state.enemies > 1 then
            local checks = math.min(8, #state.enemies - 1)
            for _ = 1, checks do
                local idx
                repeat idx = math.random(#state.enemies) until idx ~= i
                local o = state.enemies[idx]
                local dx = e.x - o.x
                local dy = e.y - o.y
                local distSq = dx*dx + dy*dy
                local minDist = ((e.size or 16) + (o.size or 16)) * 0.5
                local minDistSq = minDist * minDist
                if distSq > 0 and distSq < minDistSq then
                    local dist = math.sqrt(distSq)
                    local overlap = minDist - dist
                    local nx, ny = dx / dist, dy / dist
                    local strength = 5
                    pushX = pushX + nx * overlap * strength
                    pushY = pushY + ny * overlap * strength
                end
            end
        end

        if e.shootInterval then
            e.shootTimer = (e.shootTimer or e.shootInterval) - dt
            if e.shootTimer <= 0 then
                local ang = math.atan2(p.y - e.y, p.x - e.x)
                local spd = e.bulletSpeed or 180
                table.insert(state.enemyBullets, {
                    x = e.x, y = e.y,
                    vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
                    size = e.bulletSize or 10,
                    life = e.bulletLife or 5,
                    damage = e.bulletDamage or 10
                })
                e.shootTimer = e.shootInterval
            end
        end

        local angle = math.atan2(p.y - e.y, p.x - e.x)
        local dxToPlayer = p.x - e.x
        if math.abs(dxToPlayer) > 1 then
            e.facing = dxToPlayer >= 0 and 1 or -1
        end
        e.x = e.x + (math.cos(angle) * e.speed + pushX) * dt
        e.y = e.y + (math.sin(angle) * e.speed + pushY) * dt

        local pDist = math.sqrt((p.x - e.x)^2 + (p.y - e.y)^2)
        local playerRadius = (p.size or 20) / 2
        local enemyRadius = (e.size or 16) / 2
        if pDist < (playerRadius + enemyRadius) then
            player.hurt(state, 10)
        end

        if e.hp <= 0 then
            if e.isElite then
                table.insert(state.chests, {x=e.x, y=e.y, w=20, h=20})
            else
                if math.random() < 0.01 then
                    local kinds = {'chicken','magnet','bomb'}
                    local kind = kinds[math.random(#kinds)]
                    table.insert(state.floorPickups, {x=e.x, y=e.y, size=14, kind=kind})
                else
                    table.insert(state.gems, {x=e.x, y=e.y, value=1})
                end
            end
            table.remove(state.enemies, i)
        end
    end
end

return enemies
