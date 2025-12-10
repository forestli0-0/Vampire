local animation = {}

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

-- Backward-compatible: if frameW/frameH are numbers, slice a grid.
-- New usage: animation.newAnimation(image, framesTable, opts)
-- opts: duration (total loop), fps (overrides duration), loop (default true)
function animation.newAnimation(image, frameWOrFrames, frameH, durationOrOpts)
    local frames
    local duration = 0.8
    local loop = true

    if type(frameWOrFrames) == 'number' then
        frames = animation.newFramesFromGrid(image, frameWOrFrames, frameH)
        duration = durationOrOpts or 0.8
    else
        frames = toQuads(image, frameWOrFrames or {})
        if type(frameH) == 'table' then
            duration = frameH.duration or duration
            loop = frameH.loop ~= false
            if frameH.fps and frameH.fps > 0 then
                duration = #frames / frameH.fps
            end
        elseif type(durationOrOpts) == 'table' then
            local opts = durationOrOpts
            duration = opts.duration or duration
            loop = opts.loop ~= false
            if opts.fps and opts.fps > 0 then
                duration = #frames / opts.fps
            end
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
        playing = true
    }

    function anim:play(reset)
        self.playing = true
        if reset then self.currentTime = 0 end
    end

    function anim:stop()
        self.playing = false
    end

    function anim:update(dt)
        if not self.playing or #self.quads == 0 then return end
        self.currentTime = self.currentTime + dt
        if self.currentTime >= self.duration then
            if self.loop then
                self.currentTime = self.currentTime % self.duration
            else
                self.currentTime = self.duration - 1e-6
                self.playing = false
            end
        end
    end

    function anim:draw(x, y, r, sx, sy)
        if #self.quads == 0 then return end
        local frameDuration = self.duration / #self.quads
        local frame = math.max(1, math.min(#self.quads, math.floor(self.currentTime / frameDuration) + 1))
        local quad = self.quads[frame]
        local _, _, w, h = quad:getViewport()
        love.graphics.draw(self.image, quad, x, y, r or 0, sx or 1, sy or 1, w / 2, h / 2)
    end

    return anim
end

-- Animation set: manage multiple named animations on the same sheet.
-- animDefs: { idle = {frames={...}, fps=6}, run={frames={...}, duration=0.6}, ... }
function animation.newAnimationSet(image, animDefs)
    local set = {
        animations = {},
        current = nil
    }
    for name, def in pairs(animDefs or {}) do
        set.animations[name] = animation.newAnimation(image, def.frames, {duration=def.duration, fps=def.fps, loop=def.loop})
    end

    function set:play(name, reset)
        if self.current == self.animations[name] and not reset then return end
        self.current = self.animations[name]
        if self.current then self.current:play(reset) end
    end

    function set:update(dt)
        if self.current then self.current:update(dt) end
    end

    function set:draw(x, y, r, sx, sy)
        if self.current then self.current:draw(x, y, r, sx, sy) end
    end

    return set
end

return animation
