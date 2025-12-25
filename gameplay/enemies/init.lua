-- enemies/init.lua
-- 敌人模块索引文件
-- 统一导出所有敌人相关的子模块

local enemies = {}

-- 子模块引用
enemies.ai = require('gameplay.enemies.ai')
enemies.loot = require('gameplay.enemies.loot')

-- 导出AI状态常量
enemies.AI_STATES = enemies.ai.STATES

return enemies
