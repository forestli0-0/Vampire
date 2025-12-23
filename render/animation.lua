-- =============================================================================
-- 动画系统 (Animation System) - 升级版
-- =============================================================================
-- 支持：帧动画、速度曲线、动画事件、播放速度控制、帧回调
-- =============================================================================

local animation = {}

-- =============================================================================
-- 速度曲线预设
-- =============================================================================

animation.speedCurves = {
    -- 线性（默认）
    linear = function(t) return 1 end,
    
    -- 攻击曲线：蓄力慢、挥砍快、恢复中速
    attack = function(t)
        if t < 0.3 then return 0.7 end      -- 蓄力阶段
        if t < 0.5 then return 2.0 end      -- 挥砍阶段
        return 1.0 - (t - 0.5) * 0.4        -- 恢复阶段
    end,
    
    -- 受击曲线：开始快、结束慢
    hit = function(t)
        return 1.5 - t * 0.8
    end,
    
    -- 蓄力曲线：越来越慢
    charge = function(t)
        return 1.0 - t * 0.6
    end,
    
    -- 爆发曲线：开始慢、中间快、结束慢
    burst = function(t)
        local x = (t - 0.5) * 2
        return 1 + (1 - x * x) * 0.8
    end,
}

-- =============================================================================
-- 帧工具函数
-- =============================================================================

-- Create a grid of quads from a sheet.
function animation.newFramesFromGrid(image, frameW, frameH)
    local imgW, imgH = image:getWidth(), image:getHeight()
    local cols = math.floor(imgW / frameW)
    local rows = math.floor(imgH / frameH)
    local quads = {}
    for j = 0, rows - 1 do
        for i = 0, cols - 1 do
            table.insert(quads, love.graphics.newQuad(i * frameW, j * frameH, frameW, frameH, imgW, imgH))
        end
    end
    return quads
end

-- Normalize frames: accept a list of quads, or a list of {x,y,w,h} rects.
local function toQuads(image, frames)
    if not frames then return {} end
    if frames[1] and frames[1].getViewport then
        return frames
    end
    local quads = {}
    local imgW, imgH = image:getWidth(), image:getHeight()
    for _, f in ipairs(frames) do
        local x, y, w, h = f[1], f[2], f[3], f[4]
        table.insert(quads, love.graphics.newQuad(x, y, w, h, imgW, imgH))
    end
    return quads
end

-- =============================================================================
-- 核心动画构造函数
-- =============================================================================

