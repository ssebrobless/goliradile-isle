# Goliradile Isle — Towers

Status: **draft for owner review.** Numbers are starting proposals; the paths below are
intent and names, to be balanced with `--defense` and `--bossfight`. Rules are in
`DESIGN.md` ("Towers"); unlock tiers and caps are in `PROGRESSION.md`.

## System summary

- **12 tower types:** the 9 that exist today plus Repair, Terrain and Collector.
- **3 upgrade paths per tower, 4 tiers per path, cross-path cap 4/2/0.** A tower may reach
  tier 4 on one path, tier 2 on a second, and nothing on the third.
- **No per-tower XP or levels.** Upgrades are bought with drops: **bones and hides for tiers 1
  and 2, boss materials for tiers 3 and 4.**
- **Gating:** tier *t* of a path becomes available at world tier *(unlock tier + t − 1)*, so a
  tower's top upgrades arrive three tiers after the tower. The first path to reach tier 3 or
  4 needs the boss materials of the matching tier.
- **Targeting modes** on every tower that fires: **First, Last, Strongest, Closest**, plus
  tower-specific modes below. Set per tower in the info panel.
- **Sell** returns about 60% of the base cost and about 40% of upgrade spending.
- **Supply:** one idea covers fuel and ammo. Each tower uses **wine**, **oil** or **ammo**,
  hand-fed early and delivered by feeders later (tier 7). A tower wired to a live generator
  runs on power and uses no supply.
- **Limits:** the tower cap grows with tier (3 at tier 1 up to 12 at tier 10); each extra tower
  of the same type costs more.
- **Player buffs:** perks, abilities and gear can buff towers within about 5 tiles of the
  player (see `PLAYER.md`).
- Towers have **health**, can be damaged by crocs and bosses, and can be **repaired**. A
  destroyed tower leaves **ruins** that can be rebuilt at about half cost.

## Existing stats (today's game, for reference)

| Tower | Category | Health | Range (tiles) | Cooldown (s) | Damage | Notes |
|---|---|---|---|---|---|---|
| Sniper | ranged | 12 | 9 | 2.2 | 14 | 25% crit |
| Machine Gun | ranged | 10 | 6 | 0.25 | 4 | spread |
| Rocket | ranged | 11 | 7 | 2.5 | 9 | area, slows |
| Boxer | physical | 18 | 1.4 | 0.35 | 6 | knockback |
| Drill | physical | 12 | 1.3 | 0.2 | 3 | roams, can dig |
| Slicer | physical | 14 | 1.9 | 1.2 | 9 | hits several |
| Engineer | support | 12 | 2.2 | — | — | roams, heals |
| Adhesive | support | 10 | 8 | 2.5 | — | slow field |
| Trickster | support | 10 | 6.5 | — | — | marks +20% damage |

## The roster

For each tower: role, unlock tier, supply, special targeting, and the three paths. Each path
is listed as **tier 1 / tier 2 / tier 3 / tier 4**.

### 1. Boxer (tier 1, wine)
Cheap, tough melee that punches anything adjacent; the early wall-line.
- **Targeting:** closest only.
- **Path A, Heavy Hands:** harder punches / knockback / stagger-stun on hit / shockwave.
- **Path B, Flurry:** faster hits / double-strike / adjacent targets / afterimage barrage.
- **Path C, Bulwark:** more health / armour / taunt (crocs prefer it) / reflects damage.

### 2. Machine Gun (tier 1, ammo)
Rapid, inaccurate fire; best at mid range and against swarms.
- **Path A, Tighter Spread:** accuracy / range / armour pierce / long-range burst.
- **Path B, Volume:** fire rate / extra barrel / suppression slow / overdrive bursts.
- **Path C, Special Rounds:** ricochet / incendiary / frost rounds / explosive rounds.

### 3. Sniper (tier 2, ammo)
Slow, high-damage shots with crits; the single-target answer and boss damage dealer.
- **Targeting:** adds **Marked first** (shots marked enemies first).
- **Path A, Marksman:** damage / crit chance / crit damage / execute low-health targets.
- **Path B, Piercer:** armour pierce / pierce one target / line pierce / pierce everything.
- **Path C, Spotter:** range / marks the target / shares marks with nearby towers / wide mark.

### 4. Adhesive (tier 2, wine)
Lays slow fields; crowd control that makes every other tower stronger.
- **Targeting:** adds **Fastest**.
- **Path A, Sticky:** bigger field / stronger slow / roots briefly / sticky chain.
- **Path B, Tar:** damage-over-time field / flammable / slows projectiles / spreads.
- **Path C, Glue Gun:** range / faster refresh / second field / follows targets.

### 5. Slicer (tier 3, wine)
Short-range sweeper that hits several enemies at once.
- **Targeting:** adds **Most in range**.
- **Path A, Whirl:** wider sweep / faster sweep / damage per target hit / spinning storm.
- **Path B, Edge:** damage / bleed / bleed spreads / execute.
- **Path C, Guard:** more health / parries a hit / reflects ranged shots / revenge sweep.

