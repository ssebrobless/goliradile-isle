# Goliradile Isle — Implementation Plan (single-implementer build package)

**Audience: one strong technical implementer.** This package is built so you never have to make a game-feel or taste call. Everything is either (1) a fully-decided system/value you implement completely, or (2) a deep-design surface where you build the *functional structure + a named hook* and leave the *taste fill* for a later pass. When in doubt, build the structural, functional version and leave the hook — do **not** invent a feel decision.

**Sources, in order:**
1. **This doc** — the build order, the implement-vs-stub taxonomy, the stub contracts, the closed gaps.
2. **`DESIGN_DECISIONS.md`** — the full decided design with rationale and `Main.gd` line refs (the "why" behind every call here). Read it first.
3. **Project memory** — background and constraints.

The earlier two-workstream split (`WORKSTREAM_SYSTEMS.md` / `WORKSTREAM_DESIGN.md`) is **retired** — it added an interface contract and a merge dance that aren't worth it on a single-file codebase. One stream, one branch.

---

## The core principle: two work modes

### Mode A — Implement fully (decided; just build it)
The design is settled and the values are chosen. Build it correctly, robustly, and in the grain of the existing single-file `Main.gd`. These need no taste from you:

- Flow-field pathfinder + persistent world (the keystone) — delete the night-wipe.
- 64×64 world grid + renderer camera-cull.
- `TILE_DEF` unified descriptor + the durability bug fixes (BULB/GLAPPLE_LAMP, dead `TRAP_MAX_HP`) + the wreck model + generic `_repair_structure` + 4-tier walls (values below).
- Multi-cell Mother Tree + `_in_tree_aura` power-root + tier machinery + soft-fail downgrade + Sap deposit/growth (first-pass Sap recipe below).
- Downed-player respawn + lose-condition rewire (Tree death = only game-over).
- Split-aggro fields + Den system + maturity/evolution + retaliation surge (starting curves below).
- Production plumbing: single munition (gunpowder), Auto-Miner, combat reclaim, `IRON_VEIN` rate-limit, manual+auto-loader re-arm.
- Turret-type counter **mechanism** + the first-pass matchup matrix below.
- UX **state-model skeleton**: collapse the 7 flags to `_active_overlay` + `_docked_station`, delete `_inv_open`/`_craft_open`/`_refresh_context_panel`, retained panels with `refresh()` + dirty flags (this fixes the dead-click bug at the architecture level).
- **Functional** UX: co-visible workspace, click-to-dock station recipe-merge, build mode (palette + ghost + validity), hybrid inventory.
- **Functional** legibility: HP bars (crocs/Tree/Dens), a tooltip frame + `desc` strings (provided below/in `DESIGN_DECISIONS.md`), `_stat_line` computed from defs, ammo readout.
- Pacing: `DAY_LENGTH=150`, the `_daylight()` bands, horde-free nights 1–2, first siege night 3, functional dusk countdown, yield retune (values below).
- Save additive fields; `play_sfx(id)` hook + call sites (no sounds yet); `--selftest` kept green with new invariants.

