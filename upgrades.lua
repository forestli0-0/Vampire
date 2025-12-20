local upgrades = {}

require('upgrades.core')(upgrades)
require('upgrades.options')(upgrades)
require('upgrades.queue')(upgrades)
require('upgrades.apply')(upgrades)

return upgrades
