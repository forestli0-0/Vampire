local defs = {
    defaults = {
        biomesTotal = 3,
        stagesPerBiome = 3
    },
    world = {
        tileSize = 32,
        stage = {
            explore = {
                navRefresh = 0.35,
                roomCountMin = 3,
                roomCountMax = 5,
                fallback = {w = 90, h = 90, roomMin = 8, roomMax = 14, corridorWidth = 2}
            },
            boss = {
                navRefresh = 0.25,
                roomCountMin = 1,
                roomCountMax = 1,
                fallback = {w = 70, h = 70, roomMin = 28, roomMax = 36, corridorWidth = 2}
            }
        }
    }
}

return defs
