local vfx = {
    enabled = true
}

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
        extern number style;

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

            number spokeRaw = abs(sin(ang * spikes + seed * 6.283 + time * 8.0));
            number spoke = smoothstep(0.72, 0.98, spokeRaw);
            spoke *= smoothstep(0.85 + 0.15 * t, 0.15 + 0.25 * t, r);

            number n = noise(uv * 10.0 + vec2(time * 0.9, -time * 0.7));
            number grit = smoothstep(0.55, 1.0, n) * smoothstep(0.95, 0.25, r);

            number fade = (1.0 - t);
            // style: 0=default burst, 1=electric sparks, 2=embers, 3=ice crack/shatter
            number intensity0 = (core * 0.9 + ring * 0.7 + spoke * 0.9 + grit * 0.35) * baseEdge;
            intensity0 *= (0.35 + 0.65 * fade);

            number sparkThin = pow(spokeRaw, 10.0);
            number spark = smoothstep(0.35, 1.0, sparkThin) * smoothstep(0.95, 0.10 + 0.25 * t, r);
            number sparkDots = smoothstep(0.80, 1.0, n) * smoothstep(0.85, 0.20, r);
            number intensity1 = (spark * 1.10 + sparkDots * 0.55 + core * 0.25) * baseEdge;
            intensity1 *= (0.35 + 0.65 * fade);

            number emberFlick = 0.80 + 0.20 * sin(time * 12.0 + seed * 17.0 + r * 5.0);
            number intensity2 = (core * 0.55 + grit * 0.85 + spoke * 0.20) * baseEdge;
            intensity2 *= emberFlick * (0.35 + 0.65 * fade);

            number shard = smoothstep(0.78, 0.98, abs(sin(ang * (spikes * 0.65) + seed * 11.7)));
            shard *= smoothstep(0.92, 0.18 + 0.25 * t, r);
            number intensity3 = (shard * 1.05 + grit * 0.35 + ring * 0.25) * baseEdge;
            intensity3 *= (0.35 + 0.65 * fade);

            number w0 = 1.0 - step(0.5, style);
            number w1 = step(0.5, style) * (1.0 - step(1.5, style));
            number w2 = step(1.5, style) * (1.0 - step(2.5, style));
            number w3 = step(2.5, style);
            number intensity = intensity0 * w0 + intensity1 * w1 + intensity2 * w2 + intensity3 * w3;
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
        extern number u_length; // 传入当前段的实际显示长度

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

            // 使用实际像素长度来缩放 X，使噪声频率不随长度拉伸而改变
            // 这里的 100.0 是参考缩放系数
            number worldX = x * u_length / 100.0;

            number tStep = floor(time * 30.0) * 0.13;
            number nA = segNoise(worldX * 1.5, 12.0, tStep);
            number nB = segNoise(worldX * 2.5, 24.0, tStep + 5.7);
            number n = (nA * 0.7 + nB * 0.3) * 2.0 - 1.0;

            number micro = (hash1(uv.x * 100.0 + time * 10.0) - 0.5) * 0.05;
            
            number offset = (n * 0.35 + micro);
            number center = 0.5 + offset;

            number dist = abs(y - center);
            number core = smoothstep(0.08, 0.02, dist);
            number glow = smoothstep(0.35, 0.0, dist) * 0.5;

            number flicker = 0.75 + 0.25 * sin(time * 60.0 + uv.x * 20.0);
            number intensity = (core * 1.2 + glow) * flicker * alpha;
            intensity = clamp(intensity, 0.0, 1.2);

            vec3 colCore = vec3(1.0, 1.0, 1.0);
            vec3 colGlow = vec3(0.4, 0.7, 1.0);
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
    local style = 0
    if key == 'static_hit' or key == 'shock' or key == 'magnetic_hit' then
        colA = {0.65, 0.90, 1.00}
        colB = {1.00, 1.00, 1.00}
        spikeCount = 16
        style = 1
    elseif key == 'impact_hit' then
        colA = {0.85, 0.62, 0.28}
        colB = {1.00, 0.95, 0.80}
        spikeCount = 8
    elseif key == 'ice_shatter' then
        colA = {0.35, 0.75, 1.00}
        colB = {0.85, 0.95, 1.00}
        spikeCount = 14
        style = 3
    elseif key == 'ember' then
        colA = {1.00, 0.45, 0.12}
        colB = {1.00, 0.95, 0.55}
        spikeCount = 9
        style = 2
    elseif key == 'toxin_hit' then
        colA = {0.20, 1.00, 0.35}
        colB = {0.80, 1.00, 0.60}
        spikeCount = 10
    elseif key == 'gas_hit' then
        colA = {0.45, 1.00, 0.25}
        colB = {0.90, 1.00, 0.55}
        spikeCount = 10
    elseif key == 'bleed_hit' then
        colA = {1.00, 0.22, 0.22}
        colB = {1.00, 0.85, 0.85}
        spikeCount = 10
    elseif key == 'viral_hit' then
        colA = {0.85, 0.35, 1.00}
        colB = {0.95, 0.80, 1.00}
        spikeCount = 11
    elseif key == 'corrosive_hit' then
        colA = {0.78, 1.00, 0.22}
        colB = {1.00, 1.00, 0.80}
        spikeCount = 11
    elseif key == 'blast_hit' then
        colA = {1.00, 0.65, 0.20}
        colB = {1.00, 1.00, 0.75}
        spikeCount = 10
    elseif key == 'puncture_hit' then
        colA = {1.00, 0.95, 0.55}
        colB = {1.00, 1.00, 1.00}
        spikeCount = 10
    elseif key == 'radiation_hit' then
        colA = {0.85, 1.00, 0.25}
        colB = {1.00, 1.00, 0.65}
        spikeCount = 12
    end

    progress = progress or 0
    scale = scale or 1
    alpha = alpha or 1
    local baseSize = 28
    if style == 1 then baseSize = 22
    elseif style == 2 then baseSize = 24
    elseif style == 3 then baseSize = 26
    end
    local size = baseSize * scale

    local alphaMul = 0.95
    if style == 1 then alphaMul = 0.85
    elseif style == 3 then alphaMul = 0.82
    end

    local t = timeNow()
    local seed = ((x * 0.013) + (y * 0.017)) % 1

    local function doDraw(isBloom)
        love.graphics.setBlendMode('add')
        love.graphics.setShader(_shHitBurst)
        _shHitBurst:send('time', t)
        _shHitBurst:send('progress', progress)
        _shHitBurst:send('alpha', isBloom and (0.80 * alphaMul * alpha) or (alphaMul * alpha))
        _shHitBurst:send('colA', colA)
        _shHitBurst:send('colB', colB)
        _shHitBurst:send('spikes', spikeCount)
        _shHitBurst:send('seed', seed)
        _shHitBurst:send('style', style)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_pixel, x - size * 0.5, y - size * 0.5, 0, size, size)

        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
    end

    doDraw(false)
