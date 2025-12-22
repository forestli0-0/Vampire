-- Chapter-based Linear Dungeon Generator
-- Generates dungeons with a clear progression path: Start → Rooms → Boss → Exit

local chapter = {}

local World = require('world.world')

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    tileSize = 32,
    
    -- Map dimensions (in tiles)
    mapWidth = 200,
    mapHeight = 80,
    
    -- Room sizes
    corridorWidth = 3,
    smallRoom = {min = 8, max = 12},
    mediumRoom = {min = 12, max = 16},
    largeRoom = {min = 16, max = 22},
    bossRoom = {min = 24, max = 28},
    
    -- Progression
    nodesPerChapter = 8,  -- How many main nodes before boss
    branchChance = 0.3,   -- Chance for optional side room
    
    -- Special rooms
    merchantEvery = 4,    -- Merchant appears every N nodes
    forgeChance = 0.25,   -- Chance for forge at eligible spots
}

--------------------------------------------------------------------------------
-- NODE TYPES
--------------------------------------------------------------------------------

local NODE_TYPES = {
    START = 'start',
    CORRIDOR = 'corridor',
    SMALL_COMBAT = 'small_combat',
    LARGE_COMBAT = 'large_combat',
    MERCHANT = 'merchant',
    FORGE = 'forge',
    SHRINE = 'shrine',
    BOSS = 'boss',
    EXIT = 'exit',
}

--------------------------------------------------------------------------------
-- CHAPTER GENERATOR
--------------------------------------------------------------------------------

local ChapterMap = {}
ChapterMap.__index = ChapterMap

function chapter.new()
    local self = setmetatable({}, ChapterMap)
    self.nodes = {}
    self.tiles = {}
    self.w = CONFIG.mapWidth
    self.h = CONFIG.mapHeight
    self.tileSize = CONFIG.tileSize
    self.pixelW = self.w * self.tileSize
    self.pixelH = self.h * self.tileSize
    self.spawnX = 0
    self.spawnY = 0
    self.exitX = 0
    self.exitY = 0
    self.explored = {}  -- For minimap fog
    return self
end

--------------------------------------------------------------------------------
-- MAIN PATH GENERATION (Spine Algorithm)
--------------------------------------------------------------------------------

function ChapterMap:generateSpine()
    -- Create a wandering path from left to right with natural curves
    local nodes = {}
    local currentX = 10  -- Start near left edge
    local currentY = math.floor(self.h / 2)  -- Start at vertical center
    
    local nodeCount = CONFIG.nodesPerChapter
    local stepX = math.floor((self.w - 40) / nodeCount)  -- Horizontal spacing
    
    for i = 1, nodeCount do
        -- Determine node type
        local nodeType
        if i == 1 then
            nodeType = NODE_TYPES.START
        elseif i % CONFIG.merchantEvery == 0 then
            nodeType = NODE_TYPES.MERCHANT
        elseif math.random() < 0.35 then
            nodeType = NODE_TYPES.LARGE_COMBAT
        else
            nodeType = NODE_TYPES.SMALL_COMBAT
        end
        
        -- Add some vertical wandering (but not too much)
        local yOffset = math.random(-8, 8)
        currentY = math.max(15, math.min(self.h - 15, currentY + yOffset))
        
        -- Slight horizontal variation
        local xOffset = math.random(-3, 3)
        currentX = currentX + stepX + xOffset
        
        local node = {
            id = i,
            type = nodeType,
            cx = currentX,
            cy = currentY,
            cleared = false,
            enemies = {},
            connected = {},  -- Connected node IDs
        }
        
        -- Set room size based on type
        if nodeType == NODE_TYPES.LARGE_COMBAT then
            node.roomW = math.random(CONFIG.largeRoom.min, CONFIG.largeRoom.max)
            node.roomH = math.random(CONFIG.largeRoom.min, CONFIG.largeRoom.max)
            node.difficulty = 'hard'
            node.spawnElite = true
        elseif nodeType == NODE_TYPES.MERCHANT or nodeType == NODE_TYPES.FORGE then
            node.roomW = 10
            node.roomH = 10
            node.difficulty = 'safe'
        else
            node.roomW = math.random(CONFIG.smallRoom.min, CONFIG.smallRoom.max)
            node.roomH = math.random(CONFIG.smallRoom.min, CONFIG.smallRoom.max)
            node.difficulty = 'normal'
        end
        
        table.insert(nodes, node)
    end
    
    -- Add boss room
    currentX = currentX + stepX
    local bossNode = {
        id = #nodes + 1,
        type = NODE_TYPES.BOSS,
        cx = math.min(self.w - 20, currentX),
        cy = math.floor(self.h / 2),
        roomW = math.random(CONFIG.bossRoom.min, CONFIG.bossRoom.max),
        roomH = math.random(CONFIG.bossRoom.min, CONFIG.bossRoom.max),
        difficulty = 'boss',
        cleared = false,
        enemies = {},
        connected = {},
    }
    table.insert(nodes, bossNode)
    
    -- Add exit after boss
    local exitNode = {
        id = #nodes + 1,
        type = NODE_TYPES.EXIT,
        cx = bossNode.cx + 12,
        cy = bossNode.cy,
        roomW = 6,
        roomH = 6,
        difficulty = 'safe',
        cleared = true,
        enemies = {},
        connected = {},
    }
    table.insert(nodes, exitNode)
    
    -- Connect nodes sequentially
    for i = 1, #nodes - 1 do
        table.insert(nodes[i].connected, nodes[i + 1].id)
        table.insert(nodes[i + 1].connected, nodes[i].id)
    end
    
    self.nodes = nodes
