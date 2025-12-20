return function(upgrades)
    function upgrades.getMaxWeapons(state)
        -- WF-style: 2 slots by default (ranged + melee), 3 if character passive unlocks extra
        local base = 2
        if state and state.inventory and state.inventory.canUseExtraSlot then
            base = 3
        end
        local max = (state and state.maxWeaponsPerRun) or base
        max = tonumber(max) or base
        return math.max(1, math.min(3, math.floor(max)))
    end
    

    function upgrades.countWeapons(state)
        local n = 0
        for _, _ in pairs(state.inventory.weapons or {}) do
            n = n + 1
        end
        return n
    end
    

    function upgrades.getWeaponKeys(state)
        local keys = {}
        for k, _ in pairs(state.inventory.weapons or {}) do
            table.insert(keys, k)
        end
        table.sort(keys)
        return keys
    end

    function upgrades.tryEvolveWeapon(state)
        return nil
    end
    
end
