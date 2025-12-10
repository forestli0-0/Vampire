local util = require('util')
local upgrades = require('upgrades')

local pickups = {}

local function addXp(state, amount)
    local p = state.player
    p.xp = p.xp + amount
    while p.xp >= p.xpToNextLevel do
        p.level = p.level + 1
        p.xp = p.xp - p.xpToNextLevel
        p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.5)
        upgrades.queueLevelUp(state)
    end
end

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
            addXp(state, g.value)
            table.remove(state.gems, i)
            if state.playSfx then state.playSfx('gem') end
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
                local chestXp = 120
                addXp(state, chestXp)
                table.insert(state.texts, {x=p.x, y=p.y-50, text="+"..chestXp.." XP", color={0, 1, 0}, life=1})
            end
            table.remove(state.chests, i)
        end
    end
end

function pickups.updateFloorPickups(state, dt)
    local p = state.player
    local radius = (p.size or 20) / 2
    for i = #state.floorPickups, 1, -1 do
        local item = state.floorPickups[i]
        if util.checkCollision({x=p.x, y=p.y, size=p.size}, item) then
            if item.kind == 'chicken' then
                p.hp = math.min(p.maxHp, p.hp + 30)
                table.insert(state.texts, {x=p.x, y=p.y-30, text="+30 HP", color={1,0.7,0}, life=1})
            elseif item.kind == 'magnet' then
                -- 吸取全地图宝石
                local collected = false
                for gi = #state.gems, 1, -1 do
                    addXp(state, state.gems[gi].value)
                    table.remove(state.gems, gi)
                    collected = true
                end
                if collected and state.playSfx then state.playSfx('gem') end
                table.insert(state.texts, {x=p.x, y=p.y-30, text="MAGNET!", color={0,0.8,1}, life=1})
            elseif item.kind == 'bomb' then
                -- 只杀屏幕内的敌人
                local w, h = love.graphics.getWidth(), love.graphics.getHeight()
                local halfW, halfH = w/2 + 50, h/2 + 50
                for ei = #state.enemies, 1, -1 do
                    local e = state.enemies[ei]
                    if math.abs(e.x - p.x) <= halfW and math.abs(e.y - p.y) <= halfH then
                        e.hp = 0
                    end
                end
                state.shakeAmount = 5
                if state.playSfx then state.playSfx('hit') end
                table.insert(state.texts, {x=p.x, y=p.y-30, text="BOMB!", color={1,0,0}, life=1})
            end
            table.remove(state.floorPickups, i)
        end
    end
end

return pickups
