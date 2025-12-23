local catalog = {
    link_health = {
        name = "连接生命", desc = "生命继承",
        stat = 'healthLink', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    link_armor = {
        name = "连接护甲", desc = "护甲继承",
        stat = 'armorLink', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    bite = {
        name = "撕咬", desc = "攻击暴击",
        stat = 'critChance', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    maul = {
        name = "重击", desc = "攻击伤害",
        stat = 'damage', type = 'mult',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    pack_leader = {
        name = "群首", desc = "近战吸血",
        stat = 'meleeLeeech', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.05,0.10,0.15,0.20,0.25,0.30}
    },
    savage_bite = {
        name = "凶猛撕咬", desc = "攻击伤害↑ 暴击率↑",
        stat = 'damage', type = 'mult',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90},
        stats = {
            {stat = 'damage', type = 'mult', value = {0.15,0.30,0.45,0.60,0.75,0.90}},
            {stat = 'critChance', type = 'add', value = {0.05,0.10,0.15,0.20,0.25,0.30}}
        }
    },
    bonded_guard = {
        name = "守护誓约", desc = "生命继承↑ 护甲继承↑",
        stat = 'healthLink', type = 'add',
        cost = {5,6,7,8,9,10}, value = {0.10,0.20,0.30,0.40,0.50,0.60},
        stats = {
            {stat = 'healthLink', type = 'add', value = {0.10,0.20,0.30,0.40,0.50,0.60}},
            {stat = 'armorLink', type = 'add', value = {0.10,0.20,0.30,0.40,0.50,0.60}}
        }
    },

    -- --- 局内增强 MOD (New) ---
    overclock = {
        name = "过载运转", desc = "能力冷却时间缩短",
        stat = 'cooldownReduction', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0.06, 0.12, 0.18, 0.24, 0.30, 0.36}
    },
    catalyst = {
        name = "增强催化", desc = "能力状态触发层数增加",
        stat = 'extraStatusProcs', type = 'add',
        cost = {4,5,6,7,8,9}, value = {0, 1, 1, 2, 2, 3}
    },
    pet_vitality = {
        name = "宠物生命", desc = "宠物基础生命值提升",
        stat = 'maxHp', type = 'mult',
        cost = {2,3,4,5,6,7}, value = {0.12, 0.24, 0.36, 0.48, 0.60, 0.72}
    },

    -- --- 行为增强 (Augments) ---
    pulse_core = {
        name = "脉冲核心", desc = "磁力幼崽: 能力变为范围脉冲",
        group = 'augment', rarity = 'RARE', baseId = 'pet_module',
        requiresPetKey = 'pet_magnet', moduleId = 'pulse',
        cost = {9}, value = {1.0}
    },
    field_core = {
        name = "腐蚀核心", desc = "腐蚀史莱姆: 能力变为腐蚀力场",
        group = 'augment', rarity = 'RARE', baseId = 'pet_module',
        requiresPetKey = 'pet_corrosive', moduleId = 'field',
        cost = {9}, value = {1.0}
    },
    barrier_core = {
        name = "护罩核心", desc = "守护精灵: 能力变为产生护盾",
        group = 'augment', rarity = 'RARE', baseId = 'pet_module',
        requiresPetKey = 'pet_guardian', moduleId = 'barrier',
        cost = {9}, value = {1.0}
    }
}

return catalog
