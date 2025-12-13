local vfx = {
    enabled = true
}

local _bloomEnabledFn
local _bloomGetCanvasFn

local _inited = false
local _pixel = nil

local _shExplosion
local _shGas
local _shElectricAura
local _shLightning
local _shAreaField
local _shHitBurst

local function safeNewShader(src)
    if not love or not love.graphics or not love.graphics.newShader then return nil end
    local ok, sh = pcall(love.graphics.newShader, src)
    if ok then return sh end
    return nil
end

local function ensurePixel()
    if _pixel then return _pixel end
    if not love or not love.image or not love.graphics then return nil end
    local data = love.image.newImageData(1, 1)
    data:setPixel(0, 0, 1, 1, 1, 1)
    local img = love.graphics.newImage(data)
    img:setFilter('linear', 'linear')
    _pixel = img
    return _pixel
end

function vfx.init()
    if _inited then return end
    _inited = true

    ensurePixel()

    _shExplosion = safeNewShader[[
        extern number time;
        extern number progress;
        extern number alpha;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 p = uv - vec2(0.5);
            number d = length(p) * 2.0; // 0..1 at edge

            number t = clamp(progress, 0.0, 1.0);
            number ring = smoothstep(t, t - 0.06, d) * smoothstep(t + 0.18, t + 0.06, d);
            number flash = smoothstep(0.18, 0.0, t) * smoothstep(1.0, 0.0, d);

            number n = noise(uv * 9.0 + vec2(time * 0.9, -time * 0.6));
            number sparks = smoothstep(0.85, 1.0, n) * smoothstep(t + 0.05, t - 0.12, d);

            number intensity = ring * (0.8 + 0.6 * n) + flash * 0.9 + sparks * 0.8;
            intensity = clamp(intensity, 0.0, 1.2);

            vec3 col = mix(vec3(1.0, 0.75, 0.25), vec3(1.0, 0.25, 0.05), d);
            col += vec3(0.4, 0.35, 0.2) * flash;

            number a = intensity * alpha;
            return vec4(col * a, a);
        }
    ]]

    _shGas = safeNewShader[[
        extern number time;
        extern number alpha;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 p = uv - vec2(0.5);
            number d = length(p) * 2.0;
            number edge = smoothstep(1.0, 0.55, d);

            vec2 flow = vec2(
                sin(time * 0.7 + uv.y * 6.0),
                cos(time * 0.6 + uv.x * 6.0)
            ) * 0.06;

            number n1 = noise((uv + flow) * 6.0 + vec2(time * 0.12, time * 0.08));
            number n2 = noise((uv - flow) * 12.0 + vec2(-time * 0.18, time * 0.11));
            number n = (n1 * 0.65 + n2 * 0.35);

            number density = edge * smoothstep(0.25, 0.85, n);
            number a = density * alpha;

            vec3 col = mix(vec3(0.15, 0.85, 0.25), vec3(0.35, 1.0, 0.55), n);
            return vec4(col * a, a);
        }
    ]]

    _shHitBurst = safeNewShader[[
        extern number time;
        extern number progress;
        extern number alpha;
        extern vec3 colA;
        extern vec3 colB;
        extern number spikes;
        extern number seed;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 19.19) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 p = uv - vec2(0.5);
            number r = length(p) * 2.0;
            number ang = atan(p.y, p.x);

            number t = clamp(progress, 0.0, 1.0);

            number baseEdge = smoothstep(1.0, 0.0, r);
            number ring = smoothstep(t * 0.95 + 0.18, t * 0.95, r) * smoothstep(t * 0.95 - 0.08, t * 0.95, r);
            number core = smoothstep(0.22 + 0.12 * t, 0.0, r);

            number spoke = abs(sin(ang * spikes + seed * 6.283 + time * 8.0));
            spoke = smoothstep(0.72, 0.98, spoke);
            spoke *= smoothstep(0.85 + 0.15 * t, 0.15 + 0.25 * t, r);

            number n = noise(uv * 10.0 + vec2(time * 0.9, -time * 0.7));
            number grit = smoothstep(0.55, 1.0, n) * smoothstep(0.95, 0.25, r);

            number fade = (1.0 - t);
            number intensity = (core * 0.9 + ring * 0.7 + spoke * 0.9 + grit * 0.35) * baseEdge;
            intensity *= (0.35 + 0.65 * fade);
            intensity = clamp(intensity, 0.0, 1.25);

            vec3 col = mix(colA, colB, clamp(r + n * 0.35, 0.0, 1.0));
            number a = intensity * alpha;
            return vec4(col * a, a);
        }
    ]]

    _shElectricAura = safeNewShader[[
        extern number time;
        extern number alpha;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(12.7, 78.2))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 p = uv - vec2(0.5);
            number d = length(p) * 2.0;

            number n = noise(uv * 14.0 + vec2(time * 1.6, -time * 1.2));
            number ring = smoothstep(0.72, 0.62, d) * smoothstep(0.92, 0.82, d);
            number arcs = smoothstep(0.55, 0.92, n) * ring;
            number core = smoothstep(0.55, 0.0, d) * 0.06;

            number intensity = (arcs * (0.7 + 0.6 * n) + core) * alpha;

            vec3 col = mix(vec3(0.55, 0.85, 1.0), vec3(1.0, 0.95, 0.35), n);
            return vec4(col * intensity, intensity);
        }
    ]]

    _shLightning = safeNewShader[[
        extern number time;
        extern number alpha;

        number hash1(number n) {
            return fract(sin(n) * 43758.5453);
        }

        number hash2(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }

        number segNoise(number x, number segs, number t) {
            number s = floor(x * segs);
            number f = fract(x * segs);
            number a = hash2(vec2(s, t));
            number b = hash2(vec2(s + 1.0, t));
            number u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u);
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            number x = uv.x;
            number y = uv.y;

            // segmented jitter (less "sine noodle", more bolt)
            number tStep = floor(time * 60.0) * 0.17;
            number nA = segNoise(x + time * 0.35, 26.0, tStep);
            number nB = segNoise(x - time * 0.25, 52.0, tStep + 7.3);
            number n = (nA * 0.65 + nB * 0.35) * 2.0 - 1.0;

            number sway = sin(x * 9.0 + time * 8.0) * 0.18;
            number offset = (n * 0.22 + sway) * 0.18;
            number center = 0.5 + offset;

            number dist = abs(y - center);
            number core = smoothstep(0.06, 0.0, dist);
            number glow = smoothstep(0.26, 0.0, dist) * 0.40;

            // occasional hot streaks along the bolt
            number sparkN = segNoise(x + time * 0.9, 18.0, tStep + 13.7);
            number sparks = smoothstep(0.86, 0.98, sparkN) * core * 0.55;

            number flicker = 0.78 + 0.22 * sin(time * 48.0 + x * 15.0);
            number intensity = (core * 1.05 + glow + sparks) * flicker * alpha;
            intensity = min(intensity, 1.0);

            vec3 colCore = vec3(1.0, 0.98, 0.75);
            vec3 colGlow = vec3(0.50, 0.82, 1.0);
            vec3 col = mix(colGlow, colCore, core);
            return vec4(col * intensity, intensity);
        }
    ]]

    _shAreaField = safeNewShader[[
        extern number time;
        extern number alpha;
        extern number intensity;

        extern vec3 colA;
        extern vec3 colB;

        extern number noiseScale;
        extern number flowAmp;
        extern number edgeSoft;
        extern number alphaCap;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            number a = hash(i);
            number b = hash(i + vec2(1.0, 0.0));
            number c = hash(i + vec2(0.0, 1.0));
            number d = hash(i + vec2(1.0, 1.0));
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
        }

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            vec2 p = uv - vec2(0.5);
            number d = length(p) * 2.0; // 0..1 at edge

            number i = clamp(intensity, 0.0, 2.0);
            number soft = max(0.02, edgeSoft);
            number edge = smoothstep(1.0, 1.0 - soft, d);

            vec2 flow = vec2(
                sin(time * 0.65 + uv.y * 6.0),
                cos(time * 0.55 + uv.x * 6.0)
            ) * (flowAmp * (0.55 + 0.45 * i));

            number n1 = noise((uv + flow) * noiseScale + vec2(time * 0.10, time * 0.07));
            number n2 = noise((uv - flow) * (noiseScale * 1.9) + vec2(-time * 0.15, time * 0.11));
            number n = (n1 * 0.65 + n2 * 0.35);

            number thresh = mix(0.28, 0.18, clamp(i, 0.0, 1.0));
            number density = edge * smoothstep(thresh, 0.92, n);

            // very subtle rim to keep readability without making it bloom too much
            number rim = smoothstep(0.95, 0.72, d) * smoothstep(1.0, 0.92, n) * (0.10 + 0.10 * i);

            number a = (density + rim) * alpha;
            a = min(a, alphaCap);

            vec3 col = mix(colA, colB, n);
            return vec4(col * a, a);
        }
    ]]
