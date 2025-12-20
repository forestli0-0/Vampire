local upgrades = {}

require('systems.upgrades.core')(upgrades)
require('systems.upgrades.options')(upgrades)
require('systems.upgrades.queue')(upgrades)
require('systems.upgrades.apply')(upgrades)

return upgrades
