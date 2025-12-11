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
- [ ] **UI**: Display these stats in the weapon selection/upgrade menu.
- [ ] **Upgrades**: Add passive items or upgrades that boost these specific stats (e.g., "Hollow Point" for Crit Damage, "Rifle Aptitude" for Status Chance).
- [ ] **Balancing**: Adjust base values in `state.lua` (currently placeholders).