end

function vfx.toggle()
    vfx.enabled = not vfx.enabled
end

function vfx.setBloomEmitter(enabledFn, getCanvasFn)
    _bloomEnabledFn = enabledFn
    _bloomGetCanvasFn = getCanvasFn
end

local function drawToBloomAlso(drawFn)
    if not _bloomEnabledFn or not _bloomGetCanvasFn then return end
    if not _bloomEnabledFn() then return end
    local c = _bloomGetCanvasFn()
    if not c then return end

    local prevCanvas = love.graphics.getCanvas()
    local bm, am = love.graphics.getBlendMode()

    love.graphics.setCanvas(c)
    drawFn(true)

    love.graphics.setCanvas(prevCanvas)
    love.graphics.setBlendMode(bm, am)
end

local function timeNow()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return 0
end

local function canDraw()
    if not vfx.enabled then return false end
    if not love or not love.graphics then return false end
    return ensurePixel() ~= nil
end

function vfx.drawExplosion(x, y, radius, progress, alpha)
    vfx.init()
    if not canDraw() then
        love.graphics.setColor(1, 0.6, 0.2, 0.35)
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    alpha = alpha or 1

    if not _shExplosion then
        love.graphics.setColor(1, 0.6, 0.2, 0.35 * alpha)
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local t = timeNow()
    local size = radius * 2

    local function doDraw(isBloom)
        love.graphics.setBlendMode('alpha')
        love.graphics.setShader(_shExplosion)
        _shExplosion:send('time', t)
        _shExplosion:send('progress', progress or 0)
        _shExplosion:send('alpha', isBloom and (0.85 * alpha) or alpha)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
    end

    doDraw(false)
    drawToBloomAlso(doDraw)
