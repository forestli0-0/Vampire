-- =============================================================================
-- 动画状态机 (Animation State Machine)
-- =============================================================================
-- 管理角色动画状态切换、过渡、中断逻辑
-- =============================================================================

local animState = {}

-- =============================================================================
-- 状态机创建
-- =============================================================================

--- 创建新的动画状态机
---@param animSet table 动画集合实例 (由 animation.newAnimationSet 创建)
---@param stateDefs table 状态定义表
---@return table 状态机实例
function animState.new(animSet, stateDefs)
    local sm = {
        animSet = animSet,         -- 动画集合
        states = stateDefs or {},  -- 状态定义
        currentState = nil,        -- 当前状态名
        previousState = nil,       -- 上一个状态
        stateTimer = 0,            -- 当前状态的持续时间
        locked = false,            -- 是否锁定（不可被打断）
        lockTimer = 0,             -- 锁定剩余时间
        queuedState = nil,         -- 锁定期间排队的状态
        context = {},              -- 上下文数据（用于条件判断）
        transform = nil,           -- 挤压拉伸变换实例
    }
    
    -- 尝试加载变换模块
    local ok, transformMod = pcall(require, 'render.animation_transform')
    if ok then
        sm.transform = transformMod.new()
    end
    
    return setmetatable(sm, { __index = animState })
end

-- =============================================================================
-- 状态定义格式
-- =============================================================================
--[[
状态定义示例:
{
    idle = {
        animation = 'idle',       -- 对应动画集中的动画名
        loop = true,              -- 是否循环
        canInterrupt = true,      -- 是否可被其他状态打断
        transitions = {           -- 自动过渡条件
            { to = 'run', condition = function(ctx) return ctx.isMoving end },
            { to = 'attack', condition = function(ctx) return ctx.attackPressed end },
        },
        onEnter = function(sm, ctx) end,  -- 进入状态时的回调
        onExit = function(sm, ctx) end,   -- 离开状态时的回调
        onComplete = 'idle',      -- 非循环动画完成后的下一个状态
    },
    attack = {
        animation = 'attack',
        loop = false,
        canInterrupt = false,     -- 攻击动画不可打断
        lockDuration = 0.3,       -- 锁定时间（无视打断请求）
        events = {
            { frame = 3, action = 'dealDamage' },
        },
        onComplete = 'idle',
    },
}
]]

-- =============================================================================
-- 核心方法
-- =============================================================================

--- 设置上下文（外部系统更新的状态数据）
---@param ctx table 上下文数据
function animState:setContext(ctx)
    self.context = ctx or {}
end

--- 更新上下文的部分字段
---@param key string 字段名
---@param value any 值
function animState:updateContext(key, value)
    self.context[key] = value
end

--- 尝试切换到新状态
---@param stateName string 目标状态名
---@param force boolean|nil 是否强制切换（忽略canInterrupt）
---@return boolean 是否成功切换
function animState:setState(stateName, force)
    if not stateName or not self.states[stateName] then
        return false
    end
    
    -- 如果是同一个状态，不切换（除非强制）
    if self.currentState == stateName and not force then
        return false
    end
    
    -- 检查锁定状态
    if self.locked and not force then
        self.queuedState = stateName
        return false
    end
    
    -- 检查当前状态是否可被打断
    local currentDef = self.states[self.currentState]
    if currentDef and not currentDef.canInterrupt and not force then
        self.queuedState = stateName
        return false
    end
    
    -- 执行状态切换
    self:_doTransition(stateName)
    return true
end

--- 内部：执行状态转换
function animState:_doTransition(stateName)
    local prevDef = self.states[self.currentState]
    local newDef = self.states[stateName]
    
    -- 调用旧状态的 onExit
    if prevDef and prevDef.onExit then
        prevDef.onExit(self, self.context)
    end
    
    -- 更新状态
    self.previousState = self.currentState
    self.currentState = stateName
    self.stateTimer = 0
    self.queuedState = nil
    
    -- 处理锁定
    if newDef and newDef.lockDuration then
        self.locked = true
        self.lockTimer = newDef.lockDuration
    else
        self.locked = false
        self.lockTimer = 0
    end
    
    -- 播放对应动画
    if self.animSet and newDef and newDef.animation then
        self.animSet:play(newDef.animation, true)
    end
    
    -- 调用新状态的 onEnter
    if newDef and newDef.onEnter then
        newDef.onEnter(self, self.context)
    end
    
    -- 应用变换效果
    if self.transform and newDef and newDef.enterTransform then
        local transformMod = require('render.animation_transform')
        local t = newDef.enterTransform
        if t.squash then
            transformMod.squash(self.transform, t.squash, t.instant)
        elseif t.stretch then
            transformMod.stretch(self.transform, t.stretch, t.instant)
        end
    end
end

--- 更新状态机
---@param dt number delta time
function animState:update(dt)
    if not self.currentState then
        -- 自动进入第一个定义的状态
        for name, _ in pairs(self.states) do
            self:setState(name, true)
            break
        end
        return
    end
    
    local def = self.states[self.currentState]
    if not def then return end
    
    -- 更新计时器
    self.stateTimer = self.stateTimer + dt
    
    -- 更新锁定状态
    if self.locked then
        self.lockTimer = self.lockTimer - dt
        if self.lockTimer <= 0 then
            self.locked = false
            -- 处理排队的状态
            if self.queuedState then
                self:setState(self.queuedState, true)
            end
        end
    end
    
    -- 更新动画
    if self.animSet then
        self.animSet:update(dt)
    end
    
    -- 更新变换
    if self.transform then
        local ok, transformMod = pcall(require, 'render.animation_transform')
        if ok then
            transformMod.update(self.transform, dt)
        end
    end
    
    -- 检查自动过渡条件（只在未锁定时）
    if not self.locked and def.transitions then
        for _, trans in ipairs(def.transitions) do
            if trans.condition and trans.condition(self.context) then
                self:setState(trans.to)
                return  -- 状态已切换，退出
            end
        end
    end
    
    -- 检查非循环动画是否完成
    if not def.loop and self.animSet and self.animSet:isComplete() then
        local nextState = def.onComplete
        if type(nextState) == 'function' then
            nextState = nextState(self, self.context)
        end
        if nextState then
            self:setState(nextState, true)
        end
    end
