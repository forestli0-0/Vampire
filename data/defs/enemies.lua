--[[
添加新敌人的模板：
enemyDefs.my_enemy = {
    hp = 10,              -- 基础生命值
    shield = 0,           -- 可选护盾值（可自动回复）
    armor = 0,            -- 可选护甲值（减少受到的伤害）
    speed = 50,           -- 移动速度（朝向玩家移动）
    size = 16,            -- 碰撞箱大小（正方形）
    color = {1, 1, 1},    -- 绘制颜色（RGB）
    spawnDistance = 500,  -- 可选：生成时距离玩家的半径
    -- 可选的射击行为（纯近战敌人可省略）
    shootInterval = 3,    -- 射击间隔（秒）
    bulletSpeed = 180,    -- 子弹速度
    bulletDamage = 10,    -- 子弹伤害
    bulletLife = 5,       -- 子弹存活时间（秒）
    bulletSize = 10       -- 子弹大小
}

攻击方式通用参数：
- range: 最大攻击距离
- rangeMin: 最小攻击距离（远程敌人需要保持距离）
- windup: 攻击前摇时间（秒）
- cooldown: 攻击冷却时间（秒）
- damage: 伤害值
- w: 攻击权重（影响AI选择该攻击的概率，权重越高越容易被选中）
- bulletSpeed: 子弹速度
- bulletLife: 子弹存活时间
- bulletSize: 子弹大小
- count: 发射数量（弹幕）
- spread: 散射角度（弧度）
- telegraphWidth: 攻击预警宽度
- telegraphLength: 攻击预警长度
- interruptible: 是否可被打断
- explosive: 是否爆炸
- splashRadius: 爆炸范围

AI行为配置参数：
- type: AI类型（'melee'近战, 'ranged'远程, 'charger'冲锋, 'boss'Boss, 'support'支援, 'suicide'自爆）
- preferredRange: 远程敌人理想距离
- kiteRange: 开始风筝的距离阈值
- retreatThreshold: 血量低于此值时撤退（0-1）
- retreatDuration: 撤退持续时间（秒）
- noRetreat: 是否永不撤退
- berserkThreshold: Boss狂暴血量阈值
- berserkSpeedMult: 狂暴速度倍率
- berserkDamageMult: 狂暴伤害倍率

尺寸属性说明：
- size: 碰撞箱大小（用于碰撞检测）
- visualSize: 视觉显示大小（用于渲染缩放）
- 设计规范：小型=27px, 标准=36px, 中型=48px, 重型=60px, Boss=64px
]]

