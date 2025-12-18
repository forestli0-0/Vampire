local world = require('world')
local mission = require('mission')
local biomes = require('biomes')

local campaign = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function getStageType(c)
    local stage = tonumber(c and c.stageInBiome) or 1
    local per = tonumber(c and c.stagesPerBiome) or 3
    if stage >= per then return 'boss' end
    return 'explore'
end

local function stageLabel(c)
    local biome = tonumber(c and c.biome) or 1
    local stage = tonumber(c and c.stageInBiome) or 1
    local biomeName = (c and c.biomeDef and c.biomeDef.name) or nil
    local t = "STAGE " .. tostring(biome) .. "-" .. tostring(stage)
    if biomeName then
        t = tostring(biomeName) .. "  " .. t
    end
    if (c and c.stageType) == 'boss' then
        t = t .. "  BOSS"
    end
    return t
end

local function resetStageState(state)
    state.enemies = {}
    state.bullets = {}
    state.enemyBullets = {}
    state.gems = {}
    state.floorPickups = {}
    state.chests = {}
    state.doors = {}
    state.pendingWeaponSwap = nil
    state.pendingUpgradeRequests = {}
    state.activeUpgradeRequest = nil
    state.chainLinks = {}
    state.lightningLinks = {}
    state.quakeEffects = {}
    state.screenWaves = {}
    state.telegraphs = {}
    state.areaFields = {}
    state.hitEffects = {}
    state.dashAfterimages = {}
    state.directorState = {event60 = false, event120 = false, bossDefeated = false}
    state.mission = nil
end

local function centerCameraOnPlayer(state)
    if not (love and love.graphics and love.graphics.getWidth and love.graphics.getHeight) then return end
    if not (state and state.player and state.world) then return end
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local maxCamX = math.max(0, (state.world.pixelW or 0) - sw)
    local maxCamY = math.max(0, (state.world.pixelH or 0) - sh)
    state.camera = state.camera or {x = 0, y = 0}
    state.camera.x = clamp((state.player.x or 0) - sw / 2, 0, maxCamX)
    state.camera.y = clamp((state.player.y or 0) - sh / 2, 0, maxCamY)
end

local function getWorldOptsForStage(stageType, biomeDef)
    local ts = 32
    local nav = (stageType == 'boss') and 0.25 or 0.35
    local roomCount = (stageType == 'boss') and 1 or math.random(3, 5)

    local base = {tileSize = ts, roomCount = roomCount, navRefresh = nav}
    local src = nil
    if biomeDef then
        src = (stageType == 'boss') and biomeDef.worldBoss or biomeDef.worldExplore
    end
    src = src or {}

    base.w = src.w or ((stageType == 'boss') and 70 or 90)
    base.h = src.h or ((stageType == 'boss') and 70 or 90)
    base.roomMin = src.roomMin or ((stageType == 'boss') and 28 or 8)
    base.roomMax = src.roomMax or ((stageType == 'boss') and 36 or 14)
    base.corridorWidth = src.corridorWidth or 2
    return base
end

function campaign.startRun(state, opts)
    opts = opts or {}
    state.campaign = {
        biome = 1,
        stageInBiome = 1,
        biomesTotal = math.max(1, math.floor(opts.biomesTotal or 3)),
        stagesPerBiome = math.max(1, math.floor(opts.stagesPerBiome or 3)),
        stageType = 'explore',
        biomeDef = biomes.get(1)
    }
    return campaign.startStage(state)
end

function campaign.isFinalBoss(state)
    local c = state and state.campaign
    if not c then return false end
    local biome = tonumber(c.biome) or 1
    local stage = tonumber(c.stageInBiome) or 1
    local biomesTotal = tonumber(c.biomesTotal) or 3
    local stagesPerBiome = tonumber(c.stagesPerBiome) or 3
    return biome >= biomesTotal and stage >= stagesPerBiome
end

function campaign.startStage(state)
    local c = state and state.campaign
    if not c then return false end
    c.biomeDef = biomes.get(c.biome)
    c.stageType = getStageType(c)

    resetStageState(state)

    local opts = getWorldOptsForStage(c.stageType, c.biomeDef)
    state.world = world.new(opts)
    if state.world and c.biomeDef and c.biomeDef.wallColor then
        state.world.wallColor = c.biomeDef.wallColor
    end

    if state.player and state.world then
        state.player.x, state.player.y = state.world.spawnX, state.world.spawnY
        state.player.invincibleTimer = math.max(state.player.invincibleTimer or 0, 0.6)
    end
    centerCameraOnPlayer(state)

    mission.start(state)

    if state.texts and state.player then
        table.insert(state.texts, {x = state.player.x, y = state.player.y - 110, text = stageLabel(c), color = {0.95, 0.95, 1.0}, life = 2.2})
    end
    return true
end

function campaign.advanceStage(state)
    local c = state and state.campaign
    if not c then return false end

    local biome = tonumber(c.biome) or 1
    local stage = tonumber(c.stageInBiome) or 1
    local per = tonumber(c.stagesPerBiome) or 3
    local biomesTotal = tonumber(c.biomesTotal) or 3

    if stage >= per then
        biome = biome + 1
        stage = 1
    else
        stage = stage + 1
    end

    if biome > biomesTotal then
        -- Fallback: normally the final boss chest should end the run.
        state.gameState = 'GAME_CLEAR'
        return true
    end

    c.biome = biome
    c.stageInBiome = stage
    return campaign.startStage(state)
end

return campaign
