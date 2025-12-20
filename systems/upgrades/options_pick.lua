local helpers = require('systems.upgrades.options_helpers')

local function fillOptions(state, pools, preferExistingChance)
    for i = #state.upgradeOptions + 1, 3 do
        local choice = nil
        -- 现有/新选项混合：偏向现有，但保留一定随机新路线
        -- Use weighted selection for class-based preferences
        local preferExisting = (#pools.poolExisting > 0) and (math.random() < preferExistingChance or #pools.poolNew == 0)
        if preferExisting then
            choice = helpers.takeWeighted(state, pools.poolExisting)
        else
            choice = helpers.takeWeighted(state, pools.poolNew)
        end
        if not choice then choice = helpers.takeWeighted(state, pools.poolExisting) end
        if not choice then choice = helpers.takeWeighted(state, pools.poolNew) end
        if not choice then break end
        table.insert(state.upgradeOptions, choice)
    end
end

return {
    fillOptions = fillOptions
}
