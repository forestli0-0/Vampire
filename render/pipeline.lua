local bloom = require('render.bloom')

local pipeline = {}

local inited = false

function pipeline.init(w, h)
    if inited then return end
    inited = true
    if bloom and bloom.init then
        bloom.init(w, h)
    end
end

function pipeline.resize(w, h)
    if bloom and bloom.resize then
        bloom.resize(w, h)
    end
end

function pipeline.beginFrame()
    if bloom and bloom.preDraw then
        bloom.preDraw()
    end
end

function pipeline.drawBase(drawFn)
    if drawFn then drawFn() end
end

function pipeline.present(state)
    if bloom and bloom.postDraw then
        bloom.postDraw(state)
    end
end

function pipeline.drawUI(drawFn)
    if drawFn then drawFn() end
end

return pipeline
