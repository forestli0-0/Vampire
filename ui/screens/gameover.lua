-- Game Over / Victory Screen
-- Replaces legacy draw.lua rendering and main.lua input logic
local ui = require('ui')
local theme = ui.theme

local gameoverScreen = {}

local root = nil
local state = nil

-- Layout constants
local LAYOUT = {
    screenW = 640,
    screenH = 360,
    titleY = 60
}

-------------------------------------------
-- Main Screen Logic
-------------------------------------------

function gameoverScreen.init(gameState)
    state = gameState
    gameoverScreen.rebuild(gameState)
end

function gameoverScreen.isActive()
    return ui.core.getRoot() == root and root ~= nil
end

function gameoverScreen.rebuild(gameState)
    state = gameState
    
    root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    
    -- Dark overlay
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0, 0, 0, 0.85}
    })
    root:addChild(bg)
    
    local isVictory = (state.gameState == 'GAME_CLEAR')
    
    -- Title
    local titleText = isVictory and "VICTORY!" or "GAME OVER"
    local titleColor = isVictory and theme.colors.success or theme.colors.danger
    
    local title = ui.Text.new({
        x = 0, y = LAYOUT.titleY, w = LAYOUT.screenW,
        text = titleText,
        color = titleColor,
        align = 'center',
        font = theme.getFont('title'),
        outline = true,
        glow = true,
        glowColor = titleColor,
        glowAlpha = 0.28
    })
    root:addChild(title)
    
    -- Content
    local contentY = LAYOUT.titleY + 60
    
    if isVictory then
        local rewards = state.victoryRewards or {}
        local rewardStr = ""
        
        -- Statistics or flavor text could go here
        local msg = ui.Text.new({
            x = 0, y = contentY, w = LAYOUT.screenW,
            text = "Boss Defeated! Mission Accomplished.",
            color = theme.colors.text,
            align = 'center',
            font = theme.getFont('large')
        })
        root:addChild(msg)
        contentY = contentY + 40
        
        -- Rewards
        if rewards.currency and rewards.currency > 0 then
            local rText = string.format("+%d Credits", rewards.currency)
            local rLabel = ui.Text.new({
                x = 0, y = contentY, w = LAYOUT.screenW,
                text = rText,
                color = theme.colors.gold,
                align = 'center',
                font = theme.getFont('default')
            })
            root:addChild(rLabel)
            contentY = contentY + 30
        end
        
        if rewards.newModName then
            local mText = "New Mod: " .. rewards.newModName
            local mLabel = ui.Text.new({
                x = 0, y = contentY, w = LAYOUT.screenW,
                text = mText,
                color = theme.colors.accent,
                align = 'center',
                 font = theme.getFont('default')
            })
            root:addChild(mLabel)
            contentY = contentY + 30
        end
        
    else
        -- Defeat
        local msg = ui.Text.new({
            x = 0, y = contentY, w = LAYOUT.screenW,
            text = "You have fallen.",
            color = theme.colors.text_dim,
            align = 'center',
            font = theme.getFont('large')
        })
        root:addChild(msg)
    end
    
    -- Buttons
    local startY = 240
    local btnW, btnH = 200, 40
    local gap = 20
    
    -- Restart
    local restartBtn = ui.Button.new({
        x = (LAYOUT.screenW - btnW) / 2,
        y = startY,
        w = btnW, h = btnH,
        text = "Restart (R)",
        color = theme.colors.primary -- Updated from success to primary for consistency
    })
    restartBtn:on('click', function()
        love.load() -- Simplest restart
    end)
    root:addChild(restartBtn)
    
    -- Arsenal / Quit
    local arsenalBtn = ui.Button.new({
        x = (LAYOUT.screenW - btnW) / 2,
        y = startY + btnH + gap,
        w = btnW, h = btnH,
        text = "Return to Arsenal",
        color = theme.colors.panel_bg -- Darker button
    })
    arsenalBtn:on('click', function()
        -- Return to Arsenal logic
        -- Reset game state but keep profile
        state.gameState = 'ARSENAL'
        ui.core.setRoot(nil)
        local arsenal = require('core.arsenal')
        arsenal.show(state)
    end)
    root:addChild(arsenalBtn)
    
    ui.core.setRoot(root)
end

function gameoverScreen.keypressed(key)
    if not (ui.core.getRoot() == root) then return false end
    
    if key == 'r' then
        love.load()
        return true
    end
    
    if key == 'escape' or key == 'return' or key == 'space' then
         -- Return to Arsenal
        state.gameState = 'ARSENAL'
        ui.core.setRoot(nil)
        local arsenal = require('core.arsenal')
        arsenal.show(state)
        return true
    end
    
    return ui.keypressed(key)
end

return gameoverScreen
