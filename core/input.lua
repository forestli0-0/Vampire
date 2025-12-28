-- ============================================================================
-- 输入系统 (Input System)
-- ============================================================================
-- 文件：core/input.lua
-- 作用：提供模块化的、基于动作（Action）的输入管理
--      采用类似Unreal Engine的输入映射方式，将按键绑定抽象为"动作"
--
-- 使用方式：
--   1. 在 keymap 中定义动作与按键的映射关系
--   2. 通过 input.isDown('action_name') 检查动作是否进行中
--   3. 通过 input.getAxis('move_x') 获取连续的方向值
--   4. 通过 input.getMouseWorld(state) 获取鼠标在世界坐标系中的位置
--
-- 优势：
--   - 解耦：游戏逻辑不关心具体按键，只关心"动作"
--   - 灵活：可以通过修改 keymap 轻松更改按键绑定
--   - 可扩展：支持键盘、鼠标、后续可扩展手柄支持
-- ============================================================================

-- ============================================================================
-- 模块定义
-- ============================================================================

-- input 表作为模块的公开接口，暴露所有输入相关函数
local input = {}

-- ============================================================================
-- 输入状态缓存 (Phase 2 扩展)
-- ============================================================================
-- 用于追踪每帧的按键事件（pressed/released）
-- 这些状态会在每帧开始时重置，只在当前帧有效

input.state = {
    -- 鼠标状态
    mouseDown = {},     -- 当前按下的鼠标按钮 {[1]=true, [2]=false, ...}
    mousePressed = {},  -- 本帧刚按下的鼠标按钮
    mouseReleased = {}, -- 本帧刚释放的鼠标按钮

    -- 键盘状态
    keysPressed = {}, -- 本帧刚按下的键 {['w']=true, ...}
    keysReleased = {} -- 本帧刚释放的键
}

-- ============================================================================
-- 帧事件管理 (Phase 2 扩展)
-- ============================================================================

--- 每帧开始时调用，重置临时事件状态
-- 必须在 love.update 开始时调用
function input.beginFrame()
    input.state.mousePressed = {}
    input.state.mouseReleased = {}
    input.state.keysPressed = {}
    input.state.keysReleased = {}
end

--- 鼠标按下事件处理
-- 必须在 love.mousepressed 中调用
function input.onMousePressed(button)
    input.state.mouseDown[button] = true
    input.state.mousePressed[button] = true
end

--- 鼠标释放事件处理
-- 必须在 love.mousereleased 中调用
function input.onMouseReleased(button)
    input.state.mouseDown[button] = false
    input.state.mouseReleased[button] = true
end

--- 键盘按下事件处理
-- 必须在 love.keypressed 中调用
function input.onKeyPressed(key)
    input.state.keysPressed[key] = true
end

--- 键盘释放事件处理
-- 必须在 love.keyreleased 中调用（需要添加该回调）
function input.onKeyReleased(key)
    input.state.keysReleased[key] = true
end

--- 检查动作是否在本帧刚按下（单次触发）
function input.isPressed(action)
    local keys = input.keymap[action]
    if not keys then return false end

    for _, k in ipairs(keys) do
        if k:sub(1, 5) == 'mouse' then
            local btn = tonumber(k:sub(6))
            if input.state.mousePressed[btn] then return true end
        else
            if input.state.keysPressed[k] then return true end
        end
    end
    return false
end

--- 检查动作是否在本帧刚释放
function input.isReleased(action)
    local keys = input.keymap[action]
    if not keys then return false end

    for _, k in ipairs(keys) do
        if k:sub(1, 5) == 'mouse' then
            local btn = tonumber(k:sub(6))
            if input.state.mouseReleased[btn] then return true end
        else
            if input.state.keysReleased[k] then return true end
        end
    end
    return false
end

-- ============================================================================
-- 按键映射表 (Keymap)
-- ============================================================================
-- 核心数据结构：将游戏"动作"映射到具体的按键/鼠标按钮
-- 结构：input.keymap[动作名] = {按键列表}
-- 支持一个动作绑定多个按键（实现按键冗余）
--
-- 按键命名规则：
--   - 键盘：标准键名如 'w', 'space', 'escape'（参考 LÖVE 文档）
--   - 鼠标：'mouse1'(左键), 'mouse2'(右键), 'mouse3'(中键), 'mouse4/5'(侧键)
-- ============================================================================