end

function vfx.drawGas(x, y, radius, alpha)
    alpha = alpha or 1
    vfx.drawAreaField('gas', x, y, radius, 1, { alpha = 0.85 * alpha })
end

function vfx.drawElectricAura(x, y, radius, alpha)
    vfx.init()
    if not canDraw() then
        love.graphics.setColor(1, 1, 0, 0.35)
        love.graphics.circle('line', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    alpha = alpha or 1

    if not _shElectricAura then
        love.graphics.setColor(1, 1, 0, 0.35 * alpha)
        love.graphics.circle('line', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local t = timeNow()
    local size = radius * 2

    local function doDraw(isBloom)
        love.graphics.setBlendMode('add')
        love.graphics.setShader(_shElectricAura)
        _shElectricAura:send('time', t)
        _shElectricAura:send('alpha', isBloom and (0.7 * alpha) or (0.9 * alpha))

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
    end

    doDraw(false)
    drawToBloomAlso(doDraw)
end

function vfx.drawHitEffect(key, x, y, progress, scale, alpha)
    vfx.init()
    if not canDraw() then
        alpha = alpha or 1
        progress = progress or 0
        scale = scale or 1
        local s = 10 * scale
        local a = (1 - progress) * 0.55 * alpha
        love.graphics.setBlendMode('add')
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.circle('fill', x, y, s * 0.35)
        love.graphics.setColor(1, 0.8, 0.35, a)
        love.graphics.circle('line', x, y, s)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    if not _shHitBurst then
        alpha = alpha or 1
        progress = progress or 0
        scale = scale or 1
        local s = 10 * scale
        local a = (1 - progress) * 0.55 * alpha
        love.graphics.setBlendMode('add')
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.circle('fill', x, y, s * 0.35)
        love.graphics.setColor(1, 0.8, 0.35, a)
        love.graphics.circle('line', x, y, s)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    local colA = {1.0, 0.85, 0.30}
    local colB = {1.0, 1.0, 1.0}
    local spikeCount = 10
    if key == 'static_hit' or key == 'shock' then
        colA = {0.65, 0.90, 1.00}
        colB = {1.00, 1.00, 1.00}
        spikeCount = 12
    elseif key == 'ice_shatter' then
        colA = {0.35, 0.75, 1.00}
        colB = {0.85, 0.95, 1.00}
        spikeCount = 11
    elseif key == 'ember' then
        colA = {1.00, 0.45, 0.12}
        colB = {1.00, 0.95, 0.55}
        spikeCount = 9
    end

    progress = progress or 0
    scale = scale or 1
    alpha = alpha or 1
    local size = 28 * scale

    local t = timeNow()
    local seed = ((x * 0.013) + (y * 0.017)) % 1

    local function doDraw(isBloom)
        love.graphics.setBlendMode('add')
        love.graphics.setShader(_shHitBurst)
        _shHitBurst:send('time', t)
        _shHitBurst:send('progress', progress)
        _shHitBurst:send('alpha', isBloom and (0.80 * 0.95 * alpha) or (0.95 * alpha))
        _shHitBurst:send('colA', colA)
        _shHitBurst:send('colB', colB)
        _shHitBurst:send('spikes', spikeCount)
        _shHitBurst:send('seed', seed)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_pixel, x - size * 0.5, y - size * 0.5, 0, size, size)

        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
    end

    doDraw(false)
    drawToBloomAlso(doDraw)
end

function vfx.drawLightningSegment(x1, y1, x2, y2, width, alpha)
    vfx.init()
    if not canDraw() then
        love.graphics.setColor(0.9, 0.95, 1, 0.9)
        love.graphics.setLineWidth(width or 2)
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        return
    end

    alpha = alpha or 1
    width = width or 18

    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    if not _shLightning then
        love.graphics.setColor(0.9, 0.95, 1, 0.9 * alpha)
        love.graphics.setLineWidth(3)
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local angle = math.atan2(dy, dx)
    local t = timeNow()

    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function hash01(a, b)
        return (math.sin(a * 12.9898 + b * 78.233) * 43758.5453) % 1
    end

    local function drawRaw(ax, ay, bx, by, w, a)
        local ddx = bx - ax
        local ddy = by - ay
        local l = math.sqrt(ddx * ddx + ddy * ddy)
        if l < 1 then return end

        local ang = math.atan2(ddy, ddx)

        love.graphics.setBlendMode('add')
        love.graphics.setShader(_shLightning)
        _shLightning:send('time', t)
        _shLightning:send('alpha', a)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.push()
        love.graphics.translate(ax, ay)
        love.graphics.rotate(ang)
        love.graphics.draw(_pixel, 0, -w * 0.5, 0, l, w)
        love.graphics.pop()

        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
    end

    local function doDraw(isBloom)
        -- main bolt (cap alpha to avoid bloom washout at large widths)
        local alphaMain = clamp(alpha * (0.85 + 0.15 * (18 / math.max(6, width))), 0, 0.95)
        if isBloom then alphaMain = clamp(alphaMain * 0.7, 0, 0.7) end
        drawRaw(x1, y1, x2, y2, width, alphaMain)

        -- subtle sub-filaments / branching for depth (low alpha, thin)
        local seedA = hash01(x1 + x2, y1 + y2)
        local seedB = hash01(x1 - x2, y1 - y2)
        local branchCount = (seedA > 0.55) and 2 or 1
        local nx = -dy / len
        local ny = dx / len

        for i = 1, branchCount do
            local phase = (t * (1.2 + 0.35 * i) + seedB * 3.7 + i * 11.3)
            local along = 0.22 + 0.56 * ((seedA + 0.37 * i + (math.sin(phase) * 0.5 + 0.5) * 0.35) % 1)
            local px = x1 + dx * along
            local py = y1 + dy * along

            local side = (((seedB * 100 + i) % 2) < 1) and -1 or 1
            local off = side * (0.08 + 0.10 * ((seedA + i * 0.13) % 1)) * width
            px = px + nx * off
            py = py + ny * off

            local bl = math.min(len * (0.22 + 0.12 * ((seedB + i * 0.21) % 1)), 70)
            local bang = angle + side * (0.55 + 0.35 * ((seedA + i * 0.19) % 1))
            local bx = px + math.cos(bang) * bl
            local by = py + math.sin(bang) * bl

            local bw = math.max(4, width * 0.38)
            local ba = clamp(alphaMain * 0.35, 0, 0.45)
            if isBloom then ba = clamp(ba * 0.75, 0, 0.35) end
            drawRaw(px, py, bx, by, bw, ba)
        end
    end

    doDraw(false)
    drawToBloomAlso(doDraw)
end

local function presetForKind(kind)
    -- 统一：范围场走 alpha，不贡献大面积高亮；颜色只做轻微层次
    if kind == 'gas' then
        return {
            colA = {0.15, 0.85, 0.25},
            colB = {0.35, 1.00, 0.55},
            noiseScale = 6.0,
            flowAmp = 0.06,
            edgeSoft = 0.45,
            alphaCap = 0.55,
            blend = 'alpha'
        }
    end

    if kind == 'toxin' then
        return {
            colA = {0.10, 0.55, 0.18},
            colB = {0.25, 0.90, 0.35},
            noiseScale = 7.2,
            flowAmp = 0.05,
            edgeSoft = 0.55,
            alphaCap = 0.42,
            blend = 'alpha'
        }
    end

    if kind == 'ice' or kind == 'ice_ring' then
        return {
            colA = {0.20, 0.55, 0.95},
            colB = {0.55, 0.85, 1.00},
            noiseScale = 7.5,
            flowAmp = 0.045,
            edgeSoft = 0.55,
            alphaCap = 0.40,
            blend = 'alpha'
        }
    end

    if kind == 'garlic' then
        return {
            colA = {0.75, 0.72, 0.62},
            colB = {0.95, 0.90, 0.80},
            noiseScale = 5.5,
            flowAmp = 0.035,
            edgeSoft = 0.58,
            alphaCap = 0.32,
            blend = 'alpha'
        }
    end

    if kind == 'soul_eater' then
        return {
            colA = {0.55, 0.12, 0.55},
            colB = {0.95, 0.30, 0.85},
            noiseScale = 6.2,
            flowAmp = 0.055,
            edgeSoft = 0.52,
            alphaCap = 0.36,
            blend = 'alpha'
        }
    end

    if kind == 'absolute_zero' then
        return {
            colA = {0.25, 0.60, 0.95},
            colB = {0.70, 0.92, 1.00},
            noiseScale = 7.0,
            flowAmp = 0.05,
            edgeSoft = 0.62,
            alphaCap = 0.28,
            blend = 'alpha'
        }
    end

    if kind == 'oil' then
        return {
            colA = {0.08, 0.06, 0.05},
            colB = {0.22, 0.16, 0.10},
            noiseScale = 5.2,
            flowAmp = 0.028,
            edgeSoft = 0.68,
            alphaCap = 0.34,
            blend = 'alpha'
        }
    end

    if kind == 'freeze' then
        return {
            colA = {0.35, 0.65, 1.00},
            colB = {0.85, 0.95, 1.00},
            noiseScale = 8.5,
            flowAmp = 0.03,
            edgeSoft = 0.60,
            alphaCap = 0.30,
            blend = 'alpha'
        }
    end

    -- default
    return {
        colA = {0.8, 0.8, 0.8},
        colB = {1.0, 1.0, 1.0},
        noiseScale = 6.0,
        flowAmp = 0.04,
        edgeSoft = 0.55,
        alphaCap = 0.35,
        blend = 'alpha'
    }
end

function vfx.drawAreaField(kind, x, y, radius, intensity, opts)
    vfx.init()
    if not canDraw() then
        local p = presetForKind(kind)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(p.colB[1], p.colB[2], p.colB[3], math.min(p.alphaCap or 0.35, (opts and opts.alpha) or 0.3))
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    if not _shAreaField then
        local p = presetForKind(kind)
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(p.colB[1], p.colB[2], p.colB[3], math.min(p.alphaCap or 0.35, (opts and opts.alpha) or 0.3))
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local p = presetForKind(kind)
    local t = timeNow()
    local size = radius * 2
    intensity = intensity or 1

    -- allow per-call override
    local a = (opts and opts.alpha) or 1
    local noiseScale = (opts and opts.noiseScale) or p.noiseScale
    local flowAmp = (opts and opts.flowAmp) or p.flowAmp
    local edgeSoft = (opts and opts.edgeSoft) or p.edgeSoft
    local alphaCap = (opts and opts.alphaCap) or p.alphaCap

    love.graphics.setBlendMode(p.blend or 'alpha')
    love.graphics.setShader(_shAreaField)
    _shAreaField:send('time', t)
    _shAreaField:send('alpha', a)
    _shAreaField:send('intensity', intensity)
    _shAreaField:send('colA', p.colA)
    _shAreaField:send('colB', p.colB)
    _shAreaField:send('noiseScale', noiseScale)
    _shAreaField:send('flowAmp', flowAmp)
    _shAreaField:send('edgeSoft', edgeSoft)
    _shAreaField:send('alphaCap', alphaCap)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

    love.graphics.setShader()
    love.graphics.setBlendMode('alpha')
end

return vfx
