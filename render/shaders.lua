local shaders = {}

local outlineShader
function shaders.getOutlineShader()
    if outlineShader then return outlineShader end
    outlineShader = love.graphics.newShader([[
        extern vec2 texelSize;
        extern number thickness;
        extern vec4 outlineColor;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
        {
            vec4 base = Texel(tex, uv);
            if (base.a > 0.001) {
                return vec4(0.0);
            }

            number a = 0.0;
            vec2 o = texelSize;

            a = max(a, Texel(tex, uv + vec2( o.x, 0.0)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x, 0.0)).a);
            a = max(a, Texel(tex, uv + vec2(0.0,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2(0.0, -o.y)).a);
            a = max(a, Texel(tex, uv + vec2( o.x,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x,  o.y)).a);
            a = max(a, Texel(tex, uv + vec2( o.x, -o.y)).a);
            a = max(a, Texel(tex, uv + vec2(-o.x, -o.y)).a);

            if (thickness > 1.5) {
                vec2 o2 = o * 2.0;
                a = max(a, Texel(tex, uv + vec2( o2.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(0.0,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(0.0, -o2.y)).a);
                a = max(a, Texel(tex, uv + vec2( o2.x,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x,  o2.y)).a);
                a = max(a, Texel(tex, uv + vec2( o2.x, -o2.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o2.x, -o2.y)).a);
            }

            if (thickness > 2.5) {
                vec2 o3 = o * 3.0;
                a = max(a, Texel(tex, uv + vec2( o3.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x, 0.0)).a);
                a = max(a, Texel(tex, uv + vec2(0.0,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(0.0, -o3.y)).a);
                a = max(a, Texel(tex, uv + vec2( o3.x,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x,  o3.y)).a);
                a = max(a, Texel(tex, uv + vec2( o3.x, -o3.y)).a);
                a = max(a, Texel(tex, uv + vec2(-o3.x, -o3.y)).a);
            }

            if (a > 0.001) {
                return outlineColor * a;
            }
            return vec4(0.0);
        }
    ]])
    return outlineShader
end

local dashTrailShader
function shaders.getDashTrailShader()
    if dashTrailShader ~= nil then return dashTrailShader or nil end
    if not love or not love.graphics or not love.graphics.newShader then
        dashTrailShader = false
        return nil
    end
    local ok, sh = pcall(love.graphics.newShader, [[
        extern number time;
        extern number alpha;
        extern vec3 tint;
        extern number warp;

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

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
        {
            vec4 base = Texel(tex, uv) * color;
            if (base.a <= 0.001) {
                return vec4(0.0);
            }

            number n = noise(uv * 10.0 + vec2(time * 2.3, -time * 1.9));
            vec2 duv = uv + (vec2(n, 1.0 - n) - 0.5) * warp;
            duv = clamp(duv, vec2(0.0), vec2(1.0));

            vec4 b2 = Texel(tex, duv) * color;
            vec3 col = mix(b2.rgb, tint, 0.85);
            col += tint * (n - 0.5) * 0.35;

            number a = b2.a * alpha * (0.75 + 0.25 * n);
            col = clamp(col, vec3(0.0), vec3(1.0));
            return vec4(col, a);
        }
    ]])
    if ok then dashTrailShader = sh else dashTrailShader = false end
    return dashTrailShader or nil
end

local hitFlashShader
function shaders.getHitFlashShader()
    if hitFlashShader ~= nil then return hitFlashShader or nil end
    if not love or not love.graphics or not love.graphics.newShader then
        hitFlashShader = false
        return nil
    end
    local ok, sh = pcall(love.graphics.newShader, [[
        extern number flashAmount;
        
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
        {
            vec4 base = Texel(tex, uv) * color;
            if (base.a <= 0.001) {
                return vec4(0.0);
            }
            
            vec3 flashColor = mix(base.rgb, vec3(1.0), flashAmount);
            return vec4(flashColor, base.a);
        }
    ]])
    if ok then hitFlashShader = sh else hitFlashShader = false end
    return hitFlashShader or nil
end

return shaders
