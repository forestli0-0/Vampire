local handlers = {}

local function merge(source)
    for k, v in pairs(source or {}) do
        handlers[k] = v
    end
end

merge(require('pickups.floor_handlers.combat'))
merge(require('pickups.floor_handlers.mission'))
merge(require('pickups.floor_handlers.pets'))
merge(require('pickups.floor_handlers.shop'))

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

            -- Auto-pickup MOD cards after a short delay
            if item.kind == 'mod_card' and age >= 1.0 then
                local handler = handlers.mod_card
                local consume = true
                if handler then
                    local result = handler(state, p, item)
                    if result ~= nil then
                        consume = result
                    end
                end
                if consume then
                    table.remove(state.floorPickups, i)
                end
                goto continue
            end
            
            -- Distance check with expanded pickup radius
            local dx = p.x - item.x
            local dy = p.y - item.y
            local dist = math.sqrt(dx*dx + dy*dy)
            local itemRadius = (item.size or 16) / 2
            
            if dist < (pickupRadius / 2 + itemRadius) then
                local handler = item.kind and handlers[item.kind] or nil
                local consume = true
                if handler then
                    local result = handler(state, p, item)
                    if result ~= nil then
                        consume = result
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
