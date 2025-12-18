local logger = require('logger')
local input = require('input')

local player = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Shield System Constants (WF-style)
local SHIELD_REGEN_DELAY = 3.0    -- Seconds after damage before shield regenerates
local SHIELD_REGEN_RATE = 0.25     -- Fraction of max shield per second
local SHIELD_GATE_DURATION = 0.3   -- Invincibility when shield breaks

-- Movement Constants (WF-style)
local SLIDE_SPEED_MULT = 1.3
local SLIDE_DRAG = 0.98        -- Speed decay during slide if not moving
local BULLET_JUMP_SPEED = 500
local BULLET_JUMP_DURATION = 0.4

local function getMoveInput()
    return input.getAxis('move_x'), input.getAxis('move_y')
end

-- Check if player is holding attack key (mouse left or J)
local function isAttackKeyDown()
    return input.isDown('fire')
end

-- Check if precision aiming mode
local function isPrecisionAimMode()
    return input.isDown('precision_aim')
end

-- Get mouse position in world coordinates
local function getMouseWorldPos(state)
    local mx, my = love.mouse.getPosition()
    local camX = state.camera and state.camera.x or 0
    local camY = state.camera and state.camera.y or 0
    return mx + camX, my + camY
end

-- Get aim direction based on weapon type and current input
function player.getAimDirection(state, weaponDef)
    local p = state.player
    return math.cos(p.aimAngle or 0), math.sin(p.aimAngle or 0), nil
end

-- Update firing state
function player.updateFiring(state)
    local p = state.player
    local profile = state.profile or {}
    
    -- Manual input tracking (essential for charge weapons that need true key state)
    local manualAttack = isAttackKeyDown()
    
    -- Auto-trigger meta item bypasses manual attack requirement
    if profile.autoTrigger then
        p.isFiring = true
    else
        p.isFiring = manualAttack
    end

    -- Block firing while sliding (Tactical Rush focus)
    if p.isSliding then
        p.isFiring = false
    end
    
    -- Track precision aim mode for UI
    p.isPrecisionAim = isPrecisionAimMode()
    
    -- Update sniper aim (Shift held with sniper equipped)
    local activeWeaponInst = state.inventory and state.inventory.weaponSlots and state.inventory.weaponSlots[p.activeSlot]
    local activeWeaponKey = activeWeaponInst and activeWeaponInst.key
    local weaponDef = activeWeaponKey and state.catalog and state.catalog[activeWeaponKey]
    local isSniperMode = weaponDef and weaponDef.sniperMode and p.isPrecisionAim
    
    if isSniperMode then
        local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
        local centerX, centerY = screenW / 2, screenH / 2
        
        if not p.sniperAim.active then
            -- Just entered sniper mode: initialize cursor at MOUSE world position
            local mx, my = getMouseWorldPos(state)
            p.sniperAim.worldX = mx
            p.sniperAim.worldY = my
            -- Set mouse to center for delta tracking
            love.mouse.setPosition(centerX, centerY)
        end
        p.sniperAim.active = true
        
        -- Track mouse delta from center
        local mx, my = love.mouse.getPosition()
        local dx = mx - centerX
        local dy = my - centerY
        
        -- Accumulate movement with sensitivity based on sniper range
        local sensitivity = (weaponDef.sniperRange or 1500) / 300
        p.sniperAim.worldX = p.sniperAim.worldX + dx * sensitivity
        p.sniperAim.worldY = p.sniperAim.worldY + dy * sensitivity
        
        -- Reset mouse to center for continuous tracking
        love.mouse.setPosition(centerX, centerY)
        
        -- Clamp to maximum sniper range from player
        local maxRange = weaponDef.sniperRange or 1500
        local offsetX = p.sniperAim.worldX - p.x
        local offsetY = p.sniperAim.worldY - p.y
        local dist = math.sqrt(offsetX * offsetX + offsetY * offsetY)
        if dist > maxRange then
            local scale = maxRange / dist
            p.sniperAim.worldX = p.x + offsetX * scale
            p.sniperAim.worldY = p.y + offsetY * scale
        end
    else
        p.sniperAim.active = false
    end
    
    -- Update aim direction for UI crosshair
    if p.isPrecisionAim then
        local mx, my = getMouseWorldPos(state)
        p.aimX, p.aimY = mx, my
    else
        p.aimX, p.aimY = nil, nil
    end
    
    -- Reset bow charge if weapon changed or no longer holding a bow
    if p.bowCharge.isCharging and p.bowCharge.weaponKey ~= activeWeaponKey then
        p.bowCharge.isCharging = false
        p.bowCharge.pendingRelease = false
        p.bowCharge.chargeTime = 0
    end

    -- Update bow charge (only for bow weapons)
    -- Update bow charge (only for bow weapons)
    local isBowWeapon = weaponDef and weaponDef.chargeEnabled
    if isBowWeapon then
        local shouldCharge = manualAttack
        local maxCharge = weaponDef.maxChargeTime or 2.0
        
        -- Auto-trigger logic: spam attacks (charge -> immediate release)
        if not manualAttack and profile.autoTrigger and not p.bowCharge.pendingRelease then
            if not p.bowCharge.isCharging then
                 -- Start charge cycle
                 shouldCharge = true
            else
                 -- Already charging? Release immediately for rapid fire (no charge)
                 shouldCharge = false
            end
        end

        if shouldCharge then 
            -- Intercept any pending release (e.g. from auto-trigger) and convert back to charging
            if p.bowCharge.pendingRelease then
                p.bowCharge.pendingRelease = false
                p.bowCharge.isCharging = true
            end

            if not p.bowCharge.isCharging then
                -- Start charging
                p.bowCharge.isCharging = true
                p.bowCharge.pendingRelease = false
                p.bowCharge.startTime = state.gameTimer or 0
                p.bowCharge.chargeTime = 0
                p.bowCharge.weaponKey = activeWeaponKey
            elseif p.bowCharge.isCharging then
                -- Update charge time
                p.bowCharge.chargeTime = (state.gameTimer or 0) - p.bowCharge.startTime
                if p.bowCharge.chargeTime > maxCharge then
                    p.bowCharge.chargeTime = maxCharge
                end
            end
        elseif not shouldCharge and p.bowCharge.isCharging then
            -- Released: mark for firing in next weapon update
            p.bowCharge.pendingRelease = true
            -- Note: We keep isCharging=true until the weapon actually fires (consumes pendingRelease)
            -- This ensures the UI can still show the charge bar until the shot goes off
        end
    end