end

--------------------------------------------------------------------------------
-- OPTIONAL BRANCH ROOMS
--------------------------------------------------------------------------------

function ChapterMap:generateBranches()
    -- Add optional side rooms branching off main path
    local newNodes = {}
    
    for i, node in ipairs(self.nodes) do
        if node.type == NODE_TYPES.SMALL_COMBAT or node.type == NODE_TYPES.LARGE_COMBAT then
            if math.random() < CONFIG.branchChance then
                -- Create branch room
                local branchDir = (math.random() < 0.5) and -1 or 1  -- Up or down
                local branchNode = {
                    id = 1000 + i,  -- Branch IDs start at 1000
                    type = (math.random() < 0.3) and NODE_TYPES.SHRINE or NODE_TYPES.SMALL_COMBAT,
                    cx = node.cx + math.random(-5, 5),
                    cy = node.cy + branchDir * math.random(12, 18),
                    roomW = math.random(8, 12),
                    roomH = math.random(8, 12),
                    difficulty = 'optional',
                    cleared = false,
                    enemies = {},
                    connected = {node.id},
                    isBranch = true,
                }
                
                -- Clamp to map bounds
                branchNode.cy = math.max(10, math.min(self.h - 10, branchNode.cy))
                
                table.insert(newNodes, branchNode)
                table.insert(node.connected, branchNode.id)
            end
        end
    end
    
    -- Add branch nodes to main list
    for _, bn in ipairs(newNodes) do
        table.insert(self.nodes, bn)
    end
end

--------------------------------------------------------------------------------
-- TILE CARVING
--------------------------------------------------------------------------------

function ChapterMap:initTiles()
    -- Fill map with walls
    self.tiles = {}
    for i = 1, self.w * self.h do
        self.tiles[i] = 1  -- 1 = wall
    end
end

function ChapterMap:cellIndex(cx, cy)
    return (cy - 1) * self.w + cx
end

function ChapterMap:carveRect(x1, y1, x2, y2)
    x1 = math.max(2, math.min(self.w - 1, x1))
    y1 = math.max(2, math.min(self.h - 1, y1))
    x2 = math.max(2, math.min(self.w - 1, x2))
    y2 = math.max(2, math.min(self.h - 1, y2))
    
    for cy = y1, y2 do
        local row = (cy - 1) * self.w
        for cx = x1, x2 do
            self.tiles[row + cx] = 0  -- 0 = floor
        end
    end
end

function ChapterMap:carveRoom(node)
    local halfW = math.floor(node.roomW / 2)
    local halfH = math.floor(node.roomH / 2)
    
    local x1 = node.cx - halfW
    local y1 = node.cy - halfH
    local x2 = node.cx + halfW
    local y2 = node.cy + halfH
    
    self:carveRect(x1, y1, x2, y2)
    
    -- Store room bounds in node
    node.x1, node.y1, node.x2, node.y2 = x1, y1, x2, y2
    
    -- Add room decorations for larger rooms
    if node.roomW >= 14 and node.roomH >= 14 then
        self:addRoomPillars(node)
    end
