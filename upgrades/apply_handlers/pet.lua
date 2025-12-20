local logger = require('logger')
local pets = require('pets')

return {
    pet = function(state, opt, dispatch)
        local pet = pets.setActive(state, opt.key, {swap = true})
        if pet then
            logger.upgrade(state, opt, 1)
            if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1}) end
        end
    end
}
