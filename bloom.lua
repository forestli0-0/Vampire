local bloom = {}
bloom.enabled = true

local canvas_main
local canvas_bright
local canvas_blur_h
local canvas_blur_v

local shader_threshold
local shader_blur

function bloom.init(w, h)
    canvas_main = love.graphics.newCanvas(w, h)
    canvas_bright = love.graphics.newCanvas(w/2, h/2) -- Downscale for performance and better blur
    canvas_blur_h = love.graphics.newCanvas(w/2, h/2)
    canvas_blur_v = love.graphics.newCanvas(w/2, h/2)

    -- Shader to extract bright parts
    shader_threshold = love.graphics.newShader[[
        extern number threshold;
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 texcolor = Texel(texture, texture_coords);
            number brightness = max(max(texcolor.r, texcolor.g), texcolor.b);
            if (brightness > threshold) {
                return texcolor * color;
            } else {
                return vec4(0.0, 0.0, 0.0, 0.0);
            }
        }
    ]]
    shader_threshold:send("threshold", 0.5) -- Lowered threshold for visibility

    -- Gaussian Blur Shader
    shader_blur = love.graphics.newShader[[
        extern vec2 dir;
        extern vec2 size;
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 sum = vec4(0.0);
            vec2 tc = texture_coords;
            vec2 blur = dir / size;

            sum += Texel(texture, tc - 4.0*blur) * 0.0162162162;
            sum += Texel(texture, tc - 3.0*blur) * 0.0540540541;
            sum += Texel(texture, tc - 2.0*blur) * 0.1216216216;
            sum += Texel(texture, tc - 1.0*blur) * 0.1945945946;
            sum += Texel(texture, tc) * 0.2270270270;
            sum += Texel(texture, tc + 1.0*blur) * 0.1945945946;
            sum += Texel(texture, tc + 2.0*blur) * 0.1216216216;
            sum += Texel(texture, tc + 3.0*blur) * 0.0540540541;
            sum += Texel(texture, tc + 4.0*blur) * 0.0162162162;

            return sum * color;
        }
    ]]
end

function bloom.toggle()
    bloom.enabled = not bloom.enabled
    print("Bloom enabled:", bloom.enabled)
end

function bloom.preDraw()
    if not bloom.enabled then return end
    love.graphics.setCanvas(canvas_main)
    love.graphics.clear()
end

function bloom.postDraw()
    if not bloom.enabled then return end
    love.graphics.setCanvas() -- Reset to screen

    -- 1. Extract bright areas
    love.graphics.setCanvas(canvas_bright)
    love.graphics.clear()
    love.graphics.setShader(shader_threshold)
    love.graphics.draw(canvas_main, 0, 0, 0, 0.5, 0.5) -- Draw downscaled

    -- 2. Horizontal Blur
    love.graphics.setCanvas(canvas_blur_h)
    love.graphics.clear()
    love.graphics.setShader(shader_blur)
    shader_blur:send("dir", {1.0, 0.0})
    shader_blur:send("size", {canvas_bright:getWidth(), canvas_bright:getHeight()})
    love.graphics.draw(canvas_bright, 0, 0)

    -- 3. Vertical Blur
    love.graphics.setCanvas(canvas_blur_v)
    love.graphics.clear()
    shader_blur:send("dir", {0.0, 1.0})
    love.graphics.draw(canvas_blur_h, 0, 0)

    -- 4. Final Combine
    love.graphics.setCanvas() -- Back to screen
    love.graphics.setShader()
    
    -- Draw original scene
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas_main, 0, 0)
    -- Draw bloom (additive)
    -- love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, 1) -- Adjust alpha for bloom intensity
    love.graphics.draw(canvas_blur_v, 0, 0, 0, 2, 2) -- Upscale back
    -- love.graphics.draw(canvas_blur_v, 0, 0, 0, 2, 2) -- Draw twice for extra glow!
    love.graphics.setBlendMode("alpha")
end

function bloom.resize(w, h)
    bloom.init(w, h)
end

return bloom
