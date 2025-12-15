local util = require('util')
local upgrades = require('upgrades')
local logger = require('logger')
local pets = require('pets')

local pickups = {}

function pickups.updateMagnetSpawns(state, dt)
    if not state.magnetTimer then return end
    if state.runMode == 'rooms' then
        return
    end
    if state.runMode == 'explore' or (state.world and state.world.enabled) then
        return
    end
    state.magnetTimer = state.magnetTimer - dt
    if state.magnetTimer <= 0 then
        local dist = math.random(450, 750)
        local ang = math.random() * math.pi * 2
        local px, py = state.player.x, state.player.y
        local kinds = {'magnet', 'chicken'}
        local kind = kinds[math.random(#kinds)]
        local x = px + math.cos(ang) * dist
        local y = py + math.sin(ang) * dist
        local world = state.world
        if world and world.enabled and world.adjustToWalkable then
            x, y = world:adjustToWalkable(x, y, 14)
        end
        table.insert(state.floorPickups, {
            x = x,
            y = y,
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
        local giveUpgrade = true
        if state.runMode == 'rooms' and state.rooms and state.rooms.xpGivesUpgrades == false then
            giveUpgrade = false
        end
        if giveUpgrade then
            upgrades.queueLevelUp(state, 'xp')
        end
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
                -- Boss reward chest: ends the run and grants meta rewards (no in-run upgrades).
                if c and c.kind == 'boss_reward' then
                    local rewardCurrency = tonumber(c.rewardCurrency) or 100
                    local newModKey = nil
                    if state.profile and state.catalog then
                        state.profile.ownedMods = state.profile.ownedMods or {}
                        local locked = {}
                        for key, def in pairs(state.catalog) do
                            if def.type == 'mod' and not state.profile.ownedMods[key] then
                                table.insert(locked, key)
                            end
                        end
                        if #locked > 0 then
                            newModKey = locked[math.random(#locked)]
                            state.profile.ownedMods[newModKey] = true
                        end
                        state.profile.currency = (state.profile.currency or 0) + rewardCurrency
                        if state.saveProfile then state.saveProfile(state.profile) end
                    end
                    state.victoryRewards = {
                        currency = rewardCurrency,
                        newModKey = newModKey,
                        newModName = (newModKey and state.catalog and state.catalog[newModKey] and state.catalog[newModKey].name) or nil
                    }
                    state.gameState = 'GAME_CLEAR'
                    state.directorState = state.directorState or {}
                    state.directorState.bossDefeated = true
                    if state and state.augments and state.augments.dispatch then
                        ctx = ctx or {kind = 'chest', amount = 1, player = p, chest = c}
                        ctx.bossReward = true
                        state.augments.dispatch(state, 'postPickup', ctx)
                    end
                    logger.pickup(state, 'boss_reward')
                    table.remove(state.chests, i)
                    goto continue_chest
                end

                -- Room-mode economy: reward run currency on room reward chests (shop spend).
                if state and not state.benchmarkMode and c and c.kind == 'room_reward' then
                    local room = tonumber(c.room) or (state.rooms and state.rooms.roomIndex) or 1
                    local gain = 18 + math.floor(room * 6)
                    if c.roomKind == 'elite' then gain = gain + 16 end
                    if state.gainGold then
                        state.gainGold(gain, {source = 'room_reward', chest = c, x = p.x, y = p.y - 70, life = 1.2})
                    else
                        state.runCurrency = (state.runCurrency or 0) + gain
                        table.insert(state.texts, {x = p.x, y = p.y - 70, text = "+" .. tostring(gain) .. " GOLD", color = {0.95, 0.9, 0.45}, life = 1.2})
                    end
                end

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
        ::continue_chest::
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
            elseif item.kind == 'pet_contract' then
                local current = pets.getActive(state)
                upgrades.queueLevelUp(state, 'pet_contract', {
                    allowedTypes = {pet = true},
                    excludePetKey = current and current.key or nil,
                    source = 'special_room',
                    roomKind = item.roomKind
                })
                logger.pickup(state, 'pet_contract')
            elseif item.kind == 'pet_module_chip' then
                local pet = pets.getActive(state)
                if not pet then
                    consume = false
                    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No active pet", color = {1, 0.6, 0.6}, life = 1.0})
                elseif (pet.module or 'default') ~= 'default' then
                    consume = false
                    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "Pet module already installed", color = {1, 0.75, 0.55}, life = 1.0})
                else
                    upgrades.queueLevelUp(state, 'pet_module_chip', {allowedTypes = {pet_module = true}, source = 'pet_chip'})
                    logger.pickup(state, 'pet_module_chip')
                end
            elseif item.kind == 'pet_upgrade_chip' then
                local pet = pets.getActive(state)
                if not pet then
                    consume = false
                    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No active pet", color = {1, 0.6, 0.6}, life = 1.0})
                else
                    upgrades.queueLevelUp(state, 'pet_upgrade_chip', {allowedTypes = {pet_upgrade = true}, source = 'pet_chip'})
                    logger.pickup(state, 'pet_upgrade_chip')
                end
            elseif item.kind == 'shop_terminal' then
                local room = (state.rooms and state.rooms.roomIndex) or 1

                local function buy(cost)
                    cost = math.floor(cost or 0)
                    if cost <= 0 then return true end
                    if (state.runCurrency or 0) < cost then return false end
                    state.runCurrency = (state.runCurrency or 0) - cost
                    return true
                end

                local pet = pets.getActive(state)
                local swapCost = 55 + room * 12
                local petHealCost = 25 + room * 6
                local medkitCost = 18 + room * 5
                local petModuleCost = 40 + room * 10
                local petUpgradeCost = 32 + room * 8

                local function setMsg(msg)
                    state.shop = state.shop or {}
                    state.shop.message = msg
                end

                state.shop = {
                    title = "SHOP",
                    message = nil,
                    options = {
                        {
                            id = 'pet_swap',
                            name = "Pet Contract",
                            desc = "Swap / adopt a pet",
                            cost = swapCost,
                            enabled = true,
                            onBuy = function(st)
                                if not buy(swapCost) then setMsg("Not enough GOLD") return end
                                st.shop = nil
                                local current = pets.getActive(st)
                                upgrades.queueLevelUp(st, 'shop_pet', {
                                    allowedTypes = {pet = true},
                                    excludePetKey = current and current.key or nil,
                                    source = 'shop'
                                })
                            end
                        },
                        {
                            id = 'pet_heal',
                            name = "Pet Treat",
                            desc = "Heal your active pet",
                            cost = petHealCost,
                            enabled = (pet ~= nil) and ((pet.hp or 0) < (pet.maxHp or 0)),
                            disabledReason = (pet == nil) and "No active pet" or "Pet already full",
                            onBuy = function(st, opt, shop)
                                local p = pets.getActive(st)
                                if not p then setMsg("No active pet") return end
                                if (p.hp or 0) >= (p.maxHp or 0) then setMsg("Pet already full") return end
                                if not buy(petHealCost) then setMsg("Not enough GOLD") return end
                                local heal = math.max(10, math.floor((p.maxHp or 0) * 0.55))
                                p.hp = math.min(p.maxHp or p.hp, (p.hp or 0) + heal)
                                table.insert(st.texts, {x = st.player.x, y = st.player.y - 60, text = "Pet +" .. tostring(heal), color = {0.55, 1.0, 0.55}, life = 1.1})
                                st.shop = nil
                                st.gameState = 'PLAYING'
                            end
                        },
                        {
                            id = 'medkit',
                            name = "Medkit",
                            desc = "Heal the player",
                            cost = medkitCost,
                            enabled = (p.hp or 0) < (p.maxHp or 0),
                            disabledReason = "HP already full",
                            onBuy = function(st)
                                if (st.player.hp or 0) >= (st.player.maxHp or 0) then setMsg("HP already full") return end
                                if not buy(medkitCost) then setMsg("Not enough GOLD") return end
                                local heal = 35 + room * 2
                                st.player.hp = math.min(st.player.maxHp, st.player.hp + heal)
                                table.insert(st.texts, {x = st.player.x, y = st.player.y - 30, text = "+" .. tostring(heal) .. " HP", color = {1, 0.7, 0}, life = 1.0})
                                st.shop = nil
                                st.gameState = 'PLAYING'
                            end
                        },
                        {
                            id = 'pet_module',
                            name = "Pet Module",
                            desc = "Install a module (non-replaceable)",
                            cost = petModuleCost,
                            enabled = (pet ~= nil) and ((pet.module or 'default') == 'default'),
                            disabledReason = (pet == nil) and "No active pet" or "Module already installed",
                            onBuy = function(st)
                                local active = pets.getActive(st)
                                if not active then setMsg("No active pet") return end
                                if (active.module or 'default') ~= 'default' then setMsg("Module already installed") return end
                                if not buy(petModuleCost) then setMsg("Not enough GOLD") return end
                                st.shop = nil
                                upgrades.queueLevelUp(st, 'shop_pet_module', {allowedTypes = {pet_module = true}, source = 'shop'})
                            end
                        },
                        {
                            id = 'pet_upgrade',
                            name = "Pet Upgrade",
                            desc = "Upgrade your pet (stackable)",
                            cost = petUpgradeCost,
                            enabled = (pet ~= nil),
                            disabledReason = "No active pet",
                            onBuy = function(st)
                                local active = pets.getActive(st)
                                if not active then setMsg("No active pet") return end
                                if not buy(petUpgradeCost) then setMsg("Not enough GOLD") return end
                                st.shop = nil
                                upgrades.queueLevelUp(st, 'shop_pet_upgrade', {allowedTypes = {pet_upgrade = true}, source = 'shop'})
                            end
                        }
                    }
                }

                -- Always open the shop; leaving is handled in `main.lua` (0/esc).
                state.gameState = 'SHOP'
                logger.pickup(state, 'shop_terminal')
            elseif item.kind == 'pet_revive' then
                local revived = pets.reviveLost(state)
                if revived then
                    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "Pet revived: " .. tostring(revived.name), color = {0.75, 0.95, 1.0}, life = 1.2})
                    logger.pickup(state, 'pet_revive')
                else
                    consume = false
                    table.insert(state.texts, {x = p.x, y = p.y - 30, text = "No pet to revive", color = {1, 0.6, 0.6}, life = 1.0})
                end
            end
            if consume then
                table.remove(state.floorPickups, i)
            end
        end
    end
end

return pickups
