local catalog = {}

local function merge(source)
    for k, v in pairs(source or {}) do
        catalog[k] = v
    end
end

merge(require('data.defs.catalog.pets'))
merge(require('data.defs.catalog.weapons'))
merge(require('data.defs.catalog.augments'))

return catalog
