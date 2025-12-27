-- Mission Result & Statistics Screen
local ui = require('ui')
local theme = ui.theme
local analytics = require('systems.analytics')

local resultScreen = {
    root = nil
}

local state = nil

-- Layout constants
local LAYOUT = {
    screenW = 640,
    screenH = 360,
    headerH = 50,
    sidebarW = 200,
    contentY = 60
}

function resultScreen.init(gameState)
    state = gameState
    resultScreen.rebuild(gameState)
end

function resultScreen.isActive()
    return ui.core.getRoot() == resultScreen.root
end

function resultScreen.rebuild(gameState)
    state = gameState
    local totals = analytics.getTotals()
    local weaponStats = analytics.getWeaponStats()
    local rooms = analytics.getRoomStats()
    local isVictory = (state.gameState == 'GAME_CLEAR')
    
    resultScreen.root = ui.Widget.new({x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH})
    local root = resultScreen.root
    
    -- Background
    local bg = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.screenH,
        bgColor = {0.05, 0.05, 0.07, 0.95}
    })
    root:addChild(bg)
    
    -- Header Bar
    local headerColor = isVictory and {0.1, 0.4, 0.2, 0.8} or {0.4, 0.1, 0.1, 0.8}
    local headerPanel = ui.Panel.new({
        x = 0, y = 0, w = LAYOUT.screenW, h = LAYOUT.headerH,
        bgColor = headerColor
    })
    root:addChild(headerPanel)
    
    local titleText = isVictory and "MISSION SUCCESS" or "MISSION FAILED"
    local title = ui.Text.new({
        x = 0, y = 10, w = LAYOUT.screenW,
        text = titleText,
        color = {1, 1, 1},
        align = 'center',
        font = theme.getFont('title'),
        glow = true
    })
    headerPanel:addChild(title)
    
    -- Content Area
    local mainPanel = ui.Widget.new({x = 20, y = LAYOUT.contentY, w = LAYOUT.screenW - 40, h = 240})
    root:addChild(mainPanel)
    
    -- LEFT: Overall Stats
    local statsPanel = ui.Panel.new({
        x = 0, y = 0, w = 240, h = 220,
        bgColor = {1, 1, 1, 0.05}
    })
    mainPanel:addChild(statsPanel)
    
    local statsTitle = ui.Text.new({
        x = 10, y = 10, w = 220,
        text = "统计总览 (SUMMARY)",
        color = theme.colors.accent,
        font = theme.getFont('default')
    })
    statsPanel:addChild(statsTitle)
    
    local duration = analytics.getDuration()
    local mm = math.floor(duration / 60)
    local ss = math.floor(duration % 60)
    local timeStr = string.format("%02d:%02d", mm, ss)
    
    local accuracy = 0
    if totals.shotsFired > 0 then
        accuracy = (totals.shotsHit / totals.shotsFired) * 100
    end
    
    local lines = {
        { label = "任务时间", value = timeStr },
        { label = "击杀数", value = tostring(totals.kills) },
        { label = "总伤害", value = string.format("%d", totals.damageDealt) },
        { label = "命中率", value = string.format("%.1f%%", accuracy) },
        { label = "受到伤害", value = string.format("%d", totals.damageTaken) },
        { label = "清理房间", value = tostring(#rooms) }
    }
    
    for i, line in ipairs(lines) do
        local ly = 40 + (i - 1) * 25
        local label = ui.Text.new({
            x = 15, y = ly, w = 100,
            text = line.label,
            color = theme.colors.text_dim,
            font = theme.getFont('default')
        })
        statsPanel:addChild(label)
        
        local val = ui.Text.new({
            x = 120, y = ly, w = 100,
            text = line.value,
            color = theme.colors.text,
            align = 'right',
            font = theme.getFont('default')
        })
        statsPanel:addChild(val)
    end
    
    -- RIGHT: Weapon Breakdown
    local weaponPanel = ui.Panel.new({
        x = 250, y = 0, w = 350, h = 220,
        bgColor = {1, 1, 1, 0.05}
    })
    mainPanel:addChild(weaponPanel)
    
    local weaponTitle = ui.Text.new({
        x = 10, y = 10, w = 330,
        text = "武器数据 (WEAPONS)",
        color = theme.colors.accent,
        font = theme.getFont('default')
    })
    weaponPanel:addChild(weaponTitle)
    
    -- List weapons
    local scrollY = 40
    local sortedWeapons = {}
    for key, ws in pairs(weaponStats) do
        table.insert(sortedWeapons, {key = key, dmg = ws.damageDealt, hits = ws.shotsHit, shots = ws.shotsFired})
    end
    table.sort(sortedWeapons, function(a, b) return a.dmg > b.dmg end)
    
    for i, w in ipairs(sortedWeapons) do
        if i > 5 then break end -- Limit to top 5
        local wy = scrollY + (i-1) * 35
        
        local wName = ui.Text.new({
            x = 10, y = wy, w = 100,
            text = (state.catalog[w.key] and state.catalog[w.key].name) or w.key,
            color = theme.colors.text,
            font = theme.getFont('default')
        })
        weaponPanel:addChild(wName)
        
        -- Dmg bar
        local barMaxW = 150
        local barW = (totals.damageDealt > 0) and (w.dmg / totals.damageDealt * barMaxW) or 0
        local bar = ui.Panel.new({
            x = 120, y = wy + 5, w = barW, h = 10,
            bgColor = {0.4, 0.6, 1.0, 0.6}
        })
        weaponPanel:addChild(bar)
        
        local wDmg = ui.Text.new({
            x = 280, y = wy, w = 60,
            text = tostring(math.floor(w.dmg)),
            color = theme.colors.text_dim,
            align = 'right',
            font = theme.getFont('small')
        })
        weaponPanel:addChild(wDmg)
        
        local wAcc = 0
        if w.shots > 0 then wAcc = (w.hits / w.shots) * 100 end
        local wAccText = ui.Text.new({
            x = 120, y = wy + 16, w = 150,
            text = string.format("命中率: %.1f%%", wAcc),
            color = {0.5, 0.5, 0.5},
            font = theme.getFont('tiny')
        })
        weaponPanel:addChild(wAccText)
    end
    
    -- BOTTOM: Rewards
    local rewards = state.victoryRewards or {}
    local hasRewards = isVictory and (rewards.currency or rewards.newModName)
    
    if hasRewards then
        local rewardPanel = ui.Panel.new({
            x = 0, y = 230, w = 600, h = 60,
            bgColor = {1, 0.8, 0, 0.1}
        })
        mainPanel:addChild(rewardPanel)
        
        local rTitle = ui.Text.new({
            x = 10, y = 5, w = 100,
            text = "获得奖励",
            color = theme.colors.gold,
            font = theme.getFont('default')
        })
        rewardPanel:addChild(rTitle)
        
        local rx = 120
        if rewards.currency and rewards.currency > 0 then
            local cText = ui.Text.new({
                x = rx, y = 10, w = 150,
                text = string.format("+%d Credits", rewards.currency),
                color = theme.colors.gold,
                font = theme.getFont('large')
            })
            rewardPanel:addChild(cText)
            rx = rx + 160
        end
        
        if rewards.newModName then
            local mText = ui.Text.new({
                x = rx, y = 10, w = 250,
                text = "New Mod: " .. rewards.newModName,
                color = theme.colors.accent,
                font = theme.getFont('large')
            })
            rewardPanel:addChild(mText)
        end
    end
    
    -- Footer Button (single centered button)
    local btnW, btnH = 200, 40
    
    local hubBtn = ui.Button.new({
        x = (LAYOUT.screenW - btnW) / 2,
        y = 310,
        w = btnW, h = btnH,
        text = "返回基地 (HUB)",
        color = theme.colors.primary
    })
    hubBtn:on('click', function()
        ui.core.setRoot(nil)
        local hub = require('world.hub')
        hub.enterHub(state)
    end)
    root:addChild(hubBtn)

    ui.core.setRoot(root)
end

function resultScreen.keypressed(key)
    if not resultScreen.isActive() then return false end
    
    if key == 'escape' or key == 'return' or key == 'space' then
        ui.core.setRoot(nil)
        local hub = require('world.hub')
        hub.enterHub(state)
        return true
    end
    
    return ui.keypressed(key)
end

return resultScreen
