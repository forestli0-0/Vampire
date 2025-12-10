local player = require('player')

local enemies = {}

function enemies.spawnEnemy(state, type, isElite)
    local types = {
        skeleton = {hp=10, spd=50, col={0.8,0.8,0.8}, sz=16},
        bat = {hp=5, spd=150, col={0.6,0,1}, sz=12},
        plant = {hp=35, spd=30, col={0,0.7,0.2}, sz=22, shoot=3}
    }
    local t = types[type]
    local ang = math.random() * 6.28
    local d = 500

    local hp = t.hp
    local size = t.sz
    local color = t.col

    if isElite then
        hp = hp * 5
        size = size * 1.5
        color = {1, 0, 0}
    end

    table.insert(state.enemies, {
        x = state.player.x + math.cos(ang) * d,
        y = state.player.y + math.sin(ang) * d,
        hp = hp,
        speed = t.spd,
        color = color,
        size = size,
        isElite = isElite,
        kind = type,
        shootTimer = t.shoot
    })
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
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]

        if e.flashTimer and e.flashTimer > 0 then
            e.flashTimer = e.flashTimer - dt
            if e.flashTimer < 0 then e.flashTimer = 0 end
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

        if e.kind == 'plant' then
            e.shootTimer = (e.shootTimer or 0) - dt
            if e.shootTimer <= 0 then
                local ang = math.atan2(p.y - e.y, p.x - e.x)
                local spd = 180
                table.insert(state.enemyBullets, {x=e.x, y=e.y, vx=math.cos(ang)*spd, vy=math.sin(ang)*spd, size=10, life=5, damage=10})
                e.shootTimer = 3
            end
        end

        local angle = math.atan2(p.y - e.y, p.x - e.x)
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
