-- Shop Screen
-- Modern grid-based shop UI inspired by Warframe vendors
local ui = require('ui')
local theme = ui.theme

local shopScreen = {}

local root = nil
local state = nil
local selectedIdx = 1  -- Keyboard selection

-- Layout constants
local LAYOUT = {
    screenW = 640,
    screenH = 360,
    titleY = 20,
    
    -- Grid layout
    gridStartY = 70,
    gridCols = 2,
    cardW = 280,
    cardH = 70,
    cardGapX = 16,
    cardGapY = 10,
    
    -- Colors
    cardBg = {0.12, 0.12, 0.15, 0.95},
    cardBgHover = {0.18, 0.20, 0.25, 0.98},
    cardBgDisabled = {0.08, 0.08, 0.10, 0.7},
    cardBorder = {0.35, 0.35, 0.40, 1},
    cardBorderSelected = {1.0, 0.85, 0.30, 1},
    cardBorderHover = {0.5, 0.6, 0.8, 1},
}

-------------------------------------------
-- Shop Card Widget
-------------------------------------------
local ShopCard = setmetatable({}, {__index = ui.Widget})
ShopCard.__index = ShopCard

function ShopCard.new(opts)
    opts = opts or {}
    opts.w = opts.w or LAYOUT.cardW
    opts.h = opts.h or LAYOUT.cardH
    opts.focusable = true
    
    local self = setmetatable(ui.Widget.new(opts), ShopCard)
    
    self.option = opts.option or {}
    self.index = opts.index or 1
    self.gameState = opts.gameState
    
    -- Visual state
    self.hoverT = 0
    self.selectedT = 0
    self.selected = false
    
    -- Calculate status
    local gold = math.floor((opts.gameState and opts.gameState.runCurrency) or 0)
    local cost = math.floor(self.option.cost or 0)
    self.cost = cost
    self.affordable = (gold >= cost)
    self.enabled = (self.option.enabled == nil) or (self.option.enabled == true)
    self.active = self.enabled and self.affordable
    
    return self
end

function ShopCard:update(dt)
    ui.Widget.update(self, dt)
    
    -- Animate hover
    local targetHover = (self.hovered or self.focused) and 1 or 0
    self.hoverT = self.hoverT + (targetHover - self.hoverT) * math.min(1, dt * 12)
    
    -- Animate selection
    local targetSelect = self.selected and 1 or 0
    self.selectedT = self.selectedT + (targetSelect - self.selectedT) * math.min(1, dt * 10)
end

