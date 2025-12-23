local logger = require('core.logger')
local input = require('core.input')
local weaponTrail = require('render.weapon_trail')  -- 武器拖影系统

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
local QUICK_ABILITY_COUNT = 4

local function getMoveInput()
    return input.getAxis('move_x'), input.getAxis('move_y')
end

-- Check if player is holding attack key (mouse left or J)
local function isAttackKeyDown()
    return input.isDown('fire')
end

-- Get aim direction based on weapon type and current input
function player.getAimDirection(state, weaponDef)
    local p = state.player
    return math.cos(p.aimAngle or 0), math.sin(p.aimAngle or 0), nil
end

local function normalizeQuickAbilityIndex(index)
    local idx = math.floor(tonumber(index) or 1)
    idx = ((idx - 1) % QUICK_ABILITY_COUNT) + 1
    return idx
end

function player.getQuickAbilityIndex(state)
    local p = state.player
    if not p then return 1 end
    p.quickAbilityIndex = normalizeQuickAbilityIndex(p.quickAbilityIndex)
    return p.quickAbilityIndex
end

function player.setQuickAbilityIndex(state, index)
    local p = state.player
    if not p then return 1 end
    p.quickAbilityIndex = normalizeQuickAbilityIndex(index)
    return p.quickAbilityIndex
end

function player.cycleQuickAbility(state, dir)
    local p = state.player
    if not p then return 1 end
    local step = tonumber(dir) or 0
    if step == 0 then
        return player.getQuickAbilityIndex(state)
    end
    step = (step > 0) and 1 or -1
    return player.setQuickAbilityIndex(state, (p.quickAbilityIndex or 1) + step)
end

