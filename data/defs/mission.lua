local defs = {
    spawn = {
        preSpawnRange = {
            baseTileMult = 6,
            screenMult = 0.55,
            minTileMult = 4,
            maxTileMult = 14
        },
        minDist = {
            baseMin = 90,
            baseMax = 220,
            roomScale = 0.35,
            playerPad = 26
        },
        sample = {
            minAttempts = 12,
            defaultAttempts = 64,
            pickTries = 6,
            nearestFallback = 24
        },
        pack = {
            defaultCount = 6,
            eliteChance = 0,
            telegraphRadius = 22,
            telegraphIntensity = 1.0,
            baseDelay = 0.0,
            delayJitter = 0.0,
            sampleAttempts = 80
        },
        boss = {
            delay = 0.95,
            telegraphRadius = 54,
            telegraphIntensity = 1.25,
            sampleAttempts = 120
        },
        zone = {
            baseCount = 6,
            timeBonusMax = 6,
            timeBonusStep = 60,
            extraCountMin = 0,
            extraCountMax = 2,
            eliteChance = 0.18,
            eliteClearCount = 3
        },
        noContactDamageTimer = 0.65
    },
    chest = {
        exitSize = 26
    }
}

return defs
