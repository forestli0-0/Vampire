local logger = require('logger')
local mods = require('mods')

return {
    mod = function(state, opt, dispatch)
        local category = opt.category or 'warframe'
        local rank = opt.rank or 0
        mods.addToRunInventory(state, opt.key, category, rank, opt.rarity)
        logger.upgrade(state, opt, rank)
        if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = rank}) end
    end
}
