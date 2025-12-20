local upgrades = require('upgrades')
local logger = require('logger')
local campaign = require('campaign')

return function(pickups)
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
                            logger.pickup(state, 'boss_reward')
                            table.remove(state.chests, i)
                            campaign.advanceStage(state)
                            return
                        end

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
                            if state.saveProfile then state.saveProfile(state.profile) end
                        end
                        state.victoryRewards = {
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
    
                    local rewardType = c and c.rewardType or nil

                    -- Chests now always grant a 3-choice MOD selection.
                    upgrades.queueLevelUp(state, 'mod_drop', {
                        allowedTypes = {mod = true, augment = true},
                        source = 'chest'
                    })
                    table.insert(state.texts, {x=p.x, y=p.y-50, text="MOD FOUND!", color={0.2, 1, 0.2}, life=1.5})
                    logger.pickup(state, 'chest_mod')
    
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
    
end
