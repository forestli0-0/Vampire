local bloom = require('render.bloom')

local pipeline = {}

local inited = false
local emissiveCanvas = nil
local debugView = 'final'
local debugViews = {'final', 'base', 'emissive', 'bloom'}

pipeline.emissiveFallback = false

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
    if not bloom or not bloom.postDraw then return end

    if debugView == 'final' then
        bloom.postDraw(state, emissiveCanvas)
        return
    end

    bloom.postDraw(state, emissiveCanvas, {skipFinal = true})

    local canvas = nil
    if debugView == 'base' and bloom.getMainCanvas then
        canvas = bloom.getMainCanvas()
    elseif debugView == 'emissive' then
        canvas = emissiveCanvas
    elseif debugView == 'bloom' and bloom.getBloomCanvas then
        canvas = bloom.getBloomCanvas()
    end

    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)
    if canvas then
        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        local cw, ch = canvas:getWidth(), canvas:getHeight()
        local sx = sw / cw
        local sy = sh / ch
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, 0, 0, 0, sx, sy)
    end
end

function pipeline.drawUI(drawFn)
    if debugView == 'final' and drawFn then
        drawFn()
    end
end

function pipeline.getEmissiveCanvas()
    return emissiveCanvas
end

function pipeline.setDebugView(view)
    for _, v in ipairs(debugViews) do
        if v == view then
            debugView = view
            return debugView
        end
    end
    return debugView
end

function pipeline.getDebugView()
    return debugView
end

function pipeline.nextDebugView()
    for i, v in ipairs(debugViews) do
        if v == debugView then
            local nextIndex = i + 1
            if nextIndex > #debugViews then nextIndex = 1 end
            debugView = debugViews[nextIndex]
            return debugView
        end
    end
    debugView = debugViews[1]
    return debugView
end

return pipeline