function ShopCard:drawSelf()
    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    local opt = self.option
    
    -- Background
    local bgColor
    if not self.active then
        bgColor = LAYOUT.cardBgDisabled
    elseif self.hoverT > 0.01 then
        bgColor = theme.lerpColor(LAYOUT.cardBg, LAYOUT.cardBgHover, self.hoverT)
    else
        bgColor = LAYOUT.cardBg
    end
    
    love.graphics.setColor(bgColor)
    love.graphics.rectangle('fill', gx, gy, w, h, 4, 4)
    
    -- Border
    local borderColor
    if self.selectedT > 0.01 then
        borderColor = theme.lerpColor(LAYOUT.cardBorder, LAYOUT.cardBorderSelected, self.selectedT)
    elseif self.hoverT > 0.01 and self.active then
        borderColor = theme.lerpColor(LAYOUT.cardBorder, LAYOUT.cardBorderHover, self.hoverT)
    else
        borderColor = LAYOUT.cardBorder
    end
    
    love.graphics.setColor(borderColor)
    love.graphics.setLineWidth(self.selected and 2 or 1)
    love.graphics.rectangle('line', gx, gy, w, h, 4, 4)
    love.graphics.setLineWidth(1)
    
    -- Index badge
    local badgeSize = 20
    love.graphics.setColor(theme.colors.accent[1], theme.colors.accent[2], theme.colors.accent[3], 0.8)
    love.graphics.rectangle('fill', gx + 6, gy + 6, badgeSize, badgeSize, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(tostring(self.index), gx + 6, gy + 9, badgeSize, 'center')
    
    -- Name
    local nameX = gx + 34
    local nameColor = self.active and theme.colors.text or theme.colors.text_dim
    love.graphics.setColor(nameColor)
    love.graphics.setFont(theme.getFont('normal'))
    love.graphics.print(opt.name or "Item", nameX, gy + 8)
    
    -- Description
    love.graphics.setColor(theme.colors.text_dim)
    love.graphics.setFont(theme.getFont('small'))
    local desc = opt.desc or ""
    if #desc > 35 then desc = string.sub(desc, 1, 32) .. "..." end
    love.graphics.print(desc, nameX, gy + 28)
    
    -- Disabled reason
    if not self.enabled and opt.disabledReason then
        love.graphics.setColor(theme.colors.danger)
        love.graphics.print(opt.disabledReason, nameX, gy + 44)
    elseif not self.affordable and self.enabled then
        love.graphics.setColor(theme.colors.danger)
        love.graphics.print("金币不足", nameX, gy + 44)
    end
    
    -- Price (right side)
    local priceX = gx + w - 60
    local priceColor = self.affordable and theme.colors.gold or theme.colors.danger
    love.graphics.setColor(priceColor)
    love.graphics.setFont(theme.getFont('normal'))
    love.graphics.printf(tostring(self.cost), priceX, gy + 24, 50, 'right')
    
    -- Gold icon placeholder
    love.graphics.setColor(theme.colors.gold[1], theme.colors.gold[2], theme.colors.gold[3], 0.7)
    love.graphics.circle('fill', gx + w - 14, gy + 30, 5)
    
    love.graphics.setColor(1, 1, 1, 1)
end

function ShopCard:drawEmissiveSelf()
    local glowT = math.max(self.hoverT or 0, self.selectedT or 0, (self.focused and 1 or 0))
    if glowT <= 0.001 then return end

    local gx, gy = self:getGlobalPosition()
    local w, h = self.w, self.h
    if w <= 0 or h <= 0 then return end

    local borderColor
    if self.selectedT > 0.01 then
        borderColor = theme.lerpColor(LAYOUT.cardBorder, LAYOUT.cardBorderSelected, self.selectedT)
    elseif self.hoverT > 0.01 and self.active then
        borderColor = theme.lerpColor(LAYOUT.cardBorder, LAYOUT.cardBorderHover, self.hoverT)
    else
        borderColor = LAYOUT.cardBorder
    end

    local baseAlpha = self.active and 0.12 or 0.07
    local alpha = baseAlpha + 0.36 * glowT
    local expand = self.selected and 2 or 1

    love.graphics.setBlendMode('add')
    love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle('line', gx - expand, gy - expand, w + expand * 2, h + expand * 2, 5, 5)
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1, 1, 1, 1)
end

function ShopCard:onActivate()
    if self.active then
        self:emit('purchase', self.index)
    end
end

-------------------------------------------
-- Main Screen Logic
-------------------------------------------

local cards = {}

function shopScreen.init(gameState)
    state = gameState
    shopScreen.rebuild(gameState)
end

function shopScreen.isActive()
    return ui.core.getRoot() == root and root ~= nil
end

