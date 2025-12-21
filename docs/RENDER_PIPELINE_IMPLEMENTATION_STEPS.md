# Render Pipeline Implementation Steps (Module + Function Level)
Project: Vampire
Version: v0.1
Owner: Tech Art / Rendering
Date: 2025-12-21

Purpose: Define concrete modules and function responsibilities required to implement the target neon render pipeline in LOVE2D.

---

## 1) New Module: render/pipeline.lua
Responsibilities:
- Own all render canvases.
- Orchestrate pass order (base -> emissive -> lighting -> bloom -> composite -> post -> UI).
- Provide debug views and quality tiers.

Functions to implement:
- pipeline.init(w, h)
  - Create canvases: base, emissive, light, bloom chain, composite.
  - Precompute blur kernels or shaders as needed.
- pipeline.resize(w, h)
  - Rebuild canvases with new dimensions.
- pipeline.beginFrame()
  - Reset state, set default clear colors.
- pipeline.drawBase(drawFn)
  - Set canvas to base and call drawFn().
- pipeline.drawEmissive(drawFn)
  - Set canvas to emissive, clear to black, call drawFn() with additive blend.
- pipeline.drawLights(drawFn)
  - Set canvas to light mask, call drawFn() (optional per tier).
- pipeline.applyBloom()
  - Run downsample -> blur -> upsample using emissive canvas.
- pipeline.compose()
  - Combine base + light + bloom into composite canvas.
- pipeline.postProcess()
  - Apply tone map, LUT, vignette, grain, chromatic.
- pipeline.drawUI(drawFn)
  - Draw UI directly to screen after post.
- pipeline.present()
  - Draw final result to screen based on debug view.
- pipeline.setDebugView(mode)
  - Modes: base, emissive, light, bloom, final.
- pipeline.setQualityTier(tier)
  - Toggle bloom, post, lighting by tier.

Call order (per frame):
1) beginFrame
2) drawBase
3) drawEmissive
4) drawLights
5) applyBloom
6) compose
7) postProcess
8) present
9) drawUI

---

## 2) Modify core/scenes/init.lua (render entry)
Goal: Replace bloom.preDraw/postDraw with pipeline calls.

Steps:
- Replace drawWorld() with pipeline sequencing.
- Keep UI draw after pipeline.present().

Suggested functions to add:
- scenes.drawWorld(state):
  - pipeline.beginFrame()
  - pipeline.drawBase(function() draw.renderBase(state) end)
  - pipeline.drawEmissive(function() draw.renderEmissive(state) end)
  - pipeline.drawLights(function() draw.renderLights(state) end)
  - pipeline.applyBloom()
  - pipeline.compose()
  - pipeline.postProcess()
  - pipeline.present()
  - pipeline.drawUI(function() ui.draw() end)

---

## 3) Modify render/draw.lua (pass separation)
Goal: Separate base, emissive, and light contributions.

Functions to add:
- draw.renderBase(state)
  - All non-emissive sprites and environment.
- draw.renderEmissive(state)
  - Only emissive layers (neon parts, VFX cores).
- draw.renderLights(state)
  - Dynamic lights (player, bullets, signage) as light shapes.
- draw.renderUI(state)
  - (Optional wrapper) call ui.draw().

Implementation notes:
- Reuse existing draw.render logic but guard per pass:
  - Pass gate: if pass == "base" then draw base sprites only.
  - Pass gate: if pass == "emissive" then draw emissive quads only.
- Avoid duplicate gameplay logic; only split draw paths.

---

## 4) Modify render/assets.lua (material variants)
Goal: Load emissive/normal variants next to base sprites.

Functions to add:
- assets.loadImageVariant(path, suffix)
  - Example: load base, then try base_emit / base_nrm.
- assets.loadSpriteSet(path)
  - Returns {base=img, emissive=imgOrNil, normal=imgOrNil}

Rules:
- If emissive missing, use a 1x1 black fallback.
- If normal missing, use flat normal (0.5, 0.5, 1.0).

---

## 5) Modify render/effects.lua and render/vfx.lua (emissive routing)
Goal: Ensure VFX glow goes to emissive pass.

Steps:
- Add effects.drawBase(state) and effects.drawEmissive(state).
- Route additive particles to emissive.
- Keep alpha smoke/dust in base.

Optional:
- Add vfx.drawEmissive(state, pass) to isolate glow.

---

## 6) Replace render/bloom.lua usage
Goal: Bloom should consume emissive canvas and output bloom canvas.

Steps:
- Change bloom module to accept source canvas.
- Expose bloom.apply(src, dst) for pipeline use.

Functions to add or update:
- bloom.apply(srcCanvas, dstCanvas)
- bloom.resize(w, h)

---

## 7) Debug Views and QA Counters
Goal: Provide fast visual inspection for artists and QA.

Steps:
- Add pipeline.setDebugView() and draw in present().
- Add debug counters to state: lights, particles, bloomClampHits.
- Hook keys in scenes.keypressed for debug view cycling.

---

## 8) Minimal Implementation Order (Safe Sequence)
1) Add render/pipeline.lua with base + present only (no visual change).
2) Split draw.render into renderBase and call from pipeline.
3) Add emissive pass using black fallback (visual change begins).
4) Integrate bloom.apply with emissive.
5) Add light mask pass (optional).
6) Add postProcess chain (tone map, LUT, vignette, grain).
7) Add debug views and QA counters.

---

## 9) Asset Contract (System Driven)
Per sprite:
- Base: required
- Emissive: required for neon assets
- Normal: optional, required for player/boss

Per VFX:
- Additive glow layer (emissive)
- Alpha body layer (base)

System decides these requirements and art must follow.

