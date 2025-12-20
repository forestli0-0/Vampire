local catalog = {}

local function merge(source)
    for k, v in pairs(source or {}) do
        catalog[k] = v
    end
end

-- DEPRECATED PASSIVES (VS-style, hidden from upgrade pools)
-- These effects are now handled by the WF MOD system
-- Kept for backward save compatibility only
-- ===================================================================
-- DEPRECATED PASSIVES REMOVED
-- These effects are now handled by the WF MOD system
-- ===================================================================

merge(require('data.defs.catalog.augments.mechanics'))
merge(require('data.defs.catalog.augments.projectiles'))
merge(require('data.defs.catalog.augments.mobility'))

return catalog