input.keymap = {
    -- ==================== 移动控制 ====================
    -- 支持 WASD 和方向键两种方式
    move_up = { 'w', 'up' },       -- 向上移动：W键 或 方向键上
    move_down = { 's', 'down' },   -- 向下移动：S键 或 方向键下
    move_left = { 'a', 'left' },   -- 向左移动：A键 或 方向键左
    move_right = { 'd', 'right' }, -- 向右移动：D键 或 方向键右

    -- ==================== 战斗动作 ====================
    fire = { 'mouse1', 'j' },       -- 射击/攻击：鼠标左键 或 J键
    melee = { 'e' },                -- 近战攻击：E键
    reload = { 'r' },               -- 换弹：R键
    slide = { 'lshift', 'rshift' }, -- 滑铲：左/右Shift键
    dodge = { 'space' },            -- 闪避：空格键

    -- ==================== 技能快捷键 ====================
    ability1 = { '1' },   -- 技能1：数字键1
    ability2 = { '2' },   -- 技能2：数字键2
    ability3 = { '3' },   -- 技能3：数字键3
    ability4 = { '4' },   -- 技能4：数字键4
    quick_cast = { 'q' }, -- 快捷施法：Q键

    -- ==================== 实用功能 ====================
    cycle_weapon = { 'f' }, -- 切换武器：F键
    toggle_pet = { 'p' },   -- 切换宠物：P键
    debug_mods = { 'm' },   -- 调试MOD：M键（开发用）
    cancel = { 'escape' }   -- 取消/返回：Escape键
}

-- ============================================================================
-- 输入状态查询函数
-- ============================================================================

--- 检查指定动作是否正在进行（按键处于按下状态）
-- 这是最常用的输入查询函数，用于需要持续输入的情况
-- 例如：移动时每帧检查、持续射击时每帧检查
--
-- 实现原理：
--   遍历动作对应的所有按键，检查是否有任意一个处于按下状态
--   键盘按键使用 love.keyboard.isDown()
--   鼠标按键使用 love.mouse.isDown()
--
-- @param action string 动作名称，对应 keymap 中的键
-- @return boolean true 表示动作正在进行中，false 表示未按下
-- @usage
--   if input.isDown('move_up') then
--       player.y = player.y - speed
--   end
function input.isDown(action)
    -- 从 keymap 获取该动作对应的按键列表
    local keys = input.keymap[action]
    -- 如果动作不存在，返回 false
    if not keys then return false end

    -- 遍历所有绑定的按键
    for _, k in ipairs(keys) do
        -- 检查是否是鼠标按键（以 'mouse' 开头）
        if k:sub(1, 5) == 'mouse' then
            -- 提取鼠标按钮编号（mouse1 -> 1）
            local btn = tonumber(k:sub(6))
            -- 检查鼠标按钮是否按下
            if love.mouse.isDown(btn) then return true end
        else
            -- 键盘按键：使用 LÖVE 的键盘状态查询
            if love.keyboard.isDown(k) then return true end
        end
    end
    -- 所有按键都未按下
    return false
end

-- ============================================================================
-- 模拟轴输入函数
-- ============================================================================

--- 获取模拟轴（Axis）的值
-- 用于处理需要连续方向值的操作，如移动向量计算
-- 返回值范围：-1（负方向）到 1（正方向），0 表示无输入
--
-- 常见用法：
--   move_x < 0 表示向左，move_x > 0 表示向右
--   move_y < 0 表示向上，move_y > 0 表示向下
--   可以同时两个方向有值（如斜向移动）
--
-- @param axisName string 轴名称，支持 'move_x' 和 'move_y'
-- @return number 轴值，范围 -1 到 1
-- @usage
--   local dx = input.getAxis('move_x')
--   local dy = input.getAxis('move_y')
--   player.velocity = Vector.new(dx, dy) * speed
function input.getAxis(axisName)
    -- ==================== X轴（水平移动） ====================
    if axisName == 'move_x' then
        local val = 0
        -- 向右移动：正值
        if input.isDown('move_right') then val = val + 1 end
        -- 向左移动：负值
        if input.isDown('move_left') then val = val - 1 end
        return val -- 返回范围 [-1, 1]

        -- ==================== Y轴（垂直移动） ====================
    elseif axisName == 'move_y' then
        local val = 0
        -- 向下移动：正值（符合屏幕坐标系，Y向下增大）
        if input.isDown('move_down') then val = val + 1 end
        -- 向上移动：负值
        if input.isDown('move_up') then val = val - 1 end
        return val -- 返回范围 [-1, 1]
    end

    -- 未知轴名返回 0
    return 0
