# Goliradile Isle — Boss design sheets

Status: **draft for owner review.** Every number is a starting proposal, to be tuned with the
`--bossfight` simulation and playtests. Rules are in `DESIGN.md` ("Boss fights"); order,
tiers and rewards are in `PROGRESSION.md`; gear and abilities are in `PLAYER.md`; towers are in
`TOWERS.md`; the framework tasks are in `ROADMAP.md` Phase 2.

## Shared rules (apply to every boss)

### Anatomy of a boss night
1. **Summon at dusk** at the altar (previous boss's drop + the tier component).
2. **Approach (about 60–90 seconds).** The boss marches in from the **front** that matches its
   biome (below) while minions arrive first. The fight proper starts when it is within about
   25 tiles of the altar or base.
3. **Phases** change at health thresholds, with a visible and audible **phase transition**
   (a short roar, a screen pulse, a brief boss invulnerability of about 2 seconds while minions
   are summoned).
4. **Escalation clock:** after the approach, every minute adds pressure: minion spawn interval
   shrinks (about −4% per minute), boss damage rises (about +3% per minute), hazard frequency
   rises. At **12 minutes** the boss enters a **frenzy**.
5. **Hard cap: 15 minutes.** If it runs out (or all lives are gone) the boss **retreats, heals
   and returns stronger** the next time it is summoned.
6. **Targets by phase:** early phases pressure structures and towers; later phases hunt the
   player (and the boss swaps to whoever is hurting it most).
7. **Rematches:** reduced drops, one-day cooldown.

### Size and movement
Bosses are large (3×3 tiles or more), ignore tile pathfinding and **smash** structures in
their way: a wall slows them by taking damage, not by blocking. The camera may zoom out
during the fight.

### Telegraphs
Every dangerous attack has a **ground telegraph** (a marked shape) before it lands.

| Shape | Use | Colour cue |
|---|---|---|
| Circle | slams, eruptions, clouds | red outline fills over the telegraph time |
| Line / lane | charges, beams, dashes | red stripe |
| Cone | breath, spit, sweeps | red wedge |
| Ring | shockwaves, freezing waves | expanding red ring |
| Zone | lingering hazards | hatched area |

Telegraph duration by difficulty: **Easy 1.5 s, Normal 1.0 s, Hard 0.6 s** (a multiplier on
each attack's base time). Telegraphs are always **shape- and icon-coded as well as
colour-coded** (accessibility).

### Targets for tuning
- **Kill time** on a tier-appropriate loadout with expected towers and meals: **Easy 6–9 min,
  Normal 8–11 min, Hard 10–14 min** (inside the 15-minute cap).
- The player supplies about a third of the damage, towers the rest.
- Boss health also scales with player count (+35% per extra player; see S6).
- Minions on screen: **up to 60 or more** (performance target in ROADMAP 2.7).

### Terrain events
Each boss's map effects use the **terrain-event system** (apply, save, revert). They revert
when the fight ends or at dawn. Destroyed structures leave **ruins** that rebuild at roughly
half cost.

### Common data per boss (`boss_defs.gd`)
`id`, `name`, `croc_type`, `size`, `front`, `base_hp_scale`, `phases[]` (threshold, attacks,
minions, events), `attacks{}` (shape, telegraph, damage, targets), `escalation{}`, `drops[]`,
`music`, `summon_item`.

## Overview

| # | Boss | Type | Tier | Front (biome) | Phases | Signature |
|---|---|---|---|---|---|---|
| 1 | Grand Brute | Green | 1 | pool / water | 3 | charges and slams that crack walls |
| 2 | Dash Monarch | Yellow | 2 | nearest edge | 3 | afterimage dashes that trample traps |
| 3 | Cinder Matriarch | Red | 3 | volcano | 4 | fire that spreads across the base |
| 4 | Frost Warden | Blue | 4 | frozen cove | 4 | freezes structures and the pool |
| 5 | Demolisher | Pink | 5 | rocky highlands | 3 | wrecks buildings, hurls rubble |
| 6 | Burrow King | Brown | 6 | deep highlands | 4 | tunnels, erupts under the base |
| 7 | Bog Mother | Purple | 7 | swamp | 3 | poison clouds and a spreading bog |
| 8 | Matron | White | 8 | jungle (with entourage) | 4 | shields and heals; must be interrupted |
| 9 | Shade | Black | 9 | the darkest edge | 5 | darkness, revives, a "false death" |
| 10 | The Great Goliradile | all | 10 | all fronts in turn | 6 | everything, then the island itself |

---

## 1. Grand Brute (Green, tier 1)

*Teaches the loop: telegraph, dodge, defend.* The simplest boss; no map hazards beyond cracked
walls.

- **Approach:** from the pool shore; a few green crocs lead.
- **Phases (3):** 100% / 60% / 25%.
- **Attacks:**
  - **Charge:** a lane telegraph (1.5 s), then a straight rush that **smashes structures** in
    its path. Slow to turn, so strafing works.
  - **Slam:** a circle (radius 2.5 tiles); on impact **cracks walls** in the area (they lose
    half their health, not destroyed).
  - **Roar:** summons a wave of green crocs.
- **Phase 2:** two charges in a row; slam sends a **shockwave ring**.
- **Phase 3 (berserk):** faster, slam leads into a charge; minions arrive in tighter waves.
- **Minions:** green only (tier 1).
- **Terrain event:** *Crack*, reduces structure health in an area; no persistent change.
- **Good answers:** Adhesive, Boxer Bulwark, thick walls; **weak:** thin wood walls alone.
- **Drops:** Green Scale (set materials), bones and hides.
- **Music:** heavy percussion, one melodic motif that later bosses reuse.

## 2. Dash Monarch (Yellow, tier 2)

*Teaches reading telegraphs under pressure.* Fast and low-health; hard to hit, easy to kill if
caught.

- **Approach:** from the nearest map edge, with a dust cloud as warning.
- **Phases (3):** 100% / 65% / 30%.
- **Attacks:**
  - **Afterimage dash:** leaves **three decoys**; a lane telegraph shows the real one (0.8 s).
  - **Skid:** a cone through the base that **trampling disables traps** for 10 s in its path.
  - **Whirl:** a spin circle (radius 2 tiles).
- **Phase 2:** more decoys; dashes in short chains.
- **Phase 3:** permanent speed-up; skid leaves a **slow trail** across the ground.
- **Minions:** swarms of yellow crocs (fast, fragile), green.
- **Terrain event:** *Trample*, disables traps along a path.
- **Good answers:** Adhesive, Machine Gun, Trickster Prank; **weak:** slow single-shot towers.
- **Drops:** Yellow Scale.

## 3. Cinder Matriarch (Red, tier 3)

*Teaches that the base itself is a battlefield.* Fire spreads across wood, trees and berries.

- **Approach:** from the volcano side; red crocs (shooters) escort it.
- **Phases (4):** 100% / 70% / 40% / 15%.
- **Attacks:**
  - **Fireball volley:** three projectile lanes (telegraphed).
  - **Fire rain:** random circles across the base area, each telegraphed (1 s).
  - **Ignite:** touches set **burning** on wood walls, trees and berry bushes.
- **Terrain event:** *Burn*, fire spreads tile by tile (about every 2 s, a chance to jump to
  flammable neighbours), damages the structure on the tile, and **burns out** after about 12 s.
  Water tiles, **sprinklers**, stone and **Repair towers** stop or heal it.
- **Phase 3:** **Wildfire**, spread chance doubled.
- **Phase 4 (Meltdown):** a ring of fire closes in toward the altar over 60 s.
- **Minions:** red crocs and green.
- **Good answers:** stone walls, Repair, Engineer, sprinklers; **weak:** wooden bases.
- **Drops:** Red Scale, Cinder Core.

## 4. Frost Warden (Blue, tier 4)

*Teaches control and denial.* Freezing hampers building and movement.

- **Approach:** from the frozen cove; blue crocs.
- **Phases (4):** 100% / 70% / 40% / 15%.
- **Attacks:**
  - **Snowball barrage:** slows (stacking toward a freeze).
  - **Freeze wave:** an expanding ring that **locks structures** (cannot be operated; towers are
    disabled for 5 s).
  - **Ice-over:** the **pool and other water tiles freeze**, becoming walkable ice (crocs cross
    water; slippery ground).
- **Phase 2 (Blizzard):** vision reduced and a slow field over the base.
- **Phase 3:** ice shards (lanes) and larger freeze waves.
- **Phase 4 (Cryo-prison):** a cluster of towers is encased until the boss is hit hard enough
  or the **Terrain tower's fire** thaws it.
- **Terrain events:** *Freeze* (structures), *Ice-over* (water).
- **Minions:** blue crocs, green, red.
- **Good answers:** Terrain Embers, Repair, Engineer; **weak:** structures that lock up.
- **Drops:** Blue Scale, Frost Core.

## 5. Demolisher (Pink, tier 5)

*Teaches protecting the base itself.* Targets the nearest structure first.

- **Approach:** from the rocky highlands; pink crocs (wreckers) escort it.
- **Phases (3):** 100% / 60% / 25%.
- **Attacks:**
  - **Wrecking charge** toward the nearest structure; big damage to it.
  - **Rubble toss:** an arc that lands as **rubble** (obstacle tiles that block paths and hurt).
  - **Chew:** triple structure damage in melee.
- **Phase 2:** targets **towers** first.
- **Phase 3 (Collapse):** drops a **line of walls** at once with a short telegraph.
- **Terrain event:** *Rubble*, blocking tiles the player can smash; no permanent change.
- **Minions:** pink crocs plus the earlier types (green, yellow, red, blue).
- **Good answers:** Repair Reinforce, Terrain Barricade, Sniper at range; **weak:** close-range
  towers.
- **Drops:** Pink Scale, Quarry Core.

## 6. Burrow King (Brown, tier 6)

*Teaches ground control.* The boss is mostly underground; you fight what it brings up.

- **Approach:** underground from the deep highlands; a moving mound and ground tremors warn.
- **Phases (4):** 100% / 70% / 40% / 15%.
- **Attacks:**
  - **Burrow:** invulnerable and fast, travelling under the base; the telegraph is a moving
    mound with tremor rings.
  - **Eruption:** surfaces with an area hit (circle, 3 tiles) that **knocks structures** and
    briefly stuns the player.
  - **Undermine:** structures on a tile line **sink into ruins**.
- **Phase 2:** two mounds (one is a decoy).
- **Phase 3:** **quake zones** (hatched areas) crack tiles for a few seconds.
- **Phase 4 (Cave-in):** a large collapse area with a long telegraph.
- **Terrain events:** *Quake* (cracks, temporary pits), *Undermine* (sink to ruins).
- **Minions:** brown crocs (diggers), pink, green.
- **Good answers:** Drill, Terrain tower, Slicer; **weak:** ranged-only defence.
- **Drops:** Brown Scale, Deep Ore.

## 7. Bog Mother (Purple, tier 7)

*Teaches attrition management.* Poison and rot wear things down; cleanse and heal.

- **Approach:** from the swamp; purple crocs.
- **Phases (3):** 100% / 55% / 20%.
- **Attacks:**
  - **Spore cloud:** a zone that lingers (about 10 s) and **expands**.
  - **Toxic spit:** a cone of poison (damage over time).
  - **Corrupt:** the ground becomes **bog**.
- **Terrain event:** *Bog*, grass becomes bog: movement slowed, **planters die**, wood walls rot
  slowly, and **purple crocs regenerate** while standing in it.
- **Phase 2:** clouds **follow the player**.
- **Phase 3 (Blight):** the bog spreads widely and poisons structures.
- **Minions:** purple crocs, red, blue, green.
- **Good answers:** Engineer, Repair, long-range Sniper; **weak:** crowded melee.
- **Drops:** Purple Scale, Bog Resin.

## 8. Matron (White, tier 8)

*Teaches burst and interruption.* The boss doesn't kill you; it refuses to die.

- **Approach:** from the jungle, with a large entourage including white crocs.
- **Phases (4):** 100% / 70% / 40% / 15%.
- **Attacks:**
  - **Barrier:** shield bubbles over the boss and clusters of minions; the shield must be
    broken before damage lands.
  - **Mass heal pulse:** heals the boss about 5% per pulse unless it is **interrupted** by a
    burst within 3 s.
  - **Cleanse:** removes marks, slow fields and debuffs from the boss and minions.
  - **Summon medics:** more white crocs.
- **Phase 2:** shields on every minion cluster.
- **Phase 3:** heal pulses escalate (quicker, bigger).
- **Phase 4 (Sanctuary):** a healing ring at the boss's feet; it must be pulled out of it.
- **Terrain event:** *Sanctuary*, a healing zone that heals enemies, hurts nothing of yours.
- **Minions:** white crocs (healers), every earlier type.
- **Good answers:** Trickster Jinx, burst Sniper, Slicer; **weak:** slow damage over time.
- **Drops:** White Scale, Mending Gem.

## 9. Shade (Black, tier 9)

*Teaches the "lights on" and finishing moves.* Darkness, revival and a fake-out.

- **Approach:** from the darkest edge of the map; the sky darkens as it nears.
- **Phases (5):** 100% / 75% / 50% / 25% (after the false death) / 10%.
- **Attacks:**
  - **Darkness:** the map goes dark; your vision radius shrinks (lamps and bulbs push it back).
  - **Shadow clones:** several fake Shades; telegraphs tell the real one.
  - **Soul drain:** drains tower fuel or the player's health with a lane telegraph.
  - **Revive:** fallen minions rise again once.
- **False death:** at 0% health the Shade **revives at 50%** once ("the second form").
- **Terrain event:** *Darken*, reduces light; **electric bulbs and lamps** counter it.
- **Minions:** black crocs (revivers), every earlier type.
- **Good answers:** Sniper execute, Trickster Hex, area damage on revival, **light towers**;
  **weak:** single-target chip damage.
- **Drops:** Black Scale, Shade Core.

## 10. The Great Goliradile (Final, tier 10)

*The finale.* Six phases, each themed on one croc type's power, ending in a combined climax.
The fight is the **longest** in the game and uses the full 15-minute cap.

- **Approach:** the boss marches in from the first front; as phases change it **relocates** to
  the next front, so the player must defend all sides over the night.
- **Phases (6):** 100% / 84% / 66% / 48% / 30% / 12%.
  1. **Brute (green):** charges and slams that crack walls (as boss 1, faster).
  2. **Cinder (red):** fire rain, wildfire spreading over the base.
  3. **Frost (blue):** the **pool freezes**, freeze waves lock towers.
  4. **Wrecker and Burrower (pink, brown):** rubble tosses and quakes; the base crumbles.
  5. **Bog and Matron (purple, white):** poison, shields and healing; must be interrupted.
  6. **Eclipse (black):** darkness, shadow clones, a **false death** at the end, then a combined
     finale where earlier hazards return in short bursts.
- **World-scale hazards** (terrain events, reverted at the end):
  - **Flood:** water spreads tile by tile along the fronts, slowing everything and
    **disabling submerged towers** until it recedes.
  - **Quake:** periodic shakes that crack tiles.
  - **Firestorm / Blizzard / Eclipse:** repeating environmental waves, telegraphed by sky and
    sound cues.
- **Minions:** all nine families, up to 60 or more on screen.
- **Escalation:** the clock is strictest here; hazards come faster after minute 10 and the
  frenzy begins at 12.
- **Retreat:** if the cap runs out the boss returns with an extra phase of difficulty
  (one more hazard layer) next time.
- **Reward:** the win (credits, Hall of Fame entry); no gear set.
- **Counter notes:** a mix of everything; **no single tower or build** should beat it.

---

## Boss test scenarios (`--bossfight`)

The headless simulation runs a boss against a **loadout**: tower types and paths, supply, player
level, perks, gear, meals, difficulty, player count. Recorded bands per boss and difficulty:
- **Win rate** and **kill time** for the tier-appropriate loadout (target bands above).
- **Loss rate** for a loadout one tier below and for a single-tower-type loadout (must lose).
- **Structure and tower losses**, **player deaths**, **peak minion count and per-frame cost**.
- **Escalation check:** a stalling loadout reaches the 12-minute frenzy and the 15-minute
  retreat.
- **Phase-transition check:** every phase threshold is reached and fires its event once.
- **Terrain events:** apply, save and load mid-event, and revert (round-trip tests).

## Open details (not decisions)

- Exact attack numbers, damage and health: tuned by the simulation.
- Names of boss drops, summon components and the Pink/Brown/Black materials are placeholders.
- Art and animation: bosses are custom or edited sprites (ASSETS.md); placeholder boxes with
  telegraphs are enough for Phase 2.
- Boss music: open-licensed tracks per phase where available; otherwise per-boss ambience.
