local catalog = {
        -- Projectile Augments (modify bullet behavior)
        aug_forked_trajectory = {
            type = 'augment', name = "Forked Trajectory",
            desc = "Projectiles split into 2 angled forks.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 60,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b._forked or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        if not b.vx or not b.vy then return end

                        local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        if spd <= 0 then return end
                        local baseAng = math.atan2(b.vy, b.vx)
                        local spread = 0.22
                        local forks = 2
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end

                        local function cloneBullet(src)
                            local out = {}
                            for k, v in pairs(src) do
                                if type(v) == 'table' then
                                    local t = {}
                                    for kk, vv in pairs(v) do t[kk] = vv end
                                    out[k] = t
                                else
                                    out[k] = v
                                end
                            end
                            out.hitTargets = nil
                            return out
                        end

                        b._forked = true
                        for i = 1, forks do
                            local sign = (i == 1) and -1 or 1
                            local ang = baseAng + sign * spread
                            local c = cloneBullet(b)
                            c.x = b.x
                            c.y = b.y
                            c.vx = math.cos(ang) * spd
                            c.vy = math.sin(ang) * spd
                            c.rotation = ang
                            c.life = (b.life or 2) * 0.9
                            c.size = math.max(4, (b.size or 8) * 0.9)
                            c.damage = math.max(1, math.floor(dmg * 0.6 + 0.5))
                            c.augmentChild = true
                            c._forked = true
                            table.insert(state.bullets, c)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = c.type, bullet = c, spawnedBy = 'fork'})
                            end
                        end
                    end
                }
            }
        },
        aug_homing_protocol = {
            type = 'augment', name = "Homing Protocol",
            desc = "Projectiles steer toward nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        b.homing = math.max(b.homing or 0, 6.5)
                        b.homingRange = math.max(b.homingRange or 0, 720)
                    end
                }
            }
        },
        aug_ricochet_matrix = {
            type = 'augment', name = "Ricochet Matrix",
            desc = "Projectiles ricochet to nearby enemies.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local add = 2
                        b.ricochetRemaining = (b.ricochetRemaining or 0) + add
                        b.ricochetRange = math.max(b.ricochetRange or 0, 420)
                        b.pierce = (b.pierce or 1) + add
                    end
                }
            }
        },
        aug_boomerang_return = {
            type = 'augment', name = "Boomerang Return",
            desc = "Projectiles turn back and return to you.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileSpawned',
                    cooldown = 0.02,
                    maxPerSecond = 90,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        if not b or b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local t = math.min(0.9, (b.life or 2) * 0.45)
                        if b.boomerangTimer == nil or b.boomerangTimer > t then
                            b.boomerangTimer = t
                        end
                        b.returnHoming = math.max(b.returnHoming or 0, 22)
                        b.life = (b.life or 2) + 0.9
                        b.pierce = (b.pierce or 1) + 1
                    end
                }
            }
        },
        aug_shatter_shards = {
            type = 'augment', name = "Shatter Shards",
            desc = "On hit, projectiles burst into shards.",
            maxLevel = 1,
            triggers = {
                {
                    event = 'onProjectileHit',
                    cooldown = 0.05,
                    maxPerSecond = 30,
                    requires = {weaponTag = 'projectile'},
                    action = function(state, ctx)
                        local b = ctx and ctx.bullet
                        local enemy = ctx and ctx.enemy
                        if not b or not enemy then return end
                        if b._shattered or b.augmentChild then return end
                        if b.type == 'axe' or b.type == 'death_spiral' or b.type == 'absolute_zero' then return end
                        local dmg = b.damage or 0
                        if dmg <= 0 then return end
                        b._shattered = true

                        local spd = math.sqrt((b.vx or 0)^2 + (b.vy or 0)^2)
                        if spd <= 0 then spd = 520 end
                        local baseAng = math.atan2((b.vy or 0), (b.vx or 1))
                        local count = 3
                        local spread = 0.45

                        local function copyArray(src)
                            if not src then return nil end
                            local t = {}
                            for i, v in ipairs(src) do t[i] = v end
                            return t
                        end

                        local function copyMap(src)
                            if not src then return nil end
                            local t = {}
                            for k, v in pairs(src) do t[k] = v end
                            return t
                        end

                        for i = 1, count do
                            local offset = (i - (count + 1) / 2) * spread
                            local ang = baseAng + offset
                            local shardTags = copyArray(b.weaponTags) or {}
                            table.insert(shardTags, 'augment')
                            local shard = {
                                type = 'augment_shard',
                                x = enemy.x,
                                y = enemy.y,
                                vx = math.cos(ang) * spd,
                                vy = math.sin(ang) * spd,
                                life = 1.2,
                                size = math.max(4, (b.size or 10) * 0.7),
                                damage = math.max(1, math.floor(dmg * 0.35 + 0.5)),
                                effectType = b.effectType,
                                weaponTags = shardTags,
                                pierce = 1,
                                rotation = ang,
                                parentWeaponKey = b.type,
                                elements = copyArray(b.elements),
                                damageBreakdown = copyMap(b.damageBreakdown),
                                critChance = b.critChance,
                                critMultiplier = b.critMultiplier,
                                statusChance = b.statusChance
                            }
                            shard.augmentChild = true
                            table.insert(state.bullets, shard)
                            if state and state.augments and state.augments.dispatch then
                                state.augments.dispatch(state, 'onProjectileSpawned', {weaponKey = b.type, bullet = shard, spawnedBy = 'shatter'})
                            end
                        end
                    end
                }
            }
        },
}

return catalog
