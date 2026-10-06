# Goliradile Isle — Player power

Status: **draft for owner review.** Every number is a starting proposal, to be tuned with the
simulation tools and playtests. Decisions are in `DECISIONS.md`, rules in `DESIGN.md`
("Player power"), tiers in `PROGRESSION.md`, towers in `TOWERS.md`.

**Items marked ⚑ are interpretations I made and want the owner to confirm** (listed at the
end).

## Principles

- **Hybrid role.** The player is a strong fighter; towers hold the base. Intent for a boss
  fight on Normal: the player supplies roughly **a third** of the damage and the towers the
  rest. A player alone must not be able to beat a boss, and neither can towers alone.
- **Levels and gear both matter.** Gear gives named effects; levels give the slots to use them
  and make them stronger.
- **Free-form builds.** No classes. Perks, gear and meals steer a build.
- **Meaningful choices, cheap to change.** Respec is free, so players retune for each boss.

## Levels and XP

- **Levels 1–65.** Level targets at each boss are in `PROGRESSION.md` (5 at the first boss up to
  65 at the Final).
- **Each level** grants **1 stat point**. **Every 2 levels** grants **1 perk point** (about 32
  in total).
- **XP comes from all kills.** Kills by towers pay at a reduced rate (proposal: 40%), the
  player's own kills at the full rate, bosses and milestones add bonuses. Turrets do not
  level.
- XP needed per level grows smoothly (curve to be tuned so the level targets above hold on
  each difficulty).

## Stats

Five stats, each capped at **30 points**. With 65 points to spend, a player maxes two stats
and part of a third, so every build chooses a shape. Starting values per point:

| Stat | Per point | At 30 points | Notes |
|---|---|---|---|
| Health | +15 max health (base 100) | 550 | |
| Attack | +1 base damage (base 2) | 32 | multiplied by weapon and perks |
| Speed | +2% move speed | +60% | |
| Armor | +1.5% damage reduction | 45% | total armour from every source capped at **60%** |
| Regen | +0.3 health per second | +9/s | only while fed and watered |

## Perk tree

About **48 perks** in **4 branches of 12**, each branch in **4 tiers of 3**. A perk tier
unlocks after spending points in that branch (proposal: 0, 3, 6 and 9 points). With about 32
points a player fills one branch and most of a second, or spreads out. Branches are themed;
any mix is allowed.

### Brawler (melee)
| Tier | Perks |
|---|---|
| 1 | **Iron Knuckles** +10% melee damage · **Thick Hide** +5% armour · **Chest Beat** +25% knockback |
| 2 | **Second Wind** kills heal 5% health (every 5 s) · **Counter** after a dodge the next hit +30% · **Pummel** every third hit stuns 0.5 s |
| 3 | **Tremor** melee hits shake the ground (small area) · **Unbreakable** survive a lethal hit once per night or boss (1 health left) · **Rage** below 50% health +25% damage |
| 4 | **Titan** +20% max health and +10% damage · **Crowd Breaker** melee hits all adjacent enemies · **Gorilla Fury** every 10 kills, 5 s berserk |

### Marksman (ranged)
| Tier | Perks |
|---|---|
| 1 | **Steady Aim** +10% ranged damage · **Quick Draw** +10% fire rate · **Sharp Stones** crafted ammo +50% |
| 2 | **Far Sight** +15% range · **Pierce** shots pass through one enemy · **Crit Eye** +10% crit chance |
| 3 | **Ricochet** shots bounce once · **Boss Hunter** +15% damage to bosses · **Lead the Target** projectiles +30% speed |
| 4 | **Eagle Eye** crits hit twice · **Rapid Barrage** every 10 s, 3 s of double fire rate · **Dead Eye** first shot at a full-health enemy deals double |

### Engineer / Commander (towers and building)
| Tier | Perks |
|---|---|
| 1 | **Tinkerer** towers within 5 tiles +5% fire rate · **Cheap Parts** tower costs −10% · **Quick Hands** build speed +20% |
| 2 | **Command Presence** your aura +2 tiles · **Field Repair** nearby towers heal 2%/s · **Overclock** towers in aura +10% damage |
| 3 | **Efficient Fuel** towers use 20% less supply · **Salvage** selling towers refunds +20% · **Supply Runner** you feed towers twice as fast |
| 4 | **Warlord** aura buffs stack to the cap (see below) · **Master Builder** rebuilding ruins costs 25% instead of 50% · **Fire Control** towers in aura share marks |

### Survivalist (food, traps, gathering)
| Tier | Perks |
|---|---|
| 1 | **Forager** +15% gather yield · **Hardy Gut** hunger drains 15% slower · **Quick Sip** thirst drains 15% slower |
| 2 | **Gourmet** meal buffs last 25% longer · **Cook's Kit** cooking 20% faster · **Fleet Foot** +8% move speed out of combat |
| 3 | **Feast Master** +1 active meal slot (max 5) · **Trapper** traps +25% damage · **Green Thumb** crops grow 20% faster |
| 4 | **Second Helping** each meal also grants 20% of a random other meal buff · **Survivor** regen +50% below 30% health · **Pathfinder** ruins and ore glow on the minimap |

