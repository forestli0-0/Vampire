local logger = require('core.logger')
local mods = require('systems.mods')

return {
    mod = function(state, opt, dispatch)
        local category = opt.category or 'warframe'
        local rank = opt.rank or 0
        mods.addToRunInventory(state, opt.key, category, rank, opt.rarity)
        
        -- Smart install for companion mods
        if category == 'companion' then
            local slots = mods.getRunSlots(state, 'companion', nil)
            local firstEmpty = nil
            for i = 1, 8 do
                if not slots[i] then
                    firstEmpty = i
                    break
                end
            end
            if firstEmpty then
                mods.equipToRunSlot(state, 'companion', nil, firstEmpty, opt.key, rank)
            end
        end

        logger.upgrade(state, opt, rank)
        if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = rank}) end
    end
}
