local util = {}

local function effectiveSize(o)
    if not o then return 0 end
    if o.hitSize ~= nil then return o.hitSize end
    local s = o.size or 0
    local m = o.hitSizeScale or 1
    return s * m
end

function util.checkCollision(a, b)
    local ax = (a and a.x) or 0
    local ay = (a and a.y) or 0
    local bx = (b and b.x) or 0
    local by = (b and b.y) or 0
    local aSize = effectiveSize(a)
    local bSize = effectiveSize(b)
    return (ax - bx) ^ 2 + (ay - by) ^ 2 < (aSize / 2 + bSize / 2) ^ 2
end

return util
