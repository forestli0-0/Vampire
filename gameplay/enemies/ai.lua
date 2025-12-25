-- enemies/ai.lua
-- 敌人AI状态机模块
-- 负责AI行为决策、状态转换和移动策略

local enemyDefs = require('data.defs.enemies')

local ai = {}

--------------------------------------------------------------------------------
-- AI 状态常量
--------------------------------------------------------------------------------

ai.STATES = {
    IDLE = 'idle',       -- 未发现玩家，原地待机
    CHASE = 'chase',     -- 追击玩家
    ATTACK = 'attack',   -- 正在执行攻击
    RETREAT = 'retreat', -- 受伤后撤退
    KITING = 'kiting',   -- 保持距离射击（远程敌人）
    BERSERK = 'berserk', -- 低血量狂暴（Boss）
}

-- 默认AI行为配置
local DEFAULT_AI_BEHAVIOR = {
    type = 'melee',
    retreatThreshold = 0.25,   -- 血量低于25%时考虑撤退
    retreatDuration = 1.2,     -- 撤退持续时间（秒）
    retreatDistance = 80,      -- 撤退目标距离
    retreatCooldown = 5.0,     -- 撤退冷却时间
}

--------------------------------------------------------------------------------
-- AI 行为配置获取
--------------------------------------------------------------------------------

--- 获取敌人AI行为配置
-- @param e 敌人实体
-- @return table AI行为配置表
function ai.getBehavior(e)
    local def = enemyDefs[e.kind] or {}
    local behavior = def.aiBehavior or {}
    -- 合并默认配置
    return {
        type = behavior.type or DEFAULT_AI_BEHAVIOR.type,
        retreatThreshold = behavior.retreatThreshold or DEFAULT_AI_BEHAVIOR.retreatThreshold,
        retreatDuration = behavior.retreatDuration or DEFAULT_AI_BEHAVIOR.retreatDuration,
        retreatDistance = behavior.retreatDistance or DEFAULT_AI_BEHAVIOR.retreatDistance,
        retreatCooldown = behavior.retreatCooldown or DEFAULT_AI_BEHAVIOR.retreatCooldown,
        noRetreat = behavior.noRetreat or false,
        preferredRange = behavior.preferredRange,  -- 远程敌人理想距离
        kiteRange = behavior.kiteRange,            -- 开始风筝的距离阈值
        berserkThreshold = behavior.berserkThreshold or 0.25,
        berserkSpeedMult = behavior.berserkSpeedMult or 1.4,
        berserkDamageMult = behavior.berserkDamageMult or 1.25,
    }
end

--------------------------------------------------------------------------------
-- AI 状态转换
--------------------------------------------------------------------------------

--- 设置AI状态
-- @param e 敌人实体
-- @param newState 新状态
-- @param reason 转换原因（用于调试）
function ai.setState(e, newState, reason)
    if e.aiState ~= newState then
        e.prevAiState = e.aiState
        e.aiState = newState
        e.aiStateTimer = 0
        e.aiStateReason = reason
        -- 调试日志已注释
        -- logger.debug('[AI] ' .. (e.kind or 'enemy') .. ' -> ' .. newState .. ' (' .. (reason or '') .. ')')
    end
end

--------------------------------------------------------------------------------
-- AI 状态判断函数
--------------------------------------------------------------------------------

--- 检查是否应该撤退
-- @param e 敌人实体
-- @param behavior AI行为配置
-- @param recentDamage 最近受到的伤害
-- @return boolean 是否应该撤退
function ai.shouldRetreat(e, behavior, recentDamage)
    -- Boss不撤退（进入狂暴）
    if e.isBoss then return false end
    -- 配置为不撤退的敌人
    if behavior.noRetreat then return false end
    -- 已经在撤退中
    if e.aiState == ai.STATES.RETREAT then return false end
    -- 撤退冷却中
    if (e.retreatCooldownTimer or 0) > 0 then return false end
    
    local hpRatio = (e.health or 0) / (e.maxHealth or 1)
    local threshold = behavior.retreatThreshold or 0.25
    
    -- 血量低于阈值时撤退
    if hpRatio < threshold then
        return true
    end
    
    -- 短时间内受到大量伤害时也撤退
    if recentDamage and recentDamage > (e.maxHealth or 1) * 0.3 then
        return true
    end
    
    return false