-- 敌人定义表
local enemyDefs = {
    -- ========== 基础敌人（早期游戏） ==========
    
    -- 骷髅：基础近战敌人，会投掷骨头
    skeleton = {
        hp = 45,
        speed = 60,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小（标准型）
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH',  -- 血肉类型（影响伤害计算）
        attacks = {
            melee = {range = 55, windup = 0.4, cooldown = 1.2, damage = 18, w = 6},  -- 近战攻击：范围55，前摇0.4秒，冷却1.2秒，伤害18，权重6
            throw = {range = 200, rangeMin = 60, windup = 0.5, cooldown = 2.0, damage = 15, bulletSpeed = 365, bulletLife = 2, bulletSize = 8, w = 3}  -- 投掷攻击：范围200-60，前摇0.5秒，冷却2秒，伤害15，子弹速度365，存活2秒，权重3
        },
        -- AI行为配置：近战型
        aiBehavior = {
            type = 'melee',  -- 近战类型
            retreatThreshold = 0.2,  -- 血量低于20%时撤退
            retreatDuration = 1.0,  -- 撤退1秒
        }
    },
    
    -- 蝙蝠：快速近战敌人，会跳跃攻击
    bat = {
        hp = 25,
        speed = 100,
        size = 18,  -- 碰撞箱大小
        visualSize = 27,  -- 视觉大小（小型）
        color = {0.6, 0, 1},
        healthType = 'FLESH',  -- 血肉类型
        attacks = {
            melee = {range = 45, windup = 0.25, cooldown = 0.6, damage = 12, w = 5},  -- 近战：快速攻击，前摇0.25秒，冷却0.6秒，范围45
            leap = {range = 150, rangeMin = 50, windup = 0.3, distance = 100, speed = 600, cooldown = 1.4, damage = 18, w = 4}  -- 跳跃攻击：范围150-50，前摇0.3秒，跳跃距离100，速度600，伤害18
        }
    },
    
    -- 植物：远程弹幕敌人，会保持距离射击
    plant = {
        hp = 90,
        speed = 35,
        size = 28,  -- 碰撞箱大小
        visualSize = 48,  -- 视觉大小（中型）
        color = {0, 0.7, 0.2},
        healthType = 'INFESTED',  -- 感染类型（影响伤害计算）
        attacks = {
            burst = {range = 400, rangeMin = 80, windup = 0.6, count = 3, spread = 0.4, bulletSpeed = 340, bulletDamage = 18, bulletLife = 4, bulletSize = 10, cooldown = 3.5, w = 10}  -- 弹幕攻击：范围400-80，发射3发，散射0.4弧度，冷却3.5秒
        },
        -- AI行为配置：远程型（风筝）
        aiBehavior = {
            type = 'ranged',  -- 远程类型
            preferredRange = 320,  -- 理想距离320
            kiteRange = 140,  -- 距离小于140时开始风筝
            retreatThreshold = 0.2,  -- 血量低于20%时撤退
            retreatDuration = 0.8,  -- 撤退0.8秒
        }
    },
    
    -- 冲锋者：冲锋型敌人，会直线冲锋和范围攻击
    charger = {
        hp = 55,
        speed = 70,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小（标准型）
        color = {0.95, 0.55, 0.15},
        healthType = 'INFESTED',  -- 感染类型
        attacks = {
            charge = {range = 320, rangeMin = 80, windup = 0.55, distance = 260, speed = 500, cooldown = 1.6, damage = 40, telegraphWidth = 40, w = 8},  -- 冲锋攻击：范围320-80，冲锋距离260，速度500，伤害40，预警宽度40
            slam = {range = 80, windup = 0.6, radius = 60, cooldown = 1.4, damage = 25, w = 5}  -- 范围攻击：范围80，半径60，伤害25
        },
        -- AI行为配置：冲锋型（更鲁莽）
        aiBehavior = {
            type = 'charger',  -- 冲锋类型
            retreatThreshold = 0.15,  -- 血量低于15%时撤退（比普通敌人更少撤退）
            retreatDuration = 0.6,  -- 撤退0.6秒
        }
    },
    
    -- 孢子迫击炮：远程AOE敌人，会发射范围攻击
    spore_mortar = {
        hp = 80,
        speed = 38,
        size = 24,  -- 碰撞箱大小
        visualSize = 42,  -- 视觉大小（中小型）
        color = {0.75, 0.25, 0.95},
        healthType = 'INFESTED',  -- 感染类型
        attacks = {
            slam = {range = 420, windup = 0.85, radius = 120, cooldown = 3.0, damage = 22, w = 7},  -- 范围攻击：范围420，半径120，伤害22
            burst = {range = 500, rangeMin = 150, windup = 0.7, count = 5, spread = 0.6, bulletSpeed = 310, bulletDamage = 10, bulletLife = 3, bulletSize = 8, cooldown = 4.0, w = 5}  -- 弹幕攻击：范围500-150，发射5发，散射0.6弧度
        }
    },
    
    -- ========== 训练假人（用于测试） ==========
    
    -- 基础假人：无护盾无护甲
    dummy_pole = {
        hp = 800,
        shield = 0,
        armor = 0,
        speed = 0,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小
        color = {0.8, 0.8, 0.8},
        healthType = 'FLESH',  -- 血肉类型
        noContactDamage = true,  -- 无接触伤害
        noDrops = true,  -- 不掉落物品
        isDummy = true  -- 标记为假人
    },
    
    -- 护盾假人：有护盾，用于测试护盾机制
    dummy_shield = {
        hp = 600,
        shield = 300,
        armor = 0,
        speed = 0,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小
        color = {0.6, 0.8, 1.0},
        healthType = 'FLESH',  -- 血肉类型
        shieldType = 'SHIELD',  -- 护盾类型（影响伤害计算）
        noContactDamage = true,  -- 无接触伤害
        noDrops = true,  -- 不掉落物品
        isDummy = true  -- 标记为假人
    },
    
    -- 护甲假人：有护甲，用于测试护甲机制
    dummy_armor = {
        hp = 600,
        shield = 0,
        armor = 250,
        speed = 0,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小
        color = {1.0, 0.9, 0.4},
        healthType = 'FLESH',  -- 血肉类型
        armorType = 'FERRITE_ARMOR',  -- 铁素护甲（影响伤害计算）
        noContactDamage = true,  -- 无接触伤害
        noDrops = true,  -- 不掉落物品
        isDummy = true  -- 标记为假人
    },
    
    -- 完整假人：有护盾和护甲，用于综合测试
    dummy_full = {
        hp = 600,
        shield = 220,
        armor = 150,
        speed = 0,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小
        color = {0.7, 0.9, 0.9},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        shieldType = 'SHIELD',  -- 护盾类型
        armorType = 'FERRITE_ARMOR',  -- 铁素护甲
        noContactDamage = true,  -- 无接触伤害
        noDrops = true,  -- 不掉落物品
        isDummy = true  -- 标记为假人
    },
    
    -- ========== 中期敌人（有护盾和护甲） ==========
    
    -- 盾牌长矛兵：有护盾和护甲，会盾击
    shield_lancer = {
        hp = 65,
        shield = 70,
        armor = 30,
        speed = 55,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小（标准型）
        color = {0.2, 0.5, 1},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        shieldType = 'SHIELD',  -- 护盾类型
        armorType = 'FERRITE_ARMOR',  -- 铁素护甲
        attacks = {
            melee = {range = 60, windup = 0.5, cooldown = 2.0, damage = 15, w = 5},  -- 近战攻击：范围60，前摇0.5秒，冷却2秒，伤害15
            shield_bash = {range = 120, windup = 0.4, distance = 80, speed = 400, cooldown = 3.0, damage = 18, knockback = 100, telegraphWidth = 30, w = 4}  -- 盾击：范围120，前摇0.4秒，冲锋距离80，速度400，伤害18，击退100，预警宽度30
        }
    },
    
    -- 重装甲蛮兵：高护甲坦克，会范围攻击
    armored_brute = {
        hp = 200,
        armor = 300,
        speed = 28,
        size = 36,  -- 碰撞箱大小（重型敌人碰撞箱较大）
        visualSize = 60,  -- 视觉大小（重型）
        color = {0.8, 0.6, 0.1},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        armorType = 'ALLOY_ARMOR',  -- 合金护甲（更高防御）
        attacks = {
            melee = {range = 70, windup = 0.7, cooldown = 2.5, damage = 25, w = 5},  -- 近战攻击：范围70，前摇0.7秒，冷却2.5秒，伤害25
            slam = {range = 100, windup = 1.0, radius = 100, cooldown = 4.0, damage = 35, w = 4}  -- 范围攻击：范围100，前摇1秒，半径100，伤害35
        }
    },
    
    -- Boss：树人（Treant）- 游戏Boss
    boss_treant = {
        hp = 3600,
        shield = 1500,
        armor = 250,
        speed = 50,
        size = 48,  -- 碰撞箱大小（Boss碰撞箱）
        visualSize = 64,  -- 视觉大小（Boss）
        color = {0.9, 0.25, 0.25},
        spawnDistance = 620,  -- 生成距离620
        bulletSpeed = 220,  -- 子弹速度
        bulletDamage = 22,  -- 16 → 22 子弹伤害提升
        bulletLife = 6,  -- 子弹存活6秒
        bulletSize = 14,  -- 子弹大小14
        contactDamage = 20,  -- 14 → 20 接触伤害提升
        tenacity = 0.9,  -- 韧性（减少控制效果）
        hardCcImmune = true,  -- 免疫硬控
        attacks = {
            -- 3种可读的Boss招式：锥形弹幕（远程）、范围攻击（AOE）、冲锋（直线冲刺）
            burst = {rangeMin = 260, range = 1200, w = 5, windup = 0.75, count = 7, spread = 0.95, bulletSpeed = 240, bulletDamage = 20, bulletLife = 6, bulletSize = 14, cooldown = 2.2, telegraphWidth = 58, telegraphLength = 520, interruptible = false},  -- 锥形弹幕：范围260-1200，发射7发，散射0.95弧度，预警宽度58，长度520，不可打断
            slam  = {range = 760, w = 3, windup = 1.25, radius = 150, cooldown = 2.8, damage = 30, interruptible = false},  -- 范围攻击：范围760，前摇1.25秒，半径150，伤害30，不可打断
            charge = {range = 420, w = 3, windup = 0.70, distance = 420, speed = 720, cooldown = 2.6, damage = 35, telegraphWidth = 56, interruptible = false}  -- 冲锋：范围420，前摇0.7秒，距离420，速度720，伤害35，预警宽度56，不可打断
        },
        animKey = 'plant',  -- 使用植物动画
        isBoss = true,  -- 标记为Boss
        noDrops = true,  -- 不掉落物品（Boss有独立掉落）
        healthType = 'FOSSILIZED',  -- 化石类型（Boss特有）
        shieldType = 'PROTO_SHIELD',  -- 原型护盾（Boss特有）
        armorType = 'INFESTED_SINEW',  -- 感染肌腱（Boss特有）
        -- AI行为配置：Boss狂暴
        aiBehavior = {
            type = 'boss',  -- Boss类型
            berserkThreshold = 0.25,  -- 血量低于25%时狂暴
            berserkSpeedMult = 1.5,  -- 狂暴速度提升1.5倍
            berserkDamageMult = 1.35,  -- 狂暴伤害提升1.35倍
            noRetreat = true,  -- Boss永不撤退
        }
    },
    
    -- ========== 第一批：简单远程敌人（Warframe风格） ==========
    
    -- 枪兵：基础远程步枪兵，单发精准射击
    lancer = {
        hp = 40,
        speed = 50,
        size = 22,  -- 碰撞箱大小
        visualSize = 33,  -- 视觉大小（小型）
        color = {0.6, 0.6, 0.7},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        attacks = {
            shoot = {range = 350, rangeMin = 100, windup = 0.6, cooldown = 1.2, 
                     count = 1, spread = 0.05, bulletSpeed = 585, bulletDamage = 15,  -- cooldown 1.8 → 1.2 冷却时间缩短
                     bulletLife = 3, bulletSize = 6, w = 10}  -- 射击：范围350-100，前摇0.6秒，冷却1.2秒，单发，散射0.05弧度，子弹速度585，伤害15
        },
        -- AI行为配置：远程型（风筝）
        aiBehavior = {
            type = 'ranged',  -- 远程类型
            preferredRange = 280,  -- 理想距离280
            kiteRange = 120,  -- 距离小于120时开始风筝
            retreatThreshold = 0.25,  -- 血量低于25%时撤退
        }
    },
    
    -- 重机枪手：持续火力压制，有护甲
    heavy_gunner = {
        hp = 140,
        armor = 80,
        speed = 30,
        size = 28,  -- 碰撞箱大小
        visualSize = 48,  -- 视觉大小（中型）
        color = {0.5, 0.4, 0.3},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        armorType = 'FERRITE_ARMOR',  -- 铁素护甲
        attacks = {
            burst = {range = 320, rangeMin = 80, windup = 0.4, cooldown = 2.0,
                     count = 6, spread = 0.35, bulletSpeed = 495, bulletDamage = 10,  -- 6 → 10 伤害提升
                     bulletLife = 2.5, bulletSize = 5, w = 10}  -- 弹幕攻击：范围320-80，前摇0.4秒，冷却2秒，发射6发，散射0.35弧度，伤害10
        },
        -- AI行为配置：远程型（不风筝，坦克）
        aiBehavior = {
            type = 'ranged',  -- 远程类型
            preferredRange = 200,  -- 理想距离200
            retreatThreshold = 0.15,  -- 重装不容易逃跑，血量低于15%时撤退
        }
    },
    
    -- 弩手：狙击手，长前摇，高伤害，有预警线
    ballista = {
        hp = 50,
        speed = 25,
        size = 22,  -- 碰撞箱大小
        visualSize = 33,  -- 视觉大小（小型）
        color = {0.4, 0.5, 0.6},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        attacks = {
            snipe = {range = 600, rangeMin = 200, windup = 1.2, cooldown = 4.0,
                     count = 1, spread = 0, bulletSpeed = 845, bulletDamage = 45,  -- 35 → 45 伤害提升
                     bulletLife = 3, bulletSize = 8, 
                     telegraphLength = 400, telegraphWidth = 8, w = 10}  -- 狙击：范围600-200，前摇1.2秒，冷却4秒，单发精准，子弹速度845，伤害45，预警长度400，宽度8
        }
    },
    
    -- 炮手：火箭发射器，有AOE爆炸
    bombard = {
        hp = 100,
        armor = 60,
        speed = 35,
        size = 24,  -- 碰撞箱大小
        visualSize = 42,  -- 视觉大小（中小型）
        color = {0.8, 0.3, 0.2},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        armorType = 'ALLOY_ARMOR',  -- 合金护甲
        attacks = {
            rocket = {range = 400, rangeMin = 120, windup = 0.9, cooldown = 3.5,
                      count = 1, spread = 0, bulletSpeed = 390, bulletDamage = 40,  -- 28 → 40 伤害提升
                      bulletLife = 4, bulletSize = 14,
                      explosive = true, splashRadius = 70, w = 10}  -- 火箭：范围400-120，前摇0.9秒，冷却3.5秒，单发，子弹速度390，伤害40，爆炸，范围70
        }
    },
    
    -- ========== 第二批：特殊机制敌人 ==========
    
    -- 蝎子：钩爪将玩家拉近
    scorpion = {
        hp = 60,
        speed = 65,
        size = 24,  -- 碰撞箱大小
        visualSize = 36,  -- 视觉大小（标准型）
        color = {0.9, 0.7, 0.2},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        attacks = {
            grapple = {range = 280, rangeMin = 80, windup = 0.5, cooldown = 5.0,
                       pullDistance = 120, damage = 12, telegraphWidth = 12, w = 6},  -- 钩爪：范围280-80，前摇0.5秒，冷却5秒，拉动距离120，伤害12，预警宽度12
            melee = {range = 55, windup = 0.35, cooldown = 1.5, damage = 15, w = 5}  -- 近战：范围55，前摇0.35秒，冷却1.5秒，伤害15
        }
    },
    
    -- 古代治疗者：光环治疗附近敌人
    ancient_healer = {
        hp = 150,
        speed = 45,
        size = 32,  -- 碰撞箱大小（较大）
        visualSize = 54,  -- 视觉大小（重较型）
        color = {0.3, 0.8, 0.4},
        healthType = 'INFESTED',  -- 感染类型
        healAura = {radius = 160, healRate = 12},  -- 治疗光环：半径160，每秒治疗12点生命值（8 → 12）
        attacks = {
            melee = {range = 65, windup = 0.6, cooldown = 2.2, damage = 18, w = 10}  -- 近战：范围65，前摇0.6秒，冷却2.2秒，伤害18
        },
        -- AI行为配置：支援型（更容易撤退）
        aiBehavior = {
            type = 'support',  -- 支援类型
            retreatThreshold = 0.4,  -- 治疗者更容易撤退，血量低于40%时撤退
            retreatDuration = 1.8,  -- 撤退1.8秒
        }
    },
    
    -- 易爆跑者：快速自爆敌人
    volatile_runner = {
        hp = 20,
        speed = 110,
        size = 18,  -- 碰撞箱大小（小型）
        visualSize = 27,  -- 视觉大小（小型）
        color = {1.0, 0.4, 0.1},
        healthType = 'INFESTED',  -- 感染类型
        onDeath = {explosionRadius = 80, damage = 45},  -- 死亡时爆炸：半径80，伤害45（30 → 45）
        attacks = {
            suicide = {range = 35, windup = 0.15, cooldown = 999,
                       damage = 50, explosionRadius = 80, w = 10}  -- 自爆攻击：范围35，前摇0.15秒，冷却999（几乎不会主动使用），伤害50，爆炸半径80
        },
        -- AI行为配置：自爆型（不撤退）
        aiBehavior = {
            type = 'suicide',  -- 自爆类型
            noRetreat = true,  -- 不撤退，直接冲向玩家
        }
    },
    
    -- 无效化者：气泡阻挡玩家技能
    nullifier = {
        hp = 80,
        shield = 250,
        speed = 40,
        size = 24,  -- 碰撞箱大小
        visualSize = 39,  -- 视觉大小（标准偏大）
        color = {0.3, 0.4, 0.8},
        healthType = 'CLONED_FLESH',  -- 克隆血肉类型
        shieldType = 'PROTO_SHIELD',  -- 原型护盾
        nullBubble = {radius = 100},  -- 无效化气泡：半径100，在此范围内禁用玩家技能
        attacks = {
            shoot = {range = 280, rangeMin = 60, windup = 0.5, cooldown = 2.0,
                     count = 1, spread = 0.1, bulletSpeed = 415, bulletDamage = 12,  -- 8 → 12 伤害提升
                     bulletLife = 2.5, bulletSize = 6, w = 10}  -- 射击：范围280-60，前摇0.5秒，冷却2秒，单发，散射0.1弧度，子弹速度415，伤害12
        }
    }
}

return enemyDefs
