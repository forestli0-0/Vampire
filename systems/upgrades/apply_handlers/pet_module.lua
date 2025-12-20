local logger = require('core.logger')
local pets = require('gameplay.pets')

return {
    pet_module = function(state, opt, dispatch)
        local pet = pets.getActive(state)
        local def = opt.def or (state.catalog and state.catalog[opt.key]) or nil
        local modId = def and def.moduleId
        if pet and modId and (pet.module or 'default') == 'default' then
            pet.module = modId
            logger.upgrade(state, opt, 1)
            if state.texts then
                table.insert(state.texts, {x = pet.x, y = pet.y - 60, text = "PET MODULE: " .. tostring(def.name or opt.key), color = {0.85, 0.95, 1.0}, life = 1.3})
            end
            if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = 1}) end
        end
    end
}