-- Update firing state
function player.updateFiring(state)
    local p = state.player
    
    -- Manual input tracking (essential for charge weapons that need true key state)
    local manualAttack = isAttackKeyDown()
    p.isFiring = manualAttack

    -- Block firing while sliding (Tactical Rush focus)
    if p.isSliding then
        p.isFiring = false
    end
    
    local activeWeaponInst = state.inventory and state.inventory.weaponSlots and state.inventory.weaponSlots[p.activeSlot]
    local activeWeaponKey = activeWeaponInst and activeWeaponInst.key
    local weaponDef = activeWeaponKey and state.catalog and state.catalog[activeWeaponKey]
    
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
        
        if shouldCharge then 
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
                    local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) * (p.exaltedBladeSpeedMult or 1)
                    melee.swingTimer = HEAVY_SWING_TIME / math.max(0.01, speedMult)
                else
                    -- Light attack
                    melee.attackType = 'light'
                    melee.comboCount = melee.comboCount + 1
                    local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) * (p.exaltedBladeSpeedMult or 1)
                    melee.swingTimer = LIGHT_SWING_TIME / math.max(0.01, speedMult)
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
        
        -- ==================== 挥砍拖影记录 ====================
        local meleeRange = 60  -- 近战攻击范围
        local swingArc = math.pi * 0.8  -- 挥砍弧度 (~145度)
        
        -- 计算当前挥砍角度 (从起始角度到结束角度)
        local totalSwingTime = melee.attackType == 'heavy' and HEAVY_SWING_TIME or LIGHT_SWING_TIME
        local speedMult = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) * (p.exaltedBladeSpeedMult or 1)
        totalSwingTime = totalSwingTime / math.max(0.01, speedMult)
        
        local swingProgress = 1 - (melee.swingTimer / totalSwingTime)
        local baseAngle = p.aimAngle or 0
        local startAngle = baseAngle - swingArc / 2
        local currentAngle = startAngle + swingArc * swingProgress
        
        -- 根据攻击类型设置拖影颜色
        local trailColor = {1, 1, 1}
        if melee.attackType == 'heavy' then
            trailColor = {1, 0.6, 0.3}  -- 重击橙色
        elseif melee.attackType == 'finisher' then
            trailColor = {1, 0.3, 0.3}  -- 终结技红色
        else
            trailColor = {0.8, 0.9, 1}  -- 轻击淡蓝色
        end
        
        weaponTrail.addSlashPoint(p, currentAngle, meleeRange, {
            color = trailColor,
            width = melee.attackType == 'heavy' and 12 or 8,  -- 增粗线宽
            intensity = melee.attackType == 'finisher' and 2.0 or 1.2,  -- 增强强度
        })
        
        if melee.swingTimer <= 0 then
            melee.phase = 'recovery'
            local speedMul = (p.attackSpeedBuffMult or 1) * ((p.stats and p.stats.meleeSpeed) or 1) * (p.exaltedBladeSpeedMult or 1)
            melee.recoveryTimer = RECOVERY_TIME / math.max(0.01, speedMul)
            -- 挥砍结束时清除拖影
            weaponTrail.clearSlash(p)
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
    
    -- Escape from grapple hook (Scorpion)
    if p.grappled then
        p.grappled = false
        p.grappleEnemy = nil
        p.grappleSlowMult = nil
    end

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
    local p = state.player
    local input = require('core.input')
    
    -- Weapon cycling (F key)
    if input.isActionKey(key, 'cycle_weapon') then
        local weapons = require('gameplay.weapons')
        return weapons.cycleSlots(state)
    end

    
    -- Reload (R key)
    if input.isActionKey(key, 'reload') then
        local weapons = require('gameplay.weapons')
        return weapons.startReload(state)
    end
    
    -- Melee (E key)
    if input.isActionKey(key, 'melee') then
        return player.quickMelee(state)
    end
    
    -- Quick cast (Q)
    if input.isActionKey(key, 'quick_cast') then
        local abilities = require('gameplay.abilities')
        return abilities.tryActivate(state, player.getQuickAbilityIndex(state))
    end

    -- Ability keys (1/2/3/4)
    local abilities = require('gameplay.abilities')
    local abilityIndex = abilities.getAbilityForKey(key)
    if not abilityIndex then
        if input.isActionKey(key, 'ability1') then abilityIndex = 1
        elseif input.isActionKey(key, 'ability2') then abilityIndex = 2
        elseif input.isActionKey(key, 'ability3') then abilityIndex = 3
        elseif input.isActionKey(key, 'ability4') then abilityIndex = 4
        end
    end
    if abilityIndex then
        return abilities.tryActivate(state, abilityIndex)
    end
    
    -- M key: Test MOD system
    if input.isActionKey(key, 'debug_mods') then
        local mods = require('systems.mods')
        local inv = state.inventory
        local activeSlot = inv and inv.activeSlot or 'ranged'
        local slotData = inv and inv.weaponSlots and inv.weaponSlots[activeSlot]
        local activeKey = slotData and slotData.key
        mods.equipTestMods(state, 'warframe', nil)
        if activeKey then mods.equipTestMods(state, 'weapons', activeKey) end
        mods.equipTestMods(state, 'companion', nil)
        table.insert(state.texts, {x=state.player.x, y=state.player.y-50, text="MOD已装备!", color={0.6, 0.9, 0.4}, life=2})
        return true
    end
    
    -- Escape key: Return to Arsenal
    if input.isActionKey(key, 'cancel') then
        local arsenal = require('core.arsenal')
        if arsenal.reset then arsenal.reset(state) end
        state.gameState = 'ARSENAL'
        table.insert(state.texts or {}, {x=state.player.x, y=state.player.y-50, text="返回准备界面", color={0.8, 0.8, 1}, life=1.5})
        return true
    end
    
    -- Movement: Bullet Jump / Dash (Space)
    if input.isActionKey(key, 'dodge') then
        local dash = ensureDashState(p)
        if p.isSliding and dash and (dash.charges or 0) > 0 then
            -- Bullet Jump: Consumes 1 charge (Tactical Rush + Space)
            local dx, dy = input.getAxis('move_x'), input.getAxis('move_y')
            if dx == 0 and dy == 0 then dx = p.facing or 1 end
            local len = math.sqrt(dx*dx + dy*dy)
            if len < 0.001 then dx, len = (p.facing or 1), 1 end
            
            dash.charges = dash.charges - 1
            p.bulletJumpTimer = BULLET_JUMP_DURATION
            p.bjDx, p.bjDy = (dx/len), (dy/len)
            
            if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 1.2) end
            p.isSliding = false
            if state.spawnEffect then state.spawnEffect('blast_hit', p.x, p.y, 1.5) end
            return true
        else
            return player.tryDash(state)
        end
    end

    -- Pet Toggle
    if input.isActionKey(key, 'toggle_pet') then
        local pets = require('gameplay.pets')
        return pets.toggleMode(state)
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
    elseif p.slashDashChain and p.slashDashChain.active then
        local chain = p.slashDashChain
        moving = true
        p.isSliding = false
        if p.grappled then
            p.grappled = false
            p.grappleEnemy = nil
            p.grappleSlowMult = nil
        end

        if chain.instance and not chain._calc then
            local ok, calc = pcall(require, 'gameplay.calculator')
            if ok and calc then chain._calc = calc end
        end

        if chain.pauseTimer and chain.pauseTimer > 0 then
            chain.pauseTimer = chain.pauseTimer - dt
            dx, dy = chain.lastDx or 0, chain.lastDy or 0
        else
            local target = chain.targets and chain.targets[chain.index]
            if not target then
                p.slashDashChain = nil
            else
                if (target.health or 0) <= 0 then
                    chain.currentTarget = nil
                    chain.stepTargetX = nil
                    chain.stepTargetY = nil
                    chain.index = chain.index + 1
                    chain.pauseTimer = chain.pause or 0
                    chain.stepTimer = 0
                else
                    if chain.currentTarget ~= target then
                        chain.currentTarget = target
                        chain.stepTargetX = target.x
                        chain.stepTargetY = target.y
                    end
                    local tx = chain.stepTargetX or target.x
                    local ty = chain.stepTargetY or target.y
                    local ddx, ddy = tx - p.x, ty - p.y
                    local dist = math.sqrt(ddx * ddx + ddy * ddy)
                    chain.stepTimer = (chain.stepTimer or 0) + dt
                    local hitRadius = chain.hitRadius or 18
                    if dist <= hitRadius or chain.stepTimer >= (chain.maxStepTime or 0.55) then
                        if world and world.enabled and world.moveCircle then
                            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, ddx, ddy)
                        else
                            p.x, p.y = tx, ty
                        end
                        if ddx ~= 0 then p.facing = (ddx >= 0) and 1 or -1 end
                        if state.spawnDashAfterimage then
                            local face = p.facing or 1
                            state.spawnDashAfterimage(p.x, p.y, face, {alpha = 0.25, duration = 0.22, dirX = ddx, dirY = ddy})
                        end
                        if chain._calc and chain.instance then
                            chain._calc.applyHit(state, target, chain.instance)
                        else
                            target.health = (target.health or 0) - (chain.damage or 0)
                        end
                        if state.spawnEffect then state.spawnEffect('blast_hit', tx, ty, 0.6) end
                        chain.currentTarget = nil
                        chain.stepTargetX = nil
                        chain.stepTargetY = nil
                        chain.index = chain.index + 1
                        chain.pauseTimer = chain.pause or 0
                        chain.stepTimer = 0
                    else
                        local dirX, dirY = ddx / dist, ddy / dist
                        chain.lastDx, chain.lastDy = dirX, dirY
                        dx, dy = dirX, dirY
                        local speed = chain.speed or 700
                        local mx = dirX * speed * dt
                        local my = dirY * speed * dt
                        if world and world.enabled and world.moveCircle then
                            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, mx, my)
                        else
                            p.x = p.x + mx
                            p.y = p.y + my
                        end

                        if state.spawnDashAfterimage then
                            local spacing = 22
                            chain.trailX = chain.trailX or ox
                            chain.trailY = chain.trailY or oy
                            local ax, ay = chain.trailX, chain.trailY
                            local adx, ady = p.x - ax, p.y - ay
                            local adist = math.sqrt(adx * adx + ady * ady)
                            local guard = 0
                            local face = p.facing or 1
                            if dirX > 0 then face = 1 elseif dirX < 0 then face = -1 end
                            while adist >= spacing and guard < 24 do
                                ax = ax + dirX * spacing
                                ay = ay + dirY * spacing
                                state.spawnDashAfterimage(ax, ay, face, {alpha = 0.18, duration = 0.18, dirX = dirX, dirY = dirY})
                                adx = p.x - ax
                                ady = p.y - ay
                                adist = math.sqrt(adx * adx + ady * ady)
                                guard = guard + 1
                            end
                            chain.trailX, chain.trailY = ax, ay
                        end
                    end
                end
            end
        end

        if chain and chain.targets and chain.index > #chain.targets then
            p.slashDashChain = nil
        end
    elseif moving then
        local SLIDE_ENERGY_DRAIN = 5.0 -- Energy per second
        local hasEnergy = (p.energy or 0) > 0
        local isSliding = input.isDown('slide') and p.stats.moveSpeed > 0 and hasEnergy
        
        local speed = (p.stats.moveSpeed or 0) * (p.moveSpeedBuffMult or 1)
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
    
    -- VOLT PASSIVE: Static Discharge - accumulate electric charge while moving
    -- Only for Volt class
    if p.class == 'volt' and p.movedDist > 0 then
        p.staticCharge = p.staticCharge or 0
        local chargeRate = 0.15  -- Charge per pixel moved
        p.staticCharge = math.min(100, p.staticCharge + p.movedDist * chargeRate)
    end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    
    local camX = p.x - sw / 2
    local camY = p.y - sh / 2
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
    local dmgVal = dmg or 0
    local reduced = dmgVal
    if armor > 0 then
        reduced = dmgVal * (300 / (armor + 300))
    end
    local incoming = math.max(1, math.floor(reduced))
    
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



-- Consolidation: player.keypressed and player.useAbility removed to avoid redundancy


-- =============================================================================
-- WF-STYLE QUICK MELEE
-- =============================================================================

-- Quick melee (E key) - temporarily switch to melee, attack, switch back
function player.quickMelee(state)
    local weapons = require('gameplay.weapons')
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