end

function vfx.drawLightningSegment(x1, y1, x2, y2, width, alpha, progress)
    vfx.init()
    progress = progress or 1
    if not canDraw() then
        love.graphics.setColor(0.9, 0.95, 1, 0.9 * alpha)
        love.graphics.setLineWidth(width or 2)
        local px = x1 + (x2 - x1) * progress
        local py = y1 + (y2 - y1) * progress
        love.graphics.line(x1, y1, px, py)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        return
    end

    alpha = alpha or 1
    width = width or 18

    local dx = x2 - x1
    local dy = y2 - y1
    local totalLen = math.sqrt(dx * dx + dy * dy)
    if totalLen < 1 then return end

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
        if l < 0.1 then return end

        local ang = math.atan2(ddy, ddx)

        love.graphics.setBlendMode('add')
        love.graphics.setShader(_shLightning)
        _shLightning:send('time', t)
        _shLightning:send('alpha', a)
        _shLightning:send('u_length', l) -- 关键：告知着色器这一段有多长

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
        -- main bolt: subdivision counts based on FULL length to keep jitter static
        local alphaMain = clamp(alpha * (0.85 + 0.15 * (18 / math.max(6, width))), 0, 0.95)
        if isBloom then alphaMain = clamp(alphaMain * 0.7, 0, 0.7) end

        -- 关键：基于最终总长度确定分段数，确保生长过程中段数不跳变
        local segs = math.max(2, math.floor(totalLen / 40))
        if totalLen > 300 then segs = 5 end
        
        local jitterAmt = 12 * (width / 14)
        local nx, ny = -dy / totalLen, dx / totalLen -- 基于最终方向的法线

        local lastX, lastY = x1, y1
        for i = 1, segs do
            local tEnd = i / segs
            -- 如果这一段完全超过了进度，就跳过
            if (i-1) / segs > progress then break end

            local targetT = math.min(progress, tEnd)
            local tx = x1 + dx * targetT
            local ty = y1 + dy * targetT
            
            -- 为每个分段节点添加固定的抖动（基于 i，而非当前长度）
            if i < segs and tEnd <= progress then
                local seed = hash01(x1 + i, y1 - i)
                local offset = (seed * 2.0 - 1.0) * jitterAmt
                tx = tx + nx * offset
                ty = ty + ny * offset
            end

            drawRaw(lastX, lastY, tx, ty, width * 1.5, alphaMain)
            lastX, lastY = tx, ty
            
            -- 如果这一段是进度截断点，说明画完了
            if tEnd >= progress then break end
        end

        -- 分支逻辑 (仅在已经生长到的部分显示)
        local seedA = hash01(x1 + x2, y1 + y2)
        local seedB = hash01(x1 - x2, y1 - y2)
        local branchCount = (seedA > 0.65) and 2 or 1
        
        for i = 1, branchCount do
            local phase = (t * (1.2 + 0.35 * i) + seedB * 3.7 + i * 11.3)
            local along = 0.2 + 0.6 * ((seedA + 0.3 * i + (math.sin(phase) * 0.5 + 0.5) * 0.2) % 1)
            
            -- 只有当分支点已经长出来时才绘制
            if along <= progress then
                local px = x1 + dx * along
                local py = y1 + dy * along

                local side = (((seedB * 100 + i) % 2) < 1) and -1 or 1
                local off = side * (0.12 + 0.15 * ((seedA + i * 0.13) % 1)) * width
                px = px + nx * off
                py = py + ny * off

                -- 分支也需要根据整体缩放，但可以简化
                local bl = math.min(totalLen * (0.25 + 0.15 * ((seedB + i * 0.21) % 1)), 80)
                local bang = angle + side * (0.6 + 0.4 * ((seedA + i * 0.19) % 1))
                local bx = px + math.cos(bang) * bl
                local by = py + math.sin(bang) * bl

                local bw = math.max(4, width * 0.35)
                local ba = clamp(alphaMain * 0.4, 0, 0.5)
                if isBloom then ba = clamp(ba * 0.75, 0, 0.4) end
                drawRaw(px, py, bx, by, bw, ba)
            end
        end
    end

    doDraw(false)
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

    if kind == 'telegraph' or kind == 'danger' then
        return {
            colA = {1.00, 0.18, 0.18},
            colB = {1.00, 0.60, 0.22},
            noiseScale = 7.0,
            flowAmp = 0.05,
            edgeSoft = 0.56,
            alphaCap = 0.60,
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