end

-- Ensure melee state exists
local function ensureMeleeState(p)
    if not p.meleeState then
        p.meleeState = {
            phase = 'idle',      -- idle/windup/swing/recovery
            comboCount = 0,      -- 连击计数 (0-3)
            comboTimer = 0,      -- 连击窗口倒计时
            holdTimer = 0,       -- 按住时间
            isHolding = false,   -- 是否正在按住
            attackType = nil,    -- 'light' / 'heavy' / 'finisher'
            swingTimer = 0,      -- 挥砍动画时间
            recoveryTimer = 0,   -- 后摇时间
            damageDealt = false, -- 本次攻击是否已造成伤害
        }
    end
    return p.meleeState
end

-- Melee attack constants
local HEAVY_HOLD_THRESHOLD = 0.4  -- 长按阈值
local COMBO_WINDOW = 1.2          -- 连击窗口
local LIGHT_SWING_TIME = 0.15     -- 轻击挥砍时间
local HEAVY_SWING_TIME = 0.3      -- 重击挥砍时间
local RECOVERY_TIME = 0.1         -- 后摇时间

-- Update melee attack state machine
function player.updateMelee(state, dt)
    local p = state.player
    if not p then return end
    
    local melee = ensureMeleeState(p)
    -- WF-style: Read from inventory.activeSlot
    local activeSlot = state.inventory and state.inventory.activeSlot or 'ranged'
    
    -- Only process melee when melee slot is active
    if activeSlot ~= 'melee' then
        melee.phase = 'idle'
        melee.holdTimer = 0
        melee.isHolding = false
        return
    end
    
    -- Update combo timer
    if melee.comboTimer > 0 then
        melee.comboTimer = melee.comboTimer - dt
        if melee.comboTimer <= 0 then
            melee.comboCount = 0
            melee.comboTimer = 0
        end
    end

    -- Decay global melee combo (WF-style)
    if p.meleeCombo and p.meleeCombo > 0 then
        p.meleeComboTimer = (p.meleeComboTimer or 0) - dt
        if p.meleeComboTimer <= 0 then
            p.meleeCombo = 0
            p.meleeComboTimer = 0
        end
    end
    
    local attacking = isAttackKeyDown() and not p.isSliding
    
    -- State machine
    if melee.phase == 'idle' then
        if attacking then
            if not melee.isHolding then
                -- Just pressed attack
                melee.isHolding = true
                melee.holdTimer = 0
            else
                -- Holding attack
                melee.holdTimer = melee.holdTimer + dt
            end
        else
            if melee.isHolding then
                -- Released attack - determine type
                melee.isHolding = false
                
                if melee.holdTimer >= HEAVY_HOLD_THRESHOLD then
                    -- Heavy attack
                    if melee.comboCount >= 3 then
                        melee.attackType = 'finisher'
                        melee.comboCount = 0
                    else
                        melee.attackType = 'heavy'
                    end
                    melee.swingTimer = HEAVY_SWING_TIME
                else
                    -- Light attack
                    melee.attackType = 'light'
                    melee.comboCount = melee.comboCount + 1
                    melee.swingTimer = LIGHT_SWING_TIME
                end
                
                melee.phase = 'swing'
                melee.damageDealt = false
                melee.comboTimer = COMBO_WINDOW
                melee.holdTimer = 0
                
                -- Sound
                if state.playSfx then state.playSfx('shoot') end
            end
        end
        
    elseif melee.phase == 'swing' then
        melee.swingTimer = melee.swingTimer - dt
        if melee.swingTimer <= 0 then
            melee.phase = 'recovery'
            melee.recoveryTimer = RECOVERY_TIME
        end
        
    elseif melee.phase == 'recovery' then
        melee.recoveryTimer = melee.recoveryTimer - dt
        if melee.recoveryTimer <= 0 then
            melee.phase = 'idle'
            melee.attackType = nil
        end
    end
