# Build System Refactor Plan (Warframe-Style)

## Overview
Transform the game's combat mechanics from simple flat values to a deep, scalable system inspired by Warframe. This involves three main pillars:
1.  **Critical Hits**: Chance to deal multiplied damage.
2.  **Multishot**: Chance/Amount to spawn extra projectiles per shot.
3.  **Status Chance**: Chance to apply elemental effects (Burn, Freeze, etc.) per hit.

## Progress Tracking

### Phase 1: Critical Hit System (Completed)
- [x] **Data**: Added `critChance` and `critMultiplier` to `state.lua`.
- [x] **Logic**: Implemented RNG check in `projectiles.lua` and `weapons.lua`.
- [x] **Visuals**: Added yellow text and scaling for crits in `enemies.lua`.

### Phase 2: Multishot System (Completed)
- [x] **Data**: Added `amount` (Multishot) to `state.lua`.
- [x] **Logic**: Updated `weapons.lua` to loop projectile spawning based on `amount`.
    - Logic: `floor(amount)` guarantees X shots. `amount % 1` gives chance for one more.
    - Currently implemented as simple `floor(amount)` loop for now, or `getProjectileCount` helper?
    - *Note*: `weapons.lua` uses `getProjectileCount` which handles the RNG for the fractional part.

### Phase 3: Status Chance System (Completed)
- [x] **Data**: Added `statusChance` to `state.lua` (default 1.0 for now).
- [x] **Logic**: Updated `weapons.lua` (instant hit) and `projectiles.lua` (projectiles) to check `math.random() < statusChance` before applying status.
- [x] **Integration**: Ensured all weapon types (AoE, Projectile, Melee) respect this stat.

## Next Steps
- [x] **UI**: Display these stats in the weapon selection/upgrade menu.
    - Added stats display (Crit, Status, Multishot) to the Level Up screen in `draw.lua`.
- [x] **Upgrades**: Add passive items or upgrades that boost these specific stats.
    - Added `Clover` (+10% Crit Chance).
    - Added `Titanium Skull` (+20% Crit Damage).
    - Added `Venom Vial` (+20% Status Chance).
- [x] **Balancing**: Adjust base values in `state.lua` (currently placeholders).
    - Adjusted base `statusChance` for all weapons:
        - `Oil Bottle`: 0.8 (High reliability)
        - `Fire Wand`: 0.3 (Moderate) -> `Hellfire`: 0.5
        - `Ice Ring`: 0.3 (Moderate) -> `Absolute Zero`: 0.6
        - `Throwing Knife`: 0.2 (Low, relies on fire rate) -> `Thousand Edge`: 0.2
        - `Static Orb`: 0.4 (Moderate) -> `Thunder Loop`: 0.5
        - `Warhammer`: 0.5 (Moderate) -> `Earthquake`: 0.6
    - This makes the `Venom Vial` (+20% Status Chance) a valuable upgrade for ensuring effects trigger.
