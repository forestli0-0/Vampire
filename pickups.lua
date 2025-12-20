local pickups = {}

require('pickups.xp')(pickups)
require('pickups.gems')(pickups)
require('pickups.chests')(pickups)
require('pickups.floor')(pickups)

return pickups