end

-- Cancel melee for dodge
function player.cancelMelee(state)
    local p = state.player
    if not p or not p.meleeState then return end
    local melee = p.meleeState
    if melee.phase ~= 'idle' then
        melee.phase = 'idle'
        melee.attackType = nil
        melee.swingTimer = 0
        melee.recoveryTimer = 0
        melee.isHolding = false
        melee.holdTimer = 0
    end
end

local function ensureDashState(p)
    if not p then return nil end
    p.dash = p.dash or {}

    local stats = p.stats or {}
    local maxCharges = math.max(0, math.floor(stats.dashCharges or 0))
    local prevMax = p.dash.maxCharges
    p.dash.maxCharges = maxCharges

    if p.dash.charges == nil then
        p.dash.charges = maxCharges
    else
        if prevMax and maxCharges > prevMax then
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0) + (maxCharges - prevMax))
        else
            p.dash.charges = math.min(maxCharges, (p.dash.charges or 0))
        end
    end

    p.dash.rechargeTimer = p.dash.rechargeTimer or 0
    p.dash.timer = p.dash.timer or 0
    p.dash.dx = p.dash.dx or (p.facing or 1)
    p.dash.dy = p.dash.dy or 0

    return p.dash
end

local function tickDashRecharge(p, dt)
    local dash = ensureDashState(p)
    if not dash then return end
    local maxCharges = dash.maxCharges or 0
    if maxCharges <= 0 then return end
    dash.charges = dash.charges or 0

    if dash.charges >= maxCharges then
        dash.rechargeTimer = 0
        return
    end

    local cd = (p.stats and p.stats.dashCooldown) or 0
    if cd <= 0 then
        dash.charges = maxCharges
        dash.rechargeTimer = 0
        return
    end

    local rechargeDt = dt
    if p.isSliding then
        -- Tactical Rush (Slide) doubles dash recharge speed
        rechargeDt = rechargeDt * 2
    end

    dash.rechargeTimer = (dash.rechargeTimer or 0) + rechargeDt
    while dash.rechargeTimer >= cd and dash.charges < maxCharges do
        dash.rechargeTimer = dash.rechargeTimer - cd
        dash.charges = dash.charges + 1
    end
end

