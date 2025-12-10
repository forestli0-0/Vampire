local util = {}

function util.checkCollision(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < ((a.size or 0) / 2 + (b.size or 0) / 2) ^ 2
end

return util