**Tower-buff cap:** all tower buffs from player sources (perks, War cry, gear, meals) together
are capped at **+50%** fire rate or damage.

## Gear

**Slots:** weapon, tool, 3 armour pieces, 2 accessories.

**Base gear ladder** (not boss-themed; boss sets replace it at their tier):

| Tier | Armour | Weapons / tools |
|---|---|---|
| 1 | Hide (+4% armour per piece, today's rule) | stone tool, slingshot, mallet, spear |
| 2 | Bone | metal tool |
| 3 | Metal | metal weapons |
| 5 | Alloy | alloy weapons |
| 7 | Reinforced | reinforced weapons |

### Attunement ⚑

This is the system that makes levels and gear interact.

- **Every piece of gear carries one named effect** (armour, weapon and accessory effects are
  listed in the set table below).
- The player has **attunement slots**: **1 from the start, a 2nd at level 15, a 3rd at level
  35.** Only the effects of attuned gear are active, so with three slots the player chooses
  which three of their pieces' effects run. Swapping is free at the workbench or bed.
- **Rank:** every attuned effect has a rank that rises with player level: **rank I from
  level 1, II at 10, III at 20, IV at 30, V at 40, VI at 50, VII at 60.** Each rank adds
  about 20% of the effect's base strength.
- The UI shows the level of the next slot and the next rank.

### Boss sets

Each boss drops materials for a set (crafted with biome materials, per `PROGRESSION.md`). A
set is **three effect-bearing pieces** (armour, weapon, accessory), a **resistance**, and an
**ability** the set unlocks. The Final boss has no set; its reward is the win.

| Boss | Resistance | Armour effect | Weapon effect | Accessory effect | Ability |
|---|---|---|---|---|---|
| Green (Brute) | knockback | **Stonewall** +10% armour near walls | **Cleave** melee hits in an arc | **Brute Charm** +15% max health | **Ground Slam** |
| Yellow (Dash) | slow and snares | **Lightfoot** +12% move speed | **Quick Strike** attack speed up after a dodge | **Afterimage** dodge leaves a decoy | **Banana Throw** |
| Red (Cinder) | fire and burn | **Ember Skin** burn immunity | **Ember** hits ignite | **Hearth** towers in aura +fire rate | **Torch Swing** |
| Blue (Frost) | cold and freeze | **Rime** freeze immunity | **Chill Touch** hits slow | **Frost Core** nearby enemies slowed | **Frost Stomp** |
| Pink (Wrecker) | structure damage | **Rubble Plate** nearby structures +armour | **Wrecking Ball** hits knock enemies into others | **Mason's Belt** ruins rebuild 30% cheaper | **Wrecking Swing** |
| Brown (Burrower) | quakes and undermining | **Tunnelhide** ground effects −50% | **Pick** reveals and hits burrowers | **Seismic Sense** burrowers shown on map | **Burrow** |
| Purple (Toxic) | poison | **Filter Mask** poison immunity | **Venom Tip** hits poison | **Spore Pouch** heals in poison clouds | **Spore Cloud** |
| White (Mender) | debuffs | **Cleansing Fur** removes a debuff every 10 s | **Mender's Touch** hits heal the nearest ally | **Halo** heals structures in aura | **Mend** |
| Black (Shade) | darkness | **Shadowcloak** dodge makes you untargetable briefly | **Soul Drinker** kills heal | **Last Light** revive once per boss at 50% | **Shadow Step** |

## Abilities

Up to **three equipped**: **Dodge roll**, **War cry**, and **one boss-set ability** of the
player's choice. Swapping is free at the workbench or bed.

| Ability | Unlock | Cooldown | Effect (starting values) |
|---|---|---|---|
| **Dodge roll** | start | 6 s | dash 3 tiles with 0.35 s of invulnerability |
| **War cry** | level 8 | 25 s | 6 s: towers within 5 tiles +20% fire rate, player +10% damage |
| **Ground Slam** (Green set) | set | 14 s | area knockback and a short stun around you |
| **Banana Throw** (Yellow set) | set | 10 s | thrown arc that leaves a slippery peel (stuns crocs that step on it) |
| **Torch Swing** (Red set) | set | 12 s | fire arc that ignites enemies and ground briefly |
| **Frost Stomp** (Blue set) | set | 16 s | chilling ring that slows and briefly freezes |
| **Wrecking Swing** (Pink set) | set | 14 s | heavy swing that damages all in a line and breaks cover |
| **Burrow** (Brown set) | set | 18 s | dive underground for 2 s, untargetable, surface with an area hit |
| **Spore Cloud** (Purple set) | set | 20 s | lingering cloud that poisons enemies and heals you |
| **Mend** (White set) | set | 20 s | heals you and nearby allies and structures |
| **Shadow Step** (Black set) | set | 12 s | short teleport that leaves a damaging shade |

## Cooked meals

Cooked meals give **timed buffs** like Terraria's potions. Rules:
- **Active meal slots:** **5 on Easy, 4 on Normal, 3 on Hard.** Eating another replaces the
  oldest. The **Feast Master** perk adds one (max 5).
- **Duration:** **5–10 minutes**, depending on the meal.
- The same meal refreshes its timer; it does not stack with itself.
- **Raw ingredients spoil; cooked meals keep.**
- About **20 meals across 4 tiers.** Meal tier 1 is available from tier 1 of the ladder,
  tier 2 from ladder tier 3, tier 3 from ladder tier 6, tier 4 from ladder tier 9.

| Meal tier | Meal | Ingredients | Buff (starting value) | Time |
|---|---|---|---|---|
| 1 | **Roast Banana** | banana | regen +1/s | 5 min |
| 1 | **Berry Mash** | berries | thirst drains 25% slower | 6 min |
| 1 | **Coconut Cream** | coconut | max health +15% | 6 min |
| 1 | **Fire-Cooked Fish** | fish skewer | +10% attack | 6 min |
| 1 | **Honey-Glazed Skewer** | skewer + honey | regen +2/s, heals a little | 7 min |
| 2 | **Honeyed Fish Stew** | fish, honey, bamboo | +15% armour | 8 min |
| 2 | **Bamboo Shoot Stir-Fry** | bamboo, grass | gather speed +25% | 8 min |
| 2 | **Berry Pie** | berries, honey, coconut shell | move speed +10% | 8 min |
| 2 | **Cinder Chili** | volcano peppers, fish | fire resistance 50% | 10 min |
| 2 | **Frost Chowder** | frost crystal, fish | cold resistance 50% | 10 min |
| 3 | **Bog Broth** | swamp fungi, resin | poison resistance 50% | 10 min |
| 3 | **Sapper's Stew** | deep-cave ore dust, honey | ground and quake damage −30% | 10 min |
| 3 | **Quarry Roast** | highland roots, fish | structure and tower armour +20% | 10 min |
| 3 | **Marksman's Platter** | fish, berries, glapple | +10% crit chance | 8 min |
| 3 | **Tinkerer's Bun** | honey, grass, metal dust | tower fire rate in aura +10% | 8 min |
| 4 | **Clinic Soup** | all biome herbs | removes a debuff every 15 s; regen +3/s | 10 min |
| 4 | **Moonlit Feast** | glapple, black fungus | darkness resistance, see further at night | 10 min |
| 4 | **Warlord's Banquet** | six ingredients | your aura +2 tiles | 10 min |
| 4 | **Titan Stew** | boss-tier ingredients | max health +25%, knockback resistance | 10 min |
| 4 | **Shade Sorbet** | frost crystal, shadow fruit | untargetable 1 s after a dodge | 8 min |

Ingredients that don't exist yet (volcano peppers, frost crystal, swamp fungi, highland roots,
herbs, black fungus, shadow fruit) are added with their biomes in ROADMAP 5f. The **Roast
Banana / Honey-Glazed Skewer / Fire-Cooked Fish** tier-1 meals build on cooking that already
exists (campfire, fish, honey).

