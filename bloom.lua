local bloom = {}

local canvas_main
local canvas_warp
local canvas_bright
local canvas_blur_h
local canvas_blur_v
local shader_blur
local shader_extract
local shader_combine
local shader_warp

local down_w
local down_h

local bloom_threshold = 0.78
local bloom_knee = 0.22
local bloom_intensity = 1.0

local tonemap_exposure = 1.15
local tonemap_amount = 0.0
local vignette_strength = 0.0
local vignette_power = 1.7

local warp_max_waves = 3
local warp_strength = 3.0 -- pixels
local warp_width = 42.0 -- pixels (ring thickness/falloff)
local warp_freq = 0.18 -- radians per pixel

local function collectWarpWaves(state)
    local waves = {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
    }
    if not state or not state.quakeEffects or not state.camera then
        return waves, 0
    end

    local candidates = {}
    for _, q in ipairs(state.quakeEffects) do
        local t = q.t or 0
        local dur = q.duration or 1.0
        if t >= 0 and dur > 0 then
            local p = math.max(0, math.min(1, t / dur))
            local radius = (q.radius or 220) * p
            local strength = warp_strength * (1.0 - p)
            local cx = (q.x or state.player.x) - state.camera.x
            local cy = (q.y or state.player.y) - state.camera.y
            table.insert(candidates, {cx = cx, cy = cy, r = radius, s = strength, p = p})
        end
    end

    table.sort(candidates, function(a, b) return a.p > b.p end)
    local count = math.min(#candidates, warp_max_waves)
    for i = 1, count do
        local c = candidates[i]
        waves[i] = {c.cx, c.cy, c.r, c.s}
    end
    return waves, count
end

function bloom.init(w, h)
    canvas_main = love.graphics.newCanvas(w, h)
    canvas_warp = love.graphics.newCanvas(w, h)
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

    -- Local shockwave warp (screen-space): distorts around quake wavefronts.
    shader_warp = love.graphics.newShader[[
        extern vec2 size;
        extern number width;
        extern number freq;
        extern vec4 wave0;
        extern vec4 wave1;
        extern vec4 wave2;
        extern vec4 wave3;

        vec2 applyWave(vec2 sc, vec2 uv, vec4 wv) {
            number strength = wv.w;
            if (strength <= 0.0) return vec2(0.0);
            vec2 center = wv.xy;
            number r = wv.z;
            vec2 d = sc - center;
            number dist = length(d);
            vec2 dir = d / (dist + 1e-4);
            number ring = sin((dist - r) * freq);
            number atten = exp(-abs(dist - r) / max(1e-3, width));
            number amp = strength * ring * atten;
            return dir * amp;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 offset = vec2(0.0);
            offset += applyWave(sc, uv, wave0);
            offset += applyWave(sc, uv, wave1);
            offset += applyWave(sc, uv, wave2);
            offset += applyWave(sc, uv, wave3);

            vec2 uv2 = uv + offset / size;
            uv2 = clamp(uv2, vec2(0.0), vec2(1.0));
            return Texel(texture, uv2) * color;
        }
    ]]

    -- Final combine: main + bloom, tonemap, then vignette.
    shader_combine = love.graphics.newShader[[
        extern Image bloomTex;
        extern number bloomIntensity;
        extern number exposure;
        extern number tonemapAmount;
        extern number vignetteStrength;
        extern number vignettePower;

        vec3 tonemapReinhard(vec3 hdr, number exposureVal) {
            vec3 x = hdr * exposureVal;
            return x / (x + vec3(1.0));
        }

        vec4 effect(vec4 color, Image mainTex, vec2 uv, vec2 sc) {
            vec3 mainCol = Texel(mainTex, uv).rgb;
            vec3 bloomCol = Texel(bloomTex, uv).rgb;

            vec3 hdr = mainCol + bloomCol * bloomIntensity;
            vec3 mapped = tonemapReinhard(hdr, exposure);
            vec3 ldr = mix(hdr, mapped, clamp(tonemapAmount, 0.0, 1.0));
            ldr = clamp(ldr, 0.0, 1.0);

            // Subtle vignette (screen-space)
            vec2 p = uv * 2.0 - 1.0;
            number d = clamp(dot(p, p), 0.0, 1.0);
            number vs = clamp(vignetteStrength, 0.0, 1.0);
            number v = 1.0 - vs * pow(d, vignettePower);
            ldr *= v;

            return vec4(ldr, 1.0);
        }
    ]]
end

function bloom.preDraw()
    love.graphics.setCanvas(canvas_main)
    love.graphics.clear()
end

function bloom.postDraw(state)
    love.graphics.setCanvas() -- Reset to screen

    local src = canvas_main
    local waves, waveCount = collectWarpWaves(state)
    if waveCount > 0 then
        love.graphics.setCanvas(canvas_warp)
        love.graphics.clear()
        love.graphics.setShader(shader_warp)
        shader_warp:send("size", {src:getWidth(), src:getHeight()})
        shader_warp:send("width", warp_width)
        shader_warp:send("freq", warp_freq)
        shader_warp:send("wave0", waves[1])
        shader_warp:send("wave1", waves[2])
        shader_warp:send("wave2", waves[3])
        shader_warp:send("wave3", waves[4])
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(src, 0, 0)
        love.graphics.setShader()
        src = canvas_warp
    end

    -- 1. Downscale + extract highlights from main
    love.graphics.setCanvas(canvas_bright)
    love.graphics.clear()
    love.graphics.setShader(shader_extract)
    shader_extract:send("threshold", bloom_threshold)
    shader_extract:send("knee", bloom_knee)
    love.graphics.setColor(1, 1, 1, 1)
    local sx = down_w / src:getWidth()
    local sy = down_h / src:getHeight()
    love.graphics.draw(src, 0, 0, 0, sx, sy) -- Draw downscaled

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

    -- 4. Final Combine (tonemap + vignette)
    love.graphics.setCanvas() -- Back to screen
    love.graphics.setBlendMode("alpha")

    love.graphics.setShader(shader_combine)
    shader_combine:send("bloomTex", canvas_blur_v)
    shader_combine:send("bloomIntensity", bloom_intensity)
    shader_combine:send("exposure", tonemap_exposure)
    shader_combine:send("tonemapAmount", tonemap_amount)
    shader_combine:send("vignetteStrength", vignette_strength)
    shader_combine:send("vignettePower", vignette_power)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(src, 0, 0)

    love.graphics.setShader()
end

function bloom.resize(w, h)
    bloom.init(w, h)
end

return bloom
