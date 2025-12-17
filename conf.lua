-- LÖVE2D configuration file
-- Sets up 640x360 logical resolution with integer scaling

function love.conf(t)
    t.identity = "vampire"
    t.version = "11.4"
    
    -- Window settings
    t.window.title = "Vampire Survivors"
    t.window.width = 1280           -- 2x scale default
    t.window.height = 720
    t.window.minwidth = 640         -- Minimum 1x scale
    t.window.minheight = 360
    t.window.resizable = true
    t.window.vsync = 1
    
    -- Pixel-art friendly settings
    t.window.msaa = 0               -- No anti-aliasing
    
    -- Modules
    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = false
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = false
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
end
