local player = require('gameplay.player')
local enemyDefs = require('data.defs.enemies')
local logger = require('core.logger')
local pets = require('gameplay.pets')
local dropRates = require('data.defs.drop_rates')
local status = require('gameplay.status')

-- 引入子模块
local enemyAI = require('gameplay.enemies.ai')
local enemyLoot = require('gameplay.enemies.loot')
local enemyAttacks = require('gameplay.enemies.attacks')

local enemies = {}

local SHIELD_REGEN_DELAY = 2.5
local SHIELD_REGEN_RATE = 0.25 -- fraction of max shield per second

--------------------------------------------------------------------------------
-- AI 状态机常量与辅助函数（使用子模块）
--------------------------------------------------------------------------------

-- AI 状态常量（从子模块导出，保持向后兼容）
local AI_STATES = enemyAI.STATES

-- 使用子模块的函数
local getAIBehavior = enemyAI.getBehavior
local setAIState = enemyAI.setState
local shouldRetreat = enemyAI.shouldRetreat
local shouldKite = enemyAI.shouldKite
local shouldBerserk = enemyAI.shouldBerserk

-- 攻击系统工具函数（从子模块导出）
local chooseWeighted = enemyAttacks.chooseWeighted

--------------------------------------------------------------------------------

local _calculator = nil
local function getCalculator()
    if _calculator then return _calculator end
    _calculator = require('gameplay.calculator')
    return _calculator
end

local function buildDamageModsForTicks(e)
    return status.buildDamageModsForTicks(e)
end

local function applyDotTick(state, e, dmgType, amount, extraOpts)
    if not e or not state or not amount or amount <= 0 then return end
    local calc = getCalculator()
    if not calc then
        enemies.damageEnemy(state, e, amount, false, 0, false, extraOpts)
        return
    end
    local opts = buildDamageModsForTicks(e)
    for k, v in pairs(extraOpts or {}) do opts[k] = v end
    local key = string.upper(dmgType or '')
    local instance = calc.createInstance({
        damage = amount,
        elements = {key},
        damageBreakdown = {[key] = 1},
        critChance = 0,
        critMultiplier = 1.0,
        statusChance = 0,
        weaponTags = {'dot'}
    })
    calc.applyDamage(state, e, instance, opts)
end

local function getPunctureReduction(e)
    return status.getPunctureReduction(e)
end

local function getBlastReduction(e)
    return status.getBlastReduction(e)
end

local function ensureStatus(e)
    status.ensureStatus(e)
end

local function getEffectiveArmor(e)
    return status.getEffectiveArmor(e)
end

local function applyArmorReduction(dmg, armor)
    if not armor or armor <= 0 then return dmg end
    local dr = armor / (armor + 300)
    return dmg * (1 - dr)
end

local function clamp(x, lo, hi)
    if x == nil then return lo end
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end


function enemies.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
    status.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
end