end

--- 检查远程敌人是否应该风筝
-- @param e 敌人实体
-- @param distToPlayer 到玩家的距离
-- @param behavior AI行为配置
-- @return boolean 是否应该风筝
function ai.shouldKite(e, distToPlayer, behavior)
    -- 只有远程类型敌人会风筝
    if behavior.type ~= 'ranged' then return false end
    -- 没有配置风筝距离
    if not behavior.kiteRange then return false end
    -- 已经在撤退中
    if e.aiState == ai.STATES.RETREAT then return false end
    
    -- 玩家太近时开始风筝
    return distToPlayer < behavior.kiteRange
end

--- 检查Boss是否应该进入狂暴
-- @param e 敌人实体
-- @param behavior AI行为配置
-- @return boolean 是否应该进入狂暴
function ai.shouldBerserk(e, behavior)
    if not e.isBoss then return false end
    if e.aiState == ai.STATES.BERSERK then return false end
    if e.berserkTriggered then return false end  -- 只触发一次
    
    local hpRatio = (e.health or 0) / (e.maxHealth or 1)
    return hpRatio < (behavior.berserkThreshold or 0.25)
end

--------------------------------------------------------------------------------
-- AI 移动策略
--------------------------------------------------------------------------------

--- 计算追击移动方向
-- @param e 敌人实体
-- @param targetX 目标X坐标
-- @param targetY 目标Y坐标
-- @return dx, dy 移动方向向量（归一化）
function ai.getChaseDirection(e, targetX, targetY)
    local dx = targetX - e.x
    local dy = targetY - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
        return dx / dist, dy / dist
    end
    return 0, 0
end

--- 计算撤退移动方向（远离目标）
-- @param e 敌人实体
-- @param targetX 目标X坐标
-- @param targetY 目标Y坐标
-- @return dx, dy 移动方向向量（归一化）
function ai.getRetreatDirection(e, targetX, targetY)
    local dx = e.x - targetX
    local dy = e.y - targetY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
        return dx / dist, dy / dist
    end
    -- 如果刚好在目标位置，随机选择一个方向
    local ang = math.random() * math.pi * 2
    return math.cos(ang), math.sin(ang)
end

--- 计算风筝移动方向（保持距离的横向移动）
-- @param e 敌人实体
-- @param targetX 目标X坐标
-- @param targetY 目标Y坐标
-- @param preferredRange 理想距离
-- @return dx, dy 移动方向向量（归一化）
function ai.getKiteDirection(e, targetX, targetY, preferredRange)
    local dx = e.x - targetX
    local dy = e.y - targetY
    local dist = math.sqrt(dx * dx + dy * dy)
    
    if dist < 1 then
        local ang = math.random() * math.pi * 2
        return math.cos(ang), math.sin(ang)
    end
    
    -- 计算当前距离与理想距离的差异
    local range = preferredRange or 200
    
    if dist < range * 0.7 then
        -- 太近，后退
        return dx / dist, dy / dist
    elseif dist > range * 1.3 then
        -- 太远，接近
        return -dx / dist, -dy / dist
    else
        -- 在范围内，横向移动
        -- 选择一个垂直于目标方向的移动向量
        local perpX = -dy / dist
        local perpY = dx / dist
        -- 随机选择左或右
        if not e._kiteDir then
            e._kiteDir = math.random() < 0.5 and 1 or -1
        end
        return perpX * e._kiteDir, perpY * e._kiteDir
    end
end

return ai
