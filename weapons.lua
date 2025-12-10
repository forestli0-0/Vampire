local enemies = require('enemies')

local weapons = {}

local function cloneStats(base)
    return {
        damage = base.damage,
        cd = base.cd,
        speed = base.speed,
        radius = base.radius,
        knockback = base.knockback,
        area = base.area or 1
    }
end

function weapons.addWeapon(state, key)
    local proto = state.catalog[key]
    local stats = cloneStats(proto.base)
    state.inventory.weapons[key] = { level = 1, timer = 0, stats = stats }
end

function weapons.spawnProjectile(state, type, x, y, target)
    local wStats = state.inventory.weapons[type].stats
    local finalDmg = math.floor(wStats.damage * state.player.stats.might)
    local area = wStats.area or 1

    if type == 'wand' or type == 'holy_wand' then
        local angle = math.atan2(target.y - y, target.x - x)
        local spd = wStats.speed * state.player.stats.speed
        table.insert(state.bullets, {type='wand', x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd, life=2, size=6 * area, damage=finalDmg})
    elseif type == 'axe' then
        local spd = wStats.speed * state.player.stats.speed
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        table.insert(state.bullets, {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=12 * area, damage=finalDmg, rotation=0, hitTargets={}})
    elseif type == 'death_spiral' then
        local count = 8
        local spd = (wStats.speed or 300) * state.player.stats.speed
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2
            table.insert(state.bullets, {
                type='death_spiral', x=x, y=y,
                vx=math.cos(angle)*spd, vy=math.sin(angle)*spd,
                life=3, size=14 * area, damage=finalDmg,
                rotation=0, angularVel=1.5, hitTargets={}
            })
        end
    end
end

function weapons.update(state, dt)
    for key, w in pairs(state.inventory.weapons) do
        w.timer = w.timer - dt
        local actualCD = w.stats.cd * state.player.stats.cooldown

        if w.timer <= 0 then
            if key == 'wand' then
                local t = enemies.findNearestEnemy(state, 600)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    weapons.spawnProjectile(state, 'wand', state.player.x, state.player.y, t)
                    w.timer = actualCD
                end
            elseif key == 'holy_wand' then
                local t = enemies.findNearestEnemy(state, 700)
                if t then
                    if state.playSfx then state.playSfx('shoot') end
                    weapons.spawnProjectile(state, 'holy_wand', state.player.x, state.player.y, t)
                    w.timer = actualCD
                end
            elseif key == 'axe' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'axe', state.player.x, state.player.y, nil)
                w.timer = actualCD
            elseif key == 'death_spiral' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'death_spiral', state.player.x, state.player.y, nil)
                w.timer = actualCD
            elseif key == 'garlic' then
                local hit = false
                local actualDmg = math.floor(w.stats.damage * state.player.stats.might)
                local actualRadius = w.stats.radius * state.player.stats.area
                for _, e in ipairs(state.enemies) do
                    local d = math.sqrt((state.player.x - e.x)^2 + (state.player.y - e.y)^2)
                    if d < actualRadius then
                        enemies.damageEnemy(state, e, actualDmg, true, w.stats.knockback)
                        hit = true
                    end
                end
                if hit then w.timer = actualCD end
            end
        end
    end
end

return weapons
