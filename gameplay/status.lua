local status = {}

-- 辅助函数：根据状态构建伤害倍率
function status.buildDamageModsForTicks(e)
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

-- 确保敌人有状态表并初始化基础属性
function status.ensureStatus(e)
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

-- 获取受状态影响后的有效护甲
function status.getEffectiveArmor(e)
    local armor = (e and e.armor) or 0
    if e and e.status then
        if e.status.heatTimer and e.status.heatTimer > 0 then armor = armor * 0.5 end
    end
    if armor < 0 then armor = 0 end
    return armor
end

-- 获取穿刺减伤率
function status.getPunctureReduction(e)
    if not e or not e.status or not e.status.punctureStacks or e.status.punctureStacks <= 0 then return 0 end
    local stacks = math.min(10, e.status.punctureStacks)
    local red = 0.3 + (stacks - 1) * 0.05
    if red > 0.75 then red = 0.75 end
    return red
end

-- 获取爆炸减伤率
function status.getBlastReduction(e)
    if not e or not e.status or not e.status.blastStacks or e.status.blastStacks <= 0 then return 0 end
    local stacks = math.min(10, e.status.blastStacks)
    local red = 0.3 + (stacks - 1) * 0.05
    if red > 0.75 then red = 0.75 end
    return red
end

-- 应用状态效果逻辑
function status.applyStatus(state, e, effectType, baseDamage, weaponTags, effectData)
    if not effectType or not e then return end
    if type(effectType) ~= 'string' then return end
    status.ensureStatus(e)

    local function clamp(x, lo, hi)
        if x == nil then return lo end
        if x < lo then return lo end
        if x > hi then return hi end
        return x
    end

    local tenacity = clamp(e.tenacity or 0, 0, 0.95)
    local hardCcImmune = e.hardCcImmune or false
    local ccMult = 1 - tenacity

    local might = 1
    if state and state.player and state.player.stats and state.player.stats.might then
        might = state.player.stats.might
    end

    local enemies = require('gameplay.enemies')
    local effect = string.upper(effectType)
    
    if effect == 'FREEZE' then
        if effectData and (effectData.fullFreeze or effectData.forceFreeze) then
            local dur = effectData.freezeDuration or effectData.duration or 1.2
            if hardCcImmune then
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
        local heatDur = (effectData and effectData.heatDuration) or (effectData and effectData.duration) or 6.0
        e.status.heatTimer = math.max(e.status.heatTimer or 0, heatDur)
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.5)
        e.status.heatDps = (e.status.heatDps or 0) + addDps
        e.status.heatAcc = e.status.heatAcc or 0

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
            if hardCcImmune then dur = 0 else dur = dur * ccMult end
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
        local hadStatic = (e.status.staticTimer or 0) > 0
        e.status.static = true
        e.status.staticTimer = math.max(e.status.staticTimer or 0, dur)
        local base = baseDamage or ((e.maxHealth or e.maxHp or e.health or e.hp or 0) * 0.05 * might)
        local addDps = math.max(1, base * 0.5)
        e.status.staticDps = (e.status.staticDps or 0) + addDps
        e.status.staticRadius = math.max(e.status.staticRadius or 0, radius)
        e.status.staticTickTimer = e.status.staticTickTimer or 1.0
        if (e.status.shockLockout or 0) <= 0 then
            local stun = (effectData and effectData.stunDuration) or 0.45
            if hardCcImmune then stun = 0 else stun = stun * ccMult end
            if stun > 0 then
                e.status.shockTimer = math.max(e.status.shockTimer or 0, stun)
            end
            e.status.shockLockout = 0.9
        end
        if state.spawnEffect then state.spawnEffect('static', e.x, e.y) end
        if not hadStatic and state and state.playSfx and (state._staticSfxCooldown or 0) <= 0 then
            state.playSfx('static')
            state._staticSfxCooldown = 0.9
        end
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

return status
