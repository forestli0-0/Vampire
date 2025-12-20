return function(pickups)
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
                    pickups.addXp(state, amt)
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
    
end
