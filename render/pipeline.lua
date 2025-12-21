local bloom = require('render.bloom')

local pipeline = {}

local inited = false
local emissiveCanvas = nil

pipeline.emissiveFallback = true

function pipeline.init(w, h)
    if inited then return end
    inited = true
    if bloom and bloom.init then
        bloom.init(w, h)
    end
    emissiveCanvas = love.graphics.newCanvas(w, h)
end

function pipeline.resize(w, h)
    if bloom and bloom.resize then
        bloom.resize(w, h)
    end
    emissiveCanvas = love.graphics.newCanvas(w, h)
end

function pipeline.beginFrame()
    if bloom and bloom.preDraw then
        bloom.preDraw()
    end
end

function pipeline.drawBase(drawFn)
    if drawFn then drawFn() end
end

function pipeline.drawEmissive(drawFn)
    if not emissiveCanvas then return end
    love.graphics.setCanvas(emissiveCanvas)
    love.graphics.clear(0, 0, 0, 0)

    local prevMode, prevAlphaMode = love.graphics.getBlendMode()
    local didDraw = false
    if drawFn then
        didDraw = (drawFn() == true)
    end

    if (not didDraw) and pipeline.emissiveFallback then
        local base = bloom and bloom.getMainCanvas and bloom.getMainCanvas()
        if base then
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(base, 0, 0)
        end
    end

    love.graphics.setBlendMode(prevMode, prevAlphaMode)
    love.graphics.setCanvas()
end

function pipeline.present(state)
    if bloom and bloom.postDraw then
        bloom.postDraw(state, emissiveCanvas)
    end
end

function pipeline.drawUI(drawFn)
    if drawFn then drawFn() end
end

function pipeline.getEmissiveCanvas()
    return emissiveCanvas
end

return pipeline