end

--- 绘制当前动画
---@param x number X坐标
---@param y number Y坐标
---@param r number|nil 旋转
---@param sx number|nil X缩放
---@param sy number|nil Y缩放
function animState:draw(x, y, r, sx, sy)
    if not self.animSet then return end
    
    if self.transform then
        self.animSet:drawWithTransform(x, y, self.transform, r, sx, sy)
    else
        self.animSet:draw(x, y, r, sx, sy)
    end
end

--- 获取当前状态名
---@return string|nil
function animState:getCurrentState()
    return self.currentState
end

--- 检查是否处于特定状态
---@param stateName string
---@return boolean
function animState:isInState(stateName)
    return self.currentState == stateName
end

--- 检查是否锁定
---@return boolean
function animState:isLocked()
    return self.locked
end

--- 获取变换实例
---@return table|nil
function animState:getTransform()
    return self.transform
end

--- 强制解锁
function animState:unlock()
    self.locked = false
    self.lockTimer = 0
end

--- 应用挤压效果
---@param intensity number 强度
function animState:squash(intensity)
    if self.transform then
        local ok, transformMod = pcall(require, 'render.animation_transform')
        if ok then
            transformMod.squash(self.transform, intensity or 0.5, true)
        end
    end
end

--- 应用拉伸效果
---@param intensity number 强度
function animState:stretch(intensity)
    if self.transform then
        local ok, transformMod = pcall(require, 'render.animation_transform')
        if ok then
            transformMod.stretch(self.transform, intensity or 0.5, true)
        end
    end
end

--- 处理受击反馈
---@param hitDirX number 受击方向X
---@param hitDirY number 受击方向Y
---@param intensity number|nil 强度
function animState:hitReaction(hitDirX, hitDirY, intensity)
    if self.transform then
        local ok, transformMod = pcall(require, 'render.animation_transform')
        if ok then
            transformMod.hitReaction(self.transform, hitDirX, hitDirY, intensity or 0.6)
        end
    end
    
    -- 如果有 hit 状态且可以切换，切换到 hit
    if self.states['hit'] then
        self:setState('hit', true)
    end
end

-- =============================================================================
-- 预设状态定义
-- =============================================================================

--- 创建玩家角色的标准状态定义
---@return table 状态定义表
function animState.createPlayerStates()
    return {
        idle = {
            animation = 'idle',
            loop = true,
            canInterrupt = true,
            transitions = {
                { to = 'run', condition = function(ctx) return ctx.isMoving end },
                { to = 'dash', condition = function(ctx) return ctx.isDashing end },
                { to = 'attack_light', condition = function(ctx) return ctx.attackType == 'light' end },
                { to = 'attack_heavy', condition = function(ctx) return ctx.attackType == 'heavy' end },
            },
        },
        run = {
            animation = 'run',
            loop = true,
            canInterrupt = true,
            transitions = {
                { to = 'idle', condition = function(ctx) return not ctx.isMoving end },
                { to = 'dash', condition = function(ctx) return ctx.isDashing end },
                { to = 'attack_light', condition = function(ctx) return ctx.attackType == 'light' end },
            },
        },
        dash = {
            animation = 'dash',
            loop = false,
            canInterrupt = false,
            lockDuration = 0.2,
            enterTransform = { stretch = 0.6, instant = true },
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        attack_light = {
            animation = 'attack_light',
            loop = false,
            canInterrupt = false,
            lockDuration = 0.15,
            enterTransform = { stretch = 0.4, instant = true },
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        attack_heavy = {
            animation = 'attack_heavy',
            loop = false,
            canInterrupt = false,
            lockDuration = 0.3,
            enterTransform = { squash = 0.3, instant = false },
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        hit = {
            animation = 'hit',
            loop = false,
            canInterrupt = true,
            onComplete = function(sm, ctx) return ctx.isMoving and 'run' or 'idle' end,
        },
        death = {
            animation = 'death',
            loop = false,
            canInterrupt = false,
        },
    }
end

--- 创建敌人的标准状态定义
---@return table 状态定义表
function animState.createEnemyStates()
    return {
        idle = {
            animation = 'idle',
            loop = true,
            canInterrupt = true,
            transitions = {
                { to = 'move', condition = function(ctx) return ctx.isMoving end },
                { to = 'attack', condition = function(ctx) return ctx.isAttacking end },
            },
        },
        move = {
            animation = 'move',
            loop = true,
            canInterrupt = true,
            transitions = {
                { to = 'idle', condition = function(ctx) return not ctx.isMoving end },
                { to = 'attack', condition = function(ctx) return ctx.isAttacking end },
            },
        },
        attack = {
            animation = 'attack',
            loop = false,
            canInterrupt = false,
            lockDuration = 0.4,
            onComplete = function(sm, ctx) return ctx.isMoving and 'move' or 'idle' end,
        },
        hit = {
            animation = 'hit',
            loop = false,
            canInterrupt = true,
            onComplete = function(sm, ctx) return ctx.isMoving and 'move' or 'idle' end,
        },
        death = {
            animation = 'death',
            loop = false,
            canInterrupt = false,
        },
    }
end

return animState
