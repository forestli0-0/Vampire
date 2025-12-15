local player = require('player')
local enemyDefs = require('enemy_defs')
local logger = require('logger')
local pets = require('pets')

local enemies = {}

local SHIELD_REGEN_DELAY = 2.5
local SHIELD_REGEN_RATE = 0.25 -- fraction of max shield per second

local _calculator = nil
local function getCalculator()
    if not _calculator then
        local ok, calc = pcall(require, 'calculator')
        if ok then _calculator = calc end
    end
    return _calculator
end

local function buildDamageModsForTicks(e)
    local opts = {}
    local st = e and e.status
    if st and st.magneticTimer and st.magneticTimer > 0 then
        opts.shieldMult = st.magneticMult or 1.75
        opts.lockShield = true
    end
    if st and st.viralStacks and st.viralStacks > 0 then
        local stacks = math.min(10, st.viralStacks)
        local bonus = math.min(2.25, 0.75 + stacks * 0.25)
        opts.viralMultiplier = 1 + bonus
    end
    return opts
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
    if not e or not e.status or not e.status.punctureStacks or e.status.punctureStacks <= 0 then return 0 end
    local stacks = math.min(10, e.status.punctureStacks)
    local red = 0.3 + (stacks - 1) * 0.05
    if red > 0.75 then red = 0.75 end
    return red
end

local function getBlastReduction(e)
    if not e or not e.status or not e.status.blastStacks or e.status.blastStacks <= 0 then return 0 end
    local stacks = math.min(10, e.status.blastStacks)
    local red = 0.3 + (stacks - 1) * 0.05
    if red > 0.75 then red = 0.75 end
    return red
end

local function ensureStatus(e)
    if not e.status then
        e.status = {
            frozen = false,
            coldStacks = 0,
            coldTimer = 0,
            oiled = false,
            static = false,
            shockTimer = 0,
            shockLockout = 0,
            bleedStacks = 0,
            bleedTimer = 0,
            bleedDps = 0,
            bleedAcc = 0,
            burnTimer = 0,
            magneticTimer = 0,
            magneticStacks = 0,
            viralStacks = 0,
            viralTimer = 0,
            heatArmorLoss = 0,
            heatTimer = 0,
            heatDps = 0,
            heatAcc = 0,
            toxinTimer = 0,
            toxinDps = 0,
            toxinAcc = 0,
            corrosiveStacks = 0,
            shieldLocked = false,
            punctureStacks = 0,
            punctureTimer = 0,
            impactTimer = 0,
            blastStacks = 0,
            blastTimer = 0,
            gasTimer = 0,
            gasDps = 0,
            gasRadius = 0,
            gasAcc = 0,
            gasSplashCd = 0,
            radiationTimer = 0,
            radiationTargetTimer = 0,
            radiationTarget = nil,
            radiationAngle = 0,
            staticSplashCd = 0
        }
    end
    e.status.shockLockout = e.status.shockLockout or 0
    e.status.gasSplashCd = e.status.gasSplashCd or 0
    e.status.staticSplashCd = e.status.staticSplashCd or 0
    e.baseSpeed = e.baseSpeed or e.speed
    e.baseArmor = e.baseArmor or e.armor or 0
    e.health = e.health or e.hp
    e.maxHealth = e.maxHealth or e.maxHp or e.hp
    e.maxHp = e.maxHealth
    e.hp = e.health
    e.shield = e.shield or 0
    e.maxShield = e.maxShield or e.shield
    e.armor = e.armor or 0
    e.healthType = e.healthType or 'FLESH'
    if e.maxShield and e.maxShield > 0 then
        e.shieldType = e.shieldType or 'SHIELD'
    end
    if e.armor and e.armor > 0 then
        e.armorType = e.armorType or 'FERRITE_ARMOR'
    end
    if e.shieldDelayTimer == nil then e.shieldDelayTimer = 0 end
end

local function getEffectiveArmor(e)
    local armor = (e and e.armor) or 0
    if e and e.status then
        if e.status.heatTimer and e.status.heatTimer > 0 then armor = armor * 0.5 end
    end
    if armor < 0 then armor = 0 end
    return armor
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