end

-- ============================================================================
-- 鼠标世界坐标转换
-- ============================================================================

--- 获取鼠标在游戏世界坐标系中的位置
-- 屏幕坐标（鼠标返回的坐标）是相对于窗口左上角的
-- 需要加上相机偏移量才能得到世界坐标
--
-- @param state 全局状态表，需要访问 state.camera 获取相机位置
-- @return number 世界X坐标
-- @return number 世界Y坐标
-- @usage
--   local worldX, worldY = input.getMouseWorld(state)
--   -- 用于计算射击方向、点击世界物体等
function input.getMouseWorld(state)
    -- 获取鼠标在屏幕上的当前位置
    local mx, my = love.mouse.getPosition()

    -- 从状态表获取相机位置（如果不存在则默认为0,0）
    local camX = state.camera and state.camera.x or 0
    local camY = state.camera and state.camera.y or 0

    -- 屏幕坐标 + 相机偏移 = 世界坐标
    return mx + camX, my + camY
end

-- ============================================================================
-- 角度计算函数
-- ============================================================================

--- 计算从指定点到鼠标位置的角度
-- 返回值是以弧度为单位的朝向角度，可直接用于旋转和方向计算
--
-- 角度定义（符合数学惯例）：
--   0 弧度 = 正右方向（X轴正方向）
--   π/2 弧度 = 正下方向（Y轴正方向）
--   π 弧度 = 正左方向（X轴负方向）
--   -π/2 弧度 = 正上方向（Y轴负方向）
--
-- @param state 全局状态表（用于获取鼠标世界位置）
-- @param fromX number 起点的X坐标（可选，默认为0）
-- @param fromY number 起点的Y坐标（可选，默认为0）
-- @return number 弧度表示的角度值
-- @usage
--   -- 计算从玩家到鼠标的角度
--   local angle = input.getAimAngle(state, player.x, player.y)
--   -- 用于设置子弹方向
--   bullet.dx = math.cos(angle) * speed
--   bullet.dy = math.sin(angle) * speed
function input.getAimAngle(state, fromX, fromY)
    -- 获取鼠标在世界坐标系中的位置
    local mx, my = input.getMouseWorld(state)

    -- 计算从起点到鼠标的向量角度
    -- math.atan2(dy, dx) 返回向量 (dx, dy) 与X轴的夹角（弧度）
    return math.atan2(my - (fromY or 0), mx - (fromX or 0))
end

-- ============================================================================
-- 按键匹配辅助函数
-- ============================================================================

--- 检查指定按键是否属于某个动作的绑定
-- 主要用于 love.keypressed 事件中，判断按键是否对应某个游戏动作
--
-- 与 isDown 的区别：
--   - isDown：检查按键的"持续状态"（是否按住）
--   - isActionKey：检查按键的"触发事件"（是否刚按下）
--
-- @param key string 要检查的按键名
-- @param action string 动作名称
-- @return boolean true 表示该按键属于该动作的绑定
-- @usage
--   function love.keypressed(key)
--       if input.isActionKey(key, 'fire') then
--           player:shoot()
--       end
--   end
function input.isActionKey(key, action)
    -- 获取动作对应的按键列表
    local keys = input.keymap[action]
    if not keys then return false end

    -- 遍历检查是否有匹配的按键
    for _, k in ipairs(keys) do
        if k == key then return true end
    end
    return false
end

-- ============================================================================
-- 模块返回
-- ============================================================================

-- 返回 input 模块，供其他模块 require 使用
return input