function player.tryDash(state, dirX, dirY)
    if not state or not state.player then return false end
    local p = state.player

    -- Cancel melee attack on dash (Hades-style responsiveness)
    player.cancelMelee(state)

    local dash = ensureDashState(p)
    if not dash or (dash.maxCharges or 0) <= 0 then return false end
    if (dash.timer or 0) > 0 then return false end
    if (dash.charges or 0) <= 0 then return false end

    local dx, dy = dirX, dirY
    if dx == nil or dy == nil then
        dx, dy = getMoveInput()
    end
    if dx == 0 and dy == 0 then
        dx, dy = (p.facing or 1), 0
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return false end
    dx, dy = dx / len, dy / len

    local stats = p.stats or {}
    local duration = stats.dashDuration or 0
    local distance = stats.dashDistance or 0
    local inv = stats.dashInvincible
    if inv == nil then inv = duration end

    local ctx = {
        player = p,
        dirX = dx,
        dirY = dy,
        duration = duration,
        distance = distance,
        invincibleTimer = inv
    }
    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preDash', ctx)
        if ctx.cancel then return false end
    end

    dx, dy = ctx.dirX or dx, ctx.dirY or dy
    local len2 = math.sqrt(dx * dx + dy * dy)
    if len2 <= 0 then
        dx, dy = (p.facing or 1), 0
    else
        dx, dy = dx / len2, dy / len2
    end

    duration = ctx.duration or duration
    distance = ctx.distance or distance
    inv = ctx.invincibleTimer
    if inv == nil then inv = duration end

    if duration <= 0 or distance <= 0 then return false end

    dash.charges = math.max(0, (dash.charges or 0) - 1)
    dash.duration = duration
    dash.distance = distance
    dash.speed = distance / duration
    dash.timer = duration
    dash.dx = dx
    dash.dy = dy
    dash.trailX = p.x
    dash.trailY = p.y
    if state.spawnDashAfterimage then
        local face = p.facing or 1
        if dx > 0 then face = 1 elseif dx < 0 then face = -1 end
        state.spawnDashAfterimage(p.x, p.y, face, {alpha = 0.26, duration = 0.20, dirX = dx, dirY = dy})
    end

    if inv and inv > 0 then
        p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
    end
    if state.spawnEffect then
        state.spawnEffect('shock', p.x, p.y, 0.9)
    end

    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onDash', ctx)
    end

    -- Cancel any active reloads when dashing (WF-style)
    local inv = state.inventory
    if inv and inv.weapons then
        for key, w in pairs(inv.weapons) do
            if w.isReloading then
                w.isReloading = false
                w.reloadTimer = 0
            end
        end
    end

    return true
end

-- Switch active weapon slot (1=ranged, 2=melee)
function player.switchWeaponSlot(state, slot)
    if not state or not state.player then return false end
    local validSlots = {ranged = true, melee = true}
    if not validSlots[slot] then return false end
    
    local p = state.player
    local oldSlot = p.activeSlot
    if oldSlot == slot then return false end -- Already on this slot
    
    p.activeSlot = slot
    
    -- Visual/audio feedback
    if state.playSfx then state.playSfx('shoot') end
    
    -- Trigger switch event for augments
    if state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onWeaponSwitch', {
            oldSlot = oldSlot, newSlot = slot
        })
    end
    
    return true
end

function player.keypressed(state, key)
    if not state or state.gameState ~= 'PLAYING' then return false end
    
    -- Weapon slot switching (1=ranged, 2=melee for 2-slot system)
    if key == '1' then return player.switchWeaponSlot(state, 'ranged') end
    if key == '2' then return player.switchWeaponSlot(state, 'melee') end
    
    -- Reload (R key)
    if key == 'r' then
        local weapons = require('weapons')
        return weapons.startReload(state)
    end
    
    -- Ability keys (Q/E/C/V)
    local abilities = require('abilities')
    local abilityKey = abilities.getAbilityForKey(key)
    if abilityKey then
        return abilities.tryActivate(state, abilityKey)
    end
    
    -- M key: Test MOD system (all categories)
    if key == 'm' then
        local mods = require('mods')
        local inv = state.inventory
        local activeSlot = inv and inv.activeSlot or 'ranged'
        local slotData = inv and inv.weaponSlots and inv.weaponSlots[activeSlot]
        local activeKey = slotData and slotData.key
        
        -- Equip test mods for all categories
        mods.equipTestMods(state, 'warframe', nil)
        if activeKey then
            mods.equipTestMods(state, 'weapons', activeKey)
        end
        mods.equipTestMods(state, 'companion', nil)
        
        table.insert(state.texts, {x=state.player.x, y=state.player.y-50, text="MOD已装备!", color={0.6, 0.9, 0.4}, life=2})
        table.insert(state.texts, {x=state.player.x, y=state.player.y-70, text="角色+武器+宠物", color={0.8, 0.8, 1}, life=2})
        return true
    end
    
    -- Escape key: Return to Arsenal (prep screen)
    if key == 'escape' then
        local arsenal = require('arsenal')
        if arsenal.reset then
            arsenal.reset(state)
        end
        state.gameState = 'ARSENAL'
        table.insert(state.texts or {}, {x=state.player.x, y=state.player.y-50, text="返回准备界面", color={0.8, 0.8, 1}, life=1.5})
        return true
    end
    
    if key == 'space' then
        return player.tryDash(state)
    end
    return false
