local effects = {}

local function loadImage(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then return img end
    return nil
end

function effects.init(state)
    state.effectSprites = {}
    state.hitEffects = {}
    state.screenWaves = {}
    state.areaFields = {}
    state.telegraphs = {}
    state.dashAfterimages = {}

    local effectScaleOverrides = {
        freeze = 0.4,
        oil = 0.2,
        fire = 0.5,
        static = 0.4,
        bleed = 0.2
    }

    local function loadEffectFrames(name, frameCount)
        frameCount = frameCount or 3
        local frames = {}
        for i = 1, frameCount do
            local img = loadImage(string.format('assets/effects/%s/%d.png', name, i))
            if img then
                img:setFilter('nearest', 'nearest')
                table.insert(frames, img)
            end
        end
        if #frames > 0 then
            local frameW = frames[1]:getWidth()
            local frameH = frames[1]:getHeight()
            local autoScale = frameW > 32 and (32 / frameW) or 1
            local defaultScale = effectScaleOverrides[name] or autoScale
            state.effectSprites[name] = {
                frames = frames,
                frameW = frameW,
                frameH = frameH,
                frameCount = #frames,
                duration = 0.3,
                defaultScale = defaultScale
            }
        end
    end

    local effectKeys = {'freeze','oil','fire','static','bleed'}
    for _, k in ipairs(effectKeys) do loadEffectFrames(k, 3) end

    local proceduralEffectDefs = {
        hit = { duration = 0.16, defaultScale = 1.0 },
        shock = { duration = 0.18, defaultScale = 1.0 },
        static_hit = { duration = 0.18, defaultScale = 1.0 },
        impact_hit = { duration = 0.16, defaultScale = 1.0 },
        ice_shatter = { duration = 0.20, defaultScale = 1.0 },
        ember = { duration = 0.18, defaultScale = 1.0 },

        toxin_hit = { duration = 0.18, defaultScale = 1.0 },
        gas_hit = { duration = 0.18, defaultScale = 1.0 },
        bleed_hit = { duration = 0.18, defaultScale = 1.0 },
        viral_hit = { duration = 0.18, defaultScale = 1.0 },
        corrosive_hit = { duration = 0.18, defaultScale = 1.0 },
        magnetic_hit = { duration = 0.18, defaultScale = 1.0 },
        blast_hit = { duration = 0.18, defaultScale = 1.0 },
        puncture_hit = { duration = 0.18, defaultScale = 1.0 },
        radiation_hit = { duration = 0.18, defaultScale = 1.0 }
    }

    local screenWaveDefs = {
        blast_hit = { radius = 200, duration = 0.40, strength = 2.8, priority = 3 },
        impact_hit = { radius = 160, duration = 0.34, strength = 2.5, priority = 2 },
        shock = { radius = 140, duration = 0.30, strength = 2.2, priority = 2 },
        hit = { radius = 100, duration = 0.26, strength = 1.5, priority = 1, cooldown = 0.07 },
    }

    local screenWaveMax = 12

    local function trimScreenWaves()
        local list = state.screenWaves
        if type(list) ~= 'table' then return end
        while #list > screenWaveMax do
            local removeIndex = 1
            local worstPrio = list[1].priority or 0
            local worstT = list[1].t or 0
            for i = 2, #list do
                local p = list[i].priority or 0
                local t = list[i].t or 0
                if p < worstPrio or (p == worstPrio and t > worstT) then
                    removeIndex = i
                    worstPrio = p
                    worstT = t
                end
            end
            table.remove(list, removeIndex)
        end
    end

    function state.spawnScreenWave(x, y, radius, duration, strength, priority)
        if not x or not y then return end
        radius = radius or 120
        duration = duration or 0.28
        strength = strength or 1.8
        if duration <= 0 or radius <= 0 or strength <= 0 then return end
        state.screenWaves = state.screenWaves or {}
        table.insert(state.screenWaves, {
            x = x,
            y = y,
            t = 0,
            duration = duration,
            radius = radius,
            strength = strength,
            priority = priority or 0
        })
        trimScreenWaves()
    end

    function state.spawnEffect(key, x, y, scale)
        local def = screenWaveDefs[key]
        if def then
            local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
            local cd = def.cooldown or 0
            if cd <= 0 then
                state.spawnScreenWave(x, y, def.radius, def.duration, def.strength, def.priority)
            else
                state._screenWaveCooldown = state._screenWaveCooldown or {}
                local last = state._screenWaveCooldown[key] or 0
                if last + cd <= now then
                    state._screenWaveCooldown[key] = now
                    state.spawnScreenWave(x, y, def.radius, def.duration, def.strength, def.priority)
                end
            end
        end

        local eff = state.effectSprites[key]
        if eff then
            local useScale = scale or eff.defaultScale or 1
            table.insert(state.hitEffects, {key = key, x = x, y = y, t = 0, duration = eff.duration or 0.3, scale = useScale})
            return
        end

        local p = proceduralEffectDefs[key]
        if not p then return end
        local useScale = scale or p.defaultScale or 1
        table.insert(state.hitEffects, {key = key, x = x, y = y, t = 0, duration = p.duration or 0.18, scale = useScale})
    end

    function state.spawnAreaField(kind, x, y, radius, duration, intensity)
        if not kind then return end
        if not radius or radius <= 0 then return end
        table.insert(state.areaFields, {
            kind = kind,
            x = x,
            y = y,
            radius = radius,
            t = 0,
            duration = duration or 2.0,
            intensity = intensity or 1
        })
    end

    function state.spawnTelegraphCircle(x, y, radius, duration, opts)
        if not x or not y then return nil end
        if not radius or radius <= 0 then return nil end
        duration = duration or 0.7
        if duration <= 0 then return nil end
        state.telegraphs = state.telegraphs or {}
        local t = {
            shape = 'circle',
            x = x,
            y = y,
            radius = radius,
            t = 0,
            duration = duration,
            kind = (opts and opts.kind) or 'telegraph',
            intensity = (opts and opts.intensity) or 1
        }
        table.insert(state.telegraphs, t)
        return t
    end

    function state.spawnTelegraphLine(x1, y1, x2, y2, width, duration, opts)
        if not x1 or not y1 or not x2 or not y2 then return nil end
        width = width or 28
        if width <= 0 then return nil end
        duration = duration or 0.6
        if duration <= 0 then return nil end
        state.telegraphs = state.telegraphs or {}
        local t = {
            shape = 'line',
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2,
            width = width,
            t = 0,
            duration = duration,
            color = (opts and opts.color) or nil
        }
        table.insert(state.telegraphs, t)
        return t
    end

    local dashAfterimageMax = 28
    function state.spawnDashAfterimage(x, y, facing, opts)
        if not x or not y then return nil end
        state.dashAfterimages = state.dashAfterimages or {}
        local a = {
            x = x,
            y = y,
            facing = facing or 1,
            t = 0,
            duration = (opts and opts.duration) or 0.22,
            alpha = (opts and opts.alpha) or 0.22,
            dirX = (opts and opts.dirX) or nil,
            dirY = (opts and opts.dirY) or nil
        }
        table.insert(state.dashAfterimages, a)
        while #state.dashAfterimages > dashAfterimageMax do
            table.remove(state.dashAfterimages, 1)
        end
        return a
    end

    function state.updateEffects(dt)
        for i = #state.hitEffects, 1, -1 do
            local e = state.hitEffects[i]
            e.t = e.t + dt
            if e.t >= (e.duration or 0.3) then
                table.remove(state.hitEffects, i)
            end
        end

        for i = #(state.screenWaves or {}), 1, -1 do
            local w = state.screenWaves[i]
            w.t = (w.t or 0) + dt
            if w.t >= (w.duration or 0.3) then
                table.remove(state.screenWaves, i)
            end
        end

        for i = #state.areaFields, 1, -1 do
            local a = state.areaFields[i]
            a.t = a.t + dt
            if a.t >= (a.duration or 2.0) then
                table.remove(state.areaFields, i)
            end
        end

        for i = #(state.telegraphs or {}), 1, -1 do
            local t = state.telegraphs[i]
            t.t = (t.t or 0) + dt
            if t.t >= (t.duration or 0.6) then
                table.remove(state.telegraphs, i)
            end
        end

        for i = #(state.dashAfterimages or {}), 1, -1 do
            local a = state.dashAfterimages[i]
            a.t = (a.t or 0) + dt
            if a.t >= (a.duration or 0.22) then
                table.remove(state.dashAfterimages, i)
            end
        end

        for i = #state.lightningLinks, 1, -1 do
            local l = state.lightningLinks[i]
            l.t = (l.t or 0) + dt
            if l.t >= (l.duration or 0.12) then
                table.remove(state.lightningLinks, i)
            end
        end
    end
end

return effects
