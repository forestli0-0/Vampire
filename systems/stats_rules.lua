local statsRules = {}

-- Centralized stacking rules for numeric stats.
-- This keeps future stats (pierce/chain/bounce/etc.) from accidentally using the wrong stacking behavior.
--
-- For `mul`, the incoming modifier is interpreted as a percentage-per-rank:
--   new = base * max(minFactor, 1 + mod * level)
-- For `add`, the incoming modifier is interpreted as flat-per-rank:
--   new = base + mod * level

statsRules.rules = {
    -- additive "flat" style stats
    amount = {op = 'add', min = 0},
    pierce = {op = 'add', min = 0},
    chain = {op = 'add', default = 0, min = 0},
    bounce = {op = 'add', default = 0, min = 0},

    critChance = {op = 'add', min = 0},
    statusChance = {op = 'add', min = 0},
    critMultiplier = {op = 'add', min = 0},

    -- multiplicative percent style stats (default)
    damage = {op = 'mul', minFactor = 0.1},
    cd = {op = 'mul', minFactor = 0.1},
    speed = {op = 'mul', minFactor = 0.1},
    area = {op = 'mul', minFactor = 0.1},
    radius = {op = 'mul', minFactor = 0.1},
    size = {op = 'mul', minFactor = 0.1},
    splashRadius = {op = 'mul', minFactor = 0.1},
    duration = {op = 'mul', minFactor = 0.1},
    life = {op = 'mul', minFactor = 0.1},
    knockback = {op = 'mul', minFactor = 0.1}
}

local function clamp(x, minV, maxV)
    if minV ~= nil and x < minV then x = minV end
    if maxV ~= nil and x > maxV then x = maxV end
    return x
end

function statsRules.applyEffect(stats, effect, level)
    if not stats or not effect or not level or level <= 0 then return end
    for statKey, mod in pairs(effect) do
        local rule = statsRules.rules[statKey]
        local base = stats[statKey]
        if base == nil and rule and rule.default ~= nil then
            base = rule.default
        end
        if type(base) == 'number' and type(mod) == 'number' then
            if not rule then rule = {op = 'mul', minFactor = 0.1} end

            local out = base
            if rule.op == 'add' then
                out = base + mod * level
            else
                local factor = 1 + mod * level
                local minFactor = rule.minFactor or 0.1
                if factor < minFactor then factor = minFactor end
                out = base * factor
            end
            out = clamp(out, rule.min, rule.max)
            stats[statKey] = out
        end
    end
end

return statsRules
