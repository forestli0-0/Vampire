-- =============================================================================
-- 顿帧系统 (Hitstop System)
-- =============================================================================
-- 攻击命中时短暂暂停游戏，产生"重击感"
-- 参考: Hades, 元气骑士, Warframe 等商业游戏的打击感实现
-- =============================================================================

local hitstop = {
    active = false,       -- 当前是否处于顿帧状态
    timer = 0,            -- 当前已经暂停的时间
    duration = 0,         -- 本次顿帧的总时长
    
    -- 可选配置：哪些实体受顿帧影响
    affectsPlayer = false,   -- 玩家是否暂停（通常不暂停，保持控制感）
    affectsEnemies = true,   -- 敌人是否暂停
    affectsProjectiles = false, -- 子弹是否暂停
    affectsEffects = false,  -- 特效是否暂停

    -- 顿帧期间的视觉增强
    screenShake = 0,      -- 附加屏幕震动
    timeScale = 0.05,     -- 顿帧期间的时间缩放（不是完全停止）
    
    -- 队列系统：避免顿帧叠加过长
    queue = {},
    maxQueueSize = 3,
    minInterval = 0.08,   -- 增加最小间隔，匹配主流步枪 CD
    lastTriggerTime = 0,
}

-- =============================================================================
-- 预设配置
-- =============================================================================

hitstop.presets = {
    -- 轻击命中
    light = {
        duration = 0.03,        -- 缩短到 0.03s，确保 0.08s CD 的武器有恢复空间
        screenShake = 1.5,
        timeScale = 0.1,        -- 减弱减速程度
        affectsPlayer = false,
        noGlobalSlowdown = true,
    },
    -- 重击命中
    heavy = {
        duration = 0.08,        -- 缩短到 0.08s
        screenShake = 4,
        timeScale = 0.05,
        affectsPlayer = false,
    },
    -- 终结技命中
    finisher = {
        duration = 0.14,
        screenShake = 6,
        timeScale = 0.01,
        affectsPlayer = true,
    },
    -- 暴击命中
    critical = {
        duration = 0.08,
        screenShake = 3,
        timeScale = 0.03,
        affectsPlayer = false,
    },
    -- Boss受击
    boss_hit = {
        duration = 0.04,        -- 关键：必须显著小于 Braton 的 0.08s CD
        screenShake = 3,
        timeScale = 0.05,       -- 提高基础速度，避免完全静止
        affectsPlayer = false,
        noGlobalSlowdown = true, -- 新增标志：指示是否跳过全局敌人减速
    },
    -- 玩家受击（短暂，增加紧迫感）
    player_hit = {
        duration = 0.04,
        screenShake = 3,
        timeScale = 0.1,
        affectsPlayer = true,
        affectsEnemies = false,
    },
}

-- =============================================================================
-- 核心函数
-- =============================================================================

--- 触发顿帧
---@param preset string|nil 预设名称 ('light', 'heavy', 'finisher', 'critical', 'boss_hit', 'player_hit')
---@param opts table|nil 自定义选项，会覆盖预设
function hitstop.trigger(preset, opts)
    local now = love.timer.getTime()
    
    -- 检查最小间隔
    if now - hitstop.lastTriggerTime < hitstop.minInterval then
        return false
    end
    
    -- 获取预设或默认值
    local config = {}
    if preset and hitstop.presets[preset] then
        for k, v in pairs(hitstop.presets[preset]) do
            config[k] = v
        end
    else
        config.duration = 0.06
        config.screenShake = 2
        config.timeScale = 0.05
        config.affectsPlayer = false
    end
    
    -- 应用自定义选项
    if opts then
        for k, v in pairs(opts) do
            config[k] = v
        end
    end
    
    -- 如果当前已经在顿帧，比较优先级
    if hitstop.active then
        -- 新的顿帧时长更长才替换
        if config.duration <= hitstop.duration - hitstop.timer then
            return false
        end
    end
    
    -- 激活顿帧
    hitstop.active = true
    hitstop.timer = 0
    hitstop.duration = config.duration
    hitstop.timeScale = config.timeScale or 0.05
    hitstop.screenShake = config.screenShake or 0
    hitstop.affectsPlayer = config.affectsPlayer or false
    hitstop.affectsEnemies = config.affectsEnemies ~= false
    hitstop.affectsProjectiles = config.affectsProjectiles or false
    hitstop.affectsEffects = config.affectsEffects or false
    hitstop.noGlobalSlowdown = config.noGlobalSlowdown or false
    hitstop.lastTriggerTime = now
    
    return true
end

--- 更新顿帧状态（每帧调用）
---@param dt number delta time
---@return number 调整后的 dt（给需要受影响的系统使用）
function hitstop.update(dt)
    if not hitstop.active then
        return dt
    end
    
    -- 顿帧期间使用真实时间更新计时器
    hitstop.timer = hitstop.timer + dt
    
    if hitstop.timer >= hitstop.duration then
        hitstop.active = false
        hitstop.timer = 0
        hitstop.duration = 0
        return dt
    end
    
    -- 返回缩放后的 dt
    return dt * hitstop.timeScale
end

--- 检查某个实体类型是否应该暂停
---@param entityType string 实体类型 ('player', 'enemy', 'projectile', 'effect')
---@return boolean 是否应该暂停
function hitstop.shouldPause(entityType)
    if not hitstop.active then
        return false
    end
    
    if entityType == 'player' then
        return hitstop.affectsPlayer
    elseif entityType == 'enemy' then
        return hitstop.affectsEnemies
    elseif entityType == 'projectile' then
        return hitstop.affectsProjectiles
    elseif entityType == 'effect' then
        return hitstop.affectsEffects
    end
    
    return false
end

--- 获取当前顿帧进度 (0-1)
---@return number 进度，0=刚开始，1=即将结束
function hitstop.getProgress()
    if not hitstop.active or hitstop.duration <= 0 then
        return 0
    end
    return hitstop.timer / hitstop.duration
end

--- 获取当前屏幕震动量
---@return number 震动强度
function hitstop.getScreenShake()
    if not hitstop.active then
        return 0
    end
    -- 震动随时间衰减
    local progress = hitstop.getProgress()
    return hitstop.screenShake * (1 - progress)
end

--- 检查是否处于活动状态
---@return boolean
function hitstop.isActive()
    return hitstop.active
end

--- 强制结束顿帧
function hitstop.cancel()
    hitstop.active = false
    hitstop.timer = 0
    hitstop.duration = 0
end

--- 获取调试信息
---@return table
function hitstop.getDebugInfo()
    return {
        active = hitstop.active,
        timer = hitstop.timer,
        duration = hitstop.duration,
        progress = hitstop.getProgress(),
        timeScale = hitstop.timeScale,
    }
end

return hitstop
