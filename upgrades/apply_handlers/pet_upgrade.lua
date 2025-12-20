local logger = require('logger')
local pets = require('pets')

return {
    pet_upgrade = function(state, opt, dispatch)
        state.pets = state.pets or {}
        state.pets.upgrades = state.pets.upgrades or {}
        local cur = state.pets.upgrades[opt.key] or 0
        cur = cur + 1
        local max = opt.def and opt.def.maxLevel
        if max and cur > max then cur = max end
        state.pets.upgrades[opt.key] = cur
        logger.upgrade(state, opt, cur)
        if pets and pets.recompute then pets.recompute(state) end
        if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur}) end
    end
}
