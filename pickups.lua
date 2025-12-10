local upgrades = require('upgrades')

local pickups = {}

function pickups.updateGems(state, dt)
    local p = state.player
    for i = #state.gems, 1, -1 do
        local g = state.gems[i]
        local dx = p.x - g.x
        local dy = p.y - g.y
        local distSq = dx*dx + dy*dy

        if distSq < p.stats.pickupRange^2 then
            local a = math.atan2(dy, dx)
            g.x = g.x + math.cos(a) * 600 * dt
            g.y = g.y + math.sin(a) * 600 * dt
            dx = p.x - g.x
            dy = p.y - g.y
            distSq = dx*dx + dy*dy
        end

        local pickupRadius = (p.size or 20) / 2
        if distSq < pickupRadius * pickupRadius then
            p.xp = p.xp + g.value
            table.remove(state.gems, i)
            while p.xp >= p.xpToNextLevel do
                p.level = p.level + 1
                p.xp = p.xp - p.xpToNextLevel
                p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.5)
                upgrades.queueLevelUp(state)
            end
        end
    end
end

function pickups.updateChests(state, dt)
    local p = state.player
    for i = #state.chests, 1, -1 do
        local c = state.chests[i]
        local dist = math.sqrt((p.x - c.x)^2 + (p.y - c.y)^2)
        if dist < 30 then
            local evolvedWeapon = upgrades.tryEvolveWeapon(state)
            if evolvedWeapon then
                table.insert(state.texts, {x=p.x, y=p.y-50, text="EVOLVED! " .. evolvedWeapon, color={1, 0.84, 0}, life=2})
            else
                p.xp = p.xp + 500
                table.insert(state.texts, {x=p.x, y=p.y-50, text="+500 XP", color={0, 1, 0}, life=1})
                while p.xp >= p.xpToNextLevel do
                    p.level = p.level + 1
                    p.xp = p.xp - p.xpToNextLevel
                    p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.5)
                    upgrades.queueLevelUp(state)
                end
            end
            table.remove(state.chests, i)
        end
    end
end

return pickups