end

function ChapterMap:addRoomPillars(node)
    -- Add corner pillars for visual interest
    local inset = 3
    local pillarSize = 2
    
    local x1, y1, x2, y2 = node.x1, node.y1, node.x2, node.y2
    
    -- Four corners
    self:fillRect(x1 + inset, y1 + inset, x1 + inset + pillarSize, y1 + inset + pillarSize, 1)
    self:fillRect(x2 - inset - pillarSize, y1 + inset, x2 - inset, y1 + inset + pillarSize, 1)
    self:fillRect(x1 + inset, y2 - inset - pillarSize, x1 + inset + pillarSize, y2 - inset, 1)
    self:fillRect(x2 - inset - pillarSize, y2 - inset - pillarSize, x2 - inset, y2 - inset, 1)
end

function ChapterMap:fillRect(x1, y1, x2, y2, value)
    x1 = math.max(1, math.min(self.w, x1))
    y1 = math.max(1, math.min(self.h, y1))
    x2 = math.max(1, math.min(self.w, x2))
    y2 = math.max(1, math.min(self.h, y2))
    
    for cy = y1, y2 do
        local row = (cy - 1) * self.w
        for cx = x1, x2 do
            self.tiles[row + cx] = value
        end
    end
end

function ChapterMap:carveCorridor(fromNode, toNode)
    local x1, y1 = fromNode.cx, fromNode.cy
    local x2, y2 = toNode.cx, toNode.cy
    local width = CONFIG.corridorWidth
    
    -- L-shaped corridor (horizontal then vertical, or vice versa)
    if math.random() < 0.5 then
        -- Horizontal first
        local dir = (x2 >= x1) and 1 or -1
        for x = x1, x2, dir do
            for w = -math.floor(width/2), math.floor(width/2) do
                self:carveRect(x, y1 + w, x, y1 + w)
            end
        end
        -- Then vertical
        dir = (y2 >= y1) and 1 or -1
        for y = y1, y2, dir do
            for w = -math.floor(width/2), math.floor(width/2) do
                self:carveRect(x2 + w, y, x2 + w, y)
            end
        end
    else
        -- Vertical first
        local dir = (y2 >= y1) and 1 or -1
        for y = y1, y2, dir do
            for w = -math.floor(width/2), math.floor(width/2) do
                self:carveRect(x1 + w, y, x1 + w, y)
            end
        end
        -- Then horizontal
        dir = (x2 >= x1) and 1 or -1
        for x = x1, x2, dir do
            for w = -math.floor(width/2), math.floor(width/2) do
                self:carveRect(x, y2 + w, x, y2 + w)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- FULL GENERATION
--------------------------------------------------------------------------------

function ChapterMap:generate(opts)
    opts = opts or {}
    
    -- Override config if needed
    if opts.nodeCount then CONFIG.nodesPerChapter = opts.nodeCount end
    if opts.mapWidth then self.w = opts.mapWidth end
    if opts.mapHeight then self.h = opts.mapHeight end
    
    self.pixelW = self.w * self.tileSize
    self.pixelH = self.h * self.tileSize
    
    -- Step 1: Initialize empty map
    self:initTiles()
    
    -- Step 2: Generate main path
    self:generateSpine()
    
    -- Step 3: Add optional branches
    self:generateBranches()
    
    -- Step 4: Carve rooms
    for _, node in ipairs(self.nodes) do
        self:carveRoom(node)
    end
    
    -- Step 5: Connect rooms with corridors
    for _, node in ipairs(self.nodes) do
        for _, connectedId in ipairs(node.connected) do
            local other = self:getNodeById(connectedId)
            if other and node.id < connectedId then  -- Avoid duplicate corridors
                self:carveCorridor(node, other)
            end
        end
    end
    
    -- Step 6: Set spawn and exit positions
    local startNode = self.nodes[1]
    self.spawnX = startNode.cx * self.tileSize
    self.spawnY = startNode.cy * self.tileSize
    
    local exitNode = self:getNodeByType(NODE_TYPES.EXIT)
    if exitNode then
        self.exitX = exitNode.cx * self.tileSize
        self.exitY = exitNode.cy * self.tileSize
    end
    
    -- Step 7: Initialize navigation
    self:initNav()
    
    return self
