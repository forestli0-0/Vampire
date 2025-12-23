-- =============================================================================
-- 动画事件系统 (Animation Events System)
-- =============================================================================
-- 在动画特定帧触发回调（伤害判定、音效、特效）
-- =============================================================================

local events = {}

-- =============================================================================
-- 事件定义格式
-- =============================================================================
-- 动画事件存储在 animation.events 表中，格式：
-- {
--     { frame = 3, action = 'dealDamage', params = { multiplier = 1.0 } },
--     { frame = 4, action = 'playSound', params = { sound = 'slash' } },
--     { frame = 5, action = 'spawnEffect', params = { effect = 'slash_trail' } },
-- }
-- =============================================================================

-- 事件处理器注册表
events.handlers = {}

--- 注册事件处理器
---@param action string 事件动作名称
---@param handler function 处理函数 function(params, context)
function events.register(action, handler)
    events.handlers[action] = handler
end

--- 检查并触发动画事件
--- 检查从 prevFrame 到 currFrame 之间是否有事件需要触发
---@param anim table 动画实例（包含 events 表）
---@param prevFrame number 上一帧编号
---@param currFrame number 当前帧编号
---@param context table|nil 上下文数据（传递给处理器）
function events.check(anim, prevFrame, currFrame, context)
    if not anim or not anim.events then return end
    
    for _, evt in ipairs(anim.events) do
        -- 检查事件帧是否在区间内
        if evt.frame > prevFrame and evt.frame <= currFrame then
            events.dispatch(evt.action, evt.params, context)
        end
    end
end

--- 分发事件到对应处理器
---@param action string 事件动作名称
---@param params table|nil 事件参数
---@param context table|nil 上下文数据
function events.dispatch(action, params, context)
    local handler = events.handlers[action]
    if handler then
        handler(params or {}, context or {})
    end
end

-- =============================================================================
-- 预设事件处理器
-- =============================================================================

--- 默认事件处理器：伤害判定
events.register('dealDamage', function(params, ctx)
    -- 由外部系统实现具体伤害逻辑
    if ctx.onDealDamage then
        ctx.onDealDamage(params)
    end
end)

--- 默认事件处理器：播放音效
events.register('playSound', function(params, ctx)
    if ctx.state and ctx.state.playSfx then
        ctx.state.playSfx(params.sound or 'hit')
    end
end)

--- 默认事件处理器：生成特效
events.register('spawnEffect', function(params, ctx)
    if ctx.state and ctx.state.spawnEffect then
        local x = params.x or (ctx.entity and ctx.entity.x) or 0
        local y = params.y or (ctx.entity and ctx.entity.y) or 0
        ctx.state.spawnEffect(params.effect or 'hit', x, y, params.scale)
    end
end)

--- 默认事件处理器：屏幕震动
events.register('cameraShake', function(params, ctx)
    if ctx.state then
        ctx.state.shakeAmount = (ctx.state.shakeAmount or 0) + (params.amount or 3)
    end
end)

--- 默认事件处理器：触发顿帧
events.register('hitstop', function(params, ctx)
    local hitstop = require('render.hitstop')
    hitstop.trigger(params.preset or 'light', params)
end)

--- 默认事件处理器：应用挤压拉伸
events.register('transform', function(params, ctx)
    local animTransform = require('render.animation_transform')
    if ctx.entity and ctx.entity.transform then
        local t = ctx.entity.transform
        if params.type == 'squash' then
            animTransform.squash(t, params.intensity or 0.5, params.instant)
        elseif params.type == 'stretch' then
            animTransform.stretch(t, params.intensity or 0.5, params.instant)
        elseif params.type == 'reset' then
            animTransform.reset(t, params.instant)
        end
    end
end)

-- =============================================================================
-- 辅助函数
-- =============================================================================

--- 为动画添加事件
---@param anim table 动画实例
---@param frame number 帧编号
---@param action string 事件动作
---@param params table|nil 事件参数
function events.addEvent(anim, frame, action, params)
    if not anim then return end
    anim.events = anim.events or {}
    table.insert(anim.events, {
        frame = frame,
        action = action,
        params = params or {}
    })
end

--- 移除动画的所有事件
---@param anim table 动画实例
function events.clearEvents(anim)
    if anim then
        anim.events = {}
    end
end

--- 创建攻击动画的标准事件集
---@param anim table 动画实例
---@param damageFrame number 伤害判定帧
---@param totalFrames number 总帧数
---@param attackType string 攻击类型 ('light', 'heavy', 'finisher')
function events.setupAttackEvents(anim, damageFrame, totalFrames, attackType)
    anim.events = {}
    
    -- 蓄力阶段的挤压
    if damageFrame > 1 then
        events.addEvent(anim, 1, 'transform', { type = 'squash', intensity = 0.3 })
    end
    
    -- 伤害判定帧
    events.addEvent(anim, damageFrame, 'dealDamage', { attackType = attackType })
    events.addEvent(anim, damageFrame, 'transform', { type = 'stretch', intensity = 0.5, instant = true })
    
    -- 音效
    events.addEvent(anim, damageFrame, 'playSound', { sound = 'slash' })
    
    -- 顿帧（如果命中）
    local hitstopPreset = 'light'
    if attackType == 'heavy' then
        hitstopPreset = 'heavy'
    elseif attackType == 'finisher' then
        hitstopPreset = 'finisher'
    end
    events.addEvent(anim, damageFrame, 'hitstop', { preset = hitstopPreset })
    
    -- 恢复阶段
    if damageFrame < totalFrames then
        events.addEvent(anim, damageFrame + 1, 'transform', { type = 'reset' })
    end
end

return events
