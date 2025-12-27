local logger = require('core.logger')
local progression = require('systems.progression')

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
    
        local levelsGained = 0
        while p.xp >= p.xpToNextLevel do
            p.level = p.level + 1
            p.xp = p.xp - p.xpToNextLevel
            levelsGained = levelsGained + 1
            
            -- Warframe curve approximation (simplified)
            p.xpToNextLevel = math.floor(p.xpToNextLevel * xpGrowth)
            
            if state and state.augments and state.augments.dispatch then
                state.augments.dispatch(state, 'onLevelUp', {level = p.level, player = p})
            end
    
            -- WF Style: Leveling up just restores stats and shows a notification
            -- No pause, no selection screen
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

        if levelsGained > 0 then
            progression.applyRankUp(state)
            -- 升级回满血量和护盾
            p.hp = p.maxHp or (p.stats and p.stats.maxHp) or 100
            p.shield = p.maxShield or (p.stats and p.stats.maxShield) or 100
            -- 能量只恢复25%，不再回满（让能量成为稀缺资源）
            local maxEnergy = p.maxEnergy or (p.stats and p.stats.maxEnergy) or 100
            p.energy = math.min(maxEnergy, (p.energy or 0) + maxEnergy * 0.25)
        end
    end
    
end
