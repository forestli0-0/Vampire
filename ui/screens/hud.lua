local ui = require('ui')
local theme = require('ui.theme')
local scaling = require('ui.scaling')
local hudModel = require('ui.hud_model')

local hud = {}
local root = nil

-- References to active widgets for updating
local widgets = {
    hpBar = nil,
    hpText = nil,
    shieldBar = nil,
    shieldText = nil,
    energyBar = nil,
    energyText = nil,
    xpBar = nil,
    xpText = nil,
    levelText = nil,
    goldText = nil,
    dashBar = nil,
    dashText = nil,
    dashValue = nil,
    staticChargeBar = nil,
    staticChargeText = nil,
    staticChargeValue = nil,
    weaponSlots = {},
    abilitySlots = {},
    objectiveText = nil,
    objectivePanel = nil
}

-------------------------------------------
-- Constants
-------------------------------------------

local LAYOUT = {
    -- Player Frame (Top Left)
    playerX = 20,
    playerY = 20,
    barWidth = 200,
    barHeight = 10,
    
    -- Combat Frame (Bottom Right)
    combatX = 640 - 20,
    combatY = 360 - 20,
    
    -- Objective (Top Center)
    objX = 320,
    objY = 10,
    
    -- Colors
    hpColor = {0.8, 0.2, 0.2, 1},
    shieldColor = {0.2, 0.6, 0.9, 1},
    energyColor = {0.3, 0.4, 0.8, 1},
    xpColor = {0.9, 0.8, 0.2, 1},
    goldColor = {1, 0.9, 0.4, 1},
    dashColor = {0.5, 0.8, 0.9, 1}
}

local HUD_NUM_COLOR = {0.9, 0.95, 1, 0.8}
local HUD_LABEL_COLOR = {0.7, 0.75, 0.85, 0.85}

-------------------------------------------
-- Builders
-------------------------------------------

