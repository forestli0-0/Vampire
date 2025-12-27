-- ============================================================================
-- HUB MAP EDITOR
-- ============================================================================
-- 作用：实时编辑基地的地形布局。
-- 快捷键：F10 (由 hub.lua 触发)

local hubEditor = {}

local active = false
local selectedTile = 10 -- 默认第1个 Tileset 地块 (10 -> Quads[1])
local paletteScale = 0.5
local paletteTileSize = 128 * 0.5 -- 64px

function hubEditor.toggle()
    active = not active
    print("[Editor] Mode: " .. (active and "ON" or "OFF"))
    -- 开启编辑器时锁定玩家移动 (可以在 hub.update 里根据此标志决定)
end

function hubEditor.isActive()
    return active
end

function hubEditor.update(state, dt)
    if not active then return end

    local mx, my = love.mouse.getPosition()
    -- 简单的调色板交互 (固定在右侧)
    local screenW = love.graphics.getWidth()
    local paletteX = screenW - 150
    
    if mx > paletteX then
        -- 在调色板区域点击选择地块
        if love.mouse.isDown(1) then
            local col = math.floor((mx - paletteX) / (32 + 4))
            local row = math.floor((my - 50) / (32 + 4))
            if col >= 0 and col < 4 then
                local idx = row * 4 + col + 1
                if state.hubTilesetQuads and state.hubTilesetQuads[idx] then
                    selectedTile = idx + 9 -- 映射回 Tile ID (1 -> 10, etc)
                end
            end
        end
    else
        -- 在世界区域点击放置地块
        if love.mouse.isDown(1) or love.mouse.isDown(2) then
            local ts = state.world.tileSize
            -- 将屏幕坐标转为世界坐标 (考虑摄像机)
            local worldX = mx + state.camera.x
            local worldY = my + state.camera.y
            
            local tx = math.floor(worldX / ts) + 1
            local ty = math.floor(worldY / ts) + 1
            
            if tx >= 1 and tx <= state.world.w and ty >= 1 and ty <= state.world.h then
                local idx = (ty - 1) * state.world.w + tx
                if love.mouse.isDown(1) then
                    state.world.tiles[idx] = selectedTile
                else
                    state.world.tiles[idx] = 1 -- 右键抹除为墙壁
                end
            end
        end
    end

    -- 快捷键保存 (打印到控制台，以便我复制)
    if love.keyboard.isDown('f6') then
        hubEditor.save(state)
    end
end

function hubEditor.draw(state)
    if not active then return end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- 1. 绘制网格线
    love.graphics.setColor(1, 1, 1, 0.1)
    local ts = state.world.tileSize
    local camX, camY = state.camera.x, state.camera.y
    
    love.graphics.push()
    love.graphics.translate(-camX % ts, -camY % ts)
    for x = 0, sw + ts, ts do
        love.graphics.line(x, 0, x, sh + ts)
    end
    for y = 0, sh + ts, ts do
        love.graphics.line(0, y, sw + ts, y)
    end
    love.graphics.pop()

    -- 2. 绘制调色板 (Palette)
    local px = sw - 150
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle('fill', px, 0, 150, sh)
    love.graphics.setColor(0.4, 0.7, 1.0, 1)
    love.graphics.print("TILES (F6 to Save)", px + 10, 20)
    
    if state.hubTileset and state.hubTilesetQuads then
        local margin = 4
        local size = 32
        for i, quad in ipairs(state.hubTilesetQuads) do
            local col = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            local tx = px + 10 + col * (size + margin)
            local ty = 50 + row * (size + margin)
            
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(state.hubTileset, quad, tx, ty, 0, size/128, size/128)
            
            -- 选中框
            if selectedTile == i + 9 then
                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.rectangle('line', tx - 1, ty - 1, size + 2, size + 2)
            end
        end
    end

    -- 3. 绘制鼠标预览
    local mx, my = love.mouse.getPosition()
    if mx < px then
        local ts = state.world.tileSize
        local gx = math.floor((mx + state.camera.x) / ts) * ts - state.camera.x
        local gy = math.floor((my + state.camera.y) / ts) * ts - state.camera.y
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.rectangle('line', gx, gy, ts, ts)
    end
end

function hubEditor.save(state)
    print("--- HUB MAP EXPORT ---")
    local w = state.world.w
    local h = state.world.h
    local tiles = state.world.tiles
    
    local lines = {}
    table.insert(lines, "local mapData = {")
    table.insert(lines, "    w = " .. w .. ",")
    table.insert(lines, "    h = " .. h .. ",")
    table.insert(lines, "    tiles = {")
    
    for y = 1, h do
        local row = {}
        for x = 1, w do
            table.insert(row, tiles[(y - 1) * w + x])
        end
        table.insert(lines, "        " .. table.concat(row, ", ") .. ",")
    end
    
    table.insert(lines, "    }")
    table.insert(lines, "}")
    
    local output = table.concat(lines, "\n")
    print(output)
    print("--- END EXPORT ---")
end

return hubEditor
