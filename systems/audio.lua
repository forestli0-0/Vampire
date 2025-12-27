-- ============================================================================
-- 音频管理模块 (Audio Manager)
-- ============================================================================
-- 文件：systems/audio.lua
-- 作用：集中管理游戏的所有音频，包括：
--       1. BGM 场景映射和自动切换
--       2. 音效池管理，防止音源累积
--       3. 音量统一控制
--       4. BGM 淡入淡出过渡效果
-- ============================================================================

local audio = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

-- 音效池最大容量（每种音效同时播放的最大数量）
local SFX_POOL_SIZE = 8

-- BGM 淡入淡出时间（秒）
local BGM_FADE_DURATION = 0.5

-- ============================================================================
-- 场景 BGM 映射表
-- ============================================================================
-- 定义每个游戏场景应该播放的 BGM
-- nil 表示保持当前音乐不变

local sceneBGM = {
    MAIN_MENU  = 'menu',      -- 主菜单：轻柔的背景音乐
    ARSENAL    = 'hub',       -- 军械库：基地音乐
    HUB        = 'hub',       -- 基地：基地音乐
    PLAYING    = 'combat',    -- 战斗：紧张的战斗音乐
    BOSS       = 'boss',      -- Boss战：史诗级战斗音乐
    SHOP       = nil,         -- 商店：保持当前音乐
    LEVEL_UP   = nil,         -- 升级：保持当前音乐
    GAME_OVER  = 'gameover',  -- 结算：结算音乐
    GAME_CLEAR = 'victory',   -- 通关：胜利音乐
}

-- ============================================================================
-- 模块状态
-- ============================================================================

-- 当前加载的 BGM 源
local bgmSources = {}

-- 当前播放的 BGM key
local currentBGM = nil

-- 当前场景
local currentScene = nil

-- 音量设置
local volumes = {
    master = 1.0,
    music = 0.7,
    sfx = 0.8
}

-- 音效定义（从 assets.lua 迁移）
local sfxDefs = {}

-- 音效池（避免频繁创建新音源）
local sfxPool = {}

-- 淡入淡出状态
local fadeState = {
    active = false,
    direction = 'in',  -- 'in' 或 'out'
    timer = 0,
    duration = BGM_FADE_DURATION,
    targetVolume = 1.0,
    onComplete = nil
}

-- 是否暂停
local isPaused = false

-- state 引用（用于兼容旧系统）
local stateRef = nil

-- ============================================================================
-- 内部辅助函数
-- ============================================================================

--- 生成蜂鸣音（回退音效）
local function genBeep(freq, duration)
    duration = duration or 0.1
    local sampleRate = 44100
    local data = love.sound.newSoundData(math.floor(sampleRate * duration), sampleRate, 16, 1)
    for i = 0, data:getSampleCount() - 1 do
        local t = i / sampleRate
        local sample = math.sin(2 * math.pi * freq * t) * 0.2
        data:setSample(i, sample)
    end
    return love.audio.newSource(data, 'static')
end

--- 加载音效文件
local function loadSfx(path, fallbackFreq)
    local ok, src = pcall(love.audio.newSource, path, 'static')
    if ok and src then return src end
    return genBeep(fallbackFreq)
end

--- 加载音乐文件（流式）
local function loadMusic(paths)
    for _, path in ipairs(paths or {}) do
        local ok, src = pcall(love.audio.newSource, path, 'stream')
        if ok and src then return src end
    end
    return nil
end

--- 获取实际音效音量
local function getSfxVolume()
    return volumes.master * volumes.sfx
end

