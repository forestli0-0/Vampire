local enemies = require('enemies')

local weapons = {}

local function cloneStats(base)
    return {
        damage = base.damage,
        cd = base.cd,
        speed = base.speed,
        radius = base.radius,
        knockback = base.knockback
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

    if type == 'wand' then
        local angle = math.atan2(target.y - y, target.x - x)
        local spd = wStats.speed * state.player.stats.speed
        table.insert(state.bullets, {type='wand', x=x, y=y, vx=math.cos(angle)*spd, vy=math.sin(angle)*spd, life=2, size=6, damage=finalDmg})
    elseif type == 'axe' then
        local spd = wStats.speed * state.player.stats.speed
        local vx = (math.random() - 0.5) * 200
        local vy = -spd
        table.insert(state.bullets, {type='axe', x=x, y=y, vx=vx, vy=vy, life=3, size=12, damage=finalDmg, rotation=0, hitTargets={}})
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
            elseif key == 'axe' then
                if state.playSfx then state.playSfx('shoot') end
                weapons.spawnProjectile(state, 'axe', state.player.x, state.player.y, nil)
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