### 6. Collector (tier 3, power only — no supply)
Gathers drops automatically and trickles resources, so loot doesn't pull the player out of the
fight. It does not attack.
- **Path A, Magnet:** range / speed / pulls from further / collects boss drops.
- **Path B, Yield:** small bonus drops / better bone and hide yield / tier-up chance / rare
  materials.
- **Path C, Tidy:** sorts into the nearest chest / auto-stacks / deposits into feeders /
  hands items to nearby players.

### 7. Rocket (tier 4, ammo)
Slow, area damage; strongest against groups and structures.
- **Targeting:** adds **Cluster** (densest group).
- **Path A, Warhead:** area / damage / burn / cluster bomblets.
- **Path B, Guidance:** range / homing / retargets / lock on the boss.
- **Path C, Concussion:** slow / stun / knock back / shockwave ring.

### 8. Trickster (tier 4, wine)
Marks enemies so everything attacking them deals more damage.
- **Targeting:** adds **Strongest** and **Boss**.
- **Path A, Hex:** mark bonus damage / second mark / mark spreads on death / permanent mark.
- **Path B, Jinx:** slows marked enemies / weakens their attacks / disables special abilities /
  silences boss attacks briefly.
- **Path C, Prank:** peels at the feet / stun / confusion / marks turn on each other.

### 9. Engineer (tier 5, oil)
Roams the base healing structures and towers; earns upkeep, not kills.
- **Targeting:** **Lowest health structure**, **Nearest damaged**.
- **Path A, Mender:** heal speed / heal amount / heals ruins into place / revives a fallen tower
  once per fight.
- **Path B, Mechanic:** roams further / faster / carries extra supply / refuels towers.
- **Path C, Builder:** rebuilds ruins cheaper / builds walls under fire / builds a barricade
  line / emergency fort.

### 10. Repair tower (tier 5, oil)
Stationary support: heals nearby structures and speeds up rebuilding ruins. Complements the
roaming Engineer and keeps the base standing through boss damage.
- **Targeting:** nearest damaged structure.
- **Path A, Field Medic:** heal rate / radius / heals the player / shields.
- **Path B, Foreman:** rebuild speed / rebuild cost down / auto-rebuilds ruins / instant
  rebuild once per fight.
- **Path C, Reinforce:** structure armour / bonus health / absorbs boss structure damage /
  reflects part of it.

### 11. Drill (tier 6, oil)
Roaming melee that can burrow; attacks from below and flanks.
- **Path A, Auger:** damage / speed / digs through walls / drags enemies underground.
- **Path B, Tunneller:** moves faster / burrows under crocs / invulnerable while burrowed /
  erupts for area damage.
- **Path C, Prospector:** collects ore while it roams / better yield / pulls ore to chests /
  rare finds.

### 12. Terrain tower (tier 7, oil)
Reshapes the ground using the terrain-event system: slow zones, walls and fire patches. Built
to counter the bosses' own map effects.
- **Targeting:** **Chokepoint** (narrowest approach), **Boss path**.
- **Path A, Barricade:** raises walls / thicker walls / walls that bar bosses briefly / wall line.
- **Path B, Embers:** fire patch / larger / lingers / spreads to adjacent patches.
- **Path C, Mire:** slow zone / larger / stronger slow / pulls enemies toward its centre.

## Tuning intent: counters

Variety matters more than raw power. Each boss should have a clearly good answer among the
towers, and no single path should beat everything.

| Boss | Good answers | Weak answers |
|---|---|---|
| Green (charge, slams) | Adhesive, Rocket concussion, Boxer Bulwark | thin walls alone |
| Yellow (speed) | Adhesive, MG, Trickster Prank | slow single-shot towers |
| Red (fire) | Repair tower, Terrain Barricade (fireproof), Engineer | wooden bases |
| Blue (cold, freezing) | Terrain Embers, Repair, Engineer | structures that lock up |
| Pink (demolition) | Repair Reinforce, Terrain Barricade, Sniper at range | close-range towers |
| Brown (tunnelling) | Drill, Terrain, Slicer | ranged-only defence |
| Purple (poison) | Engineer, Repair, long-range Sniper | crowded melee |
| White (heals, shields) | Trickster Jinx, burst Sniper, Slicer | slow damage over time |
| Black (revives) | Sniper execute, Trickster Hex, area damage on revival | single-target chip |
| Final | a mix of all | any one build |

## Build and balance checks

- Every tower has a role no other tower fully covers; if two overlap, merge or reshape one.
- A defence of only one tower type must lose to a tier-appropriate boss.
- The `--defense` and `--bossfight` simulations get a **loadout** parameter (tower types,
  paths, supply) and record pass bands per tier.
- Upgrade costs follow a smooth curve in bones/hides then boss materials, so players neither
  hoard nor starve.
