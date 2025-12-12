local player = require('player')
local enemyDefs = require('enemy_defs')
local logger = require('logger')

local enemies = {}

local SHIELD_REGEN_DELAY = 2.5
local SHIELD_REGEN_RATE = 0.25 -- fraction of max shield per second

local function getPunctureReduction(e)
    if not e or not e.status or not e.status.punctureStacks or e.status.punctureStacks <= 0 then return 0 end
    local stacks = math.min(10, e.status.punctureStacks)
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
            blastTimer = 0,
            gasTimer = 0,
            gasDps = 0,
            gasRadius = 0,
            gasAcc = 0,
            radiationTimer = 0,
            radiationTargetTimer = 0,
            radiationTarget = nil,
            radiationAngle = 0
        }
    end
    e.baseSpeed = e.baseSpeed or e.speed
    e.baseArmor = e.baseArmor or e.armor or 0
    e.health = e.health or e.hp
    e.maxHealth = e.maxHealth or e.maxHp or e.hp
    e.maxHp = e.maxHealth
    e.hp = e.health
    e.shield = e.shield or 0
    e.maxShield = e.maxShield or e.shield
    e.armor = e.armor or 0
    if e.shieldDelayTimer == nil then e.shieldDelayTimer = 0 end
end

local function getEffectiveArmor(e)
    local armor = (e and e.armor) or 0
    if e and e.status then
        if e.status.heatArmorLoss then armor = armor - e.status.heatArmorLoss end
    end
    if armor < 0 then armor = 0 end
    return armor
end

local function applyArmorReduction(dmg, armor)
    if not armor or armor <= 0 then return dmg end
    local dr = armor / (armor + 300)
    if dr > 0.9 then dr = 0.9 end
    return dmg * (1 - dr)
end

function enemies.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
    if not effectType or not e then return end
    if type(effectType) ~= 'string' then return end
    ensureStatus(e)

    local might = 1
    if state and state.player and state.player.stats and state.player.stats.might then
        might = state.player.stats.might
    end

    local effect = string.upper(effectType)
    if effect == 'FREEZE' then
        if effectData and (effectData.fullFreeze or effectData.forceFreeze) then
            e.status.frozen = true
            local dur = effectData.freezeDuration or effectData.duration or 1.2
            local remaining = e.status.frozenTimer or 0
            e.status.frozenTimer = math.max(dur, remaining)
            e.speed = 0
            if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
        elseif e.status.frozen then
            local freezeDur = (effectData and effectData.freezeDuration) or (effectData and effectData.duration) or 1.2
            local remaining = e.status.frozenTimer or 0
            e.status.frozenTimer = math.max(freezeDur, remaining)
            e.speed = 0
            if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
        else
            local dur = (effectData and effectData.duration) or 6.0
            e.status.coldTimer = math.max(e.status.coldTimer or 0, dur)
            e.status.coldStacks = math.min(10, (e.status.coldStacks or 0) + 1)
            if e.status.coldStacks >= 10 then
                e.status.frozen = true
                local freezeDur = (effectData and effectData.freezeDuration) or (effectData and effectData.duration) or 6.0
                e.status.frozenTimer = math.max(freezeDur, e.status.frozenTimer or 0)
                e.speed = 0
                e.status.coldStacks = 0
                e.status.coldTimer = 0
                if state.spawnEffect then state.spawnEffect('freeze', e.x, e.y) end
            else
                local stacks = e.status.coldStacks or 0
                local mult = 0.75 ^ stacks
                if mult < 0.1 then mult = 0.1 end
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
        -- Heat proc: temporary 50% armor reduction always applies
        local lossTarget = (e.armor or 0) * 0.5
        if lossTarget > (e.status.heatArmorLoss or 0) then
            e.status.heatArmorLoss = lossTarget
        end
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
            local remaining = e.status.impactTimer or 0
            e.status.impactTimer = math.max(dur, remaining)
        end
    elseif effect == 'STATIC' then
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local data = {
            duration = math.max((effectData and effectData.duration) or 2.0, 0),
            range = (effectData and effectData.range) or 160,
            remaining = (effectData and effectData.chain) or 3,
            allowRepeat = (effectData and effectData.allowRepeat) or false,
            stunDuration = (effectData and effectData.stunDuration) or 3.0,
            baseDamage = base,
            tickDamage = math.max(1, math.floor(base * 0.5 + 0.5)),
            tick = 0.35
        }
        if not data.allowRepeat then data.visited = {} end
        if data.visited then data.visited[e] = true end
        e.status.static = true
        e.status.staticTimer = 0
        e.status.staticDuration = data.duration
        e.status.staticRange = data.range
        e.status.staticData = data
        e.status.shockTimer = math.max(e.status.shockTimer or 0, data.stunDuration or 0.6)
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
        local dur = (effectData and effectData.duration) or 0.6
        local remaining = e.status.blastTimer or 0
        e.status.blastTimer = math.max(dur, remaining)
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
        local dur = (effectData and effectData.duration) or 6.0
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

