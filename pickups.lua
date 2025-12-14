local util = require('util')
local upgrades = require('upgrades')
local logger = require('logger')

local pickups = {}

function pickups.updateMagnetSpawns(state, dt)
    if not state.magnetTimer then return end
    state.magnetTimer = state.magnetTimer - dt
    if state.magnetTimer <= 0 then
        local dist = math.random(450, 750)
        local ang = math.random() * math.pi * 2
        local px, py = state.player.x, state.player.y
        local kinds = {'magnet','chicken','bomb'}
        local kind = kinds[math.random(#kinds)]
        table.insert(state.floorPickups, {
            x = px + math.cos(ang) * dist,
            y = py + math.sin(ang) * dist,
            size = 14,
            kind = kind
        })
        state.magnetTimer = math.random(55, 70) -- roughly once a minute
    end
end

local function addXp(state, amount)
    local p = state.player
    p.xp = p.xp + amount
    logger.gainXp(state, amount)
    if state.noLevelUps or state.benchmarkMode then
        return
    end
    while p.xp >= p.xpToNextLevel do
        p.level = p.level + 1
        p.xp = p.xp - p.xpToNextLevel
        p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.25)
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onLevelUp', {level = p.level, player = p})
        end
        upgrades.queueLevelUp(state, 'xp')
        logger.levelUp(state, p.level)
    end
end

function pickups.updateGems(state, dt)
    local p = state.player
    for i = #state.gems, 1, -1 do
        local g = state.gems[i]
        local dx = p.x - g.x
        local dy = p.y - g.y
        local distSq = dx*dx + dy*dy

        local magnetized = g.magnetized
        if magnetized or distSq < p.stats.pickupRange^2 then
            local a = math.atan2(dy, dx)
            local speed = magnetized and 900 or 600
            g.x = g.x + math.cos(a) * speed * dt
            g.y = g.y + math.sin(a) * speed * dt
            dx = p.x - g.x
            dy = p.y - g.y
            distSq = dx*dx + dy*dy
        end

        local pickupRadius = (p.size or 20) / 2
        if distSq < pickupRadius * pickupRadius then
            local amt = g.value
            local ctx = {kind = 'gem', amount = amt, player = p}
            if state and state.augments and state.augments.dispatch then
                state.augments.dispatch(state, 'onPickup', ctx)
            end
            if ctx.cancel then
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'pickupCancelled', ctx)
                end
            else
                amt = ctx.amount or amt
                ctx.amount = amt
                addXp(state, amt)
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'postPickup', ctx)
                end
                table.remove(state.gems, i)
                if state.playSfx then state.playSfx('gem') end
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
            local ctx = nil
            local cancel = false
            if state and state.augments and state.augments.dispatch then
                ctx = {kind = 'chest', amount = 1, player = p, chest = c}
                state.augments.dispatch(state, 'onPickup', ctx)
                if ctx.cancel then
                    state.augments.dispatch(state, 'pickupCancelled', ctx)
                    cancel = true
                end
            end

            if not cancel then
                local rewardType = c and c.rewardType or nil
                local bonus = tonumber(c and c.bonusLevelUps) or 0
                bonus = math.max(0, math.floor(bonus))

                local function makeReq()
                    if rewardType == 'weapon' or rewardType == 'passive' or rewardType == 'mod' or rewardType == 'augment' then
                        return {allowedTypes = {[rewardType] = true}, rewardType = rewardType, source = 'chest', chestKind = c and c.kind}
                    end
                    return nil
                end

                local evolvedWeapon = upgrades.tryEvolveWeapon(state)
                if evolvedWeapon then
                    table.insert(state.texts, {x=p.x, y=p.y-50, text="EVOLVED! " .. evolvedWeapon, color={1, 0.84, 0}, life=2})
                    for _ = 1, bonus do
                        upgrades.queueLevelUp(state, 'chest_bonus', makeReq())
                    end
                    logger.pickup(state, 'chest_evolve')
                else
                    -- 触发一次升级选项（模拟 VS 宝箱随机加成）
                    upgrades.queueLevelUp(state, 'chest', makeReq())
                    for _ = 1, bonus do
                        upgrades.queueLevelUp(state, 'chest_bonus', makeReq())
                    end
                    local suffix = rewardType and (" (" .. string.upper(rewardType) .. ")") or ""
                    local bonusSuffix = (bonus > 0) and (" +" .. tostring(bonus)) or ""
                    table.insert(state.texts, {x=p.x, y=p.y-50, text="CHEST!" .. suffix .. bonusSuffix, color={1, 1, 0}, life=1.5})
                    logger.pickup(state, 'chest_reward')
                end
                if state and state.augments and state.augments.dispatch then
                    ctx = ctx or {kind = 'chest', amount = 1, player = p, chest = c}
                    ctx.evolvedWeapon = evolvedWeapon
                    state.augments.dispatch(state, 'postPickup', ctx)
                end
                table.remove(state.chests, i)
            end
        end
    end
end

function pickups.updateFloorPickups(state, dt)
    local p = state.player
    local radius = (p.size or 20) / 2
    for i = #state.floorPickups, 1, -1 do
        local item = state.floorPickups[i]
        if util.checkCollision({x=p.x, y=p.y, size=p.size}, item) then
            local consume = true
            if item.kind == 'chicken' then
                local amt = 30
                local ctx = {kind = 'chicken', amount = amt, player = p, item = item}
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onPickup', ctx)
                end
                if ctx.cancel then
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'pickupCancelled', ctx)
                    end
                    consume = false
                else
                    amt = ctx.amount or amt
                    ctx.amount = amt
                    p.hp = math.min(p.maxHp, p.hp + amt)
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="+" .. math.floor(amt) .. " HP", color={1,0.7,0}, life=1})
                    logger.pickup(state, 'chicken')
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'postPickup', ctx)
                    end
                end
            elseif item.kind == 'magnet' then
                local ctx = {kind = 'magnet', amount = 1, player = p, item = item}
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onPickup', ctx)
                end
                if ctx.cancel then
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'pickupCancelled', ctx)
                    end
                    consume = false
                end
                if consume then
                    -- 吸取全地图宝石
                    for _, g in ipairs(state.gems) do
                        g.magnetized = true
                    end
                    if #state.gems > 0 and state.playSfx then state.playSfx('gem') end
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="MAGNET!", color={0,0.8,1}, life=1})
                    logger.pickup(state, 'magnet')
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'postPickup', ctx)
                    end
                end
            elseif item.kind == 'bomb' then
                local ctx = {kind = 'bomb', amount = 1, player = p, item = item}
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onPickup', ctx)
                end
                if ctx.cancel then
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'pickupCancelled', ctx)
                    end
                    consume = false
                end
                if consume then
                    -- 只杀屏幕内的敌人
                    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
                    local halfW, halfH = w/2 + 50, h/2 + 50
                    for ei = #state.enemies, 1, -1 do
                        local e = state.enemies[ei]
                        if e.isDummy then goto continue_enemy end
                        if math.abs(e.x - p.x) <= halfW and math.abs(e.y - p.y) <= halfH then
                            e.health = 0
                            e.hp = 0
                        end
                        ::continue_enemy::
                    end
                    state.shakeAmount = 5
                    if state.playSfx then state.playSfx('hit') end
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="BOMB!", color={1,0,0}, life=1})
                    logger.pickup(state, 'bomb')
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'postPickup', ctx)
                    end
                end
            end
            if consume then
                table.remove(state.floorPickups, i)
            end
        end
    end
end

return pickups
