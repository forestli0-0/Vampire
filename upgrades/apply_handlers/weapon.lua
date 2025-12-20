local weapons = require('weapons')
local logger = require('logger')

return {
    weapon = function(state, opt, dispatch)
        if not state.inventory.weapons[opt.key] then
            weapons.addWeapon(state, opt.key, opt.assignOwner)
            logger.upgrade(state, opt, 1)
            if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1}) end
        else
            local w = state.inventory.weapons[opt.key]
            w.level = w.level + 1
            if opt.def.onUpgrade then opt.def.onUpgrade(w.stats) end
            logger.upgrade(state, opt, w.level)
            if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = w.level}) end
        end
    end
}
