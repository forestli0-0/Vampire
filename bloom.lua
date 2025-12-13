local bloom = {}

local canvas_main
local canvas_bright
local canvas_blur_h
local canvas_blur_v
local shader_blur
local shader_extract

local down_w
local down_h

local bloom_threshold = 0.78
local bloom_knee = 0.22
local bloom_intensity = 1.0

function bloom.init(w, h)
    canvas_main = love.graphics.newCanvas(w, h)
    down_w = math.max(1, math.floor(w / 2))
    down_h = math.max(1, math.floor(h / 2))
    canvas_bright = love.graphics.newCanvas(down_w, down_h) -- Downscale for performance and better blur
    canvas_blur_h = love.graphics.newCanvas(down_w, down_h)
    canvas_blur_v = love.graphics.newCanvas(down_w, down_h)

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

    -- Bright-pass extraction (automatic bloom): keep only highlights with soft knee.
    shader_extract = love.graphics.newShader[[
        extern number threshold;
        extern number knee;

        number luminance(vec3 c) {
            return dot(c, vec3(0.2126, 0.7152, 0.0722));
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec4 c = Texel(texture, uv) * color;
            number l = luminance(c.rgb);

            number k = max(1e-6, knee);
            number soft = clamp((l - threshold + k) / (2.0 * k), 0.0, 1.0);
            number w = max(l - threshold, soft * soft * (2.0 * k));

            // Preserve hue; weight by highlight energy.
            vec3 outRgb = c.rgb * w;
            return vec4(outRgb, 1.0);
        }
    ]]
end

function bloom.preDraw()
    love.graphics.setCanvas(canvas_main)
    love.graphics.clear()
end

function bloom.postDraw()
    love.graphics.setCanvas() -- Reset to screen

    -- 1. Downscale + extract highlights from main
    love.graphics.setCanvas(canvas_bright)
    love.graphics.clear()
    love.graphics.setShader(shader_extract)
    shader_extract:send("threshold", bloom_threshold)
    shader_extract:send("knee", bloom_knee)
    love.graphics.setColor(1, 1, 1, 1)
    local sx = down_w / canvas_main:getWidth()
    local sy = down_h / canvas_main:getHeight()
    love.graphics.draw(canvas_main, 0, 0, 0, sx, sy) -- Draw downscaled

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
    love.graphics.setBlendMode("add")
    love.graphics.setColor(bloom_intensity, bloom_intensity, bloom_intensity, 1)
    local usx = canvas_main:getWidth() / down_w
    local usy = canvas_main:getHeight() / down_h
    love.graphics.draw(canvas_blur_v, 0, 0, 0, usx, usy) -- Upscale back
    love.graphics.setBlendMode("alpha")
end

function bloom.resize(w, h)
    bloom.init(w, h)
end

return bloom
