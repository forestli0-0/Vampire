local logger = require('logger')

return function(pickups)
    function pickups.addXp(state, amount)
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
    
end