--- 获取实际音乐音量
local function getMusicVolume()
    return volumes.master * volumes.music
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化音频系统
-- @param state 游戏状态引用
function audio.init(state)
    stateRef = state
    
    -- 加载音效定义
    sfxDefs = {
        shoot     = { path = 'assets/sfx/shoot.wav',     fallback = 600,  volume = 0.4 },
        hit       = { path = 'assets/sfx/hit.wav',       fallback = 200,  volume = 1.0 },
        gem       = { path = 'assets/sfx/gem.wav',       fallback = 1200, volume = 0.8 },
        glass     = { path = 'assets/sfx/glass.wav',     fallback = 1000, volume = 0.9 },
        freeze    = { path = 'assets/sfx/freeze.wav',    fallback = 500,  volume = 0.8 },
        ignite    = { path = 'assets/sfx/ignite.wav',    fallback = 900,  volume = 0.9 },
        static    = { path = 'assets/sfx/static.wav',    fallback = 700,  volume = 0.5 },
        bleed     = { path = 'assets/sfx/bleed.wav',     fallback = 400,  volume = 0.85 },
        explosion = { path = 'assets/sfx/explosion.wav', fallback = 300,  volume = 0.9 },
        reload    = { path = 'assets/sfx/reload.wav',    fallback = 800,  volume = 0.7 },
        levelup   = { path = 'assets/sfx/levelup.wav',   fallback = 1500, volume = 1.0 },
        shock     = { path = 'assets/sfx/static.wav',    fallback = 700,  volume = 0.6 },  -- 复用 static
    }
    
    -- 预加载音效到池中
    for key, def in pairs(sfxDefs) do
        sfxPool[key] = {}
        local baseSrc = loadSfx(def.path, def.fallback)
        if baseSrc then
            -- 为每种音效创建多个克隆，避免频繁创建
            for i = 1, SFX_POOL_SIZE do
                local ok, clone = pcall(function() return baseSrc:clone() end)
                if ok and clone then
                    table.insert(sfxPool[key], {
                        source = clone,
                        baseVolume = def.volume or 1.0
                    })
                end
            end
        end
    end
    
    -- 加载 BGM
    bgmSources = {
        -- 目前只有一首 BGM，后续可以扩展
        combat = loadMusic({
            'assets/music/bgm.ogg', 'assets/music/bgm.mp3', 'assets/music/bgm.wav',
            'assets/sfx/bgm.ogg', 'assets/sfx/bgm.mp3', 'assets/sfx/bgm.wav'
        }),
        -- 其他 BGM 暂时复用战斗音乐（或设为 nil）
        hub      = nil,  -- 基地音乐（待添加）
        menu     = nil,  -- 菜单音乐（待添加）
        boss     = nil,  -- Boss 音乐（待添加）
        gameover = nil,  -- 结算音乐（待添加）
        victory  = nil,  -- 胜利音乐（待添加）
    }
    
    -- 设置 BGM 循环
    for _, src in pairs(bgmSources) do
        if src and src.setLooping then
            src:setLooping(true)
        end
    end
    
    -- 从存档加载音量设置
    if state and state.profile and state.profile.volumes then
        local v = state.profile.volumes
        volumes.master = v.master or 1.0
        volumes.music = v.music or 0.7
        volumes.sfx = v.sfx or 0.8
    end
    
    -- 应用音量
    audio.applyVolumes()
    
    print('[Audio] 音频系统初始化完成')
end

-- ============================================================================
-- BGM 控制
-- ============================================================================

--- 设置当前场景，自动切换 BGM
-- @param sceneName 场景名称（如 'PLAYING', 'HUB'）
function audio.setScene(sceneName)
    if sceneName == currentScene then return end
    currentScene = sceneName
    
    local targetBGM = sceneBGM[sceneName]
    
    -- nil 表示保持当前音乐
    if targetBGM == nil then return end
    
    -- 如果目标 BGM 与当前相同，不切换
    if targetBGM == currentBGM then return end
    
    -- 切换 BGM（带淡出淡入效果）
    audio.switchBGM(targetBGM)
end

--- 切换 BGM（带淡入淡出）
-- @param bgmKey BGM 键名
function audio.switchBGM(bgmKey)
    -- 如果当前有 BGM 在播放，先淡出
    if currentBGM and bgmSources[currentBGM] then
        local oldSrc = bgmSources[currentBGM]
        if oldSrc and oldSrc.isPlaying then
            local ok, playing = pcall(function() return oldSrc:isPlaying() end)
            if ok and playing then
                -- 淡出当前 BGM
                fadeState.active = true
                fadeState.direction = 'out'
                fadeState.timer = 0
                fadeState.duration = BGM_FADE_DURATION
                fadeState.onComplete = function()
                    pcall(function() oldSrc:stop() end)
                    -- 淡出完成后，开始播放新 BGM
                    audio.playBGM(bgmKey)
                end
                return
            end
        end
    end
    
    -- 没有当前 BGM，直接播放新的
    audio.playBGM(bgmKey)
end

--- 播放指定 BGM
-- @param bgmKey BGM 键名
function audio.playBGM(bgmKey)
    currentBGM = bgmKey
    
    local src = bgmSources[bgmKey]
    if not src then
        -- 没有对应的 BGM 文件，尝试使用默认战斗音乐
        src = bgmSources['combat']
    end
    
    if src then
        -- 设置音量并播放
        pcall(function()
            src:setVolume(0)  -- 从 0 开始淡入
            src:play()
        end)
        
        -- 开始淡入
        fadeState.active = true
        fadeState.direction = 'in'
        fadeState.timer = 0
        fadeState.duration = BGM_FADE_DURATION
        fadeState.targetVolume = getMusicVolume()
        fadeState.onComplete = nil
    end
end

--- 播放音乐（兼容旧接口）
function audio.playMusic()
    if currentScene then
        audio.setScene(currentScene)
    else
        -- 默认播放战斗音乐
        audio.playBGM('combat')
    end