local function chooseWeighted(pool)
    local total = 0
    for _, it in ipairs(pool or {}) do
        total = total + (it.w or 0)
    end
    if total <= 0 then return pool and pool[1] end
    local r = math.random() * total
    for _, it in ipairs(pool) do
        r = r - (it.w or 0)
        if r <= 0 then return it end
    end
    return pool[#pool]
end

function enemies.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
    if not effectType or not e then return end
    if type(effectType) ~= 'string' then return end
    ensureStatus(e)

    local tenacity = clamp(e.tenacity or 0, 0, 0.95)
    local hardCcImmune = e.hardCcImmune or false
    local ccMult = 1 - tenacity

    local might = 1
    if state and state.player and state.player.stats and state.player.stats.might then
        might = state.player.stats.might
    end

    local effect = string.upper(effectType)
    if effect == 'FREEZE' then
        if effectData and (effectData.fullFreeze or effectData.forceFreeze) then
            local dur = effectData.freezeDuration or effectData.duration or 1.2
            if hardCcImmune then
                -- boss-style CC resistance: strong cold, but never full freeze
                local softDur = dur * (0.4 + 0.6 * ccMult)
                if softDur > 0 then
                    e.status.coldTimer = math.max(e.status.coldTimer or 0, softDur)
                    e.status.coldStacks = math.min(10, (e.status.coldStacks or 0) + 2)
                end
            else
                dur = dur * ccMult
                if dur > 0 then
                    e.status.frozen = true
                    local remaining = e.status.frozenTimer or 0
                    e.status.frozenTimer = math.max(dur, remaining)
                    e.speed = 0
                end
            end
            if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
            if state.spawnAreaField then state.spawnAreaField('freeze', e.x, e.y, (e.size or 16) * 2.2, 0.55, 1) end
        elseif e.status.frozen then
            local freezeDur = (effectData and effectData.freezeDuration) or (effectData and effectData.duration) or 1.2
            if hardCcImmune then
                local softDur = freezeDur * (0.35 + 0.65 * ccMult)
                if softDur > 0 then
                    e.status.coldTimer = math.max(e.status.coldTimer or 0, softDur)
                    e.status.coldStacks = math.min(10, (e.status.coldStacks or 0) + 1)
                end
                e.status.frozen = false
                e.status.frozenTimer = nil
            else
                freezeDur = freezeDur * ccMult
                if freezeDur > 0 then
                    local remaining = e.status.frozenTimer or 0
                    e.status.frozenTimer = math.max(freezeDur, remaining)
                    e.speed = 0
                end
            end
            if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
            if state.spawnAreaField then state.spawnAreaField('freeze', e.x, e.y, (e.size or 16) * 2.2, 0.55, 1) end
        else
            local dur = (effectData and effectData.duration) or 6.0
            e.status.coldTimer = math.max(e.status.coldTimer or 0, dur)
            e.status.coldStacks = math.min(10, (e.status.coldStacks or 0) + 1)
            if e.status.coldStacks >= 10 then
                if hardCcImmune then
                    -- prevent full freeze on bosses; keep it as heavy slow feedback
                    e.status.coldStacks = 6
                    e.status.coldTimer = math.max(e.status.coldTimer or 0, 1.2)
                else
                    e.status.frozen = true
                    local freezeDur = (effectData and effectData.freezeDuration) or 2.0
                    freezeDur = freezeDur * ccMult
                    if freezeDur > 0 then
                        e.status.frozenTimer = math.max(freezeDur, e.status.frozenTimer or 0)
                        e.speed = 0
                        e.status.coldStacks = 0
                        e.status.coldTimer = 0
                    end
                end
                if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
                if state.spawnAreaField then state.spawnAreaField('freeze', e.x, e.y, (e.size or 16) * 2.4, 0.65, 1) end
            else
                local stacks = e.status.coldStacks or 0
                local slowPct = 0.25 + math.max(0, stacks - 1) * 0.05
                if slowPct > 0.7 then slowPct = 0.7 end
                local mult = 1 - slowPct
                e.speed = (e.baseSpeed or e.speed) * mult
            end
        end
    elseif effect == 'OIL' then
        e.status.oiled = true
        e.status.oiledTimer = math.max((effectData and effectData.duration) or 6.0, 0)
        if state.spawnEffect then state.spawnEffect('oil', e.x, e.y) end
    elseif effect == 'BLEED' then
        local dur = (effectData and effectData.duration) or 6.0
        e.status.bleedTimer = math.max(e.status.bleedTimer or 0, dur)
        e.status.bleedStacks = (e.status.bleedStacks or 0) + 1
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.35)
        e.status.bleedDps = (e.status.bleedDps or 0) + addDps
        e.status.bleedAcc = e.status.bleedAcc or 0
        if state.spawnEffect then state.spawnEffect('bleed', e.x, e.y) end
    elseif effect == 'FIRE' then
        -- Heat proc: 50% armor reduction during heatTimer
        local heatDur = (effectData and effectData.heatDuration) or (effectData and effectData.duration) or 6.0
        e.status.heatTimer = math.max(e.status.heatTimer or 0, heatDur)
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.5)
        e.status.heatDps = (e.status.heatDps or 0) + addDps
        e.status.heatAcc = e.status.heatAcc or 0

        -- Ignite / burn DoT remains tied to oil synergy (current balance)
        if e.status.oiled then
            e.status.burnTimer = 5
            e.status.oiled = false
            e.status.oiledTimer = nil
            e.status.burnDps = math.max(1, (e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.03 * might)
            if state.spawnEffect then state.spawnEffect('fire', e.x, e.y) end
        end
    elseif effect == 'HEAVY' then
        if e.status.frozen then
            local extra = math.floor((baseDamage or 0) * 2)
            -- Fallback: if base damage is 0 (e.g. debug tool), deal 10% max HP damage
            if extra <= 0 then
                extra = math.floor((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.1)
            end
            if extra > 0 then enemies.damageEnemy(state, e, extra, false, 0, false) end
            e.status.frozen = false
            e.status.frozenTimer = nil
            e.speed = e.baseSpeed or e.speed
            if state.playSfx then state.playSfx('glass') end
        else
            local dur = (effectData and effectData.duration) or 0.35
            if hardCcImmune then
                dur = 0
            else
                dur = dur * ccMult
            end
            local remaining = e.status.impactTimer or 0
            if dur > 0 then
                e.status.impactTimer = math.max(dur, remaining)
            end
            if remaining <= 0 and state and state.spawnEffect and dur > 0 then
                local s = 1.0
                if e.size and e.size > 0 then s = math.max(0.8, math.min(1.6, (e.size / 16) * 0.95)) end
                state.spawnEffect('impact_hit', e.x, e.y, s)
            end
        end
    elseif effect == 'STATIC' then
        local dur = math.max((effectData and effectData.duration) or 3.0, 0)
        local radius = (effectData and (effectData.radius or effectData.range)) or 140
        e.status.static = true
        e.status.staticTimer = math.max(e.status.staticTimer or 0, dur)
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.5)
        e.status.staticDps = (e.status.staticDps or 0) + addDps
        e.status.staticRadius = math.max(e.status.staticRadius or 0, radius)
        e.status.staticAcc = e.status.staticAcc or 0
        -- Prevent perma-stun loops: apply a short stun with a lockout instead of refreshing for full duration.
        if (e.status.shockLockout or 0) <= 0 then
            local stun = (effectData and effectData.stunDuration) or 0.45
            if hardCcImmune then
                stun = 0
            else
                stun = stun * ccMult
            end
            if stun > 0 then
                e.status.shockTimer = math.max(e.status.shockTimer or 0, stun)
            end
            e.status.shockLockout = 0.9
        end
        if state.spawnEffect then state.spawnEffect('static', e.x, e.y) end
    elseif effect == 'MAGNETIC' then
        local dur = (effectData and effectData.duration) or 6.0
        e.status.magneticStacks = math.min(10, (e.status.magneticStacks or 0) + 1)
        e.status.magneticTimer = math.max(e.status.magneticTimer or 0, dur)
        local stacks = e.status.magneticStacks
        local bonus = math.min(2.25, 0.75 + stacks * 0.25)
        e.status.magneticMult = 1 + bonus
        e.status.shieldLocked = true
        if state.spawnEffect then state.spawnEffect('static', e.x, e.y) end
    elseif effect == 'CORROSIVE' then
        e.baseArmor = e.baseArmor or e.armor or 0
        e.status.corrosiveStacks = math.min(10, (e.status.corrosiveStacks or 0) + 1)
        local stacks = e.status.corrosiveStacks
        local stripPct = 0.26 + math.max(0, stacks - 1) * 0.06
        if stripPct > 0.8 then stripPct = 0.8 end
        local newArmor = math.floor((e.baseArmor or 0) * (1 - stripPct) + 0.5)
        if newArmor < 0 then newArmor = 0 end
        e.armor = newArmor
    elseif effect == 'VIRAL' then
        e.status.viralStacks = math.min(10, (e.status.viralStacks or 0) + 1)
        e.status.viralTimer = math.max((effectData and effectData.duration) or 6.0, e.status.viralTimer or 0)
    elseif effect == 'PUNCTURE' then
        local dur = (effectData and effectData.duration) or 6.0
        e.status.punctureStacks = math.min(10, (e.status.punctureStacks or 0) + 1)
        e.status.punctureTimer = math.max(e.status.punctureTimer or 0, dur)
    elseif effect == 'BLAST' then
        local dur = (effectData and effectData.duration) or 6.0
        e.status.blastStacks = math.min(10, (e.status.blastStacks or 0) + 1)
        e.status.blastTimer = math.max(e.status.blastTimer or 0, dur)
    elseif effect == 'GAS' then
        local dur = (effectData and effectData.duration) or 6.0
        e.status.gasTimer = math.max(e.status.gasTimer or 0, dur)
        local radius = (effectData and (effectData.radius or effectData.range)) or 100
        e.status.gasRadius = math.max(e.status.gasRadius or 0, radius)
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.5)
        e.status.gasDps = (e.status.gasDps or 0) + addDps
        e.status.gasAcc = e.status.gasAcc or 0
    elseif effect == 'RADIATION' then
        local dur = (effectData and effectData.duration) or 12.0
        e.status.radiationTimer = math.max(e.status.radiationTimer or 0, dur)
        e.status.radiationTargetTimer = 0
        e.status.radiationTarget = nil
        e.status.radiationAngle = math.random() * 6.28
    elseif effect == 'TOXIN' then
        e.status.toxinTimer = math.max((effectData and effectData.duration) or 6.0, e.status.toxinTimer or 0)
        local base = baseDamage or ((e.maxHealth or e.health or 0) * 0.05 * might)
        e.status.toxinDps = math.max(1, base * 0.5)
        e.status.toxinAcc = 0
    end
