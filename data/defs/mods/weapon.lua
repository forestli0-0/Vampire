local catalog = {
    serration = {
        name = "膛线", desc = "伤害",
        stat = 'damage', type = 'mult',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    heavy_caliber = {
        name = "重装口径", desc = "伤害",
        stat = 'damage', type = 'mult',
        weaponType = 'ranged',
        cost = {6,7,8,9,10,11}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    split_chamber = {
        name = "分裂膛室", desc = "多重射击",
        stat = 'multishot', type = 'add',
        weaponType = 'ranged',
        cost = {5,6,7,8,9,10}, value = {0.15,0.30,0.45,0.60,0.75,0.90}
    },
    point_strike = {
        name = "致命一击", desc = "暴击率",
        stat = 'critChance', type = 'add',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    vital_sense = {
        name = "致命打击", desc = "暴击伤害",
        stat = 'critMult', type = 'add',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    speed_trigger = {
        name = "速度扳机", desc = "射速",
        stat = 'fireRate', type = 'mult',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    magazine_warp = {
        name = "弹匣扭曲", desc = "弹匣容量",
        stat = 'magSize', type = 'mult',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    fast_hands = {
        name = "快手", desc = "换弹速度",
        stat = 'reloadSpeed', type = 'mult',
        weaponType = 'ranged',
        cost = {3,4,5,6,7,8}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    status_matrix = {
        name = "异常矩阵", desc = "异常几率",
        stat = 'statusChance', type = 'add',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.10,0.20,0.30,0.40,0.50,0.60}
    },
    pressure_point = {
        name = "压力点", desc = "近战伤害",
        stat = 'damage', type = 'mult',
        weaponType = 'melee',
        cost = {4,5,6,7,8,9}, value = {0.20,0.40,0.60,0.80,1.00,1.20}
    },
    metal_auger = {
        name = "金属促退器", desc = "穿透",
        stat = 'pierce', type = 'add',
        weaponType = 'ranged',
        cost = {6,7,8,9,10,11}, value = {0.4, 0.8, 1.2, 1.6, 2.0, 2.4}
    },
    stabilizer = {
        name = "稳定器", desc = "降低后坐力",
        stat = 'recoil', type = 'mult',
        weaponType = 'ranged',
        cost = {3,4,5,6,7,8}, value = {0.15, 0.30, 0.45, 0.60, 0.75, 0.90}
    },
    guided_ordnance = {
        name = "制导法令", desc = "降低散射",
        stat = 'bloom', type = 'mult',
        weaponType = 'ranged',
        cost = {4,5,6,7,8,9}, value = {0.10, 0.20, 0.30, 0.40, 0.50, 0.60}
    }
}

return catalog
