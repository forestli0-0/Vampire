local world = {}

local World = {}
World.__index = World

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function cellFromCoord(coord, tileSize)
    return math.floor(coord / tileSize) + 1
end

function World:cellIndex(cx, cy)
    return (cy - 1) * self.w + cx
end

function World:isWallCell(cx, cy)
    if cx < 1 or cy < 1 or cx > self.w or cy > self.h then return true end
    return self.tiles[self:cellIndex(cx, cy)] == 1
end

function World:isWalkableCell(cx, cy)
    return not self:isWallCell(cx, cy)
end

function World:worldToCell(x, y)
    local ts = self.tileSize
    return cellFromCoord(x, ts), cellFromCoord(y, ts)
end

function World:cellToWorld(cx, cy)
    local ts = self.tileSize
    return (cx - 0.5) * ts, (cy - 0.5) * ts
end

function World:clampToBounds(x, y, r)
    local maxX = self.pixelW - r
    local maxY = self.pixelH - r
    return clamp(x, r, maxX), clamp(y, r, maxY)
end

function World:segmentHitsWall(x0, y0, x1, y1)
    local ts = self.tileSize
    if not ts or ts <= 0 then return false end

    local dx = (x1 or 0) - (x0 or 0)
    local dy = (y1 or 0) - (y0 or 0)

    local cx, cy = self:worldToCell(x0 or 0, y0 or 0)
    local endCx, endCy = self:worldToCell(x1 or 0, y1 or 0)

    local stepX = (dx > 0) and 1 or ((dx < 0) and -1 or 0)
    local stepY = (dy > 0) and 1 or ((dy < 0) and -1 or 0)

    local tMaxX, tMaxY = math.huge, math.huge
    local tDeltaX, tDeltaY = math.huge, math.huge

    if stepX ~= 0 then
        local nextBoundaryX = (stepX > 0) and (cx * ts) or ((cx - 1) * ts)
        tMaxX = (nextBoundaryX - (x0 or 0)) / dx
        tDeltaX = ts / math.abs(dx)
    end
    if stepY ~= 0 then
        local nextBoundaryY = (stepY > 0) and (cy * ts) or ((cy - 1) * ts)
        tMaxY = (nextBoundaryY - (y0 or 0)) / dy
        tDeltaY = ts / math.abs(dy)
    end

    local guard = 0
    while true do
        if self:isWallCell(cx, cy) then return true end
        if cx == endCx and cy == endCy then return false end

        guard = guard + 1
        if guard > 4096 then return true end

        if tMaxX < tMaxY then
            cx = cx + stepX
            tMaxX = tMaxX + tDeltaX
        else
            cy = cy + stepY
            tMaxY = tMaxY + tDeltaY
        end
    end
end

function World:hasLineOfSight(x0, y0, x1, y1)
    return not self:segmentHitsWall(x0, y0, x1, y1)
end

local function carveRect(self, x1, y1, x2, y2)
    x1 = math.max(2, math.min(self.w - 1, x1))
    y1 = math.max(2, math.min(self.h - 1, y1))
    x2 = math.max(2, math.min(self.w - 1, x2))
    y2 = math.max(2, math.min(self.h - 1, y2))
    if x2 < x1 or y2 < y1 then return end
    for cy = y1, y2 do
        local row = (cy - 1) * self.w
        for cx = x1, x2 do
            self.tiles[row + cx] = 0
        end
    end
end

local function fillRect(self, x1, y1, x2, y2, value)
    value = value or 1
    x1 = math.max(2, math.min(self.w - 1, x1))
    y1 = math.max(2, math.min(self.h - 1, y1))
    x2 = math.max(2, math.min(self.w - 1, x2))
    y2 = math.max(2, math.min(self.h - 1, y2))
    if x2 < x1 or y2 < y1 then return end
    for cy = y1, y2 do
        local row = (cy - 1) * self.w
        for cx = x1, x2 do
            self.tiles[row + cx] = value
        end
    end
end

