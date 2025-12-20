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
    }
}

return catalog
