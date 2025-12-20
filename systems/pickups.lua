local pickups = {}

require('systems.pickups.xp')(pickups)
require('systems.pickups.gems')(pickups)
require('systems.pickups.chests')(pickups)
require('systems.pickups.floor')(pickups)

return pickups