end

function player.updateMovement(state, dt)
    local p = state.player
    local ox, oy = p.x, p.y

    local dash = ensureDashState(p)
    tickDashRecharge(p, dt)

    local dx, dy = getMoveInput()
    local moving = dx ~= 0 or dy ~= 0
    local world = state.world

    -- Handle Advanced Movement Timers
    if (p.bulletJumpTimer or 0) > 0 then
        p.bulletJumpTimer = p.bulletJumpTimer - dt
        local mx = (p.bjDx or 0) * BULLET_JUMP_SPEED * dt
        local my = (p.bjDy or 0) * BULLET_JUMP_SPEED * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x, p.y = p.x + mx, p.y + my
        end
        moving = true
    elseif dash and (dash.timer or 0) > 0 then
        local speed = dash.speed
        if speed == nil then
            local stats = p.stats or {}
            local duration = stats.dashDuration or 0
            local distance = stats.dashDistance or 0
            speed = (duration > 0) and (distance / duration) or 0
        end

        local mx = (dash.dx or 0) * speed * dt
        local my = (dash.dy or 0) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
        dash.timer = dash.timer - dt
        if dash.timer < 0 then dash.timer = 0 end
        moving = true
        dx, dy = dash.dx or 0, dash.dy or 0

        if state.spawnDashAfterimage then
            local spacing = 24
            dash.trailX = dash.trailX or ox
            dash.trailY = dash.trailY or oy
            local tx, ty = dash.trailX, dash.trailY
            local dirX, dirY = dash.dx or 0, dash.dy or 0
            local face = p.facing or 1
            if dirX > 0 then face = 1 elseif dirX < 0 then face = -1 end
            local ddx = p.x - tx
            local ddy = p.y - ty
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            local guard = 0
            while dist >= spacing and guard < 32 do
                tx = tx + dirX * spacing
                ty = ty + dirY * spacing
                state.spawnDashAfterimage(tx, ty, face, {alpha = 0.20, duration = 0.20, dirX = dirX, dirY = dirY})
                ddx = p.x - tx
                ddy = p.y - ty
                dist = math.sqrt(ddx * ddx + ddy * ddy)
                guard = guard + 1
            end
            dash.trailX, dash.trailY = tx, ty
        end

        if dash.timer <= 0 and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'postDash', {player = p})
        end
    elseif moving then
        local SLIDE_ENERGY_DRAIN = 5.0 -- Energy per second
        local hasEnergy = (p.energy or 0) > 0
        local isSliding = input.isDown('slide') and p.stats.moveSpeed > 0 and hasEnergy
        
        local speed = p.stats.moveSpeed
        if isSliding then
            -- Drain energy over time
            p.energy = math.max(0, p.energy - SLIDE_ENERGY_DRAIN * dt)
            
            speed = speed * SLIDE_SPEED_MULT
            p.isSliding = true
            -- 专注闪避状态 (Focus evasion): no size reduction, just speed + DR (in hurt)
            if state.spawnDashAfterimage and math.random() < 0.2 then
                state.spawnDashAfterimage(p.x, p.y, p.facing, {alpha=0.1, duration=0.3})
            end
        else
            p.isSliding = false
        end
        local len = math.sqrt(dx * dx + dy * dy)
        local mx = (dx / len) * speed * dt
        local my = (dy / len) * speed * dt
        if world and world.enabled and world.moveCircle then
            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
        else
            p.x = p.x + mx
            p.y = p.y + my
        end
    else
        p.isSliding = false
        p.size = 20
    end

    if dash and (dash.timer or 0) <= 0 then
        dash.trailX = nil
        dash.trailY = nil
    end

    -- Update Aim Angle (360 degrees towards mouse)
    p.aimAngle = input.getAimAngle(state, p.x, p.y)

    -- Decouple facing from movement if attacking or using abilities
    local isAttacking = input.isDown('fire') or (p.meleeState and p.meleeState.phase ~= 'idle')
    if isAttacking then
        -- Face the crosshair/mouse
        p.facing = (math.cos(p.aimAngle) >= 0) and 1 or -1
    elseif dx ~= 0 then
        -- Standard movement facing
        p.facing = (dx > 0) and 1 or -1
    end
    p.isMoving = moving
    local mdx, mdy = p.x - ox, p.y - oy
    p.movedDist = math.sqrt(mdx * mdx + mdy * mdy)

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- Camera target: sniper aim point if active, otherwise player
    local camTargetX, camTargetY = p.x, p.y
    if p.sniperAim and p.sniperAim.active then
        -- Blend camera between player and sniper aim point (70% towards aim)
        local aimX, aimY = p.sniperAim.worldX, p.sniperAim.worldY
        camTargetX = p.x * 0.3 + aimX * 0.7
        camTargetY = p.y * 0.3 + aimY * 0.7
    end
    
    local camX = camTargetX - sw / 2
    local camY = camTargetY - sh / 2
    if world and world.enabled and world.pixelW and world.pixelH then
        local maxCamX = math.max(0, world.pixelW - sw)
        local maxCamY = math.max(0, world.pixelH - sh)
        camX = clamp(camX, 0, maxCamX)
        camY = clamp(camY, 0, maxCamY)
    end
    state.camera.x = camX
    state.camera.y = camY
