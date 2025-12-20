local benchmark = {}
local progression = require('systems.progression')
local defs = progression.defs or {}

benchmark.active = false
benchmark.startTime = 0
benchmark.frames = 0
benchmark.totalFPS = 0
benchmark.minFPS = 9999
benchmark.maxFPS = 0
benchmark.results = nil
benchmark.lowFpsThreshold = 10
benchmark.lowFpsHold = 0.5
benchmark.lowFpsTimer = 0
benchmark.stopReason = nil
benchmark.spawnRate = 40        -- enemies per second, grows over time
benchmark.spawnGrowth = 8       -- how much spawnRate increases per second
benchmark.spawnAccumulator = 0
benchmark.logInterval = 1       -- seconds between log samples
benchmark.logTimer = 0
benchmark.runId = nil
benchmark.totalSpawned = 0
benchmark.logFile = "logs/benchmark_stream.log"

local function appendLog(line)
    if not (love and love.filesystem and love.filesystem.append) then
        print("[benchmark] log skipped: filesystem unavailable")
        return
    end
    pcall(function() love.filesystem.createDirectory("logs") end)
    local ok, err = pcall(function()
        love.filesystem.append(benchmark.logFile, line .. "\n")
    end)
    if not ok then
        print("[benchmark] log write failed: " .. tostring(err))
    end
end

local function logSnapshot(state, elapsed, currentFPS, reason)
    local bullets = #state.bullets
    local enemyBullets = #state.enemyBullets
    local enemiesCount = #state.enemies
    local line = string.format(
        "%s run=%s t=%.2f fps=%.2f min=%.2f enemies=%d bullets=%d enemyBullets=%d spawnRate=%.1f totalSpawned=%d reason=%s",
        os.date("%Y-%m-%d %H:%M:%S"),
        benchmark.runId or "n/a",
        elapsed,
        currentFPS,
        benchmark.minFPS,
        enemiesCount,
        bullets,
        enemyBullets,
        benchmark.spawnRate,
        benchmark.totalSpawned,
        reason or "tick"
    )
    print("[benchmark] " .. line)
    appendLog(line)
end

local function spawnBurst(state, count)
    local enemies = require('gameplay.enemies')
    for i = 1, count do
        local r = math.random()
        local kind, elite
        if r < 0.6 then
            kind = 'skeleton'
        elseif r < 0.85 then
            kind = 'bat'
        else
            kind = 'plant'
        end
        elite = (math.random() < 0.05)
        local angle = math.random() * math.pi * 2
        local dist = 220 + math.random() * 520
        local ex = state.player.x + math.cos(angle) * dist
        local ey = state.player.y + math.sin(angle) * dist
        enemies.spawnEnemy(state, kind, elite, ex, ey)
        benchmark.totalSpawned = benchmark.totalSpawned + 1
    end
end

function benchmark.toggle(state)
    if benchmark.active then
        local elapsed = love.timer.getTime() - benchmark.startTime
        local currentFPS = love.timer.getFPS()
        logSnapshot(state, elapsed, currentFPS, "manual_stop")
        benchmark.active = false
        state.benchmarkMode = false
        state.noLevelUps = false
        state.pendingLevelUps = 0
        state.pendingUpgradeRequests = {}
        state.activeUpgradeRequest = nil
        state.pendingWeaponSwap = nil
        state.doors = {}
        state.player.level = 0
        state.player.xp = 0
        state.player.xpToNextLevel = defs.xpBase or 10
        state.gameState = 'PLAYING'
        print("Benchmark stopped manually.")
    else
        benchmark.active = true
        state.benchmarkMode = true
        state.noLevelUps = true
        state.gameState = 'PLAYING'
        state.pendingLevelUps = 0
        state.pendingUpgradeRequests = {}
        state.activeUpgradeRequest = nil
        state.pendingWeaponSwap = nil
        state.doors = {}
        state.upgradeOptions = {}
        state.player.level = 0
        state.player.xp = 0
        state.player.xpToNextLevel = math.huge
        benchmark.startTime = love.timer.getTime()
        benchmark.runId = os.date("bench_%Y%m%d_%H%M%S")
        benchmark.frames = 0
        benchmark.totalFPS = 0
        benchmark.minFPS = 9999
        benchmark.maxFPS = 0
        benchmark.results = nil
        benchmark.lowFpsTimer = 0
        benchmark.stopReason = nil
        benchmark.spawnRate = 40
        benchmark.spawnAccumulator = 0
        benchmark.logTimer = 0
        benchmark.totalSpawned = 0
        benchmark.stopReason = nil
        appendLog(string.format("%s run=%s start", os.date("%Y-%m-%d %H:%M:%S"), benchmark.runId))
        
        -- Setup stress test scenario
        print("Starting Benchmark...")
        
        -- 1. Add weapons for projectile stress
        local weapons = require('gameplay.weapons')
        local function ensureWeapon(key)
            if not state.inventory.weapons[key] then weapons.addWeapon(state, key) end
        end
        ensureWeapon('wand')
        ensureWeapon('axe')
        ensureWeapon('fire_wand')
        ensureWeapon('dagger')
        ensureWeapon('static_orb')
        ensureWeapon('heavy_hammer')
        ensureWeapon('ice_ring')
        
        -- Max out passives that amplify projectile count and cooldowns
        local passives = state.inventory.passives
        passives['duplicator'] = 2
        passives['tome'] = 5
        passives['candelabrador'] = 5
        passives['bracer'] = 5
        passives['clover'] = 5
        passives['skull'] = 5
        passives['venom_vial'] = 5

        -- Upgrade weapons to spam projectiles
        local function tuneWeapon(key, overrides)
            local w = state.inventory.weapons[key]
            if not w then return end
            for stat, val in pairs(overrides) do
                w.stats[stat] = val
            end
        end
        tuneWeapon('wand', { amount = 8, cd = 0.05 })
        tuneWeapon('fire_wand', { amount = 6, cd = 0.25, splashRadius = 140 })
        tuneWeapon('dagger', { amount = 8, cd = 0.05 })
        tuneWeapon('axe', { amount = 5, cd = 0.4 })
        tuneWeapon('static_orb', { amount = 4, cd = 0.35, chain = 10, allowRepeat = true })
        tuneWeapon('heavy_hammer', { amount = 3, cd = 0.35 })
        tuneWeapon('ice_ring', { radius = 200, cd = 0.4 })
        
        -- 2. Add Companion (Pet) for AI/Pathing/Proc stress
        local pets = require('gameplay.pets')
        pets.setActive(state, 'pet_corrosive', {swap=false})
        if state.pets and state.pets.list and state.pets.list[1] then
            state.pets.list[1].module = 'field'
        end
        
        -- 3. Add Augments for Event System stress (proc on move/hit/kill)
        local augments = state.augments -- already loaded in main.lua
        state.inventory.augments['aug_kinetic_discharge'] = 1 -- procs on move
        state.inventory.augments['aug_forked_trajectory'] = 1 -- doubles projectiles
        state.inventory.augments['aug_blood_burst'] = 1       -- procs on kill
        state.inventory.augments['aug_shockstep'] = 1         -- spawns AreaFields (persistent zones)
        
        -- 4. Spawn enemies (continuous growth)
        state.enemies = {}
        state.enemyBullets = {}
        spawnBurst(state, 400)
    end