## Respec

**Free**, any time, at the **workbench or bed**: stat points, perk points, attunement, equipped
abilities.

## Co-op

- Each player has their **own level, perks, gear and meals**.
- **Each player earns their own XP**; drops are shared; **each player gets their own boss
  reward**.
- Tower buffs from several players' auras add up to the same **+50% cap**.

## Tuning and checks

- The `--bossfight` and `--defense` simulations take a **loadout** (level, stat spread, perks,
  gear, meals) and record the share of damage from the player versus towers; the intended split
  is about 1 : 2.
- Level targets per tier (`PROGRESSION.md`) are checked against the XP curve by a headless
  simulation of a typical run.
- No stat, perk or effect may let one build trivialise a tier-appropriate boss.

## Interpretations to confirm ⚑

1. **Attunement as player slots.** The decision said "gear has perk slots that levels unlock
   and strengthen." I read it as: every piece carries one named effect, the player has
   attunement slots (1, then 2 at level 15, 3 at level 35), and rank rises with level. If you
   meant each piece has its own slots, say so and I will redo this section.
2. **Boss-set pieces:** three pieces per set (armour, weapon, accessory) while the player has
   three armour slots and two accessory slots. Whether sets should fill all slots (for example
   a helmet, chest and boots plus accessories) is open.
3. **Perk tier unlock thresholds** (0, 3, 6, 9 points) and the **40% XP rate for tower kills**.
4. **Ability unlock levels:** War cry at level 8 is a guess.
