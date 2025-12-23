local handlers = {}

local function merge(source)
    for k, v in pairs(source or {}) do
        handlers[k] = v
    end
end

merge(require('systems.upgrades.apply_handlers.weapon'))
merge(require('systems.upgrades.apply_handlers.mod'))
merge(require('systems.upgrades.apply_handlers.augment'))
-- Legacy pet handlers removed (unified to MOD system)
merge(require('systems.upgrades.apply_handlers.pet'))
merge(require('systems.upgrades.apply_handlers.passive'))

local function dispatch(state, eventName, ctx)
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, eventName, ctx or {})
    end
end

return function(upgrades)
    function upgrades.applyUpgrade(state, opt)
        -- Track upgrade count for starting guarantee system
        state.upgradeCount = (state.upgradeCount or 0) + 1

        if opt.evolveFrom then
            -- This should be unreachable now, but kept safe
            return
        end

        local handler = opt and opt.type and handlers[opt.type] or nil
        if handler then
            handler(state, opt, dispatch)
        end
    end
end