end

function enemies.spawnEnemy(state, type, isElite, spawnX, spawnY, opts)
    opts = opts or {}
    local def = enemyDefs[type] or enemyDefs.skeleton
    local color = def.color and {def.color[1], def.color[2], def.color[3]} or {1,1,1}
    local hp = def.hp
    local shield = def.shield or 0
    local armor = def.armor or 0
    local size = def.size
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

    local hpScale = 1 + math.min((state.gameTimer or 0), 300) / 300 -- cap at ~2x at 5min
    if hpScale > 2.5 then hpScale = 2.5 end
    hp = hp * hpScale
    shield = shield * hpScale

    if isElite then
        hp = hp * 5
        shield = shield * 5
        size = size * 1.5
        tenacity = math.max(tenacity, 0.15)

        local mods = {}
        table.insert(mods, {key = 'swift', w = 3})
        table.insert(mods, {key = 'brutal', w = 3})
        if shield > 0 then table.insert(mods, {key = 'warded', w = 2}) end
        if def.shootInterval or (def.attacks and def.attacks.burst) then
            table.insert(mods, {key = 'sniper', w = 2})
        end
        local pick = chooseWeighted(mods)
        eliteMod = pick and pick.key or 'brutal'

        if eliteMod == 'swift' then
            speed = speed * 1.35
            eliteWindupMult = 0.9
            eliteDamageMult = 1.05
            color = {0.25, 1.0, 0.95}
        elseif eliteMod == 'warded' then
            shield = shield * 1.6 + 40
            eliteDamageMult = 1.10
            shieldRegenDelay = SHIELD_REGEN_DELAY * 0.8
            shieldRegenRate = SHIELD_REGEN_RATE * 1.35
            color = {0.35, 0.65, 1.0}
        elseif eliteMod == 'sniper' then
            eliteDamageMult = 1.15
            eliteBulletSpeedMult = 1.35
            if shootInterval then shootInterval = shootInterval * 0.75 end
            color = {0.85, 0.35, 1.0}
        else
            eliteMod = 'brutal'
            eliteDamageMult = 1.35
            color = {1.0, 0.25, 0.15}
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
        size = size,
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
        facing = 1
    })
    if state.loadMoveAnimationFromFolder then
        local animKey = def.animKey or def.animName or type
        local anim = state.loadMoveAnimationFromFolder(animKey, 4, 8)
        if anim then state.enemies[#state.enemies].anim = anim end
    end
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
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        ensureStatus(e)
        local def = enemyDefs[e.kind] or enemyDefs.skeleton
        local tenacity = clamp(e.tenacity or 0, 0, 0.95)
        local hardCcImmune = (e.hardCcImmune == true) or (def and def.hardCcImmune == true) or false

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
                e.status.staticAcc = (e.status.staticAcc or 0) + (e.status.staticDps or 0) * dt
                if e.status.staticAcc >= 1 then
                    local tick = math.floor(e.status.staticAcc)
                    e.status.staticAcc = e.status.staticAcc - tick
                    if tick > 0 then
                        local radius = e.status.staticRadius or 140
                        local r2 = radius * radius
                        applyDotTick(state, e, 'ELECTRIC', tick)
                        local shown = 0
                        local world = state.world
                        local useLos = world and world.enabled and world.segmentHitsWall
                        for _, o in ipairs(state.enemies) do
                            if o ~= e and o.health > 0 then
                                local dx = o.x - e.x
                                local dy = o.y - e.y
                                if dx*dx + dy*dy <= r2 then
                                    local blocked = false
                                    if useLos and world:segmentHitsWall(e.x, e.y, o.x, o.y) then
                                        blocked = true
                                    end
                                    
                                    if not blocked then
                                        ensureStatus(o)
                                        local applied = false
                                        if (o.status.staticSplashCd or 0) <= 0 then
                                            applyDotTick(state, o, 'ELECTRIC', tick, {noText=true})
                                            o.status.staticSplashCd = 0.25
                                            applied = true
                                        end
                                        if applied and shown < 6 then
                                            table.insert(state.chainLinks, {x1=e.x, y1=e.y, x2=o.x, y2=o.y})
                                            shown = shown + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if e.status.staticTimer and e.status.staticTimer <= 0 then
                e.status.static = false
                e.status.staticTimer = nil
                e.status.staticDps = nil
                e.status.staticRadius = nil
                e.status.staticAcc = nil
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
                    local strength = 5
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
                                spriteKey = spriteKey
                            })
                        end
                        e.attack = nil
                        e.attackCooldown = atk.cooldown or 2.5
                    end
                end
            end
        end

        -- start a new telegraphed attack if ready (multi-attack enemies pick by weights + range)
        if attacks and not stunned and not e.attack and (e.attackCooldown or 0) <= 0 then
            local dx = targetX - e.x
            local dy = targetY - e.y
            local distSq = dx * dx + dy * dy

            local pool = {}
            for key, cfg in pairs(attacks) do
                if type(cfg) == 'table' then
                    local minR = cfg.rangeMin or 0
                    local maxR = cfg.range or cfg.rangeMax or cfg.maxRange or 999999
                    if distSq >= minR * minR and distSq <= maxR * maxR then
                        local w = cfg.w or cfg.weight or 1
                        if e.isBoss then
                            local phase = e.bossPhase or 1
                            if key == 'burst' then
                                if phase == 1 then w = w * 1.20
                                elseif phase == 3 then w = w * 0.85 end
                            elseif key == 'slam' then
                                if phase == 2 then w = w * 1.15 end
                            elseif key == 'charge' then
                                if phase == 3 then w = w * 1.25 end
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
                elseif key == 'burst' then
                    local windup = math.max(0.45, (cfg.windup or 0.6) * windupMult)
                    local count = cfg.count or 5
                    local spread = cfg.spread or 0.8
                    local bulletSpeed = (cfg.bulletSpeed or (e.bulletSpeed or 180)) * (e.eliteBulletSpeedMult or 1)
                    local bulletDamage = (cfg.bulletDamage or (e.bulletDamage or 10)) * eliteDamageMult
                    local bulletLife = cfg.bulletLife or (e.bulletLife or 5)
                    local bulletSize = cfg.bulletSize or (e.bulletSize or 10)
                    local cooldown = cfg.cooldown or 2.5
                    local len = cfg.telegraphLength or cfg.distance or 360
                    local width = cfg.telegraphWidth or 46
                    if e.isBoss then
                        windup = math.max(0.55, windup * (1 - phaseK * 0.05))
                        count = count + phaseK * 2
                        spread = spread * (1 + phaseK * 0.16)
                        bulletSpeed = bulletSpeed * (1 + phaseK * 0.06)
                        bulletDamage = bulletDamage * (1 + phaseK * 0.10)
                        len = len * (1 + phaseK * 0.05)
                        width = width * (1 + phaseK * 0.10)
                        cooldown = math.max(1.2, cooldown * (1 - phaseK * 0.10))
                    end
                    e.attack = {
                        type = 'burst',
                        phase = 'windup',
                        timer = windup,
                        interruptible = interruptible,
                        ang = angToTarget, -- lock direction for fairness/readability
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
                    if state.spawnTelegraphLine then
                        local ex, ey = e.x, e.y
                        state.spawnTelegraphLine(ex, ey, ex + math.cos(angToTarget) * len, ey + math.sin(angToTarget) * len, width, windup, lineOpts)
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
            local vx = (math.cos(moveAng) * e.speed + pushX)
            local vy = (math.sin(moveAng) * e.speed + pushY)
            if world and world.enabled and world.moveCircle then
                e.x, e.y = world:moveCircle(e.x, e.y, (e.size or 16) / 2, vx * dt, vy * dt)
            else
                e.x = e.x + vx * dt
                e.y = e.y + vy * dt
            end
        end

        local pDist = math.sqrt((p.x - e.x)^2 + (p.y - e.y)^2)
        local playerRadius = (p.size or 20) / 2
        local enemyRadius = (e.size or 16) / 2
        local inChargeDash = e.attack and e.attack.type == 'charge' and e.attack.phase == 'dash'
        local contactGrace = (e.noContactDamageTimer or 0) > 0
        if not inChargeDash and pDist < (playerRadius + enemyRadius) and not e.noContactDamage and not contactGrace then
            local dmgMult = 1 - getPunctureReduction(e)
            if dmgMult < 0.25 then dmgMult = 0.25 end
            local baseContact = ((def and def.contactDamage) or 10) * (e.eliteDamageMult or 1)
            player.hurt(state, baseContact * dmgMult)
        end
        if not inChargeDash and not e.noContactDamage and not contactGrace then
            local pet = pets.getActive(state)
            if pet and not pet.downed then
                local dmgMult = 1 - getPunctureReduction(e)
                if dmgMult < 0.25 then dmgMult = 0.25 end
                local baseContact = ((def and def.contactDamage) or 10) * (e.eliteDamageMult or 1)
                local dist = math.sqrt(((pet.x or 0) - e.x) ^ 2 + ((pet.y or 0) - e.y) ^ 2)
                local pr = (pet.size or 18) / 2
                if dist < (pr + enemyRadius) then
                    pets.hurt(state, pet, baseContact * dmgMult)
                end
            end
        end

        if e.health <= 0 then
            if e.isDummy then
                resetDummy(e)
            else
                if state and state.augments and state.augments.dispatch then
                    state.augments.dispatch(state, 'onKill', {enemy = e, player = state.player, lastDamage = e.lastDamage})
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
                            table.insert(state.texts, {x = e.x, y = e.y - 110, text = "BOSS DOWN! CLAIM REWARD", color = {1, 0.85, 0.35}, life = 2.2})
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
                        state.directorState = state.directorState or {}
                        state.directorState.bossDefeated = true
                        logger.kill(state, e)
                        table.remove(state.enemies, i)
                        isBossDefeated = true
                    end
                end

                if not isBossDefeated then
                    if not e.noDrops then
                        local exploreMode = (state.runMode == 'explore') or (state.world and state.world.enabled)
                        if exploreMode then
                            local gain = e.isElite and 6 or 1
                            if not e.isElite and math.random() < 0.12 then gain = gain + 1 end
                            if state.gainGold then
                                state.gainGold(gain, {source = 'kill', enemy = e, x = e.x, y = e.y - 20, life = 0.55})
                            else
                                state.runCurrency = (state.runCurrency or 0) + gain
                                table.insert(state.texts, {x = e.x, y = e.y - 20, text = "+" .. tostring(gain) .. " GOLD", color = {0.95, 0.9, 0.45}, life = 0.55})
                            end
        
                            if e.isElite and state.floorPickups then
                                local pet = pets.getActive(state)
                                if pet and not pet.downed and (pet.module or 'default') == 'default' then
                                    if math.random() < 0.35 then
                                        table.insert(state.floorPickups, {x = e.x + 26, y = e.y + 8, size = 14, kind = 'pet_module_chip'})
                                    end
                                end
                            end
                        else
                            local roomsMode = (state.runMode == 'rooms')
                            local useXp = true
                            if roomsMode and state.rooms and state.rooms.useXp == false then
                                useXp = false
                            end
            
                            if e.isElite then
                                local dropChest = true
                                if roomsMode and state.rooms and state.rooms.eliteDropsChests == false then
                                    dropChest = false
                                end
                                if dropChest then
                                    table.insert(state.chests, {x=e.x, y=e.y, w=20, h=20})
                                else
                                    if useXp then
                                        if math.random() < 0.35 then
                                            local kinds = roomsMode and {'magnet'} or {'chicken', 'magnet'}
                                            local kind = kinds[math.random(#kinds)]
                                            table.insert(state.floorPickups, {x=e.x, y=e.y, size=14, kind=kind})
                                        else
                                            table.insert(state.gems, {x=e.x, y=e.y, value=3})
                                        end
                                    else
                                        local room = tonumber(state.rooms and state.rooms.roomIndex) or 1
                                        local gain = 4 + math.max(0, math.min(6, room))
                                        if state.gainGold then
                                            state.gainGold(gain, {source = 'kill', enemy = e, x = e.x, y = e.y - 20, life = 0.65})
                                        else
                                            state.runCurrency = (state.runCurrency or 0) + gain
                                            table.insert(state.texts, {x = e.x, y = e.y - 20, text = "+" .. tostring(gain) .. " GOLD", color = {0.95, 0.9, 0.45}, life = 0.65})
                                        end
                                    end
                                end
                            else
                                if useXp then
                                    if math.random() < 0.01 then
                                        local kinds = roomsMode and {'magnet'} or {'chicken', 'magnet'}
                                        local kind = kinds[math.random(#kinds)]
                                        table.insert(state.floorPickups, {x=e.x, y=e.y, size=14, kind=kind})
                                    else
                                        table.insert(state.gems, {x=e.x, y=e.y, value=1})
                                    end
                                else
                                    local gain = 1
                                    if math.random() < 0.12 then gain = 2 end
                                    if state.gainGold then
                                        state.gainGold(gain, {source = 'kill', enemy = e, x = e.x, y = e.y - 20, life = 0.55})
                                    else
                                        state.runCurrency = (state.runCurrency or 0) + gain
                                        table.insert(state.texts, {x = e.x, y = e.y - 20, text = "+" .. tostring(gain) .. " GOLD", color = {0.95, 0.9, 0.45}, life = 0.55})
                                    end
                                end
                            end
                        end
                    end
                    logger.kill(state, e)
                    table.remove(state.enemies, i)
                end
            end
        end
    end
end

return enemies
