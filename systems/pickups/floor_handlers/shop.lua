local upgrades = require('systems.upgrades')
local logger = require('core.logger')
local pets = require('gameplay.pets')

local function handleShop(state, p, item)
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
    return true
end

return {
    shop_terminal = handleShop
}
