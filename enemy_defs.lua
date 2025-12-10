local enemyDefs = {
    skeleton = {
        hp = 10,
        speed = 50,
        size = 16,
        color = {0.8, 0.8, 0.8}
    },
    bat = {
        hp = 5,
        speed = 150,
        size = 12,
        color = {0.6, 0, 1}
    },
    plant = {
        hp = 35,
        speed = 30,
        size = 22,
        color = {0, 0.7, 0.2},
        shootInterval = 3,
        bulletSpeed = 180,
        bulletDamage = 10,
        bulletLife = 5,
        bulletSize = 10
    }
}

return enemyDefs
