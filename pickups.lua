local util = require('util')
local upgrades = require('upgrades')
local logger = require('logger')
local pets = require('pets')
local campaign = require('campaign')

local pickups = {}


-- updateMagnetSpawns removed

local function addXp(state, amount)
    local p = state.player
    p.xp = p.xp + amount
    logger.gainXp(state, amount)
    if state.noLevelUps or state.benchmarkMode then
        return
    end

    -- Warframe-style Rank Cap: 30
    if p.level >= 30 then
        p.xp = 0
        p.xpToNextLevel = 999999999
        return
    end

    while p.xp >= p.xpToNextLevel do
        p.level = p.level + 1
        p.xp = p.xp - p.xpToNextLevel
        
        -- Warframe curve approximation (simplified)
        p.xpToNextLevel = math.floor(p.xpToNextLevel * 1.5)
        
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onLevelUp', {level = p.level, player = p})
        end

        -- WF Style: Leveling up just restores stats and shows a notification
        -- No pause, no selection screen
        p.hp = p.maxHp
        p.energy = p.maxEnergy or 100
        
        if state.texts then
            table.insert(state.texts, {
                x = p.x, 
                y = p.y - 80, 
                text = "RANK UP! " .. p.level, 
                color = {0.8, 1.0, 0.2}, 
                life = 2.0,
                scale = 1.5
            })
        end
        
        state.playSfx('levelup')
        logger.levelUp(state, p.level)
        
        if p.level >= 30 then
            p.xp = 0
            p.xpToNextLevel = 999999999
            break
        end
    end
end

