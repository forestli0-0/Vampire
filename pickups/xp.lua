local logger = require('logger')
local progression = require('progression')

return function(pickups)
    function pickups.addXp(state, amount)
        local p = state.player
        local defs = progression.defs or {}
        local rankCap = defs.rankCap or 30
        local xpGrowth = defs.xpGrowth or 1.5
        local xpCapValue = defs.xpCapValue or 999999999

        p.xp = p.xp + amount
        logger.gainXp(state, amount)
        if state.noLevelUps or state.benchmarkMode then
            return
        end
    
        -- Warframe-style Rank Cap
        if p.level >= rankCap then
            p.xp = 0
            p.xpToNextLevel = xpCapValue
            return
        end
    
        while p.xp >= p.xpToNextLevel do
            p.level = p.level + 1
            p.xp = p.xp - p.xpToNextLevel
            
            -- Warframe curve approximation (simplified)
            p.xpToNextLevel = math.floor(p.xpToNextLevel * xpGrowth)
            
            if state and state.augments and state.augments.dispatch then
                state.augments.dispatch(state, 'onLevelUp', {level = p.level, player = p})
            end

            progression.applyRankUp(state)
    
            -- WF Style: Leveling up just restores stats and shows a notification
            -- No pause, no selection screen
            p.hp = p.maxHp or (p.stats and p.stats.maxHp) or 100
            p.shield = p.maxShield or (p.stats and p.stats.maxShield) or 100
            p.energy = p.maxEnergy or (p.stats and p.stats.maxEnergy) or 100
            
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
            
            if p.level >= rankCap then
                p.xp = 0
                p.xpToNextLevel = xpCapValue
                break
            end
        end
    end
    
end