function enemies.spawnEnemy(state, type, isElite, spawnX, spawnY, opts)
    opts = opts or {}
    local def = enemyDefs[type] or enemyDefs.skeleton
    local color = def.color and {def.color[1], def.color[2], def.color[3]} or {1,1,1}
    local hp = def.hp
    local shield = def.shield or 0
    local armor = def.armor or 0
    local size = def.size
    local visualSize = def.visualSize or size  -- 视觉大小，默认等于碰撞箱大小
    local speed = def.speed

    local eliteMod = nil
    local eliteDamageMult = 1
    local eliteWindupMult = 1
    local eliteBulletSpeedMult = 1
    local shieldRegenDelay = nil
    local shieldRegenRate = nil

    local tenacity = clamp(def.tenacity or 0, 0, 0.95)
    local hardCcImmune = def.hardCcImmune or false
    if def.isBoss then
        tenacity = math.max(tenacity, 0.85)
        hardCcImmune = (def.hardCcImmune ~= false)
    end

    local shootInterval = def.shootInterval
    local bulletSpeed = def.bulletSpeed
    local bulletDamage = def.bulletDamage
    local bulletLife = def.bulletLife
    local bulletSize = def.bulletSize

    local ang = math.random() * 6.28
    local d = def.spawnDistance or 500
    local x = spawnX or (state.player.x + math.cos(ang) * d)
    local y = spawnY or (state.player.y + math.sin(ang) * d)

    local world = state.world
    if world and world.enabled then
        if spawnX == nil and spawnY == nil then
            local ts = world.tileSize or 32
            local maxCells = math.max(8, math.floor(d / ts))
            local minCells = math.max(6, maxCells - 4)
            x, y = world:sampleSpawn(state.player.x, state.player.y, minCells, maxCells, 42)
        end
        x, y = world:adjustToWalkable(x, y, 16)
    end


    -- Scaling: time + room-based progression
    local timeScale = 1 + math.min((state.gameTimer or 0), 300) / 300  -- up to 2x in 5 min
    local roomIndex = (state.rooms and state.rooms.roomIndex) or 0
    local roomScale = 1 + roomIndex * 0.25  -- 25% per room
    local combinedScale = math.max(timeScale, roomScale)  -- use whichever is higher
    
    hp = hp * combinedScale
    shield = shield * combinedScale

    if isElite then
        hp = hp * 5
        shield = shield * 5
        size = size * 1.25  -- 精英怪碰撞箱放大1.25倍
        visualSize = visualSize * 1.5  -- 精英怪视觉大小放大1.5倍（更显眼）
        tenacity = math.max(tenacity, 0.15)

        -- 使用权重随机选择精英类型
        local mods = {
            {key = 'swift', w = 3},
            {key = 'brutal', w = 3},
            {key = 'shielded', w = 2},
            {key = 'armored', w = 2}
        }
        local pick = chooseWeighted(mods)
        eliteMod = pick and pick.key or 'brutal'
        
        -- 根据精英类型应用效果
        if eliteMod == 'swift' then
            speed = speed * 1.6
            eliteBulletSpeedMult = 1.3
            color = {0.5, 1.0, 0.5}  -- 绿色 - 快速
        elseif eliteMod == 'brutal' then
            eliteDamageMult = 1.35 * (1 + roomIndex * 0.1)
            color = {1.0, 0.25, 0.15}  -- 红色 - 高伤
        elseif eliteMod == 'shielded' then
            shield = shield * 2.5
            color = {0.4, 0.85, 1.0}  -- 蓝色 - 护盾
        elseif eliteMod == 'armored' then
            armor = armor + 150
            color = {1.0, 0.7, 0.15}  -- 金色 - 护甲
        end
    end

    tenacity = clamp(tenacity, 0, 0.95)

    table.insert(state.enemies, {
        x = x,
        y = y,
        hp = hp,
        health = hp,
        maxHealth = hp,
        shield = shield,
        maxShield = shield,
        armor = armor,
        healthType = def.healthType or 'FLESH',
        shieldType = def.shieldType or (shield > 0 and 'SHIELD' or nil),
        armorType = def.armorType or (armor > 0 and 'FERRITE_ARMOR' or nil),
        noContactDamage = def.noContactDamage,
        noDrops = def.noDrops,
        isDummy = def.isDummy,
        speed = speed,
        color = color,
        size = size,  -- 碰撞箱大小
        visualSize = visualSize,  -- 视觉显示大小
        isElite = isElite,
        eliteMod = eliteMod,
        eliteDamageMult = eliteDamageMult,
        eliteWindupMult = eliteWindupMult,
        eliteBulletSpeedMult = eliteBulletSpeedMult,
        shieldRegenDelay = shieldRegenDelay,
        shieldRegenRate = shieldRegenRate,
        tenacity = tenacity,
        hardCcImmune = hardCcImmune,
        isBoss = def.isBoss or false,
        kind = type,
        shootInterval = shootInterval,
        shootTimer = shootInterval,
        bulletSpeed = bulletSpeed,
        bulletDamage = bulletDamage,
        bulletLife = bulletLife,
        bulletSize = bulletSize,
        facing = 1,
        spawnTime = love.timer.getTime()  -- For animation phase offset
    })
    local spawned = state.enemies[#state.enemies]
    ensureStatus(spawned)
    if spawned and spawned.isElite and spawned.eliteMod and state and state.texts and not opts.suppressSpawnText then
        table.insert(state.texts, {x = spawned.x, y = spawned.y - 70, text = string.upper(spawned.eliteMod), color = {1, 1, 1}, life = 1.2})
    end
    if state and state.augments and state.augments.dispatch then
        state.augments.dispatch(state, 'onEnemySpawned', {
            enemy = spawned,
            kind = type,
            isElite = isElite or false,
            isBoss = spawned.isBoss or false,
            player = state.player
        })
    end
    return spawned
end

local function resetDummy(e)
    if not e or not e.isDummy then return end
    e.health = e.maxHealth or e.health or 0
    e.hp = e.health
    e.shield = e.maxShield or e.shield or 0
    e.lastDamage = nil
    e.status = nil
    e.shieldDelayTimer = 0
    ensureStatus(e)
end

function enemies.findNearestEnemy(state, maxDist, fromX, fromY, opts)
    if not state then return nil end
    opts = opts or {}
    local px = fromX
    local py = fromY
    if px == nil then px = state.player and state.player.x end
    if py == nil then py = state.player and state.player.y end
    if px == nil or py == nil then return nil end

    local t, m = nil, (maxDist or 999999) ^ 2
    local world = state.world
    local requireLOS = opts.requireLOS == true
    for _, e in ipairs(state.enemies or {}) do
        if e and (e.health or e.hp or 0) > 0 then
            local dx = px - e.x
            local dy = py - e.y
            local d2 = dx * dx + dy * dy
            if d2 < m then
                local blocked = false
                if requireLOS and world and world.enabled and world.segmentHitsWall then
                    blocked = world:segmentHitsWall(px, py, e.x, e.y)
                end
                if not blocked then
                    m = d2
                    t = e
                end
            end
        end
    end
    return t
end

-- Check if player is inside any nullifier's bubble (blocks abilities)
function enemies.isInNullBubble(state)
    if not state or not state.enemies then return false end
    local px, py = state.player.x, state.player.y
    
    for _, e in ipairs(state.enemies) do
        if e and (e.health or e.hp or 0) > 0 and e.kind == 'nullifier' then
            local def = enemyDefs[e.kind] or {}
            if def.nullBubble and def.nullBubble.radius then
                local radius = def.nullBubble.radius
                local dx = px - e.x
                local dy = py - e.y
                if dx*dx + dy*dy <= radius * radius then
                    return true, e  -- Return enemy reference for visual feedback
                end
            end
        end
    end
    return false
end

function enemies.damageEnemy(state, e, dmg, knock, kForce, isCrit, opts)
    opts = opts or {}
    ensureStatus(e)
    local incoming = dmg or 0
    if incoming <= 0 then return 0 end

    if not opts.noFlash then
        e.flashTimer = 0.1
    end
    if not opts.noSfx and state.playSfx then state.playSfx('hit') end

    local remaining = incoming
    local shieldHit = 0
    if not opts.bypassShield and e.shield and e.shield > 0 then
        local mult = opts.shieldMult or 1
        local eff = remaining * mult
        shieldHit = math.min(e.shield, eff)
        e.shield = e.shield - shieldHit
        local consumed = shieldHit / mult
        remaining = math.max(0, remaining - consumed)
    end

    local healthHit = 0
    if remaining > 0 then
        local armor = opts.ignoreArmor and 0 or getEffectiveArmor(e)
        local reduced = applyArmorReduction(remaining, armor)
        local viralMult = opts.viralMultiplier or 1
        healthHit = math.max(0, math.floor(reduced * viralMult + 0.5))
        e.health = e.health - healthHit
        e.hp = e.health
    end
    e.maxHp = e.maxHealth
    e.shieldDelayTimer = 0
    if opts.lockShield then
        e.status.shieldLocked = true
    end
    local appliedTotal = shieldHit + healthHit
    
    -- 追踪最近伤害（用于触发撤退行为）
    e.recentDamage = (e.recentDamage or 0) + healthHit

    local color = {1,1,1}
    local scale = 1
    if isCrit then
        color = {1, 1, 0}
        scale = 1.5
    elseif shieldHit > 0 and healthHit == 0 then
        color = {0.4, 0.7, 1}
    end
    if appliedTotal > 0 and not opts.noText then
        local shown = math.floor(appliedTotal + 0.5)
        local textOffsetY = opts.textOffsetY or 0
        table.insert(state.texts, {x=e.x, y=e.y-20 + textOffsetY, text=shown, color=color, life=0.5, scale=scale})
    end
    if knock then
        local a = math.atan2(e.y - state.player.y, e.x - state.player.x)
        e.x = e.x + math.cos(a) * (kForce or 10)
        e.y = e.y + math.sin(a) * (kForce or 10)
    end
    if e.isDummy and e.health <= 0 then
        resetDummy(e)
    end
    return appliedTotal, shieldHit, healthHit
end

function enemies.update(state, dt)
    local p = state.player
    local playerMight = (state.player and state.player.stats and state.player.stats.might) or 1
    state.chainLinks = {}
    state._staticSfxCooldown = math.max(0, (state._staticSfxCooldown or 0) - dt)
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        ensureStatus(e)
        
        -- === 局部顿帧处理 ===
        local localDt = dt
        if e.hitstopTimer and e.hitstopTimer > 0 then
            e.hitstopTimer = e.hitstopTimer - dt
            localDt = dt * (e.hitstopTimeScale or 0.05)
            if e.hitstopTimer <= 0 then
                e.hitstopTimer = 0
            end
        end
        -- 使用 localDt 替换后续逻辑中的 dt
        local dt = localDt 
        local def = enemyDefs[e.kind] or enemyDefs.skeleton
        local tenacity = clamp(e.tenacity or 0, 0, 0.95)
        local hardCcImmune = (e.hardCcImmune == true) or (def and def.hardCcImmune == true) or false

        -- === STUCK DETECTION ===
        -- If enemy is far from player and hasn't moved much, teleport them closer
        -- DISABLED in chapter mode to preserve pre-spawn spatial design
        if state.runMode ~= 'chapter' then
            local distToPlayer = math.sqrt((p.x - e.x)^2 + (p.y - e.y)^2)
            e._stuckTimer = e._stuckTimer or 0
            e._lastX = e._lastX or e.x
            e._lastY = e._lastY or e.y
            
            local movedDist = math.sqrt((e.x - e._lastX)^2 + (e.y - e._lastY)^2)
            if distToPlayer > 400 and movedDist < 5 then
                -- Enemy is far and hasn't moved
                e._stuckTimer = e._stuckTimer + dt
            else
                e._stuckTimer = 0
            end
            e._lastX = e.x
            e._lastY = e.y
            
            -- If stuck for more than 8 seconds, teleport to a valid location near player
            if e._stuckTimer > 8 and not e.isBoss then
                local world = state.world
                if world and world.enabled and world.sampleSpawn then
                    local newX, newY = world:sampleSpawn(p.x, p.y, 150, 300, 20)
                    if newX and newY then
                        e.x, e.y = newX, newY
                        e._stuckTimer = 0
                        if state.texts then
                            table.insert(state.texts, {x = e.x, y = e.y - 40, text = "!", color = {1, 0.5, 0.5}, life = 0.6})
                        end
                    end
                else
                    -- No world, just teleport near player
                    local ang = math.random() * math.pi * 2
                    e.x = p.x + math.cos(ang) * 200
                    e.y = p.y + math.sin(ang) * 200
                    e._stuckTimer = 0
                end
            end
        end
        -- === END STUCK DETECTION ===

        if e.noContactDamageTimer and e.noContactDamageTimer > 0 then
            e.noContactDamageTimer = e.noContactDamageTimer - (dt or 0)
            if e.noContactDamageTimer <= 0 then e.noContactDamageTimer = nil end
        end

        if hardCcImmune and e.status then
            if e.status.frozen then
                e.status.frozen = false
                e.status.frozenTimer = nil
                e.speed = e.baseSpeed or e.speed
            end
            if e.status.impactTimer and e.status.impactTimer > 0 then e.status.impactTimer = 0 end
            if e.status.shockTimer and e.status.shockTimer > 0 then e.status.shockTimer = 0 end
        end

        -- Boss phase (simple HP thresholds) to create a readable escalation.
        if e.isBoss or (def and def.isBoss) then
            local maxHp = (e.maxHealth or e.maxHp or 1)
            local hp = (e.health or e.hp or 0)
            local ratio = (maxHp > 0) and (hp / maxHp) or 0
            local phase = 1
            if ratio <= 0.33 then phase = 3
            elseif ratio <= 0.66 then phase = 2 end
            if e.bossPhase == nil then
                e.bossPhase = phase
            elseif phase ~= e.bossPhase then
                e.bossPhase = phase
                if state and state.texts then
                    table.insert(state.texts, {x = e.x, y = e.y - 120, text = "PHASE " .. phase, color = {1, 0.35, 0.25}, life = 1.4})
                end
                -- prevent long idle gaps when entering a new phase
                if e.attackCooldown and e.attackCooldown > 0.6 then e.attackCooldown = 0.6 end
            end
        end

        if e.flashTimer and e.flashTimer > 0 then
            e.flashTimer = e.flashTimer - dt
            if e.flashTimer < 0 then e.flashTimer = 0 end
        end
        
        -- 更新受击动画计时器（与顿帧关联）
        if e.hitAnimTimer and e.hitAnimTimer > 0 then
            e.hitAnimTimer = e.hitAnimTimer - dt
            if e.hitAnimTimer < 0 then e.hitAnimTimer = 0 end
        end


        if e.status.frozen then
            e.status.frozenTimer = (e.status.frozenTimer or 0) - dt
            if e.status.frozenTimer <= 0 then
                e.status.frozen = false
                e.status.frozenTimer = nil
                e.speed = e.baseSpeed or e.speed
            end
        end

        if not e.status.frozen and e.status.coldTimer and e.status.coldTimer > 0 then
            e.status.coldTimer = e.status.coldTimer - dt
            if e.status.coldTimer <= 0 then
                e.status.coldTimer = nil
                e.status.coldStacks = 0
                e.speed = e.baseSpeed or e.speed
            else
                local stacks = e.status.coldStacks or 0
                local slowPct = 0.25 + math.max(0, stacks - 1) * 0.05
                if slowPct > 0.7 then slowPct = 0.7 end
                -- Tenacity reduces soft-CC strength (slows) and makes bosses less lockable.
                slowPct = slowPct * (1 - tenacity * 0.6)
                local mult = 1 - slowPct
                e.speed = (e.baseSpeed or e.speed) * mult
            end
        end

        if e.anim then e.anim:update(dt) end

        if e.status.blastTimer and e.status.blastTimer > 0 then
            e.status.blastTimer = e.status.blastTimer - dt
            if e.status.blastTimer <= 0 then
                e.status.blastTimer = nil
                e.status.blastStacks = 0
            end
        end

        if e.status.impactTimer and e.status.impactTimer > 0 then
            e.status.impactTimer = e.status.impactTimer - dt
            if e.status.impactTimer <= 0 then
                e.status.impactTimer = nil
            end
        end

        if e.status.shockTimer and e.status.shockTimer > 0 then
            e.status.shockTimer = e.status.shockTimer - dt
            if e.status.shockTimer <= 0 then
                e.status.shockTimer = nil
            end
        end
        if e.status.shockLockout and e.status.shockLockout > 0 then
            e.status.shockLockout = e.status.shockLockout - dt
            if e.status.shockLockout < 0 then e.status.shockLockout = 0 end
        end
        if e.status.gasSplashCd and e.status.gasSplashCd > 0 then
            e.status.gasSplashCd = e.status.gasSplashCd - dt
            if e.status.gasSplashCd < 0 then e.status.gasSplashCd = 0 end
        end
        if e.status.staticSplashCd and e.status.staticSplashCd > 0 then
            e.status.staticSplashCd = e.status.staticSplashCd - dt
            if e.status.staticSplashCd < 0 then e.status.staticSplashCd = 0 end
        end

        if e.status.punctureTimer and e.status.punctureTimer > 0 then
            e.status.punctureTimer = e.status.punctureTimer - dt
            if e.status.punctureTimer <= 0 then
                e.status.punctureTimer = nil
                e.status.punctureStacks = 0
            end
        end

        if e.status.radiationTimer and e.status.radiationTimer > 0 then
            e.status.radiationTimer = e.status.radiationTimer - dt
            e.status.radiationTargetTimer = (e.status.radiationTargetTimer or 0) - dt
            if e.status.radiationTargetTimer <= 0 then
                e.status.radiationTargetTimer = 0.8
                local target = nil
                if #state.enemies > 1 then
                    for _ = 1, 6 do
                        local cand = state.enemies[math.random(#state.enemies)]
                        if cand ~= e then
                            target = cand
                            break
                        end
                    end
                end
                e.status.radiationTarget = target
                if not target then
                    e.status.radiationAngle = math.random() * 6.28
                end
            end
            if e.status.radiationTimer <= 0 then
                e.status.radiationTimer = nil
                e.status.radiationTargetTimer = nil
                e.status.radiationTarget = nil
                e.status.radiationAngle = nil
            end
        end

        if e.status.burnTimer and e.status.burnTimer > 0 then
            e.status.burnTimer = e.status.burnTimer - dt
            local dps = math.max(1, e.status.burnDps or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05))
            e.status._burnAcc = (e.status._burnAcc or 0) + dps * dt
            if e.status._burnAcc >= 1 then
                local burnDmg = math.floor(e.status._burnAcc)
                e.status._burnAcc = e.status._burnAcc - burnDmg
                if burnDmg > 0 then applyDotTick(state, e, 'HEAT', burnDmg) end
            end
            if e.status.burnTimer and e.status.burnTimer < 0 then e.status.burnTimer = 0 end
        end

        if e.status.bleedTimer and e.status.bleedTimer > 0 then
            e.status.bleedTimer = e.status.bleedTimer - dt
            e.status.bleedAcc = (e.status.bleedAcc or 0) + (e.status.bleedDps or 0) * dt
            if e.status.bleedAcc >= 1 then
                local tick = math.floor(e.status.bleedAcc)
                e.status.bleedAcc = e.status.bleedAcc - tick
                if tick > 0 then
                    applyDotTick(state, e, 'SLASH', tick, {bypassShield=true, ignoreArmor=true})
                end
            end
            if e.status.bleedTimer and e.status.bleedTimer <= 0 then
                e.status.bleedTimer = nil
                e.status.bleedDps = nil
                e.status.bleedAcc = nil
                e.status.bleedStacks = 0
            end
        end

        if e.status.oiled and e.status.oiledTimer then
            e.status.oiledTimer = e.status.oiledTimer - dt
            if e.status.oiledTimer <= 0 then
                e.status.oiled = false
                e.status.oiledTimer = nil
            end
        end

        if e.status.static and e.status.staticTimer and e.status.staticTimer > 0 then
            e.status.staticTimer = e.status.staticTimer - dt
            if e.health > 0 then
                e.status.staticTickTimer = (e.status.staticTickTimer or 1.0) - dt
                if e.status.staticTickTimer <= 0 then
                    e.status.staticTickTimer = 1.0
                    local tick = math.floor(e.status.staticDps or 0)
                    if tick > 0 then
                        local radius = e.status.staticRadius or 140
                        local r2 = radius * radius
                        applyDotTick(state, e, 'ELECTRIC', tick, {noSfx=true})
                        
                        local conductionTargets = {}
                        local world = state.world
                        for _, o in ipairs(state.enemies) do
                            if o ~= e and o.health > 0 then
                                local dx = o.x - e.x
                                local dy = o.y - e.y
                                if dx*dx + dy*dy <= r2 then
                                    local blocked = false
                                    -- 检查视线遮挡
                                    if world and world.enabled and world.segmentHitsWall and world:segmentHitsWall(e.x, e.y, o.x, o.y) then
                                        blocked = true
                                    end
                                    
                                    if not blocked and (o.status.staticSplashCd or 0) <= 0 then
                                        table.insert(conductionTargets, o)
                                    end
                                end
                            end
                        end
                        
                        -- Sort by distance or just pick top targets
                        if #conductionTargets > 0 then
                            local abilities = require('gameplay.abilities')
                            local segments = {}
                            local maxShown = 6
                            for i = 1, math.min(#conductionTargets, maxShown) do
                                local o = conductionTargets[i]
                                o.status.staticSplashCd = 0.5 -- Higher CD for secondary procs
                                table.insert(segments, {
                                    x1 = e.x, y1 = e.y,
                                    x2 = o.x, y2 = o.y,
                                    width = 10,
                                    source = e,
                                    target = o,
                                    damage = tick -- Secondary targets take same tick damage
                                })
                            end
                            abilities.spawnChain(state, segments, { speed = 2500, noSfx = true })
                        end
                    end
                end
            end
            if e.status.staticTimer and e.status.staticTimer <= 0 then
                e.status.static = false
                e.status.staticTimer = nil
                e.status.staticDps = nil
                e.status.staticRadius = nil
                e.status.staticTickTimer = nil
            end
        end

        if e.status.magneticTimer and e.status.magneticTimer > 0 then
            e.status.magneticTimer = e.status.magneticTimer - dt
            e.status.shieldLocked = true
            if e.status.magneticTimer <= 0 then
                e.status.magneticTimer = nil
                e.status.magneticMult = nil
                e.status.magneticStacks = 0
                e.status.shieldLocked = false
            end
        end

        if e.status.viralTimer and e.status.viralTimer > 0 then
            e.status.viralTimer = e.status.viralTimer - dt
            if e.status.viralTimer <= 0 then
                e.status.viralTimer = nil
                e.status.viralStacks = 0
            end
        end

        if e.status.heatTimer and e.status.heatTimer > 0 then
            e.status.heatTimer = e.status.heatTimer - dt
            e.status.heatAcc = (e.status.heatAcc or 0) + (e.status.heatDps or 0) * dt
            if e.status.heatAcc >= 1 then
                local tick = math.floor(e.status.heatAcc)
                e.status.heatAcc = e.status.heatAcc - tick
                if tick > 0 then applyDotTick(state, e, 'HEAT', tick) end
            end
            if e.status.heatTimer and e.status.heatTimer <= 0 then
                e.status.heatTimer = nil
                e.status.heatDps = nil
                e.status.heatAcc = nil
            end
        end

        if e.status.toxinTimer and e.status.toxinTimer > 0 then
            e.status.toxinTimer = e.status.toxinTimer - dt
            e.status.toxinAcc = (e.status.toxinAcc or 0) + (e.status.toxinDps or 0) * dt
            if e.status.toxinAcc >= 1 then
                local tick = math.floor(e.status.toxinAcc)
                e.status.toxinAcc = e.status.toxinAcc - tick
                applyDotTick(state, e, 'TOXIN', tick, {bypassShield=true})
            end
            if e.status.toxinTimer and e.status.toxinTimer <= 0 then
                e.status.toxinTimer = nil
                e.status.toxinDps = nil
                e.status.toxinAcc = nil
            end
        end

        if e.status.gasTimer and e.status.gasTimer > 0 then
            e.status.gasTimer = e.status.gasTimer - dt
            e.status.gasAcc = (e.status.gasAcc or 0) + (e.status.gasDps or 0) * dt
            if e.status.gasAcc >= 1 then
                local tick = math.floor(e.status.gasAcc)
                e.status.gasAcc = e.status.gasAcc - tick
                if tick > 0 then
                    local radius = e.status.gasRadius or 100
                    local r2 = radius * radius
                    applyDotTick(state, e, 'GAS', tick, {bypassShield=true})
                    for _, o in ipairs(state.enemies) do
                        if o ~= e then
                            local dx = o.x - e.x
                            local dy = o.y - e.y
                            if dx*dx + dy*dy <= r2 then
                                ensureStatus(o)
                                if (o.status.gasSplashCd or 0) <= 0 then
                                    applyDotTick(state, o, 'GAS', tick, {bypassShield=true, noText=true})
                                    o.status.gasSplashCd = 0.35
                                end
                            end
                        end
                    end
                end
            end
            if e.status.gasTimer and e.status.gasTimer <= 0 then
                e.status.gasTimer = nil
                e.status.gasDps = nil
                e.status.gasRadius = nil
                e.status.gasAcc = nil
            end
        end

        if e.maxShield and e.maxShield > 0 and not (e.status and e.status.shieldLocked) then
            local delay = e.shieldRegenDelay or SHIELD_REGEN_DELAY
            local rate = e.shieldRegenRate or SHIELD_REGEN_RATE
            e.shieldDelayTimer = (e.shieldDelayTimer or 0) + dt
            if e.shieldDelayTimer >= delay and e.shield < e.maxShield then
                local regen = e.maxShield * rate * dt
                e.shield = math.min(e.maxShield, e.shield + regen)
            end
        end

        -- Heal Aura mechanic (Ancient Healer)
        local def = enemyDefs[e.kind] or {}
        if def.healAura and def.healAura.radius and def.healAura.healRate then
            local radius = def.healAura.radius
            local healRate = def.healAura.healRate
            local r2 = radius * radius
            
            for _, other in ipairs(state.enemies) do
                if other ~= e and (other.health or other.hp or 0) > 0 then
                    local dx = other.x - e.x
                    local dy = other.y - e.y
                    if dx*dx + dy*dy <= r2 then
                        local maxHp = other.maxHealth or other.maxHp or other.health or 0
                        if other.health < maxHp then
                            other.health = math.min(maxHp, other.health + healRate * dt)
                            other.hp = other.health
                        end
                    end
                end
            end
            
            -- Visual indicator for heal aura (spawn occasionally)
            e._healAuraVfxTimer = (e._healAuraVfxTimer or 0) - dt
            if e._healAuraVfxTimer <= 0 then
                e._healAuraVfxTimer = 1.5  -- VFX every 1.5s
                if state.spawnAreaField then
                    state.spawnAreaField('heal', e.x, e.y, radius, 0.8, 0.5)
                end
            end
        end

        local pushX, pushY = 0, 0
        if #state.enemies > 1 then
            local checks = math.min(8, #state.enemies - 1)
            for _ = 1, checks do
                local idx
                repeat idx = math.random(#state.enemies) until idx ~= i
                local o = state.enemies[idx]
                local dx = e.x - o.x
                local dy = e.y - o.y
                local distSq = dx*dx + dy*dy
                local minDist = ((e.size or 16) + (o.size or 16)) * 0.5
                local minDistSq = minDist * minDist
                if distSq > 0 and distSq < minDistSq then
                    local dist = math.sqrt(distSq)
                    local overlap = minDist - dist
                    local nx, ny = dx / dist, dy / dist
                    -- Soft repulsion: adjust strength for better stability
                    local strength = 3.5
                    pushX = pushX + nx * overlap * strength
                    pushY = pushY + ny * overlap * strength
                end
            end
        end

        local stunned = false
        if not hardCcImmune then
            stunned = e.status.frozen
                or (e.status.impactTimer and e.status.impactTimer > 0)
                or (e.status.shockTimer and e.status.shockTimer > 0)
        end
        local coldMult = 1
        if not e.status.frozen and e.status.coldTimer and e.status.coldTimer > 0 and (e.status.coldStacks or 0) > 0 then
            local stacks = e.status.coldStacks or 0
            local slowPct = 0.25 + math.max(0, stacks - 1) * 0.05
            if slowPct > 0.7 then slowPct = 0.7 end
            slowPct = slowPct * (1 - tenacity * 0.6)
            coldMult = 1 - slowPct
        end
        
        -- === 死亡状态检查 ===
        -- 正在播放死亡动画的敌人不应该移动或攻击
        if e.isDying then
            -- 更新死亡动画计时器
            e.dyingTimer = (e.dyingTimer or 0) - dt
            if e.dyingTimer <= 0 then
                -- 死亡动画播完，标记为可移除
                e.readyToRemove = true
            end
            -- 跳过移动和攻击逻辑，但不跳过死亡处理逻辑
            if not e.readyToRemove then
                goto continue_enemy_loop
            end
        end
        
        -- === AI STATE ACTIVATION ===
        -- Check if enemy should activate (start chasing)
        local dx = p.x - e.x
        local dy = p.y - e.y
        local distToPlayerSq = dx * dx + dy * dy
        local distToPlayer = math.sqrt(distToPlayerSq)
        local aggroRange = e.aggroRange or 350
        local aggroRangeSq = aggroRange * aggroRange
        
        -- 获取AI行为配置
        local aiBehavior = getAIBehavior(e)
        
        -- 更新撤退冷却计时器
        if e.retreatCooldownTimer and e.retreatCooldownTimer > 0 then
            e.retreatCooldownTimer = e.retreatCooldownTimer - dt
        end
        
        -- === 扩展AI状态机 ===
        if e.aiState == AI_STATES.IDLE or e.aiState == 'idle' then
            -- 发现玩家
            if distToPlayerSq < aggroRangeSq then
                setAIState(e, AI_STATES.CHASE, 'player_detected')
                -- 显示"!"指示器
                if state.texts then
                    table.insert(state.texts, {x = e.x, y = e.y - 30, text = "!", color = {1, 0.8, 0.2}, life = 0.5, scale = 1.2})
                end
            else
                -- Still idle, skip movement and attack logic
                goto continue_enemy_loop
            end
            
        elseif e.aiState == AI_STATES.CHASE or e.aiState == 'chase' then
            -- 检查Boss是否应该进入狂暴
            if shouldBerserk(e, aiBehavior) then
                setAIState(e, AI_STATES.BERSERK, 'low_hp_rage')
                e.berserkTriggered = true
                e.berserkSpeedMult = aiBehavior.berserkSpeedMult or 1.4
                e.berserkDamageMult = aiBehavior.berserkDamageMult or 1.25
                -- 显示狂暴提示
                if state.texts then
                    table.insert(state.texts, {x = e.x, y = e.y - 40, text = "狂暴!", color = {1, 0.2, 0.2}, life = 1.5, scale = 1.5})
                end
            -- 检查是否应该撤退
            elseif shouldRetreat(e, aiBehavior, e.recentDamage) then
                setAIState(e, AI_STATES.RETREAT, 'low_hp')
                e.retreatStartX = e.x
                e.retreatStartY = e.y
                -- 计算撤退方向（远离玩家）
                local awayAng = math.atan2(e.y - p.y, e.x - p.x)
                e.retreatDirX = math.cos(awayAng)
                e.retreatDirY = math.sin(awayAng)
                -- 显示撤退提示
                if state.texts then
                    table.insert(state.texts, {x = e.x, y = e.y - 25, text = "!", color = {0.8, 0.8, 0.2}, life = 0.4, scale = 0.9})
                end
            -- 检查远程单位是否应该风筝
            elseif shouldKite(e, distToPlayer, aiBehavior) then
                setAIState(e, AI_STATES.KITING, 'too_close')
            end
            
        elseif e.aiState == AI_STATES.RETREAT then
            e.aiStateTimer = (e.aiStateTimer or 0) + dt
            local retreatDuration = aiBehavior.retreatDuration or 1.2
            -- 撤退完成
            if e.aiStateTimer >= retreatDuration then
                setAIState(e, AI_STATES.CHASE, 'retreat_complete')
                e.retreatCooldownTimer = aiBehavior.retreatCooldown or 5.0
                e.recentDamage = 0  -- 重置累积伤害
            end
            
        elseif e.aiState == AI_STATES.KITING then
            local preferredRange = aiBehavior.preferredRange or 280
            local kiteRange = aiBehavior.kiteRange or 140
            
            -- 玩家太远，恢复追击
            if distToPlayer > preferredRange * 1.3 then
                setAIState(e, AI_STATES.CHASE, 'player_too_far')
            -- 玩家不再太近
            elseif distToPlayer > kiteRange * 1.5 then
                setAIState(e, AI_STATES.CHASE, 'safe_distance')
            end
            -- 否则保持kiting状态
            
        elseif e.aiState == AI_STATES.BERSERK then
            -- Boss狂暴状态：持续追击，不会转换到其他状态
            -- 只有死亡才会退出
        end
        -- === END AI STATE ACTIVATION ===
        
        local targetX, targetY = p.x, p.y
        if e.status.radiationTimer and e.status.radiationTimer > 0 then
            local rt = e.status.radiationTarget
            if rt and rt.health and rt.health > 0 then
                targetX, targetY = rt.x, rt.y
            else
                local ang = e.status.radiationAngle or (math.random() * 6.28)
                targetX, targetY = e.x + math.cos(ang), e.y + math.sin(ang)
            end
        end
        local angToTarget = math.atan2(targetY - e.y, targetX - e.x)
        local world = state.world
        local moveAng = angToTarget
        if world and world.enabled and not (e.status.radiationTimer and e.status.radiationTimer > 0) then
            local ndx, ndy = world:getFlowDir(e.x, e.y)
            if ndx and ndy and not (ndx == 0 and ndy == 0) then
                moveAng = math.atan2(ndy, ndx)
            end
        end

        -- Telegraph-based attacks (reusable templates via enemy_defs.lua: def.attacks)
        if e.attackCooldown == nil then e.attackCooldown = 0 end
        if e.attackCooldown > 0 then
            e.attackCooldown = e.attackCooldown - dt * coldMult
            if e.attackCooldown < 0 then e.attackCooldown = 0 end
        end

        if stunned and e.attack and not hardCcImmune and e.attack.interruptible ~= false then
            -- some enemies can be interrupted during windup (but bosses resist hard-CC and keep patterns readable)
            e.attack = nil
            e.attackCooldown = math.max(e.attackCooldown or 0, 0.6)
        end

        local attacks = def and def.attacks

        -- tick active telegraphed attack
        do
            local atk = e.attack
            if atk and atk.type == 'charge' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        atk.phase = 'dash'
                        atk.remaining = atk.distance or 0
                        atk.hitPlayer = false
                        atk.hitPet = nil
                    end
                end
            elseif atk and atk.type == 'slam' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        local sx, sy = atk.x or e.x, atk.y or e.y
                        local radius = atk.radius or 0
                        local damage = atk.damage or 0
                        if radius > 0 and damage > 0 then
                            local dx = (p.x - sx)
                            local dy = (p.y - sy)
                            local pr = (p.size or 20) / 2
                            local rr = radius + pr
                            local dmgMult = 1 - getPunctureReduction(e)
                            if dmgMult < 0.25 then dmgMult = 0.25 end
                            if dx * dx + dy * dy <= rr * rr then
                                player.hurt(state, damage * dmgMult)
                            end
                            local pet = pets.getActive(state)
                            if pet and not pet.downed then
                                local ax = ((pet.x or 0) - sx)
                                local ay = ((pet.y or 0) - sy)
                                local ar = (pet.size or 18) / 2
                                local rr2 = radius + ar
                                if ax * ax + ay * ay <= rr2 * rr2 then
                                    pets.hurt(state, pet, damage * dmgMult)
                                end
                            end
                        end
                        if state.spawnEffect then
                            local s = 1.0
                            if radius and radius > 0 then s = math.max(0.8, math.min(2.0, radius / 90)) end
                            state.spawnEffect('blast_hit', sx, sy, s)
                        end
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 3.0
                    end
                end
            elseif atk and atk.type == 'burst' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        local baseAng = atk.ang or angToTarget
                        local count = math.max(1, math.floor(atk.count or 5))
                        local spread = atk.spread or 0.8
                        local spd = (atk.bulletSpeed or (e.bulletSpeed or 180))
                        local dmg = (atk.bulletDamage or (e.bulletDamage or 10))
                        local life = atk.bulletLife or (e.bulletLife or 5)
                        local size = atk.bulletSize or (e.bulletSize or 10)
                        local spriteKey = atk.spriteKey
                        if not spriteKey and (e.kind == 'plant' or e.kind == 'boss_treant') then
                            spriteKey = 'plant_bullet'
                        end

                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        local bulletDmg = dmg * dmgMult

                        for k = 1, count do
                            local t = (count == 1) and 0 or ((k - 1) / (count - 1) - 0.5)
                            local ang = baseAng + t * spread
                            table.insert(state.enemyBullets, {
                                x = e.x, y = e.y,
                                vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
                                size = size,
                                life = life,
                                damage = bulletDmg,
                                type = e.kind,
                                rotation = ang,
                                spriteKey = spriteKey,
                                -- Explosive properties for bombard rockets
                                explosive = atk.explosive,
                                splashRadius = atk.splashRadius
                            })
                        end
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 2.5
                    end
                end
            elseif atk and atk.type == 'melee' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        -- Melee attack damage
                        local range = atk.range or 50
                        local damage = atk.damage or 10
                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        damage = damage * dmgMult * (e.eliteDamageMult or 1)
                        
                        -- Check player hit
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local pr = (p.size or 20) / 2
                        if dist <= range + pr then
                            player.hurt(state, damage)
                        end
                        
                        -- Check pet hit
                        local pet = pets.getActive(state)
                        if pet and not pet.downed then
                            local pdx = (pet.x or 0) - e.x
                            local pdy = (pet.y or 0) - e.y
                            local pdist = math.sqrt(pdx * pdx + pdy * pdy)
                            local petR = (pet.size or 18) / 2
                            if pdist <= range + petR then
                                pets.hurt(state, pet, damage)
                            end
                        end
                        
                        -- Sound effect
                        if state.playSfx then state.playSfx('hit') end
                        
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 1.5
                    end
                end
            elseif atk and atk.type == 'throw' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        -- Fire projectile
                        local ang = atk.ang or 0
                        local spd = atk.bulletSpeed or 200
                        local dmg = atk.damage or 6
                        local life = atk.bulletLife or 2
                        local size = atk.bulletSize or 8
                        
                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        
                        table.insert(state.enemyBullets, {
                            x = e.x, y = e.y,
                            vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
                            size = size,
                            life = life,
                            damage = dmg * dmgMult,
                            type = e.kind,
                            rotation = ang
                        })
                        
                        if state.playSfx then state.playSfx('shoot') end
                        
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 3.0
                    end
                end
            elseif atk and atk.type == 'leap' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        atk.phase = 'leaping'
                        atk.leapProgress = 0
                    end
                elseif atk.phase == 'leaping' then
                    -- Move toward target
                    local totalDist = atk.distance or 100
                    local spd = atk.speed or 600
                    local moveDist = spd * dt
                    atk.leapProgress = (atk.leapProgress or 0) + moveDist
                    
                    -- Interpolate position
                    local t = math.min(1, atk.leapProgress / totalDist)
                    e.x = atk.startX + (atk.targetX - atk.startX) * t
                    e.y = atk.startY + (atk.targetY - atk.startY) * t
                    
                    -- Landing
                    if t >= 1 then
                        -- Damage on landing
                        local radius = atk.radius or 40
                        local damage = atk.damage or 7
                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        damage = damage * dmgMult * (e.eliteDamageMult or 1)
                        
                        -- Hit player
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local pr = (p.size or 20) / 2
                        if dist <= radius + pr then
                            player.hurt(state, damage)
                        end
                        
                        -- Hit pet
                        local pet = pets.getActive(state)
                        if pet and not pet.downed then
                            local pdx = (pet.x or 0) - e.x
                            local pdy = (pet.y or 0) - e.y
                            local pdist = math.sqrt(pdx * pdx + pdy * pdy)
                            local petR = (pet.size or 18) / 2
                            if pdist <= radius + petR then
                                pets.hurt(state, pet, damage)
                            end
                        end
                        
                        -- Effect
                        if state.spawnEffect then
                            state.spawnEffect('blast_hit', e.x, e.y, 0.8)
                        end
                        if state.playSfx then state.playSfx('hit') end
                        
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 2.0
                    end
                end
            elseif atk and atk.type == 'shield_bash' then
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        atk.phase = 'dash'
                        atk.distanceTraveled = 0
                        atk.hasHit = false
                    end
                elseif atk.phase == 'dash' then
                    -- Move in charge direction
                    local spd = atk.speed or 400
                    local moveDist = spd * dt
                    local moveX = atk.dirX * moveDist
                    local moveY = atk.dirY * moveDist
                    
                    if world and world.enabled and world.moveCircle then
                        e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, moveX, moveY)
                    else
                        e.x = e.x + moveX
                        e.y = e.y + moveY
                    end
                    
                    atk.distanceTraveled = (atk.distanceTraveled or 0) + moveDist
                    
                    -- Check hit (only once)
                    if not atk.hasHit then
                        local width = atk.width or 30
                        local damage = atk.damage or 12
                        local knockback = atk.knockback or 100
                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        damage = damage * dmgMult * (e.eliteDamageMult or 1)
                        
                        -- Check player
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local pr = (p.size or 20) / 2
                        if dist <= width / 2 + pr then
                            player.hurt(state, damage)
                            -- Knockback player
                            local kbDist = knockback
                            local kbDir = math.atan2(dy, dx)
                            p.x = p.x + math.cos(kbDir) * kbDist
                            p.y = p.y + math.sin(kbDir) * kbDist
                            atk.hasHit = true
                            if state.playSfx then state.playSfx('hit') end
                        end
                    end
                    
                    -- End dash
                    if atk.distanceTraveled >= (atk.distance or 80) then
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 3.0
                    end
                end
            elseif atk and atk.type == 'grapple' then
                -- Scorpion's grapple hook execution (gradual pull over 3 seconds)
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        -- Check if player is in range (cone-shaped hit detection)
                        local ang = atk.ang or 0
                        local range = atk.range or 280
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local playerAng = math.atan2(dy, dx)
                        local angDiff = math.abs((playerAng - ang + math.pi) % (math.pi * 2) - math.pi)
                        
                        local hitPlayer = (dist <= range and angDiff < 0.35)  -- ~20 degree cone
                        
                        if hitPlayer then
                            -- Initial damage on hook hit
                            local damage = (atk.damage or 8) * 0.3  -- Reduced initial damage
                            local dmgMult = 1 - getPunctureReduction(e)
                            if dmgMult < 0.25 then dmgMult = 0.25 end
                            player.hurt(state, damage * dmgMult)
                            
                            -- Start pulling phase
                            atk.phase = 'pulling'
                            atk.pullTimer = 3.0  -- 3 seconds to pull player to enemy
                            atk.pullTotalTime = 3.0
                            atk.startX = p.x
                            atk.startY = p.y
                            atk.targetX = e.x
                            atk.targetY = e.y
                            
                            -- Mark player as hooked (for escape detection)
                            p.grappled = true
                            p.grappleEnemy = e
                            p.grappleSlowMult = 0.3  -- Player moves at 30% speed while hooked
                            
                            if state.spawnEffect then state.spawnEffect('shock', p.x, p.y, 0.6) end
                            if state.playSfx then state.playSfx('hit') end
                            table.insert(state.texts, {x = p.x, y = p.y - 30, text = "GET OVER HERE!", color = {0.9, 0.7, 0.2}, life = 1.2})
                        else
                            e.attack = nil
                            e.attackCooldown = atk.cooldown or 5.0
                        end
                    end
                elseif atk.phase == 'pulling' then
                    -- Check if player escaped (dashed, used movement ability, or enemy died)
                    local dash = p.dash or {}
                    local isDashing = (dash.timer and dash.timer > 0)
                    local escaped = isDashing or
                                    (p.isSliding) or
                                    not p.grappled
                    
                    if escaped then
                        -- Player broke free!
                        p.grappled = false
                        p.grappleEnemy = nil
                        p.grappleSlowMult = nil
                        e.attack = nil
                        e.attackCooldown = (atk.cooldown or 5.0) * 0.5  -- Shorter cooldown on escape
                        table.insert(state.texts, {x = p.x, y = p.y - 30, text = "挣脱!", color = {0.4, 1, 0.4}, life = 0.8})
                    else
                        -- Continue pulling
                        atk.pullTimer = atk.pullTimer - dt
                        local t = 1 - (atk.pullTimer / atk.pullTotalTime)  -- 0 to 1 progress
                        t = math.min(1, math.max(0, t))
                        
                        -- Update target position (enemy may have moved)
                        atk.targetX = e.x
                        atk.targetY = e.y
                        
                        -- Calculate new position (lerp towards enemy)
                        local pullX = atk.startX + (atk.targetX - atk.startX) * t
                        local pullY = atk.startY + (atk.targetY - atk.startY) * t
                        
                        -- Apply pull with wall collision
                        local pullDx = pullX - p.x
                        local pullDy = pullY - p.y
                        if world and world.enabled and world.moveCircle then
                            p.x, p.y = world:moveCircle(p.x, p.y, (p.size or 20) / 2, pullDx, pullDy)
                        else
                            p.x, p.y = pullX, pullY
                        end
                        
                        -- Periodic damage ticks during pull
                        atk.damageTick = (atk.damageTick or 0) + dt
                        if atk.damageTick >= 0.8 then
                            atk.damageTick = 0
                            local tickDmg = (atk.damage or 8) * 0.15
                            player.hurt(state, tickDmg)
                        end
                        
                        -- Pull complete or timer expired
                        if atk.pullTimer <= 0 then
                            p.grappled = false
                            p.grappleEnemy = nil
                            p.grappleSlowMult = nil
                            e.attack = nil
                            e.attackCooldown = atk.cooldown or 5.0
                        end
                    end
                end
            elseif atk and atk.type == 'suicide' then
                -- Volatile Runner's suicide explosion
                if atk.phase == 'windup' then
                    atk.timer = (atk.timer or 0) - dt * coldMult
                    if atk.timer <= 0 then
                        local damage = atk.damage or 35
                        local radius = atk.explosionRadius or 80
                        local dmgMult = 1 - getPunctureReduction(e)
                        if dmgMult < 0.25 then dmgMult = 0.25 end
                        damage = damage * dmgMult
                        
                        -- Damage to player
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local distSq = dx * dx + dy * dy
                        local pr = (p.size or 20) / 2
                        local rr = radius + pr
                        if distSq <= rr * rr then
                            player.hurt(state, damage)
                        end
                        
                        -- Damage to pet
                        local pet = pets.getActive(state)
                        if pet and not pet.downed then
                            local pdx = (pet.x or 0) - e.x
                            local pdy = (pet.y or 0) - e.y
                            local petR = (pet.size or 18) / 2
                            local prr = radius + petR
                            if pdx * pdx + pdy * pdy <= prr * prr then
                                pets.hurt(state, pet, damage)
                            end
                        end
                        
                        -- Visual and sound effects
                        if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 1.5) end
                        if state.playSfx then state.playSfx('hit') end
                        
                        -- Kill self
                        e.health = 0
                        e.hp = 0
                        e.attack = nil
                    end
                end
            end
        end

        -- start a new telegraphed attack if ready (multi-attack enemies pick by weights + range)
        if attacks and not stunned and not e.attack and (e.attackCooldown or 0) <= 0 then
            local dx = targetX - e.x
            local dy = targetY - e.y
            local distSq = dx * dx + dy * dy
            local distToTarget = math.sqrt(distSq)

            local pool = {}
            for key, cfg in pairs(attacks) do
                if type(cfg) == 'table' then
                    local minR = cfg.rangeMin or 0
                    local maxR = cfg.range or cfg.rangeMax or cfg.maxRange or 999999
                    if distSq >= minR * minR and distSq <= maxR * maxR then
                        local w = cfg.w or cfg.weight or 1
                        if e.isBoss then
                            local phase = e.bossPhase or 1
                            local isBerserk = (e.aiState == AI_STATES.BERSERK)
                            
                            -- Boss 阶段性权重调整
                            if key == 'burst' then
                                if phase == 1 then w = w * 1.20
                                elseif phase == 3 then w = w * 0.85 end
                            elseif key == 'slam' then
                                if phase == 2 then w = w * 1.15 end
                                -- 狂暴时 AOE 更频繁
                                if isBerserk then w = w * 1.4 end
                            elseif key == 'charge' then
                                if phase == 3 then w = w * 1.25 end
                                -- 狂暴时猛冲更频繁
                                if isBerserk then w = w * 1.6 end
                            elseif key == 'rapid_burst' then
                                -- 快速弹幕在狂暴阶段大幅增加
                                if isBerserk then w = w * 2.5
                                elseif phase >= 2 then w = w * 1.5 end
                            end
                        end
                        if w > 0 then
                            table.insert(pool, {key = key, cfg = cfg, w = w})
                        end
                    end
                end
            end


            local pick = (#pool > 0) and chooseWeighted(pool) or nil
            if pick then
                local key = pick.key
                local cfg = pick.cfg or {}
                local bossPhase = e.bossPhase or 1
                local phaseK = math.max(0, bossPhase - 1)
                local eliteDamageMult = (e.eliteDamageMult or 1)
                local windupMult = (e.eliteWindupMult or 1)

                local circleOpts = nil
                if e.isBoss then circleOpts = {kind = 'danger', intensity = 1.35 + phaseK * 0.15}
                elseif e.isElite then circleOpts = {kind = 'telegraph', intensity = 1.1} end

                local lineOpts = nil
                if e.isBoss then lineOpts = {color = {1.0, 0.55, 0.22}}
                elseif e.isElite then lineOpts = {color = {1.0, 0.25, 0.25}} end

                local interruptible = cfg.interruptible
                if interruptible == nil then
                    interruptible = (key ~= 'burst')
                end
                if e.isBoss then interruptible = false end

                if key == 'charge' then
                    local windup = math.max(0.4, (cfg.windup or 0.55) * windupMult)
                    local distance = cfg.distance or 260
                    local spd = cfg.speed or 520
                    local width = cfg.telegraphWidth or 36
                    local damage = (cfg.damage or 18) * eliteDamageMult
                    local cooldown = cfg.cooldown or 2.5
                    if e.isBoss then
                        windup = math.max(0.45, windup * (1 - phaseK * 0.07))
                        distance = distance * (1 + phaseK * 0.12)
                        spd = spd * (1 + phaseK * 0.08)
                        width = width * (1 + phaseK * 0.08)
                        damage = damage * (1 + phaseK * 0.12)
                        cooldown = math.max(1.2, cooldown * (1 - phaseK * 0.08))
                    end
                    e.attack = {
                        type = 'charge',
                        phase = 'windup',
                        timer = windup,
                        interruptible = interruptible,
                        dirX = math.cos(angToTarget),
                        dirY = math.sin(angToTarget),
                        distance = distance,
                        speed = spd,
                        width = width,
                        damage = damage,
                        cooldown = cooldown
                    }
                    if state.spawnTelegraphLine then
                        local ex, ey = e.x, e.y
                        state.spawnTelegraphLine(ex, ey, ex + math.cos(angToTarget) * distance, ey + math.sin(angToTarget) * distance, width, windup, lineOpts)
                    end
                elseif key == 'slam' then
                    local windup = math.max(0.45, (cfg.windup or 0.85) * windupMult)
                    local radius = cfg.radius or 110
                    local damage = (cfg.damage or 16) * eliteDamageMult
                    local cooldown = cfg.cooldown or 3.0
                    if e.isBoss then
                        windup = math.max(0.5, windup * (1 - phaseK * 0.06))
                        radius = radius * (1 + phaseK * 0.12)
                        damage = damage * (1 + phaseK * 0.12)
                        cooldown = math.max(1.4, cooldown * (1 - phaseK * 0.07))
                    end
                    e.attack = {
                        type = 'slam',
                        phase = 'windup',
                        timer = windup,
                        interruptible = interruptible,
                        x = targetX,
                        y = targetY,
                        radius = radius,
                        damage = damage,
                        cooldown = cooldown
                    }
                    if state.spawnTelegraphCircle then
                        state.spawnTelegraphCircle(targetX, targetY, radius, windup, circleOpts)
                    end
                elseif key == 'burst' or key == 'rapid_burst' then
                    local windup = math.max(0.35, (cfg.windup or 0.6) * windupMult)
                    local count = cfg.count or 5
                    local spread = cfg.spread or 0.8
                    local bulletSpeed = (cfg.bulletSpeed or (e.bulletSpeed or 180)) * (e.eliteBulletSpeedMult or 1)
                    local bulletDamage = (cfg.bulletDamage or (e.bulletDamage or 10)) * eliteDamageMult
                    local bulletLife = cfg.bulletLife or (e.bulletLife or 5)
                    local bulletSize = cfg.bulletSize or (e.bulletSize or 10)
                    local cooldown = cfg.cooldown or 2.5
                    local len = cfg.telegraphLength or cfg.distance or 360
                    local width = cfg.telegraphWidth or 46
                    
                    -- === Boss 玩家移动预测瞄准 ===
                    local aimAng = angToTarget
                    local aiBehavior = getAIBehavior(e)
                    if e.isBoss and aiBehavior.predictPlayer then
                        -- 获取玩家速度向量
                        local pvx = p.vx or 0
                        local pvy = p.vy or 0
                        local playerSpeed = math.sqrt(pvx * pvx + pvy * pvy)
                        
                        -- 只在玩家移动时预测
                        if playerSpeed > 30 then
                            local dx = p.x - e.x
                            local dy = p.y - e.y
                            local distToP = math.sqrt(dx * dx + dy * dy)
                            
                            -- 预测时间 = 距离 / 子弹速度
                            local predTime = distToP / bulletSpeed
                            -- 增加预测偏差使其更准但不完美
                            local predMult = 0.65 + 0.15 * (e.bossPhase or 1)  -- Phase 1: 65%, Phase 3: 95%
                            
                            -- 预测玩家未来位置
                            local predX = p.x + pvx * predTime * predMult
                            local predY = p.y + pvy * predTime * predMult
                            
                            -- 使用预测位置计算瞄准角度
                            aimAng = math.atan2(predY - e.y, predX - e.x)
                        end
                    end
                    
                    if e.isBoss then
                        windup = math.max(0.35, windup * (1 - phaseK * 0.08))
                        count = count + phaseK * 2
                        spread = spread * (1 + phaseK * 0.16)
                        bulletSpeed = bulletSpeed * (1 + phaseK * 0.08)
                        bulletDamage = bulletDamage * (1 + phaseK * 0.12)
                        len = len * (1 + phaseK * 0.05)
                        width = width * (1 + phaseK * 0.10)
                        cooldown = math.max(0.8, cooldown * (1 - phaseK * 0.12))
                        
                        -- 狂暴阶段进一步加强
                        if e.aiState == AI_STATES.BERSERK then
                            bulletSpeed = bulletSpeed * 1.2
                            bulletDamage = bulletDamage * (aiBehavior.berserkDamageMult or 1.6)
                            cooldown = cooldown * 0.7
                            count = count + 2
                        end
                    end
                    e.attack = {
                        type = 'burst',
                        phase = 'windup',
                        timer = windup,
                        interruptible = interruptible,
                        ang = aimAng, -- 使用预测角度
                        count = count,
                        spread = spread,
                        bulletSpeed = bulletSpeed,
                        bulletDamage = bulletDamage,
                        bulletLife = bulletLife,
                        bulletSize = bulletSize,
                        cooldown = cooldown,
                        width = width,
                        length = len
                    }
                    -- Only show telegraph line for bosses/elites, normal enemies get "!" indicator
                    if e.isBoss or e.isElite then
                        if state.spawnTelegraphLine then
                            local ex, ey = e.x, e.y
                            state.spawnTelegraphLine(ex, ey, ex + math.cos(aimAng) * len, ey + math.sin(aimAng) * len, width, windup, lineOpts)
                        end
                    else
                        if state.texts then
                            table.insert(state.texts, {x = e.x, y = e.y - (e.size or 24) - 15, text = "!", color = {1, 0.8, 0.3, 0.8}, life = windup * 0.9, scale = 1.2})

                        end
                    end
                elseif key == 'melee' then
                    local windup = math.max(0.25, (cfg.windup or 0.4) * windupMult)
                    local range = cfg.range or 50
                    local damage = (cfg.damage or 8) * eliteDamageMult
                    local cooldown = cfg.cooldown or 1.5
                    
                    e.attack = {
                        type = 'melee',
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        range = range,
                        damage = damage,
                        cooldown = cooldown
                    }
                    
                    -- Simple "!" indicator for melee (close range, no telegraph circle needed)
                    if state.texts then
                        table.insert(state.texts, {x = e.x, y = e.y - (e.size or 24) - 15, text = "!", color = {1, 0.3, 0.3, 0.9}, life = windup * 0.9, scale = 1.1})
                    end
                    
                elseif key == 'throw' then
                    -- Ranged projectile attack
                    local windup = math.max(0.3, (cfg.windup or 0.5) * windupMult)
                    local damage = (cfg.damage or 6) * eliteDamageMult
                    local bulletSpeed = (cfg.bulletSpeed or 200) * (e.eliteBulletSpeedMult or 1)
                    local bulletLife = cfg.bulletLife or 2
                    local bulletSize = cfg.bulletSize or 8
                    local cooldown = cfg.cooldown or 3.0
                    
                    e.attack = {
                        type = 'throw',
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        ang = angToTarget,
                        damage = damage,
                        bulletSpeed = bulletSpeed,
                        bulletLife = bulletLife,
                        bulletSize = bulletSize,
                        cooldown = cooldown
                    }
                    
                    -- Simple "!" indicator for basic throw (no telegraph line)
                    if state.texts then
                        table.insert(state.texts, {x = e.x, y = e.y - (e.size or 24) - 15, text = "!", color = {1, 0.8, 0.3, 0.8}, life = windup * 0.9, scale = 1.2})
                    end
                    
                elseif key == 'leap' then
                    -- Jump attack landing at target location
                    local windup = math.max(0.2, (cfg.windup or 0.3) * windupMult)
                    local distance = cfg.distance or 100
                    local spd = cfg.speed or 600
                    local damage = (cfg.damage or 7) * eliteDamageMult
                    local cooldown = cfg.cooldown or 2.0
                    local radius = cfg.radius or 40
                    
                    -- Calculate target position (limited by distance)
                    local actualDist = math.min(distToTarget, distance)
                    local leapX = e.x + math.cos(angToTarget) * actualDist
                    local leapY = e.y + math.sin(angToTarget) * actualDist
                    
                    e.attack = {
                        type = 'leap',
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        targetX = leapX,
                        targetY = leapY,
                        startX = e.x,
                        startY = e.y,
                        distance = actualDist,
                        speed = spd,
                        leapProgress = 0,
                        damage = damage,
                        radius = radius,
                        cooldown = cooldown
                    }
                    
                    -- Show landing zone
                    if state.spawnTelegraphCircle then
                        local leapTime = actualDist / spd
                        state.spawnTelegraphCircle(leapX, leapY, radius, windup + leapTime, {kind = 'danger', intensity = 0.8})
                    end
                    
                elseif key == 'shield_bash' then
                    -- Short charge with knockback
                    local windup = math.max(0.3, (cfg.windup or 0.4) * windupMult)
                    local distance = cfg.distance or 80
                    local spd = cfg.speed or 400
                    local width = cfg.telegraphWidth or 30
                    local damage = (cfg.damage or 12) * eliteDamageMult
                    local knockback = cfg.knockback or 100
                    local cooldown = cfg.cooldown or 3.0
                    
                    e.attack = {
                        type = 'shield_bash',
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        dirX = math.cos(angToTarget),
                        dirY = math.sin(angToTarget),
                        distance = distance,
                        distanceTraveled = 0,
                        speed = spd,
                        width = width,
                        damage = damage,
                        knockback = knockback,
                        cooldown = cooldown,
                        hasHit = false
                    }
                    
                    -- Show charge line
                    if state.spawnTelegraphLine then
                        state.spawnTelegraphLine(e.x, e.y, e.x + math.cos(angToTarget) * distance, e.y + math.sin(angToTarget) * distance, width, windup, lineOpts)
                    end

                -- ===== New Attack Types for Batch 1 Ranged Enemies =====
                elseif key == 'shoot' then
                    -- Single accurate shot (Lancer-style)
                    local windup = math.max(0.3, (cfg.windup or 0.6) * windupMult)
                    local count = cfg.count or 1
                    local spread = cfg.spread or 0.05
                    local bulletSpeed = (cfg.bulletSpeed or 320) * (e.eliteBulletSpeedMult or 1)
                    local bulletDamage = (cfg.bulletDamage or 10) * eliteDamageMult
                    local bulletLife = cfg.bulletLife or 3
                    local bulletSize = cfg.bulletSize or 6
                    local cooldown = cfg.cooldown or 1.8
                    
                    e.attack = {
                        type = 'burst',  -- Reuse burst execution logic
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        ang = angToTarget,
                        count = count,
                        spread = spread,
                        bulletSpeed = bulletSpeed,
                        bulletDamage = bulletDamage,
                        bulletLife = bulletLife,
                        bulletSize = bulletSize,
                        cooldown = cooldown
                    }
                    
                    -- Simple "!" indicator for normal ranged attack (no telegraph line)
                    if state.texts then
                        table.insert(state.texts, {x = e.x, y = e.y - (e.size or 24) - 15, text = "!", color = {1, 0.8, 0.3, 0.8}, life = windup * 0.9, scale = 1.2})
                    end
                    
                elseif key == 'snipe' then
                    -- High damage sniper shot with long telegraph (Ballista-style)
                    local windup = math.max(0.8, (cfg.windup or 1.2) * windupMult)
                    local bulletSpeed = (cfg.bulletSpeed or 500) * (e.eliteBulletSpeedMult or 1)
                    local bulletDamage = (cfg.bulletDamage or 35) * eliteDamageMult
                    local bulletLife = cfg.bulletLife or 3
                    local bulletSize = cfg.bulletSize or 8
                    local cooldown = cfg.cooldown or 4.0
                    local telegraphLen = cfg.telegraphLength or 400
                    local telegraphWidth = cfg.telegraphWidth or 8
                    
                    e.attack = {
                        type = 'burst',  -- Reuse burst execution logic
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        ang = angToTarget,
                        count = 1,
                        spread = 0,
                        bulletSpeed = bulletSpeed,
                        bulletDamage = bulletDamage,
                        bulletLife = bulletLife,
                        bulletSize = bulletSize,
                        cooldown = cooldown
                    }
                    
                    -- Long visible telegraph line (sniper laser sight)
                    if state.spawnTelegraphLine then
                        state.spawnTelegraphLine(e.x, e.y, e.x + math.cos(angToTarget) * telegraphLen, e.y + math.sin(angToTarget) * telegraphLen, telegraphWidth, windup, {color = {1, 0.2, 0.2}})
                    end
                    
                elseif key == 'rocket' then
                    -- Explosive projectile (Bombard-style)
                    local windup = math.max(0.5, (cfg.windup or 0.9) * windupMult)
                    local bulletSpeed = (cfg.bulletSpeed or 200) * (e.eliteBulletSpeedMult or 1)
                    local bulletDamage = (cfg.bulletDamage or 28) * eliteDamageMult
                    local bulletLife = cfg.bulletLife or 4
                    local bulletSize = cfg.bulletSize or 14
                    local cooldown = cfg.cooldown or 3.5
                    local splashRadius = cfg.splashRadius or 70
                    
                    e.attack = {
                        type = 'burst',  -- Reuse burst execution logic
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        ang = angToTarget,
                        count = 1,
                        spread = 0,
                        bulletSpeed = bulletSpeed,
                        bulletDamage = bulletDamage,
                        bulletLife = bulletLife,
                        bulletSize = bulletSize,
                        cooldown = cooldown,
                        explosive = true,
                        splashRadius = splashRadius,
                        spriteKey = 'rocket'  -- Optional visual
                    }
                    
                    -- Simple "!" indicator for rocket (avoidable after launch)
                    if state.texts then
                        table.insert(state.texts, {x = e.x, y = e.y - (e.size or 28) - 15, text = "!", color = {1, 0.5, 0.2, 0.9}, life = windup * 0.9, scale = 1.4})
                    end

                elseif key == 'grapple' then
                    -- Scorpion's grapple hook attack
                    local windup = math.max(0.3, (cfg.windup or 0.5) * windupMult)
                    local pullDist = cfg.pullDistance or 120
                    local damage = (cfg.damage or 8) * eliteDamageMult
                    local cooldown = cfg.cooldown or 5.0
                    local width = cfg.telegraphWidth or 12
                    
                    e.attack = {
                        type = 'grapple',
                        phase = 'windup',
                        timer = windup,
                        interruptible = true,
                        ang = angToTarget,
                        pullDistance = pullDist,
                        damage = damage,
                        cooldown = cooldown,
                        range = cfg.range or 280
                    }
                    
                    -- Show hook telegraph line
                    if state.spawnTelegraphLine then
                        local len = cfg.range or 280
                        state.spawnTelegraphLine(e.x, e.y, e.x + math.cos(angToTarget) * len, e.y + math.sin(angToTarget) * len, width, windup, {color = {0.9, 0.7, 0.2}})
                    end
                    
                elseif key == 'suicide' then
                    -- Volatile Runner's suicide explosion attack
                    local windup = math.max(0.1, (cfg.windup or 0.15) * windupMult)
                    local damage = (cfg.damage or 35) * eliteDamageMult
                    local radius = cfg.explosionRadius or 80
                    
                    e.attack = {
                        type = 'suicide',
                        phase = 'windup',
                        timer = windup,
                        interruptible = false,
                        damage = damage,
                        explosionRadius = radius,
                        cooldown = 999  -- Doesn't matter, enemy dies
                    }
                    
                    -- Show danger circle
                    if state.spawnTelegraphCircle then
                        state.spawnTelegraphCircle(e.x, e.y, radius, windup, {kind = 'danger', intensity = 1.5})
                    end

                end
            end
        end

        if e.shootInterval and not stunned and not e.attack then
            e.shootTimer = (e.shootTimer or e.shootInterval) - dt * coldMult
            if e.shootTimer <= 0 then
                local ang = angToTarget
                local blastRed = getBlastReduction(e)
                if blastRed > 0 then
                    local spread = blastRed * 0.7
                    ang = ang + (math.random() - 0.5) * spread * 2
                end
                local spd = (e.bulletSpeed or 180) * (e.eliteBulletSpeedMult or 1)
                local spriteKey = nil
                if e.kind == 'plant' or e.kind == 'boss_treant' then spriteKey = 'plant_bullet' end
                local dmgMult = 1 - getPunctureReduction(e)
                if dmgMult < 0.25 then dmgMult = 0.25 end
                local bulletDmg = (e.bulletDamage or 10) * dmgMult * (e.eliteDamageMult or 1)
                table.insert(state.enemyBullets, {
                    x = e.x, y = e.y,
                    vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
                    size = e.bulletSize or 10,
                    life = e.bulletLife or 5,
                    damage = bulletDmg,
                    type = e.kind,
                    rotation = ang,
                    spriteKey = spriteKey
                })
                e.shootTimer = e.shootInterval
            end
        end

        local dxToTarget = targetX - e.x
        if math.abs(dxToTarget) > 1 then
            e.facing = dxToTarget >= 0 and 1 or -1
        end
        if stunned then
            if world and world.enabled and world.moveCircle then
                e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, pushX * dt, pushY * dt)
            else
                e.x = e.x + pushX * dt
                e.y = e.y + pushY * dt
            end
        elseif e.attack and e.attack.type == 'charge' and e.attack.phase == 'dash' then
            local atk = e.attack
            local remaining = atk.remaining or 0
            local step = (atk.speed or 0) * dt
            if step > remaining then step = remaining end
            if step > 0 then
                local mx = (atk.dirX or 0) * step
                local my = (atk.dirY or 0) * step
                if world and world.enabled and world.moveCircle then
                    e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, mx, my)
                else
                    e.x = e.x + mx
                    e.y = e.y + my
                end
                atk.remaining = remaining - step
            end

            if (atk.dirX or 0) ~= 0 then
                e.facing = ((atk.dirX or 0) >= 0) and 1 or -1
            end

            -- Charge collision: apply once per dash
            local dmgMult = 1 - getPunctureReduction(e)
            if dmgMult < 0.25 then dmgMult = 0.25 end
            local hitRadius = ((p.size or 20) + (e.size or 16)) * 0.5
            local cdx = p.x - e.x
            local cdy = p.y - e.y
            if not atk.hitPlayer and cdx * cdx + cdy * cdy <= hitRadius * hitRadius then
                player.hurt(state, (atk.damage or 18) * dmgMult)
                atk.hitPlayer = true
            end
            local pet = pets.getActive(state)
            if pet and not pet.downed and not atk.hitPet then
                local r = (((pet.size or 18) + (e.size or 16)) * 0.5)
                local dx = (pet.x or 0) - e.x
                local dy = (pet.y or 0) - e.y
                if dx * dx + dy * dy <= r * r then
                    pets.hurt(state, pet, (atk.damage or 18) * dmgMult)
                    atk.hitPet = true
                end
            end

            if (atk.remaining or 0) <= 0 then
                e.attack = nil
                e.attackCooldown = atk.cooldown or 2.5
            end
        elseif e.attack and e.attack.phase == 'windup' then
            -- windup: hold position (telegraph fairness)
        else
            -- === 检查近战敌人是否应该停止移动（等待攻击冷却） ===
            local shouldHoldPosition = false
            if attacks and not e.attack and (e.attackCooldown or 0) > 0 then
                -- 遍历攻击配置，检查是否有近战攻击且在范围内
                local dx = targetX - e.x
                local dy = targetY - e.y
                local distSq = dx * dx + dy * dy
                for key, cfg in pairs(attacks) do
                    if type(cfg) == 'table' and (key == 'melee' or key == 'slam') then
                        local maxR = cfg.range or cfg.rangeMax or 80
                        -- 如果已经在攻击范围内（加一点余量），就停止移动
                        if distSq <= (maxR * 1.2) * (maxR * 1.2) then
                            shouldHoldPosition = true
                            break
                        end
                    end
                end
            end
            
            if shouldHoldPosition then
                -- 在攻击范围内等待冷却，只应用推力不主动移动
                if world and world.enabled and world.moveCircle then
                    e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, pushX * dt, pushY * dt)
                else
                    e.x = e.x + pushX * dt
                    e.y = e.y + pushY * dt
                end
            else
            -- === 根据AI状态决定移动方向和速度 ===
            local moveVx, moveVy
            local speedMult = 1.0
            
            if e.aiState == AI_STATES.RETREAT then
                -- 撤退状态：远离玩家
                local awayAng = math.atan2(e.y - p.y, e.x - p.x)
                moveVx = math.cos(awayAng) * e.speed
                moveVy = math.sin(awayAng) * e.speed
                speedMult = 1.3  -- 撤退时略快
                
            elseif e.aiState == AI_STATES.KITING then
                -- 风筝状态：保持理想距离，绕行射击
                local preferredRange = aiBehavior.preferredRange or 280
                local kiteRange = aiBehavior.kiteRange or 140
                
                if distToPlayer < kiteRange then
                    -- 太近，后撤
                    local awayAng = math.atan2(e.y - p.y, e.x - p.x)
                    moveVx = math.cos(awayAng) * e.speed
                    moveVy = math.sin(awayAng) * e.speed
                    speedMult = 1.2
                elseif distToPlayer > preferredRange then
                    -- 太远，靠近
                    moveVx = math.cos(moveAng) * e.speed
                    moveVy = math.sin(moveAng) * e.speed
                else
                    -- 理想距离，绕行（侧移）
                    local circleDir = ((e.x + e.y) % 2 < 1) and 1 or -1  -- 随机绕行方向
                    local circleAng = angToTarget + math.pi/2 * circleDir
                    moveVx = math.cos(circleAng) * e.speed * 0.6
                    moveVy = math.sin(circleAng) * e.speed * 0.6
                end
                
            elseif e.aiState == AI_STATES.BERSERK then
                -- 狂暴状态：快速追击
                moveVx = math.cos(moveAng) * e.speed
                moveVy = math.sin(moveAng) * e.speed
                speedMult = e.berserkSpeedMult or 1.4
                
            else
                -- 默认追击行为 (CHASE 状态)
                moveVx = math.cos(moveAng) * e.speed
                moveVy = math.sin(moveAng) * e.speed
            end
            
            -- 应用速度倍率和推力
            local vx = moveVx * speedMult + pushX
            local vy = moveVy * speedMult + pushY
            
            if world and world.enabled and world.moveCircle then
                e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, vx * dt, vy * dt)
            else
                e.x = e.x + vx * dt
                e.y = e.y + vy * dt
            end
            end  -- end of shouldHoldPosition else branch
        end

        local pDist = math.sqrt((p.x - e.x)^2 + (p.y - e.y)^2)
        local playerRadius = (p.size or 20) / 2
        local enemyRadius = (e.size or 16) / 2
        local inChargeDash = e.attack and e.attack.type == 'charge' and e.attack.phase == 'dash'
        
        -- Collision: Player can push enemies, but enemies don't push player
        local collisionDist = playerRadius + enemyRadius
        if not inChargeDash and pDist < collisionDist and pDist > 0.1 then
            local pushDist = collisionDist - pDist
            local dx = (p.x - e.x) / pDist
            local dy = (p.y - e.y) / pDist
            
            -- Directional Push: Player pushes enemy, player doesn't get pushed
            local enemyPushX = -dx * pushDist
            local enemyPushY = -dy * pushDist
            
            -- Apply push to enemy (using moveCircle for smooth wall sliding)
            if world and world.enabled and world.moveCircle then
                e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, enemyPushX, enemyPushY)
            else
                e.x = e.x + enemyPushX
                e.y = e.y + enemyPushY
            end
        end

        if e.health <= 0 then
            -- 死亡动画延迟处理
            if not e.isDying then
                -- 刚进入死亡状态，开始播放死亡动画
                e.isDying = true
                e.dyingTimer = 0.5  -- 死亡动画播放时长
                e.health = 0  -- 确保血量为0
                e.attack = nil  -- 停止攻击
                goto continue_enemy_loop  -- 等待下一帧处理
            end
            
            -- 如果还没准备好移除，跳过（计时器在前面已更新）
            if not e.readyToRemove then
                goto continue_enemy_loop
            end
            
            if e.isDummy then
                resetDummy(e)
            else
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onKill', {enemy = e, player = state.player, lastDamage = e.lastDamage})
                end
                if e.magnetize then
                    local abilities = require('gameplay.abilities')
                    abilities.detonateMagnetize(state, e, 'death')
                end

                -- Check for onDeath explosion (Volatile Runner)
                local def = enemyDefs[e.kind] or {}
                if def.onDeath and def.onDeath.explosionRadius and def.onDeath.damage then
                    local radius = def.onDeath.explosionRadius
                    local damage = def.onDeath.damage
                    local r2 = radius * radius
                    
                    -- Damage player
                    local dx = p.x - e.x
                    local dy = p.y - e.y
                    local pr = (p.size or 20) / 2
                    local rr = radius + pr
                    if dx*dx + dy*dy <= rr * rr then
                        player.hurt(state, damage)
                    end
                    
                    -- Damage pet
                    local pet = pets.getActive(state)
                    if pet and not pet.downed then
                        local pdx = (pet.x or 0) - e.x
                        local pdy = (pet.y or 0) - e.y
                        local petR = (pet.size or 18) / 2
                        local prr = radius + petR
                        if pdx*pdx + pdy*pdy <= prr * prr then
                            pets.hurt(state, pet, damage)
                        end
                    end
                    
                    -- Explosion visual
                    if state.spawnEffect then state.spawnEffect('blast_hit', e.x, e.y, 1.3) end
                    if state.playSfx then state.playSfx('hit') end
                end

                local isBossDefeated = false
                if e.isBoss then
                    local exploreMode = (state.runMode == 'explore') or (state.world and state.world.enabled)
                    if exploreMode then
                        state.chests = state.chests or {}
                        table.insert(state.chests, {x = e.x, y = e.y, w = 26, h = 26, kind = 'boss_reward', rewardCurrency = 100})
                        state.directorState = state.directorState or {}
                        state.directorState.bossDefeated = true
                        if state.enemyBullets then
                            for k = #state.enemyBullets, 1, -1 do table.remove(state.enemyBullets, k) end
                        end
                        if state.texts then
                            table.insert(state.texts, {x = e.x, y = e.y - 110, text = "BOSS DOWN!", color = {1, 0.85, 0.35}, life = 2.2})
                        end
                        logger.kill(state, e)
                        table.remove(state.enemies, i)
                        isBossDefeated = true
                    else
                        -- Standard Boss Logic
                        local rewardCurrency = 100
                        local newModKey = nil
                        if state.profile and state.catalog then
                            state.profile.ownedMods = state.profile.ownedMods or {}
                            local locked = {}
                            for key, def in pairs(state.catalog) do
                                if def.type == 'mod' and not state.profile.ownedMods[key] then
                                    table.insert(locked, key)
                                end
                            end
                            if #locked > 0 then
                                newModKey = locked[math.random(#locked)]
                                state.profile.ownedMods[newModKey] = true
                            end
                            state.profile.currency = (state.profile.currency or 0) + rewardCurrency
                            if state.saveProfile then state.saveProfile(state.profile) end
                        end
                        state.victoryRewards = {
                            currency = rewardCurrency,
                            newModKey = newModKey,
                            newModName = (newModKey and state.catalog and state.catalog[newModKey] and state.catalog[newModKey].name) or nil
                        }
                        state.gameState = 'GAME_CLEAR'
                        -- Analytics: save run on victory
                        pcall(function() require('systems.analytics').endRun() end)
                        state.directorState = state.directorState or {}
                        state.directorState.bossDefeated = true
                        logger.kill(state, e)
                        table.remove(state.enemies, i)
                        isBossDefeated = true
                    end
                end

                if not isBossDefeated then
                    if not e.noDrops then
                         -- XP / Affinity Drop (Always drops, WF style affinity)
                        local xpValue = e.xp or (e.isElite and 50 or 10)
                        if e.isBoss then xpValue = 500 end
                        
                        -- Gain XP directly (Warframe style affinity)
                        require('systems.pickups').addXp(state, xpValue)
                        
                        -- Show pale floating text near player
                        if state.texts then
                            local px = state.player.x
                            local py = state.player.y
                            -- Slight random offset to prevent overlap
                            local ox = (math.random() - 0.5) * 40
                            local oy = (math.random() - 0.5) * 40 - 30
                            table.insert(state.texts, {
                                x = px + ox, 
                                y = py + oy, 
                                text = "+" .. tostring(xpValue) .. " XP", 
                                color = {0.6, 0.65, 0.7, 0.8}, -- Pale blue-grey
                                life = 0.6,
                                scale = 0.8
                            })
                        end


                        -- 使用 loot 子模块处理掉落
                        enemyLoot.process(state, e)
                    end
                    logger.kill(state, e)
                    table.remove(state.enemies, i)
                end
            end
        end
        
        ::continue_enemy_loop::
    end
end

--- 为敌人应用局部顿帧
---@param e table 敌人对象
---@param preset table|string 预设或名称
function enemies.applyLocalHitstop(e, preset)
    local hitstop = require('render.hitstop')
    local config = {}
    if type(preset) == 'string' and hitstop.presets[preset] then
        config = hitstop.presets[preset]
    elseif type(preset) == 'table' then
        config = preset
    end
    
    e.hitstopTimer = config.duration or 0.05
    e.hitstopTimeScale = config.timeScale or 0.05
end

return enemies
