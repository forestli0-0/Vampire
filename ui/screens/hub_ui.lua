-- ============================================================================
-- HUB UI SCREEN
-- ============================================================================

local ui = require('ui')
local widget = require('ui.widgets.widget')
local text = require('ui.widgets.text')
local arsenal = require('core.arsenal')

local hubUI = {}
local root = nil

function hubUI.init(state)
    local logW, logH = 640, 360
    
    root = ui.Widget.new({x = 0, y = 0, w = logW, h = logH})
    
    -- Interaction Hint
    local hint = ui.Text.new({
        x = 0, y = logH - 40, w = logW,
        text = "使用 WASD 移动 | 接近控制台按 [E] 备战 | [Space] 开启远征",
        font = ui.theme.getFont('normal'),
        color = {0.7, 0.7, 0.8, 0.8},
        align = 'center',
        shadow = true
    })
    root:addChild(hint)
    
    -- Top Left Status
    local status = ui.Text.new({
        x = 20, y = 20,
        text = "中继站 / 处于安全区",
        font = ui.theme.getFont('normal'),
        color = {0.4, 0.8, 1.0, 1},
        outline = true
    })
    root:addChild(status)
    
    ui.setRoot(root)
end

function hubUI.update(state, dt)
    if not root then hubUI.init(state) end
    
    local p = state.player
    local canInteract = nil
    
    -- 检测玩家与交互点的距离
    if state.hubInteractions then
        for _, inter in ipairs(state.hubInteractions) do
            local dx = p.x - inter.x
            local dy = p.y - inter.y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < inter.radius + 10 then
                canInteract = inter
                break
            end
        end
    end

    -- 检测交互输入
    if canInteract and love.keyboard.isDown('e') then
        if canInteract.type == 'arsenal' then
            state.gameState = 'ARSENAL'
            arsenal.show(state)
        elseif canInteract.type == 'chapter_entry' then
            arsenal.startRun(state, {runMode = 'chapter'})
        end
    end
    
    -- 快捷键仍保留（方便调试）
    if love.keyboard.isDown('space') and not canInteract then
        arsenal.startRun(state, {runMode = 'chapter'})
    end
end

function hubUI.draw()
    if root then root:draw() end
end

return hubUI
