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
local warp_strength = 2.2 -- pixels
local warp_width = 30.0 -- pixels (ring thickness/falloff)
local warp_freq = 0.18 -- radians per pixel
local quake_visual_radius_scale = 0.85

-- Perf / adaptive quality (very lightweight): decimate expensive passes when FPS drops.
local perf_dt_smooth = 1 / 60
local perf_tier = 0 -- 0=full, 1=medium, 2=low
local perf_frame = 0
local perf_bloom_div = 1
local perf_warp_div = 1
local warp_max_waves_effective = warp_max_waves
local bloom_ready = false

local perf_fps_to_medium = 42
local perf_fps_to_full = 50
local perf_fps_to_low = 28
local perf_fps_to_medium_from_low = 34

local function collectWarpWaves(state)
    local waves = {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
    }
    if not state or not state.camera then
        return waves, 0
    end

    local candidates = {}
    if state.quakeEffects then
        for _, q in ipairs(state.quakeEffects) do
            local t = q.t or 0
            local dur = q.duration or 1.0
            if t >= 0 and dur > 0 then
                local p = math.max(0, math.min(1, t / dur))
                local radius = (q.radius or 220) * quake_visual_radius_scale * p
                local strength = warp_strength * (1.0 - p)
                local cx = (q.x or state.player.x) - state.camera.x
                local cy = (q.y or state.player.y) - state.camera.y
                table.insert(candidates, {cx = cx, cy = cy, r = radius, s = strength, sort = p})
            end
        end
    end

    if state.screenWaves then
        for _, w in ipairs(state.screenWaves) do
            local t = w.t or 0
            local dur = w.duration or 0.3
            if t >= 0 and dur > 0 then
                local p = math.max(0, math.min(1, t / dur))
                local radius = (w.radius or 140) * p
                local strength = (w.strength or 2.2) * (1.0 - p)
                local cx = (w.x or state.player.x) - state.camera.x
                local cy = (w.y or state.player.y) - state.camera.y
                -- 普通命中希望立刻可见：用 (1-p) 做排序权重
                table.insert(candidates, {cx = cx, cy = cy, r = radius, s = strength, sort = (1.0 - p)})
            end
        end
    end

    table.sort(candidates, function(a, b) return (a.sort or 0) > (b.sort or 0) end)
    local count = math.min(#candidates, warp_max_waves_effective)
    for i = 1, count do
        local c = candidates[i]
        waves[i] = {c.cx, c.cy, c.r, c.s}
    end
    return waves, count
end

function bloom.getParams()
    return {
        bloom_threshold = bloom_threshold,
        bloom_knee = bloom_knee,
        bloom_intensity = bloom_intensity,

        tonemap_exposure = tonemap_exposure,
        tonemap_amount = tonemap_amount,
        vignette_strength = vignette_strength,
        vignette_power = vignette_power,

        warp_max_waves = warp_max_waves,
        warp_strength = warp_strength,
        warp_width = warp_width,
        warp_freq = warp_freq,
        quake_visual_radius_scale = quake_visual_radius_scale,

        perf_fps_to_medium = perf_fps_to_medium,
        perf_fps_to_full = perf_fps_to_full,
        perf_fps_to_low = perf_fps_to_low,
        perf_fps_to_medium_from_low = perf_fps_to_medium_from_low,
    }
end

function bloom.setParams(p)
    if type(p) ~= 'table' then return bloom.getParams() end

    if p.bloom_threshold ~= nil then bloom_threshold = p.bloom_threshold end
    if p.bloom_knee ~= nil then bloom_knee = p.bloom_knee end
    if p.bloom_intensity ~= nil then bloom_intensity = p.bloom_intensity end

    if p.tonemap_exposure ~= nil then tonemap_exposure = p.tonemap_exposure end
    if p.tonemap_amount ~= nil then tonemap_amount = p.tonemap_amount end
    if p.vignette_strength ~= nil then vignette_strength = p.vignette_strength end
    if p.vignette_power ~= nil then vignette_power = p.vignette_power end

    if p.warp_max_waves ~= nil then warp_max_waves = p.warp_max_waves end
    if p.warp_strength ~= nil then warp_strength = p.warp_strength end
    if p.warp_width ~= nil then warp_width = p.warp_width end
    if p.warp_freq ~= nil then warp_freq = p.warp_freq end
    if p.quake_visual_radius_scale ~= nil then quake_visual_radius_scale = p.quake_visual_radius_scale end

    if p.perf_fps_to_medium ~= nil then perf_fps_to_medium = p.perf_fps_to_medium end
    if p.perf_fps_to_full ~= nil then perf_fps_to_full = p.perf_fps_to_full end
    if p.perf_fps_to_low ~= nil then perf_fps_to_low = p.perf_fps_to_low end
    if p.perf_fps_to_medium_from_low ~= nil then perf_fps_to_medium_from_low = p.perf_fps_to_medium_from_low end

    return bloom.getParams()
end

function bloom.update(dt)
    if type(dt) ~= 'number' or dt <= 0 then return end
    perf_frame = perf_frame + 1
    perf_dt_smooth = perf_dt_smooth * 0.92 + dt * 0.08
    local fps = 1 / math.max(1e-6, perf_dt_smooth)

    if perf_tier == 0 then
        if fps < perf_fps_to_low then
            perf_tier = 2
        elseif fps < perf_fps_to_medium then
            perf_tier = 1
        end
    elseif perf_tier == 1 then
        if fps < perf_fps_to_low then
            perf_tier = 2
        elseif fps > perf_fps_to_full then
            perf_tier = 0
        end
    else
        if fps > perf_fps_to_medium_from_low then
            perf_tier = 1
        end
    end

    if perf_tier == 0 then
        perf_bloom_div = 1
        perf_warp_div = 1
        warp_max_waves_effective = warp_max_waves
    elseif perf_tier == 1 then
        perf_bloom_div = 2
        perf_warp_div = 1
        warp_max_waves_effective = math.max(1, math.min(warp_max_waves, 2))
    else
        perf_bloom_div = 4
        perf_warp_div = 2
        warp_max_waves_effective = 1
    end
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
    local doWarp = (perf_warp_div <= 1) or (perf_frame % perf_warp_div == 0)
    local waves, waveCount = doWarp and collectWarpWaves(state) or nil, 0
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

    local doBloom = (perf_bloom_div <= 1) or (perf_frame % perf_bloom_div == 0) or (not bloom_ready)
    if doBloom then
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

        bloom_ready = true
    end

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
