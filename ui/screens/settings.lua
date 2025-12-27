-- ============================================================================
-- SETTINGS SCREEN
-- ============================================================================
-- 设置界面：音量调节等

local ui = require('ui')

local settings = {}
local root = nil
local state_ref = nil
local onClose = nil

-- 默认音量值 (0.0 - 1.0)
local volumes = {
    master = 1.0,
    music = 0.7,
    sfx = 0.8
}

-- 保存音量到存档
local function saveVolumes()
    if state_ref and state_ref.profile then
        state_ref.profile.volumes = {
            master = volumes.master,
            music = volumes.music,
            sfx = volumes.sfx
        }
        if state_ref.saveProfile then
            state_ref.saveProfile(state_ref.profile)
        end
    end
end

-- 应用音量设置
local function applyVolumes()
    -- 使用新的音频系统设置音量
    if state_ref and state_ref.audio and state_ref.audio.setVolumes then
        state_ref.audio.setVolumes(volumes.master, volumes.music, volumes.sfx)
    else
        -- 回退到旧方式（兼容性）
        if state_ref and state_ref.music and state_ref.music.setVolume then
            pcall(function()
                state_ref.music:setVolume(volumes.master * volumes.music)
            end)
        end
        if state_ref then
            state_ref.sfxMasterVolume = volumes.master * volumes.sfx
        end
    end
end

-- 加载音量设置
local function loadVolumes()
    if state_ref and state_ref.profile and state_ref.profile.volumes then
        local v = state_ref.profile.volumes
        volumes.master = v.master or 1.0
        volumes.music = v.music or 0.7
        volumes.sfx = v.sfx or 0.8
    end
end

function settings.init(state, closeCallback)
    state_ref = state
    onClose = closeCallback
    loadVolumes()
    
    local logW, logH = 640, 360
    
    root = ui.Widget.new({x = 0, y = 0, w = logW, h = logH})
    
    -- 半透明背景遮罩
    local overlay = ui.Panel.new({
        x = 0, y = 0, w = logW, h = logH,
        bgColor = {0, 0, 0, 0.7}
    })
    root:addChild(overlay)
    
    -- 设置面板
    local panelW, panelH = 320, 240
    local panelX = (logW - panelW) / 2
    local panelY = (logH - panelH) / 2
    
    local panel = ui.Panel.new({
        x = panelX, y = panelY, w = panelW, h = panelH,
        bgColor = {0.15, 0.17, 0.22, 0.95},
        borderColor = {0.4, 0.5, 0.6, 1},
        cornerRadius = 8
    })
    root:addChild(panel)
    
    -- 标题
    local title = ui.Text.new({
        x = 0, y = 15, w = panelW,
        text = "设置 (Settings)",
        font = ui.theme.getFont('title'),
        color = {1, 1, 1, 1},
        align = 'center'
    })
    panel:addChild(title)
    
    -- 音量控制器位置
    local sliderX = 20
    local sliderW = panelW - 40
    local labelW = 100
    local barX = sliderX + labelW
    local barW = sliderW - labelW - 60
    local startY = 60
    local rowH = 45
    
    -- 创建音量条
    local function createVolumeRow(label, y, volumeKey)
        -- 标签
        local lbl = ui.Text.new({
            x = sliderX, y = y + 8, w = labelW,
            text = label,
            font = ui.theme.getFont('normal'),
            color = {0.8, 0.8, 0.9, 1},
            align = 'left'
        })
        panel:addChild(lbl)
        
        -- 音量条背景
        local barBg = ui.Panel.new({
            x = barX, y = y + 10, w = barW, h = 16,
            bgColor = {0.1, 0.1, 0.15, 1},
            cornerRadius = 3
        })
        panel:addChild(barBg)
        
        -- 音量条填充
        local barFill = ui.Panel.new({
            x = barX + 2, y = y + 12, w = (barW - 4) * volumes[volumeKey], h = 12,
            bgColor = {0.3, 0.7, 1, 1},
            cornerRadius = 2
        })
        panel:addChild(barFill)
        
        -- 百分比文本
        local pctText = ui.Text.new({
            x = barX + barW + 5, y = y + 8, w = 50,
            text = math.floor(volumes[volumeKey] * 100) .. "%",
            font = ui.theme.getFont('small'),
            color = {0.7, 0.7, 0.8, 1},
            align = 'left'
        })
        panel:addChild(pctText)
        
        -- 减少按钮
        local minusBtn = ui.Button.new({
            x = barX - 25, y = y + 7, w = 20, h = 20,
            text = "-",
            color = {0.4, 0.4, 0.5, 1}
        })
        minusBtn:on('click', function()
            volumes[volumeKey] = math.max(0, volumes[volumeKey] - 0.1)
            barFill.w = (barW - 4) * volumes[volumeKey]
            local newText = math.floor(volumes[volumeKey] * 100) .. "%"
            pctText.text = newText
            pctText.displayText = newText
            applyVolumes()
            saveVolumes()
        end)
        panel:addChild(minusBtn)
        
        -- 增加按钮
        local plusBtn = ui.Button.new({
            x = barX + barW + 35, y = y + 7, w = 20, h = 20,
            text = "+",
            color = {0.4, 0.4, 0.5, 1}
        })
        plusBtn:on('click', function()
            volumes[volumeKey] = math.min(1, volumes[volumeKey] + 0.1)
            barFill.w = (barW - 4) * volumes[volumeKey]
            local newText = math.floor(volumes[volumeKey] * 100) .. "%"
            pctText.text = newText
            pctText.displayText = newText
            applyVolumes()
            saveVolumes()
        end)
        panel:addChild(plusBtn)
    end
    
    createVolumeRow("主音量:", startY, 'master')
    createVolumeRow("音乐:", startY + rowH, 'music')
    createVolumeRow("音效:", startY + rowH * 2, 'sfx')
    
    -- 返回按钮
    local backBtn = ui.Button.new({
        x = (panelW - 100) / 2, y = panelH - 50,
        w = 100, h = 30,
        text = "返回",
        color = ui.theme.colors.button_normal
    })
    backBtn:on('click', function()
        settings.close()
    end)
    panel:addChild(backBtn)
    
    applyVolumes()
end

function settings.close()
    root = nil
    if onClose then
        onClose()
    end
end

function settings.isActive()
    return root ~= nil
end

function settings.update(dt)
    if root then root:update(dt) end
end

function settings.draw()
    if root then root:draw() end
end

function settings.getRoot()
    return root
end

-- 获取当前音效音量（供外部使用）
function settings.getSfxVolume()
    return volumes.master * volumes.sfx
end

function settings.getMusicVolume()
    return volumes.master * volumes.music
end

return settings