local function applyRoomArchetype(self, room)
    local w = (room.x2 or 0) - (room.x1 or 0) + 1
    local h = (room.y2 or 0) - (room.y1 or 0) + 1
    if w < 9 or h < 9 then return end

    local choice = math.random()
    if choice < 0.55 then
        -- four corner pillars (reusable landmark, leaves center clear)
        fillRect(self, room.x1 + 2, room.y1 + 2, room.x1 + 3, room.y1 + 3, 1)
        fillRect(self, room.x2 - 3, room.y1 + 2, room.x2 - 2, room.y1 + 3, 1)
        fillRect(self, room.x1 + 2, room.y2 - 3, room.x1 + 3, room.y2 - 2, 1)
        fillRect(self, room.x2 - 3, room.y2 - 3, room.x2 - 2, room.y2 - 2, 1)
    elseif choice < 0.80 then
        -- sparse inner pillars (grid-ish) for larger rooms
        local step = 4
        for cy = room.y1 + 3, room.y2 - 3, step do
            for cx = room.x1 + 3, room.x2 - 3, step do
                local dx = cx - (room.cx or cx)
                local dy = cy - (room.cy or cy)
                if dx * dx + dy * dy > 9 then
                    fillRect(self, cx, cy, cx, cy, 1)
                end
            end
        end
    else
        -- center lane divider with a gap (recognizable but navigable)
        local midX = room.cx or math.floor((room.x1 + room.x2) * 0.5)
        local gapY = room.cy or math.floor((room.y1 + room.y2) * 0.5)
        for cy = room.y1 + 2, room.y2 - 2 do
            if math.abs(cy - gapY) <= 1 then
                -- gap
            else
                fillRect(self, midX, cy, midX, cy, 1)
            end
        end
    end
end

local function rectsOverlap(a, b, margin)
    margin = margin or 0
    return not (a.x2 + margin < b.x1 - margin
        or a.x1 - margin > b.x2 + margin
        or a.y2 + margin < b.y1 - margin
        or a.y1 - margin > b.y2 + margin)
end

