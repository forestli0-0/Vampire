local pool = require('systems.upgrades.options_pool')
local pick = require('systems.upgrades.options_pick')
local rules = require('systems.upgrades.options_rules')

local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

return function(upgrades)
    function upgrades.generateUpgradeOptions(state, request, allowFallback)
        if allowFallback == nil then allowFallback = true end
        local pools = pool.buildPools(state, request)

        state.upgradeOptions = {}
        -- Removed Evolution Pool Logic due to WF system migration
        rules.applyStartingGuarantee(state, pools)
        local runLevel, preferExistingChance, maxWeapons, weaponsOwned = rules.computeRunState(state, upgrades)
        rules.applyEarlyRoute(state, pools, runLevel, maxWeapons, weaponsOwned)
        pick.fillOptions(state, pools, preferExistingChance)
        rules.applyLowLevelForce(state, pools, runLevel)

        if #state.upgradeOptions == 0 and allowFallback and type(pools.allowedTypes) == 'table' and next(pools.allowedTypes) ~= nil then
            return upgrades.generateUpgradeOptions(state, nil, false)
        end

        local ctx = {options = state.upgradeOptions, player = state.player, request = request}
        dispatch(state, 'onUpgradeOptions', ctx)
        if ctx.options and ctx.options ~= state.upgradeOptions then
            state.upgradeOptions = ctx.options
        end
    end
end
