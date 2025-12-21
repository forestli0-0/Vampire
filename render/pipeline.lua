local bloom = require('render.bloom')

local pipeline = {}

local inited = false
local emissiveCanvas = nil
local debugView = 'final'
local debugViews = {'final', 'base', 'emissive', 'bloom'}
local statsCanvas = nil
local statsEnabled = false
local statsFrame = 0
local statsSampleEvery = 10
local statsThreshold = 0.08
local emissiveStats = {
    coverage = 0,
    avg = 0,
    max = 0,
    sampleW = 0,
    sampleH = 0,
    lastTime = 0
}

pipeline.emissiveFallback = false

function pipeline.init(w, h)
    if inited then return end
    inited = true
    if bloom and bloom.init then
        bloom.init(w, h)
    end
    emissiveCanvas = love.graphics.newCanvas(w, h)
    local sw = math.max(1, math.floor(w / 10))
    local sh = math.max(1, math.floor(h / 10))
    statsCanvas = love.graphics.newCanvas(sw, sh)
end

function pipeline.resize(w, h)
    if bloom and bloom.resize then
        bloom.resize(w, h)
    end
    emissiveCanvas = love.graphics.newCanvas(w, h)
    local sw = math.max(1, math.floor(w / 10))
    local sh = math.max(1, math.floor(h / 10))
    statsCanvas = love.graphics.newCanvas(sw, sh)
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

    if statsEnabled and statsCanvas then
        local prevCanvas = love.graphics.getCanvas()
        local pm, pa = love.graphics.getBlendMode()
        love.graphics.setCanvas(statsCanvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
        local sx = statsCanvas:getWidth() / emissiveCanvas:getWidth()
        local sy = statsCanvas:getHeight() / emissiveCanvas:getHeight()
        love.graphics.draw(emissiveCanvas, 0, 0, 0, sx, sy)
        love.graphics.setBlendMode(pm, pa)
        love.graphics.setCanvas(prevCanvas)
    end
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

local function updateEmissiveStats()
    if not statsEnabled or not statsCanvas then return end
    statsFrame = statsFrame + 1
    if statsFrame % statsSampleEvery ~= 0 then return end

    local ok, imgData = pcall(function()
        return statsCanvas:newImageData()
    end)
    if not ok or not imgData then return end

    local w, h = imgData:getDimensions()
    local count = w * h
    if count <= 0 then return end

    local sum = 0
    local maxVal = 0
    local bright = 0

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local r, g, b, a = imgData:getPixel(x, y)
            local lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) * a
            sum = sum + lum
            if lum > statsThreshold then bright = bright + 1 end
            if lum > maxVal then maxVal = lum end
        end
    end

    emissiveStats.coverage = bright / count
    emissiveStats.avg = sum / count
    emissiveStats.max = maxVal
    emissiveStats.sampleW = w
    emissiveStats.sampleH = h
    emissiveStats.lastTime = love.timer.getTime()
end

function pipeline.getEmissiveStats()
    updateEmissiveStats()
    return emissiveStats
end

function pipeline.setEmissiveStatsEnabled(enabled)
    statsEnabled = enabled == true
    statsFrame = 0
    return statsEnabled
end

function pipeline.toggleEmissiveStats()
    statsEnabled = not statsEnabled
    statsFrame = 0
    return statsEnabled
end

function pipeline.drawEmissiveStatsOverlay(font)
    if not statsEnabled then return end
    updateEmissiveStats()

    local prevFont = love.graphics.getFont()
    if font then love.graphics.setFont(font) end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local boxW, boxH = 240, 72
    local x = sw - boxW - 10
    local y = 10

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle('fill', x, y, boxW, boxH, 6, 6)

    local coverPct = emissiveStats.coverage * 100
    local avg = emissiveStats.avg
    local maxVal = emissiveStats.max

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("Emissive cover: %.1f%%", coverPct), x + 10, y + 10)
    love.graphics.print(string.format("Emissive avg: %.3f", avg), x + 10, y + 28)
    love.graphics.print(string.format("Emissive max: %.3f", maxVal), x + 10, y + 46)

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return pipeline