local function corridorOffsets(width)
    width = math.max(1, math.floor(width or 1))
    local offsets = {}
    if width == 1 then
        offsets[1] = 0
        return offsets
    end
    if width % 2 == 1 then
        local half = (width - 1) / 2
        for i = -half, half do
            offsets[#offsets + 1] = i
        end
        return offsets
    end
    local half = width / 2
    local start, stop
    if math.random() < 0.5 then
        start, stop = -half, half - 1
    else
        start, stop = -half + 1, half
    end
    for i = start, stop do
        offsets[#offsets + 1] = i
    end
    return offsets
end

local function carveCorridor(self, x1, y1, x2, y2, width)
    local offsets = corridorOffsets(width)
    if math.random() < 0.5 then
        local dir = (x2 >= x1) and 1 or -1
        for x = x1, x2, dir do
            for _, oy in ipairs(offsets) do
                carveRect(self, x, y1 + oy, x, y1 + oy)
            end
        end
        dir = (y2 >= y1) and 1 or -1
        for y = y1, y2, dir do
            for _, ox in ipairs(offsets) do
                carveRect(self, x2 + ox, y, x2 + ox, y)
            end
        end
    else
        local dir = (y2 >= y1) and 1 or -1
        for y = y1, y2, dir do
            for _, ox in ipairs(offsets) do
                carveRect(self, x1 + ox, y, x1 + ox, y)
            end
        end
        dir = (x2 >= x1) and 1 or -1
        for x = x1, x2, dir do
            for _, oy in ipairs(offsets) do
                carveRect(self, x, y2 + oy, x, y2 + oy)
            end
        end
    end
end

function World:generate(opts)
    opts = opts or {}
    self.tileSize = math.max(8, math.floor(opts.tileSize or 32))
    self.w = math.max(48, math.floor(opts.w or 160))
    self.h = math.max(48, math.floor(opts.h or 160))
    self.pixelW = self.w * self.tileSize
    self.pixelH = self.h * self.tileSize

    self.tiles = {}
    for i = 1, self.w * self.h do
        self.tiles[i] = 1
    end

    local targetRooms = math.max(6, math.floor(opts.roomCount or 28))
    local minSize = math.max(4, math.floor(opts.roomMin or 6))
    local maxSize = math.max(minSize, math.floor(opts.roomMax or 14))
    local margin = math.max(0, math.floor(opts.roomMargin or 2))
    local corridorW = math.max(1, math.floor(opts.corridorWidth or 2))

    self.rooms = {}
    local attempts = targetRooms * 18
    for _ = 1, attempts do
        if #self.rooms >= targetRooms then break end

        local rw = math.random(minSize, maxSize)
        local rh = math.random(minSize, maxSize)
        local rx = math.random(2, math.max(2, self.w - rw - 1))
        local ry = math.random(2, math.max(2, self.h - rh - 1))

        local room = {
            x1 = rx,
            y1 = ry,
            x2 = rx + rw - 1,
            y2 = ry + rh - 1
        }
        room.cx = math.floor((room.x1 + room.x2) * 0.5)
        room.cy = math.floor((room.y1 + room.y2) * 0.5)

        local ok = true
        for _, other in ipairs(self.rooms) do
            if rectsOverlap(room, other, margin) then
                ok = false
                break
            end
        end
        if ok then
            carveRect(self, room.x1, room.y1, room.x2, room.y2)
            applyRoomArchetype(self, room)
            self.rooms[#self.rooms + 1] = room
        end
    end

    if #self.rooms < 1 then
        local cx = math.floor(self.w / 2)
        local cy = math.floor(self.h / 2)
        carveRect(self, cx - 6, cy - 6, cx + 6, cy + 6)
        self.rooms[1] = {x1 = cx - 6, y1 = cy - 6, x2 = cx + 6, y2 = cy + 6, cx = cx, cy = cy}
    end

    table.sort(self.rooms, function(a, b) return a.cx < b.cx end)
    for i = 2, #self.rooms do
        local a = self.rooms[i - 1]
        local b = self.rooms[i]
        carveCorridor(self, a.cx, a.cy, b.cx, b.cy, corridorW)
    end

    local extraLinks = math.floor(#self.rooms * 0.25)
    for _ = 1, extraLinks do
        if #self.rooms < 3 then break end
        local a = self.rooms[math.random(#self.rooms)]
        local b = self.rooms[math.random(#self.rooms)]
        if a ~= b then
            carveCorridor(self, a.cx, a.cy, b.cx, b.cy, corridorW)
        end
    end

    local spawnRoom = self.rooms[1]
    self.spawnCx, self.spawnCy = spawnRoom.cx, spawnRoom.cy
    self.spawnX, self.spawnY = self:cellToWorld(self.spawnCx, self.spawnCy)

    self.nav = {
        dist = {},
        refresh = tonumber(opts.navRefresh) or 0.35,
        timer = 0,
        playerCx = nil,
        playerCy = nil,
        ready = false
    }
    for i = 1, self.w * self.h do
        self.nav.dist[i] = -1
    end
    self._navQueue = {}
end

local function buildDistanceField(self, startCx, startCy)
    local nav = self.nav
    if not nav then return end
    local w, h = self.w, self.h
    local dist = nav.dist

    for i = 1, w * h do
        dist[i] = -1
    end

    if self:isWallCell(startCx, startCy) then
        nav.ready = false
        return
    end

    local q = self._navQueue
    local head, tail = 1, 1
    local startIdx = self:cellIndex(startCx, startCy)
    q[1] = startIdx
    dist[startIdx] = 0

    while head <= tail do
        local idx = q[head]
        head = head + 1
        local base = dist[idx]

        local cx = ((idx - 1) % w) + 1
        local cy = math.floor((idx - 1) / w) + 1

        if cx > 1 then
            local n = idx - 1
            if dist[n] == -1 and self.tiles[n] == 0 then
                dist[n] = base + 1
                tail = tail + 1
                q[tail] = n
            end
        end
        if cx < w then
            local n = idx + 1
            if dist[n] == -1 and self.tiles[n] == 0 then
                dist[n] = base + 1
                tail = tail + 1
                q[tail] = n
            end
        end
        if cy > 1 then
            local n = idx - w
            if dist[n] == -1 and self.tiles[n] == 0 then
                dist[n] = base + 1
                tail = tail + 1
                q[tail] = n
            end
        end
        if cy < h then
            local n = idx + w
            if dist[n] == -1 and self.tiles[n] == 0 then
                dist[n] = base + 1
                tail = tail + 1
                q[tail] = n
            end
        end
    end

    nav.ready = true
end

function World:updateNav(playerX, playerY, dt)
    local nav = self.nav
    if not nav then return end
    nav.timer = (nav.timer or 0) - (dt or 0)

    local pcx, pcy = self:worldToCell(playerX or 0, playerY or 0)
    if nav.playerCx ~= pcx or nav.playerCy ~= pcy then
        nav.timer = 0
    end

    if nav.timer > 0 then return end
    nav.timer = nav.refresh
    nav.playerCx, nav.playerCy = pcx, pcy

    buildDistanceField(self, pcx, pcy)
end

function World:getFlowDir(x, y)
    local nav = self.nav
    if not nav or not nav.ready then return nil end

    local cx, cy = self:worldToCell(x or 0, y or 0)
    if cx < 1 or cy < 1 or cx > self.w or cy > self.h then return nil end
    local idx = self:cellIndex(cx, cy)
    local d = nav.dist[idx]
    if not d or d < 0 then return nil end
    if d == 0 then return 0, 0 end

    local bestD = d
    local bestIdx = nil
    local w = self.w

    if cx > 1 then
        local n = idx - 1
        local nd = nav.dist[n]
        if nd and nd >= 0 and nd < bestD then bestD, bestIdx = nd, n end
    end
    if cx < w then
        local n = idx + 1
        local nd = nav.dist[n]
        if nd and nd >= 0 and nd < bestD then bestD, bestIdx = nd, n end
    end
    if cy > 1 then
        local n = idx - w
        local nd = nav.dist[n]
        if nd and nd >= 0 and nd < bestD then bestD, bestIdx = nd, n end
    end
    if cy < self.h then
        local n = idx + w
        local nd = nav.dist[n]
        if nd and nd >= 0 and nd < bestD then bestD, bestIdx = nd, n end
    end

    if not bestIdx then return nil end
    local ncx = ((bestIdx - 1) % w) + 1
    local ncy = math.floor((bestIdx - 1) / w) + 1
    local wx, wy = self:cellToWorld(ncx, ncy)
    local dx = wx - x
    local dy = wy - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return nil end
    return dx / len, dy / len
end

function World:findNearestWalkable(cx, cy, maxR)
    maxR = maxR or 10
    if self:isWalkableCell(cx, cy) then return cx, cy end
    for r = 1, maxR do
        for dy = -r, r do
            local y = cy + dy
            local x1 = cx - r
            local x2 = cx + r
            if self:isWalkableCell(x1, y) then return x1, y end
            if self:isWalkableCell(x2, y) then return x2, y end
        end
        for dx = -(r - 1), (r - 1) do
            local x = cx + dx
            local y1 = cy - r
            local y2 = cy + r
            if self:isWalkableCell(x, y1) then return x, y1 end
            if self:isWalkableCell(x, y2) then return x, y2 end
        end
    end
    return nil
end

function World:adjustToWalkable(x, y, maxR)
    local cx, cy = self:worldToCell(x or 0, y or 0)
    if self:isWalkableCell(cx, cy) then return x, y end
    local fx, fy = self:findNearestWalkable(cx, cy, maxR or 12)
    if not fx then
        return self.spawnX, self.spawnY
    end
    return self:cellToWorld(fx, fy)
end

function World:sampleSpawn(px, py, minCells, maxCells, attempts)
    local pcx, pcy = self:worldToCell(px or 0, py or 0)
    minCells = math.max(2, math.floor(minCells or 10))
    maxCells = math.max(minCells, math.floor(maxCells or 18))
    attempts = math.max(8, math.floor(attempts or 36))

    for _ = 1, attempts do
        local ang = math.random() * math.pi * 2
        local r = math.random(minCells, maxCells)
        local cx = pcx + math.floor(math.cos(ang) * r)
        local cy = pcy + math.floor(math.sin(ang) * r)
        if self:isWalkableCell(cx, cy) then
            return self:cellToWorld(cx, cy)
        end
    end

    local fx, fy = self:findNearestWalkable(pcx, pcy, maxCells + 6)
    if fx then return self:cellToWorld(fx, fy) end
    return self.spawnX, self.spawnY
end

function World:sampleSpawnInCells(minCx, minCy, maxCx, maxCy, attempts)
    attempts = math.max(8, math.floor(attempts or 48))
    minCx = math.max(2, math.min(self.w - 1, math.floor(minCx or 2)))
    maxCx = math.max(2, math.min(self.w - 1, math.floor(maxCx or (self.w - 1))))
    minCy = math.max(2, math.min(self.h - 1, math.floor(minCy or 2)))
    maxCy = math.max(2, math.min(self.h - 1, math.floor(maxCy or (self.h - 1))))
    if maxCx < minCx then minCx, maxCx = maxCx, minCx end
    if maxCy < minCy then minCy, maxCy = maxCy, minCy end

    for _ = 1, attempts do
        local cx = math.random(minCx, maxCx)
        local cy = math.random(minCy, maxCy)
        if self:isWalkableCell(cx, cy) then
            return self:cellToWorld(cx, cy)
        end
    end

    local ccx = math.floor((minCx + maxCx) * 0.5)
    local ccy = math.floor((minCy + maxCy) * 0.5)
    local maxR = math.max(8, math.max(maxCx - minCx, maxCy - minCy))
    local fx, fy = self:findNearestWalkable(ccx, ccy, maxR)
    if fx then return self:cellToWorld(fx, fy) end
    return self.spawnX, self.spawnY
end

local function resolveAxisX(self, x, y, r, dx)
    if not dx or dx == 0 then return x, false end
    local ts = self.tileSize
    local target = x + dx
    target = clamp(target, r, self.pixelW - r)
    local hit = false
    local rr = r * r

    for _ = 1, 4 do
        local adjusted = false
        local minCx = math.max(1, cellFromCoord(target - r, ts))
        local maxCx = math.min(self.w, cellFromCoord(target + r, ts))
        local minCy = math.max(1, cellFromCoord(y - r, ts))
        local maxCy = math.min(self.h, cellFromCoord(y + r, ts))

        for cy = minCy, maxCy do
            local row = (cy - 1) * self.w
            local top = (cy - 1) * ts
            local bottom = top + ts
            for cx = minCx, maxCx do
                if self.tiles[row + cx] == 1 then
                    local left = (cx - 1) * ts
                    local right = left + ts
                    local nearestX = clamp(target, left, right)
                    local nearestY = clamp(y, top, bottom)
                    local ddx = target - nearestX
                    local ddy = y - nearestY
                    if ddx * ddx + ddy * ddy < rr then
                        local dy = 0
                        if y < top then dy = top - y elseif y > bottom then dy = y - bottom end
                        local root = rr - dy * dy
                        local off = (root > 0) and math.sqrt(root) or 0
                        if dx > 0 then
                            local allowed = left - off
                            if allowed < target then
                                target = allowed
                                adjusted = true
                                hit = true
                            end
                        else
                            local allowed = right + off
                            if allowed > target then
                                target = allowed
                                adjusted = true
                                hit = true
                            end
                        end
                    end
                end
            end
        end

        target = clamp(target, r, self.pixelW - r)
        if not adjusted then break end
    end

    return target, hit
end

local function resolveAxisY(self, x, y, r, dy)
    if not dy or dy == 0 then return y, false end
    local ts = self.tileSize
    local target = y + dy
    target = clamp(target, r, self.pixelH - r)
    local hit = false
    local rr = r * r

    for _ = 1, 4 do
        local adjusted = false
        local minCx = math.max(1, cellFromCoord(x - r, ts))
        local maxCx = math.min(self.w, cellFromCoord(x + r, ts))
        local minCy = math.max(1, cellFromCoord(target - r, ts))
        local maxCy = math.min(self.h, cellFromCoord(target + r, ts))

        for cy = minCy, maxCy do
            local row = (cy - 1) * self.w
            local top = (cy - 1) * ts
            local bottom = top + ts
            for cx = minCx, maxCx do
                if self.tiles[row + cx] == 1 then
                    local left = (cx - 1) * ts
                    local right = left + ts
                    local nearestX = clamp(x, left, right)
                    local nearestY = clamp(target, top, bottom)
                    local ddx = x - nearestX
                    local ddy = target - nearestY
                    if ddx * ddx + ddy * ddy < rr then
                        local dx = 0
                        if x < left then dx = left - x elseif x > right then dx = x - right end
                        local root = rr - dx * dx
                        local off = (root > 0) and math.sqrt(root) or 0
                        if dy > 0 then
                            local allowed = top - off
                            if allowed < target then
                                target = allowed
                                adjusted = true
                                hit = true
                            end
                        else
                            local allowed = bottom + off
                            if allowed > target then
                                target = allowed
                                adjusted = true
                                hit = true
                            end
                        end
                    end
                end
            end
        end

        target = clamp(target, r, self.pixelH - r)
        if not adjusted then break end
    end

    return target, hit
end

function World:moveCircle(x, y, r, dx, dy)
    r = math.max(1, tonumber(r) or 1)
    x, y = self:clampToBounds(x or 0, y or 0, r)

    local newX, hitX = resolveAxisX(self, x, y, r, dx or 0)
    local newY, hitY = resolveAxisY(self, newX, y, r, dy or 0)
    return newX, newY, hitX, hitY
end

function world.new(opts)
    local self = setmetatable({}, World)
    self.enabled = true
    self:generate(opts)
    return self
end

function world.update(state, dt)
    local w = state and state.world
    if not (w and w.enabled) then return end
    local p = state.player or {}
    w:updateNav(p.x or 0, p.y or 0, dt or 0)
end

return world
