local animation = {}

function animation.newAnimation(image, frameW, frameH, duration)
    local imgW, imgH = image:getWidth(), image:getHeight()
    local cols = math.floor(imgW / frameW)
    local rows = math.floor(imgH / frameH)
    local quads = {}
    for j = 0, rows - 1 do
        for i = 0, cols - 1 do
            table.insert(quads, love.graphics.newQuad(i * frameW, j * frameH, frameW, frameH, imgW, imgH))
        end
    end

    local anim = {
        image = image,
        quads = quads,
        frameW = frameW,
        frameH = frameH,
        duration = duration or 0.8,
        currentTime = 0
    }

    function anim:update(dt)
        self.currentTime = (self.currentTime + dt) % self.duration
    end

    function anim:draw(x, y)
        local frameDuration = self.duration / #self.quads
        local frame = math.floor(self.currentTime / frameDuration) + 1
        local quad = self.quads[frame]
        love.graphics.draw(self.image, quad, x, y, 0, 1, 1, self.frameW / 2, self.frameH / 2)
    end

    return anim
end

return animation