### Mode B — Build the hook, stub the fill (deep design; leave structure, defer taste)
Here the *mechanism* is yours but the *taste content* is deliberately deferred to a later focused pass (done against the running game, where it's far easier and better). For each, build the functional/structural version and leave the named hook clean and obvious — then **stop**. **You do not implement the design content; that fill is a separate design pass, not yours.** Do not polish these, do not guess the aesthetic, do not tune past the first-pass numbers. The target is functional-but-ugly on purpose — pretty/juicy/tuned is out of scope and the design pass would only redo it.

| Surface | You build (now) | You leave as a stub (later taste pass) |
|---|---|---|
| **Item icons** | The bake structure: one `_item_icons[id]` per `INV_ORDER`, baked at 24–32px via the existing primitives, with *crude but distinguishable* shapes | The actual icon artistry — a later art pass refines each shape |
| **Croc role silhouettes** | Distinct enough per-role shapes that roles are *readable* (rammer/flanker/sapper), or color+tag fallback | The polished silhouette art |
| **Programmatic Theme** | The single `Theme` object, applied at the CanvasLayer root, with placeholder palette/fonts | The visual identity (colors, fonts, styleboxes) — one tuning point for a later pass |
| **Juice / game-feel** | Named FX hooks called at the right sim moments (see Stub contracts), with minimal/no animation | Tween/particle choreography, damage-number feel — a later juice pass |
| **TECH overlay look** | The functional 3-column layout reading Tree/tech/threat state | The visual design (graph aesthetics, NEW-marker styling, anims) |
| **Dusk telegraph look** | Functional countdown + `_canvas_mod` shift + spawn-preview poofs | The polished radial-clock art and particle feel |
| **Deep balance** | First-pass numbers wired as tunable consts (below) | The real tuning — the Phase-7 playtest pass |
| **Audio** | The `play_sfx(id)` hook + call sites | Sound selection/mapping — a whole later pass |

The rule of thumb: **anything that needs the game *running* in front of a person to get right is a stub.** Anything decidable from the spec is Mode A.

---

## Closed gaps — first-pass values (so nothing blocks you)

These were the two open spec gaps; here are first-pass decisions. **Wire them as tunable consts and move on — they get tuned in Phase 7, not perfected now.**

### Sap conversion (first-pass)
- **Sap is a Tree-internal counter**, not an `INV_ORDER` item (avoids inventory clutter). The player interacts with the Tree to **deposit** surplus materials, which convert to Sap at fixed rates.
- Starting conversion rates (per unit deposited): `wood 1`, `stone 1`, `metal 3`, `glass 2`, `honey 2`, `food/berry 0.5` (low, so you can't trivialize growth by farming the easy resource).
- Tier-up costs (from `DESIGN_DECISIONS.md`): **40 / 90 / 180 / 320 Sap** for tiers 1→2→3→4→5.
- Deposit is a Tree-hub action (lives in the TECH overlay): pick a material + quantity → converts → Sap counter rises → tier-up triggers when the threshold is met.

### Economy mass-balance (first-pass sanity, tune later)
- Target feel: roughly **tier 1→2 by ~day 2–3**, full growth by the mid-game, *if* the player invests surplus rather than hoarding.
- Rough envelope at base yield 2/node and a ~107s build window: a day yields on the order of ~30–50 raw units; after spending on walls/turrets/ammo, expect ~10–20 Sap/day of surplus early → 40-Sap tier-2 in ~2–4 days. Auto-Miner throughput should be tuned so stone/metal for ammo + walls doesn't *also* have to fund Sap — Sap should come from *surplus*, creating the push to expand production.
- This is a starting envelope, **not** a solved spreadsheet. Phase 7 closes it empirically against the running build.

### First-pass tunable tables (starting values — see `DESIGN_DECISIONS.md` for the full ones)
- **Tree tier curve** (aura R / Tree HP / Sap-to-next): `1: 4/120/40 · 2: 6/200/90 · 3: 8/320/180 · 4: 10/460/320 · 5: 12/620/—`.
- **Wall tiers** (cost / break_hp / armor): `barricade: wood1/8/0 · wood: wood3/24/0 · stone: stone4/60/2 · reinforced: stone6+metal2+beeswax1/140/4`. Door stays a weak point (~break_hp 12, armor 0).
- **Pacing**: `DAY_LENGTH=150`; buildable window `f[0.07–0.78]` (~107s) incl. a dusk band `f[0.68–0.78]`; day-1 start `_time=0.10`; base TREE/STONE yield `1→2`.
- **Wave SIZE** by night: `n1–2: 0 · n3: 4 · n4: 7 · n5: 11 · n6: 16 · n7+: min(36, 16+(n−6)*6)` (raise `MONSTER_CAP` 28→36). Per-croc level from `(night−3)`.
- **Tree-aggro fraction** by night: `n4: 20% · n5: 30% · n6+: 40%` (ship via the interim fixed-cell beeline before the pather).
- **Turret↔croc counter matrix (first-pass)**: physical/boxer-drill-slicer → strong vs swarms, weak vs armored; ranged/sniper-mg-rocket → strong vs armored/single-target, weak vs swarms; support/engineer-adhesive-trickster → utility (slow/heal/disrupt), low raw DPS. Build the mechanism as a per-(turret-category × croc-role) multiplier table so the matrix is one edit to retune.

---

## Build order (single stream)

Keep `--selftest` green at every step. Each phase notes what to **build**, what to **stub**, and the **acceptance** bar.

- **Phase 0 — foundations (no pather).**
  Build: UX state-model skeleton (enum-collapse, `_docked_station`, retained `refresh()` + dirty flags — fixes dead-click); save additive fields; wire the Sap counter + deposit action stub; harness updates; `DAY_LENGTH`/bands/yield retune.
  Stub: leave the FX hooks + Theme object empty-but-present.
  Acceptance: opening a station while crafting works; no per-frame rebuild; selftest green; first build day ≈ 102s.

- **Phase 1 — durability descriptor + bug fixes.**
  Build: `TILE_DEF`; fix BULB/GLAPPLE_LAMP; delete dead `TRAP_MAX_HP["trap"]`; WRECK terrain; 4-tier walls (values above); generic `_repair_structure` (day+night, all structures); route both monster-damage sites through the descriptor (the `_damage_structure` damage-amount signature change).
  Acceptance: loud selftest on a missing `TILE_DEF` entry + the "no blocking tile without break_hp/impassable" invariant; destroyed wall → walkable wreck, no material deleted.

- **Phase 2 — THE KEYSTONE: flow-field pather + persistent world.**
  Build: cost grid (reads Phase-1 break_hp/armor); dual integration fields (`field_tree` on wall-change, `field_player` ~0.2s) via a bucket/BFS; separation nudge; delete the night-wipe + `REGROW_STONE` (sequence the stone deletion with the Auto-Miner in Phase 5 — until then keep a minimal stone source). 64×64 + camera-cull lands here.
  Acceptance: crocs route around walls and chew the thinnest gap; no straight-line jamming; per-frame budget holds at 64×64; selftest asserts a wall forces the expected detour.

- **Phase 3 — Mother Tree core loop.**
  Build: the 3×3 Tree as power-root (`_in_tree_aura` OR'd into the powered check at `Main.gd:1705`, **not** a `_compute_power` fold-in); HP + tier machinery + soft-fail downgrade; Sap deposit → growth; downed-player respawn; lose decoupled from player death (`_on_death` rewire); the **functional** TECH overlay (Mode B stub: layout + state, not the look). Ship the interim fixed-cell-beeline anti-kite here.
  Acceptance: aura powers in-range turrets; tier up/down moves radius + tech gates both ways; Tree at 0 HP is the only game-over; selftest covers tier transitions + lose condition.

- **Phase 4 — split-aggro + Dens + composition.**
  Build: `aggro` field per `CROC_DEFS`; crocs read `field_tree`/`field_player`; the sapper ignore-walls flag; Dens replace `_pool_shore` seeding; Den creep + maturity/evolution + retaliation surge; the Tree-aggro fraction curve; win = all Dens down AND Tree tier ≥3.
  Stub: Den visual evolution + croc silhouettes are Mode B (functional-distinct now, art later).
  Acceptance: crocs split per the composition table; Dens spawn/creep/mature/retaliate; win/lose fire correctly; selftest covers Den lifecycle.

- **Phase 5 — production pivot.**
  Build: single-munition swap (gunpowder, no sealant); Auto-Miner + scrap reclaim (sequence `REGROW_STONE` deletion *with* the miner); casing dawn-sweep; power-as-buff; turret-type counter mechanism + first-pass matrix; manual + auto-loader re-arm; `IRON_VEIN` rate-limit.
  Acceptance: turrets run on the munition; no orphaned outputs; mining renewable; selftest asserts every `INV_ORDER` item has ≥1 producer AND ≥1 consumer.

- **Phase 6 — UX functional completion + legibility.**
  Build: the co-visible workspace (functional), build-bar + ghost, hybrid inventory, the recipe-merge docking; HP bars; tooltip frame + `desc` strings + `_stat_line`; ammo readout. Bake *crude-but-distinct* item icons + croc silhouettes (Mode B structure).
  Stub: the Theme palette, icon artistry, and all juice stay as hooks for the later taste pass.
  Acceptance: every interaction in the `DESIGN_DECISIONS.md` interaction table works; nothing is a silent no-op; UI reads state from the published vars, never a shadow copy.

- **Phase 7 — first-pass balance + leave it tunable (NOT the deep pass).**
  Build: confirm all tunable consts are in one delimited block and the game is *playable* end-to-end with the first-pass numbers. The deep balance/juice/art tuning is the **later taste pass** — your job is to make sure it's a one-stop edit, not to perfect the feel.

---

## Stub contracts (the hooks to leave for the later taste pass)

Leave these named, placed, and obvious so the later pass is a fill-in, not a hunt:

- **FX hooks** (called at the sim moment, minimal/empty body now): `_fx_croc_death(pos)`, `_fx_wall_hit(cell)`, `_fx_build(cell)`, `_fx_tier_up()`, `_fx_damage_number(pos, amount, kind)`, `_fx_dusk_enter()`, `_fx_night_incoming()`. Wire them where the events fire; a later pass fills the Tween/particle bodies.
- **`play_sfx(id)`** — no-op now, called at the same event points; a later pass maps sounds.
- **Theme** — one `Theme` object + a single `_apply_theme()` applied at the root, placeholder values; a later pass owns its contents.
- **Icon/silhouette bake** — `_bake_item_icons()` and per-croc-role shapes as their own functions with crude output; a later art pass refines them in place.
- **TECH overlay render** — the functional layout in its own draw/build function reading Tree/tech/threat state; a later pass restyles it.
- **Tunable block** — collect every first-pass value (Sap rates, tier curve, wall tiers, pacing, wave curves, counter matrix) into **one clearly-delimited const block** so the deep-balance pass is one location.

---

## Global invariants & constraints (respect these throughout)

- **Single file.** Everything stays in `Main.gd` + procedural bake. `.tres`/GameDb and `TileMapLayer` are **not** prerequisites (optional later refactors). The 3×3 Tree footprint is the one thing that might justify `TileMapLayer` — only if PackedArrays prove painful.
- **Zero external ART assets** — all sprites/icons procedurally baked. (Audio may use files later; art may not.)
- **Never reorder/insert into the `Terrain` enum mid-list** — saves store raw enum ints. Append only.
- **Save is additive** — new fields load on old saves via `d.get(key, default)`; add a `"v"` branch only if `INV_ORDER`/`_resources` shift destructively. Demolishing a machine must still hand-erase its per-cell state dict.
- **`--selftest` is the safety net** — keep it green; a red harness is a blocker, not a warning. Update the asserts the new tables break (e.g. `_monsters.size()==MONSTER_BASE`, the debug-skip threshold).
- **Animated entities** must be in the `queue_redraw` gate or they render frozen; `_draw` overlays gate on the existing redraw mechanism.
- **Don't invent feel.** Where a value isn't decided here, use the first-pass number and flag it; where a surface is Mode B, leave the hook. Never silently ship a guessed taste decision as final.