end

function player.hurt(state, dmg)
    local p = state.player
    if state.benchmarkMode then return end -- invincible during benchmark/debug runs
    if p.invincibleTimer > 0 then return end
    
    local armor = (p.stats and p.stats.armor) or 0
    local hpBefore = p.hp
    local shieldBefore = p.shield or 0
    local incoming = math.max(1, math.floor((dmg or 0) - armor))
    
    local ctx = {
        amount = incoming,
        dmg = dmg or 0,
        armor = armor,
        hpBefore = hpBefore,
        shieldBefore = shieldBefore,
        hpAfter = hpBefore,
        shieldAfter = shieldBefore,
        player = p,
        isMoving = p.isMoving or false,
        movedDist = p.movedDist or 0
    }
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'preHurt', ctx)
    end
    incoming = math.max(0, math.floor(ctx.amount or incoming))
    if ctx.cancel or incoming <= 0 then
        local inv = ctx.invincibleTimer or 0
        if inv > 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, inv)
        end
        ctx.amount = 0
        ctx.hpAfter = p.hp
        ctx.shieldAfter = p.shield or 0
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'hurtCancelled', ctx)
        end
        return
    end
    
    -- Reset shield regeneration delay
    p.shieldDelayTimer = 0
    
    local shieldDamage = 0
    local healthDamage = 0
    local remaining = incoming
    
    -- Special Evasion: Tactical Rush (Slide) Damage Reduction
    if p.isSliding then
        local SLIDE_DR = 0.30 -- 30% Damage Reduction
        remaining = math.floor(remaining * (1 - SLIDE_DR))
    end
    
    -- Damage shields first (WF-style)
    if (p.shield or 0) > 0 then
        shieldDamage = math.min(p.shield, remaining)
        p.shield = p.shield - shieldDamage
        remaining = remaining - shieldDamage
        
        -- Shield Gating: if shield broke, grant brief invincibility
        if shieldDamage > 0 and (p.shield or 0) <= 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, SHIELD_GATE_DURATION)
            remaining = 0  -- Absorb remaining damage during gate
            if state.texts then
                table.insert(state.texts, {x=p.x, y=p.y-50, text="SHIELD GATE!", color={0.4, 0.8, 1}, life=0.8})
            end
        end
    end
    
    -- Apply remaining damage to health
    if remaining > 0 then
        healthDamage = remaining
        p.hp = math.max(0, p.hp - healthDamage)
    end
    
    local applied = shieldDamage + healthDamage
    ctx.amount = applied
    ctx.shieldDamage = shieldDamage
    ctx.healthDamage = healthDamage
    ctx.hpAfter = p.hp
    ctx.shieldAfter = p.shield or 0
    
    if applied > 0 then
        if state and state.augments and state.augments.dispatch then
            state.augments.dispatch(state, 'onHurt', ctx)
            state.augments.dispatch(state, 'postHurt', ctx)
        end
    end
    
    logger.damageTaken(state, applied, p.hp)
    if p.hp <= 0 then
        p.invincibleTimer = 0
        state.shakeAmount = 0
        state.gameState = 'GAME_OVER'
        if state.stopMusic then state.stopMusic() end
        logger.gameOver(state, 'death')
    else
        if healthDamage > 0 then
            p.invincibleTimer = math.max(p.invincibleTimer or 0, 0.5)
        end
        state.shakeAmount = 5
    end
    if state.playSfx then state.playSfx('hit') end
    
    -- Show damage text with color based on type
    local textColor = {1, 0, 0}  -- Red for health damage
    if shieldDamage > 0 and healthDamage == 0 then
        textColor = {0.4, 0.7, 1}  -- Blue for shield-only damage
    end
    table.insert(state.texts, {x=p.x, y=p.y-30, text="-"..applied, color=textColor, life=1})
