# Placeholder Assets (Stage 1)

This is a snapshot of placeholder or missing art/audio so you can start replacing.

## Weapons (missing sprites)
- absolute_zero -> expected `assets/weapons/absolute_zero.png` (placeholder file: `assets/weapons/absolute_zero.txt`)
- earthquake -> expected `assets/weapons/earthquake.png` (placeholder file: `assets/weapons/earthquake.txt`)
- hellfire -> expected `assets/weapons/hellfire.png` (placeholder file: `assets/weapons/hellfire.txt`)
- soul_eater -> expected `assets/weapons/soul_eater.png` (placeholder file: `assets/weapons/soul_eater.txt`)
- thousand_edge -> expected `assets/weapons/thousand_edge.png` (placeholder file: `assets/weapons/thousand_edge.txt`)
- thunder_loop -> expected `assets/weapons/thunder_loop.png` (placeholder file: `assets/weapons/thunder_loop.txt`)

Source: `render/assets.lua` loads `assets/weapons/<key>.png` for these keys.

## Projectile weapons missing bullet sprites (auto-mapped)
These projectile weapons do not have a bespoke `assets/weapons/<key>.png`. `render/assets.lua` now loads the shared placeholder `assets/weapons/bullet.png` (32×32), renders it at double scale for better readability, and falls back to a procedural dot if that image is missing:
- atomos
- boltor
- braton
- dread
- hek
- hellfire
- lanka
- lato
- lex
- paris
- strun
- thousand_edge
- thunder_loop
- vectis

## Pickups (procedural placeholder shapes)
These items are drawn with simple shapes in `render/draw.lua` when no sprite is present:
- ammo (crate box placeholder)
- shop_terminal
- pet_module_chip
- pet_upgrade_chip
- pet_contract
- pet_revive
- health_orb
- energy_orb
- mod_card
- chicken
- magnet

Notes:
- Sprites exist for `assets/pickups/chicken.png` and `assets/pickups/magnet.png`, but `render/assets.lua` only loads `chest` and `gem`, so these still render as placeholders.
- `chest` and `gem` have sprites; the placeholder rectangle only appears if the image fails to load.

## UI icons (placeholder draw)
- Button icon: colored square placeholder in `ui/widgets/button.lua`.
- Slot icon: colored rectangle placeholder in `ui/widgets/slot.lua` (plus default placeholder for empty).
- Shop price icon: circle placeholder in `ui/screens/shop.lua` (gold display uses an emoji icon there too).

## Pets
- Pet body is a colored circle placeholder in `render/draw.lua` (commented as replaceable with animation/skins).

## Enemy visuals
- When an enemy has no animation, `render/draw.lua` uses `assets/characters/skeleton/move_*.PNG` as a generic tinted fallback.

## Audio (SFX placeholders)
`render/assets.lua` falls back to generated beeps when these files are missing:
- `assets/sfx/shoot.wav`
- `assets/sfx/hit.wav`
- `assets/sfx/gem.wav`
- `assets/sfx/glass.wav`
- `assets/sfx/freeze.wav`
- `assets/sfx/ignite.wav`
- `assets/sfx/static.wav`
- `assets/sfx/bleed.wav`
- `assets/sfx/explosion.wav`

## Fallback visuals (only if assets are missing)
- Background tile fallback (procedural) if `assets/tiles/grass.png` is missing.
- Player animation fallback (procedural sheet) if `assets/characters/player/move_*.png` is missing.
