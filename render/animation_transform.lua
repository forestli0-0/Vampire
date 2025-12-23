-- =============================================================================
-- 动画变换系统 (Animation Transform System)
-- =============================================================================
-- 实现挤压拉伸 (Squash & Stretch)、旋转、弹簧物理等变换效果
-- 用于增加角色和物体的弹性感和重量感
-- =============================================================================

local transform = {}

-- =============================================================================
-- 创建新的变换实例
-- =============================================================================

--- 创建一个新的变换对象
---@return table 变换实例
function transform.new()
    return {
        -- 当前值
        scaleX = 1,
        scaleY = 1,
        rotation = 0,
        offsetX = 0,
        offsetY = 0,
        
        -- 目标值
        targetScaleX = 1,
        targetScaleY = 1,
        targetRotation = 0,
        targetOffsetX = 0,
        targetOffsetY = 0,
        
        -- 弹簧物理参数
        stiffness = 300,   -- 刚度（越大恢复越快）
        damping = 18,      -- 阻尼（越大振荡越少）
        
        -- 速度（用于弹簧物理）
        velocityScaleX = 0,
        velocityScaleY = 0,
        velocityRotation = 0,
        velocityOffsetX = 0,
        velocityOffsetY = 0,
        
        -- 是否使用弹簧物理（false则使用线性插值）
        useSpring = true,
        
        -- 线性插值速度（当 useSpring = false 时使用）
        lerpSpeed = 15,
    }
end

-- =============================================================================
-- 弹簧物理更新
-- =============================================================================

local function springUpdate(current, target, velocity, stiffness, damping, dt)
    local diff = target - current
    local acceleration = diff * stiffness - velocity * damping
    local newVelocity = velocity + acceleration * dt
    local newValue = current + newVelocity * dt
    return newValue, newVelocity
end

local function lerpUpdate(current, target, speed, dt)
    local diff = target - current
    local change = diff * math.min(1, speed * dt)
    return current + change, 0
end

--- 更新变换（每帧调用）
---@param t table 变换实例
---@param dt number delta time
function transform.update(t, dt)
    if t.useSpring then
        -- 弹簧物理更新
        t.scaleX, t.velocityScaleX = springUpdate(t.scaleX, t.targetScaleX, t.velocityScaleX, t.stiffness, t.damping, dt)
        t.scaleY, t.velocityScaleY = springUpdate(t.scaleY, t.targetScaleY, t.velocityScaleY, t.stiffness, t.damping, dt)
        t.rotation, t.velocityRotation = springUpdate(t.rotation, t.targetRotation, t.velocityRotation, t.stiffness, t.damping, dt)
        t.offsetX, t.velocityOffsetX = springUpdate(t.offsetX, t.targetOffsetX, t.velocityOffsetX, t.stiffness, t.damping, dt)
        t.offsetY, t.velocityOffsetY = springUpdate(t.offsetY, t.targetOffsetY, t.velocityOffsetY, t.stiffness, t.damping, dt)
    else
        -- 线性插值更新
        t.scaleX, t.velocityScaleX = lerpUpdate(t.scaleX, t.targetScaleX, t.lerpSpeed, dt)
        t.scaleY, t.velocityScaleY = lerpUpdate(t.scaleY, t.targetScaleY, t.lerpSpeed, dt)
        t.rotation, t.velocityRotation = lerpUpdate(t.rotation, t.targetRotation, t.lerpSpeed, dt)
        t.offsetX, t.velocityOffsetX = lerpUpdate(t.offsetX, t.targetOffsetX, t.lerpSpeed, dt)
        t.offsetY, t.velocityOffsetY = lerpUpdate(t.offsetY, t.targetOffsetY, t.lerpSpeed, dt)
    end
end

-- =============================================================================
-- 挤压拉伸效果
-- =============================================================================

--- 挤压效果（水平拉宽，垂直压扁）
--- 用于：落地、被击中、重击蓄力
---@param t table 变换实例
---@param intensity number 强度 (0-1)
---@param instant boolean|nil 是否立即应用（否则作为目标值）
function transform.squash(t, intensity, instant)
    intensity = math.max(0, math.min(1, intensity or 0.5))
    local sx = 1 + intensity * 0.3   -- 水平拉宽
    local sy = 1 - intensity * 0.25  -- 垂直压扁
    
    if instant then
        t.scaleX = sx
        t.scaleY = sy
        t.velocityScaleX = 0
        t.velocityScaleY = 0
    else
        t.targetScaleX = sx
        t.targetScaleY = sy
    end
end

