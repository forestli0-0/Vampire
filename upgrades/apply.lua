local weapons = require('weapons')
local logger = require('logger')
local pets = require('pets')

local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

return function(upgrades)
    function upgrades.applyUpgrade(state, opt)
        -- Track upgrade count for starting guarantee system
        state.upgradeCount = (state.upgradeCount or 0) + 1
        
        if opt.evolveFrom then
            -- This should be unreachable now, but kept safe
            return
        elseif opt.type == 'weapon' then
            if not state.inventory.weapons[opt.key] then
                weapons.addWeapon(state, opt.key, opt.assignOwner)
                logger.upgrade(state, opt, 1)
                dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
            else
                local w = state.inventory.weapons[opt.key]
                w.level = w.level + 1
                if opt.def.onUpgrade then opt.def.onUpgrade(w.stats) end
                logger.upgrade(state, opt, w.level)
                dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = w.level})
            end
        elseif opt.type == 'passive' then
            -- DEPRECATED: Passives removed.
            return
        elseif opt.type == 'mod' then
            -- Mods are loadout-only and apply per-weapon when equipped.
            -- If enabled as an in-run reward (debug), treat this as ranking up the mod and refresh weapon loadouts.
            state.profile = state.profile or {}
            state.profile.modRanks = state.profile.modRanks or {}
            state.profile.ownedMods = state.profile.ownedMods or {}
            state.profile.ownedMods[opt.key] = true
    
            local cur = state.profile.modRanks[opt.key]
            if cur == nil then cur = 1 end
            cur = cur + 1
            local max = opt.def and opt.def.maxLevel
            if max and cur > max then cur = max end
            state.profile.modRanks[opt.key] = cur
            if state.applyPersistentMods then state.applyPersistentMods() end
    
            logger.upgrade(state, opt, cur)
            if opt.def.onUpgrade then opt.def.onUpgrade() end
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur})
        elseif opt.type == 'augment' then
            state.inventory.augments = state.inventory.augments or {}
            state.inventory.augmentOrder = state.inventory.augmentOrder or {}
            if not state.inventory.augments[opt.key] then
                state.inventory.augments[opt.key] = 0
                table.insert(state.inventory.augmentOrder, opt.key)
            end
            state.inventory.augments[opt.key] = state.inventory.augments[opt.key] + 1
            logger.upgrade(state, opt, state.inventory.augments[opt.key])
            if opt.def.onUpgrade then opt.def.onUpgrade() end
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = state.inventory.augments[opt.key]})
        elseif opt.type == 'pet_module' then
            local pet = pets.getActive(state)
            local def = opt.def or (state.catalog and state.catalog[opt.key]) or nil
            local modId = def and def.moduleId
            if pet and modId and (pet.module or 'default') == 'default' then
                pet.module = modId
                logger.upgrade(state, opt, 1)
                if state.texts then
                    table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = "PET MODULE: " .. tostring(def.name or opt.key), color = {0.85, 0.95, 1.0}, life = 1.3})
                end
                dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
            end
        elseif opt.type == 'pet_upgrade' then
            state.pets = state.pets or {}
            state.pets.upgrades = state.pets.upgrades or {}
            local cur = state.pets.upgrades[opt.key] or 0
            cur = cur + 1
            local max = opt.def and opt.def.maxLevel
            if max and cur > max then cur = max end
            state.pets.upgrades[opt.key] = cur
            logger.upgrade(state, opt, cur)
            if pets and pets.recompute then pets.recompute(state) end
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur})
        elseif opt.type == 'pet' then
            local pet = pets.setActive(state, opt.key, {swap = true})
            if pet then
                logger.upgrade(state, opt, 1)
                dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1})
            end
        end
    end
    
end