function pickups.updateGems(state, dt)
    local p = state.player
    local now = state.gameTimer or 0
    for i = #state.gems, 1, -1 do
        local g = state.gems[i]
        local valid = true
        
        -- Default to auto-magnet after 1s
        local age = now - (g.spawnTime or 0)
        local autoMagnet = age > 1.0

        local dx = p.x - g.x
        local dy = p.y - g.y
        local distSq = dx*dx + dy*dy

        if autoMagnet or g.magnetized or distSq < p.stats.pickupRange^2 then
            local a = math.atan2(dy, dx)
            local speed = (g.magnetized or autoMagnet) and 900 or 600
            
            -- accelerate towards player
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
                -- Quieter/Faster pickup sound for particles? 
                -- or keep gem sound but maybe pitch shift
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
                -- Stage exit (campaign): advances to the next stage.
                if c and c.kind == 'stage_exit' and state.runMode == 'explore' and state.campaign then
                    logger.pickup(state, 'stage_exit')
                    table.remove(state.chests, i)
                    campaign.advanceStage(state)
                    return
                end

                -- Boss reward chest: ends the run and grants meta rewards (no in-run upgrades).
                if c and c.kind == 'boss_reward' then
                    if state.runMode == 'explore' and state.campaign and not campaign.isFinalBoss(state) then
                        local rewardCurrency = tonumber(c.rewardCurrency) or 100
                        if state.gainGold then
                            state.gainGold(rewardCurrency, {source = 'boss_stage', chest = c, x = p.x, y = p.y - 70, life = 1.2})
                        else
                            state.runCurrency = (state.runCurrency or 0) + rewardCurrency
                            if state.texts then
                                table.insert(state.texts, {x = p.x, y = p.y - 70, text = "+" .. tostring(rewardCurrency) .. " GOLD", color = {0.95, 0.9, 0.45}, life = 1.2})
                            end
                        end
                        logger.pickup(state, 'boss_reward')
                        table.remove(state.chests, i)
                        campaign.advanceStage(state)
                        return
                    end

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
                
                -- VS-Style Evolution removed. 
                -- Generic chests now give a Mod Card (triggering selection) or pure Gold.
                
                if math.random() < 0.3 then
                     -- Mod Drop
                     upgrades.queueLevelUp(state, 'mod_drop', {
                        allowedTypes = {mod = true, augment = true},
                        source = 'chest'
                    })
                    table.insert(state.texts, {x=p.x, y=p.y-50, text="MOD FOUND!", color={0.2, 1, 0.2}, life=1.5})
                    logger.pickup(state, 'chest_mod')
                else
                    -- Gold Reward
                    local gain = 50 + (state.rooms and state.rooms.roomIndex or 1) * 10
                    if state.gainGold then
                        state.gainGold(gain, {source = 'chest', x = p.x, y = p.y - 50, life = 1.0})
                    else
                        state.runCurrency = (state.runCurrency or 0) + gain
                        table.insert(state.texts, {x = p.x, y = p.y - 50, text = "+" .. tostring(gain) .. " GOLD", color = {1, 0.9, 0.4}, life = 1.2})
                    end
                    logger.pickup(state, 'chest_gold')
                end

                if state and state.augments and state.augments.dispatch then
                    ctx = ctx or {kind = 'chest', amount = 1, player = p, chest = c}
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
    if not p then return end
    
    -- Pickup radius: player can pick up items within this range even if not directly touching
    local pickupRadius = (p.size or 28) + 30  -- Increased pickup range for better feel
    
    for i = #state.floorPickups, 1, -1 do
        local item = state.floorPickups[i]
        if not item then goto continue end
        
        -- Distance check with expanded pickup radius
        local dx = p.x - item.x
        local dy = p.y - item.y
        local dist = math.sqrt(dx*dx + dy*dy)
        local itemRadius = (item.size or 16) / 2
        
        if dist < (pickupRadius / 2 + itemRadius) then
            local consume = true
            if item.kind == 'ammo' then
                -- Ammo pickup: refill reserve ammo for all weapons
                local fullRefill = item.fullRefill or false
                local amount = item.amount or 20
                local refilled = false
                local totalGained = 0
                for weaponKey, w in pairs(state.inventory and state.inventory.weapons or {}) do
                    if w.reserve ~= nil then
                        local def = state.catalog and state.catalog[weaponKey]
                        local maxRes = (def and def.base and def.base.maxReserve) or 120
                        if w.reserve < maxRes then
                            local before = w.reserve
                            if fullRefill then
                                w.reserve = maxRes
                            else
                                w.reserve = math.min(maxRes, w.reserve + amount)
                            end
                            totalGained = totalGained + (w.reserve - before)
                            refilled = true
                        end
                    end
                end
                if refilled then
                    local msg = fullRefill and "AMMO FULL!" or ("+" .. totalGained .. " AMMO")
                    table.insert(state.texts, {x=p.x, y=p.y-30, text=msg, color={0.8, 0.9, 1}, life=1})
                    if state.playSfx then state.playSfx('gem') end
                    logger.pickup(state, 'ammo')
                else
                    -- All weapons full, don't consume
                    consume = false
                end
            elseif item.kind == 'energy' then
                -- Energy pickup for abilities
                local amount = item.amount or 25
                local maxEnergy = p.maxEnergy or 100
                local current = p.energy or 0
                if current < maxEnergy then
                    p.energy = math.min(maxEnergy, current + amount)
                    local gained = p.energy - current
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="+"..math.floor(gained).." ENERGY", color={0.4, 0.7, 1}, life=1})
                    if state.playSfx then state.playSfx('gem') end
                    logger.pickup(state, 'energy')
                else
                    consume = false
                end
            elseif item.kind == 'health_orb' then
                -- WF-style health orb
                local amt = item.amount or 15
                local ctx = {kind = 'health_orb', amount = amt, player = p, item = item}
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
                    if p.hp < p.maxHp then
                        p.hp = math.min(p.maxHp, p.hp + amt)
                        table.insert(state.texts, {x=p.x, y=p.y-30, text="+" .. math.floor(amt) .. " HP", color={0.4, 1, 0.4}, life=1})
                        if state.playSfx then state.playSfx('gem') end
                        logger.pickup(state, 'health_orb')
                        if state and state.augments and state.augments.dispatch then
                            state.augments.dispatch(state, 'postPickup', ctx)
                        end
                    else
                        consume = false -- Already at full HP
                    end
                end
            elseif item.kind == 'energy_orb' then
                -- WF-style energy orb (restores ability energy)
                local amt = item.amount or 25
                local maxEnergy = p.maxEnergy or 100
                local current = p.energy or 0
                if current < maxEnergy then
                    p.energy = math.min(maxEnergy, current + amt)
                    local gained = p.energy - current
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="+" .. math.floor(gained) .. " ENERGY", color={0.4, 0.6, 1}, life=1})
                    if state.playSfx then state.playSfx('gem') end
                    logger.pickup(state, 'energy_orb')
                else
                    consume = false -- Already at full energy
                end
            elseif item.kind == 'mod_card' then
                -- WF-style MOD card drop - triggers mod selection
                local ctx = {kind = 'mod_card', amount = 1, player = p, item = item}
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onPickup', ctx)
                end
                if ctx.cancel then
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'pickupCancelled', ctx)
                    end
                    consume = false
                else
                    -- Queue a MOD selection upgrade
                    upgrades.queueLevelUp(state, 'mod_drop', {
                        allowedTypes = {mod = true, augment = true},
                        source = 'enemy_drop'
                    })
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="MOD ACQUIRED!", color={0.9, 0.8, 0.2}, life=1.2})
                    if state.playSfx then state.playSfx('gem') end
                    logger.pickup(state, 'mod_card')
                    if state and state.augments and state.augments.dispatch then
                        state.augments.dispatch(state, 'postPickup', ctx)
                    end
                end
            elseif item.kind == 'life_support' then
                -- Survival mission life support capsule
                local r = state.rooms
                if r and r.lifeSupport then
                    local restore = 20
                    r.lifeSupport = math.min(100, r.lifeSupport + restore)
                    table.insert(state.texts, {x=p.x, y=p.y-30, text="+"..restore.."%生命支援", color={0.4, 0.8, 1}, life=1})
                    if state.playSfx then state.playSfx('gem') end
                    logger.pickup(state, 'life_support')
                else
                    consume = false
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
        ::continue::
    end
end

return pickups