function enemies.spawnEnemy(state, type, isElite, spawnX, spawnY)
    local def = enemyDefs[type] or enemyDefs.skeleton
    local color = def.color and {def.color[1], def.color[2], def.color[3]} or {1,1,1}
    local hp = def.hp
    local shield = def.shield or 0
    local armor = def.armor or 0
    local size = def.size
    local speed = def.speed

    local ang = math.random() * 6.28
    local d = def.spawnDistance or 500
    local x = spawnX or (state.player.x + math.cos(ang) * d)
    local y = spawnY or (state.player.y + math.sin(ang) * d)

    local hpScale = 1 + math.min((state.gameTimer or 0), 300) / 300 -- cap at ~2x at 5min
    if hpScale > 2.5 then hpScale = 2.5 end
    hp = hp * hpScale
    shield = shield * hpScale

    if isElite then
        hp = hp * 5
        shield = shield * 5
        size = size * 1.5
        color = {1, 0, 0}
    end

    table.insert(state.enemies, {
        x = x,
        y = y,
        hp = hp,
        health = hp,
        maxHealth = hp,
        shield = shield,
        maxShield = shield,
        armor = armor,
        noContactDamage = def.noContactDamage,
        noDrops = def.noDrops,
        isDummy = def.isDummy,
        speed = speed,
        color = color,
        size = size,
        isElite = isElite,
        kind = type,
        shootInterval = def.shootInterval,
        shootTimer = def.shootInterval,
        bulletSpeed = def.bulletSpeed,
        bulletDamage = def.bulletDamage,
        bulletLife = def.bulletLife,
        bulletSize = def.bulletSize,
        facing = 1
    })
    if state.loadMoveAnimationFromFolder then
        local anim = state.loadMoveAnimationFromFolder(type, 4, 8)
        if anim then state.enemies[#state.enemies].anim = anim end
    end
    ensureStatus(state.enemies[#state.enemies])
end

local function resetDummy(e)
    if not e or not e.isDummy then return end
    e.health = e.maxHealth or e.health or 0
    e.hp = e.health
    e.shield = e.maxShield or e.shield or 0
    e.status = nil
    e.shieldDelayTimer = 0
    ensureStatus(e)
end

function enemies.findNearestEnemy(state, maxDist)
    local t, m = nil, (maxDist or 999999) ^ 2
    for _, e in ipairs(state.enemies) do
        local d = (state.player.x - e.x)^2 + (state.player.y - e.y)^2
        if d < m then m = d; t = e end
    end
    return t
end

function enemies.damageEnemy(state, e, dmg, knock, kForce, isCrit, opts)
    opts = opts or {}
    ensureStatus(e)
    local incoming = dmg or 0
    if incoming <= 0 then return 0 end

    e.flashTimer = 0.1
    if state.playSfx then state.playSfx('hit') end

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
    return appliedTotal
end

function enemies.update(state, dt)
    local p = state.player
    local playerMight = (state.player and state.player.stats and state.player.stats.might) or 1
    state.chainLinks = {}
    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        ensureStatus(e)

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
                local mult = 0.75 ^ stacks
                if mult < 0.1 then mult = 0.1 end
                e.speed = (e.baseSpeed or e.speed) * mult
            end
        end

        if e.anim then e.anim:update(dt) end

        if e.status.blastTimer and e.status.blastTimer > 0 then
            e.status.blastTimer = e.status.blastTimer - dt
            if e.status.blastTimer <= 0 then
                e.status.blastTimer = nil
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
                if burnDmg > 0 then enemies.damageEnemy(state, e, burnDmg, false, 0) end
            end
            if e.status.burnTimer < 0 then e.status.burnTimer = 0 end
        end

        if e.status.bleedTimer and e.status.bleedTimer > 0 then
            e.status.bleedTimer = e.status.bleedTimer - dt
            e.status.bleedAcc = (e.status.bleedAcc or 0) + (e.status.bleedDps or 0) * dt
            if e.status.bleedAcc >= 1 then
                local tick = math.floor(e.status.bleedAcc)
                e.status.bleedAcc = e.status.bleedAcc - tick
                if tick > 0 then
                    enemies.damageEnemy(state, e, tick, false, 0, false, {bypassShield=true, ignoreArmor=true})
                end
            end
            if e.status.bleedTimer <= 0 then
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

        if e.status.static then
            local data = e.status.staticData or {}
            data.duration = (data.duration or 0) - dt
            e.status.staticTimer = (e.status.staticTimer or 0) - dt
            if data.duration <= 0 or (data.remaining or 0) <= 0 then
                e.status.static = false
                e.status.staticTimer = nil
                e.status.staticDuration = nil
                e.status.staticRange = nil
                e.status.staticData = nil
            elseif e.status.staticTimer <= 0 then
                local visited = data.visited or {}
                if not data.allowRepeat then
                    visited[e] = true
                    data.visited = visited
                end
                local nearest, dist2 = nil, (data.range or e.status.staticRange or 160) ^ 2
                for j, o in ipairs(state.enemies) do
                    if i ~= j then
                        if data.allowRepeat or not visited[o] then
                            local dx = o.x - e.x
                            local dy = o.y - e.y
                            local d2 = dx*dx + dy*dy
                            if d2 < dist2 then
                                dist2 = d2
                                nearest = o
                            end
                        end
                    end
                end
                if nearest then
                    ensureStatus(nearest)
                    local staticDmg = data.tickDamage
                    if not staticDmg or staticDmg <= 0 then
                        local base = data.baseDamage or ((e.maxHealth or e.maxHp or 10) * 0.05 * playerMight)
                        staticDmg = math.max(1, math.floor(base * 0.5 + 0.5))
                    end
                    enemies.damageEnemy(state, nearest, staticDmg, false, 0)
                    if not data.allowRepeat then visited[nearest] = true end
                    data.remaining = (data.remaining or 1) - 1
                    table.insert(state.chainLinks, {x1=e.x, y1=e.y, x2=nearest.x, y2=nearest.y})
                    nearest.status.static = true
                    nearest.status.staticTimer = data.tick or 0.35
                    nearest.status.staticDuration = data.duration
                    nearest.status.staticRange = data.range
                    nearest.status.staticData = data
                    nearest.status.shockTimer = math.max(nearest.status.shockTimer or 0, data.stunDuration or 0.6)
                    if state.spawnEffect then state.spawnEffect('static', nearest.x, nearest.y) end
                    e.status.static = false
                    e.status.staticTimer = nil
                    e.status.staticDuration = nil
                    e.status.staticRange = nil
                    e.status.staticData = nil
                else
                    e.status.static = false
                    e.status.staticTimer = nil
                    e.status.staticDuration = nil
                    e.status.staticRange = nil
                    e.status.staticData = nil
                end
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
                if tick > 0 then enemies.damageEnemy(state, e, tick, false, 0) end
            end
            if e.status.heatTimer <= 0 then
                e.status.heatTimer = nil
                e.status.heatArmorLoss = 0
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
                enemies.damageEnemy(state, e, tick, false, 0, false, {bypassShield=true})
            end
            if e.status.toxinTimer <= 0 then
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
                    enemies.damageEnemy(state, e, tick, false, 0, false, {bypassShield=true})
                    for _, o in ipairs(state.enemies) do
                        if o ~= e then
                            local dx = o.x - e.x
                            local dy = o.y - e.y
                            if dx*dx + dy*dy <= r2 then
                                enemies.damageEnemy(state, o, tick, false, 0, false, {bypassShield=true, noText=true})
                            end
                        end
                    end
                end
            end
            if e.status.gasTimer <= 0 then
                e.status.gasTimer = nil
                e.status.gasDps = nil
                e.status.gasRadius = nil
                e.status.gasAcc = nil
            end
        end

        if e.maxShield and e.maxShield > 0 and not (e.status and e.status.shieldLocked) then
            e.shieldDelayTimer = (e.shieldDelayTimer or 0) + dt
            if e.shieldDelayTimer >= SHIELD_REGEN_DELAY and e.shield < e.maxShield then
                local regen = e.maxShield * SHIELD_REGEN_RATE * dt
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

        local stunned = e.status.frozen
            or (e.status.blastTimer and e.status.blastTimer > 0)
            or (e.status.impactTimer and e.status.impactTimer > 0)
            or (e.status.shockTimer and e.status.shockTimer > 0)
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

        if e.shootInterval and not stunned then
            e.shootTimer = (e.shootTimer or e.shootInterval) - dt
            if e.shootTimer <= 0 then
                local ang = angToTarget
                local spd = e.bulletSpeed or 180
                local spriteKey = nil
                if e.kind == 'plant' then spriteKey = 'plant_bullet' end
                local dmgMult = 1 - getPunctureReduction(e)
                if dmgMult < 0.25 then dmgMult = 0.25 end
                local bulletDmg = (e.bulletDamage or 10) * dmgMult
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

        local angle = angToTarget
        local dxToTarget = targetX - e.x
        if math.abs(dxToTarget) > 1 then
            e.facing = dxToTarget >= 0 and 1 or -1
        end
        if stunned then
            e.x = e.x + pushX * dt
            e.y = e.y + pushY * dt
        else
            e.x = e.x + (math.cos(angle) * e.speed + pushX) * dt
            e.y = e.y + (math.sin(angle) * e.speed + pushY) * dt
        end

        local pDist = math.sqrt((p.x - e.x)^2 + (p.y - e.y)^2)
        local playerRadius = (p.size or 20) / 2
        local enemyRadius = (e.size or 16) / 2
        if pDist < (playerRadius + enemyRadius) and not e.noContactDamage then
            local dmgMult = 1 - getPunctureReduction(e)
            if dmgMult < 0.25 then dmgMult = 0.25 end
            player.hurt(state, 10 * dmgMult)
        end

        if e.health <= 0 then
            if e.isDummy then
                resetDummy(e)
                goto continue_enemy
            end
            if not e.noDrops then
                if e.isElite then
                    table.insert(state.chests, {x=e.x, y=e.y, w=20, h=20})
                else
                    if math.random() < 0.01 then
                        local kinds = {'chicken','magnet','bomb'}
                        local kind = kinds[math.random(#kinds)]
                        table.insert(state.floorPickups, {x=e.x, y=e.y, size=14, kind=kind})
                    else
                        table.insert(state.gems, {x=e.x, y=e.y, value=1})
                    end
                end
            end
            logger.kill(state, e)
            table.remove(state.enemies, i)
        end
        ::continue_enemy::
    end
end

return enemies
