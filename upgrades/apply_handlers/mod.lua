local logger = require('logger')

return {
    mod = function(state, opt, dispatch)
        -- Mods are loadout-only and apply per-weapon when equipped.
        -- If enabled as an in-run reward (debug), treat this as ranking up the mod and refresh weapon loadouts.
        state.profile = state.profile or {}
        state.profile.modRanks = state.profile.modRanks or {}
        state.profile.ownedMods = state.profile.ownedMods or {}
        state.profile.ownedMods[opt.key] = true

        local cur = state.profile.modRanks[opt.key]
        if cur == nil then cur = 1 end
        cur = cur + 1
        local max = opt.def and opt.def.maxLevel
        if max and cur > max then cur = max end
        state.profile.modRanks[opt.key] = cur
        if state.applyPersistentMods then state.applyPersistentMods() end

        logger.upgrade(state, opt, cur)
        if opt.def.onUpgrade then opt.def.onUpgrade() end
        if dispatch then dispatch(state, 'onUpgradeChosen', {opt = opt, player = state.player, level = cur}) end
    end
}
