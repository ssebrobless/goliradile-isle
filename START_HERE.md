# Goliradile Isle — Implementer Kickoff

**You are the sole technical implementer** for Goliradile Isle, a single-file Godot 4.6 GDScript game (`Main.gd`, ~7,400 lines: a `Node2D` God-object with procedurally-baked sprites, immediate-mode `_draw`, and parallel `PackedArray` world state). You are a strong, robust coder. **You will not be asked to make any game-feel, art, or balance ("taste") decision** — every such call is either already decided in the docs or deliberately left as a *stub* for a later pass. Your job: implement the decided systems correctly, in the grain of the existing file, and leave clean hooks exactly where the plan tells you to.

## Read these first, in order (do not skip)
1. **`IMPLEMENTATION_PLAN.md`** — your primary spec and the thing you execute. It defines the two work modes, the closed-gap first-pass values, the build order (Phases 0–7), the stub contracts, and the global invariants.
2. **`DESIGN_DECISIONS.md`** — the full decided design with rationale and `Main.gd` line refs (the "why" behind every call in the plan). Read end-to-end before writing code.
3. **`Main.gd`** — the codebase you're modifying. Learn the existing patterns (procedural `_bake_sprites`, immediate-mode `_draw` + the `queue_redraw` gate, parallel PackedArrays, the `--selftest` harness) before changing them.
4. **`DESIGN_REVIEW.md`** — archive/background: the original problem analysis that motivated the direction. Skim for context; where it conflicts with the two docs above, they win.

## The one principle that governs the whole build
From the plan — internalize this, because it survives even if you skim everything else:
- **Mode A — implement fully:** the design is decided and the values are chosen → build it completely and robustly.
- **Mode B — build the hook, then STOP.** For the deep-design surfaces the plan marks (icon/silhouette artistry, the Theme palette, juice/animation, the TECH-overlay look, the dusk-telegraph look, fine balance, audio, flavor/`desc` copy), you build **only** the functional skeleton the plan specifies — the named hook, the working-but-ugly layout, the crude-but-distinguishable placeholder — and then you stop. **You do not implement the design content itself.** A separate design pass fills it in later; that pass is explicitly **not yours**, and you are not handing off to it — you are leaving it room.

### ⚠️ The bright line: functional, not finished
The target for every Mode-B surface is **functional-but-ugly, on purpose.** Pretty / polished / tuned / juicy is *out of scope* and is actively the wrong thing to deliver — the design pass will redo it, so doing it now is wasted effort that creates churn. Concretely, do **not**:
- choreograph any Tween / particle / animation feel — wire the empty `_fx_*` hook and leave the body;
- pick a color palette, font identity, or styling — build the one `Theme` object with placeholder values, don't design it;
- craft real icon / silhouette art — crude, distinguishable shapes only;
- tune balance past the first-pass numbers — wire them as consts, don't "improve" them;
- write flavor / `desc` copy — functional placeholder strings only;
- map any audio — `play_sfx` stays a no-op.

**Tripwire — your self-check:** the moment you're choosing between two options because one "looks better," "feels better," or "reads nicer," you've crossed into the design pass. Stop, leave the hook, move on. When the docs don't pin something down, do **not** invent a feel / balance / art decision — use the first-pass value if one exists, else leave the hook. If a genuine *systems* blocker appears (a decided thing can't be built as specified), **stop and flag it** — don't hack around it.

## How to work
- **Single stream, single branch.** Everything stays in `Main.gd` + procedural bake. No `.tres`/GameDb/TileMapLayer unless the plan explicitly calls for it.
- **Follow the build order Phase 0 → 7 in sequence.** Phase 2 (the flow-field pathfinder + persistent world) is the keystone — several later phases are inert without it.
- **Meet each phase's acceptance bar before moving on, and keep `--selftest` green at every step.** A red harness is a blocker, not a warning — update the asserts the new tables break, and add the new invariants the plan names.
- **Respect the global invariants** in the plan: never reorder/insert into the `Terrain` enum (append only — saves store raw enum ints); keep saves additive (`d.get(key, default)`); keep animated entities inside the redraw gate; collect every first-pass tunable into one clearly-delimited const block.
- **Work one phase at a time.** At each phase boundary, summarize what changed and report the selftest result before continuing.

## Definition of done
All 8 phases complete; the game is playable end-to-end on the first-pass numbers; `--selftest` is green; every Mode-B hook is named and placed for the later taste pass; and all tunables live in one delimited block so the deep-balance/juice/art pass is a single-location fill-in.