--- 拉伸效果（水平压窄，垂直拉高）
--- 用于：跳跃、冲刺起步、攻击挥砍
---@param t table 变换实例
---@param intensity number 强度 (0-1)
---@param instant boolean|nil 是否立即应用
function transform.stretch(t, intensity, instant)
    intensity = math.max(0, math.min(1, intensity or 0.5))
    local sx = 1 - intensity * 0.2   -- 水平压窄
    local sy = 1 + intensity * 0.25  -- 垂直拉高
    
    if instant then
        t.scaleX = sx
        t.scaleY = sy
        t.velocityScaleX = 0
        t.velocityScaleY = 0
    else
        t.targetScaleX = sx
        t.targetScaleY = sy
    end
end

--- 重置到正常状态
---@param t table 变换实例
---@param instant boolean|nil 是否立即重置
function transform.reset(t, instant)
    if instant then
        t.scaleX = 1
        t.scaleY = 1
        t.rotation = 0
        t.offsetX = 0
        t.offsetY = 0
        t.velocityScaleX = 0
        t.velocityScaleY = 0
        t.velocityRotation = 0
        t.velocityOffsetX = 0
        t.velocityOffsetY = 0
    end
    t.targetScaleX = 1
    t.targetScaleY = 1
    t.targetRotation = 0
    t.targetOffsetX = 0
    t.targetOffsetY = 0
end

-- =============================================================================
-- 预设动画效果
-- =============================================================================

--- 受击反馈（向受击方向挤压，然后恢复）
---@param t table 变换实例
---@param hitDirX number 受击方向X
---@param hitDirY number 受击方向Y
---@param intensity number 强度 (0-1)
function transform.hitReaction(t, hitDirX, hitDirY, intensity)
    intensity = intensity or 0.6
    
    -- 向受击方向偏移
    local len = math.sqrt(hitDirX * hitDirX + hitDirY * hitDirY)
    if len > 0.001 then
        t.offsetX = hitDirX / len * intensity * 4
        t.offsetY = hitDirY / len * intensity * 4
    end
    
    -- 轻微挤压
    transform.squash(t, intensity * 0.4, true)
    
    -- 设置恢复目标
    t.targetOffsetX = 0
    t.targetOffsetY = 0
    t.targetScaleX = 1
    t.targetScaleY = 1
end

--- 跳跃起步效果
---@param t table 变换实例
function transform.jumpStart(t)
    -- 先挤压（蓄力）
    transform.squash(t, 0.4, true)
    -- 目标拉伸（起跳）
    transform.stretch(t, 0.5)
end

--- 落地效果
---@param t table 变换实例
---@param velocity number 落地速度（用于计算强度）
function transform.land(t, velocity)
    local intensity = math.min(1, math.abs(velocity or 300) / 500)
    transform.squash(t, intensity, true)
    transform.reset(t)
end

--- 冲刺效果
---@param t table 变换实例
---@param dirX number 冲刺方向X
---@param dirY number 冲刺方向Y
function transform.dash(t, dirX, dirY)
    transform.stretch(t, 0.6, true)
    t.targetScaleX = 1
    t.targetScaleY = 1
end

--- 攻击蓄力效果
---@param t table 变换实例
---@param progress number 蓄力进度 (0-1)
function transform.attackCharge(t, progress)
    local intensity = progress * 0.3
    t.targetScaleX = 1 - intensity * 0.15  -- 轻微收缩
    t.targetScaleY = 1 + intensity * 0.1
end

--- 攻击释放效果
---@param t table 变换实例
---@param attackType string 攻击类型 ('light', 'heavy', 'finisher')
function transform.attackRelease(t, attackType)
    local intensity = 0.4
    if attackType == 'heavy' then
        intensity = 0.6
    elseif attackType == 'finisher' then
        intensity = 0.8
    end
    
    -- 瞬间拉伸
    transform.stretch(t, intensity, true)
    -- 恢复正常
    transform.reset(t)
end

-- =============================================================================
-- 应用变换到绘制
-- =============================================================================

--- 将变换应用到 Love2D 图形上下文
--- 在 love.graphics.draw 之前调用
---@param t table 变换实例
---@param x number 绘制中心X
---@param y number 绘制中心Y
function transform.apply(t, x, y)
    love.graphics.push()
    love.graphics.translate(x + t.offsetX, y + t.offsetY)
    love.graphics.rotate(t.rotation)
    love.graphics.scale(t.scaleX, t.scaleY)
    love.graphics.translate(-x, -y)
end

--- 结束变换应用
function transform.unapply()
    love.graphics.pop()
end

--- 获取用于 draw 函数的缩放值
---@param t table 变换实例
---@param baseScaleX number 基础缩放X
---@param baseScaleY number|nil 基础缩放Y（默认等于X）
---@return number, number 最终缩放X, 最终缩放Y
function transform.getScale(t, baseScaleX, baseScaleY)
    baseScaleY = baseScaleY or baseScaleX
    return baseScaleX * t.scaleX, baseScaleY * t.scaleY
end

--- 获取用于 draw 函数的偏移值
---@param t table 变换实例
---@return number, number 偏移X, 偏移Y
function transform.getOffset(t)
    return t.offsetX, t.offsetY
end

return transform