local function buildPlayerFrame(data, parent)
    local x, y = LAYOUT.playerX, LAYOUT.playerY
    
    -- Name / Level
    local p = data.player or {}
    local name = p.class or "Tenno"
    local level = (p.level ~= nil) and p.level or 0
    
    local nameText = ui.Text.new({
        x = x, y = y,
        w = LAYOUT.barWidth,
        text = string.upper(name) .. " Lv" .. tostring(level),
        color = HUD_LABEL_COLOR,
        font = theme.getFont('small'),
        align = 'left'
    })
    parent:addChild(nameText)
    widgets.levelText = nameText
    y = y + 14
    
    -- Shield Bar
    widgets.shieldBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 6,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.shieldColor,
        bgColor = {0.1, 0.1, 0.2, 0.5},
        cornerRadius = 1
    })
    parent:addChild(widgets.shieldBar)
    widgets.shieldText = ui.Text.new({
        x = x + 2, y = y - 4,
        w = LAYOUT.barWidth - 4,
        text = "0/0",
        color = HUD_NUM_COLOR,
        font = theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    parent:addChild(widgets.shieldText)
    y = y + 8
    
    -- HP Bar
    widgets.hpBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 10,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.hpColor,
        bgColor = {0.2, 0.1, 0.1, 0.5},
        cornerRadius = 2
    })
    parent:addChild(widgets.hpBar)
    widgets.hpText = ui.Text.new({
        x = x + 2, y = y - 3,
        w = LAYOUT.barWidth - 4,
        text = "0/0",
        color = HUD_NUM_COLOR,
        font = theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    parent:addChild(widgets.hpText)
    y = y + 14
    
    -- XP Bar (Thin line)
    widgets.xpBar = ui.Bar.new({
        x = x, y = y,
        w = LAYOUT.barWidth, h = 2,
        value = 0, maxValue = 100,
        fillColor = LAYOUT.xpColor,
        bgColor = {0,0,0,0}
    })
    parent:addChild(widgets.xpBar)
    widgets.xpText = ui.Text.new({
        x = x + 2, y = y - 7,
        w = LAYOUT.barWidth - 4,
        text = "0/0",
        color = HUD_NUM_COLOR,
        font = theme.getFont('tiny') or theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    parent:addChild(widgets.xpText)
    y = y + 6
    
    -- Dash / Stamina
    local dashLabelW = 46
    widgets.dashText = ui.Text.new({
        x = x, y = y,
        text = "DASH",
        color = HUD_LABEL_COLOR,
        font = theme.getFont('small')
    })
    parent:addChild(widgets.dashText)
    
    widgets.dashBar = ui.Bar.new({
        x = x + dashLabelW, y = y + 2,
        w = 100, h = 4,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.dashColor,
        bgColor = {0.1, 0.1, 0.1, 0.5}
    })
    parent:addChild(widgets.dashBar)
    widgets.dashValue = ui.Text.new({
        x = x + dashLabelW + 2, y = y - 4,
        w = 100 - 4,
        text = "0/0",
        color = HUD_NUM_COLOR,
        font = theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    parent:addChild(widgets.dashValue)
    
    -- Static Charge Bar (Volt only - will be shown/hidden in update)
    y = y + 14
    widgets.staticChargeText = ui.Text.new({
        x = x, y = y,
        text = "STATIC",
        color = HUD_LABEL_COLOR,
        font = theme.getFont('small')
    })
    widgets.staticChargeText.visible = false
    parent:addChild(widgets.staticChargeText)
    
    widgets.staticChargeBar = ui.Bar.new({
        x = x + dashLabelW, y = y + 2,
        w = 94, h = 4,
        value = 0, maxValue = 100,
        fillColor = {0.3, 0.7, 1, 1},
        bgColor = {0.1, 0.1, 0.2, 0.5}
    })
    widgets.staticChargeBar.visible = false
    parent:addChild(widgets.staticChargeBar)
    widgets.staticChargeValue = ui.Text.new({
        x = x + dashLabelW + 2, y = y - 5,
        w = 94 - 4,
        text = "0/100",
        color = HUD_NUM_COLOR,
        font = theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    widgets.staticChargeValue.visible = false
    parent:addChild(widgets.staticChargeValue)
    
    -- Gold display (below frame)
    widgets.goldText = ui.Text.new({
        x = x, y = y + 14,
        text = "GOLD 0",
        color = LAYOUT.goldColor,
        shadow = true,
        font = theme.getFont('small')
    })
    parent:addChild(widgets.goldText)
end

local function buildCombatFrame(parent)
    local endX = LAYOUT.combatX
    local endY = LAYOUT.combatY
    
    -- Ability Slots (1, 2, 3, 4)
    local abilities = {'1', '2', '3', '4'} 
    local slotSize = 40
    local gap = 8
    local totalW = #abilities * slotSize + (#abilities - 1) * gap
    local startX = endX - totalW
    local startY = endY - slotSize
    
    widgets.abilitySlots = {}
    for i, key in ipairs(abilities) do
        local sx = startX + (i-1) * (slotSize + gap)
        
        local slot = ui.Slot.new({
            x = sx, y = startY,
            w = slotSize, h = slotSize,
            content = nil,
            sublabel = key,
            cornerRadius = 4,
            focusable = false
        })

        parent:addChild(slot)
        widgets.abilitySlots[i] = slot -- Keyed by index 1-4
    end
    
    -- Energy Bar (Above abilities)
    local energyY = startY - 10
    widgets.energyBar = ui.Bar.new({
        x = startX, y = energyY,
        w = totalW, h = 4,
        value = 100, maxValue = 100,
        fillColor = LAYOUT.energyColor,
        bgColor = {0.1, 0.1, 0.2, 0.5},
        cornerRadius = 2
    })
    parent:addChild(widgets.energyBar)
    widgets.energyText = ui.Text.new({
        x = startX + 2, y = energyY - 5,
        w = totalW - 4,
        text = "0/0",
        color = HUD_NUM_COLOR,
        font = theme.getFont('small'),
        align = 'right',
        shadow = true
    })
    parent:addChild(widgets.energyText)
    
    -- Weapon Slots (To the left of abilities)
    -- Default: 2 slots (ranged, melee). 3rd slot (extra) is conditional.
    local slotCount = 2  -- Only 2 by default
    local slotW = 90
    local weaponTotalW = slotCount * slotW + (slotCount - 1) * gap
    local weaponStartX = startX - weaponTotalW - 20
    local weaponY = endY - 50 -- Slightly higher
    
    widgets.weaponSlots = {}
    for i = 1, slotCount do
        local wx = weaponStartX + (i-1) * (slotW + gap)
        local slotH = 50
        
        local panel = ui.Panel.new({
            x = wx, y = weaponY,
            w = slotW, h = slotH,
            bgColor = {0.1, 0.1, 0.1, 0.6},
            borderColor = {0.3, 0.3, 0.3, 1},
            borderWidth = 1,
            cornerRadius = 4
        })
        parent:addChild(panel)

        local slotName = (i == 1 and "PRIMARY") or "MELEE"
        local label = ui.Text.new({
            x = 4, y = 2,
            text = (i == 1 and "F") or "E", -- F to cycle, E for quick melee
            color = theme.colors.text_dim,
            font = theme.getFont('small')
        })
        panel:addChild(label)
        
        local name = ui.Text.new({
            x = 16, y = 4, w = 70,
            text = slotName,
            color = theme.colors.text
        })
        panel:addChild(name)
        
        -- Ammo display: horizontal layout
        local ammo = ui.Text.new({
            x = 4, y = 26, w = 82,
            text = "--/--",
            color = theme.colors.text_dim
        })
        panel:addChild(ammo)
        
        -- Reserve display below
        local reserve = ui.Text.new({
            x = 4, y = 38, w = 82,
            text = "",
            color = {0.6, 0.7, 0.8, 0.8},
            font = theme.getFont('small'),
            align = 'left',
            shadow = true
        })
        panel:addChild(reserve)
        
        -- Reload progress bar (overlays the slot when reloading)
        local reloadBar = ui.Bar.new({
            x = 2, y = slotH - 6,
            w = slotW - 4, h = 4,
            value = 0, maxValue = 100,
            fillColor = {0.9, 0.7, 0.2, 1},
            bgColor = {0.2, 0.2, 0.2, 0.8},
            cornerRadius = 1
        })
        reloadBar.visible = false
        panel:addChild(reloadBar)
        
        -- Reload text overlay
        local reloadText = ui.Text.new({
            x = 0, y = 18, w = slotW,
            text = "RELOADING",
            align = 'center',
            color = {1, 0.8, 0.3, 1},
            font = theme.getFont('small'),
            shadow = true
        })
        reloadText.visible = false
        panel:addChild(reloadText)
        
        widgets.weaponSlots[i] = {
            panel = panel,
            name = name,
            ammo = ammo,
            reserve = reserve,
            reloadBar = reloadBar,
            reloadText = reloadText
        }
    end
end

local function buildObjectiveFrame(parent)
    -- Objective panel below the wave/room info (draw.lua shows room at Y=40)
    local panelW = 320
    local panelH = 20
    local panel = ui.Panel.new({
        x = LAYOUT.objX - panelW/2, y = 60,  -- Below wave info
        w = panelW, h = panelH,
        bgColor = {0, 0, 0, 0.4},  -- Slight background for readability
        cornerRadius = 4
    })
    parent:addChild(panel)
    
    widgets.objectiveText = ui.Text.new({
        x = 0, y = 2, w = panelW,
        text = "",
        align = 'center',
        color = {1, 1, 1, 0.9},
        shadow = true,
        font = theme.getFont('small')
    })
    panel:addChild(widgets.objectiveText)
    widgets.objectivePanel = panel
end

-------------------------------------------
-- Public API
-------------------------------------------

function hud.init(gameState)
    hud.rebuild(gameState)
end

function hud.rebuild(gameState)
    root = ui.Widget.new({x = 0, y = 0, w = 640, h = 360})
    root.transparent = true 
    
    -- Make root passthrough (only children can be hit)
    -- This prevents the full-screen HUD root from stealing focus and consuming input
    function root:contains(x, y)
        return false
    end 
    
    local data = hudModel.build(gameState)
    buildPlayerFrame(data, root)
    buildCombatFrame(root)
    buildObjectiveFrame(root)
    
    ui.core.setRoot(root)
end

function hud.update(gameState, dt)
    if not root then return end
    local data = hudModel.build(gameState)

    if gameState and gameState.player then
        local p = data.player or {}

        -- HP/Shield/XP/Energy
        if widgets.hpBar then
            widgets.hpBar.value = p.hp or 0
            widgets.hpBar.maxValue = p.maxHp or 100
        end
        if widgets.hpText then
            local cur = math.floor(p.hp or 0)
            local max = math.floor(p.maxHp or 100)
            widgets.hpText:setText(string.format("%d/%d", cur, max))
        end
        if widgets.shieldBar then
            widgets.shieldBar.value = p.shield or 0
            widgets.shieldBar.maxValue = p.maxShield or 100
        end
        if widgets.shieldText then
            local cur = math.floor(p.shield or 0)
            local max = math.floor(p.maxShield or 100)
            widgets.shieldText:setText(string.format("%d/%d", cur, max))
        end
        if widgets.xpBar then
            widgets.xpBar.value = p.xp or 0
            widgets.xpBar.maxValue = p.xpToNext or 100
        end
        if widgets.xpText then
            local cur = math.floor(p.xp or 0)
            local max = math.floor(p.xpToNext or 100)
            widgets.xpText:setText(string.format("%d/%d", cur, max))
        end
        if widgets.energyBar then
            widgets.energyBar.value = p.energy or 0
            widgets.energyBar.maxValue = p.maxEnergy or 100
        end
        if widgets.energyText then
            local cur = math.floor(p.energy or 0)
            local max = math.floor(p.maxEnergy or 100)
            widgets.energyText:setText(string.format("%d/%d", cur, max))
        end

        -- Level Text
        if widgets.levelText then
            local level = (p.level ~= nil) and p.level or 0
            widgets.levelText:setText(string.upper(p.class or "Tenno") .. " Lv" .. tostring(level))
        end

        -- Gold
        if widgets.goldText then
            widgets.goldText:setText(string.format("GOLD %d", data.resources.gold or 0))
        end

        -- Dash
        if widgets.dashBar then
            local dash = data.dash or {}
            widgets.dashBar.value = dash.totalValue or 0
            widgets.dashBar.maxValue = dash.max or 0
            if widgets.dashValue then
                widgets.dashValue:setText(string.format("%d/%d", dash.current or 0, dash.max or 0))
            end
        end

        -- Static Charge Bar (Volt only)
        if widgets.staticChargeBar and widgets.staticChargeText then
            local static = data.staticCharge or {}
            if static.enabled then
                widgets.staticChargeBar.visible = true
                widgets.staticChargeText.visible = true
                if widgets.staticChargeValue then
                    widgets.staticChargeValue.visible = true
                end
                widgets.staticChargeBar.value = static.current or 0
                widgets.staticChargeBar.maxValue = static.max or 100

                -- Color changes based on charge level
                local charge = static.current or 0
                if charge >= 80 then
                    widgets.staticChargeBar.fillColor = {0.6, 1, 1, 1}
                elseif charge >= 40 then
                    widgets.staticChargeBar.fillColor = {0.4, 0.8, 1, 1}
                else
                    widgets.staticChargeBar.fillColor = {0.3, 0.5, 0.8, 0.8}
                end
                if widgets.staticChargeValue then
                    widgets.staticChargeValue:setText(string.format("%d/100", math.floor(charge)))
                end
            else
                widgets.staticChargeBar.visible = false
                widgets.staticChargeText.visible = false
                if widgets.staticChargeValue then
                    widgets.staticChargeValue.visible = false
                end
            end
        end

        -- Ability Slots (updated for index 1-4, WF-style no-CD system)
        local quickIndex = data.quickAbilityIndex or 1
        for i, slot in pairs(widgets.abilitySlots) do
            local ability = data.abilities and data.abilities[i] or nil
            slot.cooldownRatio = ability and ability.cooldownRatio or 0
            if ability and ability.canUse then
                slot.iconColor = {1, 1, 1, 1}
            else
                slot.iconColor = {0.5, 0.5, 0.5, 0.5}
            end
            slot.quickCast = (i == quickIndex)
            slot.quickLabel = 'Q'
        end

        -- Weapon Slots
        local weaponData = data.weapons or {}
        for i, slotData in pairs(widgets.weaponSlots) do
            local slot = weaponData.slots and weaponData.slots[i] or nil
            if not slot then
                slotData.name:setText("Empty")
                slotData.ammo:setText("")
                if slotData.reserve then
                    slotData.reserve:setText("")
                end
                if slotData.reloadBar then
                    slotData.reloadBar.visible = false
                end
                if slotData.reloadText then
                    slotData.reloadText.visible = false
                end
            else
                if slot.isActive then
                    slotData.panel.borderColor = {0.3, 0.6, 0.9, 1}
                    slotData.panel.bgColor = {0.2, 0.3, 0.5, 0.8}
                else
                    slotData.panel.borderColor = {0.3, 0.3, 0.3, 1}
                    slotData.panel.bgColor = {0.1, 0.1, 0.1, 0.6}
                end

                if slot.hasWeapon then
                    slotData.name:setText(slot.name or "")

                    if slot.isReloading and slotData.reloadBar then
                        local progress = slot.reloadProgress or 0
                        slotData.reloadBar.value = progress * 100
                        slotData.reloadBar.maxValue = 100
                        slotData.reloadBar.visible = true
                        if slotData.reloadText then
                            slotData.reloadText.visible = true
                        end
                        slotData.ammo.color = {0.5, 0.5, 0.5, 0.6}
                    else
                        if slotData.reloadBar then
                            slotData.reloadBar.visible = false
                        end
                        if slotData.reloadText then
                            slotData.reloadText.visible = false
                        end
                        slotData.ammo.color = theme.colors.text_dim
                    end

                    if slot.ammoInfinite then
                        slotData.ammo:setText("∞")
                        if slotData.reserve then
                            slotData.reserve:setText("")
                        end
                    else
                        local mag = slot.mag or 0
                        local maxMag = slot.maxMag or mag
                        slotData.ammo:setText(string.format("%d / %d", mag, maxMag))
                        if slotData.reserve then
                            slotData.reserve:setText(string.format("%d", slot.reserve or 0))
                        end
                    end
                else
                    slotData.name:setText("Empty")
                    slotData.ammo:setText("")
                    if slotData.reserve then
                        slotData.reserve:setText("")
                    end
                    if slotData.reloadBar then
                        slotData.reloadBar.visible = false
                    end
                    if slotData.reloadText then
                        slotData.reloadText.visible = false
                    end
                end
            end
        end
    end
    
    -- Mission Objective (based on rooms mode mission type)
    if widgets.objectiveText and widgets.objectivePanel then
        local obj = data.objective or {}
        local missionType = obj.missionType or 'exterminate'

        if not obj.visible then
            widgets.objectivePanel.visible = false
        else
            widgets.objectivePanel.visible = true
            
            local objText = ""
            local objColor = {1, 1, 1, 0.9}
            
            if missionType == 'exterminate' then
                objText = string.format("歼灭: 消灭所有敌人 (%d)", obj.alive or 0)
                objColor = {1.0, 0.6, 0.5, 1}
            elseif missionType == 'defense' then
                if obj.defenseHasObjective and obj.defenseHpPct then
                    objText = string.format("防御: 保护目标 (HP: %d%%)", obj.defenseHpPct)
                else
                    objText = "防御: 保护目标"
                end
                objColor = {0.5, 0.85, 1.0, 1}
            elseif missionType == 'survival' then
                local remaining = obj.survivalRemaining or 0
                local lifeSupport = obj.lifeSupport or 100
                objText = string.format("生存: %d秒 | 生命支援: %.0f%%", math.ceil(remaining), lifeSupport)
                objColor = {0.5, 1.0, 0.6, 1}
            end
            
            widgets.objectiveText:setText(objText)
            widgets.objectiveText.color = objColor
        end
    end
end
-------------------------------------------
-- draw is handled by ui.draw()
-------------------------------------------

function hud.keypressed(key) return false end

return hud