end

function player.tickInvincibility(state, dt)
    if state.player.invincibleTimer > 0 then
        state.player.invincibleTimer = state.player.invincibleTimer - dt
        if state.player.invincibleTimer < 0 then state.player.invincibleTimer = 0 end
    end
end

function player.tickRegen(state, dt)
    local p = state.player
    local regen = p.stats.regen or 0
    if regen > 0 and p.hp < p.maxHp then
        p.hp = math.min(p.maxHp, p.hp + regen * dt)
    end
end

-- Shield Regeneration (WF-style)
function player.tickShields(state, dt)
    local p = state.player
    if not p then return end
    
    local maxShield = (p.stats and p.stats.maxShield) or p.maxShield or 0
    if maxShield <= 0 then return end
    
    -- Update shield delay timer
    p.shieldDelayTimer = (p.shieldDelayTimer or 0) + dt
    
    -- Regenerate shields after delay
    if p.shieldDelayTimer >= SHIELD_REGEN_DELAY and (p.shield or 0) < maxShield then
        local regen = maxShield * SHIELD_REGEN_RATE * dt
        p.shield = math.min(maxShield, (p.shield or 0) + regen)
    end
end

function player.tickTexts(state, dt)
    for i = #state.texts, 1, -1 do
        local t = state.texts[i]
        t.life = t.life - dt
        local speed = t.floatSpeed or 30
        t.y = t.y - speed * dt
        if t.life <= 0 then table.remove(state.texts, i) end
    end
end

-- Update ability cooldown tick
function player.updateAbility(state, dt)
    local p = state.player
    local ability = p.ability
    if not ability then
        p.ability = {cooldown = 0, timer = 0}
        ability = p.ability
    end
    
    if (ability.timer or 0) > 0 then
        ability.timer = ability.timer - dt
        if ability.timer < 0 then ability.timer = 0 end
    end
end

-- Use class ability (indexed 1-4)
function player.useAbility(state, index)
    local p = state.player
    index = index or 1
    
    local abilities = require('abilities')
    local def = abilities.getAbilityDef(state, index)
    if not def then return false end
    
    -- Check energy and cooldown
    p.abilityCooldowns = p.abilityCooldowns or {}
    local cd = p.abilityCooldowns[index] or 0
    if cd > 0 then return false end
    
    local eff = p.stats and p.stats.abilityEfficiency or 1.0
    local cost = math.floor(def.cost / eff)
    if (p.energy or 0) < cost then
        if state.texts then
            table.insert(state.texts, {x=p.x, y=p.y-40, text="能量不足!", color={1,0,0}, life=0.5})
        end
        return false
    end
    
    -- Execute ability
    local success = def.effect(state)
    
    -- Set cooldown and consume energy if successful
    if success then
        p.energy = p.energy - cost
        p.abilityCooldowns[index] = def.cd or 5.0
        if state.texts then
            table.insert(state.texts, {x=p.x, y=p.y-60, text=def.name, color={0.5, 1, 1}, life=1.0})
        end
    end
    
    return success
end