--- 创建新动画
--- 向后兼容旧用法，同时支持新的高级选项
---@param image userdata Love2D Image
---@param frameWOrFrames number|table 帧宽度或帧列表
---@param frameH number|table|nil 帧高度或选项表
---@param durationOrOpts number|table|nil 持续时间或选项表
---@return table 动画实例
function animation.newAnimation(image, frameWOrFrames, frameH, durationOrOpts)
    local frames
    local duration = 0.8
    local loop = true
    local speedCurve = nil
    local events = nil
    local onComplete = nil
    local onFrameChange = nil

    if type(frameWOrFrames) == 'number' then
        frames = animation.newFramesFromGrid(image, frameWOrFrames, frameH)
        if type(durationOrOpts) == 'table' then
            duration = durationOrOpts.duration or duration
            loop = durationOrOpts.loop ~= false
            if durationOrOpts.fps and durationOrOpts.fps > 0 then
                duration = #frames / durationOrOpts.fps
            end
            speedCurve = durationOrOpts.speedCurve
            events = durationOrOpts.events
            onComplete = durationOrOpts.onComplete
            onFrameChange = durationOrOpts.onFrameChange
        elseif type(durationOrOpts) == 'number' then
            duration = durationOrOpts
        end
    else
        frames = toQuads(image, frameWOrFrames or {})
        local opts = nil
        if type(frameH) == 'table' then
            opts = frameH
        elseif type(durationOrOpts) == 'table' then
            opts = durationOrOpts
        end
        
        if opts then
            duration = opts.duration or duration
            loop = opts.loop ~= false
            if opts.fps and opts.fps > 0 then
                duration = #frames / opts.fps
            end
            speedCurve = opts.speedCurve
            events = opts.events
            onComplete = opts.onComplete
            onFrameChange = opts.onFrameChange
        elseif type(durationOrOpts) == 'number' then
            duration = durationOrOpts
        end
    end

    local anim = {
        image = image,
        quads = frames,
        duration = duration,
        loop = loop,
        currentTime = 0,
        playing = true,
        
        -- 新增属性
        speed = 1,              -- 播放速度倍率
        speedCurve = speedCurve, -- 速度曲线函数
        events = events or {},   -- 动画事件列表
        onComplete = onComplete, -- 完成回调
        onFrameChange = onFrameChange, -- 帧变化回调
        currentFrame = 1,       -- 当前帧索引
        previousFrame = 0,      -- 上一帧索引（用于事件检测）
        completed = false,      -- 是否已完成（非循环动画）
        eventContext = nil,     -- 事件上下文
    }

    --- 播放动画
    ---@param reset boolean|nil 是否重置到开头
    function anim:play(reset)
        self.playing = true
        self.completed = false
        if reset then 
            self.currentTime = 0 
            self.currentFrame = 1
            self.previousFrame = 0
        end
    end

    --- 停止动画
    function anim:stop()
        self.playing = false
    end

    --- 设置播放速度
    ---@param speed number 速度倍率
    function anim:setSpeed(speed)
        self.speed = speed or 1
    end

    --- 设置事件上下文
    ---@param ctx table 上下文数据
    function anim:setEventContext(ctx)
        self.eventContext = ctx
    end

    --- 获取当前帧索引
    ---@return number 帧索引 (1-based)
    function anim:getFrame()
        return self.currentFrame
    end

    --- 获取总帧数
    ---@return number 总帧数
    function anim:getFrameCount()
        return #self.quads
    end

    --- 获取播放进度
    ---@return number 进度 (0-1)
    function anim:getProgress()
        if self.duration <= 0 then return 0 end
        return self.currentTime / self.duration
    end

    --- 跳转到指定帧
    ---@param frame number 帧索引 (1-based)
    function anim:gotoFrame(frame)
        if #self.quads == 0 then return end
        frame = math.max(1, math.min(#self.quads, frame))
        local frameDuration = self.duration / #self.quads
        self.currentTime = (frame - 1) * frameDuration
        self.currentFrame = frame
    end

    --- 更新动画
    ---@param dt number delta time
    function anim:update(dt)
        if not self.playing or #self.quads == 0 then return end
        
        -- 保存上一帧
        self.previousFrame = self.currentFrame
        
        -- 计算实际dt（考虑速度曲线和播放速度）
        local progress = self:getProgress()
        local curveMultiplier = 1
        if self.speedCurve then
            if type(self.speedCurve) == 'function' then
                curveMultiplier = self.speedCurve(progress)
            elseif type(self.speedCurve) == 'string' and animation.speedCurves[self.speedCurve] then
                curveMultiplier = animation.speedCurves[self.speedCurve](progress)
            end
        end
        
        local effectiveDt = dt * self.speed * curveMultiplier
        self.currentTime = self.currentTime + effectiveDt
        
        -- 计算当前帧
        local frameDuration = self.duration / #self.quads
        self.currentFrame = math.max(1, math.min(#self.quads, math.floor(self.currentTime / frameDuration) + 1))
        
        -- 检查动画事件
        if self.currentFrame ~= self.previousFrame and #self.events > 0 then
            local animEvents = require('render.animation_events')
            animEvents.check(self, self.previousFrame, self.currentFrame, self.eventContext)
            
            -- 帧变化回调
            if self.onFrameChange then
                self.onFrameChange(self, self.currentFrame, self.previousFrame)
            end
        end
        
        -- 处理动画结束
        if self.currentTime >= self.duration then
            if self.loop then
                self.currentTime = self.currentTime % self.duration
                self.previousFrame = 0  -- 重置以便检测循环事件
            else
                self.currentTime = self.duration - 1e-6
                self.currentFrame = #self.quads
                self.playing = false
                
                if not self.completed then
                    self.completed = true
                    if self.onComplete then
                        self.onComplete(self)
                    end
                end
            end
        end
    end

    --- 绘制动画
    ---@param x number X坐标
    ---@param y number Y坐标
    ---@param r number|nil 旋转角度
    ---@param sx number|nil X缩放
    ---@param sy number|nil Y缩放
    function anim:draw(x, y, r, sx, sy)
        if #self.quads == 0 then return end
        local quad = self.quads[self.currentFrame]
        local _, _, w, h = quad:getViewport()
        love.graphics.draw(self.image, quad, x, y, r or 0, sx or 1, sy or 1, w / 2, h / 2)
    end

    --- 绘制动画（带变换）
    ---@param x number X坐标
    ---@param y number Y坐标
    ---@param transform table|nil 变换实例
    ---@param r number|nil 旋转角度
    ---@param baseSx number|nil 基础X缩放
    ---@param baseSy number|nil 基础Y缩放
    function anim:drawWithTransform(x, y, transform, r, baseSx, baseSy)
        if #self.quads == 0 then return end
        local quad = self.quads[self.currentFrame]
        local _, _, w, h = quad:getViewport()
        
        local sx = (baseSx or 1)
        local sy = (baseSy or 1)
        local offsetX = 0
        local offsetY = 0
        
        if transform then
            sx = sx * transform.scaleX
            sy = sy * transform.scaleY
            offsetX = transform.offsetX or 0
            offsetY = transform.offsetY or 0
            r = (r or 0) + (transform.rotation or 0)
        end
        
        love.graphics.draw(self.image, quad, x + offsetX, y + offsetY, r or 0, sx, sy, w / 2, h / 2)
    end

    return anim
end

-- =============================================================================
-- 动画集合
-- =============================================================================

--- 创建动画集合（管理多个命名动画）
---@param image userdata Love2D Image
---@param animDefs table 动画定义表 { name = {frames, fps, loop, ...}, ... }
---@return table 动画集合实例
function animation.newAnimationSet(image, animDefs)
    local set = {
        animations = {},
        current = nil,
        currentName = nil,
    }
    
    for name, def in pairs(animDefs or {}) do
        set.animations[name] = animation.newAnimation(image, def.frames, {
            duration = def.duration, 
            fps = def.fps, 
            loop = def.loop,
            speedCurve = def.speedCurve,
            events = def.events,
            onComplete = def.onComplete,
            onFrameChange = def.onFrameChange,
        })
    end

    --- 播放指定动画
    ---@param name string 动画名称
    ---@param reset boolean|nil 是否重置
    function set:play(name, reset)
        if self.currentName == name and not reset then return end
        self.current = self.animations[name]
        self.currentName = name
        if self.current then self.current:play(reset or true) end
    end

    --- 更新当前动画
    function set:update(dt)
        if self.current then self.current:update(dt) end
    end

    --- 绘制当前动画
    function set:draw(x, y, r, sx, sy)
        if self.current then self.current:draw(x, y, r, sx, sy) end
    end

    --- 绘制（带变换）
    function set:drawWithTransform(x, y, transform, r, sx, sy)
        if self.current then self.current:drawWithTransform(x, y, transform, r, sx, sy) end
    end

    --- 获取当前动画名称
    function set:getCurrentName()
        return self.currentName
    end

    --- 检查当前动画是否完成
    function set:isComplete()
        return self.current and self.current.completed
    end

    --- 设置事件上下文
    function set:setEventContext(ctx)
        for _, anim in pairs(self.animations) do
            anim.eventContext = ctx
        end
    end

    return set
end

return animation