end

function benchmark.update(state, dt)
    if not benchmark.active then return end
    
    local currentTime = love.timer.getTime()
    local elapsed = currentTime - benchmark.startTime
    
    local currentFPS = love.timer.getFPS()
    benchmark.frames = benchmark.frames + 1
    benchmark.totalFPS = benchmark.totalFPS + currentFPS
    
    if currentFPS < benchmark.minFPS then benchmark.minFPS = currentFPS end
    if currentFPS > benchmark.maxFPS then benchmark.maxFPS = currentFPS end
    
    -- Progressive spawn each tick, spawnRate increases over time
    benchmark.spawnRate = benchmark.spawnRate + benchmark.spawnGrowth * dt
    benchmark.spawnAccumulator = benchmark.spawnAccumulator + benchmark.spawnRate * dt
    local toSpawn = math.floor(benchmark.spawnAccumulator)
    if toSpawn > 0 then
        benchmark.spawnAccumulator = benchmark.spawnAccumulator - toSpawn
        spawnBurst(state, toSpawn)
    end

    -- Early stop when FPS stays below threshold
    if currentFPS < benchmark.lowFpsThreshold then
        benchmark.lowFpsTimer = benchmark.lowFpsTimer + dt
        if benchmark.lowFpsTimer >= benchmark.lowFpsHold then
            benchmark.stopReason = 'fps_drop'
        end
    else
        benchmark.lowFpsTimer = 0
    end

    -- periodic logging
    benchmark.logTimer = benchmark.logTimer + dt
    if benchmark.logTimer >= benchmark.logInterval then
        benchmark.logTimer = benchmark.logTimer - benchmark.logInterval
        logSnapshot(state, elapsed, currentFPS, benchmark.stopReason or "tick")
    end

    if benchmark.stopReason then
        benchmark.active = false
        local avgFPS = benchmark.frames > 0 and (benchmark.totalFPS / benchmark.frames) or (love.timer.getFPS() or 0)
        local entityCount = #state.enemies
        local reason = benchmark.stopReason or 'duration'
        local reasonText = reason == 'fps_drop' and "FPS < " .. benchmark.lowFpsThreshold or reason
        benchmark.results = string.format(
            "Benchmark Complete (%s)\nDuration: %.1fs\nAvg FPS: %.2f\nMin FPS: %d\nMax FPS: %d\nEntities: %d\nTotal Spawned: %d",
            reasonText, elapsed, avgFPS, benchmark.minFPS, benchmark.maxFPS, entityCount, benchmark.totalSpawned
        )
        print(benchmark.results)
        logSnapshot(state, elapsed, currentFPS, reason)
        state.benchmarkMode = false
        state.noLevelUps = false
        state.pendingLevelUps = 0
        state.pendingUpgradeRequests = {}
        state.activeUpgradeRequest = nil
        state.player.level = 0
        state.player.xp = 0
        state.player.xpToNextLevel = defs.xpBase or 10
        state.gameState = 'PLAYING'
    end
end

function benchmark.draw(state)
    if benchmark.active then
        love.graphics.setColor(1, 0, 1, 1)
        love.graphics.print("BENCHMARK RUNNING...", 10, 100)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 120)
        love.graphics.print("Enemies: " .. #state.enemies, 10, 140)
        local elapsed = love.timer.getTime() - benchmark.startTime
        love.graphics.print(string.format("Time: %.1f (stop if FPS<%d)", elapsed, benchmark.lowFpsThreshold), 10, 160)
        love.graphics.print(string.format("SpawnRate: %.1f/s  TotalSpawned: %d", benchmark.spawnRate, benchmark.totalSpawned), 10, 180)
    elseif benchmark.results then
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.print(benchmark.results, 10, 100)
    end
end

return benchmark
