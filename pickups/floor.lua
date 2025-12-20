local upgrades = require('upgrades')
local logger = require('logger')
local pets = require('pets')

return function(pickups)
    function pickups.updateFloorPickups(state, dt)
        local p = state.player
        if not p then return end
        
        -- Pickup lifetime constants (WF-style)
        local PICKUP_LIFETIME = 60       -- Seconds before despawn
        local PICKUP_WARN_TIME = 45      -- Seconds before starting to flash
        local now = love.timer.getTime()
        
        -- Pickup radius: player can pick up items within this range
        local pickupRadius = (p.size or 28) + 30
        
        for i = #state.floorPickups, 1, -1 do
            local item = state.floorPickups[i]
            if not item then goto continue end
            
            -- Initialize spawn time if not set
            if not item.spawnTime then
                item.spawnTime = now
            end
            
            -- Only health_orb and energy_orb can despawn
            local canDespawn = (item.kind == 'health_orb' or item.kind == 'energy_orb')
            local age = now - item.spawnTime
            
            if canDespawn and age >= PICKUP_LIFETIME then
                -- Despawn expired orb
                table.remove(state.floorPickups, i)
                goto continue
            end
            
            -- Set flashing state for warning (orbs only)
            if canDespawn and age >= PICKUP_WARN_TIME then
                item.flashing = true
            end
            
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
    
end
