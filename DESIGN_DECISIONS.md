# Goliradile Isle — Design Decisions: Closing the Gap

**Will — this is the artifact that turns the locked direction into a buildable plan.**

> **Status — all decisions LOCKED (2026-06-21).** Will signed off on every recommendation. Net changes folded in below: **the map grows 50×50 → 64×64** (decision #19) to give the Den frontier real runway; **Dens gain Factorio-style maturity/evolution** (ignore one and it gets harder); and **ammo stays a single munition with counter-play in turret *types*, not ammo families** (decision #3 revised — the three-family graph is retained as an *optional later-depth layer*, not the baseline). See the **Decisions — LOCKED** section for the full list. The two former spec gaps (exact Sap conversion + one-page economy mass-balance) are now **closed with first-pass numbers in `IMPLEMENTATION_PLAN.md`** (to be tuned in playtest, not pre-solved). The build ships to a **single technical implementer** working from that plan — the earlier two-workstream split is superseded. The rest of the document's analysis stands as written.

We're past the "what kind of game is this" stage. The direction is settled: production-driven base defense, a Mother Tree central objective, lose-when-the-tree-dies (not when you die), flow-field pathfinding, persistent durability, renewable sustainability, retuned pacing, bees demoted to an input, and a ground-up co-visible UX. This document does not relitigate any of that. It makes the **open** parts concrete — the Tree loop, the economy graph, the combat/durability rules, the pacing numbers, and a fully-specified UX — resolves the contradictions between them, and ends with a numbered list of the calls only you can make.

**How to read it:** each section gives you a concrete recommendation with starting numbers and real `Main.gd` symbols, so an implementer can begin without guessing. Where I'm making a taste call on your behalf, I say so and it reappears in *Remaining taste decisions* at the end. The numbers are starting points to tune in playtest, not gospel — but the *shapes* are the design. One thing to internalize up front: **the flow-field pather plus deleting the night-wipe is the keystone.** Four of the five systems below are inert without it. The sequencing section makes this explicit so we don't build dependent work on sand.

---

## The Mother Tree loop

This is the most important open problem, so it gets the most concrete spec. **Top recommendation: the Mother Tree is the power root of your existing generator/wire network and the refinery for a single hub resource (Sap); you advance by clearing a finite, escalating set of croc-spawning Dens out in the world.** This unifies all six open sub-questions — generator, tiers, win, lose, push-out, downed-player — through one resource and one system that already exists.

The reason this is the right call and not the alternatives: a full power network is **already built and load-bearing**. `_generators` (idx→{oil,on,drain}), `_compute_power()` BFS-flooding power across `WIRE` tiles, turrets calling `_is_powered(t["cell"])` each frame and burning no `cup_wine` when powered (`Main.gd:1705`), and `POWER_DEMAND_NIGHT=6` (`Main.gd:256`) as an existing telegraphed "you must upgrade your power infrastructure" beat. We make the Tree *be* the generator root rather than bolting on a new system. Endless score-runs (option B) throw away the "advance/win" pressure you flagged as open; a roguelike-with-meta (option C) wants to discard the base each run, which fights the persistent-durability pillar and demands a meta-save layer we don't have. **Bounded Den-clear is the answer.**

### What the Tree produces (the generator)

The Tree is a **3×3 multi-cell structure** at world center, registered as a special entry in `_generators` with effectively infinite oil so the *wired* perimeter behaves exactly as it does today. On top of that, the Tree projects a **wireless power aura** of radius `R_tier`: any turret whose cell is within `R_tier` of the Tree footprint is powered for free. **Defending the Tree and powering your core turrets become literally the same act.**

> **Implementation honesty (resolving a cross-area contradiction):** the aura does *not* "fold into `_compute_power`" — that BFS only spreads along `Terrain.WIRE`. The aura is **net-new radius logic**, implemented as a separate `_in_tree_aura(cell)` distance test (mirror the `_adhesive_factor` idiom at `Main.gd:1266`) OR'd into the per-turret powered check at `Main.gd:1705`: `t["powered"] = _is_powered(t["cell"]) or _in_tree_aura(t["cell"])`. Leave `_compute_power` untouched for the wired perimeter. Note `_is_powered` already grants power one cell *adjacent* to any energized tile, so wired bleed is a separate 1-cell slop — don't double-count it in the aura math.

Coupling recommendation: **hybrid** — aura for the core ring, wires to extend to the perimeter. Build near the Tree = free power; build far = run wire from the Tree (or a built generator) or burn `cup_wine`. This keeps the existing wire/generator tech meaningful late-game and preserves the power-routing puzzle the code already supports. Repurpose `POWER_DEMAND_NIGHT=6`: the tier-1 aura covers the same small core a single generator covers today, the horde outscales it around night 4–6, and the existing dusk message at `Main.gd:939-941` becomes **"grow the Tree or wire the perimeter"** — reusing the built telegraph instead of inventing one.

### How it grows (Sap + tiers)

Sap is the **one hub resource** and the terminal sink for the entire production economy (see next section). You deposit surplus production into the Tree, it refines to Sap, the Tree grows. This is what makes "the tree produces/powers something, so defending and upgrading it are the same act" real: feed Tree → bigger aura + new tech.

| Tier | Aura R | Tree HP | Unlocks | Deposit to next |
|------|--------|---------|---------|-----------------|
| 1 (start) | 4 | 120 | basic turrets (boxer/sniper/mg), walls | 40 Sap |
| 2 | 6 | 200 | drill/slicer/rocket + extraction (kiln/juicer) | 90 Sap |
| 3 | 8 | 320 | support turrets (engineer/adhesive/trickster) + still/generator | 180 Sap |
| 4 | 10 | 460 | bee/beeswax advanced-turret tech, aquarium, sprinkler | 320 Sap |
| 5 (max) | 12 | 620 | top-tier ammo-tech + the **Bomb** to crack hardened Dens | — |

Each tier-up: a brief dawn ceremony (Tween + `CPUParticles2D`), full Tree heal, +HP, +aura, new hub tech rows light up. These numbers are a starting curve; the *shape* (aura and HP grow with tier, tech gates on tier) is the design.

### Win / advance — Dens

The horde spawns from a finite, growing set of **Crocodile Dens** (2×2 `BREAK_HP` structures out in the world, never near base). The island starts with **1 Den**; a new one erupts every ~2 nights at increasing proximity to the Tree — the inward creep *is* the escalation and the pressure to push out. Cap total active Dens (start: 4).

**Den maturity — Factorio nest-growth (locked).** Each Den tracks `maturity` (nights survived). Maturity raises the size/frequency of the waves it spawns and, at thresholds, **evolves** the Den — tougher croc roles, more HP, a visible grow (2×2 → 3×3). This makes **"clear it young or pay later"** the core push-out pressure: a *young* Den is solo-clearable by a brave dash; a *mature* Den effectively requires a forward turret outpost. So solo clears are **possible but dangerous** (decision #2), and the gradient teaches the outpost strategy organically instead of mandating it. Cost: a `maturity` int per Den + threshold logic.

**Map size — 64×64 (locked, decision #19).** The Den + maturity + push-out fantasy needs spatial runway that 50×50 can't give once the Tree aura and multiple creeping Dens compete for tiles. 64×64 yields three legible zones (safe aura **core** / contested outpost **mid** / Den **frontier**), room for 2–3 forward outposts, and a real multi-night creep runway — and it makes solo sorties *naturally* riskier (longer night exposure traveling out and back) without inflating Den HP. Free to change now: grid dims are `const`, and PackedArrays + the flow-field BFS scale fine to 4,096 cells. The one consequence: it makes the renderer **camera-cull non-optional** (already the planned fix for immediate-mode `_draw`).

**`_spawn_monsters` draws crocs from live Dens** — this maps directly onto the existing two-phase spawn (`_pool_shore` seeding, then random far-ground fallback at `Main.gd:1052-1077`): replace `_pool_shore` with per-Den shore cells, keep the far-ground fallback. More Dens alive = bigger, faster waves.

**WIN = all Dens destroyed AND Tree at Tier ≥3.** The tier gate stops a turtle from rushing Dens before earning the tech. Hardened Dens require the Tier-5 Bomb, gating the final push behind full Tree growth. This is bounded (a run ends in victory) yet replayable, and *not* a hard roguelike reset. Add an optional endless mode later for free by never stopping Den spawns.

> **Resolving the engineer-identity contradiction (mandatory architecture, not optional):** the headline "destroy all Dens" must NOT make solo melee the path to victory — that resurrects the player as primary DPS, exactly the center-of-gravity the locked identity moves away from. **Dens must be killable primarily by powered forward turret outposts** (built near the Den, wired or `cup_wine`-fueled, under aura-less risk), with hand-chipping as a slow, risky supplement only. Spec the Den HP pool so solo melee clear-time is punishingly long relative to a 1–2 turret outpost. You still must *sortie* — to build and defend the outpost — so push-out pressure survives, but turrets stay the DPS center. The exact ratio is a taste call (see decision #2); the turret-killable architecture is mandatory.

Destroying a Den triggers a **retaliation surge**: an immediate oversized wave from remaining Dens on the opposite side. You prep before every push (the Kingdom Two Crowns portal mechanic, validated).

### Lose — soft then hard

Split aggro (needs the pather): each night a designed fraction of the horde targets the Tree, the rest target you/turrets — telegraphed by a tint/icon on Tree-seekers. Tunable per night (~30% Tree-seekers early → 55% late).

- **Soft-fail:** if Tree HP crosses a tier threshold downward, it **drops a tier** — aura shrinks, now-uncovered turrets go dark mid-fight, some tech locks. Dramatic, recoverable by surviving the night and re-depositing Sap. This delivers the "setback not game-over" feel at the structure level and reuses the tier machinery in both directions for almost no extra code. **Recommended over a binary HP bar.**
- **Hard-fail (run over):** Tree HP hits 0. This is the **only** game-over. Replace the `_reset_game`-on-death path (`_on_death` at `Main.gd:2253`) with Tree-destroyed-as-only-game-over.
- **Tree repair is a siege job** (matches the durability pillar): repair with Sap/wood during the night under fire; only partial dawn regen (~+10%/dawn), never a painless full reset.

### Downed player

On 0 HP the player is **downed, not dead**. Respawn at the Tree after a short delay (~4s) at a flat Sap cost (~15 Sap), OR free-but-debuffed if Sap-broke. During the downed window you deal no damage and can't repair — a real setback that makes turret automation matter (the engineer fantasy). Keep `_lives` as an optional difficulty modifier but it no longer ends the run. **Flat Sap cost, escalating only within a single night** — keeps personal HP a meaningful setback (you bleed Sap = slower Tree growth) without spiraling into an unrecoverable death-loop.

### The hub panel

Standing adjacent to the Tree surfaces the hub as a **dedicated full-screen TECH overlay** (added to the UX `_active_overlay` enum — see UX section), not a cramped station card: three columns — (1) Tree status: tier, HP, aura radius, Sap stored, deposit-to-next-tier bar; (2) Tech tree: branch rows (turrets / extraction / ammo-tech / bee-tech) greyed by tier, with NEW markers; (3) Threat readout: Dens alive, next Den ETA, nights survived. This is the one place to understand "what to build/farm next."

---

## The production economy

**Top recommendation: the ammo-economy pivot, staged.** Today turrets run entirely on the **berry monoculture** — `TURRET_FUEL_MAX=100` abstract fuel refilled by pouring `cup_wine` (`Main.gd:369-371, 1688-1693`), and the generator that frees turrets from fuel burns `cup_oil`, *also* berry-derived. Stone is a true dead-end (only feeds nails/sling-ammo/walls), beeswax and honey are orphaned outputs read by no cost-side code, and nothing in the tech ladder makes a *better* turret. We re-route turret operation off berries onto a discrete munition, add renewable extraction, close the combat-reclaim loop, and promote beeswax to a real input.

> **DECISION UPDATE (#3 revised — locked).** Counter-play moves to turret **TYPES**, not ammo families: the sniper shreds armor, the splash turret eats swarms, etc. — chosen at *placement*, not manufactured and juggled in inventory. So the **baseline ships a SINGLE munition (gunpowder)**, and the three-family ammo graph below is retained as an **optional later-depth layer** (the depth we *can* add if turret-type counters aren't enough), not the Phase-1 plan. You still build a *mix* of turrets to counter croc types, so the turret loop stays the strategic centerpiece — with far less UX/inventory load. The staged plan already shipped single-munition first, so nothing downstream breaks; read the three-family graph through that lens.

### The target dependency graph

```
RENEWABLE EXTRACTION (scale by building MORE, never deplete)
  STONE ── hand-mine (finite, leaves DEPLETED_ROCK wreck)
        └─ AUTO-MINER [M] on a vein ──> +stone/tick forever   (Frostpunk Coal-Thumper)
  ORE   ── AUTO-MINER ──> metal_ore + (rare) IRON_VEIN gate mineral
  SAND  ── already infinite (keep, Main.gd:2907)
  WOOD  ── trees -> stumps -> regrow in place (capped, never in base)
  BEES  ── enclosure ──> honey + beeswax/tick     WORMS ──> fertilizer    FISH ──> food

INTERMEDIATES (kiln + new bench recipes)
  metal_ore ─[kiln]→ metal          sand ─[kiln]→ glass        wood ─[kiln]→ charcoal
  stone + charcoal ─[kiln]→ GUNPOWDER          beeswax + glue ─[bench]→ SEALANT
  honey + fish_bones ─[bench]→ COMPOUND

THREE TURRET AMMO FAMILIES  (each turret category eats ONE; distinct bottlenecks)
  PHYSICAL (boxer/drill/slicer)        metal + stone   ─[bench]→ SHOT     ── spine: AUTO-MINER
  RANGED   (sniper/mg/rocket)          charcoal + metal ─[bench]→ ROUNDS  ── spine: WOOD/forestry
  SUPPORT  (engineer/adhesive/trick.)  compound + sealant ─[bench]→ CHARGE── spine: BEES/apiary

OPTIONAL AMMO-TECH (Factorio: 1 extra step, never a forced tier — base always works)
  ROUNDS + extra metal ─→ AP_ROUNDS      (+dmg, ignores armor → armored crocs)
  SHOT   + sealant     ─→ INCENDIARY_SHOT (burn → healer packs / swarms)
  CHARGE + power       ─→ SHOCK_CHARGE    (chains → ice clusters)  [electric ammo]

COMBAT RECLAIM (deep nights pay for themselves)
  corpse ─→ bone(1) + hide(55%) + SCRAP(1, 40%)        SCRAP ─[kiln]→ metal (partial refund)
  spent ranged shots ─→ recoverable CASING (manual DAWN SWEEP) ─→ refund ROUNDS

POWER  generator+wire ──> powered turrets get +rate AND can load SHOCK_CHARGE  (defense upgrade)
                          ──> SAP DEPOSIT at the Tree = terminal sink for ALL of the above
```

### Resolving the contradictions in this graph

1. **The three families must have *distinct* bottlenecks or "run all three in parallel" is a lie.** As naively drawn, PHYSICAL and RANGED both route through stone+metal (the auto-miner), so two of three share one faucet. **Fix:** PHYSICAL stays metal+stone (the miner spine); **RANGED's gate is charcoal-from-WOOD** (tie it to forestry, so it competes with construction wood, not stone); SUPPORT stays the bee/honey spine. Now mining, forestry, and apiary are three independent faucets, each starving a different turret category if neglected.

2. **Phase-1 munition must not be gated behind bees.** The naive Phase-1 fuel (gunpowder + SEALANT) needs beeswax+glue, and bees unlock only via glass→kiln→bee_enclosure — that accidentally walls day-1 turret fuel behind the entire bee chain, defeating Phase 1's whole purpose. **Fix:** Phase-1 munition is **stone + charcoal → gunpowder, no sealant.** Sealant/bee inputs enter at Phase 3 (advanced ammo) and the reinforced-wall tier, where the bees-as-advanced-input lock actually belongs.

3. **Power-as-buff re-couples defense to berries — accept it as secondary.** Power buffing turrets needs `cup_oil` (berry-derived). Resolution: **unpowered turrets stay fully combat-viable on ammo alone**; power is a +25% rate *sweetener* and the unlock for electric ammo. Berries keep `cup_oil → generator → power-buff` as a **secondary, optional** investment, never load-bearing. (Decision #9.)

### Sustainability mechanics

- **Renewable extraction (Frostpunk model):** the **Auto-Miner** produces stone/ore forever at a fixed rate; you scale by building more, gated behind metal+wooden_rod so it can't be rushed day 1. **DELETE `REGROW_STONE`** (`Main.gd:207, 1085`) — the teleport-stone-into-base bug — but **sequence the deletion to land *with* the Auto-Miner**, never before, or stone becomes strictly finite with no renewable source in the gap.
- **The one finite gate is `IRON_VEIN`** (~4–6 on map) — the carrot that pushes you out past the base. **Make it non-soft-locking** (decision #8): a claimed vein + Auto-Miner is effectively infinite-but-rate-limited, with very slow off-screen vein renewal so a long run never hard-locks. Truly-finite veins would violate the locked "indefinite survival is possible" goal — don't ship that option.
- **Combat reclaim:** corpses add SCRAP (40%) → metal; spent ranged shots leave casings recovered by a **manual dawn field-sweep** (not auto-collected — passive collection undercuts the engineer fantasy and fights the persistent-world boundary). Gate casing recovery rate behind a hub upgrade rather than a flat 30%, and **exclude MG / hard-cap casing yield per night** so the highest-fire-rate turret stays the most ammo-hungry. Schedule this for Phase 3, after the persistent world lands.
- **Bees-as-input:** beeswax → SEALANT (support ammo + reinforced wall). This is the concrete bee sink that ends the orphaned-output problem.

### Re-arming UX

**Hybrid:** early nights = manual per-turret reload (click turret + matching ammo = the engineer-plugging-gaps fantasy + tension). An **auto-loader is a mid-game tech-hub unlock** that pulls from an adjacent depot, so deep nights don't become reload-spam at 5 turrets. This also gives the Tree's tech tree something meaningful to unlock. (Decision #7.)

---

## Combat, pathfinding & durability

There is **no pathfinder** today — every croc moves on the raw vector `to = _player_pos - m["pos"]` and chews any `BREAK_HP` tile it can't slide past. The only structure-targeting is the pink "wrecker" via `_nearest_structure_cell` (`Main.gd:1347`). The night **wipes the world to an open arena** (`_begin_night` NATURAL→GRASS at `Main.gd:921`) purely so the greedy AI doesn't jam — which is itself the degenerate kiting field. We replace all of this.

### Pathfinding: dual flow-field

Build **two integration (flow) fields**, not per-enemy A* — flow-field is the right tool when many enemies share few goals, and the 64×64 grid (4,096 cells) is cheap per pass:

- **`field_tree`** rooted at the Tree — recompute only on wall change (rare).
- **`field_player`** rooted at the player — recompute when the player crosses a cell boundary or every 0.2s.

**Cost grid:** walkable = 1; impassable natural/water = ∞; **`BREAK_HP` structures = finite cost ≈ break-HP**, not infinity. This is the They-Are-Billions trick: a 1-wide gap costs ~1, a stone wall costs ~48, so the horde *emergently routes to the thinnest gap and arcs around thick walls.* **Walls become funnels, not speed-bumps — and your wall placement becomes a real strategic verb.**

> **GDScript performance note:** don't trust "sub-millisecond" borrowed from native benchmarks. Use a **bucket/BFS field** where cost==1 cells (the vast majority) go in a simple queue and only break-cost cells go in higher buckets — keeps the per-frame `field_player` recompute genuinely cheap in interpreted GDScript.

**Delete the night-wipe** (`Main.gd:921-944`) and `REGROW_STONE` as part of this — the field routes through trees/stone as cover, dissolving the open-arena kiting field by construction. This is the persistent-world rider, and it's the keystone the next three subsystems ride on.

### Split-aggro rules (designed + telegraphed)

Add `"aggro"` to each `CROC_DEFS` entry. Each croc reads EITHER `field_tree` or `field_player`. Target mix per wave: ~40–50% tree/structure-seekers, ~30–40% player-seekers, ~20% swarm/support.

| Role | Aggro | Field | Telegraph |
|------|-------|-------|-----------|
| green grunt | swarm (samples both, picks cheaper goal) | tree or player | broad low body, green |
| yellow flanker | **player** + lead | player-field | small/spiky/fast — "darts at you" |
| pink ram | **structure/tree** (ignores detour cost) | tree-field | bulky armored snout |
| brown sapper | **tree** (tunnels, surfaces inside perimeter) | tree-field | digging dust |
| red/blue artillery | player, ranged, **leads shots** | player-field, kites | thin raised head |
| purple/white/black | swarm / support | nearest | per-role color |

**Two fields total** — structure-seekers reading `field_tree` naturally chew the walls between them and the Tree (that *is* the funnel). Keep pink's `_nearest_structure_cell` scan as a cheap special-case. The sapper "surface inside perimeter" needs an ignore-walls traversal flag (decision #15 — it's the one thing that complicates the clean two-field model).

> **Interim anti-kite with ZERO pathfinding dependency (resolves a cross-area contradiction):** the pacing milestone "solo-kiting non-viable by night 3–4" must not be hostage to the pather landing. Ship a fraction of crocs that **beeline the Tree's fixed cell on spawn** — the current straight-line AI already supports a fixed target. This delivers split-aggro and the anti-kite milestone *before* the flow-field; the flow-field later upgrades path *quality*, not the existence of the mechanic. Until that's live, **keep `MON_SPD_GROW` at 0.06** so act-1 nights don't get net-easier in the gap.

### Durability: unified descriptor + wreck model

Tile behavior is split across three disjoint dicts (`WALKABLE`, `MONSTER_WALK`, `BREAK_HP`) — a tile in none of them is a **silent invincible wall**. This is a real, confirmed bug: **`BULB` and `GLAPPLE_LAMP` are in neither `MONSTER_WALK` nor `BREAK_HP`**, so crocs can neither cross nor break them — free accidental walls.

Replace the three dicts with **one `TILE_DEF` descriptor** keyed by Terrain: `{player_walk, monster_walk, break_hp, armor, on_break}`. Fix the lamps by giving them `monster_walk=true`. Delete the dead `TRAP_MAX_HP["trap"]` entry (`Main.gd:327` — spike traps never enter `_traps`). **Make a missing entry a LOUD `--selftest` failure at startup**, and assert the inverse the BULB bug violated: *no tile is monster-blocking unless it has `break_hp` OR `impassable`.* That assertion is the permanent guard. (Do **not** market "fail-open" as the fix — a forgotten *wall* silently becoming walkable is a worse bug in a defense game than an invincible one; the selftest is the actual fix.)

**Wreck model (persistent damage, cheap rebuild):** today a structure at 0 HP **vanishes to GRASS and deletes its cost** (`_damage_structure` at `Main.gd:1394-1408`). Instead, route through `on_break` to a **WRECK tile** — passable rubble (`monster_walk=true`) that holds the footprint and rebuilds at a discount (Kingdom stump model). A breach you fail to repair becomes a live lane until you fix it. **No dawn auto-heal**; a single generic `_repair_structure(idx)` generalizes the existing `_turret_repair` (`Main.gd:1672`) to every structure, **allowed day AND night** (the engineer plugs gaps under fire — decision #12). Both monster→structure damage call sites (the probe at `Main.gd:1273` and the wrecker at `Main.gd:1335`) must route through the descriptor.

### Wall tiers (HP grows faster than cost; armor gates swarm-DPS)

| Tier | Cost | break_hp | armor | ~time-to-break (1 croc) |
|------|------|----------|-------|------------------------|
| 0 barricade (new) | wood 1 | 8 | 0 | ~5s |
| 1 wood wall | wood 3 (was 1) | 24 (was **5**) | 0 | ~14s |
| 2 stone wall | stone 4 (was 1) | 60 (was **8**) | 2 | ~36s |
| 3 reinforced (new) | stone 6 + metal 2 + **beeswax 1** | 140 | 4 | ~84s |

Current walls are absurdly weak (`wood_wall=5, stone_wall=8, door=3`) — they read as accidents, not choices. The reinforced tier's beeswax cost is the bees-as-defense-input lock. The **door stays a deliberate weak point** (break_hp ~12, armor 0) = a designed funnel gap. Note: armor must start at **0** on wood (with crocs doing ≥1 dmg and a min-1 floor, armor=1 is a no-op) — introduce armor at tier 2 where it bites. Route croc chew through a damage-amount arg (a signature change to `_damage_structure`, more invasive than a pure number bump — flag it).

### Turret-as-DPS rebalance — treat as playtest-tuned, not spec'd

The intent: by ~night 3–4 the horde outscales solo clear, so holding the turret line is mandatory. But the honest position is that **the specific crossover numbers are not yet knowable** — the player-DPS figures floating around are unverified, and the LOSE condition depends on horde *incoming-DPS-to-the-Tree*, not horde EHP. **Ship the pather + cost grid + split-aggro first; do balance as an empirical pass last** (Phase 7), modeling DPS-onto-the-Tree, and respecting the hard ceilings already in code (`MAX_TURRETS=5` at `Main.gd:378`, fuel/`POWER_DEMAND_NIGHT` gating). Lean on split-aggro as the primary anti-kite lever (you physically can't intercept Tree-seekers *and* kite), with a modest `MON_HP_GROW` bump as backstop — **don't nerf the player's fists** (the engineer fantasy should feel like "not enough hands," not "weak hands").

---

## Pacing & onboarding

**Top recommendation: a three-act spine** — generous build days, horde-free nights 1–2, then dusk-telegraphed sieges with size and composition on *separate* curves. Today `DAY_LENGTH=120s`, the buildable window is a cramped 72s, day 1 starts mid-morning at `_time=0.30`, night spawns the instant daylight hits 0 with **no dusk telegraph**, and `_monster_count_for_day()` already spawns 3 crocs on night 1 (`Main.gd:1008`) — there is no horde-free onboarding.

### Daylight retune (concrete)

- `DAY_LENGTH`: **120 → 150s** (the grind complaint is a window-size problem; 150 is the compromise over 180 — at 180s + 2 horde-free nights you wait ~9 min for the first real siege, which risks feeling slow. Decision #13).
- New `_daylight()` bands (`f` = cycle fraction):
  - `f < 0.07` → 0.0 (pre-dawn)
  - `0.07–0.12` → ramp up (dawn)
  - `0.12–0.68` → 1.0 (**full day, buildable**)
  - `0.68–0.78` → ramp down (**DUSK band — still buildable**)
  - `0.78–1.0` → 0.0 (**night/siege**)
- Buildable window (`daylight>0`) ≈ `f[0.07–0.78]` ≈ **~107s** (vs 72s today). Night ≈ ~33s.
- **Day-1 start `_time = 0.10`** (not 0.30) — first build stretch ≈ ~102s. Generous on purpose.
- Keep building allowed through the whole dusk band — last-second gap-plugging as the horde splashes in is the fun.

### Dusk countdown (the "night in N")

A `DuskPhase` owns `f[0.68–0.78]`:
- **HUD:** a radial clock ring (rendered via `_draw` against the *current* HUD — do **not** block this on the UX redesign) labeled "NIGHT IN 0:12", with `_canvas_mod` warming→cooling (reuse the existing lerp at `Main.gd:916`).
- **Audio:** `play_sfx("dusk")` on entering the band, `play_sfx("horde_incoming")` at T−10s (assumes the thin SFX hook lands).
- **Spawn preview:** at T−5s, splash `_poofs` (reuse `Main.gd:1066`) at the shore cells where crocs *will* emerge — telegraphs *where* the line gets tested. Crocs materialize at `f≥0.78`.
- Fire the dusk beat **every** night; the `POWER_DEMAND_NIGHT` message folds in as a sub-line.

### Horde-free onboarding + escalation

- `_monster_count_for_day()` returns **0 when `_night_index() ≤ 2`** — nights 1–2 go dark with no spawns (you learn the rhythm and that the Tree survives undefended). Day-2 dusk teaches the pivot: *"The crocs come tomorrow night. Build your first turrets around the Mother Tree."* First real siege = night 3 (decision #14).
- **Two-curve scaling.** SIZE (time-gated, predictable): nights 1–2 = 0, n3 = 4, n4 = 7, n5 = 11, n6 = 16 (the `POWER_DEMAND_NIGHT` wall, clearly past solo), n7+ = `min(36, 16 + (n−6)*6)` — raise `MONSTER_CAP` 28→36. Compute per-croc stat `lv` from `(night−3)` not `(night−1)` so the first siege is genuinely soft. COMPOSITION (the anti-kite lever): introduce the Tree-aggro fraction as the headline — n4=20%, n5=30%, n6+=40% — via the interim fixed-cell beeline so it ships in act 1. Gate the nastiest roles (healer/reviver) behind night AND a progress check (turret count / Tree tier ≥2), Dome-Keeper style, so escalation matches a prepared player and doesn't pile on a struggling one.
- **Yield retune** so the wider day isn't just more grind: base TREE/STONE yield 1→2 (bare-hands viable, tools become +1/+2 on top). Defer the auto-extraction trickle to the production-machine tier. Note the size-table change **breaks the self-test** asserting `_monsters.size()==MONSTER_BASE` and the debug-skip at `_nights_survived=POWER_DEMAND_NIGHT*2` — update the harness as part of this.

---

## UX architecture

You demanded this be concrete, so here is the full spec. **Top recommendation: a co-visible named-slot workspace on one `CanvasLayer`, executed enum-collapse-first, kept programmatic GDScript** (preserving the single-file identity; `.tscn`/`.tres` is a later refactor, not a prerequisite).

The problem today: one 280px right panel (`_right_vbox`) rebuilt from scratch on every refresh via a fixed if/elif chain over 7 mutually-exclusive flags (`_choosing_levelup`, `_craft_open`, `_inv_open`, `_open_turret`, `_open_util`, `_open_storage`, `_build_mode`). Exclusion is the elif *order*, not enforced at setters — so **opening a station while crafting silently no-ops** (the confirmed dead-click bug, because `_craft_open` short-circuits earlier in the chain). Everything is text Labels, items are text-only (`ITEM_LABELS`), there are **no item icons**, no Theme, and stations open as **separate modals** that replace the whole panel — the exact "bounce between crafting and kiln" complaint.

### Screen layout — DAY / build-off

```
+----------------+----------------------------------------+------------------+
| LEFT HUD       |              BOARD (camera)            | RIGHT WORKSPACE  |
| (persistent)   |                                        | (persistent day) |
| Day 3  14:20   |                                        | [INVENTORY]      |
| NIGHT IN 0:48  |        gorilla, trees, base...         | +--+--+--+--+--+  |
| ---            |                                        | |Wd|St|Th|..|..|  |  icon grid, 5-wide
| HP 80/120  === |                                        | +--+--+--+--+--+  |  corner qty badge
| energy ======= |     (hover a tile -> tooltip)          | |..|..|..|     |  |  category-tint border
| hydration ==== |                                        | +--+--+--+--+--+  |
| ---            |                                        | ---              |
| Lvl 4  XP ==== |                                        | [CRAFT]   filter |
| Atk 6  Arm 12% |                                        | Rope    2Th  >   |  recipe rows, icon+cost
| ---            |                                        | Nails   1St  >   |  greyed if unaffordable
| [Save][Settings]|                                       | ---              |
| [Menu]         |                                        | v NEAR: KILN     |  station card DOCKS here
+----------------+----------------------------------------+ Fuel 60%  Q:2    |  (only when adjacent)
                                                          | Smelt ore   >    |  its recipes append to
                                                          | Char wood   >    |  the SAME craft list
                                                          +------------------+
```

### Screen layout — BUILD MODE (press B)

```
right workspace dims to INVENTORY-only; a BUILD BAR appears bottom-center:
+----------------------------------------------------------------------------+
| BUILD   Blocks 12/80      [Wall][Door][Turret][Barrel][Kiln][Bee] ... (1-9) |
|  selected: TURRET   cost 3 Wood 3 Stone   *needs workbench within 2*        |
+----------------------------------------------------------------------------+
Ghost preview follows cursor on the board (green=ok, red=blocked/unaffordable);
left-click/drag places a line; right-click or DESTROY toggle removes.
```

(`BLOCK_LIMIT=80`, `Main.gd:513`, is the live tally to surface.)

### Screen layout — NIGHT

Right workspace collapses to INVENTORY-only (no craft, no build). **Station cards still dock** (refuel turret, load peel launcher, repair) — re-arm and repair are the siege job. Build bar hidden.

### State model (kills the dead-click bug by construction)

- `enum Overlay { NONE, LEVELUP, SETTINGS, TECH }` as `_active_overlay` — the **only** full-screen exclusive states (they pause/dim the board). TECH is the Mother-Tree hub.
- **Delete `_inv_open` and `_craft_open` entirely** — inventory and craft are *always visible* during day. The bug class dissolves because no two panels share an arbitrated rectangle anymore. **This deletion is the fix**, not merely collapsing flags to an enum.
- `_docked_station: int` (cell idx, −1 = none) replaces `_open_util`/`_open_turret`/`_open_storage` — one int, one source of truth. **Click-to-dock** (set it in `_click_interact`, which already gates on chebyshev≤1), not proximity auto-dock — once the recipe-merge means a station no longer *destroys* the craft panel, the "bounce" is already gone, so auto-dock buys nothing and risks siege-time flicker among adjacent stations. Highlight adjacent interactables so the player knows what's clickable.
- **Delete `_refresh_context_panel`** (called from ~68 sites, each a blind free-and-rebuild that destroys scroll/focus). Each retained panel gets a `refresh()` that updates children in place, coalesced once per frame via dirty flags: inventory-change → inv+craft dirty (affordability depends on inventory); resource-change → craft dirty; station tick → station-card dirty.

### The craft/station merge rule (kills the bounce at the architecture level)

Base craft recipes always listed. When `_docked_station ≥ 0`, that station's recipes **append to the same craft list** tagged with the station's icon, and its actions (Stoke/Smelt/Refuel/Load) render as a compact card below. Walking away removes the appended block; inventory + base craft stay put. **No panel is ever destroyed to show a station** (the Terraria model).

### Icon bake + Theme

Extend `_bake_sprites` (`Main.gd:5433`) with a `_item_icons` dict — one icon per `INV_ORDER` id, reusing `_rect`/`_disc`/`_speckle`. **Bake items at 24–32px source** (not terrain's 16px) — at 16px, 49 items with family-shared silhouettes are mutually indistinguishable, which would defeat the whole legibility goal; the slot renders them at ~44px. Build one programmatic `Theme` applied to the CanvasLayer root (16/22/12 font sizes, accent/slate/border colors, slot/card StyleBoxes) replacing scattered `add_theme_*_override` calls. Add one root `_tooltip` frame driven by a new `desc` field on the defs + a `_stat_line(id)` that *computes* effective stats so it never drifts. Add HP bars to crocs, the Tree, and Dens (today only turrets draw one; `draw_string` is used 0 times — the legibility layer is net-new shared work).

### Interaction inventory (every key/click → effect)

| Input | Context | Effect |
|-------|---------|--------|
| WASD | always | move |
| Left-click (board, day) | adjacent tile | gather; OR click a station → dock its card |
| Left-click / drag (build mode) | board | place structure (line on drag) |
| Right-click (build mode) | board | destroy / toggle DESTROY |
| Left-click (board, night) | — | punch / fire toward cursor (unchanged) |
| **B** | day only | toggle build mode → build bar + ghost |
| **1–9** | build mode | select structure by number |
| **C** | — | (toggle deleted) focus craft filter box |
| **I** | — | (toggle deleted) inventory always visible; optional bulk-management overlay |
| **E** / **Q** | — | eat / drink |
| Hover | slot / recipe / build-icon / world-tile | tooltip: name + desc + computed stats + cost |
| Click slot buttons | inventory | Equip / Drink / Drop inline |
| Click station buttons | docked | Stoke / Smelt / Refuel / Load inline |
| **Esc** | — | SETTINGS overlay (`_active_overlay=SETTINGS`) |
| Level-up | — | `_active_overlay=LEVELUP`, 1–5 or click picks stat (board paused) |
| Interact at Tree | — | `_active_overlay=TECH` full-screen hub |

Inventory model: **hybrid** — a small fixed icon row for equipped tool/weapon/ammo (hotbar feel) plus a compact scroll list for bulk materials. A full fixed grid would invent a carry-cap mechanic that isn't in the design (decision #17).

---

## Decisions — LOCKED (2026-06-21)

Will signed off on **every** recommendation below — these are now decisions, not open forks. Two were revised in discussion (#2, #3) and a nineteenth was added (#19), noted inline. The recommendation shown is the locked choice.

1. **WIN shape** — bounded "clear all Dens" / endless score-run / roguelike-with-meta. → **Bounded Den-clear.** Gives the advance-pressure you flagged, fits the persistent-base identity, no meta-save layer. Endless mode comes free later.
2. **How Dens die + turret-vs-melee clear ratio** → **LOCKED: forward powered outposts are the safe/efficient path; solo clears are *possible but dangerous*.** A *young* Den is soloable by a risky dash; a *mature* Den (see Den-maturity in the Mother Tree section) needs an outpost — that gradient teaches the strategy. Turret-reachable stays mandatory architecture; solo remains viable-but-punishing.
3. **Ammo granularity** → **REVISED & LOCKED: a single munition (gunpowder); counter-play lives in turret *types*, not ammo families.** Different turrets counter different crocs (placed once) instead of manufacturing/juggling three ammo types. Same "no single best turret" depth, far less UX load. The three-family graph is kept as *optional later depth only*.
4. **`IRON_VEIN` hardness** — truly finite (can soft-lock) / slow off-screen renewal / **infinite-but-rate-limited via auto-miner**. → **Rate-limited hybrid.** Truly-finite violates "indefinite survival is possible"; don't ship it.
5. **Generator coupling** — wireless aura / wires-only / **hybrid (aura core + wires to extend)**. → **Hybrid.** Keeps the wire tech meaningful late.
6. **Soft-fail granularity** — **tier-downgrade on HP loss** / binary alive-dead. → **Tier-downgrade.** Delivers "setback not game-over" at the structure level for almost no extra code.
7. **Re-arming UX** — manual reload / auto-pull depot / **hybrid (manual early, auto-loader tech later)**. → **Hybrid.** Engineer fantasy early, no reload-spam late, gives the tech hub something to unlock.
8. **Downed-player cost** — flat Sap / **escalating within a night** / time-only. → **Flat Sap, escalating only within one night.** HP matters as a setback without a death-loop.
9. **Berry chain** — keep `oil→generator→power-buff` as secondary / fully demote to drinks. → **Keep as secondary.** Preserves the still/barrel systems; never load-bearing.
10. **Wall tier count + beeswax** — **4 tiers (barricade/wood/stone/reinforced)**, reinforced consumes beeswax. → **Yes to both.** Barricade is the cheap emergency-patch; beeswax is the concrete bee sink.
11. **Wreck breach passability** — **monster-walkable breach** / impassable rubble. → **Walkable breach.** Makes repair-as-siege-job matter. (Inert until the pather lands — fine.)
12. **Repair at night for ALL structures incl. turrets** / turrets day-only. → **Day+night for all.** This removes the only current day/night asymmetry — a deliberate feel change, hence your sign-off.
13. **Cycle length** — **150s** / 180s / keep 120 widened. → **150s.** 180 + 2 horde-free nights = ~9 min to first siege, likely too slow.
14. **First siege night 3 (2 horde-free)** / night 2 (1 horde-free). → **Night 3.** The identity is engineer-first; give two full build days.
15. **Sapper** — keep tunnel-under-walls (surface inside, anti-turtle) / remove. → **Keep, surface inside, telegraphed.** It's the one anti-turtle counter — but it needs an ignore-walls traversal flag that complicates the clean two-field model, so it's a real cost.
16. **Machine-break loot** — **spill ~50% banked contents as reclaimable** / lose it. → **Spill.** Reinforces the combat-reclaim pillar, softens losing a full barrel.
17. **Inventory model** — fixed grid / compact list / **hybrid hotbar+list**. → **Hybrid.** A full grid invents a carry-cap that isn't in the design.
18. **Mother-Tree tech UI** — **dedicated full-screen TECH overlay** / docked station card. → **Full-screen overlay.** A branching graph wants space and pause; a 340px card fights "see the whole tree."
19. **Map size** (new — from your Den-runway question) → **LOCKED: grow 50×50 → 64×64.** Gives the Den frontier real runway (three zones, outpost room, multi-night creep) and makes solo sorties naturally riskier. Free to change now (`const` grid dims; arrays + BFS scale fine), but it makes the renderer camera-cull **non-optional**.

---

## Implementation readiness & sequencing

**Are we ready?** Yes. All 19 decisions are locked (above), and the two former gates — the SAP definition and the economy mass-balance — are **closed with first-pass numbers in `IMPLEMENTATION_PLAN.md`** (Sap = a Tree-internal counter with a fixed per-material deposit table; the mass-balance is a starting envelope, not a solved spreadsheet — both get tuned empirically in Phase 7, not perfected now). The build is a **single stream for one technical implementer**, who works from `IMPLEMENTATION_PLAN.md` and treats this document as the rationale record. The earlier two-workstream split is superseded: its model/view interface contract and merge dance weren't worth it on a single-file God-object. **Deep design surfaces** (icon/silhouette artistry, the Theme palette, juice, the TECH-overlay look, fine balance) are deliberately left as **structural stubs + named hooks** for a later taste pass against the running game — so the implementer never has to make a feel call.

Two more shared gaps to own explicitly during build: the **multi-cell Tree primitive** (a 3×3 object is new in a strictly single-cell PackedArray codebase — how it keys `_struct_hp`, how the flow-field picks goal cells for a 9-cell object) and **telegraph-by-silhouette** (`CROC_DEFS` encodes role as *color* only today; distinct per-role shapes are net-new bake work — commit to it or fall back to color+icon tags).

### Technical prerequisites — what gates what

- **SAVE — no rewrite needed.** Re-scope this *down* from how it's often framed. The schema is version-stamped (`"v": 1` at `Main.gd:4500`) and `_deserialize_state` reads every field via `d.get(key, default)` (`Main.gd:4548+`), so additive fields (`sap`, `tree_tier`, `dens`, ammo bins, unlock flags) **load on old saves for free with zero migration code.** Add a `"v"` branch only if `INV_ORDER`/`_resources` shift destructively. Do not gate Tree work behind a save rewrite.
- **`AStarGrid2D` / flow-field pather + persistent world is the true keystone.** At least four systems (Tree split-aggro, Dens-as-spawn-source, walls-as-funnels, wreck-as-breach, tree-aggro composition) are **inert without it.** It must be sequenced before any aggro/funnel/Den work despite each area tagging itself independently shippable.
- **The `TILE_DEF` descriptor lands *before* the pather** — it's the edge-cost source the cost grid reads.
- **GameDb / `.tres` migration is NOT a prerequisite.** Keep const dicts + programmatic single-file GDScript now; the `desc` field and icon bake are the pre-migration bridge. `.tres` is a later refactor.
- **`TileMapLayer` is optional** — the PackedArray terrain model works; only adopt it if the 3×3 Tree footprint proves painful in single-cell arrays.
- **Map is now 64×64 (decision #19)** — a `const` change, but it makes the renderer **camera-cull non-optional** (immediate-mode `_draw` over 4,096 cells). Fold the cull into Phase 2/6 rather than treating it as optional polish; flow-field BFS and PackedArray saves scale fine at this size.
- **The self-test / debug harness must be updated alongside nearly every phase** (the size-table change alone breaks two existing asserts).

### Phased order

- **Phase 0 — foundations, parallel, no pather:** UX enum-collapse (delete the 7 flags / `_craft_open` / `_inv_open`, retained `refresh()`) → fixes the dead-click bug by construction; confirm additive save fields; **define SAP + its conversion recipe**; update the test harness. Daylight retune + dusk telegraph can also start here (rendered against the current HUD).
- **Phase 1 — durability descriptor + bug fixes:** unify into `TILE_DEF`; fix BULB/GLAPPLE_LAMP; delete dead `TRAP_MAX_HP["trap"]`; add WRECK terrain + 4-tier walls + generic `_repair_structure`; route both monster-damage sites through the descriptor; loud selftest on missing entries.
- **Phase 2 — THE KEYSTONE:** flow-field pather + persistent world. Cost grid (reads Phase-1 break_hp/armor), dual integration fields (bucket-BFS fast path), separation nudge, **delete the night-wipe + `REGROW_STONE`.** Ship `field_tree` first, `field_player` second.
- **Phase 3 — Mother Tree core loop:** plant the 3×3 Tree as power-root (`_in_tree_aura` OR'd into the powered check, NOT a `_compute_power` fold-in); HP + tier machinery + soft-fail downgrade; Sap deposit → growth; downed-player respawn; lose decoupled from player death; hub TECH overlay. The interim fixed-cell-beeline anti-kite ships here to de-risk pacing.
- **Phase 4 — split-aggro + Dens + composition:** role aggro fields; Dens replace `_pool_shore` seeding; Den creep + retaliation surge; tree-aggro fraction.
- **Phase 5 — production pivot (staged):** single-munition swap (gunpowder, **no sealant**) + Auto-Miner + scrap reclaim (sequence `REGROW_STONE` deletion *with* the miner) → casing dawn-sweep + power-as-buff. **Counter-play ships as turret *types*, not ammo families** (decision #3); the three-family ammo split + bins is deferred to an *optional* later layer only if turret-type counters need more depth. Ammo throughput co-tuned with turret DPS as one pass.
- **Phase 6 — UX visual layer:** icon bake (24–32px items), `_slot`/`_item_row` widgets, single Theme, co-visible right column + recipe-merge docking, build-bar mode + ghost, root tooltip + `desc`/`_stat_line`, enemy/Tree/Den HP bars.
- **Phase 7 — empirical balance (LAST):** all turret-DPS crossover, `MON_HP_GROW`, Sap mass-balance, Den counts, cycle length — tuned by playtest against a working pather + economy, not spec'd ahead of them.
