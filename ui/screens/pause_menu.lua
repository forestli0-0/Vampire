-- ============================================================================
-- PAUSE MENU SCREEN
-- ============================================================================
-- 局内暂停菜单：继续游戏、返回基地、退出游戏

local ui = require('ui')

local pauseMenu = {}
local root = nil
local state_ref = nil
local isPaused = false
local previousUIRoot = nil  -- 保存之前的 UI 根节点

function pauseMenu.init(state)
    state_ref = state
    
    local logW, logH = 640, 360
    
    root = ui.Widget.new({x = 0, y = 0, w = logW, h = logH})
    
    -- 半透明背景遮罩
    local overlay = ui.Panel.new({
        x = 0, y = 0, w = logW, h = logH,
        bgColor = {0, 0, 0, 0.7}
    })
    root:addChild(overlay)
    
    -- 暂停面板
    local panelW, panelH = 240, 200
    local panelX = (logW - panelW) / 2
    local panelY = (logH - panelH) / 2
    
    local panel = ui.Panel.new({
        x = panelX, y = panelY, w = panelW, h = panelH,
        bgColor = {0.12, 0.14, 0.18, 0.95},
        borderColor = {0.4, 0.5, 0.6, 1},
        cornerRadius = 8
    })
    root:addChild(panel)
    
    -- 标题
    local title = ui.Text.new({
        x = 0, y = 20, w = panelW,
        text = "游戏暂停",
        font = ui.theme.getFont('title'),
        color = {1, 1, 1, 1},
        align = 'center'
    })
    panel:addChild(title)
    
    -- 按钮配置
    local btnW, btnH = 160, 32
    local btnX = (panelW - btnW) / 2
    local startY = 60
    local spacing = 40
    
    -- 继续游戏按钮
    local continueBtn = ui.Button.new({
        x = btnX, y = startY,
        w = btnW, h = btnH,
        text = "继续游戏",
        color = {0.2, 0.5, 0.3, 1}
    })
    continueBtn:on('click', function()
        pauseMenu.resume()
    end)
    panel:addChild(continueBtn)
    
    -- 返回基地按钮
    local hubBtn = ui.Button.new({
        x = btnX, y = startY + spacing,
        w = btnW, h = btnH,
        text = "返回基地",
        color = {0.3, 0.4, 0.5, 1}
    })
    hubBtn:on('click', function()
        pauseMenu.returnToHub()
    end)
    panel:addChild(hubBtn)
    
    -- 退出游戏按钮
    local quitBtn = ui.Button.new({
        x = btnX, y = startY + spacing * 2,
        w = btnW, h = btnH,
        text = "退出游戏",
        color = {0.5, 0.3, 0.3, 1}
    })
    quitBtn:on('click', function()
        love.event.quit()
    end)
    panel:addChild(quitBtn)
    
    isPaused = true
    
    -- 确保 UI 系统处于开启状态
    if ui.core then ui.core.enabled = true end
    
    -- 保存当前 UI 根节点，然后设置暂停菜单为根节点
    previousUIRoot = ui.getRoot()
    ui.setRoot(root)
end

function pauseMenu.resume()
    isPaused = false
    root = nil
    if state_ref then
        state_ref.paused = false
    end
    -- 恢复之前的 UI 根节点
    if previousUIRoot then
        ui.setRoot(previousUIRoot)
    end
    previousUIRoot = nil
end

function pauseMenu.returnToHub()
    isPaused = false
    root = nil
    previousUIRoot = nil  -- 返回基地时不需要恢复，hub 会重新设置 UI
    if state_ref then
        state_ref.paused = false
        local hub = require('world.hub')
        hub.enterHub(state_ref)
    end
end

function pauseMenu.isActive()
    return isPaused and root ~= nil
end

function pauseMenu.update(dt)
    -- 确保 UI 核心已开启
    if ui.core and not ui.core.enabled then
        ui.core.enabled = true
    end
    
    -- 确保根节点仍然是暂停菜单（防止被其他逻辑意外改写）
    if ui.getRoot() ~= root then
        ui.setRoot(root)
    end

    -- 注意：必须调用 ui.update(dt) 才能让 UI 系统处理 hover 检测和基础逻辑
    ui.update(dt)
end

function pauseMenu.draw()
    -- 暂停菜单现在通过 ui.setRoot 自动由 ui.draw() 绘制，无需手动实现 draw 函数
    -- 但为了防止某些地方显式调用，我们可以留空或简单代理
end

function pauseMenu.keypressed(key)
    if not isPaused then return false end
    
    -- ESC 关闭菜单
    if key == 'escape' then
        pauseMenu.resume()
        return true
    end
    
    -- 阻止其他按键（如Tab）传递到下层
    return true
end

return pauseMenu