end

--- 停止音乐
function audio.stopMusic()
    if currentBGM and bgmSources[currentBGM] then
        local src = bgmSources[currentBGM]
        if src then
            pcall(function() src:stop() end)
        end
    end
    currentBGM = nil
end

--- 暂停音频（用于暂停菜单）
function audio.pause()
    isPaused = true
    if currentBGM and bgmSources[currentBGM] then
        local src = bgmSources[currentBGM]
        if src then
            pcall(function() src:pause() end)
        end
    end
end

--- 恢复音频
function audio.resume()
    isPaused = false
    if currentBGM and bgmSources[currentBGM] then
        local src = bgmSources[currentBGM]
        if src then
            pcall(function() src:play() end)
        end
    end
end

-- ============================================================================
-- 音效控制
-- ============================================================================

--- 播放音效
-- @param key 音效键名
-- @param opts 可选参数 { volume = 1.0, pitch = 1.0 }
function audio.playSfx(key, opts)
    opts = opts or {}
    
    local pool = sfxPool[key]
    if not pool or #pool == 0 then
        -- 未知音效，打印调试信息
        print("[Audio] 未知音效: " .. tostring(key))
        return
    end
    
    -- 特殊处理：static 音效不重复播放
    if key == 'static' then
        for _, entry in ipairs(pool) do
            local ok, playing = pcall(function() return entry.source:isPlaying() end)
            if ok and playing then return end
        end
    end
    
    -- 从池中找一个未在播放的音源
    local entry = nil
    for _, e in ipairs(pool) do
        local ok, playing = pcall(function() return e.source:isPlaying() end)
        if ok and not playing then
            entry = e
            break
        end
    end
    
    -- 如果所有音源都在播放，使用第一个（会中断它）
    if not entry then
        entry = pool[1]
        if entry and entry.source then
            pcall(function() entry.source:stop() end)
        end
    end
    
    if entry and entry.source then
        local vol = (opts.volume or 1.0) * entry.baseVolume * getSfxVolume()
        pcall(function()
            entry.source:setVolume(vol)
            if opts.pitch and entry.source.setPitch then
                entry.source:setPitch(opts.pitch)
            end
            entry.source:stop()  -- 确保从头播放
            entry.source:play()
        end)
    end
end

-- ============================================================================
-- 音量控制
-- ============================================================================

--- 设置音量
-- @param master 主音量 (0.0 - 1.0)
-- @param music 音乐音量 (0.0 - 1.0)
-- @param sfx 音效音量 (0.0 - 1.0)
function audio.setVolumes(master, music, sfx)
    volumes.master = master or volumes.master
    volumes.music = music or volumes.music
    volumes.sfx = sfx or volumes.sfx
    audio.applyVolumes()
end

--- 应用当前音量设置
function audio.applyVolumes()
    -- 应用到当前播放的 BGM
    if currentBGM and bgmSources[currentBGM] then
        local src = bgmSources[currentBGM]
        if src and src.setVolume then
            pcall(function()
                src:setVolume(getMusicVolume())
            end)
        end
    end
    
    -- 保存到 state（兼容旧系统）
    if stateRef then
        stateRef.sfxMasterVolume = getSfxVolume()
    end
end

--- 获取当前音量设置
function audio.getVolumes()
    return {
        master = volumes.master,
        music = volumes.music,
        sfx = volumes.sfx
    }
end

-- ============================================================================
-- 更新（每帧调用）
-- ============================================================================

--- 更新音频系统（处理淡入淡出）
-- @param dt delta time
function audio.update(dt)
    if not fadeState.active then return end
    
    fadeState.timer = fadeState.timer + dt
    local progress = math.min(1, fadeState.timer / fadeState.duration)
    
    if currentBGM and bgmSources[currentBGM] then
        local src = bgmSources[currentBGM]
        if src and src.setVolume then
            local targetVol = fadeState.direction == 'in' and fadeState.targetVolume or 0
            local startVol = fadeState.direction == 'in' and 0 or getMusicVolume()
            local currentVol = startVol + (targetVol - startVol) * progress
            pcall(function() src:setVolume(currentVol) end)
        end
    end
    
    -- 淡入淡出完成
    if progress >= 1 then
        fadeState.active = false
        if fadeState.onComplete then
            fadeState.onComplete()
            fadeState.onComplete = nil
        end
    end
end

-- ============================================================================
-- 兼容接口（供旧代码调用）
-- ============================================================================

--- 获取音效音量（供外部使用）
function audio.getSfxVolume()
    return getSfxVolume()
end

--- 获取音乐音量
function audio.getMusicVolume()
    return getMusicVolume()
end

return audio
