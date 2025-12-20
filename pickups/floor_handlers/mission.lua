local logger = require('logger')

local function handleLifeSupport(state, p, item)
    -- Survival mission life support capsule
    local r = state.rooms
    if r and r.lifeSupport then
        local restore = 20
        r.lifeSupport = math.min(100, r.lifeSupport + restore)
        table.insert(state.texts, {x=p.x, y=p.y-30, text="+"..restore.."%生命支援", color={0.4, 0.8, 1}, life=1})
        if state.playSfx then state.playSfx('gem') end
        logger.pickup(state, 'life_support')
        return true
    end
    return false
end

return {
    life_support = handleLifeSupport
}
