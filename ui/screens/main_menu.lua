-- ============================================================================
-- MAIN MENU SCREEN
-- ============================================================================

local ui = require('ui')
local widget = require('ui.widgets.widget')
local panel = require('ui.widgets.panel')
local button = require('ui.widgets.button')
local text = require('ui.widgets.text')
local state_module = require('core.state')
local hub = require('world.hub')

local mainMenu = {}
local root = nil

function mainMenu.init(state)
    -- 注意：UI系统使用 640x360 的逻辑分辨率
    local logW, logH = 640, 360
    
    root = ui.Widget.new({x = 0, y = 0, w = logW, h = logH})
    
    -- 背景面板
    local bg = ui.Panel.new({
        x = 0, y = 0, w = logW, h = logH,
        bgColor = {0.1, 0.12, 0.15, 1}
    })
    root:addChild(bg)
    
    -- 居中内容容器
    local menuW, menuH = 300, 200
    local menuPanel = ui.Widget.new({
        x = (logW - menuW) / 2,
        y = (logH - menuH) / 2,
        w = menuW, h = menuH
    })
    root:addChild(menuPanel)
    
    -- 标题
    local title = ui.Text.new({
        x = 0, y = 0, w = menuW,
        text = "VAMPIRE",
        font = ui.theme.getFont('title'),
        color = {1, 0.2, 0.2, 1},
        align = 'center',
        outline = true,
        glow = true,
        glowColor = {1, 0, 0}
    })
    menuPanel:addChild(title)
    
    local subtitle = ui.Text.new({
        x = 0, y = 35, w = menuW,
        text = "ROGUE REFRACTION",
        font = ui.theme.getFont('normal'),
        color = {0.7, 0.7, 0.8, 1},
        align = 'center'
    })
    menuPanel:addChild(subtitle)
    
    -- 按钮
    local btnW, btnH = 160, 35
    local startY = 100
    
    local startBtn = ui.Button.new({
        x = (menuW - btnW) / 2, y = startY,
        w = btnW, h = btnH,
        text = "开始任务 (START)",
        color = ui.theme.colors.button_normal
    })
    startBtn:on('click', function()
        local hub = require('world.hub')
        hub.enterHub(state)
    end)
    menuPanel:addChild(startBtn)
    
    local quitBtn = ui.Button.new({
        x = (menuW - btnW) / 2, y = startY + btnH + 15,
        w = btnW, h = btnH,
        text = "退出游戏 (QUIT)",
        color = ui.theme.colors.button_normal
    })
    quitBtn:on('click', function()
        love.event.quit()
    end)
    menuPanel:addChild(quitBtn)
    
    ui.setRoot(root)
end

function mainMenu.update(dt)
    if root then root:update(dt) end
end

function mainMenu.draw()
    if root then root:draw() end
end

return mainMenu