function shopScreen.rebuild(gameState)
    state = gameState
    cards = {}
    selectedIdx = 1
    
    root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    
    -- Dark overlay
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0, 0, 0, 0.92}
    })
    root:addChild(bg)
    
    -- Title
    local title = ui.Text.new({
        x = 0, y = LAYOUT.titleY, w = LAYOUT.screenW,
        text = "商 店",
        color = theme.colors.gold,
        align = 'center',
        font = theme.getFont('title'),
        outline = true,
        glow = true,
        glowColor = theme.colors.gold,
        glowAlpha = 0.28
    })
    root:addChild(title)
    
    -- Gold Display
    local gold = math.floor(state.runCurrency or 0)
    local goldPanel = ui.Panel.new({
        x = LAYOUT.screenW/2 - 60, y = LAYOUT.titleY + 30,
        w = 120, h = 24,
        bgColor = {0.1, 0.1, 0.12, 0.9},
        cornerRadius = 4
    })
    root:addChild(goldPanel)
    
    local goldText = ui.Text.new({
        x = 0, y = 4, w = 120,
        text = "💰 " .. gold,
        color = theme.colors.gold,
        align = 'center',
        glow = true,
        glowColor = theme.colors.gold,
        glowAlpha = 0.22
    })
    goldPanel:addChild(goldText)
    
    -- Build Card Grid
    local shop = state.shop or {}
    local options = shop.options or {}
    
    local gridW = LAYOUT.cardW * LAYOUT.gridCols + LAYOUT.cardGapX * (LAYOUT.gridCols - 1)
    local startX = (LAYOUT.screenW - gridW) / 2
    local startY = LAYOUT.gridStartY
    
    for i, opt in ipairs(options) do
        local col = ((i - 1) % LAYOUT.gridCols)
        local row = math.floor((i - 1) / LAYOUT.gridCols)
        
        local cardX = startX + col * (LAYOUT.cardW + LAYOUT.cardGapX)
        local cardY = startY + row * (LAYOUT.cardH + LAYOUT.cardGapY)
        
        local card = ShopCard.new({
            x = cardX, y = cardY,
            option = opt,
            index = i,
            gameState = state
        })
        
        card:on('click', function()
            shopScreen.selectAndBuy(i)
        end)
        
        card:on('purchase', function(_, idx)
            shopScreen.buyItem(idx)
        end)
        
        root:addChild(card)
        table.insert(cards, card)
    end
    
    -- Select first card
    if #cards > 0 then
        cards[1].selected = true
        ui.core.setFocus(cards[1])
    end
    
    -- Help text (bottom)
    local help = ui.Text.new({
        x = 0, y = LAYOUT.screenH - 28, w = LAYOUT.screenW,
        text = "按数字键购买  |  方向键选择  |  Enter确认  |  ESC离开",
        color = theme.colors.text_dim,
        align = 'center',
        font = theme.getFont('small')
    })
    root:addChild(help)
    
    ui.core.setRoot(root)
end

function shopScreen.selectCard(idx)
    if idx < 1 or idx > #cards then return end
    
    -- Deselect current
    if cards[selectedIdx] then
        cards[selectedIdx].selected = false
    end
    
    -- Select new
    selectedIdx = idx
    if cards[selectedIdx] then
        cards[selectedIdx].selected = true
        ui.core.setFocus(cards[selectedIdx])
    end
end

function shopScreen.selectAndBuy(idx)
    shopScreen.selectCard(idx)
    shopScreen.buyItem(idx)
end

function shopScreen.buyItem(idx)
    local shop = state.shop or {}
    if not shop.options or idx < 1 or idx > #shop.options then return end
    
    local opt = shop.options[idx]
    local gold = math.floor(state.runCurrency or 0)
    local cost = math.floor(opt.cost or 0)
    local affordable = (gold >= cost)
    local enabled = (opt.enabled == nil) or (opt.enabled == true)
    
    if enabled and affordable then
        if opt.onBuy then
            opt.onBuy(state, opt, shop)
            -- Refresh UI to update gold/status
            shopScreen.rebuild(state)
        end
    end
end

function shopScreen.close()
    state.shop = nil
    state.gameState = 'PLAYING'
    ui.core.setRoot(nil)
    
    -- Re-enable HUD
    local hud = require('ui.screens.hud')
    if hud.rebuild then hud.rebuild(state) end
end

function shopScreen.keypressed(key)
    if not (ui.core.getRoot() == root) then return false end
    
    -- Close shop
    if key == 'escape' or key == 'backspace' or key == '0' then
        shopScreen.close()
        return true
    end
    
    -- Number key direct buy
    local idx = tonumber(key)
    if idx and idx >= 1 and idx <= #cards then
        shopScreen.selectAndBuy(idx)
        return true
    end
    
    -- Arrow navigation
    if key == 'left' then
        shopScreen.selectCard(selectedIdx - 1)
        return true
    elseif key == 'right' then
        shopScreen.selectCard(selectedIdx + 1)
        return true
    elseif key == 'up' then
        shopScreen.selectCard(selectedIdx - LAYOUT.gridCols)
        return true
    elseif key == 'down' then
        shopScreen.selectCard(selectedIdx + LAYOUT.gridCols)
        return true
    end
    
    -- Enter to confirm purchase
    if key == 'return' or key == 'kpenter' then
        shopScreen.buyItem(selectedIdx)
        return true
    end
    
    return ui.keypressed(key)
end

return shopScreen
