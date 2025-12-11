local player = require('player')
local enemyDefs = require('enemy_defs')
local logger = require('logger')

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

function enemies.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
    if not effectType or not e then return end
    if type(effectType) ~= 'string' then return end
    ensureStatus(e)

    local might = 1
    if state and state.player and state.player.stats and state.player.stats.might then
        might = state.player.stats.might
    end

    local effect = string.upper(effectType)
    if effect == 'FREEZE' then
        e.status.frozen = true
        local dur = (effectData and effectData.duration) or 0.5
        local remaining = e.status.frozenTimer or 0
        e.status.frozenTimer = math.max(dur, remaining)
        e.speed = 0
        if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
    elseif effect == 'OIL' then
        e.status.oiled = true
        e.status.oiledTimer = math.max((effectData and effectData.duration) or 6.0, 0)
        if state.spawnEffect then state.spawnEffect('oil', e.x, e.y) end
    elseif effect == 'BLEED' then
        e.status.bleedStacks = (e.status.bleedStacks or 0) + 1
        if state.spawnEffect then state.spawnEffect('bleed', e.x, e.y) end
        if e.status.bleedStacks >= 10 then
            local boom = math.floor((e.maxHp or e.hp or 0) * 0.2 * might)
            if boom > 0 then enemies.damageEnemy(state, e, boom, false, 0) end
            e.status.bleedStacks = 0
        end
    elseif effect == 'FIRE' then
        if e.status.oiled then
            e.status.burnTimer = 5
            e.status.oiled = false
            e.status.oiledTimer = nil
            e.status.burnDps = math.max(1, (e.maxHp or e.hp or 0) * 0.03 * might)
            if state.spawnEffect then state.spawnEffect('fire', e.x, e.y) end
        end
    elseif effect == 'HEAVY' then
        if e.status.frozen then
            local extra = math.floor((baseDamage or 0) * 2)
            if extra > 0 then enemies.damageEnemy(state, e, extra, false, 0) end
            e.status.frozen = false
            e.status.frozenTimer = nil
            e.speed = e.baseSpeed or e.speed
            if state.playSfx then state.playSfx('glass') end
        end
    elseif effect == 'STATIC' then
        local data = {
            duration = math.max((effectData and effectData.duration) or 2.0, 0),
            range = (effectData and effectData.range) or 160,
            remaining = (effectData and effectData.chain) or 3,
            allowRepeat = (effectData and effectData.allowRepeat) or false,
            tick = 0.35
        }
        if not data.allowRepeat then data.visited = {} end
        if data.visited then data.visited[e] = true end
        e.status.static = true
        e.status.staticTimer = 0
        e.status.staticDuration = data.duration
        e.status.staticRange = data.range
        e.status.staticData = data
        if state.spawnEffect then state.spawnEffect('static', e.x, e.y) end
    end
end

