local logger = require('core.logger')

return {
    augment = function(state, opt, dispatch)
        state.inventory.augments = state.inventory.augments or {}
        state.inventory.augmentOrder = state.inventory.augmentOrder or {}
        if not state.inventory.augments[opt.key] then
            state.inventory.augments[opt.key] = 0
            table.insert(state.inventory.augmentOrder, opt.key)
        end
        state.inventory.augments[opt.key] = state.inventory.augments[opt.key] + 1
        logger.upgrade(state, opt, state.inventory.augments[opt.key])
        if opt.def.onUpgrade then opt.def.onUpgrade() end
        if dispatch then
            dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = state.inventory.augments[opt.key]})
        end
    end
}
