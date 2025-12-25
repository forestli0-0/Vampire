-- Minimap HUD Component
-- Shows explored areas with fog of war

local minimap = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- Position and size
    x = 10,
    y = 580,
    width = 150,
    height = 100,
    
    -- Visual
    bgColor = {0.05, 0.05, 0.08, 0.85},
    borderColor = {0.3, 0.35, 0.4, 1},
    wallColor = {0.15, 0.15, 0.2, 1},
    floorColor = {0.25, 0.28, 0.32, 1},
    unexploredColor = {0.08, 0.08, 0.1, 1},
    
    -- Icons
    playerColor = {0.3, 0.9, 0.4, 1},
    exitColor = {1, 0.8, 0.2, 1},
    merchantColor = {0.3, 0.8, 1, 1},
    bossColor = {1, 0.3, 0.3, 1},
    
    -- Reveal radius (in tiles)
    revealRadius = 12,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local state = {
    scale = 1,
    offsetX = 0,
    offsetY = 0,
    canvas = nil,
    dirty = true,  -- Redraw flag
}

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function minimap.init(chapterMap)
    if not chapterMap then return end
    
    -- Calculate scale to fit map in minimap bounds
    local mapW = chapterMap.w or 200
    local mapH = chapterMap.h or 80
    
    local scaleX = CONFIG.width / mapW
    local scaleY = CONFIG.height / mapH
    state.scale = math.min(scaleX, scaleY)
    
    -- Center offset
    state.offsetX = (CONFIG.width - mapW * state.scale) / 2
    state.offsetY = (CONFIG.height - mapH * state.scale) / 2
    
    -- Create canvas for caching
    state.canvas = love.graphics.newCanvas(CONFIG.width, CONFIG.height)
    state.dirty = true
end

--------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------

function minimap.update(gameState, chapterMap, dt)
    if not chapterMap or not gameState.player then return end
    
    local p = gameState.player
    
    -- Reveal area around player; only mark dirty if new tiles were actually revealed
    local revealed = chapterMap:revealArea(p.x, p.y, CONFIG.revealRadius * chapterMap.tileSize)
    
    if revealed then
        state.dirty = true
    end
end

--------------------------------------------------------------------------------
-- RENDERING
--------------------------------------------------------------------------------

local function drawToCanvas(chapterMap)
    local scale = state.scale
    local ox, oy = state.offsetX, state.offsetY
    
    love.graphics.setCanvas(state.canvas)
    love.graphics.clear(CONFIG.bgColor)
    
    -- Draw tiles
    for cy = 1, chapterMap.h do
        for cx = 1, chapterMap.w do
            local idx = (cy - 1) * chapterMap.w + cx
            local explored = chapterMap.explored[idx]
            
            local px = ox + (cx - 1) * scale
            local py = oy + (cy - 1) * scale
            local ps = math.max(1, scale)
            
            if explored then
                local isWall = chapterMap.tiles[idx] == 1
                if isWall then
                    love.graphics.setColor(CONFIG.wallColor)
                else
                    love.graphics.setColor(CONFIG.floorColor)
                end
            else
                love.graphics.setColor(CONFIG.unexploredColor)
            end
            
            love.graphics.rectangle('fill', px, py, ps, ps)
        end
    end
    
    -- Draw special room markers
    for _, node in ipairs(chapterMap.nodes or {}) do
        local ncx, ncy = node.cx, node.cy
        local idx = (ncy - 1) * chapterMap.w + ncx
        
        if chapterMap.explored[idx] then
            local px = ox + (ncx - 1) * scale
            local py = oy + (ncy - 1) * scale
            local size = math.max(3, scale * 3)
            
            if node.type == 'merchant' then
                love.graphics.setColor(CONFIG.merchantColor)
                love.graphics.rectangle('fill', px - size/2, py - size/2, size, size)
            elseif node.type == 'boss' then
                love.graphics.setColor(CONFIG.bossColor)
                love.graphics.circle('fill', px, py, size)
            elseif node.type == 'exit' then
                love.graphics.setColor(CONFIG.exitColor)
                love.graphics.polygon('fill', 
                    px, py - size,
                    px + size, py + size/2,
                    px - size, py + size/2
                )
            end
        end
    end
    
    love.graphics.setCanvas()
end

function minimap.draw(gameState, chapterMap)
    if not chapterMap then return end
    
    -- Redraw canvas if dirty
    if state.dirty and state.canvas then
        drawToCanvas(chapterMap)
        state.dirty = false
    end
    
    -- Draw background with border
    love.graphics.setColor(CONFIG.bgColor)
    love.graphics.rectangle('fill', CONFIG.x - 2, CONFIG.y - 2, 
        CONFIG.width + 4, CONFIG.height + 4, 4, 4)
    
    love.graphics.setColor(CONFIG.borderColor)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle('line', CONFIG.x - 2, CONFIG.y - 2, 
        CONFIG.width + 4, CONFIG.height + 4, 4, 4)
    
    -- Draw cached canvas
    if state.canvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(state.canvas, CONFIG.x, CONFIG.y)
    end
    
    -- Draw player position (always on top)
    if gameState.player then
        local p = gameState.player
        local pcx, pcy = chapterMap:worldToCell(p.x, p.y)
        
        local px = CONFIG.x + state.offsetX + (pcx - 1) * state.scale
        local py = CONFIG.y + state.offsetY + (pcy - 1) * state.scale
        
        -- Pulsing player dot
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 4)
        love.graphics.setColor(CONFIG.playerColor[1], CONFIG.playerColor[2], 
            CONFIG.playerColor[3], pulse)
        love.graphics.circle('fill', px, py, 4)
        
        -- Direction indicator
        local facing = p.facing or 1
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle('fill', px + facing * 3, py, 2)
    end
    
    -- Draw exit direction arrow (if exit is unexplored)
    local exitNode = nil
    for _, node in ipairs(chapterMap.nodes or {}) do
        if node.type == 'exit' then
            exitNode = node
            break
        end
    end
    
    if exitNode and gameState.player then
        local p = gameState.player
        local pcx, pcy = chapterMap:worldToCell(p.x, p.y)
        
        local dx = exitNode.cx - pcx
        local dy = exitNode.cy - pcy
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist > 5 then  -- Only show if exit is far
            local ang = math.atan2(dy, dx)
            local arrowDist = math.min(40, CONFIG.width / 3)
            
            local centerX = CONFIG.x + CONFIG.width / 2
            local centerY = CONFIG.y + CONFIG.height / 2
            
            local ax = centerX + math.cos(ang) * arrowDist
            local ay = centerY + math.sin(ang) * arrowDist
            
            -- Arrow pointing to exit
            love.graphics.setColor(CONFIG.exitColor)
            local arrowSize = 6
            love.graphics.polygon('fill',
                ax + math.cos(ang) * arrowSize,
                ay + math.sin(ang) * arrowSize,
                ax + math.cos(ang + 2.5) * arrowSize,
                ay + math.sin(ang + 2.5) * arrowSize,
                ax + math.cos(ang - 2.5) * arrowSize,
                ay + math.sin(ang - 2.5) * arrowSize
            )
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- TOGGLE
--------------------------------------------------------------------------------

local visible = true

function minimap.toggle()
    visible = not visible
end

function minimap.isVisible()
    return visible
end

function minimap.setVisible(v)
    visible = v
end

return minimap