function enemies.spawnEnemy(state, type, isElite, spawnX, spawnY)
    local def = enemyDefs[type] or enemyDefs.skeleton
    local color = def.color and {def.color[1], def.color[2], def.color[3]} or {1,1,1}
    local hp = def.hp
    local size = def.size
    local speed = def.speed

    local ang = math.random() * 6.28
    local d = def.spawnDistance or 500
    local x = spawnX or (state.player.x + math.cos(ang) * d)
    local y = spawnY or (state.player.y + math.sin(ang) * d)

    local hpScale = 1 + math.min((state.gameTimer or 0), 300) / 300 -- cap at ~2x at 5min
    if hpScale > 2.5 then hpScale = 2.5 end
    hp = hp * hpScale

    if isElite then
        hp = hp * 5
        size = size * 1.5
        color = {1, 0, 0}
    end

    table.insert(state.enemies, {
        x = x,
        y = y,
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

function enemies.damageEnemy(state, e, dmg, knock, kForce, isCrit)
    e.hp = e.hp - dmg
    e.flashTimer = 0.1
    if state.playSfx then state.playSfx('hit') end
    local color = {1,1,1}
    local scale = 1
    if isCrit then
        color = {1, 1, 0}
        scale = 1.5
    end
    table.insert(state.texts, {x=e.x, y=e.y-20, text=dmg, color=color, life=0.5, scale=scale})
    if knock then
        local a = math.atan2(e.y - state.player.y, e.x - state.player.x)
        e.x = e.x + math.cos(a) * (kForce or 10)
        e.y = e.y + math.sin(a) * (kForce or 10)
    end
end

function enemies.update(state, dt)
    local p = state.player
    local playerMight = (state.player and state.player.stats and state.player.stats.might) or 1
    state.chainLinks = {}
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        ensureStatus(e)

        if e.flashTimer and e.flashTimer > 0 then
            e.flashTimer = e.flashTimer - dt
            if e.flashTimer < 0 then e.flashTimer = 0 end
        end

        if e.status.frozen then
            e.status.frozenTimer = (e.status.frozenTimer or 0) - dt
            if e.status.frozenTimer <= 0 then
                e.status.frozen = false
                e.status.frozenTimer = nil
                e.speed = e.baseSpeed or e.speed
            end
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

        if e.status.oiled and e.status.oiledTimer then
            e.status.oiledTimer = e.status.oiledTimer - dt
            if e.status.oiledTimer <= 0 then
                e.status.oiled = false
                e.status.oiledTimer = nil
            end
        end

        if e.status.static then
            local data = e.status.staticData or {}
            data.duration = (data.duration or 0) - dt
            e.status.staticTimer = (e.status.staticTimer or 0) - dt
            if data.duration <= 0 or (data.remaining or 0) <= 0 then
                e.status.static = false
                e.status.staticTimer = nil
                e.status.staticDuration = nil
                e.status.staticRange = nil
                e.status.staticData = nil
            elseif e.status.staticTimer <= 0 then
                local visited = data.visited or {}
                if not data.allowRepeat then
                    visited[e] = true
                    data.visited = visited
                end
                local nearest, dist2 = nil, (data.range or e.status.staticRange or 160) ^ 2
                for j, o in ipairs(state.enemies) do
                    if i ~= j then
                        if data.allowRepeat or not visited[o] then
                            local dx = o.x - e.x
                            local dy = o.y - e.y
                            local d2 = dx*dx + dy*dy
                            if d2 < dist2 then
                                dist2 = d2
                                nearest = o
                            end
                        end
                    end
                end
                if nearest then
                    ensureStatus(nearest)
                    local staticDmg = math.max(1, math.floor((e.maxHp or 10) * 0.05 * playerMight))
                    enemies.damageEnemy(state, nearest, staticDmg, false, 0)
                    if not data.allowRepeat then visited[nearest] = true end
                    data.remaining = (data.remaining or 1) - 1
                    table.insert(state.chainLinks, {x1=e.x, y1=e.y, x2=nearest.x, y2=nearest.y})
                    nearest.status.static = true
                    nearest.status.staticTimer = data.tick or 0.35
                    nearest.status.staticDuration = data.duration
                    nearest.status.staticRange = data.range
                    nearest.status.staticData = data
                    if state.spawnEffect then state.spawnEffect('static', nearest.x, nearest.y) end
                    e.status.static = false
                    e.status.staticTimer = nil
                    e.status.staticDuration = nil
                    e.status.staticRange = nil
                    e.status.staticData = nil
                else
                    e.status.static = false
                    e.status.staticTimer = nil
                    e.status.staticDuration = nil
                    e.status.staticRange = nil
                    e.status.staticData = nil
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
                local spriteKey = nil
                if e.kind == 'plant' then spriteKey = 'plant_bullet' end
                table.insert(state.enemyBullets, {
                    x = e.x, y = e.y,
                    vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
                    size = e.bulletSize or 10,
                    life = e.bulletLife or 5,
                    damage = e.bulletDamage or 10,
                    type = e.kind,
                    rotation = ang,
                    spriteKey = spriteKey
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
            logger.kill(state, e)
            table.remove(state.enemies, i)
        end
    end
end

return enemies
