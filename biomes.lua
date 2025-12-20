local biomes = {}

local function addWeighted(pool, key, weight)
    weight = math.floor(tonumber(weight) or 0)
    if weight <= 0 then return end
    for _ = 1, weight do
        pool[#pool + 1] = key
    end
end

local function buildPoolFromWeights(weights)
    local pool = {}
    if type(weights) == 'table' then
        for key, w in pairs(weights) do
            addWeighted(pool, key, w)
        end
    end
    if #pool == 0 then pool[1] = 'skeleton' end
    return pool
end

local defs = require('data.defs.biomes')

function biomes.get(index)
    local i = tonumber(index) or 1
    i = math.floor(i)
    if i < 1 then i = 1 end
    if i > #defs then i = #defs end
    return defs[i]
end

function biomes.buildEnemyPool(biomeDef, tier)
    local def = biomeDef or defs[1]
    local t = tonumber(tier) or 1
    t = math.floor(t)
    if t < 1 then t = 1 end
    local weights = def.enemyTiers and def.enemyTiers[t]
    if weights == nil then
        weights = def.enemyTiers and def.enemyTiers[#(def.enemyTiers or {})]
    end
    return buildPoolFromWeights(weights)
end

return biomes
