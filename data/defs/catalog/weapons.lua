local catalog = {}

local function merge(source)
    for k, v in pairs(source or {}) do
        catalog[k] = v
    end
end

merge(require('data.defs.catalog.weapons.active'))
merge(require('data.defs.catalog.weapons.active'))

return catalog