end

function ChapterMap:getNodeById(id)
    for _, node in ipairs(self.nodes) do
        if node.id == id then return node end
    end
    return nil
end

function ChapterMap:getNodeByType(nodeType)
    for _, node in ipairs(self.nodes) do
        if node.type == nodeType then return node end
    end
    return nil
end

--------------------------------------------------------------------------------
-- NAVIGATION (reuse World's nav system)
--------------------------------------------------------------------------------

function ChapterMap:initNav()
    self.nav = {
        dist = {},
        refresh = 0.35,
        timer = 0,
        playerCx = nil,
        playerCy = nil,
        ready = false,
    }
    for i = 1, self.w * self.h do
        self.nav.dist[i] = -1
    end
    self._navQueue = {}
end

function ChapterMap:isWallCell(cx, cy)
    if cx < 1 or cy < 1 or cx > self.w or cy > self.h then return true end
    return self.tiles[self:cellIndex(cx, cy)] == 1
end

function ChapterMap:isWalkableCell(cx, cy)
    return not self:isWallCell(cx, cy)
end

function ChapterMap:worldToCell(x, y)
    local ts = self.tileSize
    return math.floor(x / ts) + 1, math.floor(y / ts) + 1
end

function ChapterMap:cellToWorld(cx, cy)
    local ts = self.tileSize
    return (cx - 0.5) * ts, (cy - 0.5) * ts
end

--------------------------------------------------------------------------------
-- MINIMAP FOG OF WAR
--------------------------------------------------------------------------------

function ChapterMap:revealArea(worldX, worldY, radius)
    local cx, cy = self:worldToCell(worldX, worldY)
    local cellRadius = math.ceil(radius / self.tileSize)
    
    for dy = -cellRadius, cellRadius do
        for dx = -cellRadius, cellRadius do
            local tx = cx + dx
            local ty = cy + dy
            if tx >= 1 and tx <= self.w and ty >= 1 and ty <= self.h then
                local idx = self:cellIndex(tx, ty)
                self.explored[idx] = true
            end
        end
    end
end

function ChapterMap:isExplored(cx, cy)
    if cx < 1 or cy < 1 or cx > self.w or cy > self.h then return false end
    return self.explored[self:cellIndex(cx, cy)] == true
end

--------------------------------------------------------------------------------
-- ROOM QUERIES (for enemy spawning)
--------------------------------------------------------------------------------

function ChapterMap:getNodeAtPosition(worldX, worldY)
    local cx, cy = self:worldToCell(worldX, worldY)
    
    for _, node in ipairs(self.nodes) do
        if node.x1 and cx >= node.x1 and cx <= node.x2 and cy >= node.y1 and cy <= node.y2 then
            return node
        end
    end
    return nil
end

function ChapterMap:getNodesInRange(worldX, worldY, range)
    local result = {}
    local rangeSq = range * range
    
    for _, node in ipairs(self.nodes) do
        local nodeWorldX = node.cx * self.tileSize
        local nodeWorldY = node.cy * self.tileSize
        local dx = nodeWorldX - worldX
        local dy = nodeWorldY - worldY
        
        if dx * dx + dy * dy <= rangeSq then
            table.insert(result, node)
        end
    end
    
    return result
end

function ChapterMap:getSpawnPointsForNode(node, count)
    -- Returns spawn points within a node's room, avoiding center
    local points = {}
    if not node or not node.x1 then return points end
    
    local padding = 2
    local minX = node.x1 + padding
    local maxX = node.x2 - padding
    local minY = node.y1 + padding
    local maxY = node.y2 - padding
    
    local attempts = count * 10
    for _ = 1, attempts do
        if #points >= count then break end
        
        local cx = math.random(minX, maxX)
        local cy = math.random(minY, maxY)
        
        -- Avoid exact center
        local distToCenter = math.abs(cx - node.cx) + math.abs(cy - node.cy)
        if distToCenter > 3 and self:isWalkableCell(cx, cy) then
            local wx, wy = self:cellToWorld(cx, cy)
            table.insert(points, {x = wx, y = wy})
        end
    end
    
    return points
end

--------------------------------------------------------------------------------
-- EXPORT
--------------------------------------------------------------------------------

function chapter.generate(opts)
    local map = chapter.new()
    return map:generate(opts)
end

return chapter