function player.keypressed(state, key)
    local p = state.player
    
    
    -- Movement: Bullet Jump / Dash (Space)
    if input.isActionKey(key, 'jump') then
        local dash = ensureDashState(p)
        if p.isSliding and dash and (dash.charges or 0) > 0 then
            -- Bullet Jump: Consumes 1 charge (Tactical Rush + Space)
            local dx, dy = input.getAxis('move_x'), input.getAxis('move_y')
            if dx == 0 and dy == 0 then dx = p.facing or 1 end
            local len = math.sqrt(dx*dx + dy*dy)
            
            dash.charges = dash.charges - 1
            p.bulletJumpTimer = BULLET_JUMP_DURATION
            p.bjDx, p.bjDy = (dx/len), (dy/len)
            
            if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.2) end
            p.isSliding = false
            if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 1.5) end
            return true
        else
            -- Standard Dash (Space) or failed Bullet Jump fallback
            return player.tryDash(state)
        end
    end
    
    -- Escape key: Return to Arsenal
    if input.isActionKey(key, 'cancel') then
        local arsenal = require('arsenal')
        if arsenal.reset then arsenal.reset(state) end
        state.gameState = 'ARSENAL'
        table.insert(state.texts or {}, {x=state.player.x, y=state.player.y-50, text="返回准备界面", color={0.8, 0.8, 1}, life=1.5})
        return true
    end
    
    -- Abilities: 1, 2, 3, 4
    if input.isActionKey(key, 'ability1') then player.useAbility(state, 1) return true end
    if input.isActionKey(key, 'ability2') then player.useAbility(state, 2) return true end
    if input.isActionKey(key, 'ability3') then player.useAbility(state, 3) return true end
    if input.isActionKey(key, 'ability4') then player.useAbility(state, 4) return true end
    
    -- Weapons: Cycle, Quick Melee, Reload
    if input.isActionKey(key, 'cycle_weapon') then
        local weapons = require('weapons')
        weapons.cycleSlots(state)
        return true
    end
    if input.isActionKey(key, 'melee') then
        player.quickMelee(state)
        return true
    end
    if input.isActionKey(key, 'reload') then
        local weapons = require('weapons')
        weapons.startReload(state)
        return true
    end

    -- Pets
    if input.isActionKey(key, 'toggle_pet') then
        local pets = require('pets')
        pets.toggleMode(state)
        return true
    end
    
    -- Debug: M key to equip test MODs
    if input.isActionKey(key, 'debug_mods') then
        local mods = require('mods')
        local inv = state.inventory
        local activeSlot = inv and inv.activeSlot or 'ranged'
        local slotData = inv and inv.weaponSlots and inv.weaponSlots[activeSlot]
        local activeKey = slotData and slotData.key
        
        mods.equipTestMods(state, 'warframe', nil)
        if activeKey then
            mods.equipTestMods(state, 'weapons', activeKey)
        end
        mods.equipTestMods(state, 'companion', nil)
        
        if state.texts then
            table.insert(state.texts, {x=p.x, y=p.y-50, text="MODs RESTORED (Debug)", color={0.6, 0.9, 0.4}, life=2})
        end
        return true
    end
    
    return false
end

-- =============================================================================
-- WF-STYLE QUICK MELEE
-- =============================================================================

-- Quick melee (E key) - temporarily switch to melee, attack, switch back
function player.quickMelee(state)
    local weapons = require('weapons')
    local inv = state.inventory
    
    -- Check if melee weapon equipped
    if not inv.weaponSlots.melee then
        return false
    end
    
    -- Store previous slot to return to
    local prevSlot = inv.activeSlot
    if prevSlot == 'melee' then
        -- Already in melee mode, just trigger attack
        player.triggerMelee(state)
        return true
    end
    
    -- Switch to melee
    inv.activeSlot = 'melee'
    
    -- Set flag to return to previous slot after melee finishes
    state.player.quickMeleeReturn = prevSlot
    
    -- Trigger melee attack
    player.triggerMelee(state)
    
    return true
end

-- Helper to trigger melee attack (used by quickMelee and regular melee)
function player.triggerMelee(state)
    local p = state.player
    -- Initialize melee state if not present
    if not p.melee then
        p.melee = {state = 'ready', timer = 0}
    end
    -- Start melee attack if not already attacking
    if p.melee.state == 'ready' or p.melee.state == 'cooldown' then
        p.melee.state = 'anticipating'
        p.melee.timer = 0
    end
end

return player

