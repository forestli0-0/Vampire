local vfx = {
    enabled = true
}

local _inited = false
local _pixel = nil

local _shExplosion
local _shGas
local _shElectricAura
local _shLightning

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

        vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
            number x = uv.x;
            number y = uv.y;

            number w1 = sin(x * 28.0 + time * 26.0);
            number w2 = sin(x * 61.0 - time * 33.0) * 0.6;
            number w3 = sin(x * 103.0 + time * 41.0) * 0.25;
            number offset = (w1 + w2 + w3) * 0.08;

            number dist = abs((y - 0.5) - offset);
            number core = smoothstep(0.055, 0.0, dist);
            number glow = smoothstep(0.22, 0.0, dist) * 0.45;

            number flicker = 0.75 + 0.25 * sin(time * 55.0 + x * 12.0);
            number intensity = (core + glow) * flicker * alpha;

            vec3 col = mix(vec3(0.55, 0.85, 1.0), vec3(1.0, 0.95, 0.6), core);
            return vec4(col * intensity, intensity);
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

    love.graphics.setBlendMode('alpha')
    love.graphics.setShader(_shExplosion)
    _shExplosion:send('time', t)
    _shExplosion:send('progress', progress or 0)
    _shExplosion:send('alpha', alpha)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

    love.graphics.setShader()
    love.graphics.setBlendMode('alpha')
end

function vfx.drawGas(x, y, radius, alpha)
    vfx.init()
    if not canDraw() then
        love.graphics.setColor(0.2, 1, 0.2, 0.12)
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    alpha = alpha or 1

    if not _shGas then
        love.graphics.setColor(0.2, 1, 0.2, 0.12 * alpha)
        love.graphics.circle('fill', x, y, radius)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local t = timeNow()
    local size = radius * 2

    love.graphics.setBlendMode('alpha')
    love.graphics.setShader(_shGas)
    _shGas:send('time', t)
    _shGas:send('alpha', 0.85 * alpha)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
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

    love.graphics.setBlendMode('add')
    love.graphics.setShader(_shElectricAura)
    _shElectricAura:send('time', t)
    _shElectricAura:send('alpha', 0.9 * alpha)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(_pixel, x - radius, y - radius, 0, size, size)

    love.graphics.setShader()
    love.graphics.setBlendMode('alpha')
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

    love.graphics.setBlendMode('add')
    love.graphics.setShader(_shLightning)
    _shLightning:send('time', t)
    _shLightning:send('alpha', alpha)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(x1, y1)
    love.graphics.rotate(angle)
    love.graphics.draw(_pixel, 0, -width * 0.5, 0, len, width)
    love.graphics.pop()

    love.graphics.setShader()
    love.graphics.setBlendMode('alpha')
end

return vfx
