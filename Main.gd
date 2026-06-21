extends Node2D
##
## Pixel Grid Base
## -----------------------------------------------------------------------------
## Foundation for the survival / sim / strategy game.
##
## LAYOUT: the game board renders centre; styled side panels (Control UI) flank
## it and hold ALL text/informational UI. The board shows only gameplay cues.
##   * Left panel:  Day/time, day/night threat line, Health, Energy, Inventory.
##   * Right panel: context -- controls, the build menu, or a storage view.
##
## WORLD: 64 x 64 data tiles. Grass/stumps/saplings/doors/floors are walkable
## for the player; doors/walls/etc. block. Survival systems: energy, health,
## food (apples), renewable trees, day/night.
##
## DAY/NIGHT COMBAT:
##   * The world is persistent across night/day; harvested resources and broken
##     structures stay in the grid until systems explicitly regrow or repair them.
##   * Monsters spawn (more each night) and follow flow fields toward the player
##     or later objectives. Walls and doors become chew-through costs, not pathing
##     blind spots. Adjacent, they damage Health. Face one + Space to fight back.
##   * Dawn clears combat actors/effects and runs only explicit regrowth.
##   * Health 0 at night -> you black out and wake at dawn.
##

# Screen-space radial "NIGHT IN m:ss" countdown clock (§8A). A tiny Control on the
# FX CanvasLayer so it lives in HUD space (not the camera-transformed world _draw).
# It forwards its _draw back to the owning game node, which holds all the state.
class CountdownClock extends Control:
	var game = null
	func _draw() -> void:
		if game != null:
			game._draw_countdown_clock(self)


# === FIRST-PASS TUNABLES BEGIN ===============================================
const FP_GRID_CELLS: int = 64
const FP_DAY_LENGTH: float = 150.0
const FP_DAY_START: float = 0.10
const FP_MONSTER_CAP: int = 36
const FP_WAVE_SIZES := {1: 0, 2: 0, 3: 4, 4: 7, 5: 11, 6: 16}
const FP_TREE_AGGRO_FRAC := {4: 0.20, 5: 0.30, 6: 0.40}
const FP_TREE_TIERS := {
	1: {"aura": 4, "hp": 120.0, "sap_next": 40.0},
	2: {"aura": 6, "hp": 200.0, "sap_next": 90.0},
	3: {"aura": 8, "hp": 320.0, "sap_next": 180.0},
	4: {"aura": 10, "hp": 460.0, "sap_next": 320.0},
	5: {"aura": 12, "hp": 620.0, "sap_next": 0.0},
}
const FP_SAP_CONVERSION := {
	"wood": 1.0, "stone": 1.0, "metal": 3.0, "glass": 2.0,
	"honey": 2.0, "berry": 0.5, "banana": 0.5, "cooked_skewer": 0.5,
}
const FP_RESPAWN_DELAY: float = 4.0
const FP_RESPAWN_SAP_COST: float = 15.0
const FP_TREE_DAWN_REGEN_FRAC: float = 0.10
const FP_DEN_START_COUNT: int = 1
const FP_DEN_CAP: int = 4
const FP_DEN_NEW_EVERY_NIGHTS: int = 2
const FP_DEN_BASE_HP: float = 180.0
const FP_DEN_EVOLVED_HP: float = 320.0
const FP_DEN_EVOLVE_MATURITY: int = 2
const FP_DEN_RETALIATION_MULT: float = 1.5
const FP_TURRET_AMMO_MAX: int = 20
const FP_TURRET_START_AMMO: int = 8
const FP_AUTO_MINER_TICK: float = 10.0
const FP_AUTO_MINER_STONE: int = 2
const FP_AUTO_MINER_ORE_CHANCE: float = 0.35
const FP_IRON_VEIN_COUNT: int = 5
const FP_REGROW_STONE: int = 0
const FP_GROUND_ITEM_TTL: float = 90.0
const FP_WORM_DROP_CHANCE: float = 0.06
const FP_HIVE_BEE_CHANCE: float = 0.15
const FP_HIVE_HARVEST_BEE_CHANCE: float = 0.15
const FP_WORLD_STONE_NOISE_THRESHOLD: float = 0.50
const FP_WORLD_TREE_CHANCE: float = 0.06
const FP_WORLD_BUSH_CHANCE: float = 0.02
const FP_WORLD_COCONUT_CHANCE: float = 0.012
const FP_WORLD_BAMBOO_CHANCE: float = 0.015
const FP_WORLD_HIVE_CHANCE: float = 0.004
const FP_REGROW_TREES: int = 3
const FP_REGROW_BUSHES: int = 2
const FP_REGROW_COCONUTS: int = 1
const FP_REGROW_BAMBOO: int = 1
const FP_REGROW_HIVES: int = 0
const FP_TURRET_POWER_RATE_MULT: float = 0.75
const FP_COUNTER_MATRIX := {
	"physical": {"swarm": 1.25, "armored": 0.75, "single": 1.0, "support": 1.0},
	"ranged": {"swarm": 0.75, "armored": 1.25, "single": 1.20, "support": 1.0},
	"support": {"swarm": 0.70, "armored": 0.70, "single": 0.70, "support": 0.70},
}
# Tier tech-gating (decision: the TECH overlay LOCK/OPEN rows must actually
# enforce). Each entry is the minimum _tree_tier required to build/craft/place
# it; anything not listed is tier 1 (always available). The gate is checked both
# ways -- a downgrade re-locks -- in _apply_build_at, _configure_turret, _craft.
# Tiers follow the TECH overlay rows in DESIGN_DECISIONS.md:
#   T2: drill/slicer/rocket turrets + extraction (kiln, juicer)
#   T3: support turrets (engineer/adhesive/trickster) + still, generator
#   T4: bee tech (bee_enclosure), aquarium, sprinkler
#   T5: top-tier ammo tech + reinforced wall + Bomb hook
const FP_STRUCT_TIER := {
	"kiln": 2, "juicer": 2,
	"still": 3, "generator": 3,
	"bee_enclosure": 4, "aquarium": 4, "sprinkler": 4,
	"reinforced_wall": 5,
}
const FP_TURRET_TIER := {
	"drill": 2, "slicer": 2, "rocket": 2,
	"engineer": 3, "adhesive": 3, "trickster": 3,
}
const FP_CRAFT_TIER := {}
# Wall tiers are keyed by structure id here so the block stays independent of
# Terrain enum order.
const FP_WALL_TIERS := {
	"barricade": {"cost": {"wood": 1}, "break_hp": 8, "armor": 0},
	"wood_wall": {"cost": {"wood": 3}, "break_hp": 24, "armor": 0},
	"stone_wall": {"cost": {"stone": 4}, "break_hp": 60, "armor": 2},
	"reinforced_wall": {"cost": {"stone": 6, "metal": 2, "beeswax": 1}, "break_hp": 140, "armor": 4},
	"door": {"cost": {"wood": 2}, "break_hp": 12, "armor": 0},
}
# === FIRST-PASS TUNABLES END =================================================

const GRID_CELLS: int = FP_GRID_CELLS
const CELL_SIZE: float = 32.0
const PLAYER_SPEED: float = 3.0 * CELL_SIZE   # pixels/second
const CROC_SPEED: float = 3.0 * CELL_SIZE     # same as the player for now
const PLAYER_RADIUS: float = CELL_SIZE * 0.34
const MONSTER_RADIUS: float = CELL_SIZE * 0.34
const CAMERA_ZOOM: float = 1.5
const WORLD_SEED: int = 1337
const PANEL_W: float = 280.0

# --- Survival / time tuning --------------------------------------------------
const ENERGY_MAX: float = 100.0
const ENERGY_DRAIN: float = 0.4
const ENERGY_NIGHT_EXTRA: float = 0.25
const ENERGY_MOVE: float = 1.5         # per second while moving
const ENERGY_HARVEST: float = 1.5
const ENERGY_BUILD: float = 0.5
const EAT_RESTORE: float = 30.0
const DAY_LENGTH: float = FP_DAY_LENGTH
const HEALTH_MAX: float = 100.0
const HEALTH_DRAIN: float = 2.0
const HEALTH_REGEN: float = 1.0
const HEALTH_REGEN_ENERGY: float = 50.0
const MAX_LIVES: int = 3                # 1 default + 2 extra; out of all 3 = game over

# --- Hydration / drinks ------------------------------------------------------
const HYDRATION_MAX: float = 100.0
const HYDRATION_DRAIN: float = 0.30     # thirst per second
const HYDRATION_HEALTH_DRAIN: float = 1.5  # health lost/sec while fully parched
const WATER_HYDRATION: float = 45.0     # a cup of water
const JUICE_HYDRATION: float = 30.0     # berry juice (also heals a little)
const JUICE_HEAL: float = 8.0
const WINE_HYDRATION: float = 12.0      # berry wine -- lowest hydration

# --- Crafting / utility tuning -----------------------------------------------
const GRASS_PER_STRING: int = 3
const WOOD_PER_CUP: int = 2
const BARREL_CAP: int = 20              # cups of water OR juice (not both)
const JUICER_CAP: int = 10              # berry juice held
const JUICE_PER_BERRY: int = 2
const JUICE_TICK: float = 3.0           # juicer converts a berry this often
const CUP_JUICE_SPOIL: float = 25.0     # loose berry juice spoils after this long (sec)
const FERMENT_TIME: float = DAY_LENGTH * 2.0  # juice in a barrel -> wine after 2 cycles
const PLANTER_GROW: float = 8.0         # seconds (watered) to grow each berry
const PLANTER_DRY: float = 20.0         # a watering keeps the bush growing this long

# --- Fruit / regrowth tuning -------------------------------------------------
const BANANA_TICK: float = 2.0
const BANANA_GROW_CHANCE: float = 0.02
const BANANA_START_CHANCE: float = 0.30
const BERRY_GROW_CHANCE: float = 0.03    # wild bushes regrow berries a touch faster
const BUSH_MAX_BERRIES: int = 3          # planter bushes (and wild) cap here
const STUMP_TIME: float = 12.0
const SAPLING_TIME: float = 18.0

# --- Food spoilage -----------------------------------------------------------
const DECAY_INTERVAL: float = 4.0        # spoilage is rolled this often (seconds)
const BANANA_DECAY_CHANCE: float = 0.05  # chance one fresh banana spoils per roll
const BERRY_DECAY_CHANCE: float = 0.07   # berries spoil a bit faster
const GLAPPLE_DECAY_CHANCE: float = 0.09 # the glowing apple fades fast
const GLAPPLE_LAMP_DECAY_CHANCE: float = 0.04  # an unplaced lamp slowly dies too
# Fresh kind -> the rotten kind it decays into (glapples just become generic rot).
const PERISHABLE := {"banana": "rotten_banana", "berry": "rotten_berry", "glapple": "rot"}
const DECAY_CHANCE := {"banana": BANANA_DECAY_CHANCE, "berry": BERRY_DECAY_CHANCE, "glapple": GLAPPLE_DECAY_CHANCE}
# A placed glapple lamp glows for this long, then goes dark (destroy it for parts).
const LAMP_LIFE: float = DAY_LENGTH * 1.5
const LAMP_RADIUS := {"glapple": CELL_SIZE * 2.6, "oil": CELL_SIZE * 4.0, "electric": CELL_SIZE * 5.2}
const LAMP_COLOR := {"glapple": Color(0.45, 0.7, 1.0), "oil": Color(1.0, 0.78, 0.4), "electric": Color(1.0, 1.0, 0.85)}
# Inventory display order + labels (only nonzero rows are shown).
const INV_ORDER := [
	"wood", "stone", "grass", "string", "seed",
	"bamboo", "metal_ore", "coconut", "coconut_shell", "glapple",
	"sand", "metal", "charcoal", "gunpowder", "scrap", "casing", "glass", "glass_jar",
	"worm", "bee", "honey", "beeswax", "fertilizer",
	"croc_hide", "bone",
	"fish_m", "fish_f", "fish_bones", "fish_skewer", "cooked_skewer", "ash",
	"rope", "glue", "wooden_rod", "nails",
	"stone_tool", "metal_tool", "slingshot", "mallet", "spear", "sling_ammo",
	"glapple_lamp", "rot",
	"banana", "berry", "banana_peel", "rotten_banana", "rotten_berry",
	"cup", "cup_water", "cup_juice", "cup_wine", "cup_oil",
]
const ITEM_LABELS := {
	"wood": "Wood", "stone": "Stone", "grass": "Grass", "string": "String", "seed": "Seed",
	"bamboo": "Bamboo", "metal_ore": "Metal Ore", "coconut": "Coconut", "coconut_shell": "Coconut Shell",
	"glapple": "Glapple", "sand": "Sand", "metal": "Metal", "charcoal": "Charcoal", "gunpowder": "Gunpowder",
	"scrap": "Scrap", "casing": "Casing", "glass": "Glass", "glass_jar": "Glass Jar",
	"worm": "Worm (jar)", "bee": "Bee (jar)", "honey": "Honey", "beeswax": "Beeswax", "fertilizer": "Fertilizer",
	"croc_hide": "Croc Hide", "bone": "Bone",
	"fish_m": "Fish (M)", "fish_f": "Fish (F)", "fish_bones": "Fish Bones",
	"fish_skewer": "Raw Skewer", "cooked_skewer": "Cooked Skewer", "ash": "Ash",
	"rope": "Rope", "glue": "Glue", "wooden_rod": "Wooden Rod", "nails": "Nails",
	"stone_tool": "Stone Tool", "metal_tool": "Metal Tool", "slingshot": "Slingshot",
	"mallet": "Mallet", "spear": "Spear", "sling_ammo": "Sling Ammo",
	"glapple_lamp": "Glapple Lamp", "rot": "Rot",
	"banana": "Banana", "berry": "Berry", "banana_peel": "Banana Peel",
	"rotten_banana": "Rotten Banana", "rotten_berry": "Rotten Berry",
	"cup": "Empty Cup", "cup_water": "Cup of Water", "cup_juice": "Cup of Juice", "cup_wine": "Cup of Wine",
	"cup_oil": "Cup of Berry Oil",
}
# Flavor + role, one terse sentence each (the field-journal voice). Mechanical
# numbers live in _tooltip_stat_line, never here, so they can't drift. Sibling of
# ITEM_LABELS so a missing-desc selftest is one loop over INV_ORDER.
const ITEM_DESC := {
	"wood": "Cut from trees. The Isle's first material.",
	"stone": "Chipped from rock. Walls, tools, nails.",
	"grass": "Twisted into string.",
	"string": "Three twists make rope.",
	"seed": "Drop in a planter to grow berries.",
	"bamboo": "Fast, light shafts. Pipes and stills.",
	"metal_ore": "Raw ore. The kiln smelts it to metal.",
	"coconut": "Food and water in one shell.",
	"coconut_shell": "Empty husk. Nothing left in it.",
	"glapple": "Glowing apple. Feeds a lamp.",
	"sand": "Beach grit. The kiln fires it to glass.",
	"metal": "Smelted ingot. Tools, machines, rounds.",
	"charcoal": "Charred wood. Hot kiln fuel; makes powder.",
	"gunpowder": "The one munition. Every turret runs on it.",
	"scrap": "Salvaged from corpses. Smelts back to metal.",
	"casing": "Spent shell. Swept at dawn for a refund.",
	"glass": "Clear and brittle. Jars, hives, tanks.",
	"glass_jar": "Holds a caught worm or bee.",
	"worm": "Jarred. Composts rot; feeds the tank.",
	"bee": "Jarred. Stock an enclosure for honey.",
	"honey": "Sweet. Deposits well as Sap.",
	"beeswax": "Seals the reinforced wall.",
	"fertilizer": "Boosts a planter's next harvests.",
	"croc_hide": "Tanned into armor.",
	"bone": "Ground to fertilizer.",
	"fish_m": "Raw fish. Eat it or breed it.",
	"fish_f": "Raw roe-bearer. Breeds in the tank.",
	"fish_bones": "Picked clean. Waste.",
	"fish_skewer": "Raw. Cook it on a campfire.",
	"cooked_skewer": "Hot meal. Restores hunger.",
	"ash": "Burnt to nothing. Waste.",
	"rope": "Binds the bigger builds.",
	"glue": "Boiled from spoiled fruit. Sticks wire.",
	"wooden_rod": "A shaped haft for tools and traps.",
	"nails": "Stone-cut fixings.",
	"stone_tool": "Gathers +1 yield and uses 60% energy.",
	"metal_tool": "Gathers +2 yield and uses 40% energy.",
	"slingshot": "Throws stone from a safe distance.",
	"mallet": "Slow, heavy, knocks crocs back hard.",
	"spear": "Long reach. Strike before they close.",
	"sling_ammo": "Stone shot for the slingshot.",
	"glapple_lamp": "Placed light. Holds back the dark.",
	"rot": "Spoiled matter. Worms turn it to feed.",
	"banana": "Quick hunger. Spoils if you hoard it.",
	"berry": "Eat it, juice it, or deposit it.",
	"banana_peel": "Slick. Loads the peel launcher.",
	"rotten_banana": "Spoiled. Boil it down to glue.",
	"rotten_berry": "Spoiled. Boil it down to glue.",
	"cup": "Empty. Fill at water, juicer, or barrel.",
	"cup_water": "Slakes thirst best.",
	"cup_juice": "Hydrates and heals a little.",
	"cup_wine": "Poured into turrets as backup fuel.",
	"cup_oil": "Pressed berry oil. Runs a generator.",
}
# Hybrid inventory (decision #17): the bulk list groups INV_ORDER into category
# bands with a header before each non-empty band. INV_CATEGORY maps item -> band;
# INV_BAND_ORDER fixes the band sequence and header text.
const INV_BAND_ORDER := ["materials", "components", "tools", "critters", "food", "drinks", "waste"]
const INV_BAND_LABEL := {
	"materials": "MATERIALS", "components": "COMPONENTS", "tools": "TOOLS & ARMS",
	"critters": "CRITTERS & BEES", "food": "FOOD & FISH", "drinks": "DRINKS", "waste": "WASTE",
}
const INV_CATEGORY := {
	"wood": "materials", "stone": "materials", "grass": "materials", "sand": "materials",
	"bamboo": "materials", "metal_ore": "materials", "metal": "materials", "charcoal": "materials",
	"glass": "materials", "scrap": "materials", "casing": "materials",
	"string": "components", "rope": "components", "glue": "components", "wooden_rod": "components",
	"nails": "components", "glass_jar": "components", "gunpowder": "components", "beeswax": "components",
	"fertilizer": "components",
	"stone_tool": "tools", "metal_tool": "tools", "slingshot": "tools", "mallet": "tools",
	"spear": "tools", "sling_ammo": "tools", "glapple_lamp": "tools",
	"worm": "critters", "bee": "critters", "honey": "critters", "croc_hide": "critters", "bone": "critters",
	"coconut": "food", "coconut_shell": "food", "banana": "food", "berry": "food", "cooked_skewer": "food",
	"fish_m": "food", "fish_f": "food", "fish_skewer": "food", "seed": "food", "glapple": "food",
	"cup": "drinks", "cup_water": "drinks", "cup_juice": "drinks", "cup_wine": "drinks", "cup_oil": "drinks",
	"rot": "waste", "ash": "waste", "fish_bones": "waste", "banana_peel": "waste",
	"rotten_banana": "waste", "rotten_berry": "waste",
}
const EAT_ENERGY := {"banana": 30.0, "berry": 18.0}   # energy restored by eating each
# Drink kind -> [hydration, health, energy]; the cup empties afterward.
const DRINKS := {
	"cup_water": [WATER_HYDRATION, 0.0, 0.0],
	"cup_juice": [JUICE_HYDRATION, JUICE_HEAL, 6.0],
	"cup_wine":  [WINE_HYDRATION, 0.0, 0.0],
}
# Phase 5: bees, worms, fish, cooking.
const WORM_CAP: int = 10                  # worms a habitat tops out at
const WORM_MULTIPLY_TIME: float = 14.0    # seconds to breed one more worm (needs >=2)
const COMPOST_TIME: float = 10.0          # seconds for worms to turn 1 rot -> 1 fertilizer
const FERTILIZER_BONUS_HARVESTS: int = 4  # extra-yield harvests granted per fertilizer
const BEE_CAP: int = 4                     # bees one enclosure houses
const BEE_PROD_TIME: float = 16.0          # seconds per honey/beeswax cycle (scales w/ bees)
const BEE_PLANT_RADIUS: int = 4            # a plant must be within this many tiles to thrive
const BEE_STARVE_TIME: float = 40.0        # with no plants near, a bee is lost after this
const HIVE_BEE_CHANCE: float = FP_HIVE_BEE_CHANCE  # chance a wild hive looses a bee each dawn
const FISH_MAX: int = 8                    # fish the pool holds at once
const FISH_CATCH_R: float = CELL_SIZE * 1.6
const FISH_ENERGY: float = 28.0            # raw fish ~ a banana of hunger, no hydration
const COOK_TIME: float = 8.0               # skewer is done after this on a campfire
const COOK_BURN_TIME: float = 16.0         # left this long, it chars to ash
const STILL_TICK: float = 6.0              # seconds to refine one cup of juice into oil
# Phase 7: power. A generator burns berry oil to energize its wire network.
const GEN_OIL_MAX: int = 5                 # cups of berry oil a generator holds
const GEN_DRAIN_TIME: float = DAY_LENGTH * 0.5  # one cup of oil powers it this long
const POWER_SPEED_MULT: float = 2.0        # powered juicer/still/kiln run this much faster
# Phase 8: plumbing + the breeding aquarium.
const SPRINKLER_RADIUS: int = 3            # planters within this many tiles are auto-watered
const AQUARIUM_WATER_MAX: int = 20         # cups of water the tank holds
const AQUARIUM_FISH_SAFE: int = 10         # fish beyond this pollute the water faster + faster
const AQUARIUM_POLLUTE: float = 0.6        # quality lost per fish per second
const AQUARIUM_FILTER_GAIN: float = 6.0    # quality regained per second when the filter runs
const AQUARIUM_FEED_TIME: float = 30.0     # one worm feeds the tank this long
const AQUARIUM_BREED_TIME: float = 22.0    # seconds between spawning attempts (50% hatch)

# Phase 4: the kiln smelts/melts/chars over time, burning wood or charcoal fuel.
const KILN_TICK: float = 2.5             # seconds to finish one conversion
const KILN_FUEL_MAX: float = 100.0
const KILN_FUEL_PER_WOOD: float = 18.0   # fuel gained by feeding one wood
const KILN_FUEL_PER_CHARCOAL: float = 45.0  # charcoal is the denser fuel
const KILN_FUEL_PER_JOB: float = 10.0    # fuel burned per conversion

# Phase 1 naturals + materials tuning.
const COCONUT_ENERGY: float = 26.0       # hunger restored by a coconut
const COCONUT_HYDRATION: float = 22.0    # coconut also slakes thirst
const ORE_DROP_CHANCE: float = 0.35      # chance a smashed rock yields metal ore
const GLAPPLE_DAWN_CHANCE: float = 0.45  # chance a fresh glapple appears each dawn
const GLUE_PER_ROT: int = 2              # rotten fruit consumed per glue

# Handheld crafting recipes (key C). Placeable utilities live in the build menu.
# "glue" is special-cased in _craft (it eats any spoiled fruit, not a fixed item).
const CRAFT_ORDER := ["string", "cup", "rope", "wooden_rod", "nails", "glue", "gunpowder", "casing_powder", "scrap_metal",
	"sling_ammo", "metal_ammo", "stone_tool", "metal_tool", "slingshot", "mallet", "spear",
	"glapple_lamp", "glass_jar", "fish_skewer", "bone_meal", "hide_armor"]
const CRAFT_RECIPES := {
	"string":     {"label": "String", "out": "string", "cost": {"grass": GRASS_PER_STRING}},
	"cup":        {"label": "Empty Cup", "out": "cup", "cost": {"wood": WOOD_PER_CUP}},
	"rope":       {"label": "Rope", "out": "rope", "cost": {"string": 3}},
	"wooden_rod": {"label": "Wooden Rod", "out": "wooden_rod", "cost": {"wood": 2}},
	"nails":      {"label": "Nails (x2)", "out": "nails", "cost": {"stone": 1}, "out_count": 2},
	"glue":       {"label": "Glue", "out": "glue", "cost": {}, "rot": GLUE_PER_ROT},
	"gunpowder":  {"label": "Gunpowder (x4)", "out": "gunpowder", "cost": {"stone": 1, "charcoal": 1}, "out_count": 4},
	"casing_powder": {"label": "Reclaim Casings -> Gunpowder (x2)", "out": "gunpowder", "cost": {"casing": 3}, "out_count": 2},
	"scrap_metal": {"label": "Smelt Scrap -> Metal", "out": "metal", "cost": {"scrap": 3}},
	"sling_ammo": {"label": "Sling Ammo (x4)", "out": "sling_ammo", "cost": {"stone": 1}, "out_count": 4},
	"stone_tool": {"label": "Stone Tool", "out": "stone_tool", "cost": {"wood": 3, "stone": 3, "rope": 1}},
	"slingshot":  {"label": "Slingshot", "out": "slingshot", "cost": {"wooden_rod": 1, "rope": 1}},
	"mallet":     {"label": "Mallet", "out": "mallet", "cost": {"wooden_rod": 1, "stone": 4}},
	"spear":      {"label": "Spear", "out": "spear", "cost": {"wooden_rod": 1, "stone": 2, "nails": 2}},
	"glapple_lamp": {"label": "Glapple Lamp", "out": "glapple_lamp", "cost": {"glapple": 1, "wooden_rod": 1}},
	"metal_ammo": {"label": "Sling Ammo from Metal (x10)", "out": "sling_ammo", "cost": {"metal": 1}, "out_count": 10},
	"metal_tool": {"label": "Metal Tool", "out": "metal_tool", "cost": {"metal": 2, "wooden_rod": 1, "rope": 1}},
	"glass_jar":  {"label": "Glass Jar", "out": "glass_jar", "cost": {"glass": 1}},
	"fish_skewer": {"label": "Raw Skewer (rod + 3 fish)", "out": "fish_skewer", "cost": {"wooden_rod": 1}, "fish": 3},
	"bone_meal":  {"label": "Bone Meal -> Fertilizer", "out": "fertilizer", "cost": {"bone": 2}},
	"hide_armor": {"label": "Hide Armor (+armor)", "out": "", "cost": {"croc_hide": 3}, "armor": HIDE_ARMOR_STEP},
}

# --- World pool + daily regrowth ---------------------------------------------
const POOL_CENTER := Vector2(12.0, 13.0)  # the one constant water pool (never moves)
const POOL_RADIUS: float = 4.2
const GROUND_ITEM_TTL: float = FP_GROUND_ITEM_TTL
const REGROW_TREES: int = FP_REGROW_TREES  # new resources sprinkled onto empty grass each dawn
const REGROW_STONE: int = FP_REGROW_STONE
const REGROW_BUSHES: int = FP_REGROW_BUSHES
const REGROW_COCONUTS: int = FP_REGROW_COCONUTS
const REGROW_BAMBOO: int = FP_REGROW_BAMBOO
const REGROW_HIVES: int = FP_REGROW_HIVES

# --- Combat / monster tuning -------------------------------------------------
# These are the *base* (night-1 / level-1) stats; both sides scale from here.
const MONSTER_HP: float = 4.0          # base croc health
const PLAYER_DMG: float = 2.0          # base player attack
const MONSTER_HIT: float = 8.0         # base croc attack
const MONSTER_ATK_INTERVAL: float = 0.8   # seconds between a monster's attacks
const MONSTER_BRK_INTERVAL: float = 0.6   # seconds between hits on a blocking wall
const ATTACK_RANGE: float = CELL_SIZE * 0.85  # monster stops & attacks within this
const PUNCH_TIME: float = 0.3          # full out-and-back punch duration (seconds)
const PUNCH_REACH: float = CELL_SIZE * 0.85   # how far the fist extends
const FIST_R: float = CELL_SIZE * 0.16        # fist hit radius (only the fist hurts)
const KNOCKBACK: float = 9.0 * CELL_SIZE      # initial knockback speed (px/sec)
const KB_DECAY: float = 1400.0                # knockback slowdown (px/sec^2)

# --- Player equipment: one tool slot + one weapon slot -----------------------
# Tools universally speed up wood/stone gathering (more per swing, less energy).
const TOOL_DEFS := {
	"stone_tool": {"label": "Stone Tool", "bonus": 1, "energy": 0.6},
	"metal_tool": {"label": "Metal Tool", "bonus": 2, "energy": 0.4},
}
const TOOL_ITEMS := ["stone_tool", "metal_tool"]
# Weapon "" == bare fists. dmg/reach/time are multipliers of the punch baseline;
# a ranged weapon fires a projectile instead of swinging.
const WEAPON_DEFS := {
	"":          {"label": "Fists",     "dmg": 1.0, "reach": 1.0, "time": 1.0, "kb": 1.0, "ranged": false, "desc": "Always ready. Weakest hit on the Isle."},
	"mallet":    {"label": "Mallet",    "dmg": 2.4, "reach": 0.95, "time": 1.8, "kb": 2.4, "ranged": false, "desc": "Heavy and slow. Knocks crocs off the wall."},
	"spear":     {"label": "Spear",     "dmg": 1.5, "reach": 1.9,  "time": 1.1, "kb": 1.0, "ranged": false, "desc": "Outranges a snout. Poke, step, poke."},
	"slingshot": {"label": "Slingshot", "dmg": 1.3, "reach": 1.0,  "time": 1.0, "kb": 0.6, "ranged": true, "desc": "Ranged stone. Chip them before they bite."},
}
const WEAPON_ITEMS := ["slingshot", "mallet", "spear"]
const SLING_PROJ_SPEED: float = CELL_SIZE * 13.0

# --- Combat juice ------------------------------------------------------------
const FLASH_TIME: float = 0.14         # white hit-flash duration
const SHAKE_DECAY: float = 40.0        # screen-shake falloff (px/sec)
const POOF_TIME: float = 0.35          # croc death burst duration
const SPARK_TIME: float = 0.18         # punch-connect spark duration
const LOW_HP_FRAC: float = 0.35        # vignette shows below this health fraction
const HITSTOP_HIT: float = 0.045       # brief freeze when the player lands a punch
const HITSTOP_HURT: float = 0.075      # bigger freeze when the player gets hit

# --- Juice / _fx transient-effects-list lifetimes (seconds) ------------------
# All heterogeneous _fx entries advance their normalized t by delta/life and are
# culled at t>=1. See _draw_fx / _update_juice.
const FX_GORE_LIFE: float = 0.40       # croc gut-splat ring
const FX_CHUNK_LIFE: float = 0.55      # croc chunk debris (the composite's tail)
const FX_FLASH_LIFE: float = 0.12      # croc contact white kernel
const FX_WALLHIT_LIFE: float = 0.22    # croc-gnaws-wall impact splinter
const FX_DMGNUM_LIFE: float = 0.85     # floating combat number
const FX_DMGNUM_AGG_DIST: float = CELL_SIZE * 0.6   # aggregation radius
const FX_DMGNUM_AGG_T: float = 0.45    # only fold into entries younger than this
const FX_BUILD_LIFE: float = 0.45      # build/repair placement flash
const FX_TIER_LIFE: float = 1.6        # Mother-Tree dawn bloom
const FX_DUSK_SWEEP_LIFE: float = 1.2  # golden horizon sweep at dusk onset
const FX_SPAWNWARN_LIFE: float = 10.0  # pulsing shore ring, spans to night-begin
const FX_TIER_GLOW_DECAY: float = 0.5  # _tier_glow seconds to fade
const FX_CLOCK_FLASH_DECAY: float = 0.5 # _clock_flash pulse seconds to fade
# Leaf palette anchors for the tier-up leaf burst (mirror the local bake colors).
const FX_LEAF: Color = Color(0.20, 0.42, 0.22)
const FX_LEAF_D: Color = Color(0.14, 0.32, 0.16)
const FX_LEAF_L: Color = Color(0.31, 0.55, 0.31)
const FX_SUNSET: Color = Color(1.05, 0.80, 0.55)   # warm amber sunset wash
const MONSTER_BASE: int = 3            # monsters on night 1
const MONSTER_PER_DAY: int = 2         # extra monsters each subsequent night
const MONSTER_CAP: int = FP_MONSTER_CAP
const SPAWN_MIN_DIST: int = 11         # spawn at least this far from the player
const FIELD_INF: float = 1.0e9
const FIELD_BLOCKED: int = 100000000
const FLOW_PLAYER_INTERVAL: float = 0.20
# Phase 10: the required-progression ramp. Past this night the horde + fuel burn
# outpace hand-poured wine, so turrets must be wired to a generator (powered = no burn).
const POWER_DEMAND_NIGHT: int = 6
const TURRET_FUEL_NIGHT_SCALE: float = 0.18  # extra wine burn per night for UNPOWERED turrets
const HIDE_ARMOR_STEP: float = 0.04          # armor gained per hide_armor crafted
const HIDE_ARMOR_CAP: float = 0.30           # cap on gear armor from hides

# --- Per-night monster escalation --------------------------------------------
const MON_HP_GROW: float = 1.5
const MON_ATK_GROW: float = 1.5
const MON_SPD_GROW: float = 0.06       # +6% speed per night
const MON_SPD_CAP: float = 2.0         # max speed multiplier
const MON_ARM_GROW: float = 0.03
const MON_ARM_CAP: float = 0.5
const MON_REGEN_GROW: float = 0.3      # hp/sec gained per night past the first
const MON_XP_BASE: int = 3             # XP for killing a night-1 croc
const MON_XP_GROW: float = 2.0         # +XP per night -- deep-night kills level turrets fast

# --- Player leveling ----------------------------------------------------------
const HEALTH_PER_LEVEL: float = 20.0
const ATK_PER_LEVEL: float = 1.0
const SPD_PER_LEVEL: float = 0.03
const ARMOR_PER_LEVEL: float = 0.03
const ARMOR_CAP: float = 0.6
const REGEN_PER_LEVEL: float = 0.3

# --- Croc roster -------------------------------------------------------------
# Each type defines its colors, stat multipliers (vs. the night's base croc),
# a behaviour role, the first night it can appear, and a spawn weight.
const CROC_DEFS := {
	"green":  {"body": Color(0.32, 0.54, 0.30), "belly": Color(0.58, 0.72, 0.46), "hp": 1.0, "atk": 1.0, "spd": 1.0, "role": "melee",   "aggro": "swarm",   "unlock": 1, "weight": 5, "desc": "Grunt. Comes in numbers; physical turrets shred it."},
	"yellow": {"body": Color(0.88, 0.78, 0.20), "belly": Color(0.96, 0.90, 0.55), "hp": 0.7, "atk": 0.5, "spd": 1.7, "role": "melee",   "aggro": "player",  "unlock": 2, "weight": 3, "desc": "Flanker. Fast, darts at you -- not the base."},
	"red":    {"body": Color(0.78, 0.26, 0.22), "belly": Color(0.93, 0.56, 0.45), "hp": 1.0, "atk": 1.0, "spd": 0.9, "role": "fire",    "aggro": "player",  "unlock": 3, "weight": 3, "desc": "Burns. Hits you from range; close the gap or wall up."},
	"blue":   {"body": Color(0.28, 0.50, 0.82), "belly": Color(0.62, 0.82, 0.97), "hp": 1.0, "atk": 0.8, "spd": 0.9, "role": "ice",     "aggro": "player",  "unlock": 4, "weight": 3, "desc": "Chills and slows. Don't get pinned in the open."},
	"pink":   {"body": Color(0.86, 0.46, 0.68), "belly": Color(0.97, 0.74, 0.86), "hp": 1.6, "atk": 1.0, "spd": 0.7, "role": "wrecker", "aggro": "tree",    "unlock": 5, "weight": 2, "desc": "Rammer. Ignores you, chews the wall. Armor needs ranged."},
	"brown":  {"body": Color(0.48, 0.34, 0.20), "belly": Color(0.68, 0.54, 0.36), "hp": 1.1, "atk": 1.1, "spd": 1.0, "role": "digger",  "aggro": "tree",    "unlock": 6, "weight": 2, "desc": "Sapper. Tunnels the wall and surfaces inside."},
	"purple": {"body": Color(0.56, 0.34, 0.74), "belly": Color(0.80, 0.62, 0.92), "hp": 1.0, "atk": 1.0, "spd": 0.85,"role": "poison",  "aggro": "swarm",   "unlock": 7, "weight": 2, "desc": "Leaves a poison cloud. Don't stand in it."},
	"white":  {"body": Color(0.86, 0.88, 0.92), "belly": Color(0.97, 0.98, 1.00), "hp": 1.2, "atk": 0.0, "spd": 1.0, "role": "healer",  "aggro": "support", "unlock": 8, "weight": 2, "desc": "Mends its pack. Kill it first."},
	"black":  {"body": Color(0.20, 0.20, 0.25), "belly": Color(0.40, 0.40, 0.47), "hp": 1.2, "atk": 1.0, "spd": 1.0, "role": "reviver", "aggro": "swarm",   "unlock": 9, "weight": 2, "desc": "Plays dead, then gets back up. Burn it down."},
}

# --- Projectiles / status / special-croc tuning ------------------------------
const RANGED_RANGE: float = CELL_SIZE * 6.0     # red/blue start shooting within this
const RANGED_CD: float = 1.8                    # seconds between ranged shots
const PROJ_SPEED: float = CELL_SIZE * 7.0       # projectile travel speed
const PROJ_RADIUS: float = CELL_SIZE * 0.18     # projectile hit radius vs. player
const FIRE_DMG: float = 4.0                     # fireball impact damage
const BURN_DPS: float = 4.0                     # burn damage per second
const BURN_TIME: float = 3.0                    # burn duration
const SNOW_DMG: float = 2.0                     # snowball impact damage
const SLOW_FACTOR: float = 0.8                  # snowball slows move speed to 80%
const SLOW_TIME: float = 1.0
const FREEZE_HITS: int = 3                      # snowballs within the window to freeze
const FREEZE_WINDOW: float = 5.0
const FREEZE_TIME: float = 2.0
const PURPLE_RANGE: float = CELL_SIZE * 2.6     # purple's short attack range
const PURPLE_CD: float = 2.2                    # slow-firing
const POISON_TIME: float = 2.5                  # cloud lingers this long
const POISON_DPS: float = 6.0                   # damage per second while standing in it
const POISON_RADIUS: float = CELL_SIZE * 0.95
const HEAL_RADIUS: float = CELL_SIZE * 3.2      # white croc heal aura
const HEAL_DPS: float = 3.0                     # hp/sec restored to allies in radius
const REVIVE_TIME: float = 2.0                  # black croc lies dead this long, then revives
const DIG_SURFACE_RANGE: float = CELL_SIZE * 2.2  # brown croc surfaces within this of player
const PINK_STRUCT_MUL: int = 3                  # pink croc does this many break-hits per chew

# --- Buildable defenses: traps ----------------------------------------------
const ARROW_SPEED: float = CELL_SIZE * 12.0     # generic friendly projectile speed
const TRAP_DMG: float = 7.0                     # spike-trap damage per trigger
const TRAP_SLOW_TIME: float = 1.5               # how long a tripped croc is slowed
# Phase 9: trap cap + the three new traps.
const MAX_TRAPS: int = 10                        # placed traps allowed at once
const TRAP_REPAIR_COST := {"wood": 2}            # restores a worn trap's durability
const TRAP_MAX_HP := {"peel_launcher": 8}  # wear HP (lost per shot)
const MINE_RADIUS: float = CELL_SIZE * 2.2       # land-mine blast radius
const MINE_DMG: float = 32.0
const PEEL_CD: float = 1.2                        # peel-launcher fire interval
const PEEL_RANGE: float = CELL_SIZE * 6.0
const PEEL_DMG: float = 1.0                       # minimal impact damage
const PEEL_GROUND_LIFE: float = 4.0               # a dropped peel lingers this long
const PEEL_STUN_TIME: float = 2.0                 # croc that steps on a peel is frozen
const FENCE_ZAP_CD: float = 0.6
const FENCE_ZAP_DMG: float = 6.0
const TRAP_REARM: float = 2.5                   # seconds before a trap re-arms

# --- Global progression caps -------------------------------------------------
const LEVEL_CAP: int = 122                       # player / croc / turret max level
const STAT_UPGRADE_CAP: int = 70                 # max points into any single stat

# --- Turrets -----------------------------------------------------------------
# Ranges/aoe are in CELL_SIZE multiples; hp/dmg are absolute; cd is seconds.
const TURRET_CATEGORIES := ["physical", "ranged", "support"]
const TURRET_TYPES := {
	"physical": ["boxer", "drill", "slicer"],
	"ranged":   ["sniper", "mg", "rocket"],
	"support":  ["engineer", "adhesive", "trickster"],
}
const TURRET_DEFS := {
	"sniper":    {"label": "Sniper",      "cat": "ranged",   "hp": 12.0, "range": 9.0, "cd": 2.2,  "dmg": 14.0, "kb": 1.2,  "crit": 0.25, "proj": "snipe", "desc": "One hard shot. Cracks armor."},
	"mg":        {"label": "Machine Gun", "cat": "ranged",   "hp": 10.0, "range": 6.0, "cd": 0.25, "dmg": 4.0,  "kb": 0.0,  "proj": "bullet", "spread": 0.18, "desc": "Fast and hungry. Empties fast."},
	"rocket":    {"label": "Rocket",      "cat": "ranged",   "hp": 11.0, "range": 7.0, "cd": 2.5,  "dmg": 9.0,  "kb": 0.0,  "proj": "rocket", "aoe": 1.8, "aoefrac": 0.4, "slow": 1.0, "desc": "Splash and slow. Punishes a pack."},
	"boxer":     {"label": "Boxer",       "cat": "physical", "hp": 18.0, "range": 1.4, "cd": 0.35, "dmg": 6.0,  "kb": 0.4, "desc": "Tanky fists. Best against swarms."},
	"drill":     {"label": "Drill",       "cat": "physical", "hp": 12.0, "range": 1.3, "cd": 0.2,  "dmg": 3.0,  "kb": 0.15, "mover": true, "desc": "Roams and grinds. Holds a gap."},
	"slicer":    {"label": "Slicer",      "cat": "physical", "hp": 14.0, "range": 1.9, "cd": 1.2,  "dmg": 9.0,  "kb": 0.5,  "multi": true, "desc": "Wide arc, hits a cluster at once."},
	"engineer":  {"label": "Engineer",    "cat": "support",  "hp": 12.0, "range": 2.2, "cd": 0.0,  "dmg": 0.0,  "kb": 0.0,  "mover": true, "heal": 5.0, "desc": "Mends nearby turrets. Deals no damage."},
	"adhesive":  {"label": "Adhesive",    "cat": "support",  "hp": 10.0, "range": 8.0, "cd": 2.5,  "dmg": 0.0,  "kb": 0.0,  "field": 2.6, "fieldslow": 0.12, "desc": "Slows everything in its field."},
	"trickster": {"label": "Trickster",   "cat": "support",  "hp": 10.0, "range": 6.5, "cd": 0.0,  "dmg": 0.0,  "kb": 0.0,  "marks": 2, "markdmg": 0.2, "desc": "Marks crocs so allies hit harder."},
}
const TURRET_CAT_LABEL := {"physical": "Physical", "ranged": "Ranged", "support": "Support"}
const TURRET_CAT_BLURB := {
	"physical": "Tanky close-range bruiser with knockback.",
	"ranged": "Fragile, fires from a distance.",
	"support": "Aids your other turrets / weakens crocs.",
}

const TURRET_FUEL_MAX: float = 100.0            # "5 cups" of berry wine
const TURRET_FUEL_PER_CUP: float = 20.0         # a poured cup_wine refills this much
const TURRET_FUEL_PER_ACTION: float = 0.45      # base fuel spent per attack/ability
const TURRET_FUEL_LVL_SCALE: float = 0.01       # +1% fuel burn per level
const TURRET_PROJ_SPEED: float = CELL_SIZE * 12.0
const TURRET_MOVE_SPEED: float = CELL_SIZE * 3.2  # roaming drill/engineer speed
const TURRET_REPAIR_FRAC: float = 0.25          # HP restored per repair click
const TURRET_REPAIR_COST := {"wood": 2, "stone": 1}
const TURRET_XP_BASE: int = 4
const MAX_TURRETS: int = 5                      # only five may stand on the isle at once
# XP attribution: kills are worth full XP, assists half. An assist counts only if
# the turret damaged the croc within this many seconds of its death.
const TURRET_ASSIST_WINDOW: float = 3.0
const TURRET_ASSIST_FRAC: float = 0.5
# Support turrets earn no kills, so a debuff still "live" on the croc at death
# (or applied within this window) pays full XP to the adhesive/trickster behind it.
const TURRET_SUPPORT_WINDOW: float = 3.0
# Engineers can't fight; they bank a consistent slice of every croc the team
# downs -- but only while they've been actively mending allies.
const TURRET_ENGINEER_XP_FRAC: float = 0.5
const TURRET_ENGINEER_HEAL_WINDOW: float = 4.0
# Per-level turret growth + which stat each allocated point buffs.
const TURRET_HP_PER: float = 6.0
const TURRET_DMG_PER: float = 1.0
const TURRET_RATE_PER: float = 0.04            # -4% cooldown per point
const TURRET_RANGE_PER: float = 0.10           # +0.1 cell range per point
const TURRET_STAT_ORDER := ["hp", "dmg", "rate", "range"]
const TURRET_STAT_LABEL := {"hp": "Health", "dmg": "Damage", "rate": "Fire Rate", "range": "Range"}

# --- Terrain -----------------------------------------------------------------
enum Terrain {
	GRASS, WATER, TREE, STONE, STUMP, SAPLING,
	WOOD_WALL, STONE_WALL, DOOR, WORKBENCH, FLOOR, STORAGE,
	TURRET, TRAP, BUSH, BARREL, JUICER, PLANTER,
	COCONUT, BAMBOO, GLAPPLE_LAMP, SAND, KILN,
	HIVE, BEE_ENCLOSURE, WORM_FARM, CAMPFIRE, STILL,
	GENERATOR, WIRE, BULB,
	PIPE, SPRINKLER, AQUARIUM,
	LAND_MINE, PEEL_LAUNCHER, ELECTRIC_FENCE,
	WRECK, BARRICADE, REINFORCED_WALL, MOTHER_TREE, CROC_DEN,
	IRON_VEIN, AUTO_MINER, AUTO_LOADER,
}

const TERRAIN_COLOR := {
	Terrain.GRASS: Color(0.42, 0.60, 0.31),
	Terrain.WATER: Color(0.26, 0.44, 0.62),
	Terrain.TREE: Color(0.18, 0.38, 0.21),
	Terrain.STONE: Color(0.52, 0.52, 0.55),
	Terrain.STUMP: Color(0.42, 0.60, 0.31),
	Terrain.SAPLING: Color(0.42, 0.60, 0.31),
	Terrain.WOOD_WALL: Color(0.55, 0.38, 0.20),
	Terrain.STONE_WALL: Color(0.66, 0.66, 0.70),
	Terrain.DOOR: Color(0.64, 0.46, 0.26),
	Terrain.WORKBENCH: Color(0.72, 0.52, 0.26),
	Terrain.FLOOR: Color(0.74, 0.66, 0.48),
	Terrain.STORAGE: Color(0.50, 0.34, 0.16),
	Terrain.TURRET: Color(0.45, 0.45, 0.50),
	Terrain.TRAP: Color(0.30, 0.30, 0.33),
	Terrain.BUSH: Color(0.24, 0.44, 0.26),
	Terrain.BARREL: Color(0.50, 0.34, 0.18),
	Terrain.JUICER: Color(0.62, 0.30, 0.40),
	Terrain.PLANTER: Color(0.46, 0.32, 0.18),
	Terrain.COCONUT: Color(0.20, 0.40, 0.22),
	Terrain.BAMBOO: Color(0.42, 0.62, 0.34),
	Terrain.GLAPPLE_LAMP: Color(0.35, 0.55, 0.85),
	Terrain.SAND: Color(0.82, 0.74, 0.52),
	Terrain.KILN: Color(0.40, 0.34, 0.34),
	Terrain.HIVE: Color(0.78, 0.62, 0.22),
	Terrain.BEE_ENCLOSURE: Color(0.74, 0.60, 0.28),
	Terrain.WORM_FARM: Color(0.46, 0.40, 0.30),
	Terrain.CAMPFIRE: Color(0.40, 0.26, 0.16),
	Terrain.STILL: Color(0.56, 0.50, 0.44),
	Terrain.GENERATOR: Color(0.44, 0.44, 0.50),
	Terrain.WIRE: Color(0.55, 0.40, 0.20),
	Terrain.BULB: Color(0.95, 0.92, 0.6),
	Terrain.PIPE: Color(0.50, 0.62, 0.40),
	Terrain.SPRINKLER: Color(0.50, 0.58, 0.66),
	Terrain.AQUARIUM: Color(0.40, 0.62, 0.74),
	Terrain.LAND_MINE: Color(0.45, 0.35, 0.30),
	Terrain.PEEL_LAUNCHER: Color(0.86, 0.78, 0.30),
	Terrain.ELECTRIC_FENCE: Color(0.60, 0.62, 0.30),
	Terrain.WRECK: Color(0.30, 0.28, 0.25),
	Terrain.BARRICADE: Color(0.48, 0.30, 0.16),
	Terrain.REINFORCED_WALL: Color(0.50, 0.52, 0.56),
	Terrain.MOTHER_TREE: Color(0.20, 0.42, 0.24),
	Terrain.CROC_DEN: Color(0.22, 0.17, 0.14),
	Terrain.IRON_VEIN: Color(0.44, 0.42, 0.38),
	Terrain.AUTO_MINER: Color(0.42, 0.44, 0.48),
	Terrain.AUTO_LOADER: Color(0.45, 0.38, 0.26),
}

const TILE_DEF := {
	Terrain.GRASS: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.WATER: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.WATER},
	Terrain.TREE: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.STUMP},
	Terrain.STONE: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.GRASS},
	Terrain.STUMP: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.SAPLING: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.WOOD_WALL: {"player_walk": false, "monster_walk": false, "break_hp": FP_WALL_TIERS["wood_wall"]["break_hp"], "armor": FP_WALL_TIERS["wood_wall"]["armor"], "impassable": false, "on_break": Terrain.WRECK},
	Terrain.STONE_WALL: {"player_walk": false, "monster_walk": false, "break_hp": FP_WALL_TIERS["stone_wall"]["break_hp"], "armor": FP_WALL_TIERS["stone_wall"]["armor"], "impassable": false, "on_break": Terrain.WRECK},
	Terrain.DOOR: {"player_walk": true, "monster_walk": false, "break_hp": FP_WALL_TIERS["door"]["break_hp"], "armor": FP_WALL_TIERS["door"]["armor"], "impassable": false, "on_break": Terrain.WRECK},
	Terrain.WORKBENCH: {"player_walk": false, "monster_walk": false, "break_hp": 4, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.FLOOR: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.STORAGE: {"player_walk": false, "monster_walk": false, "break_hp": 4, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.TURRET: {"player_walk": false, "monster_walk": false, "break_hp": 5, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.TRAP: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.BUSH: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.GRASS},
	Terrain.BARREL: {"player_walk": false, "monster_walk": false, "break_hp": 6, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.JUICER: {"player_walk": false, "monster_walk": false, "break_hp": 5, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.PLANTER: {"player_walk": false, "monster_walk": false, "break_hp": 5, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.COCONUT: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.STUMP},
	Terrain.BAMBOO: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.GRASS},
	Terrain.GLAPPLE_LAMP: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.SAND: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.SAND},
	Terrain.KILN: {"player_walk": false, "monster_walk": false, "break_hp": 7, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.HIVE: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.GRASS},
	Terrain.BEE_ENCLOSURE: {"player_walk": false, "monster_walk": false, "break_hp": 5, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.WORM_FARM: {"player_walk": false, "monster_walk": false, "break_hp": 5, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.CAMPFIRE: {"player_walk": false, "monster_walk": false, "break_hp": 4, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.STILL: {"player_walk": false, "monster_walk": false, "break_hp": 6, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.GENERATOR: {"player_walk": false, "monster_walk": false, "break_hp": 8, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.WIRE: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.BULB: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.PIPE: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.SPRINKLER: {"player_walk": false, "monster_walk": false, "break_hp": 4, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.AQUARIUM: {"player_walk": false, "monster_walk": false, "break_hp": 8, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.LAND_MINE: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.PEEL_LAUNCHER: {"player_walk": false, "monster_walk": false, "break_hp": 8, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.ELECTRIC_FENCE: {"player_walk": false, "monster_walk": false, "break_hp": 4, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.WRECK: {"player_walk": true, "monster_walk": true, "break_hp": 0, "armor": 0, "impassable": false, "on_break": Terrain.GRASS},
	Terrain.BARRICADE: {"player_walk": false, "monster_walk": false, "break_hp": FP_WALL_TIERS["barricade"]["break_hp"], "armor": FP_WALL_TIERS["barricade"]["armor"], "impassable": false, "on_break": Terrain.WRECK},
	Terrain.REINFORCED_WALL: {"player_walk": false, "monster_walk": false, "break_hp": FP_WALL_TIERS["reinforced_wall"]["break_hp"], "armor": FP_WALL_TIERS["reinforced_wall"]["armor"], "impassable": false, "on_break": Terrain.WRECK},
	Terrain.MOTHER_TREE: {"player_walk": false, "monster_walk": false, "break_hp": 1, "armor": 0, "impassable": false, "on_break": Terrain.MOTHER_TREE},
	Terrain.CROC_DEN: {"player_walk": false, "monster_walk": false, "break_hp": 1, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.IRON_VEIN: {"player_walk": false, "monster_walk": false, "break_hp": 0, "armor": 0, "impassable": true, "on_break": Terrain.IRON_VEIN},
	Terrain.AUTO_MINER: {"player_walk": false, "monster_walk": false, "break_hp": 8, "armor": 1, "impassable": false, "on_break": Terrain.WRECK},
	Terrain.AUTO_LOADER: {"player_walk": false, "monster_walk": false, "break_hp": 6, "armor": 0, "impassable": false, "on_break": Terrain.WRECK},
}

# Walkability, break-HP, armor, and impassability all live in TILE_DEF (the single
# source of truth). Use the _tile_player_walk / _tile_monster_walk / _tile_break_hp /
# _tile_armor / _tile_impassable helpers for every collision, spawn, and damage read.

const STRUCTURES := {
	"wood_wall":  {"num": 1, "terrain": Terrain.WOOD_WALL,  "cost": FP_WALL_TIERS["wood_wall"]["cost"],  "label": "Wood Wall",  "bench": false, "desc": "Honest cover. Buys you seconds."},
	"stone_wall": {"num": 2, "terrain": Terrain.STONE_WALL, "cost": FP_WALL_TIERS["stone_wall"]["cost"], "label": "Stone Wall", "bench": false, "desc": "Armored. Shrugs off swarm bites."},
	"door":       {"num": 3, "terrain": Terrain.DOOR,       "cost": FP_WALL_TIERS["door"]["cost"],       "label": "Door",       "bench": false, "desc": "A deliberate gap. Your sortie route -- and theirs."},
	"workbench":  {"num": 4, "terrain": Terrain.WORKBENCH,  "cost": {"wood": 4, "stone": 2}, "label": "Workbench",  "bench": false, "desc": "Unlocks the advanced builds nearby."},
	"floor":      {"num": 5, "terrain": Terrain.FLOOR,      "cost": {"wood": 1},             "label": "Floor",      "bench": true, "desc": "Clean footing. Marks your ground."},
	"storage":    {"num": 6, "terrain": Terrain.STORAGE,    "cost": {"wood": 3},             "label": "Storage",    "bench": true, "desc": "Stows the overflow. Walk up to sort."},
	"turret":     {"num": 7, "terrain": Terrain.TURRET,     "cost": {"wood": 3, "stone": 3}, "label": "Turret",     "bench": true, "desc": "The base's hands. Pick its type at placement."},
	"trap":       {"num": 8, "terrain": Terrain.TRAP,       "cost": {"wood": 2, "stone": 2}, "label": "Spike Trap", "bench": true, "desc": "Spikes underfoot. Wounds and slows."},
	"barrel":     {"num": 9, "terrain": Terrain.BARREL,     "cost": {"wood": 8, "stone": 3, "string": 2}, "label": "Barrel",   "bench": true, "desc": "Ferments juice into wine over time."},
	"juicer":     {"num": 10, "terrain": Terrain.JUICER,    "cost": {"wood": 5, "stone": 3, "string": 1}, "label": "Juicer",   "bench": true, "desc": "Presses berries into juice."},
	"planter":    {"num": 11, "terrain": Terrain.PLANTER,   "cost": {"wood": 6, "string": 2}, "label": "Planter Box", "bench": true, "desc": "Grows berries from seed. Fertilize for more."},
	"glapple_lamp": {"num": 12, "terrain": Terrain.GLAPPLE_LAMP, "cost": {"glapple_lamp": 1}, "label": "Glapple Lamp", "bench": false, "desc": "A fixed light. Keeps a corner lit."},
	"kiln":       {"num": 13, "terrain": Terrain.KILN,      "cost": {"stone": 12, "nails": 4}, "label": "Kiln", "bench": true, "desc": "Smelts ore, fires sand, chars wood."},
	"campfire":   {"num": 14, "terrain": Terrain.CAMPFIRE,  "cost": {"wood": 4, "stone": 4}, "label": "Campfire", "bench": false, "desc": "Cooks skewers. Don't walk off and burn them."},
	"bee_enclosure": {"num": 15, "terrain": Terrain.BEE_ENCLOSURE, "cost": {"wood": 6, "glass": 2, "rope": 2}, "label": "Bee Enclosure", "bench": true, "desc": "Houses bees for honey and wax."},
	"worm_farm":  {"num": 16, "terrain": Terrain.WORM_FARM,  "cost": {"glass": 3, "wood": 2}, "label": "Worm Habitat", "bench": true, "desc": "Breeds worms; composts rot to fertilizer."},
	"still":      {"num": 17, "terrain": Terrain.STILL,      "cost": {"bamboo": 4, "metal": 2, "glass": 1}, "label": "Still", "bench": true, "desc": "Refines juice into berry oil."},
	"generator":  {"num": 18, "terrain": Terrain.GENERATOR,  "cost": {"metal": 4, "bamboo": 4, "glue": 2, "wooden_rod": 2}, "label": "Generator", "bench": true, "desc": "Burns oil to power wired turrets -- no reload."},
	"wire":       {"num": 19, "terrain": Terrain.WIRE,       "cost": {"string": 1, "metal_ore": 1, "glue": 1}, "label": "Wire", "bench": false, "desc": "Carries power out from the generator or Tree."},
	"bulb":       {"num": 20, "terrain": Terrain.BULB,       "cost": {"glass": 2, "metal": 1, "nails": 2}, "label": "Electric Bulb", "bench": true, "desc": "Wired light. Proof the line is live."},
	"pipe":       {"num": 21, "terrain": Terrain.PIPE,       "cost": {"bamboo": 1, "glue": 1, "rope": 1}, "label": "Pipe", "bench": false, "desc": "Routes water to sprinklers."},
	"sprinkler":  {"num": 22, "terrain": Terrain.SPRINKLER,  "cost": {"bamboo": 3, "metal": 1}, "label": "Sprinkler", "bench": true, "desc": "Auto-waters nearby planters."},
	"aquarium":   {"num": 23, "terrain": Terrain.AQUARIUM,   "cost": {"glass": 8, "metal": 2, "rope": 2}, "label": "Fish Aquarium", "bench": true, "desc": "Breeds fish. Keep the water clean."},
	"land_mine":  {"num": 24, "terrain": Terrain.LAND_MINE,  "cost": {"metal": 1, "charcoal": 1}, "label": "Land Mine", "bench": true, "desc": "One blast, then gone. Save it for a pack."},
	"peel_launcher": {"num": 25, "terrain": Terrain.PEEL_LAUNCHER, "cost": {"bamboo": 3, "wooden_rod": 1, "rope": 1}, "label": "Peel Launcher", "bench": true, "desc": "Flings peels. Steppers freeze in place."},
	"electric_fence": {"num": 26, "terrain": Terrain.ELECTRIC_FENCE, "cost": {"metal": 2, "wooden_rod": 1}, "label": "Electric Fence", "bench": true, "desc": "Zaps anything that leans on it."},
	"barricade": {"num": 27, "terrain": Terrain.BARRICADE, "cost": FP_WALL_TIERS["barricade"]["cost"], "label": "Barricade", "bench": false, "desc": "Cheap emergency patch. Folds fast."},
	"reinforced_wall": {"num": 28, "terrain": Terrain.REINFORCED_WALL, "cost": FP_WALL_TIERS["reinforced_wall"]["cost"], "label": "Reinforced Wall", "bench": true, "desc": "The hard line. Waxed and metal-banded."},
	"auto_miner": {"num": 29, "terrain": Terrain.AUTO_MINER, "cost": {"metal": 2, "wooden_rod": 1}, "label": "Auto-Miner", "bench": true, "desc": "Mines a vein forever. Build more to scale."},
	"auto_loader": {"num": 30, "terrain": Terrain.AUTO_LOADER, "cost": {"wood": 4, "metal": 1}, "label": "Auto-Loader", "bench": true, "desc": "Feeds gunpowder to the turret beside it."},
}
const STRUCTURE_ORDER := ["wood_wall", "stone_wall", "door", "workbench", "floor", "storage", "turret", "trap", "barrel", "juicer", "planter", "glapple_lamp", "kiln", "campfire", "bee_enclosure", "worm_farm", "still", "generator", "wire", "bulb", "pipe", "sprinkler", "aquarium", "land_mine", "peel_launcher", "electric_fence", "barricade", "reinforced_wall", "auto_miner", "auto_loader"]
# Every trap kind, for the 10-trap placement cap.
const TRAP_TERRAIN := {Terrain.TRAP: true, Terrain.LAND_MINE: true, Terrain.PEEL_LAUNCHER: true, Terrain.ELECTRIC_FENCE: true}

# Placed-block cap: only the structural pieces that shape/obstruct the base count.
# Turrets, workstations (bench/storage/barrel/juicer/planter/etc), traps, pipes and
# wires are all exempt -- they have their own limits or none.
const BLOCK_LIMIT: int = 80
const BLOCK_TERRAIN := {
	Terrain.BARRICADE: true, Terrain.WOOD_WALL: true, Terrain.STONE_WALL: true, Terrain.REINFORCED_WALL: true, Terrain.DOOR: true, Terrain.FLOOR: true,
}
# Loot lying on the ground is vacuumed up when the player wanders within this range.
const LOOT_PICKUP_R: float = CELL_SIZE * 0.9

# --- Colors ------------------------------------------------------------------
const COLOR_GRID: Color = Color(0.0, 0.0, 0.0, 0.18)
const COLOR_PLAYER: Color = Color(1.0, 0.85, 0.1)
const COLOR_FACE: Color = Color(0.15, 0.12, 0.0)
const COLOR_FACE_HL: Color = Color(1.0, 1.0, 1.0, 0.85)
const COLOR_BUILD_HL: Color = Color(0.40, 1.0, 0.45, 0.9)
const COLOR_DESTROY_HL: Color = Color(1.0, 0.40, 0.40, 0.9)
const COLOR_BANANA: Color = Color(0.96, 0.82, 0.20)
const COLOR_STUMP: Color = Color(0.45, 0.31, 0.17)
const COLOR_SAPLING: Color = Color(0.24, 0.55, 0.28)
const COLOR_MONSTER: Color = Color(0.82, 0.16, 0.20)
const NIGHT_COLOR: Color = Color(0.36, 0.42, 0.62)   # moonlit blue, bright enough for fx to read

# UI palette
const UI_SLATE: Color = Color(0.10, 0.11, 0.14)
const UI_ACCENT: Color = Color(0.95, 0.80, 0.35)
const UI_BORDER: Color = Color(0.26, 0.28, 0.36)
const UI_BAR_BG: Color = Color(0.05, 0.05, 0.07)
const UI_WOOD: Color = Color(0.60, 0.42, 0.22)
const UI_STONE: Color = Color(0.62, 0.62, 0.66)
const UI_FOOD: Color = Color(0.85, 0.25, 0.25)
# Legibility palette (tooltip frame, hotbar, affordability). One home so the later
# Theme pass owns it. Hexes from the design brief (#RRGGBB).
const UI_OK: Color = Color("#74C46A")       # affordable / sufficient
const UI_SHORT: Color = Color("#D86A5E")    # short / empty (the ONLY red signal)
const UI_TOOL: Color = Color("#7FB5E0")     # hotbar tool-slot border (steel-blue)
const UI_WEAPON: Color = Color("#E0A24C")   # hotbar weapon-slot border (amber)
const UI_AMMO: Color = Color("#C9C46A")     # hotbar ammo-slot border (brass)
const UI_FUEL: Color = Color("#9A6CC4")     # turret fuel bar (wine/power purple)
const UI_SUBTLE: Color = Color("#7E84A0")   # subtitle / band header
const UI_DESC: Color = Color("#9AA0B4")     # desc body text (muted)
const UI_NAME: Color = Color("#F2F4FA")     # tooltip name row
const UI_STAT: Color = Color("#C8CCDA")     # tooltip computed-stat row
const UI_TIP_BG: Color = Color(0.0824, 0.0902, 0.1098, 0.95)  # #15171C @ .95

# --- Visual-identity palette (design brief) ----------------------------------
# Additive to the four anchor consts (UI_SLATE/UI_ACCENT/UI_BORDER/UI_BAR_BG).
# UI chrome: panels, cards, slots, text tiers. Consumed by the programmatic Theme
# (_apply_theme) so panels/cards/buttons share one identity instead of inline overrides.
const UI_PANEL_2: Color = Color("#22252F")  # raised card / docked-station fill (one step up from slate)
const UI_SLOT_BG: Color = Color("#13151B")  # inventory slot well
const UI_BORDER_HI: Color = Color("#5E6680") # hovered / focused border
const UI_TEXT: Color = Color("#EBEEF5")     # primary text
const UI_TEXT_DIM: Color = Color("#8B92A3") # secondary / unaffordable label
const UI_TEXT_MUTE: Color = Color("#5A6070") # disabled / greyed recipe
# Theme font sizes (one home; the programmatic Theme reads these).
const FS_HEADER: int = 22
const FS_BODY: int = 16
const FS_BUTTON: int = 14
const FS_SMALL: int = 12
# Semantic state colors -- "danger = warm glow" carries world->UI->den escalation.
const UI_POWER: Color = Color("#56C8E0")    # electricity / aura / power-related
const UI_WARN: Color = Color("#E8A23A")     # dusk countdown / low fuel / low ammo (warm warning)
const UI_BAD: Color = Color("#E04848")      # unaffordable / blocked / damage / Tree-seeker
# Item-category tints: slot border + icon family base (replace the HSV-by-index hack).
const CAT_WOOD: Color = Color("#9A6B38")     # wood, bamboo, wooden_rod, charcoal
const CAT_STONE: Color = Color("#9FA0A6")    # stone, sand, glass, nails, scrap
const CAT_METAL: Color = Color("#B8C2CC")    # metal, metal_ore, casing, gunpowder
const CAT_ORGANIC: Color = Color("#6FA84A")  # grass, string, seed, rope, glue, fertilizer, worm
const CAT_FOOD: Color = Color("#E7B23C")     # banana, berry, coconut, honey, fish, skewer
const CAT_FLUID: Color = Color("#4FB0D8")    # cup, cup_*, glass_jar
const CAT_CREATURE: Color = Color("#C77B5A") # croc_hide, bone, bee, fish_bones
const CAT_TOOL: Color = Color("#D6C27A")     # stone_tool..glapple_lamp, weapons, sling_ammo
const CAT_WASTE: Color = Color("#6B5E4A")    # rot, ash, banana_peel, rotten_*, coconut_shell
# World accents for the Mother Tree / Den escalation overlays.
const TREE_BARK: Color = Color("#5E4A2E")
const TREE_LEAF_TIERS := [
	Color("#2E5A24"), Color("#3C7A2E"), Color("#4E9636"), Color("#5FB23E"), Color("#7AD24E"),
]   # canopy lightens as Tree tier 1->5 climbs
const SAP_GLOW: Color = UI_ACCENT            # aura ring / Sap particles (= gold)
const DEN_MOUND: Color = Color("#3A2C20")    # Den earth
const DEN_MAW: Color = Color("#0F0B08")      # Den entrance void
const DEN_EMBER: Color = Color("#C8542A")    # mature-Den glow

# --- TECH hub: branch rows, gated by the Tree tier that unlocks them. Data-driven
# so the full-screen TECH column is one loop, and the lock state reflects the REAL
# tier enforcement. The 25s NEW-marker + LEFT-HUD nudge key off _tree_tier vs these.
const TECH_ROWS := [
	{"tier": 1, "branch": "DEFENSE",    "label": "Basic turrets, walls, barricades"},
	{"tier": 2, "branch": "EXTRACTION", "label": "Drill, slicer, rocket turret, kiln, juicer"},
	{"tier": 3, "branch": "SUPPORT",    "label": "Engineer / adhesive / trickster, still, generator"},
	{"tier": 4, "branch": "BEE-TECH",   "label": "Apiary, beeswax ammo, aquarium, sprinkler"},
	{"tier": 5, "branch": "AMMO-TECH",  "label": "Top-tier ammo, the Bomb (cracks hardened Dens)"},
]
const TECH_BRANCH_HUE := {
	"DEFENSE": Color(0.70, 0.74, 0.82), "EXTRACTION": UI_STONE,
	"SUPPORT": Color(0.55, 0.80, 1.0), "BEE-TECH": Color(0.95, 0.74, 0.22),
	"AMMO-TECH": Color(0.90, 0.45, 0.40),
}
const TECH_NEW_DWELL: float = 25.0          # NEW marker lifetime after a tier-up
# HP-state thresholds (hard bands so "danger" reads instantly, not a gradient).
const HP_GREEN: Color = Color(0.40, 0.78, 0.42)
const HP_AMBER: Color = Color(0.92, 0.70, 0.25)
const HP_RED: Color = Color(0.88, 0.28, 0.28)

# --- One-shot onboarding beats. Each fires at most once ever and is persisted, so
# the tutorial never replays across sessions; _reset_game clears it so New Game
# re-teaches. Triggers live where the state already changes (one _onboard call each).
const ONBOARD_BEATS := ["welcome", "first_thirst", "first_hunger", "day2_dusk",
	"first_turret", "first_night", "tier_up", "first_den_seen", "casings",
	"tier_locked", "first_vein"]
const ONBOARD_TINT: Color = Color(0.55, 0.85, 1.0)   # instructional blue (vs amber msg / red night)

# Per-item-id -> category-tint family. The icon base + slot border read off this
# so a glanced icon reads its family. Every INV_ORDER id must map (selftest).
const ITEM_CATEGORY_TINT := {
	"wood": CAT_WOOD, "bamboo": CAT_WOOD, "charcoal": CAT_WOOD, "wooden_rod": CAT_WOOD,
	"stone": CAT_STONE, "sand": CAT_STONE, "glass": CAT_STONE, "nails": CAT_STONE, "scrap": CAT_STONE,
	"metal": CAT_METAL, "metal_ore": CAT_METAL, "casing": CAT_METAL, "gunpowder": CAT_METAL,
	"grass": CAT_ORGANIC, "string": CAT_ORGANIC, "seed": CAT_ORGANIC, "rope": CAT_ORGANIC,
	"glue": CAT_ORGANIC, "fertilizer": CAT_ORGANIC, "worm": CAT_ORGANIC, "beeswax": CAT_ORGANIC,
	"banana": CAT_FOOD, "berry": CAT_FOOD, "coconut": CAT_FOOD, "honey": CAT_FOOD,
	"fish_m": CAT_FOOD, "fish_f": CAT_FOOD, "fish_skewer": CAT_FOOD, "cooked_skewer": CAT_FOOD,
	"cup": CAT_FLUID, "cup_water": CAT_FLUID, "cup_juice": CAT_FLUID, "cup_wine": CAT_FLUID,
	"cup_oil": CAT_FLUID, "glass_jar": CAT_FLUID,
	"croc_hide": CAT_CREATURE, "bone": CAT_CREATURE, "bee": CAT_CREATURE, "fish_bones": CAT_CREATURE,
	"stone_tool": CAT_TOOL, "metal_tool": CAT_TOOL, "slingshot": CAT_TOOL, "mallet": CAT_TOOL,
	"spear": CAT_TOOL, "sling_ammo": CAT_TOOL, "glapple_lamp": CAT_TOOL, "glapple": CAT_TOOL,
	"rot": CAT_WASTE, "ash": CAT_WASTE, "banana_peel": CAT_WASTE,
	"rotten_banana": CAT_WASTE, "rotten_berry": CAT_WASTE, "coconut_shell": CAT_WASTE,
}

# Marker colors for loot lying on the ground (falls back to grey for anything unlisted).
const LOOT_ITEM_COLOR := {
	"wood": UI_WOOD, "stone": UI_STONE, "grass": Color(0.46, 0.66, 0.34),
	"banana": COLOR_BANANA, "berry": Color(0.62, 0.24, 0.72),
	"banana_peel": Color(0.92, 0.86, 0.42), "seed": Color(0.74, 0.62, 0.40),
	"rotten_banana": Color(0.42, 0.36, 0.18), "rotten_berry": Color(0.32, 0.20, 0.30),
	"bamboo": Color(0.52, 0.70, 0.36), "metal_ore": Color(0.62, 0.55, 0.48),
	"coconut": Color(0.50, 0.34, 0.20), "coconut_shell": Color(0.40, 0.27, 0.16),
	"glapple": Color(0.35, 0.62, 1.0),
	"worm": Color(0.85, 0.55, 0.55), "bee": Color(0.95, 0.82, 0.25),
	"croc_hide": Color(0.34, 0.50, 0.32), "bone": Color(0.92, 0.92, 0.84),
}

enum BuildAction { NONE, BUILD, DESTROY }
enum Overlay { NONE, LEVELUP, SETTINGS, TECH }

# --- State -------------------------------------------------------------------
var _terrain: PackedInt32Array = PackedInt32Array()
var _banana: PackedByteArray = PackedByteArray()
var _berry: PackedByteArray = PackedByteArray()    # bush berry count (0..BUSH_MAX_BERRIES)
var _growth: PackedFloat32Array = PackedFloat32Array()
var _pool_shore: Array = []                        # walkable cells touching the water pool
var _cell: Vector2i = Vector2i(GRID_CELLS / 2, GRID_CELLS / 2)  # tile the player is on
var _facing: Vector2i = Vector2i(0, 1)                          # last cardinal direction
var _player_pos: Vector2                                        # continuous world position
var _player_kb: Vector2 = Vector2.ZERO                          # knockback velocity

# Punch (night melee)
var _punch_active: bool = false
var _punch_t: float = 0.0          # 0..1 over PUNCH_TIME
var _punch_dir: Vector2 = Vector2.RIGHT
var _punch_hit: bool = false       # has this punch already connected?

# Combat juice
var _shake: float = 0.0
var _hitstop: float = 0.0          # world-freeze timer for impact punch
var _hurt_flash: float = 0.0
var _spark_t: float = 1.0          # >=1 inactive
var _spark_pos: Vector2 = Vector2.ZERO
var _poofs: Array = []             # [{pos:Vector2, t:float}, ...]
var _ground_items: Array = []      # [{pos:Vector2, kind:String, count:int, t:float}, ...] auto-collected loot
var _block_count: int = 0          # live tally of placed structural blocks (vs BLOCK_LIMIT)

var _resources := {"wood": 0, "stone": 0, "banana": 0, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
var _decay_timer: float = 0.0
var _juice_spoil_t: float = 0.0    # loose cup-of-juice spoilage timer
var _sap: float = 0.0              # Tree-internal hub resource; not an inventory item
# Window-size presets (all 16:9 to match the canvas, so no letterboxing).
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

# --- Title screen / menu state -----------------------------------------------
enum AppState { SPLASH, MENU, SETTINGS, PLAYING }
const GAME_SAVE_PATH := "user://goliradile_isle_game.save"
const SPLASH_HOLD := 1.8            # seconds the "For William." card holds before fading
const SPLASH_FADE := 1.1            # fade-out duration
var _app_state: int = AppState.PLAYING   # PLAYING by default so --selftest/--shot bypass the menu
var _splash_t: float = 0.0
var _settings_return: int = AppState.MENU  # where the Settings overlay returns to
var _menu_layer: CanvasLayer
var _splash_root: Control
var _menu_root: Control
var _settings_root: Control
var _confirm_root: Control
var _menu_btns: VBoxContainer
var _lbl_menu_best: Label
var _barrels := {}                 # idx -> {kind:"water"|"juice"|"wine"|"", amount:int, ferment:float}
var _juicers := {}                 # idx -> {juice:int, conv:float}
var _planters := {}                # idx -> {planted:bool, berries:int, grow:float, wet:float}
var _lamps := {}                   # idx -> {kind:String, life:float, dead:bool} placed light sources
var _kilns := {}                   # idx -> {fuel:float, queue:Array, conv:float} smelter/charrer
var _apiaries := {}                # idx -> {bees:int, prod:float, starve:float} bee enclosures
var _wormfarms := {}               # idx -> {worms:int, rot:int, mult:float, compost:float} habitats
var _campfires := {}               # idx -> {item:String, cook:float} cooking spots
var _stills := {}                  # idx -> {pending:int, conv:float} juice -> berry oil
var _generators := {}              # idx -> {oil:int, on:bool, drain:float} power sources
var _energized := {}               # cell idx -> true: live generators + their connected wires
var _watered := {}                 # cell idx -> true: pipes carrying pool water
var _sprinklers := {}              # idx -> {} (placed; behavior derives from pipe + planters)
var _aquariums := {}               # idx -> {males,females,eggs,quality,water,feed,breed}
var _miners := {}                  # idx -> {t:float} renewable stone/ore producers
var _autoloaders := {}             # idx -> {t:float} adjacent turret gunpowder loaders
var _casings: Array = []           # [{pos}] spent ranged casings for manual dawn sweep
var _fish: Array = []              # [{pos:Vector2, sex:"m"|"f", t:float}] swimming in the pool
var _tool_equipped: String = ""    # "" / "stone_tool" / "metal_tool"
var _weapon_equipped: String = ""  # "" (fists) / "slingshot" / "mallet" / "spear"
var _gear_armor: float = 0.0       # bonus armor from crafted hide armor (capped)
var _energy: float = ENERGY_MAX
var _hydration: float = HYDRATION_MAX
var _health: float = HEALTH_MAX
var _lives: int = MAX_LIVES
var _seed: int = WORLD_SEED         # world seed (randomized on a fresh run)

# Progression
var _level: int = 1
var _xp: int = 0
var _xp_to_next: int = 5
var _nights_survived: int = 0
var _best_nights: int = 0           # best across all runs (persisted to disk)

# Player-directed stat allocation: each level grants one point to spend.
var _stat_points: int = 0           # unspent points (queues if you level mid-fight)
var _active_overlay: int = Overlay.NONE
var _alloc := {"health": 0, "attack": 0, "speed": 0, "armor": 0, "regen": 0}
const STAT_ORDER: Array = ["health", "attack", "speed", "armor", "regen"]

const SAVE_PATH := "user://goliradile_isle.save"

# Derived player stats (recomputed from _level)
var _p_max_health: float = HEALTH_MAX
var _p_attack: float = PLAYER_DMG
var _p_speed: float = PLAYER_SPEED
var _p_armor: float = 0.0
var _p_regen: float = HEALTH_REGEN
var _time: float = FP_DAY_START
var _day: int = 1
var _banana_timer: float = 0.0
var _msg: String = ""               # transient banner (death / game over)
var _msg_timer: float = 0.0
var _msg_onboard: bool = false      # current banner is a blue onboarding beat (2-line, tinted)
var _msg_queue: Array = []          # pending onboard beats: [{text, secs}] drained as _msg_timer hits 0

# Onboarding + TECH-hub discovery state (all persisted additively in the save dict).
var _onboard_seen := {}             # beat id -> true; one-shot, cleared by _reset_game
var _tech_new_until: float = 0.0    # NEW marker live until this world-time (set on tier-up)
var _tech_seen_tier: int = 1        # highest tier the player has acknowledged in the TECH hub

var _storage := {}
var _docked_station: int = -1       # one clicked adjacent station/card target (-1 = none)
var _turret_pick_cat: String = ""   # two-step turret picker: chosen category, no type yet
var _util_refresh_t: float = 0.0    # coarse timer to refresh an open utility panel
var _workspace_dirty: bool = false
var _workspace_refresh_queued: bool = false

var _build_mode: bool = false
var _build_struct: String = ""
var _dragging: bool = false
var _drag_action: int = BuildAction.NONE
var _last_applied_cell: Vector2i = Vector2i(-9999, -9999)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_near_bench: bool = false

# Mother Tree / downed-player objective loop
var _tree_tier: int = 1
var _tree_hp: float = 120.0
var _downed: bool = false
var _downed_timer: float = 0.0
var _dens := {}                     # origin idx -> {origin, size, hp, max_hp, maturity}
var _won: bool = false

# Night / combat
var _is_night: bool = false
var _dusk_telegraphed: bool = false
var _incoming_telegraphed: bool = false
var _field_tree: PackedFloat32Array = PackedFloat32Array()
var _field_player: PackedFloat32Array = PackedFloat32Array()
# Sapper tunnel field: a tree-rooted flow that IGNORES wall break-cost, so a
# burrowed digger routes straight under a sealed perimeter to the Tree.
var _field_sapper: PackedFloat32Array = PackedFloat32Array()
var _field_tree_dirty: bool = true
var _field_player_timer: float = 0.0
var _field_player_cell: Vector2i = Vector2i(-9999, -9999)
var _monsters: Array = []          # [{pos, hp, type, role, ...}, ...]
var _projectiles: Array = []       # [{pos, vel, kind, dmg}, ...] kind = "fire"|"snow"
var _poison_clouds: Array = []     # [{pos, t}] purple lingering smoke
var _night_snapshot := {}          # idx -> {t:int, apple:int}
var _struct_hp := {}               # idx -> current break hp (only if damaged)
var _wrecks := {}                  # idx -> {terrain:int, key:String, hp:int} repairable breach footprint
var _turrets := {}                 # home cell idx -> turret object dict
var _trap_cd := {}                 # idx -> seconds until a spike trap re-arms (0 = armed)
var _traps := {}                   # idx -> {type, hp, ammo, cd} for mine/peel/fence
var _peels: Array = []             # [{pos, t}] dropped banana peels (stun on contact)

# Juice: one heterogeneous transient-effects list, keyed by "kind" (§ juice brief).
# Each entry advances its own t by delta/life and is culled at t>=1; rendered in
# _draw_fx at the end of _draw so bursts/numbers sit on top of entities.
var _fx: Array = []                # [{kind, pos, t, life, ...}, ...]
# Dusk->night telegraph (persistent, animates continuously across the window).
var _dusk_active: bool = false     # true across the dusk warning window [0.68, 0.78)
var _dusk_phase: float = 0.0       # 0->1 across that window = (_time-0.68)/0.10
var _clock_flash: float = 0.0      # decaying pulse, re-kicked at the count-in beats
var _tier_glow: float = 0.0        # transient canvas brighten on a tier-up (dawn wash)
var _clock_last_beat: int = -1     # last whole-second the countdown pinged a flash

# Player status effects (set by croc projectiles)
var _burn_t: float = 0.0           # remaining burn (DoT) time
var _slow_t: float = 0.0           # remaining snowball slow time
var _freeze_t: float = 0.0         # remaining frozen-in-place time
var _snow_count: int = 0           # snowball hits inside the current rolling window
var _snow_window: float = 0.0      # time left in that window (resets count at 0)

var _camera: Camera2D
var _canvas_mod: CanvasModulate
var _fx_font: Font                 # ThemeDB.fallback_font (procedural, zero-asset) for combat text
var _clock_ctrl: Control           # screen-space radial "NIGHT IN m:ss" countdown clock

# Baked pixel-art textures
var _tiles := {}                  # Terrain -> ImageTexture
var _item_icons := {}             # item id -> crude ImageTexture placeholder
var _ui_theme: Theme
var _tex_gorilla: ImageTexture
var _tex_croc_r: ImageTexture
var _tex_croc_l: ImageTexture
var _tex_croc_flash_r: ImageTexture
var _tex_croc_flash_l: ImageTexture
var _tex_gorilla_flash: ImageTexture
var _tex_banana: ImageTexture
var _tex_coconut: ImageTexture    # overlay for a palm bearing coconuts
var _croc_tex := {}               # type -> {"r","l","fr","fl"} ImageTextures
# Den maturity overlays: drawn over the footprint, keyed off each _dens[id]'s
# size/maturity (the tile alone can't know its Den's stage). Young uses the
# base CROC_DEN tile; these escalate it warm -> hot as the Den matures.
var _tex_den_warm: ImageTexture    # maturing (2x2, ember flecks, "evolves tomorrow")
var _tex_den_evolved: ImageTexture # mature (3x3 cell, cracked earth, ember veins)

# FX overlays
var _fx_layer: CanvasLayer
var _flash_rect: ColorRect
var _vignette: TextureRect
# Full-screen TECH hub overlay (the Mother Tree's 3-column workbench). Lives on its
# own CanvasLayer above the side panels; rebuilt through the workspace dirty path.
var _tech_layer: CanvasLayer
var _tech_root: Control          # full-screen dim+frame; visible only while Overlay.TECH
var _tech_body: VBoxContainer    # cleared+repopulated each rebuild (title bar + columns)

# Victory banner (functional placeholder -- the polished screen is Editor 8/visual).
var _victory_layer: CanvasLayer
var _victory_label: Label
var _victory_stats: Label

# Hover tooltip (a single root frame, driven by _hover_kind/_hover_source).
var _tooltip_layer: CanvasLayer
var _tooltip_panel: PanelContainer
var _tt_icon: TextureRect
var _tt_name: Label
var _tt_sub: Label
var _tt_stat: Label
var _tt_cost: HBoxContainer
var _tt_desc: Label
var _hover_kind: String = ""        # the def id under the cursor ("" = nothing)
var _hover_source: String = ""      # one of item/recipe/struct/turret/croc/weapon
var _hover_dwell: float = 0.0       # seconds the current hover has been held
var _tooltip_shown: bool = false
const TOOLTIP_DWELL: float = 0.18
const TOOLTIP_W: float = 220.0

# UI node references
var _right_vbox: VBoxContainer
var _lbl_time: Label
var _lbl_threat: Label
var _lbl_nights: Label
var _lbl_level: Label
var _bar_xp: ProgressBar
var _lbl_xp: Label
var _lbl_stats: Label
var _life_pips: Array = []
var _bar_health: ProgressBar
var _lbl_health: Label
var _bar_energy: ProgressBar
var _lbl_energy: Label
var _bar_hydration: ProgressBar
var _lbl_hydration: Label
var _lbl_wood: Label
var _lbl_stone: Label
var _lbl_food: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel scaling
	_load_progress()
	_bake_sprites()
	_bake_item_icons()
	_generate_world()
	_init_progression()

	_player_pos = _cell_center_world(_cell)
	_invalidate_flow_fields()
	_ensure_flow_fields()

	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(_camera)
	_camera.make_current()
	_camera.position = _player_pos

	_canvas_mod = CanvasModulate.new()
	add_child(_canvas_mod)

	# Built-in procedural font (not an external asset) for combat text in _draw_fx.
	_fx_font = ThemeDB.fallback_font

	_build_ui()
	_build_tooltip()
	_build_tech_layer()
	_build_fx()
	_build_menu_layer()
	_apply_daylight()
	_update_status()
	_mark_workspace_dirty()
	_refresh_workspace()

	if "--pathing-probe" in OS.get_cmdline_user_args():
		_run_pathing_probe()
		return
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
		return
	_handle_shot_arg()

	# Normal launch (no headless test / screenshot args): open with the
	# "For William." card, then fade into the main menu.
	if not ("--shot" in OS.get_cmdline_user_args()):
		_enter_splash()


func _process(delta: float) -> void:
	# Title / menu / settings: gameplay is paused behind the overlay.
	if _app_state == AppState.SPLASH:
		_tick_splash(delta)
		return
	if _app_state != AppState.PLAYING:
		_hide_tooltip()
		return

	# The hover tooltip runs every frame (even behind overlays / hitstop / win), so
	# it always tracks the cursor and dwells correctly over the always-visible panels.
	_tick_tooltip(delta)

	# WIN: the run is over. Halt the whole sim (mirrors the game-over halt) and
	# hold the victory banner until the player dismisses it for a fresh run.
	if _won:
		queue_redraw()
		return

	# Full-screen overlays freeze the world until dismissed/spent.
	if _active_overlay == Overlay.LEVELUP or _active_overlay == Overlay.TECH:
		_update_status()
		return

	# Hit-stop: hold the world frozen for a few ms on impact so hits land harder.
	if _hitstop > 0.0:
		_hitstop = maxf(0.0, _hitstop - delta)
		queue_redraw()   # keep the frozen frame (with its hit-flash) on screen
		return

	_advance_time(delta)
	_tick_downed(delta)
	_decay_tick(delta)   # loose food spoils over time, day or night

	# Continuous free movement (8-directional, WASD).
	var input := Vector2.ZERO
	if not _downed:
		if Input.is_physical_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): input.x += 1.0
		if Input.is_physical_key_pressed(KEY_W): input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S): input.y += 1.0
	if _freeze_t > 0.0:
		input = Vector2.ZERO   # snow-frozen: can't move (or punch)
	if input != Vector2.ZERO:
		input = input.normalized()
		_facing = _cardinal(input)
		var spd := _p_speed * (0.5 if _energy <= 0.0 else 1.0)  # sluggish when exhausted
		if _slow_t > 0.0:
			spd *= SLOW_FACTOR                                   # snowball chill
		_player_pos = _move_collide(_player_pos, input * spd * delta, PLAYER_RADIUS, false)
		_energy = maxf(0.0, _energy - ENERGY_MOVE * delta)
		_cell = _world_to_cell(_player_pos)

	# Knockback (decays each frame).
	if _player_kb.length() > 1.0:
		_player_pos = _move_collide(_player_pos, _player_kb * delta, PLAYER_RADIUS, false)
		_player_kb = _player_kb.move_toward(Vector2.ZERO, KB_DECAY * delta)
		_cell = _world_to_cell(_player_pos)

	_camera.position = _player_pos

	if not _downed:
		_collect_ground_items(delta)   # auto-vacuum nearby loot, day or night

	if _is_night:
		_monster_update(delta)
		_turret_update(delta)
		_trap_update(delta)
		_update_projectiles(delta)
		_update_poison_clouds(delta)
		_update_status_effects(delta)
		_update_punch(delta)
	else:
		_world_tick(delta)

	_utility_tick(delta)   # barrels ferment, juicers press, planters grow (always)

	if _docked_station >= 0 and _chebyshev(_cell, _index_cell(_docked_station)) > 1:
		_clear_docked_station()

	if _build_mode:
		var near := _near_workbench()
		if near != _last_near_bench:
			_last_near_bench = near
			_mark_workspace_dirty()

	var hc := _mouse_cell()
	if hc != _hover_cell:
		_hover_cell = hc
		queue_redraw()
	if not _is_night and _near_iron_vein():
		_onboard("first_vein", "Iron veins mine themselves -- place an Auto-Miner on one. Power it (Tree aura) to double output.", 7.0)

	_update_juice(delta)

	# Things move continuously now, so redraw while anything is animating.
	if input != Vector2.ZERO or _player_kb.length() > 1.0 or _punch_active \
			or not _monsters.is_empty() or not _poofs.is_empty() or _spark_t < 1.0 or _shake > 0.0 \
			or not _projectiles.is_empty() or not _poison_clouds.is_empty() \
			or not _ground_items.is_empty() or not _fish.is_empty() or not _peels.is_empty() \
			or _burn_t > 0.0 or _freeze_t > 0.0 or _slow_t > 0.0 \
			or not _fx.is_empty() or _dusk_active or _tier_glow > 0.0 or _clock_flash > 0.0:
		queue_redraw()

	_update_status()


# Drive the hover tooltip each frame: when the cursor is over the board (not a
# panel), read the croc/structure under it; otherwise the panel widgets own the
# hover via _wire_hover. Once a hover has been held TOOLTIP_DWELL, show the frame
# and keep it pinned to the cursor.
func _tick_tooltip(delta: float) -> void:
	if not _tooltip_panel:
		return
	# Board hover only matters when the mouse is over the play area (not a panel) and
	# no full-screen overlay is up. Panel-widget hovers are wired directly.
	if _mouse_in_board() and _active_overlay == Overlay.NONE:
		var bk := _board_hover_target()
		_hover_set(bk[0], bk[1])
	if _hover_kind == "":
		if _tooltip_shown:
			_hide_tooltip()
		return
	if not _tooltip_shown:
		_hover_dwell += delta
		if _hover_dwell >= TOOLTIP_DWELL:
			_show_tooltip(_hover_kind, _hover_source)
	else:
		_position_tooltip()


# What's under the cursor on the board: a croc (by type) or an adjacent structure.
# Returns ["", ""] for empty grass so the frame clears. Crocs win over terrain.
func _board_hover_target() -> Array:
	var w := get_global_mouse_position()
	# Croc under the cursor (within ~half a cell): show its role telegraph.
	for m in _monsters:
		if float(m["hp"]) <= 0.0 and not (m.get("role", "") == "reviver"):
			continue
		if (m["pos"] as Vector2).distance_to(w) <= CELL_SIZE * 0.45:
			return [String(m["type"]), "croc"]
	var hc := _mouse_cell()
	if not _in_bounds(hc):
		return ["", ""]
	# Structures map back to a STRUCTURES key (so the desc/cost reads from the def).
	var key := _structure_key_for_terrain(_terrain_at(hc))
	if key != "" and STRUCTURES.has(key):
		return [key, "struct"]
	var t := _terrain_at(hc)
	if t == Terrain.MOTHER_TREE and _chebyshev(_cell, hc) <= 1:
		return ["mother_tree_hub", "special"]
	if t == Terrain.GRASS and _chebyshev(_cell, hc) <= 1:
		return ["bare_grass", "special"]
	return ["", ""]


# -----------------------------------------------------------------------------
# Time, daylight, health, growth, day/night transitions
# -----------------------------------------------------------------------------
func _advance_time(delta: float) -> void:
	_time += delta / DAY_LENGTH
	while _time >= 1.0:
		_time -= 1.0
		_day += 1
	_apply_daylight()
	_update_dusk_telegraph()

	# Day/night edge detection.
	var dark := _daylight(_time) <= 0.0
	if dark and not _is_night:
		_begin_night()
	elif not dark and _is_night:
		# Reaching dawn alive counts as a survived night.
		_nights_survived += 1
		if _nights_survived > _best_nights:
			_best_nights = _nights_survived
			_save_progress()
		_begin_day()

	var drain := ENERGY_DRAIN + (1.0 - _daylight(_time)) * ENERGY_NIGHT_EXTRA
	_energy = maxf(0.0, _energy - drain * delta)
	_hydration = maxf(0.0, _hydration - HYDRATION_DRAIN * delta)
	if _energy < ENERGY_MAX * 0.5:
		_onboard("first_hunger", "Low energy. Press E to eat a banana or berry -- starving drains your health.", 5.0)
	if _hydration < HYDRATION_MAX * 0.5:
		_onboard("first_thirst", "You're getting thirsty. Press Q to drink water. Walk to the shore or a barrel to refill cups.", 5.0)

	if _energy <= 0.0:
		_health = maxf(0.0, _health - HEALTH_DRAIN * delta)   # starving
		if _health <= 0.0:
			_on_death()
	if _hydration <= 0.0:
		_health = maxf(0.0, _health - HYDRATION_HEALTH_DRAIN * delta)  # parched
		if _health <= 0.0:
			_on_death()
	if _energy >= HEALTH_REGEN_ENERGY and _hydration > 0.0 and _health > 0.0:
		_health = minf(_p_max_health, _health + _p_regen * delta)

	if _msg_timer > 0.0:
		_msg_timer = maxf(0.0, _msg_timer - delta)
	# Drain a queued onboarding beat the instant the banner frees up, so a tutorial
	# line queued behind a threat/SFX message still lands.
	if _msg_timer <= 0.0 and not _msg_queue.is_empty():
		var beat: Dictionary = _msg_queue.pop_front()
		_set_msg_long(String(beat["text"]), float(beat["secs"]))


func _update_dusk_telegraph() -> void:
	if _time >= 0.68 and _time < 0.78:
		if not _dusk_telegraphed:
			_dusk_telegraphed = true
			_fx_dusk_enter()
			play_sfx("dusk")
			# Keystone beat: the dusk before the first siege. Queued so the dusk SFX/
			# threat line the same frame doesn't eat it.
			if _day == 2 and not _is_night:
				_onboard("day2_dusk", "The crocs come tomorrow night. Build turrets around the Mother Tree tonight -- press B, then place them inside the green power aura so they fire for free.", 8.0)
		var secs_left := (0.78 - _time) * DAY_LENGTH
		if secs_left <= 10.0 and not _incoming_telegraphed:
			_incoming_telegraphed = true
			_fx_night_incoming()
			play_sfx("horde_incoming")
	else:
		_dusk_telegraphed = false
		_incoming_telegraphed = false


func _daylight(f: float) -> float:
	if f < 0.07 or f >= 0.78:
		return 0.0
	elif f < 0.12:
		return smoothstep(0.07, 0.12, f)
	elif f < 0.68:
		return 1.0
	else:
		return 1.0 - smoothstep(0.68, 0.78, f)


func _apply_daylight() -> void:
	if not _canvas_mod:
		return
	var base := NIGHT_COLOR.lerp(Color.WHITE, _daylight(_time))
	# Dusk: inject an amber sunset that swells mid-window then drains to night blue,
	# so the day->night ramp reads as a real sunset, not lights dimming (§8B).
	if _dusk_active:
		var warm := 1.0 - absf(_dusk_phase - 0.45) / 0.45   # 0->1->0, peaks ~mid-window
		base = base.lerp(FX_SUNSET, clampf(warm, 0.0, 1.0) * 0.5)
		base = base.lerp(NIGHT_COLOR, _dusk_phase * 0.35)   # progressively cool
	# Tier-up dawn wash: flare the canvas toward white for a beat even mid-day (§5).
	if _tier_glow > 0.0:
		base = base.lerp(Color(1.08, 1.06, 0.95), _tier_glow * 0.5)
	_canvas_mod.color = base


func _begin_night() -> void:
	_is_night = true
	# No building at night: force-exit build mode.
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_night_snapshot.clear()
	_ensure_flow_fields()
	_spawn_monsters(_monster_count_for_day())
	# Telegraph the wall: deep nights demand wired, generator-powered defenses.
	if _night_index() == POWER_DEMAND_NIGHT:
		_set_msg("The horde swells -- wine alone can't keep turrets firing. Wire them to a generator!")
	elif _night_index() > POWER_DEMAND_NIGHT:
		_set_msg("Night %d: power your turrets or they'll run dry." % _night_index())
	# First real siege: teach the hold-the-line loop (queued behind the POWER line).
	if _monster_count_for_day() > 0:
		_onboard("first_night", "First siege. Don't fight alone -- let your turrets hold the line. Punch crocs that break through (left-click toward them). Survive until dawn.", 7.0)
	_mark_workspace_dirty()
	queue_redraw()


func _begin_day() -> void:
	_is_night = false
	if _casings.size() > 0:
		_onboard("casings", "Spent rounds litter the field. Open the Tree panel and Sweep Casings each dawn to recover ammo.", 5.0)
	_night_snapshot.clear()
	_tree_dawn_regen()
	_advance_dens_day()
	_regrow_world()
	_monsters.clear()
	_projectiles.clear()
	_poison_clouds.clear()
	_clear_status_effects()
	_punch_active = false
	_player_kb = Vector2.ZERO
	_mark_workspace_dirty()
	queue_redraw()


func _world_tick(delta: float) -> void:
	_banana_timer += delta
	if _banana_timer < BANANA_TICK:
		return
	_banana_timer -= BANANA_TICK
	var changed := false
	var player_idx := _cell_index(_cell)
	for i in range(_terrain.size()):
		match _terrain[i]:
			Terrain.TREE:
				if _banana[i] == 0 and randf() < BANANA_GROW_CHANCE:
					_banana[i] = 1
					changed = true
			Terrain.STUMP:
				_growth[i] += BANANA_TICK
				if _growth[i] >= STUMP_TIME:
					_terrain[i] = Terrain.SAPLING
					_growth[i] = 0.0
					changed = true
			Terrain.SAPLING:
				_growth[i] += BANANA_TICK
				if _growth[i] >= SAPLING_TIME and i != player_idx:
					_terrain[i] = Terrain.TREE
					_growth[i] = 0.0
					changed = true
			Terrain.BUSH:
				if _berry[i] < BUSH_MAX_BERRIES and randf() < BERRY_GROW_CHANCE:
					_berry[i] += 1
					changed = true
	if changed:
		queue_redraw()


# -----------------------------------------------------------------------------
# Monsters
# -----------------------------------------------------------------------------
func _monster_count_for_day() -> int:
	var n := _night_index()
	if n <= 2:
		return 0
	if FP_WAVE_SIZES.has(n):
		return int(FP_WAVE_SIZES[n])
	return mini(MONSTER_CAP, 16 + (n - 6) * 6)


func _tree_aggro_fraction(night: int) -> float:
	if night >= 6:
		return float(FP_TREE_AGGRO_FRAC[6])
	return float(FP_TREE_AGGRO_FRAC.get(night, 0.0))


# Build a crocodile of `type` with stats scaled to night `n` (n = 1 on night one).
func _croc_for_night(pos: Vector2, n: int, type: String = "green") -> Dictionary:
	n = mini(n, LEVEL_CAP)        # crocs stop scaling past the global level cap
	var lv := maxi(0, n - 3)
	var def: Dictionary = CROC_DEFS[type]
	var hp: float = (MONSTER_HP + lv * MON_HP_GROW) * float(def["hp"])
	return {
		"pos": pos, "hp": hp, "max_hp": hp, "type": type, "role": def["role"],
		"attack": (MONSTER_HIT + lv * MON_ATK_GROW) * float(def["atk"]),
		"speed": CROC_SPEED * minf(MON_SPD_CAP, 1.0 + lv * MON_SPD_GROW) * float(def["spd"]),
		"armor": minf(MON_ARM_CAP, lv * MON_ARM_GROW),
		"regen": lv * MON_REGEN_GROW,
		# Tougher, later-night crocs are worth markedly more -- so a fresh turret
		# thrown into a deep night still climbs levels quickly off big kills.
		# (Scaled by the type's HP multiplier: beefier crocs pay out more.)
		"xp": int((MON_XP_BASE + lv * MON_XP_GROW) * float(def["hp"])),
		"atk_cd": 0.0, "brk_cd": 0.0, "shoot_cd": RANGED_CD, "kb": Vector2.ZERO, "flash": 0.0,
		"dig": def["role"] == "digger",   # brown starts burrowed (invulnerable)
		"revived": false, "dead_t": 0.0,  # black-croc revive bookkeeping
		"healing": false,                 # white-croc visual flag (allies in range this frame)
		"slow_t": 0.0,                    # trap-induced slow timer
		"stun_t": 0.0,                    # banana-peel stun (can't move)
		"marked": false,                  # trickster mark (+damage taken)
		"target": "tree" if String(def.get("aggro", "")) == "tree" else "player",
		"killer": "",                     # who landed the killing blow (turret idx or "player")
		"dmg_log": {},                    # owner -> seconds left to still count as an assist
		"debuff_by": {},                  # support turret idx -> seconds left to credit its debuff
	}


# Weighted pool of types unlocked by `night`.
func _unlocked_croc_pool(night: int) -> Array:
	var pool := []
	for t in CROC_DEFS:
		if night >= int(CROC_DEFS[t]["unlock"]):
			for _i in range(int(CROC_DEFS[t]["weight"])):
				pool.append(t)
	if pool.is_empty():
		pool.append("green")
	return pool


func _spawn_monsters(n: int) -> void:
	if n <= 0 or _dens.is_empty():
		return
	var night := _night_index()
	var pool := _unlocked_croc_pool(night)
	var tree_goal_count := int(round(float(n) * _tree_aggro_fraction(night)))
	var tree_assigned := 0
	# Crocs emerge from live Dens; if a Den shore is blocked, fallback uses far ground.
	var shore := _den_spawn_cells()
	shore.shuffle()
	var placed := 0
	for c in shore:
		if placed >= n:
			break
		if not _tile_monster_walk(_terrain_at(c)):
			continue
		var type: String = pool[randi() % pool.size()]
		var croc := _croc_for_night(_cell_center_world(c), night, type)
		if tree_assigned < tree_goal_count:
			croc["target"] = "tree"
			tree_assigned += 1
		_monsters.append(croc)
		_poofs.append({"pos": _cell_center_world(c), "t": 0.2})  # a splash as it surfaces
		placed += 1
	# If the pool can't seat them all, the rest wade in from random far ground.
	var attempts := 0
	while placed < n and attempts < 3000:
		attempts += 1
		var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
		if not _tile_monster_walk(_terrain_at(c)) or _chebyshev(c, _cell) < SPAWN_MIN_DIST:
			continue
		var type: String = pool[randi() % pool.size()]
		var croc := _croc_for_night(_cell_center_world(c), night, type)
		if tree_assigned < tree_goal_count:
			croc["target"] = "tree"
			tree_assigned += 1
		_monsters.append(croc)
		placed += 1


func _invalidate_flow_fields() -> void:
	_field_tree_dirty = true
	_field_player_timer = FLOW_PLAYER_INTERVAL
	_field_player_cell = Vector2i(-9999, -9999)


func _ensure_flow_fields() -> void:
	if _field_tree_dirty or _field_tree.size() != GRID_CELLS * GRID_CELLS:
		_recompute_tree_field()
	if _field_player.size() != GRID_CELLS * GRID_CELLS:
		_recompute_player_field(true)


func _tick_flow_fields(delta: float) -> void:
	if _field_tree_dirty or _field_tree.size() != GRID_CELLS * GRID_CELLS:
		_recompute_tree_field()
	_field_player_timer += delta
	var pc := _world_to_cell(_player_pos)
	if _field_player.size() != GRID_CELLS * GRID_CELLS \
			or pc != _field_player_cell \
			or _field_player_timer >= FLOW_PLAYER_INTERVAL:
		_recompute_player_field(true)


func _flow_tree_goals() -> Array:
	return _tree_cells()


func _recompute_tree_field() -> void:
	_field_tree = _recompute_flow_field(_flow_tree_goals())
	# The sapper's tunnel field shares the Tree goal but treats walls as cheap
	# dirt (ignore_break) -- this is the path that crosses a sealed wall ring.
	_field_sapper = _recompute_flow_field(_flow_tree_goals(), true)
	_field_tree_dirty = false


func _recompute_player_field(_force: bool = false) -> void:
	_field_player_cell = _world_to_cell(_player_pos)
	_field_player = _recompute_flow_field([_field_player_cell])
	_field_player_timer = 0.0


func _flow_step_cost(c: Vector2i, ignore_break: bool = false) -> int:
	if not _in_bounds(c):
		return FIELD_BLOCKED
	var t := _terrain_at(c)
	if _tile_monster_walk(t):
		return 1
	if _tile_impassable(t):
		return FIELD_BLOCKED
	var hp := _tile_break_hp(t)
	if hp > 0:
		if ignore_break:
			return 1
		return maxi(2, hp + _tile_armor(t) * 8)
	return FIELD_BLOCKED


func _recompute_flow_field(goals: Array, ignore_break: bool = false) -> PackedFloat32Array:
	var total := GRID_CELLS * GRID_CELLS
	var field := PackedFloat32Array()
	field.resize(total)
	for i in range(total):
		field[i] = FIELD_INF

	var buckets := {}
	var queued := 0
	for g in goals:
		var c: Vector2i = g
		if not _in_bounds(c):
			continue
		var idx := _cell_index(c)
		field[idx] = 0.0
		if not buckets.has(0):
			buckets[0] = []
		buckets[0].append(idx)
		queued += 1

	var current := 0
	var offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queued > 0 and current < FIELD_BLOCKED:
		var bucket: Array = buckets.get(current, [])
		if bucket.is_empty():
			current += 1
			continue
		var idx: int = bucket.pop_back()
		queued -= 1
		if int(field[idx]) != current:
			continue
		var c := _index_cell(idx)
		for off in offsets:
			var n: Vector2i = c + off
			if not _in_bounds(n):
				continue
			var step := _flow_step_cost(n, ignore_break)
			if step >= FIELD_BLOCKED:
				continue
			var nd := current + step
			var ni := _cell_index(n)
			if float(nd) < field[ni]:
				field[ni] = float(nd)
				if not buckets.has(nd):
					buckets[nd] = []
				buckets[nd].append(ni)
				queued += 1
	return field


func _flow_dir_from_cell(field: PackedFloat32Array, cell: Vector2i) -> Vector2:
	if field.size() != GRID_CELLS * GRID_CELLS or not _in_bounds(cell):
		return Vector2.ZERO
	var idx := _cell_index(cell)
	var here := field[idx]
	if here >= FIELD_INF * 0.5:
		return Vector2.ZERO
	var best := here
	var best_dir := Vector2.ZERO
	var offsets := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for off in offsets:
		var n: Vector2i = cell + off
		if not _in_bounds(n):
			continue
		if off.x != 0 and off.y != 0:
			var a := cell + Vector2i(off.x, 0)
			var b := cell + Vector2i(0, off.y)
			if not _in_bounds(a) or not _in_bounds(b) \
					or not _tile_monster_walk(_terrain_at(a)) \
					or not _tile_monster_walk(_terrain_at(b)):
				continue
		var nd := field[_cell_index(n)]
		if nd < best:
			best = nd
			best_dir = Vector2(off)
	return best_dir.normalized() if best_dir != Vector2.ZERO else Vector2.ZERO


func _flow_dir_from_pos(field: PackedFloat32Array, pos: Vector2, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var d := _flow_dir_from_cell(field, _world_to_cell(pos))
	if d != Vector2.ZERO:
		return d
	return fallback.normalized() if fallback.length() > 0.01 else Vector2.ZERO


func _monster_separation(pos: Vector2) -> Vector2:
	var steer := Vector2.ZERO
	for other in _monsters:
		var op: Vector2 = other["pos"]
		var away := pos - op
		var dist := away.length()
		if dist <= 0.01 or dist >= CELL_SIZE * 0.85:
			continue
		steer += away.normalized() * (1.0 - dist / (CELL_SIZE * 0.85))
	return steer.normalized() if steer.length() > 0.01 else Vector2.ZERO


# Sprinkle fresh resources onto empty grass each dawn (never onto water, the
# player, or any built structure/turret -- those tiles simply aren't grass).
func _regrow_world() -> void:
	var kinds := []
	for _i in range(REGROW_TREES): kinds.append(Terrain.TREE)
	for _i in range(REGROW_STONE): kinds.append(Terrain.STONE)
	for _i in range(REGROW_BUSHES): kinds.append(Terrain.BUSH)
	for _i in range(REGROW_COCONUTS): kinds.append(Terrain.COCONUT)
	for _i in range(REGROW_BAMBOO): kinds.append(Terrain.BAMBOO)
	for _i in range(REGROW_HIVES): kinds.append(Terrain.HIVE)
	for t in kinds:
		var attempts := 0
		while attempts < 60:
			attempts += 1
			var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
			if _terrain_at(c) != Terrain.GRASS or c == _cell:
				continue
			_set_terrain(c, t)
			if t == Terrain.TREE or t == Terrain.COCONUT:
				_banana[_cell_index(c)] = 1
			elif t == Terrain.BUSH:
				_berry[_cell_index(c)] = 1
			break
	_spawn_fish_daily()    # the pool restocks with 1-4 fish each morning
	_spawn_hive_bees()     # wild hives may loose a bee to catch
	# A glapple -- the rare glowing blue apple -- sometimes turns up at dawn.
	if randf() < GLAPPLE_DAWN_CHANCE:
		var gattempts := 0
		while gattempts < 40:
			gattempts += 1
			var gc := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
			if _terrain_at(gc) == Terrain.GRASS and gc != _cell:
				_spawn_loot("glapple", 1, _cell_center_world(gc))
				break


func _monster_update(delta: float) -> void:
	_tick_flow_fields(delta)
	_apply_heal_auras(delta)   # white crocs mend nearby allies (and flag them)

	for m in _monsters:
		m["flash"] = maxf(0.0, m["flash"] - delta)

		# Down but not out: black crocs lie dead, counting to their single revive.
		if m["hp"] <= 0.0:
			if m["role"] == "reviver" and not m["revived"]:
				m["dead_t"] += delta
				if m["dead_t"] >= REVIVE_TIME:
					m["revived"] = true
					m["hp"] = m["max_hp"]
					m["dead_t"] = 0.0
					m["flash"] = FLASH_TIME
					_add_shake(3.0)
			continue

		m["atk_cd"] = maxf(0.0, m["atk_cd"] - delta)
		m["brk_cd"] = maxf(0.0, m["brk_cd"] - delta)
		m["shoot_cd"] = maxf(0.0, m["shoot_cd"] - delta)
		m["slow_t"] = maxf(0.0, m["slow_t"] - delta)   # trap chill wears off
		_tick_credit_windows(m, delta)                 # expire stale assist/debuff credit
		m["hp"] = minf(m["max_hp"], m["hp"] + m["regen"] * delta)  # regeneration

		# Slipped on a banana peel: frozen in place until the stun wears off.
		if float(m.get("stun_t", 0.0)) > 0.0:
			m["stun_t"] = maxf(0.0, float(m["stun_t"]) - delta)
			continue

		var role: String = m["role"]

		# Knockback overrides chasing while strong (burrowed diggers ignore it).
		var kb: Vector2 = m["kb"]
		if not m["dig"] and kb.length() > 8.0:
			m["pos"] = _move_collide(m["pos"], kb * delta, MONSTER_RADIUS, true)
			m["kb"] = kb.move_toward(Vector2.ZERO, KB_DECAY * delta)
			continue
		m["kb"] = kb.move_toward(Vector2.ZERO, KB_DECAY * delta)

		var target_tree := String(m.get("target", "player")) == "tree"
		var target_pos := _cell_center_world(_nearest_tree_cell_to(m["pos"])) if target_tree else _player_pos
		var to: Vector2 = target_pos - m["pos"]
		var dist: float = to.length()
		var dir: Vector2 = to / dist if dist > 0.01 else Vector2.RIGHT
		var chase_field := _field_tree if target_tree else _field_player
		var chase_dir := _flow_dir_from_pos(chase_field, m["pos"], dir)
		var sep := _monster_separation(m["pos"])
		if sep != Vector2.ZERO and not m["dig"]:
			chase_dir = (chase_dir + sep * 0.35).normalized()

		# Sapper: a tree-aggro digger gets its dedicated tunnel logic FIRST, so the
		# generic tree-seek branch below never swallows it. While burrowed it follows
		# the ignore-walls sapper field straight under the perimeter to the Tree.
		if role == "digger":
			_update_digger(m, delta, dir, dist, target_pos)
			continue

		if target_tree:
			if dist <= ATTACK_RANGE + CELL_SIZE * 0.35:
				if float(m["attack"]) > 0.0 and m["atk_cd"] <= 0.0:
					_damage_tree(float(m["attack"]))
					m["atk_cd"] = MONSTER_ATK_INTERVAL
				continue
			_move_monster_toward(m, chase_dir, delta, m["speed"])
			continue

		match role:
			"healer":
				# Support unit: never attacks; trails the pack, keeping its distance.
				if dist > CELL_SIZE * 3.5:
					_move_monster_toward(m, chase_dir, delta, m["speed"] * 0.85)
				continue
			"wrecker":
				_update_wrecker(m, delta, dir)
				continue
			"poison":
				if dist <= PURPLE_RANGE:
					if m["atk_cd"] <= 0.0:
						_poison_clouds.append({"pos": _player_pos, "t": 0.0})
						m["atk_cd"] = PURPLE_CD
					continue
			"fire", "ice":
				if dist <= RANGED_RANGE and dist > ATTACK_RANGE and _has_los(m["pos"], _player_pos):
					if m["shoot_cd"] <= 0.0:
						_fire_projectile(m["pos"], "fire" if role == "fire" else "snow")
						m["shoot_cd"] = RANGED_CD
					continue   # hold the line and keep firing instead of closing in

		# Default melee chase (green, yellow, red/blue up close, surfaced brown, black).
		if dist <= ATTACK_RANGE:
			if m["attack"] > 0.0 and m["atk_cd"] <= 0.0:
				_damage_player(m["attack"], m["pos"])
				m["atk_cd"] = MONSTER_ATK_INTERVAL
			continue
		_move_monster_toward(m, chase_dir, delta, m["speed"])

	# Remove dead -- but keep black crocs still owing a revive (no XP on first kill).
	var alive := []
	for m in _monsters:
		if m["hp"] > 0.0 or (m["role"] == "reviver" and not m["revived"]):
			alive.append(m)
		else:
			_award_kill_xp(m)
			# A slain croc leaves a bone, and often its hide -- auto-collected loot.
			_spawn_loot("bone", 1, m["pos"])
			if randf() < 0.55:
				_spawn_loot("croc_hide", 1, m["pos"])
			if randf() < 0.40:
				_spawn_loot("scrap", 1, m["pos"])
			_poofs.append({"pos": m["pos"], "t": 0.0})
			_fx_croc_death(m["pos"])
			play_sfx("croc_death")
			_add_shake(2.0)
	_monsters = alive


# Count down the assist/debuff credit timers, dropping any that have lapsed so
# only hits/debuffs from the last few seconds can claim XP on a kill.
func _tick_credit_windows(m: Dictionary, delta: float) -> void:
	var log: Dictionary = m["dmg_log"]
	for k in log.keys():
		log[k] = float(log[k]) - delta
		if float(log[k]) <= 0.0:
			log.erase(k)
	var deb: Dictionary = m["debuff_by"]
	for k in deb.keys():
		deb[k] = float(deb[k]) - delta
		if float(deb[k]) <= 0.0:
			deb.erase(k)


# Hand out XP for a downed croc. A turret keeps what it earns (no shared pool):
# the killer gets the full bounty, recent direct-damage assisters get half, and
# support turrets are paid for the debuffs they had live on the croc -- full XP
# for adhesive/trickster (they can't kill), a consistent slice for mending engineers.
func _award_kill_xp(m: Dictionary) -> void:
	var xp: int = int(m["xp"])
	var killer = m.get("killer", "")
	var paid := {}   # owners already paid this kill, so nobody double-dips
	# 1) The killing blow earns the full bounty.
	if killer is int and _turrets.has(killer):
		_turret_gain_xp(_turrets[killer], xp)
		paid[killer] = true
	elif killer == "player" or killer == "":
		_gain_xp(xp)
	# 2) Direct-damage turrets that hit within the window get a half-XP assist.
	var log: Dictionary = m["dmg_log"]
	for owner in log:
		if owner is int and _turrets.has(owner) and not paid.has(owner):
			var ty: String = _turrets[owner]["type"]
			if ty == "adhesive" or ty == "trickster" or ty == "engineer":
				continue   # support turrets are credited via their debuffs instead
			_turret_gain_xp(_turrets[owner], maxi(1, int(round(xp * TURRET_ASSIST_FRAC))))
			paid[owner] = true
	# 3) Adhesive / trickster turrets debuffing the croc claim full XP.
	var deb: Dictionary = m["debuff_by"]
	for owner in deb:
		if owner is int and _turrets.has(owner) and not paid.has(owner):
			var ty2: String = _turrets[owner]["type"]
			if ty2 == "adhesive" or ty2 == "trickster":
				_turret_gain_xp(_turrets[owner], xp)
				paid[owner] = true
	# 4) Engineers bank a consistent slice of every croc downed while they mend.
	for eidx in _turrets:
		var e: Dictionary = _turrets[eidx]
		if e["type"] == "engineer" and float(e["heal_t"]) > 0.0 and not paid.has(eidx):
			_turret_gain_xp(e, maxi(1, int(round(xp * TURRET_ENGINEER_XP_FRAC))))


# Move a monster toward `dir`; if blocked by a structure, chew through it.
func _move_monster_toward(m: Dictionary, dir: Vector2, delta: float, speed: float) -> void:
	if dir.length() <= 0.01:
		return
	dir = dir.normalized()
	if m["slow_t"] > 0.0:
		speed *= 0.5   # slowed by a spike trap / rocket
	speed *= _adhesive_factor(m["pos"])   # adhesive support-turret slow field
	var motion: Vector2 = dir * speed * delta
	var before: Vector2 = m["pos"]
	m["pos"] = _move_collide(before, motion, MONSTER_RADIUS, true)
	if (m["pos"] as Vector2).distance_to(before) < motion.length() * 0.5 and m["brk_cd"] <= 0.0:
		var probe: Vector2 = before + dir * (MONSTER_RADIUS + CELL_SIZE * 0.5)
		var c := _world_to_cell(probe)
		if _in_bounds(c) and _tile_break_hp(_terrain_at(c)) > 0:
			_fx_wall_hit(c)
			play_sfx("wall_hit")
			_damage_structure(c)
			m["brk_cd"] = MONSTER_BRK_INTERVAL
			return
		var perp := Vector2(-dir.y, dir.x)
		var best_pos: Vector2 = m["pos"]
		var best_gain := best_pos.distance_to(before)
		for retry_dir in [(dir + perp).normalized(), (dir - perp).normalized()]:
			var retry_pos := _move_collide(before, retry_dir * speed * delta, MONSTER_RADIUS, true)
			var gain := retry_pos.distance_to(before)
			if gain > best_gain:
				best_gain = gain
				best_pos = retry_pos
		m["pos"] = best_pos


# White croc: heal living allies inside the aura and flag them for the FX.
func _apply_heal_auras(delta: float) -> void:
	for m in _monsters:
		m["healing"] = false
	for i in range(_monsters.size()):
		var h: Dictionary = _monsters[i]
		if h["role"] != "healer" or h["hp"] <= 0.0 or h["dig"]:
			continue
		for j in range(_monsters.size()):
			if j == i:
				continue
			var m: Dictionary = _monsters[j]
			if m["hp"] <= 0.0:
				continue
			if (h["pos"] as Vector2).distance_to(m["pos"]) <= HEAL_RADIUS:
				m["hp"] = minf(m["max_hp"], m["hp"] + HEAL_DPS * delta)
				m["healing"] = true


# Brown SAPPER (decision #15): the anti-turtle counter. While burrowed it is
# invulnerable and follows the ignore-walls sapper field straight under the
# perimeter -- so it crosses a fully sealed wall ring -- then surfaces INSIDE
# the ring, right next to the Mother Tree (telegraphed), and chews the Tree.
# `dir`/`dist`/`target_pos` are already aimed at the nearest Tree cell.
func _update_digger(m: Dictionary, delta: float, dir: Vector2, dist: float, target_pos: Vector2) -> void:
	if m["dig"]:
		# Tunnel along the ignore-break tree field; fall back to the straight
		# dir so it never stalls if the field has no gradient at this cell.
		var tunnel_dir := _flow_dir_from_pos(_field_sapper, m["pos"], dir)
		# Surface only once the sapper's cell is ADJACENT to the Tree footprint --
		# i.e. it has burrowed all the way past the wall ring to the trunk. Using
		# Tree-cell adjacency (not a raw radius) guarantees it erupts INSIDE the
		# ring, never on the wall it just tunneled under.
		var here := _world_to_cell(m["pos"])
		var at_tree := false
		for tcell in _tree_cells():
			if _chebyshev(here, tcell) <= 1:
				at_tree = true
				break
		if at_tree:
			m["dig"] = false          # erupt next to the Tree, inside the wall ring
			m["atk_cd"] = MONSTER_ATK_INTERVAL * 0.5
			_poofs.append({"pos": m["pos"], "t": 0.0})  # telegraph the breach
			play_sfx("wall_hit")
			_add_shake(5.0)
			return
		var nxt: Vector2 = (m["pos"] as Vector2) + tunnel_dir * float(m["speed"]) * delta
		# Burrowed: walls are dirt -- move freely, ignoring structure collision.
		if _in_bounds(_world_to_cell(nxt)):
			m["pos"] = nxt
		return
	# Surfaced inside the ring -> chew the Tree.
	if dist <= ATTACK_RANGE + CELL_SIZE * 0.35:
		if float(m["attack"]) > 0.0 and m["atk_cd"] <= 0.0:
			_damage_tree(float(m["attack"]))
			m["atk_cd"] = MONSTER_ATK_INTERVAL
		return
	var chase_dir := _flow_dir_from_pos(_field_tree, m["pos"], dir)
	_move_monster_toward(m, chase_dir, delta, m["speed"])


# Pink croc: makes a beeline for the nearest player structure and wrecks it
# (extra damage) before ever bothering with the player.
func _update_wrecker(m: Dictionary, delta: float, dir_to_player: Vector2) -> void:
	var target := _nearest_structure_cell(m["pos"])
	var goal: Vector2
	if target == Vector2i(-1, -1):
		goal = _player_pos          # nothing left to wreck -> go for the player
	else:
		goal = _cell_center_world(target)
	var to: Vector2 = goal - m["pos"]
	var d: float = to.length()
	var dir: Vector2 = to / d if d > 0.01 else dir_to_player
	if target != Vector2i(-1, -1) and d <= ATTACK_RANGE + CELL_SIZE * 0.4:
		if m["brk_cd"] <= 0.0:
			for _i in range(PINK_STRUCT_MUL):
				if _in_bounds(target) and _tile_break_hp(_terrain_at(target)) > 0:
					_fx_wall_hit(target)
					play_sfx("wall_hit")
					_damage_structure(target)
			m["brk_cd"] = MONSTER_BRK_INTERVAL
		return
	if target == Vector2i(-1, -1) and d <= ATTACK_RANGE:
		if m["atk_cd"] <= 0.0:
			_damage_player(m["attack"], m["pos"])
			m["atk_cd"] = MONSTER_ATK_INTERVAL
		return
	_move_monster_toward(m, dir, delta, m["speed"])


func _nearest_structure_cell(from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for idx in _struct_cells():
		var c := _index_cell(idx)
		var d := from.distance_to(_cell_center_world(c))
		if d < best_d:
			best_d = d
			best = c
	return best


# Indices of all standing player structures (anything with break HP).
func _struct_cells() -> Array:
	var out := []
	for i in range(_terrain.size()):
		if _tile_break_hp(_terrain[i]) > 0:
			out.append(i)
	return out


func _update_poison_clouds(delta: float) -> void:
	var keep := []
	for cl in _poison_clouds:
		cl["t"] += delta
		if cl["t"] < POISON_TIME:
			keep.append(cl)
	_poison_clouds = keep


func _monster_at(c: Vector2i) -> int:
	for i in range(_monsters.size()):
		if _world_to_cell(_monsters[i]["pos"]) == c:
			return i
	return -1


func _damage_structure(c: Vector2i, amount: float = 1.0) -> void:
	var idx := _cell_index(c)
	var t := _terrain_at(c)
	if t == Terrain.MOTHER_TREE:
		_damage_tree(amount)
		return
	if t == Terrain.CROC_DEN:
		_damage_den_at(c, amount)
		return
	var maxhp: int = _tile_break_hp(t)
	if maxhp <= 0:
		return
	# Turrets don't get demolished -- they take object HP and "break" in place.
	if t == Terrain.TURRET and _turrets.has(idx):
		_turret_take_damage(_turrets[idx], maxf(1.0, amount - float(_tile_armor(t))))
		queue_redraw()
		return
	var dealt: int = maxi(1, int(round(amount - float(_tile_armor(t)))))
	# Grey "blocked" number: the wall ate this hit (reads as armor absorbing damage).
	# Only while the structure survives -- a final demolishing blow has no wall to credit.
	if _is_night and int(_struct_hp.get(idx, maxhp)) - dealt > 0:
		_fx_damage_number(_cell_center_world(c), float(dealt), "blocked")
	var hp: int = int(_struct_hp.get(idx, maxhp)) - dealt
	if hp <= 0:
		var key := _structure_key_for_terrain(t)
		if t == Terrain.STORAGE:
			_storage.erase(idx)
			if _docked_station == idx:
				_clear_docked_station()
		_struct_hp.erase(idx)
		_barrels.erase(idx)
		_juicers.erase(idx)
		_planters.erase(idx)
		_lamps.erase(idx); _kilns.erase(idx); _apiaries.erase(idx); _wormfarms.erase(idx)
		_campfires.erase(idx); _stills.erase(idx); _generators.erase(idx)
		_sprinklers.erase(idx); _aquariums.erase(idx); _miners.erase(idx); _autoloaders.erase(idx); _traps.erase(idx)
		if _docked_station == idx:
			_clear_docked_station()
		var broken_to := _tile_on_break(t)
		if broken_to == Terrain.WRECK:
			_wrecks[idx] = {"terrain": t, "key": key, "hp": maxhp}
		else:
			_wrecks.erase(idx)
		_set_terrain(c, broken_to)
	else:
		_struct_hp[idx] = hp
	queue_redraw()


func _turret_take_damage(t: Dictionary, dmg: float) -> void:
	if t["broken"]:
		return
	t["hp"] = float(t["hp"]) - dmg
	if t["hp"] <= 0.0:
		t["hp"] = 0.0
		t["broken"] = true   # stays in place for daytime repair
		_add_shake(4.0)


func _damage_player(dmg: float, from_pos: Vector2 = Vector2.INF) -> void:
	if _downed:
		return
	_health = maxf(0.0, _health - dmg * (1.0 - _p_armor))  # armor reduces incoming damage
	_hurt_flash = FLASH_TIME * 1.6
	_add_shake(9.0)
	_hitstop = maxf(_hitstop, HITSTOP_HURT)
	# A punch is canceled if the player is hurt before it fully extends.
	if _punch_active and _punch_t < 0.5:
		_punch_active = false
	# Knockback away from the attacker.
	if from_pos != Vector2.INF:
		var d := _player_pos - from_pos
		if d.length() > 0.01:
			_player_kb = d.normalized() * KNOCKBACK
	if _health <= 0.0:
		_on_death()


# Damage-over-time (burn / poison) -- bypasses armor so status stays threatening.
func _hurt_dot(amount: float) -> void:
	if _downed:
		return
	_health = maxf(0.0, _health - amount)
	if _health <= 0.0:
		_on_death()


# --- Player status effects ---------------------------------------------------
func _apply_fire_hit(from_pos: Vector2) -> void:
	_damage_player(FIRE_DMG, from_pos)
	_burn_t = BURN_TIME


func _apply_snow_hit(from_pos: Vector2) -> void:
	_damage_player(SNOW_DMG, from_pos)
	# Slow is NOT re-applied while a snowball slow is already active.
	if _slow_t <= 0.0:
		_slow_t = SLOW_TIME
	# Freeze when enough snowballs land inside the rolling window.
	if _snow_window <= 0.0:
		_snow_count = 0
	_snow_window = FREEZE_WINDOW
	_snow_count += 1
	# Freeze does NOT stack while already frozen.
	if _snow_count >= FREEZE_HITS and _freeze_t <= 0.0:
		_freeze_t = FREEZE_TIME
		_snow_count = 0


func _update_status_effects(delta: float) -> void:
	if _burn_t > 0.0:
		_burn_t = maxf(0.0, _burn_t - delta)
		_hurt_dot(BURN_DPS * delta)
	if _slow_t > 0.0:
		_slow_t = maxf(0.0, _slow_t - delta)
	if _freeze_t > 0.0:
		_freeze_t = maxf(0.0, _freeze_t - delta)
	if _snow_window > 0.0:
		_snow_window = maxf(0.0, _snow_window - delta)
		if _snow_window == 0.0:
			_snow_count = 0
	# Standing in a purple poison cloud hurts each frame.
	for cl in _poison_clouds:
		if _player_pos.distance_to(cl["pos"]) <= POISON_RADIUS:
			_hurt_dot(POISON_DPS * delta)
			break


func _clear_status_effects() -> void:
	_burn_t = 0.0; _slow_t = 0.0; _freeze_t = 0.0
	_snow_count = 0; _snow_window = 0.0


# --- Projectiles -------------------------------------------------------------
# Tiles a projectile can fly over; anything else (walls, doors, trees, stone,
# structures) blocks the shot -- which is what makes walling yourself in defend
# against the ranged crocs.
const PROJ_PASS := {
	Terrain.GRASS: true, Terrain.FLOOR: true, Terrain.WATER: true,
	Terrain.STUMP: true, Terrain.SAPLING: true, Terrain.SAND: true, Terrain.WIRE: true, Terrain.PIPE: true, Terrain.LAND_MINE: true,
	Terrain.WRECK: true, Terrain.GLAPPLE_LAMP: true, Terrain.BULB: true,
}


func _proj_blocked_cell(c: Vector2i) -> bool:
	return not _in_bounds(c) or not PROJ_PASS.has(_terrain_at(c))


# Line-of-sight between two world points (sampled every half cell). The
# endpoints' own cells are ignored, so a turret can see out of its own tile and
# a shot isn't blocked by the target's tile.
func _has_los(a: Vector2, b: Vector2) -> bool:
	var ca := _world_to_cell(a)
	var cb := _world_to_cell(b)
	var d := b - a
	var steps := int(d.length() / (CELL_SIZE * 0.5)) + 1
	for i in range(1, steps):
		var c := _world_to_cell(a + d * (float(i) / float(steps)))
		if c == ca or c == cb:
			continue
		if _proj_blocked_cell(c):
			return false
	return true


func _fire_projectile(from: Vector2, kind: String) -> void:
	var dir := (_player_pos - from)
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	_projectiles.append({"pos": from, "vel": dir * PROJ_SPEED, "kind": kind})


func _update_projectiles(delta: float) -> void:
	var keep := []
	for p in _projectiles:
		var np: Vector2 = p["pos"] + p["vel"] * delta
		if p["kind"] == "arrow" or p["kind"] == "bullet" or p["kind"] == "snipe" or p["kind"] == "rocket" or p["kind"] == "sling" or p["kind"] == "peel":
			# Friendly projectile (turret or player slingshot): hits the first croc.
			var owner = p.get("owner", "")
			var hit = null
			for m in _monsters:
				if m["hp"] <= 0.0 or m["dig"]:
					continue
				if np.distance_to(m["pos"]) <= PROJ_RADIUS + MONSTER_RADIUS:
					hit = m
					break
			if hit != null:
				var dmg: float = float(p.get("dmg", 3.0))
				var crit: bool = randf() < float(p.get("crit", 0.0))
				if crit:
					dmg *= 2.0
				_hurt_croc(hit, dmg, p["vel"], float(p.get("kb", 0.0)), owner)
				if p["kind"] == "rocket":
					_rocket_splash(np, dmg * float(p.get("aoefrac", 0.4)), float(p.get("aoe", 1.8)) * CELL_SIZE, float(p.get("slow", 1.0)), owner, hit)
				elif p["kind"] == "peel":
					_peels.append({"pos": np, "t": 0.0})   # leaves a slippery peel behind
				continue
			var dc := _world_to_cell(np)
			if _in_bounds(dc) and _terrain_at(dc) == Terrain.CROC_DEN:
				_damage_den_at(dc, float(p.get("dmg", 3.0)))
				if p["kind"] == "rocket":
					_rocket_splash(np, float(p.get("dmg", 3.0)) * float(p.get("aoefrac", 0.4)), float(p.get("aoe", 1.8)) * CELL_SIZE, float(p.get("slow", 1.0)), owner, null)
				continue
			if _proj_blocked_cell(_world_to_cell(np)):
				if p["kind"] == "rocket":
					_rocket_splash(np, float(p.get("dmg", 3.0)) * float(p.get("aoefrac", 0.4)), float(p.get("aoe", 1.8)) * CELL_SIZE, float(p.get("slow", 1.0)), owner, null)
				continue
			p["pos"] = np
			keep.append(p)
			continue
		# Enemy projectile: hit the player?
		if np.distance_to(_player_pos) <= PROJ_RADIUS + PLAYER_RADIUS:
			if p["kind"] == "fire":
				_apply_fire_hit(p["pos"])
			else:
				_apply_snow_hit(p["pos"])
			continue
		# Blocked by a wall / structure?
		if _proj_blocked_cell(_world_to_cell(np)):
			continue
		p["pos"] = np
		keep.append(p)
	_projectiles = keep


# --- Turrets -----------------------------------------------------------------
func _new_turret(cell: Vector2i) -> Dictionary:
	return {
		"cell": cell, "pos": _cell_center_world(cell),
		"category": "", "type": "",
		"hp": 0.0, "max_hp": 0.0, "broken": false,
		"level": 1, "xp": 0, "xp_to_next": _turret_xp_needed(1), "points": 0,
		"alloc": {"hp": 0, "dmg": 0, "rate": 0, "range": 0},
		"fuel": 0.0, "max_fuel": TURRET_FUEL_MAX,
		"ammo": FP_TURRET_START_AMMO, "max_ammo": FP_TURRET_AMMO_MAX,
		"cd": 0.0, "dig": false, "field": Vector2.INF,
		"heal_t": 0.0,   # engineers: seconds left where recent healing still earns kill XP
		"powered": false, # wired to a live generator this frame? (runs without burning wine)
	}


func _configure_turret(idx: int, type: String) -> void:
	if not _turrets.has(idx):
		return
	var t: Dictionary = _turrets[idx]
	if t["type"] != "":
		return  # already chosen (permanent)
	if not _turret_tier_ok(type):
		_onboard("tier_locked", "Locked -- needs Mother Tree tier %d. Feed the Tree Sap at its hub to grow it and unlock this." % _turret_required_tier(type), 6.0)
		return
	var def: Dictionary = TURRET_DEFS[type]
	t["type"] = type
	t["category"] = def["cat"]
	t["max_hp"] = float(def["hp"])
	t["hp"] = t["max_hp"]
	t["fuel"] = TURRET_FUEL_MAX            # ships with a starter charge of wine
	t["ammo"] = maxi(int(t.get("ammo", 0)), FP_TURRET_START_AMMO)
	t["max_ammo"] = FP_TURRET_AMMO_MAX
	t["dig"] = bool(def.get("mover", false)) and type == "drill"
	_mark_workspace_dirty()


# Effective stat including this turret's spent upgrade points.
func _turret_stat(t: Dictionary, key: String) -> float:
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var a: Dictionary = t["alloc"]
	match key:
		"max_hp": return float(def["hp"]) + int(a["hp"]) * TURRET_HP_PER
		"dmg": return float(def["dmg"]) + int(a["dmg"]) * TURRET_DMG_PER
		"cd":
			var cd := maxf(0.05, float(def["cd"]) * (1.0 - int(a["rate"]) * TURRET_RATE_PER))
			return cd * FP_TURRET_POWER_RATE_MULT if bool(t.get("powered", false)) else cd
		"range": return (float(def["range"]) + int(a["range"]) * TURRET_RANGE_PER) * CELL_SIZE
	return 0.0


func _turret_spend_fuel(t: Dictionary) -> void:
	t["ammo"] = maxi(0, int(t.get("ammo", FP_TURRET_START_AMMO)) - 1)
	if bool(t.get("powered", false)):
		return   # wired turrets run off the generator -- no wine burned
	# Unpowered turrets drink wine ever faster as the nights deepen -- the pressure
	# that eventually forces a generator + wire network (required progression).
	var night_scale := 1.0 + float(_night_index()) * TURRET_FUEL_NIGHT_SCALE
	t["fuel"] = maxf(0.0, float(t["fuel"]) - TURRET_FUEL_PER_ACTION * (1.0 + int(t["level"]) * TURRET_FUEL_LVL_SCALE) * night_scale)


func _turret_xp_needed(level: int) -> int:
	return TURRET_XP_BASE + level * 3


func _turret_gain_xp(t: Dictionary, amount: int) -> void:
	t["xp"] = int(t["xp"]) + amount
	while int(t["xp"]) >= int(t["xp_to_next"]) and int(t["level"]) < LEVEL_CAP:
		t["xp"] = int(t["xp"]) - int(t["xp_to_next"])
		t["level"] = int(t["level"]) + 1
		t["points"] = int(t["points"]) + 1
		t["xp_to_next"] = _turret_xp_needed(int(t["level"]))


func _turret_alloc(idx: int, stat: String) -> void:
	if not _turrets.has(idx):
		return
	var t: Dictionary = _turrets[idx]
	if int(t["points"]) <= 0 or int(t["alloc"][stat]) >= STAT_UPGRADE_CAP:
		return
	t["alloc"][stat] = int(t["alloc"][stat]) + 1
	t["points"] = int(t["points"]) - 1
	t["max_hp"] = _turret_stat(t, "max_hp")
	if stat == "hp":
		t["hp"] = float(t["hp"]) + TURRET_HP_PER   # bonus HP is immediately usable
	_mark_workspace_dirty()


func _toggle_turret(idx: int) -> void:
	_docked_station = -1 if _docked_station == idx else idx
	_turret_pick_cat = ""
	_mark_workspace_dirty()


func _close_turret() -> void:
	if _docked_station != -1 and _terrain[_docked_station] == Terrain.TURRET:
		_docked_station = -1
		_turret_pick_cat = ""
		_mark_workspace_dirty()


func _turret_repair(idx: int) -> void:
	if not _turrets.has(idx):
		return
	var t: Dictionary = _turrets[idx]
	if float(t["hp"]) >= float(t["max_hp"]):
		return
	if not _can_afford(TURRET_REPAIR_COST):
		_set_msg("Need %s to repair." % _cost_text(TURRET_REPAIR_COST)); return
	_spend(TURRET_REPAIR_COST)
	t["hp"] = minf(float(t["max_hp"]), float(t["hp"]) + float(t["max_hp"]) * TURRET_REPAIR_FRAC)
	if t["hp"] > 0.0:
		t["broken"] = false
	_mark_workspace_dirty()


func _turret_refuel(idx: int) -> void:
	if not _turrets.has(idx) or _inv("cup_wine") <= 0:
		_set_msg("Need a cup of berry wine."); return
	var t: Dictionary = _turrets[idx]
	_resources["cup_wine"] = _inv("cup_wine") - 1
	_resources["cup"] = _inv("cup") + 1
	t["fuel"] = minf(float(t["max_fuel"]), float(t["fuel"]) + TURRET_FUEL_PER_CUP)
	_mark_workspace_dirty()


func _turret_reload(idx: int) -> void:
	if not _turrets.has(idx):
		return
	var t: Dictionary = _turrets[idx]
	var need := int(t.get("max_ammo", FP_TURRET_AMMO_MAX)) - int(t.get("ammo", 0))
	var take := mini(need, _inv("gunpowder"))
	if take <= 0:
		_set_msg("Need gunpowder to reload.")
		return
	_resources["gunpowder"] = _inv("gunpowder") - take
	t["ammo"] = int(t.get("ammo", 0)) + take
	_mark_workspace_dirty()


func _turret_update(delta: float) -> void:
	_update_trickster_marks(delta)   # tricksters maintain their marks globally
	_tag_adhesive_debuffs()          # credit adhesive fields for the crocs they slow
	for idx in _turrets:
		var t: Dictionary = _turrets[idx]
		t["heal_t"] = maxf(0.0, float(t["heal_t"]) - delta)
		if t["type"] == "" or t["broken"]:
			continue
		t["powered"] = _is_powered(t["cell"]) or _in_tree_aura(t["cell"])   # wired or inside Tree aura?
		t["cd"] = maxf(0.0, float(t["cd"]) - delta)
		if int(t.get("ammo", FP_TURRET_START_AMMO)) <= 0:
			continue
		if not bool(t["powered"]) and float(t["fuel"]) <= 0.0:
			continue        # out of wine and unpowered -- idle until refueled/wired
		match t["type"]:
			"sniper", "mg", "rocket": _turret_ranged(t, delta)
			"boxer", "slicer": _turret_melee(t, delta)
			"drill": _turret_drill(t, delta)
			"engineer": _turret_engineer(t, delta)
			"adhesive": _turret_adhesive(t, delta)
			"trickster": pass   # marking handled in _update_trickster_marks


# --- Ranged turrets: Sniper / Machine Gun / Rocket ---------------------------
func _turret_ranged(t: Dictionary, _delta: float) -> void:
	if float(t["cd"]) > 0.0:
		return
	var rng := _turret_stat(t, "range")
	var target = _nearest_croc_los(t["pos"], rng)
	if target == null:
		var den_target = _nearest_den_los(t["pos"], rng)
		if den_target == null:
			return
		_damage_den_at(den_target["cell"], _turret_stat(t, "dmg"))
		t["cd"] = _turret_stat(t, "cd")
		_turret_spend_fuel(t)
		return
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var owner := _cell_index(t["cell"])
	var from: Vector2 = t["pos"]
	var dir: Vector2 = ((target["pos"] as Vector2) - from).normalized()
	var dmg := _turret_stat(t, "dmg")
	var proj := {"pos": from, "owner": owner, "dmg": dmg, "kb": float(def.get("kb", 0.0))}
	match t["type"]:
		"sniper":
			proj["kind"] = "snipe"
			proj["crit"] = float(def.get("crit", 0.0))
			proj["vel"] = dir * TURRET_PROJ_SPEED * 1.5
		"mg":
			# Accuracy degrades with distance, so mid-range is the sweet spot.
			var dist: float = from.distance_to(target["pos"])
			var spread: float = float(def.get("spread", 0.0)) * (dist / rng)
			proj["kind"] = "bullet"
			proj["vel"] = dir.rotated(randf_range(-spread, spread)) * TURRET_PROJ_SPEED
		"rocket":
			proj["kind"] = "rocket"
			proj["vel"] = dir * TURRET_PROJ_SPEED * 0.8
			proj["aoe"] = float(def.get("aoe", 1.8))
			proj["aoefrac"] = float(def.get("aoefrac", 0.4))
			proj["slow"] = float(def.get("slow", 1.0))
	_projectiles.append(proj)
	_casings.append({"pos": from})
	t["cd"] = _turret_stat(t, "cd")
	_turret_spend_fuel(t)


# --- Physical turrets: Boxer (single) / Slicer (wide multi-target) -----------
func _turret_melee(t: Dictionary, _delta: float) -> void:
	if float(t["cd"]) > 0.0:
		return
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var rng := _turret_stat(t, "range")
	var dmg := _turret_stat(t, "dmg")
	var owner := _cell_index(t["cell"])
	var from: Vector2 = t["pos"]
	if def.get("multi", false):
		var hit := false
		for m in _monsters:
			if m["hp"] <= 0.0 or m["dig"]:
				continue
			if from.distance_to(m["pos"]) <= rng + MONSTER_RADIUS:
				_hurt_croc(m, dmg, (m["pos"] as Vector2) - from, float(def["kb"]), owner)
				hit = true
		if hit:
			_spark_pos = from; _spark_t = 0.0
			t["cd"] = _turret_stat(t, "cd")
			_turret_spend_fuel(t)
	else:
		var target = _nearest_croc_los(from, rng + MONSTER_RADIUS)
		if target != null:
			_hurt_croc(target, dmg, (target["pos"] as Vector2) - from, float(def["kb"]), owner)
			t["cd"] = _turret_stat(t, "cd")
			_turret_spend_fuel(t)


# --- Drill: roams to the highest-priority croc and jackhammers it -------------
func _turret_drill(t: Dictionary, delta: float) -> void:
	var target = _drill_target(t["pos"])
	if target == null:
		# No prey -- return toward the dock and idle.
		var home := _cell_center_world(t["cell"])
		if (t["pos"] as Vector2).distance_to(home) > 2.0:
			t["pos"] = (t["pos"] as Vector2).move_toward(home, TURRET_MOVE_SPEED * delta)
		t["dig"] = true
		return
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var rng := _turret_stat(t, "range")
	var to: Vector2 = (target["pos"] as Vector2) - (t["pos"] as Vector2)
	var dist: float = to.length()
	if dist > rng:
		t["dig"] = true   # tunnelling toward the target
		t["pos"] = (t["pos"] as Vector2) + to.normalized() * TURRET_MOVE_SPEED * delta
		t["fuel"] = maxf(0.0, float(t["fuel"]) - TURRET_FUEL_PER_ACTION * 0.4 * delta)
	else:
		t["dig"] = false  # surfaced, drilling
		if float(t["cd"]) <= 0.0:
			_hurt_croc(target, _turret_stat(t, "dmg"), to, float(def["kb"]), _cell_index(t["cell"]))
			t["cd"] = _turret_stat(t, "cd")
			_turret_spend_fuel(t)


# Croc-class priority for the drill: support(healer) > ranged > physical.
func _croc_priority(role: String) -> int:
	if role == "healer": return 3
	if role == "fire" or role == "ice" or role == "poison": return 2
	return 1


func _drill_target(from: Vector2):
	var best = null
	var best_pri := 0
	var best_d := INF
	for m in _monsters:
		if m["hp"] <= 0.0 or m["dig"]:
			continue
		var pri := _croc_priority(m["role"])
		var d: float = from.distance_to(m["pos"])
		if pri > best_pri or (pri == best_pri and d < best_d):
			best_pri = pri
			best_d = d
			best = m
	return best


# --- Engineer: roams to wounded turrets and heals an AoE around itself --------
func _turret_engineer(t: Dictionary, delta: float) -> void:
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var rng := _turret_stat(t, "range")
	var goal = _nearest_wounded_turret(t)
	if goal == null:
		var home := _cell_center_world(t["cell"])
		if (t["pos"] as Vector2).distance_to(home) > 2.0:
			t["pos"] = (t["pos"] as Vector2).move_toward(home, TURRET_MOVE_SPEED * delta)
		return
	var gp: Vector2 = goal["pos"]
	if (t["pos"] as Vector2).distance_to(gp) > rng:
		t["pos"] = (t["pos"] as Vector2).move_toward(gp, TURRET_MOVE_SPEED * delta)
		t["fuel"] = maxf(0.0, float(t["fuel"]) - TURRET_FUEL_PER_ACTION * 0.4 * delta)
		return
	# In range: mend every wounded turret in the aura.
	var healed := false
	for oidx in _turrets:
		var o: Dictionary = _turrets[oidx]
		if o == t or o["type"] == "":
			continue
		if (t["pos"] as Vector2).distance_to(o["pos"]) <= rng and float(o["hp"]) < float(o["max_hp"]):
			o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(def["heal"]) * delta)
			if float(o["hp"]) > 0.0:
				o["broken"] = false
			healed = true
	if healed:
		t["fuel"] = maxf(0.0, float(t["fuel"]) - TURRET_FUEL_PER_ACTION * 0.6 * delta)
		t["heal_t"] = TURRET_ENGINEER_HEAL_WINDOW   # bank kill-XP eligibility while mending


func _nearest_wounded_turret(t: Dictionary):
	var best = null
	var best_d := INF
	for oidx in _turrets:
		var o: Dictionary = _turrets[oidx]
		if o == t or o["type"] == "" or float(o["hp"]) >= float(o["max_hp"]):
			continue
		var d: float = (t["pos"] as Vector2).distance_to(o["pos"])
		if d < best_d:
			best_d = d
			best = o
	return best


# --- Adhesive: lobs a lingering slow field onto the crocs --------------------
func _turret_adhesive(t: Dictionary, _delta: float) -> void:
	if float(t["cd"]) > 0.0:
		return
	var rng := _turret_stat(t, "range")
	var target = _nearest_croc_los(t["pos"], rng)
	if target == null:
		return
	t["field"] = target["pos"]   # replaces the previous field
	t["cd"] = _turret_stat(t, "cd")
	_turret_spend_fuel(t)


# Credit each adhesive turret for every croc currently caught in its slow field,
# so a kill on a slowed croc pays the adhesive turret its full XP.
func _tag_adhesive_debuffs() -> void:
	for idx in _turrets:
		var t: Dictionary = _turrets[idx]
		if t["type"] != "adhesive" or t["broken"] or float(t["fuel"]) <= 0.0:
			continue
		if (t["field"] as Vector2) == Vector2.INF:
			continue
		var reach: float = float(TURRET_DEFS["adhesive"]["field"]) * CELL_SIZE
		for m in _monsters:
			if m["hp"] <= 0.0:
				continue
			if (m["pos"] as Vector2).distance_to(t["field"]) <= reach:
				(m["debuff_by"] as Dictionary)[idx] = TURRET_SUPPORT_WINDOW


# Slow multiplier from any adhesive field covering `pos` (12% slow, no stacking).
func _adhesive_factor(pos: Vector2) -> float:
	for idx in _turrets:
		var t: Dictionary = _turrets[idx]
		if t["type"] == "adhesive" and not t["broken"] and (t["field"] as Vector2) != Vector2.INF:
			var def: Dictionary = TURRET_DEFS["adhesive"]
			if pos.distance_to(t["field"]) <= float(def["field"]) * CELL_SIZE:
				return 1.0 - float(def["fieldslow"])
	return 1.0


# --- Trickster: marks the toughest crocs for +20% damage taken ---------------
func _update_trickster_marks(delta: float) -> void:
	var tricksters := []
	for idx in _turrets:
		var t: Dictionary = _turrets[idx]
		if t["type"] == "trickster" and not t["broken"] and float(t["fuel"]) > 0.0:
			tricksters.append(t)
	if tricksters.is_empty():
		for m in _monsters:
			m["marked"] = false
		return
	var cap: int = 2 * tricksters.size()
	var marked := 0
	for m in _monsters:
		if m["marked"] and m["hp"] > 0.0:
			marked += 1
	# Fill empty mark slots with the highest-HP unmarked croc in any range.
	while marked < cap:
		var pick = null
		var pick_hp := 0.0
		for m in _monsters:
			if m["hp"] <= 0.0 or m["marked"] or m["dig"]:
				continue
			if float(m["hp"]) <= pick_hp:
				continue
			for tr in tricksters:
				if (tr["pos"] as Vector2).distance_to(m["pos"]) <= _turret_stat(tr, "range"):
					pick = m
					pick_hp = float(m["hp"])
					break
		if pick == null:
			break
		pick["marked"] = true
		marked += 1
	# Keep each trickster credited for every marked croc it can still see, so a
	# kill on a marked croc pays the trickster(s) responsible their full XP.
	for tr in tricksters:
		var tidx := _cell_index(tr["cell"])
		for m in _monsters:
			if m["hp"] <= 0.0 or not m["marked"]:
				continue
			if (tr["pos"] as Vector2).distance_to(m["pos"]) <= _turret_stat(tr, "range"):
				(m["debuff_by"] as Dictionary)[tidx] = TURRET_SUPPORT_WINDOW
		tr["fuel"] = maxf(0.0, float(tr["fuel"]) - TURRET_FUEL_PER_ACTION * 0.3 * delta)


func _croc_counter_class(m: Dictionary) -> String:
	match String(m.get("role", "")):
		"wrecker", "digger", "reviver":
			return "armored"
		"fire", "ice":
			return "single"
		"healer", "poison":
			return "support"
	return "swarm"


# Central croc-damage entry: applies armor + trickster mark, knockback, flash,
# and records who gets the kill (a turret cell idx, or "player").
func _hurt_croc(m: Dictionary, dmg: float, kb_vec: Vector2, kb_mult: float, killer) -> void:
	var mult := 1.2 if m["marked"] else 1.0
	if killer is int and _turrets.has(killer):
		var cat: String = _turrets[killer].get("category", "")
		var cls := _croc_counter_class(m)
		mult *= float((FP_COUNTER_MATRIX.get(cat, {}) as Dictionary).get(cls, 1.0))
	var dealt := dmg * (1.0 - float(m["armor"])) * mult
	m["hp"] = float(m["hp"]) - dealt
	_fx_damage_number(m["pos"], dealt, "damage")
	m["flash"] = FLASH_TIME
	if kb_mult > 0.0:
		var d := kb_vec.normalized() if kb_vec.length() > 0.01 else Vector2.RIGHT
		m["kb"] = d * KNOCKBACK * kb_mult
	# Remember this hit so the dealer can still claim an assist if the croc dies soon.
	# (killer is a turret cell-index int, "player", or "" -- log only real dealers.)
	var anon: bool = killer == null or (killer is String and (killer as String).is_empty())
	if not anon:
		var log: Dictionary = m["dmg_log"]
		log[killer] = TURRET_ASSIST_WINDOW
	if float(m["hp"]) <= 0.0:
		m["killer"] = killer


func _rocket_splash(center: Vector2, dmg: float, radius: float, slow: float, owner, exclude) -> void:
	for m in _monsters:
		if m["hp"] <= 0.0 or m["dig"] or m == exclude:
			continue
		if (m["pos"] as Vector2).distance_to(center) <= radius:
			_hurt_croc(m, dmg, (m["pos"] as Vector2) - center, 0.0, owner)
			m["slow_t"] = maxf(float(m["slow_t"]), slow)   # rocket slow (not stackable: just sets)
	_poofs.append({"pos": center, "t": 0.15})


func _nearest_croc_los(from: Vector2, radius: float):
	var best = null
	var best_d := radius
	for m in _monsters:
		if m["hp"] <= 0.0 or m["dig"]:
			continue
		var d: float = from.distance_to(m["pos"])
		if d < best_d and _has_los(from, m["pos"]):
			best_d = d
			best = m
	return best


func _count_traps() -> int:
	var n := 0
	for i in range(_terrain.size()):
		if TRAP_TERRAIN.has(_terrain[i]):
			n += 1
	return n


func _trap_update(_delta: float) -> void:
	# Spike traps: hurt + slow a croc standing on them, then re-arm.
	for idx in range(_terrain.size()):
		if _terrain[idx] != Terrain.TRAP:
			continue
		var cd: float = maxf(0.0, float(_trap_cd.get(idx, 0.0)) - _delta)
		if cd <= 0.0:
			var tc := _index_cell(idx)
			for m in _monsters:
				if m["hp"] <= 0.0 or m["dig"]:
					continue
				if _world_to_cell(m["pos"]) == tc:
					_hurt_croc(m, TRAP_DMG, Vector2.ZERO, 0.0, "player")
					m["slow_t"] = TRAP_SLOW_TIME
					_add_shake(2.0)
					cd = TRAP_REARM
					break
		_trap_cd[idx] = cd

	# The new traps (mine / peel launcher / electric fence).
	var spent_mines := []
	for idx in _traps:
		var tr: Dictionary = _traps[idx]
		var tc2 := _index_cell(idx)
		var tp: Vector2 = _cell_center_world(tc2)
		match tr["type"]:
			"land_mine":
				for m in _monsters:
					if m["hp"] <= 0.0 or m["dig"]:
						continue
					if tp.distance_to(m["pos"]) <= CELL_SIZE * 0.7:
						_mine_explode(tp)
						spent_mines.append(idx)
						break
			"peel_launcher":
				tr["cd"] = maxf(0.0, float(tr["cd"]) - _delta)
				if tr["cd"] <= 0.0 and int(tr["ammo"]) > 0:
					var target = _nearest_croc_los(tp, PEEL_RANGE)
					if target != null:
						var dir: Vector2 = ((target["pos"] as Vector2) - tp).normalized()
						# Start just outside the launcher tile so the shot isn't self-blocked.
						_projectiles.append({"pos": tp + dir * CELL_SIZE * 0.8, "vel": dir * SLING_PROJ_SPEED * 0.8, "kind": "peel", "owner": "player", "dmg": PEEL_DMG, "kb": 0.0})
						tr["ammo"] = int(tr["ammo"]) - 1
						tr["cd"] = PEEL_CD
						tr["hp"] = int(tr["hp"]) - 1   # the launcher wears with each shot
						if int(tr["hp"]) <= 0:
							spent_mines.append(idx)   # worn out -> breaks (reuse the removal list)
			"electric_fence":
				if _is_powered(tc2):
					tr["cd"] = maxf(0.0, float(tr["cd"]) - _delta)
					if tr["cd"] <= 0.0:
						var zapped := false
						for m in _monsters:
							if m["hp"] <= 0.0 or m["dig"]:
								continue
							if tp.distance_to(m["pos"]) <= CELL_SIZE * 1.3:
								_hurt_croc(m, FENCE_ZAP_DMG, Vector2.ZERO, 0.0, "player")
								zapped = true
						if zapped:
							tr["cd"] = FENCE_ZAP_CD
	for idx in spent_mines:
		_traps.erase(idx)
		_set_terrain(_index_cell(idx), Terrain.GRASS)

	# Dropped peels: linger, and stun the first croc that slips on one.
	var keep_peels := []
	for pl in _peels:
		pl["t"] = float(pl["t"]) + _delta
		var hit := false
		for m in _monsters:
			if m["hp"] <= 0.0 or m["dig"]:
				continue
			if (pl["pos"] as Vector2).distance_to(m["pos"]) <= CELL_SIZE * 0.5 + MONSTER_RADIUS:
				m["stun_t"] = PEEL_STUN_TIME
				hit = true
				break
		if not hit and float(pl["t"]) < PEEL_GROUND_LIFE:
			keep_peels.append(pl)
	_peels = keep_peels


func _mine_explode(at: Vector2) -> void:
	_add_shake(8.0)
	_poofs.append({"pos": at, "t": 0.0})
	for m in _monsters:
		if m["hp"] <= 0.0 or m["dig"]:
			continue
		if at.distance_to(m["pos"]) <= MINE_RADIUS:
			_hurt_croc(m, MINE_DMG, (m["pos"] as Vector2) - at, 1.5, "player")


func _peel_launcher_load(idx: int) -> void:
	var tr: Dictionary = _traps[idx]
	if _inv("banana_peel") <= 0:
		_set_msg("No banana peels for ammo."); return
	_resources["banana_peel"] = _inv("banana_peel") - 1
	tr["ammo"] = int(tr["ammo"]) + 1
	_mark_workspace_dirty()


func _trap_repair(idx: int) -> void:
	var tr: Dictionary = _traps.get(idx, {})
	if not tr.has("hp"):
		return   # mines/fences don't wear-repair
	var maxhp: int = int(TRAP_MAX_HP.get(tr["type"], 1))
	if int(tr["hp"]) >= maxhp:
		return
	if not _can_afford(TRAP_REPAIR_COST):
		_set_msg("Need %s to repair." % _cost_text(TRAP_REPAIR_COST)); return
	_spend(TRAP_REPAIR_COST)
	tr["hp"] = maxhp
	_mark_workspace_dirty()


# Position of the nearest living, non-burrowed croc within `range` of `from`
# (with clear line of sight); Vector2.INF if none.
func _nearest_croc_in_range(from: Vector2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_d := radius
	for m in _monsters:
		if m["hp"] <= 0.0 or m["dig"]:
			continue
		var d: float = from.distance_to(m["pos"])
		if d < best_d and _has_los(from, m["pos"]):
			best_d = d
			best = m["pos"]
	return best


# --- Persistence -------------------------------------------------------------
func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = f.get_var()
	f.close()
	if data is Dictionary and (data as Dictionary).has("best_nights"):
		_best_nights = int((data as Dictionary)["best_nights"])


func _save_progress() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"best_nights": _best_nights})
	f.close()


# --- Leveling / stats --------------------------------------------------------
func _init_progression() -> void:
	_level = 1
	_xp = 0
	_nights_survived = 0
	_stat_points = 0
	_active_overlay = Overlay.NONE
	_alloc = {"health": 0, "attack": 0, "speed": 0, "armor": 0, "regen": 0}
	_recompute_player_stats()
	_xp_to_next = _xp_needed(_level)
	_health = _p_max_health
	_energy = ENERGY_MAX
	_hydration = HYDRATION_MAX


func _recompute_player_stats() -> void:
	# Stats grow from the points the player has chosen to spend, not from level alone.
	_p_max_health = HEALTH_MAX + _alloc["health"] * HEALTH_PER_LEVEL
	_p_attack = PLAYER_DMG + _alloc["attack"] * ATK_PER_LEVEL
	_p_speed = PLAYER_SPEED * (1.0 + _alloc["speed"] * SPD_PER_LEVEL)
	_p_armor = minf(ARMOR_CAP, _alloc["armor"] * ARMOR_PER_LEVEL + _gear_armor)
	_p_regen = HEALTH_REGEN + _alloc["regen"] * REGEN_PER_LEVEL


func _xp_needed(level: int) -> int:
	return 5 * level


func _gain_xp(amount: int) -> void:
	if _level >= LEVEL_CAP:
		return   # maxed out -- no more XP needed
	_xp += amount
	while _xp >= _xp_to_next and _level < LEVEL_CAP:
		_xp -= _xp_to_next
		_level_up()


func _level_up() -> void:
	_level += 1
	_xp_to_next = _xp_needed(_level)
	# Grant a point and freeze the action until the player chooses where it goes.
	_stat_points += 1
	_active_overlay = Overlay.LEVELUP
	_msg = "LEVEL UP!  Choose a stat to raise"
	_msg_timer = 2.5
	_mark_workspace_dirty()


# Stat names mapped to a short label + the per-point effect text.
const STAT_INFO: Dictionary = {
	"health": {"label": "Health", "num": 1},
	"attack": {"label": "Attack", "num": 2},
	"speed":  {"label": "Speed",  "num": 3},
	"armor":  {"label": "Armor",  "num": 4},
	"regen":  {"label": "Regen",  "num": 5},
}


func _stat_choice_text(stat: String) -> String:
	match stat:
		"health": return "+%d max HP" % int(HEALTH_PER_LEVEL)
		"attack": return "+%d damage" % int(ATK_PER_LEVEL)
		"speed":  return "+%d%% move speed" % int(SPD_PER_LEVEL * 100.0)
		"armor":  return "+%d%% damage cut" % int(ARMOR_PER_LEVEL * 100.0)
		"regen":  return "+%.1f HP/sec" % REGEN_PER_LEVEL
	return ""


func _choose_stat(stat: String) -> void:
	if _stat_points <= 0 or not _alloc.has(stat):
		return
	if _alloc[stat] >= STAT_UPGRADE_CAP:
		_set_msg("%s is already maxed (70)." % stat.capitalize())
		return
	_alloc[stat] += 1
	_stat_points -= 1
	_recompute_player_stats()
	_health = _p_max_health          # full heal on spending a point
	if _stat_points <= 0:
		_active_overlay = Overlay.NONE
	_mark_workspace_dirty()
	_update_status()
	queue_redraw()


func _night_index() -> int:
	return _nights_survived + 1


func _on_death() -> void:
	_start_player_downed()


func _respawn_after_death() -> void:
	# Return at the Mother Tree. The world keeps moving while the player is down.
	_downed = false
	_downed_timer = 0.0
	if _sap >= FP_RESPAWN_SAP_COST:
		_sap -= FP_RESPAWN_SAP_COST
	else:
		_apply_sap_broke_respawn_debuff()
	_health = _p_max_health
	_energy = maxf(_energy, ENERGY_MAX * 0.5)
	_hydration = maxf(_hydration, HYDRATION_MAX * 0.5)
	_player_kb = Vector2.ZERO
	_punch_active = false
	_clear_status_effects()
	_projectiles.clear()
	_poison_clouds.clear()
	_cell = _tree_respawn_cell()
	_player_pos = _cell_center_world(_cell)
	_invalidate_flow_fields()
	_ensure_flow_fields()
	_camera.position = _player_pos
	_apply_daylight()
	_set_msg("The Mother Tree pulled you back.")
	_mark_workspace_dirty()


func _reset_game() -> void:
	# Wipe everything and start a brand-new run on a fresh world.
	# (_best_nights is intentionally preserved across runs.)
	_seed = randi()
	_generate_world()
	_init_progression()
	_resources = _default_inventory()
	_sap = 0.0
	_decay_timer = 0.0
	_juice_spoil_t = 0.0
	_active_overlay = Overlay.NONE
	_hydration = HYDRATION_MAX
	_tool_equipped = ""
	_weapon_equipped = ""
	_gear_armor = 0.0
	_lives = MAX_LIVES
	_time = FP_DAY_START
	_day = 1
	_banana_timer = 0.0
	_monsters.clear()
	_projectiles.clear()
	_poison_clouds.clear()
	_ground_items.clear()
	_clear_status_effects()
	_turrets.clear()
	_trap_cd.clear()
	_barrels.clear()
	_juicers.clear()
	_planters.clear()
	_lamps.clear()
	_kilns.clear()
	_apiaries.clear()
	_wormfarms.clear()
	_campfires.clear()
	_stills.clear()
	_generators.clear()
	_energized.clear()
	_watered.clear()
	_sprinklers.clear()
	_aquariums.clear()
	_miners.clear()
	_autoloaders.clear()
	_casings.clear()
	_traps.clear()
	_peels.clear()
	_fish.clear()
	_dens.clear()
	_won = false
	# Re-teach on a fresh run: clear the one-shot beats + TECH discovery state.
	_onboard_seen = {}
	_msg_queue.clear()
	_msg_onboard = false
	_tech_new_until = 0.0
	_tech_seen_tier = 1
	if _victory_layer:
		_victory_layer.visible = false
	if _tech_root:
		_tech_root.visible = false
	_night_snapshot.clear()
	_struct_hp.clear()
	_wrecks.clear()
	_storage.clear()
	_is_night = false
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_docked_station = -1
	_punch_active = false
	_player_kb = Vector2.ZERO
	_reset_tree_state()
	_place_iron_veins()
	_spawn_initial_dens()
	_cell = _tree_respawn_cell()
	_player_pos = _cell_center_world(_cell)
	_invalidate_flow_fields()
	_ensure_flow_fields()
	_camera.position = _player_pos
	_apply_daylight()
	_mark_workspace_dirty()
	queue_redraw()


# -----------------------------------------------------------------------------
# Build-mode input and mouse
# -----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Menu / splash / settings consume their own GUI input; ignore gameplay keys.
	if _app_state != AppState.PLAYING:
		return
	# Victory banner is up: the sim is halted. Any key starts a fresh run.
	if _won:
		if event is InputEventKey and event.pressed and not event.echo:
			_reset_game()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		# Pending level-up choice eats number keys 1-5.
		if _active_overlay == Overlay.LEVELUP:
			if kc >= KEY_1 and kc <= KEY_5:
				_choose_stat(STAT_ORDER[kc - KEY_1])
			return
		# The full-screen TECH hub: Esc dismisses it back to the board.
		if _active_overlay == Overlay.TECH:
			if kc == KEY_ESCAPE:
				_close_active_overlay()
			return
		if kc == KEY_B:
			# Build mode is daytime-only. B toggles it; pressing B again exits.
			if _build_mode:
				_build_mode = false
				_build_struct = ""
				_dragging = false
				_drag_action = BuildAction.NONE
				_mark_workspace_dirty()
				queue_redraw()
			elif not _is_night:
				_build_mode = true
				_clear_docked_station()
				_mark_workspace_dirty()
				queue_redraw()
		elif kc == KEY_E:
			_try_eat()
		elif kc == KEY_Q:
			_drink_best()
		elif kc == KEY_I:
			_set_msg("Inventory is always open in the workspace.")
		elif kc == KEY_C:
			_set_msg("Crafting is always open by day.")
		elif _build_mode and kc >= KEY_1 and kc <= KEY_9:
			_select_by_num(kc - KEY_0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _active_overlay != Overlay.NONE or not _mouse_in_board():
			return
		if _build_mode:
			if event.pressed:
				_begin_drag()
			else:
				_dragging = false
				_drag_action = BuildAction.NONE
		elif event.pressed:
			_on_left_click_world()
	elif event is InputEventMouseMotion:
		if _build_mode and _dragging and _mouse_in_board():
			var c := _mouse_cell()
			if c != _last_applied_cell:
				_apply_build_at(c)


func _mouse_in_board() -> bool:
	var vp := get_viewport_rect().size
	var mx := get_viewport().get_mouse_position().x
	return mx >= PANEL_W and mx <= vp.x - PANEL_W


func _select_struct(key: String) -> void:
	_build_struct = key
	_mark_workspace_dirty()


func _select_by_num(n: int) -> void:
	for key in STRUCTURE_ORDER:
		if STRUCTURES[key]["num"] == n:
			_select_struct(key)
			return


func _begin_drag() -> void:
	var c := _mouse_cell()
	if _in_bounds(c) and _structure_key_for_terrain(_terrain_at(c)) != "":
		_drag_action = BuildAction.DESTROY
	else:
		_drag_action = BuildAction.BUILD
	_dragging = true
	_last_applied_cell = Vector2i(-9999, -9999)
	_apply_build_at(c)


# Pure predicate: can the currently-selected structure be placed at `c`?
# Mirrors every build gate in _apply_build_at without side effects, so the
# build-mode ghost (see _draw) can colour itself OK-vs-blocked from the same
# truth the placement uses. Keeping one predicate stops the ghost from lying.
# `check_afford` is split out so the ghost can distinguish "blocked" (red X tint)
# from merely "can't afford" (red tint, but the spot is otherwise valid).
func _build_placement_valid_spot(c: Vector2i) -> bool:
	if not _in_bounds(c) or _build_struct == "":
		return false
	var s: Dictionary = STRUCTURES[_build_struct]
	if not _struct_tier_ok(_build_struct):
		return false
	if c == _cell or _monster_at(c) != -1:
		return false
	if _build_struct == "auto_miner":
		if _terrain_at(c) != Terrain.IRON_VEIN:
			return false
	elif _terrain_at(c) != Terrain.GRASS:
		return false
	if s["bench"] and not _near_workbench():
		return false
	if BLOCK_TERRAIN.has(int(s["terrain"])) and _block_count >= BLOCK_LIMIT:
		return false
	if TRAP_TERRAIN.has(int(s["terrain"])) and _count_traps() >= MAX_TRAPS:
		return false
	if int(s["terrain"]) == Terrain.TURRET:
		if _turrets.size() >= MAX_TURRETS or not _is_outdoors(c):
			return false
	return true


# Full placement check used by the ghost: valid spot AND affordable.
func _build_placement_ok(c: Vector2i) -> bool:
	if not _build_placement_valid_spot(c):
		return false
	return _can_afford(STRUCTURES[_build_struct]["cost"])


func _apply_build_at(c: Vector2i) -> void:
	if not _in_bounds(c):
		return
	_last_applied_cell = c

	if _drag_action == BuildAction.BUILD:
		if _build_struct == "":
			return
		var s: Dictionary = STRUCTURES[_build_struct]
		if not _struct_tier_ok(_build_struct):
			_onboard("tier_locked", "Locked -- needs Mother Tree tier %d. Feed the Tree Sap at its hub to grow it and unlock this." % _struct_required_tier(_build_struct), 6.0)
			return
		if c == _cell or _monster_at(c) != -1:
			return
		if _build_struct == "auto_miner":
			if _terrain_at(c) != Terrain.IRON_VEIN:
				_set_msg("Auto-Miner must be placed on an iron vein.")
				return
		elif _terrain_at(c) != Terrain.GRASS:
			return
		if s["bench"] and not _near_workbench():
			return
		# Structural blocks (walls/floors/doors) are capped; workstations/turrets exempt.
		if BLOCK_TERRAIN.has(int(s["terrain"])) and _block_count >= BLOCK_LIMIT:
			_set_msg("Block limit reached (%d). Remove some to build more." % BLOCK_LIMIT)
			return
		# Traps have their own separate cap.
		if TRAP_TERRAIN.has(int(s["terrain"])) and _count_traps() >= MAX_TRAPS:
			_set_msg("Trap limit reached (%d)." % MAX_TRAPS)
			return
		# Turrets must stand outdoors, never walled inside your base.
		if int(s["terrain"]) == Terrain.TURRET:
			if _turrets.size() >= MAX_TURRETS:
				_set_msg("Turret limit reached (%d). Tear one down first." % MAX_TURRETS)
				return
			if not _is_outdoors(c):
				_set_msg("Turrets must be placed outdoors.")
				return
		if not _can_afford(s["cost"]):
			return
		_spend(s["cost"])
		_set_terrain(c, s["terrain"])
		var bidx := _cell_index(c)
		match int(s["terrain"]):
			Terrain.STORAGE:
				_storage[bidx] = _new_storage_box()
			Terrain.BARREL:
				_barrels[bidx] = {"kind": "", "amount": 0, "ferment": 0.0}
			Terrain.JUICER:
				_juicers[bidx] = {"juice": 0, "pending": 0, "conv": 0.0}
			Terrain.PLANTER:
				_planters[bidx] = {"planted": false, "berries": 0, "grow": 0.0, "wet": 0.0}
			Terrain.GLAPPLE_LAMP:
				_lamps[bidx] = {"kind": "glapple", "life": LAMP_LIFE, "dead": false}
			Terrain.KILN:
				_kilns[bidx] = {"fuel": 0.0, "queue": [], "conv": 0.0}
			Terrain.BEE_ENCLOSURE:
				_apiaries[bidx] = {"bees": 0, "prod": 0.0, "starve": 0.0}
			Terrain.WORM_FARM:
				_wormfarms[bidx] = {"worms": 0, "rot": 0, "mult": 0.0, "compost": 0.0}
			Terrain.CAMPFIRE:
				_campfires[bidx] = {"item": "", "cook": 0.0}
			Terrain.STILL:
				_stills[bidx] = {"pending": 0, "conv": 0.0}
			Terrain.GENERATOR:
				_generators[bidx] = {"oil": 0, "on": false, "drain": 0.0}
			Terrain.BULB:
				_lamps[bidx] = {"kind": "electric", "life": 0.0, "dead": false}
			Terrain.SPRINKLER:
				_sprinklers[bidx] = {}
			Terrain.AQUARIUM:
				_aquariums[bidx] = {"males": 0, "females": 0, "eggs": 0, "quality": 100.0, "water": 0, "feed": 0.0, "breed": 0.0}
			Terrain.AUTO_MINER:
				_miners[bidx] = {"t": 0.0}
			Terrain.AUTO_LOADER:
				_autoloaders[bidx] = {"t": 0.0}
			Terrain.LAND_MINE:
				_traps[bidx] = {"type": "land_mine"}
			Terrain.PEEL_LAUNCHER:
				_traps[bidx] = {"type": "peel_launcher", "hp": TRAP_MAX_HP["peel_launcher"], "ammo": 0, "cd": 0.0}
			Terrain.ELECTRIC_FENCE:
				_traps[bidx] = {"type": "electric_fence", "cd": 0.0}
			Terrain.TURRET:
				_turrets[bidx] = _new_turret(c)
				_onboard("first_turret", "Turret placed. Inside the Tree's aura it needs no fuel. Outside, run a wire or feed it wine. It fires on its own at night.", 6.0)
		_energy = maxf(0.0, _energy - ENERGY_BUILD)
		_fx_build(c)
		play_sfx("build")
		queue_redraw()
	elif _drag_action == BuildAction.DESTROY:
		var t := _terrain_at(c)
		var key := _structure_key_for_terrain(t)
		if key == "":
			return
		# A glapple lamp gives back parts (its glapple has rotted into rot).
		if t == Terrain.GLAPPLE_LAMP:
			_remove_lamp(_cell_index(c))
			_energy = maxf(0.0, _energy - ENERGY_BUILD)
			queue_redraw()
			return
		if t == Terrain.STORAGE:
			var idx := _cell_index(c)
			var contents: Dictionary = _storage.get(idx, {})
			for r in contents:
				_resources[r] = _inv(r) + int(contents[r])
			_storage.erase(idx)
			if _docked_station == idx:
				_clear_docked_station()
		var didx := _cell_index(c)
		_struct_hp.erase(didx)
		_turrets.erase(didx)
		_trap_cd.erase(didx)
		_traps.erase(didx)
		_barrels.erase(didx)
		_juicers.erase(didx)
		_planters.erase(didx)
		_kilns.erase(didx)
		_apiaries.erase(didx)
		_wormfarms.erase(didx)
		_campfires.erase(didx)
		_stills.erase(didx)
		_generators.erase(didx)
		_lamps.erase(didx)   # electric bulbs live here too
		_sprinklers.erase(didx)
		_aquariums.erase(didx)
		_miners.erase(didx)
		_autoloaders.erase(didx)
		if _docked_station == didx:
			_clear_docked_station()
		_refund(STRUCTURES[key]["cost"])
		_set_terrain(c, Terrain.IRON_VEIN if t == Terrain.AUTO_MINER else Terrain.GRASS)
		_energy = maxf(0.0, _energy - ENERGY_BUILD)
		queue_redraw()


# Active light sources in the world (lit lamps now; oil/electric lights join later).
func _light_sources() -> Array:
	var out := []
	for idx in _lamps:
		var lm: Dictionary = _lamps[idx]
		var k: String = lm["kind"]
		var lit: bool = (not lm["dead"]) if k != "electric" else _is_powered(_index_cell(idx))
		if lit:
			out.append({
				"pos": _cell_center_world(_index_cell(idx)),
				"radius": float(LAMP_RADIUS.get(k, CELL_SIZE * 3.0)),
				"color": LAMP_COLOR.get(k, Color.WHITE),
			})
	return out


# Tear down a glapple lamp: hand back a wooden rod plus the rot its glapple became.
func _remove_lamp(idx: int) -> void:
	_lamps.erase(idx)
	_set_terrain(_index_cell(idx), Terrain.GRASS)
	_give_item("wooden_rod", 1)
	_give_item("rot", 1)
	_mark_workspace_dirty()


func _structure_key_for_terrain(t: int) -> String:
	for key in STRUCTURE_ORDER:
		if STRUCTURES[key]["terrain"] == t:
			return key
	return ""


func _tile_def(t: int) -> Dictionary:
	return TILE_DEF.get(t, {})


func _tile_player_walk(t: int) -> bool:
	return bool(_tile_def(t).get("player_walk", false))


func _tile_monster_walk(t: int) -> bool:
	return bool(_tile_def(t).get("monster_walk", false))


func _tile_break_hp(t: int) -> int:
	return int(_tile_def(t).get("break_hp", 0))


func _tile_armor(t: int) -> int:
	return int(_tile_def(t).get("armor", 0))


func _tile_impassable(t: int) -> bool:
	return bool(_tile_def(t).get("impassable", false))


func _tile_on_break(t: int) -> int:
	return int(_tile_def(t).get("on_break", Terrain.GRASS))


# --- Tier tech-gating --------------------------------------------------------
# Required Tree tier for each gated thing (1 = always available).
func _struct_required_tier(key: String) -> int:
	return int(FP_STRUCT_TIER.get(key, 1))


func _turret_required_tier(ty: String) -> int:
	return int(FP_TURRET_TIER.get(ty, 1))


func _craft_required_tier(key: String) -> int:
	return int(FP_CRAFT_TIER.get(key, 1))


# True iff the gated thing is buildable at the CURRENT Tree tier. Enforced both
# ways: a tier downgrade re-locks anything above the new tier.
func _struct_tier_ok(key: String) -> bool:
	return _tree_tier >= _struct_required_tier(key)


func _turret_tier_ok(ty: String) -> bool:
	return _tree_tier >= _turret_required_tier(ty)


func _craft_tier_ok(key: String) -> bool:
	return _tree_tier >= _craft_required_tier(key)


func _near_workbench() -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var c := _cell + Vector2i(ox, oy)
			if _in_bounds(c) and _terrain_at(c) == Terrain.WORKBENCH:
				return true
	return false


func _near_iron_vein() -> bool:
	for oy in range(-3, 4):
		for ox in range(-3, 4):
			var c := _cell + Vector2i(ox, oy)
			if _in_bounds(c) and _terrain_at(c) == Terrain.IRON_VEIN:
				return true
	return false


func _can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if _inv(k) < int(cost[k]):
			return false
	return true


func _spend(cost: Dictionary) -> void:
	for k in cost:
		_resources[k] = _inv(k) - int(cost[k])


func _refund(cost: Dictionary) -> void:
	for k in cost:
		_resources[k] = _inv(k) + int(cost[k])


func _discount_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = maxi(1, int(ceil(float(cost[k]) * 0.5)))
	return out


func _repair_cost_for_terrain(t: int) -> Dictionary:
	var key := _structure_key_for_terrain(t)
	if key == "":
		return {"wood": 1}
	return _discount_cost(STRUCTURES[key]["cost"])


func _repair_structure(idx: int) -> void:
	if idx < 0 or idx >= _terrain.size():
		return
	var t := int(_terrain[idx])
	if t == Terrain.TURRET and _turrets.has(idx):
		_turret_repair(idx)
		return
	if t == Terrain.WRECK and _wrecks.has(idx):
		var old_t := int(_wrecks[idx]["terrain"])
		var cost := _repair_cost_for_terrain(old_t)
		if not _can_afford(cost):
			_set_msg("Need %s to rebuild." % _cost_text(cost))
			return
		_spend(cost)
		_wrecks.erase(idx)
		_set_terrain(_index_cell(idx), old_t)
		_init_structure_state(idx, old_t)
		_struct_hp.erase(idx)
		_fx_build(_index_cell(idx), true)
		play_sfx("repair")
		_mark_workspace_dirty()
		queue_redraw()
		return
	if _tile_break_hp(t) <= 0 or not _struct_hp.has(idx):
		return
	var repair_cost := _repair_cost_for_terrain(t)
	if not _can_afford(repair_cost):
		_set_msg("Need %s to repair." % _cost_text(repair_cost))
		return
	_spend(repair_cost)
	_struct_hp.erase(idx)
	_fx_build(_index_cell(idx), true)   # cyan "mended" flash, no thunk shake
	play_sfx("repair")
	_mark_workspace_dirty()
	queue_redraw()


func _init_structure_state(idx: int, terrain: int) -> void:
	var c := _index_cell(idx)
	match terrain:
		Terrain.STORAGE:
			_storage[idx] = _new_storage_box()
		Terrain.BARREL:
			_barrels[idx] = {"kind": "", "amount": 0, "ferment": 0.0}
		Terrain.JUICER:
			_juicers[idx] = {"juice": 0, "pending": 0, "conv": 0.0}
		Terrain.PLANTER:
			_planters[idx] = {"planted": false, "berries": 0, "grow": 0.0, "wet": 0.0}
		Terrain.GLAPPLE_LAMP:
			_lamps[idx] = {"kind": "glapple", "life": LAMP_LIFE, "dead": false}
		Terrain.KILN:
			_kilns[idx] = {"fuel": 0.0, "queue": [], "conv": 0.0}
		Terrain.BEE_ENCLOSURE:
			_apiaries[idx] = {"bees": 0, "prod": 0.0, "starve": 0.0}
		Terrain.WORM_FARM:
			_wormfarms[idx] = {"worms": 0, "rot": 0, "mult": 0.0, "compost": 0.0}
		Terrain.CAMPFIRE:
			_campfires[idx] = {"item": "", "cook": 0.0}
		Terrain.STILL:
			_stills[idx] = {"pending": 0, "conv": 0.0}
		Terrain.GENERATOR:
			_generators[idx] = {"oil": 0, "on": false, "drain": 0.0}
		Terrain.BULB:
			_lamps[idx] = {"kind": "electric", "life": 0.0, "dead": false}
		Terrain.SPRINKLER:
			_sprinklers[idx] = {}
		Terrain.AQUARIUM:
			_aquariums[idx] = {"males": 0, "females": 0, "eggs": 0, "quality": 100.0, "water": 0, "feed": 0.0, "breed": 0.0}
		Terrain.AUTO_MINER:
			_miners[idx] = {"t": 0.0}
		Terrain.AUTO_LOADER:
			_autoloaders[idx] = {"t": 0.0}
		Terrain.LAND_MINE:
			_traps[idx] = {"type": "land_mine"}
		Terrain.PEEL_LAUNCHER:
			_traps[idx] = {"type": "peel_launcher", "hp": TRAP_MAX_HP["peel_launcher"], "ammo": 0, "cd": 0.0}
		Terrain.ELECTRIC_FENCE:
			_traps[idx] = {"type": "electric_fence", "cd": 0.0}
		Terrain.TURRET:
			_turrets[idx] = _new_turret(c)


func _deposit_sap(kind: String, qty: int) -> void:
	if qty <= 0 or not FP_SAP_CONVERSION.has(kind):
		return
	var take: int = mini(qty, _inv(kind))
	if take <= 0:
		_set_msg("Need %s to deposit." % ITEM_LABELS.get(kind, kind))
		return
	_resources[kind] = _inv(kind) - take
	_sap += float(FP_SAP_CONVERSION[kind]) * float(take)
	_try_tree_tier_up()
	_mark_workspace_dirty()


func _sweep_casings() -> void:
	if _is_night:
		_set_msg("Sweep casings after dawn.")
		return
	var n := _casings.size()
	if n <= 0:
		return
	_casings.clear()
	_resources["casing"] = _inv("casing") + n
	_mark_workspace_dirty()


# -----------------------------------------------------------------------------
# Movement / interact / harvest / eat
# -----------------------------------------------------------------------------
# Move a circle (radius hs) by `motion`, resolved per-axis so it slides along
# blocking tiles. `walkset` is the set of terrains this body may stand on.
# Continuous collide-and-slide. `monster` picks the TILE_DEF walkability lane
# (monster_walk vs player_walk) so the collider always agrees with the pather.
func _move_collide(pos: Vector2, motion: Vector2, hs: float, monster: bool) -> Vector2:
	var p := pos
	var nx := Vector2(p.x + motion.x, p.y)
	if not _box_blocked(nx, hs, monster):
		p = nx
	var ny := Vector2(p.x, p.y + motion.y)
	if not _box_blocked(ny, hs, monster):
		p = ny
	return p


func _box_blocked(center: Vector2, hs: float, monster: bool) -> bool:
	var minx := int(floor((center.x - hs) / CELL_SIZE))
	var maxx := int(floor((center.x + hs) / CELL_SIZE))
	var miny := int(floor((center.y - hs) / CELL_SIZE))
	var maxy := int(floor((center.y + hs) / CELL_SIZE))
	for cy in range(miny, maxy + 1):
		for cx in range(minx, maxx + 1):
			var c := Vector2i(cx, cy)
			if not _in_bounds(c):
				return true
			var t := _terrain_at(c)
			if not (_tile_monster_walk(t) if monster else _tile_player_walk(t)):
				return true
	return false


func _cardinal(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(1 if v.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if v.y > 0.0 else -1)


func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(floor(p.x / CELL_SIZE)), 0, GRID_CELLS - 1),
		clampi(int(floor(p.y / CELL_SIZE)), 0, GRID_CELLS - 1)
	)


# Left-click in the world: interact with an adjacent object, else (at night) punch.
func _on_left_click_world() -> void:
	if _downed:
		return
	var c := _mouse_cell()
	if _click_interact(c):
		return
	if _is_night:
		if bool(_weapon().get("ranged", false)):
			_fire_slingshot(get_global_mouse_position())
		else:
			_start_punch(get_global_mouse_position())


# Interact with an adjacent interactable tile (gatherable resource or storage).
# Never used for anything combat-related. Returns true if it handled the click.
func _click_interact(c: Vector2i) -> bool:
	if not _in_bounds(c) or _chebyshev(_cell, c) > 1:
		return false
	var t := _terrain_at(c)
	if t == Terrain.STORAGE:
		_toggle_storage(_cell_index(c))
		return true
	if t == Terrain.MOTHER_TREE:
		_active_overlay = Overlay.TECH
		_mark_workspace_dirty()
		return true
	if t == Terrain.BARREL or t == Terrain.JUICER or t == Terrain.PLANTER or t == Terrain.KILN \
			or t == Terrain.BEE_ENCLOSURE or t == Terrain.WORM_FARM or t == Terrain.CAMPFIRE or t == Terrain.STILL \
			or t == Terrain.GENERATOR or t == Terrain.AQUARIUM or t == Terrain.SPRINKLER \
			or t == Terrain.AUTO_MINER or t == Terrain.AUTO_LOADER or t == Terrain.PEEL_LAUNCHER:
		_toggle_util(_cell_index(c))
		return true
	if t == Terrain.HIVE:
		_harvest_hive(c)
		return true
	if t == Terrain.TURRET:
		_toggle_turret(_cell_index(c))
		return true
	if t == Terrain.GLAPPLE_LAMP:
		var idx := _cell_index(c)
		if _lamps.has(idx) and _lamps[idx]["dead"]:
			_remove_lamp(idx)   # burnt out -> salvage rod + rot
		else:
			_set_msg("The glapple lamp is still glowing.")
		return true
	if t == Terrain.WRECK or (_tile_break_hp(t) > 0 and _struct_hp.has(_cell_index(c))):
		_repair_structure(_cell_index(c))
		return true
	# Gathering is allowed day or night (at night there's nothing natural to gather).
	if t == Terrain.TREE or t == Terrain.STONE or t == Terrain.BUSH \
			or t == Terrain.COCONUT or t == Terrain.BAMBOO or t == Terrain.SAND:
		_harvest_cell(c)
		return true
	# Pull grass fibers (day only) -- the raw material for string.
	if not _is_night and t == Terrain.GRASS:
		_resources["grass"] = _inv("grass") + 1
		_facing = _cardinal(Vector2(c - _cell))
		_energy = maxf(0.0, _energy - ENERGY_HARVEST * 0.5)
		queue_redraw()
		return true
	# Scoop water into an empty cup, or grab a fish (day only -- never at night).
	if t == Terrain.WATER:
		if _is_night:
			_set_msg("The pool is too dangerous at night.")
			return true
		if _try_catch_fish(_cell_center_world(c)):
			return true
		_fill_cup_from_pool()
		return true
	return false


# Catch a fish swimming near `where`; returns true if one was landed.
func _try_catch_fish(where: Vector2) -> bool:
	for i in range(_fish.size()):
		if (_fish[i]["pos"] as Vector2).distance_to(where) <= FISH_CATCH_R:
			var sex: String = _fish[i]["sex"]
			_give_item("fish_m" if sex == "m" else "fish_f", 1)
			_fish.remove_at(i)
			_energy = maxf(0.0, _energy - ENERGY_HARVEST * 0.5)
			queue_redraw()
			return true
	return false


func _fill_cup_from_pool() -> void:
	if _inv("cup") <= 0:
		_set_msg("Need an empty cup to scoop water.")
		return
	_resources["cup"] = _inv("cup") - 1
	_resources["cup_water"] = _inv("cup_water") + 1
	_energy = maxf(0.0, _energy - ENERGY_HARVEST * 0.5)


func _set_msg(text: String) -> void:
	_msg = text
	_msg_timer = 2.5
	_msg_onboard = false


# Longer-dwell banner for onboarding copy. Identical to _set_msg but holds for `secs`
# and flags the banner as an instructional (blue, 2-line) beat.
func _set_msg_long(text: String, secs: float) -> void:
	_msg = text
	_msg_timer = secs
	_msg_onboard = true


# One-shot teaching beat. Fires at most once ever (persisted in _onboard_seen). If a
# banner is already dwelling, the beat is queued (drained when _msg_timer hits 0) so a
# concurrent threat/SFX line never eats the tutorial. Mode-B juice goes in the FX hook.
func _onboard(id: String, text: String, secs: float = 5.0) -> void:
	if _onboard_seen.get(id, false):
		return
	_onboard_seen[id] = true
	_fx_onboard_beat(id)
	if _msg_timer > 0.0:
		_msg_queue.append({"text": text, "secs": secs})
	else:
		_set_msg_long(text, secs)


# Mode-B hook: animated slide-in / icon / typewriter reveal for an onboarding beat.
# Empty for now (mirrors _fx_dusk_enter / _fx_night_incoming); the plain 2-line
# recolored banner ships today.
func _fx_onboard_beat(_id: String) -> void:
	pass


# Hard-banded HP color: green >=50%, amber 25-50%, red <25%. Shared by the Tree HP
# bar, per-Den ledger bars, and the Dens-alive count so "danger" reads at a glance.
func _hp_color(frac: float) -> Color:
	if frac >= 0.5:
		return HP_GREEN
	elif frac >= 0.25:
		return HP_AMBER
	return HP_RED


# Monotonic wall-clock seconds, used for the NEW-marker timeout window.
func _now_secs() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# --- Drinking + crafting -----------------------------------------------------
func _drink(kind: String) -> void:
	if _inv(kind) <= 0 or not DRINKS.has(kind):
		return
	var eff: Array = DRINKS[kind]
	_hydration = minf(HYDRATION_MAX, _hydration + float(eff[0]))
	var before_hp := _health
	_health = minf(_p_max_health, _health + float(eff[1]))
	if _health > before_hp:
		_fx_damage_number(_player_pos + Vector2(0, -CELL_SIZE * 0.4), _health - before_hp, "heal")
	_energy = minf(ENERGY_MAX, _energy + float(eff[2]))
	_resources[kind] = _inv(kind) - 1
	_resources["cup"] = _inv("cup") + 1   # cup returns empty
	_mark_workspace_dirty()


func _drink_best() -> void:
	for kind in ["cup_water", "cup_juice", "cup_wine"]:
		if _inv(kind) > 0:
			_drink(kind)
			return


func _empty_cup(kind: String) -> void:
	if _inv(kind) <= 0:
		return
	_resources[kind] = _inv(kind) - 1
	_resources["cup"] = _inv("cup") + 1
	_mark_workspace_dirty()


func _craft(key: String) -> void:
	var r: Dictionary = CRAFT_RECIPES[key]
	if not _craft_tier_ok(key):
		_onboard("tier_locked", "Locked -- needs Mother Tree tier %d. Feed the Tree Sap at its hub to grow it and unlock this." % _craft_required_tier(key), 6.0)
		return
	var rot_cost := int(r.get("rot", 0))
	var fish_cost := int(r.get("fish", 0))
	if not _can_afford(r["cost"]) or (rot_cost > 0 and _rot_total() < rot_cost) \
			or (fish_cost > 0 and _fish_total() < fish_cost):
		_set_msg("Not enough materials.")
		return
	_spend(r["cost"])
	if rot_cost > 0:
		_consume_rot(rot_cost)    # glue rendered from any spoiled fruit
	if fish_cost > 0:
		_consume_fish(fish_cost)  # a skewer takes any mix of fish
	if r.has("armor"):
		_gear_armor = minf(HIDE_ARMOR_CAP, _gear_armor + float(r["armor"]))
		_recompute_player_stats()
	if String(r["out"]) != "":
		_resources[r["out"]] = _inv(r["out"]) + int(r.get("out_count", 1))
	_mark_workspace_dirty()


# --- Equipment ---------------------------------------------------------------
# Toggle a tool/weapon into its slot (clicking the equipped one bares fists again).
func _equip(kind: String) -> void:
	if _inv(kind) <= 0:
		return
	if kind in TOOL_ITEMS:
		_tool_equipped = "" if _tool_equipped == kind else kind
	elif kind in WEAPON_ITEMS:
		_weapon_equipped = "" if _weapon_equipped == kind else kind
	_mark_workspace_dirty()


func _weapon() -> Dictionary:
	return WEAPON_DEFS.get(_weapon_equipped, WEAPON_DEFS[""])


# Extra wood/stone a swing yields with the equipped tool (0 with bare hands).
func _tool_bonus() -> int:
	return int(TOOL_DEFS[_tool_equipped]["bonus"]) if TOOL_DEFS.has(_tool_equipped) else 0


func _tool_energy_mult() -> float:
	return float(TOOL_DEFS[_tool_equipped]["energy"]) if TOOL_DEFS.has(_tool_equipped) else 1.0


# Fire the slingshot toward a world point, spending one sling ammo.
func _fire_slingshot(aim_world: Vector2) -> void:
	if _inv("sling_ammo") <= 0:
		_set_msg("Out of sling ammo."); return
	var dir := aim_world - _player_pos
	dir = dir.normalized() if dir.length() > 1.0 else Vector2(_facing)
	_resources["sling_ammo"] = _inv("sling_ammo") - 1
	_facing = _cardinal(dir)
	var dmg: float = _p_attack * float(WEAPON_DEFS["slingshot"]["dmg"])
	_projectiles.append({
		"pos": _player_pos + dir * PLAYER_RADIUS, "vel": dir * SLING_PROJ_SPEED,
		"kind": "sling", "owner": "player", "dmg": dmg, "kb": float(WEAPON_DEFS["slingshot"]["kb"]),
	})


# Spoiled matter, treated uniformly (any rotten fruit) for glue/compost recipes.
func _rot_total() -> int:
	return _inv("rotten_banana") + _inv("rotten_berry") + _inv("rot")


func _consume_rot(n: int) -> void:
	for kind in ["rotten_banana", "rotten_berry", "rot"]:
		if n <= 0:
			break
		var take: int = mini(n, _inv(kind))
		if take > 0:
			_resources[kind] = _inv(kind) - take
			n -= take


# Caught fish of either sex, treated uniformly for cooking.
func _fish_total() -> int:
	return _inv("fish_m") + _inv("fish_f")


func _consume_fish(n: int) -> void:
	for kind in ["fish_m", "fish_f"]:
		if n <= 0:
			break
		var take: int = mini(n, _inv(kind))
		if take > 0:
			_resources[kind] = _inv(kind) - take
			n -= take


func _harvest_cell(c: Vector2i) -> void:
	var t := _terrain_at(c)
	var idx := _cell_index(c)
	if t == Terrain.TREE:
		if _banana[idx] == 1:
			_banana[idx] = 0
			_resources["banana"] = _inv("banana") + 1
		else:
			_set_terrain(c, Terrain.STUMP)
			_resources["wood"] = _inv("wood") + 2 + _tool_bonus()
	elif t == Terrain.BUSH:
		if _berry[idx] > 0:
			_resources["berry"] = _inv("berry") + _berry[idx]   # collect every berry at once
			_resources["seed"] = _inv("seed") + 1               # berries carry a seed
			_berry[idx] = 0
		else:
			return   # bare bush -- nothing to pick yet (it regrows)
	elif t == Terrain.COCONUT:
		if _banana[idx] == 1:                       # _banana doubles as "fruit present"
			_banana[idx] = 0
			_resources["coconut"] = _inv("coconut") + 1
		else:
			_set_terrain(c, Terrain.STUMP)
			_resources["wood"] = _inv("wood") + 2 + _tool_bonus()
	elif t == Terrain.BAMBOO:
		_set_terrain(c, Terrain.GRASS)
		_resources["bamboo"] = _inv("bamboo") + 2   # a clump yields a couple of canes
	elif t == Terrain.SAND:
		_resources["sand"] = _inv("sand") + 1        # the beach is an endless sand source
		# (tile stays sand; energy is the only limit)
	elif t == Terrain.STONE:
		_set_terrain(c, Terrain.GRASS)
		_resources["stone"] = _inv("stone") + 2 + _tool_bonus()
		if randf() < ORE_DROP_CHANCE:               # rocks sometimes hide metal ore
			_resources["metal_ore"] = _inv("metal_ore") + 1
		if randf() < FP_WORM_DROP_CHANCE:            # rarely disturb one jar-catchable worm
			_spawn_loot("worm", 1, _cell_center_world(c))
	else:
		return
	_facing = _cardinal(Vector2(c - _cell))
	_energy = maxf(0.0, _energy - ENERGY_HARVEST * _tool_energy_mult())
	queue_redraw()


# --- Punch (night melee, with a built-in out-and-back delay) ------------------
func _start_punch(aim_world: Vector2) -> void:
	if _downed or not _is_night or _punch_active or _build_mode or _freeze_t > 0.0:
		return
	var d := aim_world - _player_pos
	_punch_dir = d.normalized() if d.length() > 1.0 else Vector2(_facing)
	_facing = _cardinal(_punch_dir)
	_punch_active = true
	_punch_t = 0.0
	_punch_hit = false


# Extension 0..1: rises during the first half (extend), falls in the second (retract).
func _punch_ext(t: float) -> float:
	return t / 0.5 if t < 0.5 else (1.0 - t) / 0.5


func _fist_pos() -> Vector2:
	return _player_pos + _punch_dir * (PLAYER_RADIUS + _punch_ext(_punch_t) * PUNCH_REACH * float(_weapon()["reach"]))


func _update_punch(delta: float) -> void:
	if not _punch_active:
		return
	# Aim tracks the cursor in real time (twin-stick / shooter-style aiming).
	var aim := get_global_mouse_position() - _player_pos
	if aim.length() > 1.0:
		_punch_dir = aim.normalized()
		_facing = _cardinal(_punch_dir)
	_punch_t += delta / (PUNCH_TIME * float(_weapon()["time"]))
	if _punch_t >= 1.0:
		_punch_active = false
		return
	# Only the fist can connect, and only once per punch.
	if not _punch_hit:
		var fist := _fist_pos()
		for m in _monsters:
			if m["hp"] <= 0.0 or m.get("dig", false):
				continue  # can't punch a corpse or a burrowed croc
			if fist.distance_to(m["pos"]) <= FIST_R + MONSTER_RADIUS:
				var kd: Vector2 = (m["pos"] - _player_pos)
				var wpn := _weapon()
				_hurt_croc(m, _p_attack * float(wpn["dmg"]), kd if kd.length() > 0.01 else _punch_dir, float(wpn["kb"]), "player")
				_punch_hit = true
				_spark_pos = fist
				_spark_t = 0.0
				_add_shake(4.0)
				_hitstop = maxf(_hitstop, HITSTOP_HIT)
				break
		if not _punch_hit:
			var dc := _world_to_cell(fist)
			if _in_bounds(dc) and _terrain_at(dc) == Terrain.CROC_DEN:
				var wpn := _weapon()
				_damage_den_at(dc, _p_attack * float(wpn["dmg"]))
				_punch_hit = true
				_spark_pos = fist
				_spark_t = 0.0
				_add_shake(4.0)
				_hitstop = maxf(_hitstop, HITSTOP_HIT)


func _try_eat() -> void:
	# A coconut is the prize snack -- it feeds AND hydrates, and leaves a shell.
	if _inv("coconut") > 0 and (_energy < ENERGY_MAX or _hydration < HYDRATION_MAX):
		_resources["coconut"] = _inv("coconut") - 1
		_energy = minf(ENERGY_MAX, _energy + COCONUT_ENERGY)
		_hydration = minf(HYDRATION_MAX, _hydration + COCONUT_HYDRATION)
		_give_item("coconut_shell", 1)
		return
	if _energy >= ENERGY_MAX:
		return
	# A cooked skewer is the heartiest meal (3 fish worth) and leaves bones.
	if _inv("cooked_skewer") > 0:
		_resources["cooked_skewer"] = _inv("cooked_skewer") - 1
		_energy = minf(ENERGY_MAX, _energy + FISH_ENERGY * 3.0 * 1.4)
		_give_item("fish_bones", 3)
		return
	# Raw fish: a banana's worth of food, no hydration, leaves a bone.
	for fkind in ["fish_m", "fish_f"]:
		if _inv(fkind) > 0:
			_resources[fkind] = _inv(fkind) - 1
			_energy = minf(ENERGY_MAX, _energy + FISH_ENERGY)
			_give_item("fish_bones", 1)
			return
	# Eat the freshest snack available; rotten food can never be eaten.
	for kind in ["berry", "banana"]:   # nibble berries first, then bananas
		if int(_resources.get(kind, 0)) > 0:
			_resources[kind] -= 1
			_energy = minf(ENERGY_MAX, _energy + float(EAT_ENERGY[kind]))
			if kind == "banana":
				_give_item("banana_peel", 1)   # the peel is left over (peel-launcher ammo)
			return


# Add loot to the inventory; anything we don't track in INV_ORDER (or overflow,
# later) spills onto the ground instead so it's never silently lost.
func _give_item(kind: String, count: int) -> void:
	if count <= 0:
		return
	if kind in INV_ORDER:
		_resources[kind] = _inv(kind) + count
	else:
		_spawn_loot(kind, count, _player_pos)


# Drop loot on the ground at `pos`; the player vacuums it up by walking near.
func _spawn_loot(kind: String, count: int, pos: Vector2) -> void:
	if count <= 0:
		return
	var jitter := Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	_ground_items.append({"pos": pos + jitter, "kind": kind, "count": count, "t": 0.0})


# Vacuum up any ground loot the player is standing near (called every frame).
func _collect_ground_items(delta: float) -> void:
	if _ground_items.is_empty():
		return
	var keep := []
	for g in _ground_items:
		g["t"] = float(g["t"]) + delta
		if float(g["t"]) >= GROUND_ITEM_TTL:
			continue
		if (g["pos"] as Vector2).distance_to(_player_pos) <= LOOT_PICKUP_R + PLAYER_RADIUS:
			var kind: String = g["kind"]
			# Live critters (worm/bee) can only be scooped up if you have a glass jar.
			if kind == "worm" or kind == "bee":
				if _inv("glass_jar") <= 0:
					keep.append(g)   # no jar -> leave it crawling/buzzing
					continue
				_resources["glass_jar"] = _inv("glass_jar") - 1
			if kind in INV_ORDER:
				_resources[kind] = _inv(kind) + int(g["count"])
			# (an item not in INV_ORDER simply can't be carried; it stays dropped)
			else:
				keep.append(g)
				continue
			_poofs.append({"pos": g["pos"], "t": 0.5})   # small pickup sparkle
		else:
			keep.append(g)
	_ground_items = keep


# --- Inventory helpers + spoilage --------------------------------------------
func _default_inventory() -> Dictionary:
	var d := {}
	for k in INV_ORDER:
		d[k] = 0
	return d


func _new_storage_box() -> Dictionary:
	return _default_inventory()


func _inv(kind: String) -> int:
	return int(_resources.get(kind, 0))


func _delete_item(kind: String, all: bool) -> void:
	if _inv(kind) <= 0:
		return
	_resources[kind] = 0 if all else _inv(kind) - 1
	_mark_workspace_dirty()


func _delete_box_item(idx: int, kind: String, all: bool) -> void:
	if not _storage.has(idx):
		return
	var box: Dictionary = _storage[idx]
	if int(box.get(kind, 0)) <= 0:
		return
	box[kind] = 0 if all else int(box[kind]) - 1
	_mark_workspace_dirty()


# Roll spoilage on the player's loose food (storage acts as cold storage).
func _decay_tick(delta: float) -> void:
	_decay_timer += delta
	if _decay_timer < DECAY_INTERVAL:
		return
	_decay_timer -= DECAY_INTERVAL
	for fresh in PERISHABLE:
		var rotten: String = PERISHABLE[fresh]
		var chance: float = float(DECAY_CHANCE.get(fresh, BANANA_DECAY_CHANCE))
		if _inv(fresh) > 0 and randf() < chance:
			_resources[fresh] -= 1
			_resources[rotten] = _inv(rotten) + 1
	# An unplaced glapple lamp dies too -- its glapple rots, the rod survives.
	if _inv("glapple_lamp") > 0 and randf() < GLAPPLE_LAMP_DECAY_CHANCE:
		_resources["glapple_lamp"] = _inv("glapple_lamp") - 1
		_give_item("rot", 1)
		_give_item("wooden_rod", 1)
	# Loose berry juice spoils (the juice rots away; the cup comes back empty).
	if _inv("cup_juice") > 0:
		_juice_spoil_t += DECAY_INTERVAL
		if _juice_spoil_t >= CUP_JUICE_SPOIL:
			_juice_spoil_t = 0.0
			_resources["cup_juice"] = _inv("cup_juice") - 1
			_resources["cup"] = _inv("cup") + 1
	else:
		_juice_spoil_t = 0.0


# --- Combat juice ------------------------------------------------------------
func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func play_sfx(_id: String) -> void:
	pass


# A croc bursts: layered green gut-splat ring + chunk debris (with two bone-pale
# teeth) + a hard white contact kernel, on top of the base poof already spawned at
# the call-site (§1). All randomness baked into seed so _draw stays deterministic.
func _fx_croc_death(pos: Vector2) -> void:
	var s := randi()
	_fx.append({"kind": "croc_gore", "pos": pos, "t": 0.0, "life": FX_GORE_LIFE, "seed": s})
	_fx.append({"kind": "croc_chunks", "pos": pos, "t": 0.0, "life": FX_CHUNK_LIFE, "seed": s})
	_fx.append({"kind": "flash_dot", "pos": pos, "t": 0.0, "life": FX_FLASH_LIFE, "seed": s})


# A croc gnaws a structure: tiny, cheap splinter star + dust puff (§2). Fires a lot
# during a siege, so no shake and a short life so a wall under assault sparkles at
# its edge instead of strobing. The state-darkening is the _struct_hp overlay's job.
func _fx_wall_hit(cell: Vector2i) -> void:
	_fx.append({"kind": "wall_hit", "pos": _cell_center_world(cell), "t": 0.0, "life": FX_WALLHIT_LIFE, "seed": randi()})


# Placement flash (§4): a green slam-ring collapsing onto the cell + dust kick-out +
# a sparkle cross. repair recolors the ring cyan ("mended") and skips the thunk shake.
func _fx_build(cell: Vector2i, repair: bool = false) -> void:
	_fx.append({"kind": "build", "pos": _cell_center_world(cell), "t": 0.0, "life": FX_BUILD_LIFE,
		"seed": randi(), "repair": repair})
	if not repair:
		_add_shake(1.0)   # soft tactile thunk on a fresh build only


# The hero celebration (§5): a sunrise bloom from the 3x3 Tree footprint -- sunburst
# rays, two bloom rings, a leaf burst, a core glow, plus a canvas dawn-wash, a
# triumphant shake, and a floating gold "TIER n".
func _fx_tier_up() -> void:
	var c := _cell_center_world(_tree_center_cell())
	_fx.append({"kind": "tier_bloom", "pos": c, "t": 0.0, "life": FX_TIER_LIFE, "seed": randi()})
	_tier_glow = 1.0
	_apply_daylight()
	_add_shake(5.0)
	# Float a gold "TIER n" above the trunk via the dmgnum mechanism (gold channel).
	_fx.append({"kind": "dmgnum", "pos": c + Vector2(0, -CELL_SIZE * 1.6), "t": 0.0, "life": FX_TIER_LIFE,
		"amount": 0.0, "txt": "TIER %d" % _tree_tier, "channel": "tier", "seed": randi(), "hits": 1})


# Floating combat text (§3) with multi-hit aggregation: a fresh hit near a recent
# same-channel number folds into it (sum amount, reset t to re-pop, bump hits),
# collapsing a turret's shredding flurry into one growing, re-punching tally.
func _fx_damage_number(pos: Vector2, amount: float, kind: String) -> void:
	var n := int(round(amount))
	if n == 0:
		return
	for e in _fx:
		if e.get("kind", "") != "dmgnum":
			continue
		if e.get("channel", "") != kind:
			continue
		if float(e["t"]) >= FX_DMGNUM_AGG_T:
			continue
		if (e["pos"] as Vector2).distance_to(pos) > FX_DMGNUM_AGG_DIST:
			continue
		e["amount"] = float(e["amount"]) + float(n)
		e["t"] = 0.0                              # re-pop: re-triggers the overshoot
		e["hits"] = int(e.get("hits", 1)) + 1
		return
	_fx.append({"kind": "dmgnum", "pos": pos, "t": 0.0, "life": FX_DMGNUM_LIFE,
		"amount": float(n), "channel": kind, "seed": randi(), "hits": 1})


# Dusk onset (§6): announce the warning and arm the countdown clock. The canvas
# warming + spawn-warn rings are driven separately (dusk_active / night_incoming).
func _fx_dusk_enter() -> void:
	_dusk_active = true
	_clock_flash = 1.0
	_clock_last_beat = -1
	_set_msg("DUSK -- the horde stirs")
	# A subtle wide golden horizon sweep across the board (optional flourish).
	_fx.append({"kind": "dusk_sweep", "pos": _cell_center_world(_tree_center_cell()),
		"t": 0.0, "life": FX_DUSK_SWEEP_LIFE, "seed": randi()})
	if _clock_ctrl:
		_clock_ctrl.visible = true
		_clock_ctrl.queue_redraw()


# Final 10-second alarm (§7): escalate, paint spawn-preview rings at the exact
# Den/shore cells where crocs will surface, and a heartbeat thud.
func _fx_night_incoming() -> void:
	_clock_flash = 1.0
	_set_msg("NIGHT IN 0:10")
	_add_shake(2.0)
	# Pulsing red ground rings where _spawn_monsters will surface crocs (cap cost).
	var cells := _den_spawn_cells()
	var n := mini(cells.size(), 24)
	for i in range(n):
		_fx.append({"kind": "spawn_warn", "pos": _cell_center_world(cells[i]),
			"t": 0.0, "life": FX_SPAWNWARN_LIFE, "seed": randi()})
	if _clock_ctrl:
		_clock_ctrl.queue_redraw()


# Continuous dusk-window animation state (§6-8), recomputed every frame from
# _time so it self-heals on load/seek. The one-shot _fx_dusk_enter/_incoming hooks
# (fired from _update_dusk_telegraph) arm the banners/rings; this keeps the phase,
# the canvas warming, the per-second clock flashes, and the clock redraw live.
func _update_dusk_state(_delta: float) -> void:
	var active := _time >= 0.68 and _time < 0.78
	if active != _dusk_active:
		_dusk_active = active
		if _clock_ctrl:
			_clock_ctrl.visible = active
			_clock_ctrl.queue_redraw()
		if not active:
			_clock_last_beat = -1
	if not _dusk_active:
		return
	_dusk_phase = clampf((_time - 0.68) / 0.10, 0.0, 1.0)
	_apply_daylight()                       # sunset->moonrise warming follows the phase
	# Re-kick the clock pulse on each whole-second tick of the final countdown.
	var secs_left := (0.78 - _time) * DAY_LENGTH
	var beat := int(ceil(secs_left))
	if secs_left <= 10.0 and beat != _clock_last_beat:
		_clock_last_beat = beat
		_clock_flash = 1.0
	if _clock_ctrl:
		_clock_ctrl.queue_redraw()          # the Control redraws itself each frame in-window


func _update_juice(delta: float) -> void:
	# Screen shake (applied on top of the camera's follow position).
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	if _shake > 0.0:
		_camera.position += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake

	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if _spark_t < 1.0:
		_spark_t = minf(1.0, _spark_t + delta / SPARK_TIME)

	var keep := []
	for p in _poofs:
		p["t"] += delta / POOF_TIME
		if p["t"] < 1.0:
			keep.append(p)
	_poofs = keep

	# One advance loop + one cull for the whole heterogeneous _fx list (§9.1).
	var fkeep := []
	for e in _fx:
		e["t"] += delta / float(e["life"])
		if float(e["t"]) < 1.0:
			fkeep.append(e)
	_fx = fkeep

	# Transient juice decays.
	_tier_glow = maxf(0.0, _tier_glow - delta / FX_TIER_GLOW_DECAY)
	_clock_flash = maxf(0.0, _clock_flash - delta / FX_CLOCK_FLASH_DECAY)
	if _tier_glow > 0.0:
		_apply_daylight()   # keep the dawn-wash blended in while it fades

	# Recompute the dusk window state from _time so it self-heals on load/seek.
	_update_dusk_state(delta)

	# Screen-space overlays.
	if _flash_rect:
		_flash_rect.color.a = clampf(_hurt_flash / (FLASH_TIME * 1.6), 0.0, 1.0) * 0.45
	if _vignette:
		var thr := _p_max_health * LOW_HP_FRAC
		var lowf := 0.0
		if _health < thr:
			lowf = clampf(1.0 - _health / thr, 0.0, 1.0)
		var pulse := 0.65 + 0.35 * sin(float(Time.get_ticks_msec()) / 220.0)
		_vignette.modulate.a = lowf * pulse


# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
func _toggle_storage(idx: int) -> void:
	_docked_station = -1 if _docked_station == idx else idx
	_mark_workspace_dirty()


func _close_storage() -> void:
	if _docked_station != -1 and _terrain[_docked_station] == Terrain.STORAGE:
		_docked_station = -1
		_mark_workspace_dirty()


func _toggle_util(idx: int) -> void:
	_docked_station = -1 if _docked_station == idx else idx
	_mark_workspace_dirty()


func _close_util() -> void:
	if _docked_station != -1 and _terrain[_docked_station] != Terrain.STORAGE and _terrain[_docked_station] != Terrain.TURRET:
		_docked_station = -1
		_mark_workspace_dirty()


func _clear_docked_station() -> void:
	if _docked_station != -1:
		_docked_station = -1
		_turret_pick_cat = ""
		_mark_workspace_dirty()


# Barrels ferment, juicers press, planters grow -- runs every frame, day or night.
# Rebuild the set of energized tiles (live generators + the wires they reach) and
# drain a little oil from each running generator.
func _compute_power(delta: float) -> void:
	_energized.clear()
	var frontier := []
	for idx in _generators:
		var g: Dictionary = _generators[idx]
		if bool(g.get("tree", false)):
			if _tree_hp > 0.0:
				for tc in _tree_cells():
					var ti := _cell_index(tc)
					_energized[ti] = true
					frontier.append(tc)
			continue
		if g["on"] and int(g["oil"]) > 0:
			g["drain"] = float(g["drain"]) + delta
			if g["drain"] >= GEN_DRAIN_TIME:
				g["drain"] = 0.0
				g["oil"] = int(g["oil"]) - 1
			if int(g["oil"]) > 0:
				_energized[idx] = true
				frontier.append(_index_cell(idx))
		else:
			g["drain"] = 0.0
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if _in_bounds(n) and _terrain_at(n) == Terrain.WIRE:
				var ni := _cell_index(n)
				if not _energized.has(ni):
					_energized[ni] = true
					frontier.append(n)


# Pipes that can trace a path back to the pool carry fresh water.
func _compute_water() -> void:
	_watered.clear()
	var frontier := []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Seed: any pipe touching water is a source.
	for i in range(_terrain.size()):
		if _terrain[i] == Terrain.PIPE:
			var c := _index_cell(i)
			for off in dirs:
				var n: Vector2i = c + off
				if _in_bounds(n) and _terrain_at(n) == Terrain.WATER:
					_watered[i] = true
					frontier.append(c)
					break
	while not frontier.is_empty():
		var c2: Vector2i = frontier.pop_back()
		for off in dirs:
			var n2: Vector2i = c2 + off
			if _in_bounds(n2) and _terrain_at(n2) == Terrain.PIPE:
				var ni := _cell_index(n2)
				if not _watered.has(ni):
					_watered[ni] = true
					frontier.append(n2)


# A machine has running water if it sits on, or next to, a watered pipe.
func _is_piped_water(cell: Vector2i) -> bool:
	for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + off
		if _in_bounds(n) and _watered.has(_cell_index(n)):
			return true
	return false


# A machine is powered if it sits on, or next to, an energized tile.
func _is_powered(cell: Vector2i) -> bool:
	if _energized.has(_cell_index(cell)):
		return true
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + off
		if _in_bounds(n) and _energized.has(_cell_index(n)):
			return true
	return false


func _generator_fuel(idx: int) -> void:
	var g: Dictionary = _generators[idx]
	if _inv("cup_oil") <= 0:
		_set_msg("Need a cup of berry oil."); return
	if int(g["oil"]) >= GEN_OIL_MAX:
		_set_msg("Generator tank is full."); return
	_resources["cup_oil"] = _inv("cup_oil") - 1
	_resources["cup"] = _inv("cup") + 1
	g["oil"] = int(g["oil"]) + 1
	_mark_workspace_dirty()


func _generator_toggle(idx: int) -> void:
	var g: Dictionary = _generators[idx]
	g["on"] = not bool(g["on"])
	_mark_workspace_dirty()


func _miner_tick(delta: float) -> void:
	for idx in _miners:
		var m: Dictionary = _miners[idx]
		m["t"] = float(m.get("t", 0.0)) + delta * (POWER_SPEED_MULT if _is_powered(_index_cell(idx)) else 1.0)
		while float(m["t"]) >= FP_AUTO_MINER_TICK:
			m["t"] = float(m["t"]) - FP_AUTO_MINER_TICK
			_give_item("stone", FP_AUTO_MINER_STONE)
			if randf() < FP_AUTO_MINER_ORE_CHANCE:
				_give_item("metal_ore", 1)


func _autoloader_tick(_delta: float) -> void:
	if _inv("gunpowder") <= 0:
		return
	for idx in _autoloaders:
		var lc: Vector2i = _index_cell(idx)
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var tc: Vector2i = lc + off
			if not _in_bounds(tc):
				continue
			var ti := _cell_index(tc)
			if not _turrets.has(ti):
				continue
			var t: Dictionary = _turrets[ti]
			var need := int(t.get("max_ammo", FP_TURRET_AMMO_MAX)) - int(t.get("ammo", 0))
			if need <= 0:
				continue
			var take := mini(need, _inv("gunpowder"))
			if take <= 0:
				return
			_resources["gunpowder"] = _inv("gunpowder") - take
			t["ammo"] = int(t.get("ammo", 0)) + take


func _utility_tick(delta: float) -> void:
	_compute_power(delta)   # refresh the wire network + drain generators
	_compute_water()        # refresh which pipes carry pool water
	_miner_tick(delta)
	_autoloader_tick(delta)
	# Sprinklers fed by a watered pipe keep nearby planters moist automatically.
	for sidx in _sprinklers:
		if not _is_piped_water(_index_cell(sidx)):
			continue
		for pidx in _planters:
			var pp: Dictionary = _planters[pidx]
			if pp["planted"] and _chebyshev(_index_cell(sidx), _index_cell(pidx)) <= SPRINKLER_RADIUS:
				pp["wet"] = PLANTER_DRY
	# Fish aquariums: filter + fresh water keep quality up; fish breed when fed.
	for aidx in _aquariums:
		_aquarium_tick(_aquariums[aidx], _index_cell(aidx), delta)
	# Placed glapple lamps burn down, then go dark (still standing until removed).
	for idx in _lamps:
		var lm: Dictionary = _lamps[idx]
		if lm["kind"] == "electric":
			continue   # electric bulbs don't decay; they glow only while powered
		if not lm["dead"]:
			lm["life"] = float(lm["life"]) - delta
			if lm["life"] <= 0.0:
				lm["dead"] = true
				queue_redraw()
	for idx in _kilns:
		var kl: Dictionary = _kilns[idx]
		var q: Array = kl["queue"]
		if not q.is_empty() and float(kl["fuel"]) >= KILN_FUEL_PER_JOB:
			kl["conv"] = float(kl["conv"]) + delta * (POWER_SPEED_MULT if _is_powered(_index_cell(idx)) else 1.0)
			if kl["conv"] >= KILN_TICK:
				kl["conv"] = 0.0
				kl["fuel"] = float(kl["fuel"]) - KILN_FUEL_PER_JOB
				var out_kind: String = q.pop_front()
				_give_item(out_kind, 1)
	# Bee enclosures: bees make honey/beeswax + speed a nearby plant, but need a
	# plant nearby to survive (or they slowly die off).
	for idx in _apiaries:
		var ap: Dictionary = _apiaries[idx]
		if int(ap["bees"]) <= 0:
			continue
		if _plant_near(_index_cell(idx), BEE_PLANT_RADIUS):
			ap["starve"] = 0.0
			ap["prod"] = float(ap["prod"]) + delta * float(ap["bees"])
			if ap["prod"] >= BEE_PROD_TIME:
				ap["prod"] = float(ap["prod"]) - BEE_PROD_TIME
				_give_item("honey", 1)
				if randf() < 0.5:
					_give_item("beeswax", 1)
				_bee_boost_plant(_index_cell(idx))
		else:
			ap["starve"] = float(ap["starve"]) + delta
			if ap["starve"] >= BEE_STARVE_TIME:
				ap["starve"] = 0.0
				ap["bees"] = maxi(0, int(ap["bees"]) - 1)
	# Worm habitats: worms breed (2..10) and compost rot into fertilizer.
	for idx in _wormfarms:
		var wf: Dictionary = _wormfarms[idx]
		if int(wf["worms"]) >= 2 and int(wf["worms"]) < WORM_CAP:
			wf["mult"] = float(wf["mult"]) + delta
			if wf["mult"] >= WORM_MULTIPLY_TIME:
				wf["mult"] = 0.0
				wf["worms"] = int(wf["worms"]) + 1
		if int(wf["rot"]) > 0 and int(wf["worms"]) > 0:
			wf["compost"] = float(wf["compost"]) + delta
			if wf["compost"] >= COMPOST_TIME:
				wf["compost"] = 0.0
				wf["rot"] = int(wf["rot"]) - 1
				_give_item("fertilizer", 1)
	# Stills: refine queued cups of juice into berry oil over time.
	for idx in _stills:
		var st: Dictionary = _stills[idx]
		if int(st["pending"]) > 0:
			st["conv"] = float(st["conv"]) + delta * (POWER_SPEED_MULT if _is_powered(_index_cell(idx)) else 1.0)
			if st["conv"] >= STILL_TICK:
				st["conv"] = 0.0
				st["pending"] = int(st["pending"]) - 1
				_give_item("cup_oil", 1)
	# Campfires: a loaded skewer cooks, then chars to ash if left too long.
	for idx in _campfires:
		var cf: Dictionary = _campfires[idx]
		if cf["item"] == "fish_skewer":
			cf["cook"] = float(cf["cook"]) + delta
			if cf["cook"] >= COOK_BURN_TIME:
				cf["item"] = "ash"
	for idx in _juicers:
		var j: Dictionary = _juicers[idx]
		if int(j["pending"]) > 0 and int(j["juice"]) < JUICER_CAP:
			j["conv"] = float(j["conv"]) + delta * (POWER_SPEED_MULT if _is_powered(_index_cell(idx)) else 1.0)
			if j["conv"] >= JUICE_TICK:
				j["conv"] = 0.0
				j["pending"] = int(j["pending"]) - 1
				j["juice"] = mini(JUICER_CAP, int(j["juice"]) + JUICE_PER_BERRY)
	for idx in _barrels:
		var b: Dictionary = _barrels[idx]
		if b["kind"] == "juice" and int(b["amount"]) > 0:
			b["ferment"] = float(b["ferment"]) + delta
			if b["ferment"] >= FERMENT_TIME:
				b["kind"] = "wine"          # the whole barrel turns to wine
				b["ferment"] = 0.0
		else:
			b["ferment"] = 0.0
	for idx in _planters:
		var p: Dictionary = _planters[idx]
		if p["planted"] and float(p["wet"]) > 0.0:
			p["wet"] = maxf(0.0, float(p["wet"]) - delta)
			if int(p["berries"]) < BUSH_MAX_BERRIES:
				p["grow"] = float(p["grow"]) + delta
				if p["grow"] >= PLANTER_GROW:
					p["grow"] = 0.0
					p["berries"] = int(p["berries"]) + 1
	if _docked_station >= 0 and _terrain[_docked_station] != Terrain.STORAGE and _terrain[_docked_station] != Terrain.TURRET:
		_util_refresh_t += delta
		if _util_refresh_t >= 0.5:
			_util_refresh_t = 0.0
			_mark_workspace_dirty()


# --- Barrel / juicer / planter interactions ----------------------------------
func _barrel_store(idx: int, kind: String) -> void:
	var b: Dictionary = _barrels[idx]
	var cup_kind := "cup_water" if kind == "water" else "cup_juice"
	if _inv(cup_kind) <= 0:
		_set_msg("No %s to pour in." % kind); return
	if b["kind"] != "" and b["kind"] != kind:
		_set_msg("Barrel already holds %s." % b["kind"]); return
	if int(b["amount"]) >= BARREL_CAP:
		_set_msg("Barrel is full."); return
	_resources[cup_kind] = _inv(cup_kind) - 1
	_resources["cup"] = _inv("cup") + 1
	b["kind"] = kind
	b["amount"] = int(b["amount"]) + 1
	_mark_workspace_dirty()


func _barrel_take(idx: int) -> void:
	var b: Dictionary = _barrels[idx]
	if int(b["amount"]) <= 0:
		return
	if _inv("cup") <= 0:
		_set_msg("Need an empty cup."); return
	var cup_kind := "cup_" + str(b["kind"])
	_resources["cup"] = _inv("cup") - 1
	_resources[cup_kind] = _inv(cup_kind) + 1
	b["amount"] = int(b["amount"]) - 1
	if int(b["amount"]) == 0:
		b["kind"] = ""
		b["ferment"] = 0.0
	_mark_workspace_dirty()


func _barrel_empty(idx: int) -> void:
	var b: Dictionary = _barrels[idx]
	b["kind"] = ""; b["amount"] = 0; b["ferment"] = 0.0
	_mark_workspace_dirty()


func _juicer_add(idx: int) -> void:
	var j: Dictionary = _juicers[idx]
	if _inv("berry") <= 0:
		_set_msg("No fresh berries (rotten won't juice)."); return
	if int(j["juice"]) + int(j["pending"]) * JUICE_PER_BERRY >= JUICER_CAP:
		_set_msg("Juicer is full."); return
	_resources["berry"] = _inv("berry") - 1
	j["pending"] = int(j["pending"]) + 1
	_mark_workspace_dirty()


func _juicer_take(idx: int) -> void:
	var j: Dictionary = _juicers[idx]
	if int(j["juice"]) <= 0:
		return
	if _inv("cup") <= 0:
		_set_msg("Need an empty cup."); return
	_resources["cup"] = _inv("cup") - 1
	_resources["cup_juice"] = _inv("cup_juice") + 1
	j["juice"] = int(j["juice"]) - 1
	_mark_workspace_dirty()


# --- Kiln: smelt ore->metal, melt sand->glass, char wood->charcoal ----------
func _kiln_fuel(idx: int, kind: String) -> void:
	var kl: Dictionary = _kilns[idx]
	if kind == "wood" and _inv("wood") > 0:
		_resources["wood"] = _inv("wood") - 1
		kl["fuel"] = minf(KILN_FUEL_MAX, float(kl["fuel"]) + KILN_FUEL_PER_WOOD)
	elif kind == "charcoal" and _inv("charcoal") > 0:
		_resources["charcoal"] = _inv("charcoal") - 1
		kl["fuel"] = minf(KILN_FUEL_MAX, float(kl["fuel"]) + KILN_FUEL_PER_CHARCOAL)
	else:
		_set_msg("Need %s to stoke it." % kind); return
	_mark_workspace_dirty()


# Queue a conversion: consume the raw input now, produce the output over time.
func _kiln_load(idx: int, input_item: String, output_item: String) -> void:
	var kl: Dictionary = _kilns[idx]
	if _inv(input_item) <= 0:
		_set_msg("No %s to process." % ITEM_LABELS.get(input_item, input_item)); return
	_resources[input_item] = _inv(input_item) - 1
	(kl["queue"] as Array).append(output_item)
	_mark_workspace_dirty()


# --- Bees / hives ------------------------------------------------------------
# True if any growing plant sits within `r` tiles (bees need greenery to thrive).
func _plant_near(cell: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := cell + Vector2i(dx, dy)
			if not _in_bounds(c):
				continue
			var tt := _terrain_at(c)
			if tt == Terrain.TREE or tt == Terrain.BUSH or tt == Terrain.COCONUT \
					or tt == Terrain.BAMBOO or tt == Terrain.SAPLING or tt == Terrain.PLANTER:
				return true
	return false


# Nudge the nearest planted planter's growth along (bee pollination perk).
func _bee_boost_plant(cell: Vector2i) -> void:
	for idx in _planters:
		var p: Dictionary = _planters[idx]
		if p["planted"] and _chebyshev(cell, _index_cell(idx)) <= BEE_PLANT_RADIUS:
			p["grow"] = float(p["grow"]) + PLANTER_GROW * 0.4
			return


# Click a wild hive: collect honey, occasionally shaking a bee loose.
func _harvest_hive(c: Vector2i) -> void:
	_resources["honey"] = _inv("honey") + 1 + (1 if randf() < 0.5 else 0)
	if randf() < FP_HIVE_HARVEST_BEE_CHANCE:
		_spawn_loot("bee", 1, _cell_center_world(c))   # needs a jar to catch
	_facing = _cardinal(Vector2(c - _cell))
	_energy = maxf(0.0, _energy - ENERGY_HARVEST)
	queue_redraw()


func _apiary_add_bee(idx: int) -> void:
	var ap: Dictionary = _apiaries[idx]
	if _inv("bee") <= 0:
		_set_msg("No bee in a jar to add."); return
	if int(ap["bees"]) >= BEE_CAP:
		_set_msg("Enclosure is full (%d bees)." % BEE_CAP); return
	_resources["bee"] = _inv("bee") - 1
	_resources["glass_jar"] = _inv("glass_jar") + 1   # the jar comes back empty
	ap["bees"] = int(ap["bees"]) + 1
	_mark_workspace_dirty()


# --- Worm habitat ------------------------------------------------------------
func _wormfarm_add_worm(idx: int) -> void:
	var wf: Dictionary = _wormfarms[idx]
	if _inv("worm") <= 0:
		_set_msg("No worm in a jar to add."); return
	if int(wf["worms"]) >= WORM_CAP:
		_set_msg("Habitat is full."); return
	_resources["worm"] = _inv("worm") - 1
	_resources["glass_jar"] = _inv("glass_jar") + 1
	wf["worms"] = int(wf["worms"]) + 1
	_mark_workspace_dirty()


func _wormfarm_take_worm(idx: int) -> void:
	var wf: Dictionary = _wormfarms[idx]
	if int(wf["worms"]) <= 0:
		return
	if _inv("glass_jar") <= 0:
		_set_msg("Need a glass jar to take a worm."); return
	_resources["glass_jar"] = _inv("glass_jar") - 1
	_resources["worm"] = _inv("worm") + 1
	wf["worms"] = int(wf["worms"]) - 1
	_mark_workspace_dirty()


func _wormfarm_add_rot(idx: int) -> void:
	var wf: Dictionary = _wormfarms[idx]
	if _rot_total() <= 0:
		_set_msg("No rot to compost."); return
	_consume_rot(1)
	wf["rot"] = int(wf["rot"]) + 1
	_mark_workspace_dirty()


# --- Campfire cooking --------------------------------------------------------
func _campfire_put(idx: int) -> void:
	var cf: Dictionary = _campfires[idx]
	if cf["item"] != "":
		_set_msg("Something's already on the fire."); return
	if _inv("fish_skewer") <= 0:
		_set_msg("Make a raw skewer first (rod + 3 fish)."); return
	_resources["fish_skewer"] = _inv("fish_skewer") - 1
	cf["item"] = "fish_skewer"; cf["cook"] = 0.0
	_mark_workspace_dirty()


func _campfire_take(idx: int) -> void:
	var cf: Dictionary = _campfires[idx]
	if cf["item"] == "":
		return
	if cf["item"] == "ash":
		_give_item("ash", 1)
	elif float(cf["cook"]) >= COOK_TIME:
		_give_item("cooked_skewer", 1)   # perfectly done
	else:
		_give_item("fish_skewer", 1)     # pulled off too soon, still raw
	cf["item"] = ""; cf["cook"] = 0.0
	_mark_workspace_dirty()


# --- Fish aquarium: a powered, plumbed breeding tank --------------------------
func _aquarium_tick(aq: Dictionary, cell: Vector2i, delta: float) -> void:
	var total: int = int(aq["males"]) + int(aq["females"])
	# The filter runs only with power + piped fresh water + water in the tank.
	var filter_ok: bool = _is_powered(cell) and _is_piped_water(cell) and int(aq["water"]) > 0
	if filter_ok:
		aq["quality"] = minf(100.0, float(aq["quality"]) + AQUARIUM_FILTER_GAIN * delta)
	# Fish foul the water; every fish over the safe limit pollutes faster and faster.
	if total > 0:
		var over: int = maxi(0, total - AQUARIUM_FISH_SAFE)
		var rate: float = total * AQUARIUM_POLLUTE + over * over * AQUARIUM_POLLUTE
		aq["quality"] = float(aq["quality"]) - rate * delta
	if float(aq["quality"]) <= 0.0:
		aq["males"] = 0; aq["females"] = 0; aq["eggs"] = 0   # poisoned: the tank dies
		aq["quality"] = 0.0
		return
	# Feeding: worms keep the fish fed; unfed fish turn on the eggs.
	aq["feed"] = maxf(0.0, float(aq["feed"]) - delta)
	if total >= 2 and int(aq["males"]) > 0 and int(aq["females"]) > 0 and filter_ok and float(aq["feed"]) > 0.0:
		aq["breed"] = float(aq["breed"]) + delta
		if aq["breed"] >= AQUARIUM_BREED_TIME:
			aq["breed"] = 0.0
			if int(aq["eggs"]) < 10:
				aq["eggs"] = int(aq["eggs"]) + 1
			# Each laid egg gets a 50% shot to hatch into a fish.
			if randf() < 0.5 and int(aq["eggs"]) > 0:
				aq["eggs"] = int(aq["eggs"]) - 1
				if randf() < 0.5: aq["males"] = int(aq["males"]) + 1
				else: aq["females"] = int(aq["females"]) + 1
	elif float(aq["feed"]) <= 0.0 and int(aq["eggs"]) > 0:
		aq["breed"] = float(aq["breed"]) + delta
		if aq["breed"] >= AQUARIUM_BREED_TIME * 0.5:
			aq["breed"] = 0.0
			aq["eggs"] = int(aq["eggs"]) - 1   # hungry fish eat the eggs


func _aquarium_add_fish(idx: int, sex: String) -> void:
	var aq: Dictionary = _aquariums[idx]
	var item := "fish_m" if sex == "m" else "fish_f"
	if _inv(item) <= 0:
		_set_msg("No %s to add." % ITEM_LABELS[item]); return
	_resources[item] = _inv(item) - 1
	if sex == "m": aq["males"] = int(aq["males"]) + 1
	else: aq["females"] = int(aq["females"]) + 1
	_mark_workspace_dirty()


func _aquarium_take_fish(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if int(aq["females"]) > 0:
		aq["females"] = int(aq["females"]) - 1; _give_item("fish_f", 1)
	elif int(aq["males"]) > 0:
		aq["males"] = int(aq["males"]) - 1; _give_item("fish_m", 1)
	else:
		return
	_mark_workspace_dirty()


func _aquarium_water(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if _inv("cup_water") <= 0:
		_set_msg("Need a cup of water."); return
	if int(aq["water"]) >= AQUARIUM_WATER_MAX:
		_set_msg("Tank is full."); return
	_resources["cup_water"] = _inv("cup_water") - 1
	_resources["cup"] = _inv("cup") + 1
	aq["water"] = int(aq["water"]) + 1
	_mark_workspace_dirty()


func _aquarium_feed(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if _inv("worm") <= 0:
		_set_msg("Need a worm to feed the fish."); return
	_resources["worm"] = _inv("worm") - 1
	_resources["glass_jar"] = _inv("glass_jar") + 1
	aq["feed"] = float(aq["feed"]) + AQUARIUM_FEED_TIME
	_mark_workspace_dirty()


# --- Still: refine cups of juice into berry oil (dense, food-less fuel) -------
func _still_add(idx: int) -> void:
	var st: Dictionary = _stills[idx]
	if _inv("cup_juice") <= 0:
		_set_msg("Need a cup of juice to distill."); return
	_resources["cup_juice"] = _inv("cup_juice") - 1
	st["pending"] = int(st["pending"]) + 1
	_mark_workspace_dirty()


# Spawn the day's fish (1-4) into open water; tag each male or female.
func _spawn_fish_daily() -> void:
	var n := 1 + randi() % 4
	var attempts := 0
	while n > 0 and attempts < 400 and _fish.size() < FISH_MAX:
		attempts += 1
		var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
		if _terrain_at(c) == Terrain.WATER:
			_fish.append({"pos": _cell_center_world(c), "sex": ("m" if randf() < 0.5 else "f"), "t": randf() * TAU})
			n -= 1


# Wild hives sometimes release a catchable bee at dawn.
func _spawn_hive_bees() -> void:
	for i in range(_terrain.size()):
		if _terrain[i] == Terrain.HIVE and randf() < HIVE_BEE_CHANCE:
			_spawn_loot("bee", 1, _cell_center_world(_index_cell(i)))


# --- Mother Tree -------------------------------------------------------------
func _tree_center_cell() -> Vector2i:
	return Vector2i(GRID_CELLS / 2, GRID_CELLS / 2)


func _tree_cells() -> Array:
	var out := []
	var center := _tree_center_cell()
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var c := Vector2i(x, y)
			if _in_bounds(c):
				out.append(c)
	return out


func _tree_generator_idx() -> int:
	return _cell_index(_tree_center_cell())


func _tree_max_hp(tier: int = -1) -> float:
	var t := _tree_tier if tier < 0 else tier
	return float((FP_TREE_TIERS.get(t, FP_TREE_TIERS[1]) as Dictionary)["hp"])


func _tree_aura_radius(tier: int = -1) -> int:
	var t := _tree_tier if tier < 0 else tier
	return int((FP_TREE_TIERS.get(t, FP_TREE_TIERS[1]) as Dictionary)["aura"])


func _tree_sap_to_next(tier: int = -1) -> float:
	var t := _tree_tier if tier < 0 else tier
	return float((FP_TREE_TIERS.get(t, FP_TREE_TIERS[1]) as Dictionary)["sap_next"])


func _reset_tree_state() -> void:
	_tree_tier = 1
	_tree_hp = _tree_max_hp(1)
	_downed = false
	_downed_timer = 0.0
	_ensure_mother_tree_footprint(true)
	_sync_tree_generator()


func _clear_cell_runtime_state(idx: int) -> void:
	_struct_hp.erase(idx)
	_wrecks.erase(idx)
	_storage.erase(idx)
	_turrets.erase(idx)
	_trap_cd.erase(idx)
	_barrels.erase(idx)
	_juicers.erase(idx)
	_planters.erase(idx)
	_lamps.erase(idx)
	_kilns.erase(idx)
	_apiaries.erase(idx)
	_wormfarms.erase(idx)
	_campfires.erase(idx)
	_stills.erase(idx)
	_generators.erase(idx)
	_sprinklers.erase(idx)
	_aquariums.erase(idx)
	_miners.erase(idx)
	_autoloaders.erase(idx)
	_traps.erase(idx)


func _ensure_mother_tree_footprint(clear_ring: bool = false) -> void:
	var center := _tree_center_cell()
	if clear_ring:
		for y in range(center.y - 2, center.y + 3):
			for x in range(center.x - 2, center.x + 3):
				var c := Vector2i(x, y)
				if _in_bounds(c) and not _tree_cells().has(c):
					_set_terrain(c, Terrain.GRASS)
	for c in _tree_cells():
		var idx := _cell_index(c)
		_clear_cell_runtime_state(idx)
		_set_terrain(c, Terrain.MOTHER_TREE)
	_sync_tree_generator()
	_invalidate_flow_fields()


func _sync_tree_generator() -> void:
	var idx := _tree_generator_idx()
	if _tree_hp <= 0.0:
		_generators.erase(idx)
		return
	_generators[idx] = {"oil": 999999999, "on": true, "drain": 0.0, "tree": true}


func _tree_respawn_cell() -> Vector2i:
	var center := _tree_center_cell()
	var candidates := [
		center + Vector2i(0, 2), center + Vector2i(1, 2), center + Vector2i(-1, 2),
		center + Vector2i(2, 0), center + Vector2i(-2, 0), center + Vector2i(0, -2),
		center + Vector2i(2, 1), center + Vector2i(-2, 1), center + Vector2i(1, -2), center + Vector2i(-1, -2),
	]
	for c in candidates:
		if _is_walkable(c):
			return c
	for r in range(2, 7):
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				var c := Vector2i(x, y)
				if _is_walkable(c):
					return c
	return Vector2i(center.x, mini(GRID_CELLS - 1, center.y + 2))


func _nearest_tree_cell_to(pos: Vector2) -> Vector2i:
	var best := _tree_center_cell()
	var best_d := INF
	for c in _tree_cells():
		var d := pos.distance_to(_cell_center_world(c))
		if d < best_d:
			best_d = d
			best = c
	return best


func _in_tree_aura(cell: Vector2i) -> bool:
	if _tree_hp <= 0.0:
		return false
	var r := _tree_aura_radius()
	for tc in _tree_cells():
		if _chebyshev(cell, tc) <= r:
			return true
	return false


func _try_tree_tier_up() -> void:
	var changed := false
	while _tree_tier < 5:
		var need := _tree_sap_to_next()
		if need <= 0.0 or _sap + 0.001 < need:
			break
		_sap -= need
		_tree_tier += 1
		_tree_hp = _tree_max_hp()
		changed = true
	if changed:
		_fx_tier_up()
		_rebake_mother_tree()   # brighten/grow the canopy to the new tier (§5)
		play_sfx("tree_tier_up")
		_set_msg("Mother Tree reached tier %d." % _tree_tier)
		# Light the NEW-tech marker (overlay row + LEFT-HUD nudge) for TECH_NEW_DWELL.
		_tech_new_until = _now_secs() + TECH_NEW_DWELL
		# Teaching beat the first time a tier-up lands (queued after the tier line).
		_onboard("tier_up", "The Tree grew! Bigger power aura, more HP, and new tech unlocked. Open the Tree (stand next to it) to see what's new.", 7.0)
		_sync_tree_generator()
		_mark_workspace_dirty()
		queue_redraw()


func _maybe_tree_downgrade() -> void:
	var dropped := false
	while _tree_tier > 1 and _tree_hp <= _tree_max_hp(_tree_tier - 1):
		_tree_tier -= 1
		dropped = true
	if dropped:
		_rebake_mother_tree()   # dim/shrink the canopy to the lower tier (§5)
		_set_msg("Mother Tree withered to tier %d." % _tree_tier)
		_mark_workspace_dirty()
		queue_redraw()


func _tree_dawn_regen() -> void:
	if _tree_hp <= 0.0:
		return
	_tree_hp = minf(_tree_max_hp(), _tree_hp + _tree_max_hp() * FP_TREE_DAWN_REGEN_FRAC)
	_mark_workspace_dirty()


func _damage_tree(amount: float) -> void:
	if _tree_hp <= 0.0:
		return
	_tree_hp = maxf(0.0, _tree_hp - maxf(1.0, amount))
	if _tree_hp <= 0.0:
		_tree_game_over()
		return
	_maybe_tree_downgrade()
	_mark_workspace_dirty()
	queue_redraw()


func _tree_game_over() -> void:
	_reset_game()
	_msg = "The Mother Tree fell  -  new run"
	_msg_timer = 3.5


func _start_player_downed() -> void:
	if _downed:
		return
	_downed = true
	_downed_timer = FP_RESPAWN_DELAY
	_health = 0.0
	_player_kb = Vector2.ZERO
	_punch_active = false
	_clear_status_effects()
	_set_msg("Downed -- the Mother Tree is pulling you back.")


func _tick_downed(delta: float) -> void:
	if not _downed:
		return
	_downed_timer = maxf(0.0, _downed_timer - delta)
	if _downed_timer <= 0.0:
		_respawn_after_death()


func _apply_sap_broke_respawn_debuff() -> void:
	# Mode-B balance hook: the no-Sap respawn penalty is intentionally untuned.
	pass


# --- Crocodile Dens ----------------------------------------------------------
func _den_cells(origin: Vector2i, size: int) -> Array:
	var out := []
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			var c := Vector2i(x, y)
			if _in_bounds(c):
				out.append(c)
	return out


func _den_id_for_cell(c: Vector2i):
	for id in _dens:
		var d: Dictionary = _dens[id]
		for dc in _den_cells(d["origin"], int(d["size"])):
			if dc == c:
				return id
	return null


func _clear_den_terrain() -> void:
	for i in range(_terrain.size()):
		if _terrain[i] == Terrain.CROC_DEN:
			_set_terrain(_index_cell(i), Terrain.GRASS)


func _can_place_den(origin: Vector2i, size: int, min_tree_dist: int, allow_existing_den: bool = false) -> bool:
	if not _in_bounds(origin) or not _in_bounds(origin + Vector2i(size - 1, size - 1)):
		return false
	if _chebyshev(origin, _tree_center_cell()) < min_tree_dist:
		return false
	for c in _den_cells(origin, size):
		var t := _terrain_at(c)
		if t == Terrain.WATER or t == Terrain.MOTHER_TREE:
			return false
		if t == Terrain.CROC_DEN and not allow_existing_den:
			return false
		if _tile_break_hp(t) > 0 and not (allow_existing_den and t == Terrain.CROC_DEN):
			return false
	return true


func _create_den(origin: Vector2i, size: int = 2, maturity: int = 0) -> int:
	var id := _cell_index(origin)
	var max_hp := FP_DEN_EVOLVED_HP if size >= 3 else FP_DEN_BASE_HP
	_dens[id] = {"origin": origin, "size": size, "hp": max_hp, "max_hp": max_hp, "maturity": maturity}
	for c in _den_cells(origin, size):
		_clear_cell_runtime_state(_cell_index(c))
		_set_terrain(c, Terrain.CROC_DEN)
	return id


func _spawn_initial_dens() -> void:
	_dens.clear()
	for _i in range(FP_DEN_START_COUNT):
		_spawn_new_den()


func _spawn_new_den() -> bool:
	if _dens.size() >= FP_DEN_CAP:
		return false
	var min_dist := maxi(10, 22 - _nights_survived * 2)
	for _attempt in range(500):
		var c := Vector2i(randi() % (GRID_CELLS - 3), randi() % (GRID_CELLS - 3))
		if _can_place_den(c, 2, min_dist):
			_create_den(c, 2, 0)
			_onboard("first_den_seen", "A Crocodile Den. It spawns the horde and creeps closer each night. Clear young Dens with a quick sortie; mature ones need a forward turret outpost.", 7.0)
			return true
	return false


func _place_iron_veins() -> void:
	var placed := 0
	var attempts := 0
	while placed < FP_IRON_VEIN_COUNT and attempts < 1200:
		attempts += 1
		var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
		if _chebyshev(c, _tree_center_cell()) < 10:
			continue
		var t := _terrain_at(c)
		if t == Terrain.WATER or t == Terrain.MOTHER_TREE or t == Terrain.CROC_DEN or _tile_break_hp(t) > 0:
			continue
		_set_terrain(c, Terrain.IRON_VEIN)
		placed += 1


func _ensure_den_footprints() -> void:
	_clear_den_terrain()
	if _dens.is_empty():
		_spawn_initial_dens()
		return
	for id in _dens.keys():
		var d: Dictionary = _dens[id]
		for c in _den_cells(d["origin"], int(d["size"])):
			_clear_cell_runtime_state(_cell_index(c))
			_set_terrain(c, Terrain.CROC_DEN)


func _den_spawn_cells() -> Array:
	var out := []
	for id in _dens:
		var d: Dictionary = _dens[id]
		for dc in _den_cells(d["origin"], int(d["size"])):
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = dc + off
				if _in_bounds(n) and _tile_monster_walk(_terrain_at(n)) and not out.has(n):
					out.append(n)
	return out


# A Den's visual stage from its state, for the at-a-glance threat read (§4):
#   "young"    -- size 2, maturity 0     (cool/quiet)
#   "maturing" -- size 2, maturity >= 1  (warming, "evolves tomorrow")
#   "mature"   -- size 3 (post-evolve)   (hot/large/loud)
# Stage is a pure function of state so the bake/overlay can't drift from the
# evolve logic, and the selftest can assert the stage progression directly.
func _den_stage(d: Dictionary) -> String:
	if int(d.get("size", 2)) >= 3:
		return "mature"
	if int(d.get("maturity", 0)) >= 1:
		return "maturing"
	return "young"


func _advance_dens_day() -> void:
	for id in _dens.keys():
		var d: Dictionary = _dens[id]
		d["maturity"] = int(d.get("maturity", 0)) + 1
		if int(d["maturity"]) >= FP_DEN_EVOLVE_MATURITY and int(d["size"]) < 3:
			_evolve_den(id)
	if _nights_survived > 0 and _nights_survived % FP_DEN_NEW_EVERY_NIGHTS == 0:
		_spawn_new_den()


func _evolve_den(id: int) -> void:
	if not _dens.has(id):
		return
	var d: Dictionary = _dens[id]
	var origin: Vector2i = d["origin"]
	if not _can_place_den(origin, 3, 0, true):
		d["max_hp"] = maxf(float(d["max_hp"]), FP_DEN_EVOLVED_HP)
		d["hp"] = minf(float(d["max_hp"]), float(d["hp"]) + FP_DEN_BASE_HP * 0.5)
		return
	var old_max := float(d["max_hp"])
	d["size"] = 3
	d["max_hp"] = FP_DEN_EVOLVED_HP
	d["hp"] = minf(FP_DEN_EVOLVED_HP, float(d["hp"]) + FP_DEN_EVOLVED_HP - old_max)
	for c in _den_cells(origin, 3):
		_clear_cell_runtime_state(_cell_index(c))
		_set_terrain(c, Terrain.CROC_DEN)


func _damage_den_at(c: Vector2i, amount: float) -> void:
	var id = _den_id_for_cell(c)
	if id == null or not _dens.has(id):
		return
	var d: Dictionary = _dens[id]
	d["hp"] = maxf(0.0, float(d["hp"]) - maxf(1.0, amount))
	if float(d["hp"]) <= 0.0:
		var origin: Vector2i = d["origin"]
		for dc in _den_cells(origin, int(d["size"])):
			_set_terrain(dc, Terrain.WRECK)
		_dens.erase(id)
		_trigger_retaliation_surge(origin)
		_check_win_condition()
	queue_redraw()


func _trigger_retaliation_surge(_origin: Vector2i) -> void:
	if _dens.is_empty():
		return
	var n := maxi(2, int(ceil(float(_monster_count_for_day()) * FP_DEN_RETALIATION_MULT)))
	_spawn_monsters(n)
	_set_msg("A Den falls. The others answer.")


func _nearest_den_los(from: Vector2, radius: float):
	var best = null
	var best_d := radius
	for id in _dens:
		var d: Dictionary = _dens[id]
		for c in _den_cells(d["origin"], int(d["size"])):
			var pos := _cell_center_world(c)
			var dist := from.distance_to(pos)
			if dist < best_d and _has_los(from, pos):
				best_d = dist
				best = {"cell": c, "pos": pos, "den": id}
	return best


func _check_win_condition() -> void:
	if _won:
		return
	if _tree_tier >= 3 and _dens.is_empty():
		_trigger_victory()


# Functional end-of-run WIN state: halt the sim (see _process / _input) and
# raise the victory banner. Mirrors the game-over halt; polish is Editor 8.
func _trigger_victory() -> void:
	if _won:
		return
	_won = true
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_set_msg("All Dens cleared. The island is yours.")
	if _victory_stats:
		_victory_stats.text = "Survived %d night%s   -   Tree Tier %d   -   best run %d night%s" % [
			_nights_survived, "" if _nights_survived == 1 else "s",
			_tree_tier, _best_nights, "" if _best_nights == 1 else "s"]
	if _victory_layer:
		_victory_layer.visible = true
	queue_redraw()


func _planter_plant(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if p["planted"]:
		return
	if _inv("seed") <= 0:
		_set_msg("Need a seed (harvest berries)."); return
	_resources["seed"] = _inv("seed") - 1
	p["planted"] = true; p["berries"] = 0; p["grow"] = 0.0; p["wet"] = PLANTER_DRY
	_mark_workspace_dirty()


func _planter_water(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if not p["planted"]:
		return
	if _inv("cup_water") <= 0:
		_set_msg("Need a cup of water."); return
	_resources["cup_water"] = _inv("cup_water") - 1
	_resources["cup"] = _inv("cup") + 1
	p["wet"] = PLANTER_DRY
	_mark_workspace_dirty()


func _planter_harvest(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if int(p["berries"]) <= 0:
		return
	var yield_n := int(p["berries"])
	if int(p.get("fert", 0)) > 0:        # fertilized soil yields an extra berry
		yield_n += 1
		p["fert"] = int(p["fert"]) - 1
	_resources["berry"] = _inv("berry") + yield_n
	if randf() < 0.5:
		_resources["seed"] = _inv("seed") + 1   # planted bushes sometimes reseed
	p["berries"] = 0
	_mark_workspace_dirty()


func _planter_fertilize(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if not p["planted"]:
		return
	if _inv("fertilizer") <= 0:
		_set_msg("No fertilizer (compost rot in a worm habitat)."); return
	_resources["fertilizer"] = _inv("fertilizer") - 1
	p["fert"] = int(p.get("fert", 0)) + FERTILIZER_BONUS_HARVESTS
	_mark_workspace_dirty()


func _transfer(idx: int, res: String, amount: int, deposit: bool) -> void:
	if not _storage.has(idx):
		return
	var box: Dictionary = _storage[idx]
	if deposit:
		var n: int = mini(amount, _inv(res))
		_resources[res] = _inv(res) - n
		box[res] = int(box.get(res, 0)) + n
	else:
		var n: int = mini(amount, int(box.get(res, 0)))
		box[res] = int(box.get(res, 0)) - n
		_resources[res] = _inv(res) + n
	_mark_workspace_dirty()


func _deposit_all(idx: int) -> void:
	for res in INV_ORDER:
		_transfer(idx, res, _inv(res), true)


func _take_all(idx: int) -> void:
	if _storage.has(idx):
		var box: Dictionary = _storage[idx]
		for res in INV_ORDER:
			_transfer(idx, res, int(box.get(res, 0)), false)


# -----------------------------------------------------------------------------
# World data
# -----------------------------------------------------------------------------
func _generate_world() -> void:
	_block_count = 0   # fresh world has no player-built blocks
	_wrecks.clear()
	_terrain.resize(GRID_CELLS * GRID_CELLS)
	_banana.resize(GRID_CELLS * GRID_CELLS)
	_berry.resize(GRID_CELLS * GRID_CELLS)
	_growth.resize(GRID_CELLS * GRID_CELLS)

	var noise := FastNoiseLite.new()
	noise.seed = _seed
	noise.frequency = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	for y in range(GRID_CELLS):
		for x in range(GRID_CELLS):
			var idx := y * GRID_CELLS + x
			var t: int
			# One fixed, permanent water pool, ringed by a sandy beach.
			var pd := Vector2(x, y).distance_to(POOL_CENTER)
			if pd <= POOL_RADIUS:
				t = Terrain.WATER
			elif pd <= POOL_RADIUS + 1.6:
				t = Terrain.SAND
			else:
				var n := noise.get_noise_2d(float(x), float(y))
				if n > FP_WORLD_STONE_NOISE_THRESHOLD:
					t = Terrain.STONE
				elif rng.randf() < FP_WORLD_TREE_CHANCE:
					t = Terrain.TREE
				elif rng.randf() < FP_WORLD_BUSH_CHANCE:
					t = Terrain.BUSH
				elif rng.randf() < FP_WORLD_COCONUT_CHANCE:
					t = Terrain.COCONUT
				elif rng.randf() < FP_WORLD_BAMBOO_CHANCE:
					t = Terrain.BAMBOO
				elif rng.randf() < FP_WORLD_HIVE_CHANCE:
					t = Terrain.HIVE
				else:
					t = Terrain.GRASS
			_terrain[idx] = t
			# _banana doubles as "fruit present" for both palms and banana trees.
			if t == Terrain.TREE:
				_banana[idx] = 1 if rng.randf() < BANANA_START_CHANCE else 0
			elif t == Terrain.COCONUT:
				_banana[idx] = 1 if rng.randf() < 0.7 else 0
			else:
				_banana[idx] = 0
			_berry[idx] = 1 if t == Terrain.BUSH else 0

	# Clear a patch of grass around the player's spawn.
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var c := _cell + Vector2i(ox, oy)
			if _in_bounds(c):
				var i := _cell_index(c)
				_terrain[i] = Terrain.GRASS
				_banana[i] = 0
				_berry[i] = 0
	_reset_tree_state()
	_cell = _tree_respawn_cell()
	_compute_pool_shore()
	_invalidate_flow_fields()


# Walkable land cells adjacent to the pool -- where crocs surface at night.
func _compute_pool_shore() -> void:
	_pool_shore = []
	for i in range(_terrain.size()):
		if _terrain[i] != Terrain.WATER:
			continue
		var c := _index_cell(i)
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if _in_bounds(n) and _tile_monster_walk(_terrain_at(n)) and not _pool_shore.has(n):
				_pool_shore.append(n)


# True unless `start` is sealed inside player-built structures (walls/doors/etc).
func _is_outdoors(start: Vector2i) -> bool:
	if not _in_bounds(start):
		return true
	var seen := {_cell_index(start): true}
	var stack := [start]
	var steps := 0
	while not stack.is_empty() and steps < 4000:
		steps += 1
		var c: Vector2i = stack.pop_back()
		if c.x == 0 or c.y == 0 or c.x == GRID_CELLS - 1 or c.y == GRID_CELLS - 1:
			return true
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			var ni := _cell_index(n)
			if seen.has(ni) or _tile_break_hp(_terrain[ni]) > 0:
				continue   # player structures act as walls of the enclosure
			seen[ni] = true
			stack.append(n)
	return false


func _set_terrain(c: Vector2i, t: int) -> void:
	var i := _cell_index(c)
	var old_t: int = _terrain[i]
	# Keep the structural-block tally in sync as tiles change (single choke point).
	if BLOCK_TERRAIN.has(old_t):
		_block_count -= 1
	if BLOCK_TERRAIN.has(t):
		_block_count += 1
	_terrain[i] = t
	if old_t != t:
		_field_tree_dirty = true
		_field_player_timer = FLOW_PLAYER_INTERVAL
	if t != Terrain.WRECK:
		_wrecks.erase(i)
	_growth[i] = 0.0
	if t != Terrain.TREE:
		_banana[i] = 0
	if t != Terrain.BUSH:
		_berry[i] = 0


func _terrain_at(c: Vector2i) -> int:
	return _terrain[_cell_index(c)]


func _cell_index(c: Vector2i) -> int:
	return c.y * GRID_CELLS + c.x


func _index_cell(i: int) -> Vector2i:
	return Vector2i(i % GRID_CELLS, i / GRID_CELLS)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID_CELLS and c.y >= 0 and c.y < GRID_CELLS


func _is_walkable(c: Vector2i) -> bool:
	return _in_bounds(c) and _tile_player_walk(_terrain_at(c))


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _cell_center_world(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL_SIZE


func _mouse_cell() -> Vector2i:
	var w := get_global_mouse_position()
	return Vector2i(int(floor(w.x / CELL_SIZE)), int(floor(w.y / CELL_SIZE)))


# -----------------------------------------------------------------------------
# UI: styled side panels
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	_apply_theme()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var left_vbox := _make_panel(layer, true)
	var title := _header("GOLIRADILE ISLE")
	title.add_theme_font_size_override("font_size", 26)
	left_vbox.add_child(title)
	left_vbox.add_child(_sep())
	_lbl_time = _label("")
	left_vbox.add_child(_lbl_time)
	_lbl_threat = _label("")
	# Onboarding beats are 2-line copy: word-wrap inside the left panel width.
	_lbl_threat.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lbl_threat.custom_minimum_size.x = PANEL_W - 28
	left_vbox.add_child(_lbl_threat)
	# Lives (pips).
	var lives_row := HBoxContainer.new()
	lives_row.add_theme_constant_override("separation", 6)
	lives_row.add_child(_label("Lives"))
	_life_pips = []
	for i in range(MAX_LIVES):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 16)
		lives_row.add_child(pip)
		_life_pips.append(pip)
	left_vbox.add_child(lives_row)
	_lbl_nights = _label("")
	left_vbox.add_child(_lbl_nights)
	# Each bar's value now rides on its own caption line (saves vertical room).
	_lbl_health = _label("")
	left_vbox.add_child(_lbl_health)
	_bar_health = _make_bar(Color(0.85, 0.25, 0.25))
	left_vbox.add_child(_bar_health)
	_lbl_energy = _label("")
	left_vbox.add_child(_lbl_energy)
	_bar_energy = _make_bar(Color(0.95, 0.78, 0.20))
	left_vbox.add_child(_bar_energy)
	_lbl_hydration = _label("")
	left_vbox.add_child(_lbl_hydration)
	_bar_hydration = _make_bar(Color(0.30, 0.62, 0.95))
	left_vbox.add_child(_bar_hydration)
	left_vbox.add_child(_sep())
	_lbl_level = _header("LEVEL 1")
	left_vbox.add_child(_lbl_level)
	_lbl_xp = _label("")
	left_vbox.add_child(_lbl_xp)
	_bar_xp = _make_bar(Color(0.40, 0.65, 0.95))
	left_vbox.add_child(_bar_xp)
	_lbl_stats = _label("")
	left_vbox.add_child(_lbl_stats)
	left_vbox.add_child(_sep())
	left_vbox.add_child(_header("INVENTORY"))
	_lbl_wood = _label("")
	_lbl_stone = _label("")
	_lbl_food = _label("")
	left_vbox.add_child(_icon_row(UI_WOOD, _lbl_wood))
	left_vbox.add_child(_icon_row(UI_STONE, _lbl_stone))
	left_vbox.add_child(_icon_row(UI_FOOD, _lbl_food))
	var hint := _label("[I] manage / drop items")
	hint.add_theme_font_size_override("font_size", 13)
	left_vbox.add_child(hint)

	left_vbox.add_child(_sep())
	var save_btn := Button.new()
	save_btn.text = "Save Game"
	save_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_btn.pressed.connect(_on_save_pressed)
	left_vbox.add_child(save_btn)
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.pressed.connect(_open_settings.bind(AppState.PLAYING))
	left_vbox.add_child(settings_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_btn.pressed.connect(_return_to_menu)
	left_vbox.add_child(menu_btn)

	_right_vbox = _make_panel(layer, false)


# A single root hover-tooltip frame. Lives on its own CanvasLayer above the panels
# (layer 11 > 10) so it z-sorts on top of both side panels, ignores the mouse, and
# is hidden until _show_tooltip fills it. Every row is a Label/HBox in a VBox; only
# the desc word-wraps. Content is set per def family in _refresh_tooltip_content.
func _build_tooltip() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 11
	add_child(_tooltip_layer)

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.custom_minimum_size = Vector2(TOOLTIP_W, 0)
	if _ui_theme:
		_tooltip_panel.theme = _ui_theme   # tooltip rows share the identity fonts/colors
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI_TIP_BG
	sb.border_color = UI_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", sb)
	_tooltip_layer.add_child(_tooltip_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(vb)

	# Name row: 28px icon + name label.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tt_icon = TextureRect.new()
	_tt_icon.custom_minimum_size = Vector2(28, 28)
	_tt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tt_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_tt_icon)
	_tt_name = Label.new()
	_tt_name.add_theme_font_size_override("font_size", 16)
	_tt_name.add_theme_color_override("font_color", UI_NAME)
	_tt_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(_tt_name)
	vb.add_child(name_row)

	_tt_sub = Label.new()
	_tt_sub.add_theme_font_size_override("font_size", 12)
	_tt_sub.add_theme_color_override("font_color", UI_SUBTLE)
	vb.add_child(_tt_sub)

	_tt_stat = Label.new()
	_tt_stat.add_theme_font_size_override("font_size", 13)
	_tt_stat.add_theme_color_override("font_color", UI_STAT)
	vb.add_child(_tt_stat)

	_tt_cost = HBoxContainer.new()
	_tt_cost.add_theme_constant_override("separation", 6)
	_tt_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_tt_cost)

	_tt_desc = Label.new()
	_tt_desc.add_theme_font_size_override("font_size", 13)
	_tt_desc.add_theme_color_override("font_color", UI_DESC)
	_tt_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tt_desc.custom_minimum_size = Vector2(TOOLTIP_W - 16, 0)
	vb.add_child(_tt_desc)

	_tooltip_panel.visible = false


# Mouse entered a hoverable widget: remember what it is. The frame only appears
# after TOOLTIP_DWELL of continuous hover (handled in _process), so a sweep across
# the panel doesn't strobe tooltips.
func _hover_set(kind: String, source: String) -> void:
	if kind == _hover_kind and source == _hover_source:
		return
	_hover_kind = kind
	_hover_source = source
	_hover_dwell = 0.0
	if _tooltip_shown:
		_hide_tooltip()


func _hover_clear(kind: String, source: String) -> void:
	# Only clear if we're still the active hover (guards stale exit after a re-enter).
	if kind == _hover_kind and source == _hover_source:
		_hover_kind = ""
		_hover_source = ""
		_hover_dwell = 0.0
		_hide_tooltip()


# Connect a Control's enter/exit to the hover state so it drives the tooltip.
func _wire_hover(ctrl: Control, kind: String, source: String) -> void:
	if kind == "":
		return
	ctrl.mouse_entered.connect(_hover_set.bind(kind, source))
	ctrl.mouse_exited.connect(_hover_clear.bind(kind, source))


func _show_tooltip(kind: String, source: String) -> void:
	if not _tooltip_panel:
		return
	_refresh_tooltip_content(kind, source)
	_tooltip_panel.visible = true
	_tooltip_shown = true
	_position_tooltip()
	_fx_tooltip_show()


func _hide_tooltip() -> void:
	if _tooltip_panel:
		_tooltip_panel.visible = false
	_tooltip_shown = false


# Fill the frame from the def family. Rows with no content hide themselves so the
# panel shrinks to fit (PanelContainer auto-sizes to the VBox).
func _refresh_tooltip_content(kind: String, source: String) -> void:
	var label_text := _tooltip_name(kind, source)
	_tt_name.text = label_text
	# Icon: items/recipes/structs/weapons map to a baked item icon where one exists.
	var icon_kind := _tooltip_icon_kind(kind, source)
	_tt_icon.texture = _item_icons.get(icon_kind, null)
	_tt_icon.visible = _tt_icon.texture != null

	var sub := _tooltip_subtitle(kind, source)
	_tt_sub.text = sub
	_tt_sub.visible = sub != ""

	var stat := _tooltip_stat_line(kind, source)
	_tt_stat.text = stat
	_tt_stat.visible = stat != ""

	var cost := _tooltip_cost(kind, source)
	for c in _tt_cost.get_children():
		_tt_cost.remove_child(c)
		c.queue_free()
	if not cost.is_empty():
		_fill_cost_tokens(_tt_cost, cost)
		_tt_cost.visible = true
	else:
		_tt_cost.visible = false

	var desc := _tooltip_desc(kind, source)
	_tt_desc.text = desc
	_tt_desc.visible = desc != ""


func _tooltip_name(kind: String, source: String) -> String:
	match source:
		"item", "recipe":
			return ITEM_LABELS.get(kind, kind.capitalize())
		"struct":
			return String(STRUCTURES.get(kind, {}).get("label", kind.capitalize()))
		"turret":
			return String(TURRET_DEFS.get(kind, {}).get("label", kind.capitalize()))
		"weapon":
			return String(WEAPON_DEFS.get(kind, {}).get("label", "Fists"))
		"croc":
			return "%s Croc" % kind.capitalize()
		"special":
			if kind == "mother_tree_hub":
				return "Mother Tree Hub"
			if kind == "bare_grass":
				return "Bare Grass"
	return kind.capitalize()


func _tooltip_icon_kind(kind: String, source: String) -> String:
	# Weapons/tools/items resolve to their own baked icon; structs reuse a related
	# item icon where one exists (e.g. glapple_lamp), else no icon.
	match source:
		"item", "recipe", "weapon":
			return kind
		"struct":
			return kind if _item_icons.has(kind) else ""
	return ""


func _tooltip_subtitle(kind: String, source: String) -> String:
	match source:
		"turret":
			var d: Dictionary = TURRET_DEFS.get(kind, {})
			var tier := _turret_required_tier(kind)
			return "%s turret%s" % [TURRET_CAT_LABEL.get(d.get("cat", ""), ""), ("  T%d" % tier) if tier > 1 else ""]
		"struct":
			var st := int(FP_STRUCT_TIER.get(kind, 1))
			return "Structure%s" % ("  T%d" % st if st > 1 else "")
		"weapon":
			return "Weapon" + ("  ranged" if bool(WEAPON_DEFS.get(kind, {}).get("ranged", false)) else "")
		"croc":
			return String(CROC_DEFS.get(kind, {}).get("role", "")).capitalize()
		"item", "recipe":
			return INV_BAND_LABEL.get(INV_CATEGORY.get(kind, ""), "").capitalize()
		"special":
			return "Interact"
	return ""


func _tooltip_cost(kind: String, source: String) -> Dictionary:
	match source:
		"struct":
			return STRUCTURES.get(kind, {}).get("cost", {})
		"recipe":
			return CRAFT_RECIPES.get(kind, {}).get("cost", {})
	return {}


func _tooltip_desc(kind: String, source: String) -> String:
	match source:
		"item", "recipe":
			# A recipe's output desc reads from ITEM_DESC by the output id.
			var did := kind
			if source == "recipe":
				did = String(CRAFT_RECIPES.get(kind, {}).get("out", kind))
			return ITEM_DESC.get(did, "")
		"struct":
			return String(STRUCTURES.get(kind, {}).get("desc", ""))
		"turret":
			return String(TURRET_DEFS.get(kind, {}).get("desc", ""))
		"weapon":
			return String(WEAPON_DEFS.get(kind, {}).get("desc", ""))
		"croc":
			return String(CROC_DEFS.get(kind, {}).get("desc", ""))
		"special":
			if kind == "mother_tree_hub":
				return "Open Tree hub. Deposit Sap there to grow it and unlock tech."
			if kind == "bare_grass":
				return "Click bare grass to pull fibers (for string)."
	return ""


# Build the per-token tinted cost row (the only place green/red affordability lives,
# shared with the build bar): green when you have enough, red when short.
func _fill_cost_tokens(box: HBoxContainer, cost: Dictionary) -> void:
	var lead := Label.new()
	lead.text = "Cost:"
	lead.add_theme_font_size_override("font_size", 12)
	lead.add_theme_color_override("font_color", UI_SUBTLE)
	box.add_child(lead)
	for k in cost:
		var n := int(cost[k])
		var tok := Label.new()
		tok.text = "%d %s" % [n, ITEM_LABELS.get(k, k)]
		tok.add_theme_font_size_override("font_size", 12)
		tok.add_theme_color_override("font_color", UI_OK if _inv(k) >= n else UI_SHORT)
		box.add_child(tok)


# Clamp the frame to the cursor + (16,16), flipping left of the cursor inside the
# right panel and clamping to the viewport so it never spills offscreen.
func _position_tooltip() -> void:
	if not _tooltip_panel or not _tooltip_panel.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var mp := _tooltip_panel.get_viewport().get_mouse_position()
	var sz := _tooltip_panel.size
	if sz.x < 1.0:
		sz = Vector2(TOOLTIP_W, 80)
	var x := mp.x + 16.0
	# Inside (or about to cross into) the right panel -> flip to the cursor's left.
	if x + sz.x > vp.x - PANEL_W:
		x = mp.x - 16.0 - sz.x
	x = clampf(x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	var y := clampf(mp.y + 16.0, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	_tooltip_panel.position = Vector2(x, y)


# Mode-B juice hook: a later pass can fade the tooltip in (0.08s alpha tween). Empty
# but present so the hook exists at the right call site.
func _fx_tooltip_show() -> void:
	pass


func _on_save_pressed() -> void:
	_save_game()
	_set_msg("Game saved.")
	_update_status()


func _return_to_menu() -> void:
	# Step out to the title menu (manual save is the player's responsibility).
	_app_state = AppState.MENU
	_enter_menu()


func _build_fx() -> void:
	# FX layer sits below the panels (layer 10), so flashes/vignette only cover
	# the board, and never block clicks (mouse filter ignore).
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 5
	add_child(_fx_layer)

	_vignette = TextureRect.new()
	_vignette.texture = _make_vignette_tex()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0)
	_fx_layer.add_child(_vignette)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(0.85, 0.12, 0.10, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_flash_rect)

	# Radial "NIGHT IN m:ss" countdown clock: top-center HUD, only visible in the
	# dusk window. Anchored full-rect so it can size to the viewport in its own _draw.
	var clk := CountdownClock.new()
	clk.game = self
	clk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clk.visible = false
	_fx_layer.add_child(clk)
	_clock_ctrl = clk

	_build_victory_layer()


# The full-screen TECH hub lives on its own CanvasLayer (15: above the side panels at
# 10, below the victory banner at 20). The static frame (dim backing + margin + body
# VBox) is built once; _build_tech_overlay_panel repopulates _tech_body each rebuild
# through the same coalesced dirty path the right panel uses. Hidden unless Overlay.TECH.
func _build_tech_layer() -> void:
	_tech_layer = CanvasLayer.new()
	_tech_layer.layer = 15
	add_child(_tech_layer)
	_tech_root = _overlay_root(0.82)   # board stays faintly visible -> "I'm at the Tree"
	_tech_root.visible = false
	_tech_layer.add_child(_tech_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	_tech_root.add_child(margin)
	_tech_body = VBoxContainer.new()
	if _ui_theme:
		_tech_body.theme = _ui_theme
	_tech_body.add_theme_constant_override("separation", 14)
	margin.add_child(_tech_body)


# Victory screen: a dimmed board behind a centered card consistent with the Theme --
# baked tree crest, gold VICTORY title, the run epitaph, a live stats line, and the
# dismissal hint. Built once at boot; the stats line is filled when the run is won.
func _build_victory_layer() -> void:
	_victory_layer = CanvasLayer.new()
	_victory_layer.layer = 20   # above the panels (layer 10)
	add_child(_victory_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.06, 0.04, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_layer.add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_layer.add_child(cc)

	# The card: raised slate fill + gold hairline border, matching the menu identity.
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.07, 0.10, 0.08)
	csb.border_color = UI_ACCENT
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 56; csb.content_margin_right = 56
	csb.content_margin_top = 40; csb.content_margin_bottom = 40
	card.add_theme_stylebox_override("panel", csb)
	cc.add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Baked tree crest (the Mother Tree stands).
	var crest := _tex_rect(_glyph_tree(64), 64)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(crest)
	box.add_child(_spacer(6))

	_victory_label = Label.new()
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.add_theme_font_size_override("font_size", 44)
	_victory_label.add_theme_color_override("font_color", UI_ACCENT)
	_victory_label.text = "VICTORY"
	_victory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_victory_label)

	var epitaph := Label.new()
	epitaph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epitaph.add_theme_font_size_override("font_size", 18)
	epitaph.add_theme_color_override("font_color", Color(0.85, 0.90, 0.86))
	epitaph.text = "All Crocodile Dens cleared.\nThe Mother Tree stands. The island is yours."
	epitaph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(epitaph)
	box.add_child(_spacer(10))

	_victory_stats = Label.new()
	_victory_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_stats.add_theme_font_size_override("font_size", 16)
	_victory_stats.add_theme_color_override("font_color", UI_POWER)
	_victory_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_victory_stats)
	box.add_child(_spacer(14))

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	hint.text = "[ press any key for a new run ]"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	_victory_layer.visible = false


func _make_vignette_tex() -> ImageTexture:
	var sz := 128
	var im := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz, sz) * 0.5
	var maxd := float(sz) * 0.5
	for y in range(sz):
		for x in range(sz):
			var d := Vector2(x, y).distance_to(c) / maxd
			im.set_pixel(x, y, Color(0.75, 0.05, 0.05, smoothstep(0.55, 1.05, d)))
	return ImageTexture.create_from_image(im)


func _make_panel(layer: CanvasLayer, left: bool) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = UI_SLATE
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0
	if left:
		bg.anchor_left = 0.0
		bg.anchor_right = 0.0
		bg.offset_left = 0.0
		bg.offset_right = PANEL_W
	else:
		bg.anchor_left = 1.0
		bg.anchor_right = 1.0
		bg.offset_left = -PANEL_W
		bg.offset_right = 0.0
	layer.add_child(bg)

	# Accent border on the inner edge (toward the board).
	var border := ColorRect.new()
	border.color = UI_BORDER
	border.anchor_top = 0.0
	border.anchor_bottom = 1.0
	if left:
		border.anchor_left = 1.0
		border.anchor_right = 1.0
		border.offset_left = -3.0
		border.offset_right = 0.0
	else:
		border.anchor_left = 0.0
		border.anchor_right = 0.0
		border.offset_left = 0.0
		border.offset_right = 3.0
	bg.add_child(border)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	bg.add_child(margin)

	# A ScrollContainer so a tall panel (long build/craft lists, full inventory)
	# never spills past the bottom -- it just scrolls.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	if _ui_theme:
		vbox.theme = _ui_theme
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


func _apply_theme() -> void:
	# The one programmatic Theme: a real visual identity applied at each CanvasLayer
	# root (side panels, menu, tooltip) so font sizes / palette / slot+card+button
	# StyleBoxFlats cascade to every control instead of being re-declared inline.
	# Retained-panel model: this builds the Theme ONCE at boot -- no per-frame rebuild.
	var t := Theme.new()

	# --- Font sizes (type defaults; helpers may still bump a header/caption) ----
	t.set_font_size("font_size", "Label", FS_BODY)
	t.set_font_size("font_size", "Button", FS_BUTTON)
	t.set_font_size("font_size", "LineEdit", FS_BODY)

	# --- Text palette ----------------------------------------------------------
	t.set_color("font_color", "Label", UI_TEXT)
	t.set_color("font_color", "Button", UI_TEXT)
	t.set_color("font_hover_color", "Button", UI_TEXT)
	t.set_color("font_pressed_color", "Button", UI_ACCENT)
	t.set_color("font_focus_color", "Button", UI_TEXT)
	t.set_color("font_disabled_color", "Button", UI_TEXT_MUTE)

	# --- Button cards: a raised UI_PANEL_2 chip with a hairline border, gold-on-
	# press, brightened border on hover/focus. Replaces the default grey buttons
	# scattered across station panels and the inventory action rows.
	t.set_stylebox("normal", "Button", _theme_box(UI_PANEL_2, UI_BORDER, 1, 4, 5, 3))
	t.set_stylebox("hover", "Button", _theme_box(UI_PANEL_2.lightened(0.06), UI_BORDER_HI, 1, 4, 5, 3))
	t.set_stylebox("pressed", "Button", _theme_box(UI_SLATE, UI_ACCENT, 1, 4, 5, 3))
	t.set_stylebox("focus", "Button", _theme_box(Color(0, 0, 0, 0), UI_BORDER_HI, 1, 4, 5, 3))
	t.set_stylebox("disabled", "Button", _theme_box(UI_SLOT_BG, UI_BORDER, 1, 4, 5, 3))

	# --- Panels / cards: PanelContainer (e.g. docked-station cards) gets the
	# raised-card fill + border so a card reads as one step above the slate panel.
	t.set_stylebox("panel", "PanelContainer", _theme_box(UI_PANEL_2, UI_BORDER, 1, 4, 8, 8))

	# --- Separators: a single hairline in the divider color. ----------------
	var sep := StyleBoxFlat.new()
	sep.bg_color = UI_BORDER
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)

	# --- Progress bars: deep trough + gold fill (overridden per-bar by _make_bar
	# for the health/energy/xp colors, but this is the unstyled default). --------
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = UI_BAR_BG
	bar_bg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = UI_ACCENT
	bar_fill.set_corner_radius_all(3)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", UI_TEXT)

	_ui_theme = t


# Small StyleBoxFlat factory for the programmatic Theme: a filled, rounded, bordered
# box. Keeps _apply_theme readable and the corner/border numbers in one grammar.
func _theme_box(fill: Color, border: Color, border_w: int, radius: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y
	return sb


func _header(text: String) -> Label:
	# Section header: diverges from the Theme's Label default -- larger + gold.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_HEADER)
	l.add_theme_color_override("font_color", UI_ACCENT)
	return l


func _label(text: String) -> Label:
	# Body label: the Theme already supplies FS_BODY / UI_TEXT as the Label default,
	# so this just carries text. Color routes through the const for any untheme'd use.
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UI_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_W - 28.0
	return l


func _sep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI_BORDER
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	s.add_theme_stylebox_override("separator", sb)
	return s


func _icon_row(color: Color, lbl: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := ColorRect.new()
	icon.color = color
	icon.custom_minimum_size = Vector2(16, 16)
	row.add_child(icon)
	row.add_child(lbl)
	return row


func _make_bar(fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 100.0
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", sb)
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = UI_BAR_BG
	bgsb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bgsb)
	return b


func _update_status() -> void:
	if not _lbl_time:
		return
	var mins := int(_time * 24.0 * 60.0)
	var part := "day" if _daylight(_time) >= 0.35 else "night"
	_lbl_time.text = "Day %d   %02d:%02d  (%s)" % [_day, mins / 60, mins % 60, part]
	if _msg_timer > 0.0:
		_lbl_threat.text = _msg
		# Blue = tutorial, amber = transient threat/status. The player learns the code.
		_lbl_threat.add_theme_color_override("font_color", ONBOARD_TINT if _msg_onboard else Color(1.0, 0.85, 0.35))
	elif _is_night:
		_lbl_threat.text = "NIGHT - monsters: %d" % _monsters.size()
		_lbl_threat.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		_lbl_threat.text = "Daytime - gather & build"
		_lbl_threat.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	for i in range(_life_pips.size()):
		_life_pips[i].color = Color(0.85, 0.25, 0.25) if i < _lives else Color(0.22, 0.22, 0.26)
	# Breadcrumb: a mid-fight tier-up unlocks tech; nudge the player to the Tree even
	# while the overlay is closed. Clears when acknowledged (overlay opened) or 25s.
	var nudge := ""
	if _active_overlay != Overlay.TECH and _tech_new_until > _now_secs():
		nudge = "    NEW TECH"
	_lbl_nights.text = "Nights survived: %d   (best %d)%s" % [_nights_survived, _best_nights, nudge]
	if nudge != "":
		_lbl_nights.add_theme_color_override("font_color", UI_ACCENT)
	else:
		_lbl_nights.add_theme_color_override("font_color", UI_TEXT)
	_bar_health.max_value = _p_max_health
	_bar_health.value = _health
	_lbl_health.text = "Health  %d / %d" % [int(_health), int(_p_max_health)]
	_bar_energy.value = _energy
	var warn := "   EXHAUSTED!" if _energy <= 0.0 else ""
	_lbl_energy.text = "Energy  %d / %d%s" % [int(_energy), int(ENERGY_MAX), warn]
	_bar_hydration.max_value = HYDRATION_MAX
	_bar_hydration.value = _hydration
	var hwarn := "   PARCHED!" if _hydration <= 0.0 else ""
	_lbl_hydration.text = "Hydration  %d / %d%s" % [int(_hydration), int(HYDRATION_MAX), hwarn]
	_lbl_level.text = "LEVEL %d" % _level
	if _stat_points > 0:
		_lbl_level.text += "  (+%d!)" % _stat_points
	_bar_xp.max_value = _xp_to_next
	_bar_xp.value = _xp
	_lbl_xp.text = "XP %d / %d" % [_xp, _xp_to_next]
	var tool_name: String = TOOL_DEFS[_tool_equipped]["label"] if TOOL_DEFS.has(_tool_equipped) else "none"
	_lbl_stats.text = "Atk %d   Armor %d%%\nSpd %.2fx   Regen %.1f/s\nTool: %s   Weapon: %s" % [
		int(round(_p_attack)), int(round(_p_armor * 100.0)),
		_p_speed / PLAYER_SPEED, _p_regen,
		tool_name, String(_weapon()["label"])
	]
	_lbl_wood.text = "Wood:  %d" % _inv("wood")
	_lbl_stone.text = "Stone: %d" % _inv("stone")
	var food_bits := []
	if _inv("banana") > 0: food_bits.append("Banana %d" % _inv("banana"))
	if _inv("berry") > 0: food_bits.append("Berry %d" % _inv("berry"))
	var rot := _inv("rotten_banana") + _inv("rotten_berry")
	if rot > 0: food_bits.append("Rotten %d" % rot)
	_lbl_food.text = "Food:  " + (", ".join(food_bits) if not food_bits.is_empty() else "none")


func _mark_workspace_dirty() -> void:
	_workspace_dirty = true
	if _workspace_refresh_queued:
		return
	_workspace_refresh_queued = true
	call_deferred("_refresh_workspace")


func _refresh_workspace() -> void:
	_workspace_refresh_queued = false
	if not _workspace_dirty or not _right_vbox:
		return
	_workspace_dirty = false
	if not _right_vbox:
		return

	# The TECH hub is a dedicated full-screen overlay (not part of the right strip);
	# rebuild it on the same coalesced dirty path so deposits/tier-ups refresh it live.
	var tech_open := _active_overlay == Overlay.TECH
	if _tech_root:
		_tech_root.visible = tech_open
	if tech_open and _tech_body:
		_build_tech_overlay_panel()

	for c in _right_vbox.get_children():
		_right_vbox.remove_child(c)
		c.queue_free()

	if _active_overlay == Overlay.LEVELUP:
		_build_levelup_panel()
	elif _active_overlay == Overlay.TECH:
		# Right strip stays on the inventory beneath the full-screen hub.
		_build_inventory_panel()
	elif _build_mode:
		_build_inventory_panel()
		_right_vbox.add_child(_sep())
		_build_build_panel()
	else:
		_build_inventory_panel()
		if not _is_night:
			_right_vbox.add_child(_sep())
			_build_craft_panel()
		if _docked_station >= 0:
			_right_vbox.add_child(_sep())
			_build_docked_station_panel(_docked_station)
		else:
			_right_vbox.add_child(_sep())
			_build_help_panel()


func _build_docked_station_panel(idx: int) -> void:
	if idx < 0 or idx >= _terrain.size() or _chebyshev(_cell, _index_cell(idx)) > 1:
		_clear_docked_station()
		return
	var t := int(_terrain[idx])
	if t == Terrain.TURRET:
		_build_turret_panel(idx)
	elif t == Terrain.STORAGE:
		_build_storage_panel(idx)
	else:
		_build_util_panel(idx)


# Full-screen 3-column TECH hub. Repopulates _tech_body each rebuild (title bar +
# columns). Opening it acknowledges any live NEW marker (advances _tech_seen_tier).
func _build_tech_overlay_panel() -> void:
	# Acknowledge the NEW-tech breadcrumb the moment the player arrives at the Tree.
	if _tree_tier > _tech_seen_tier:
		_tech_seen_tier = _tree_tier
		_tech_new_until = 0.0

	for c in _tech_body.get_children():
		_tech_body.remove_child(c)
		c.queue_free()

	# --- Title bar -----------------------------------------------------------
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size.y = 56
	var title := Label.new()
	title.text = "MOTHER TREE -- TECH"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UI_ACCENT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(title)
	var tspacer := Control.new()
	tspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(tspacer)
	var close := Button.new()
	close.text = "Close  (Esc)"
	close.custom_minimum_size = Vector2(120, 44)
	close.pressed.connect(_close_active_overlay)
	title_bar.add_child(close)
	_tech_body.add_child(title_bar)
	_tech_body.add_child(_sep())

	# --- Columns -------------------------------------------------------------
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tech_body.add_child(cols)

	var col1 := _tech_card(cols, "TREE STATUS", 1.0)
	cols.add_child(_tech_vrule())
	var col2 := _tech_card(cols, "TECH", 1.35)
	cols.add_child(_tech_vrule())
	var col3 := _tech_card(cols, "THREAT", 0.9)

	_build_tech_col_status(col1)
	_build_tech_col_tree(col2)
	_build_tech_col_threat(col3)


# One column card: PanelContainer (recessed fill) -> Margin(16) -> ScrollContainer ->
# VBox(sep 8). Adds the card to `parent`, drops a 20px header + separator, returns
# the inner VBox for cells.
func _tech_card(parent: Container, title: String, stretch: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = stretch
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11)   # one notch darker than UI_SLATE -> recessed
	sb.border_color = UI_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	pc.add_child(margin)
	# Scroll so the deposit list / den ledger never clip on the 1280x720 window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	var hdr := Label.new()
	hdr.text = title
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", UI_ACCENT)
	vb.add_child(hdr)
	vb.add_child(_sep())
	return vb


func _tech_vrule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UI_BORDER
	r.custom_minimum_size.x = 2
	return r


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	return l


# A body label that word-wraps and expands, so long threat lines never force a
# column wider than its share of the screen (keeps the 1280-wide window legible).
func _wrap_label(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# --- COL 1: TREE STATUS -----------------------------------------------------
func _build_tech_col_status(col: VBoxContainer) -> void:
	var max_hp := _tree_max_hp()
	var next := _tree_sap_to_next()

	# Tier badge: baked tree glyph + "TIER n / 5".
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	tier_row.add_child(_tex_rect(_glyph_tree(28), 28))
	var tlbl := Label.new()
	tlbl.add_theme_font_size_override("font_size", 26)
	tlbl.text = "TIER %d" % _tree_tier
	tlbl.add_theme_color_override("font_color", UI_ACCENT)
	tier_row.add_child(tlbl)
	var tslash := Label.new()
	tslash.add_theme_font_size_override("font_size", 26)
	tslash.text = " / 5"
	tslash.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	tier_row.add_child(tslash)
	col.add_child(tier_row)

	# HP bar with a hard-banded fill + centered value overlay.
	var hp_frac := _tree_hp / max_hp if max_hp > 0.0 else 0.0
	col.add_child(_tech_value_bar(hp_frac, _hp_color(hp_frac),
		"%d / %d" % [int(_tree_hp), int(max_hp)], 22))

	col.add_child(_icon_row(Color(0.45, 0.80, 1.0, 0.9),
		_label("Aura radius  %d cells" % _tree_aura_radius())))
	col.add_child(_dim_label("Heals +%d%% each dawn" % int(FP_TREE_DAWN_REGEN_FRAC * 100.0)))
	col.add_child(_sep())

	# Sap counter + progress to next tier.
	var sap_row := HBoxContainer.new()
	sap_row.add_theme_constant_override("separation", 8)
	sap_row.add_child(_tex_rect(_glyph_sap_drop(22), 22))
	var slbl := Label.new()
	slbl.add_theme_font_size_override("font_size", 22)
	slbl.text = "%.0f Sap" % _sap
	slbl.add_theme_color_override("font_color", Color(0.95, 0.74, 0.22))
	sap_row.add_child(slbl)
	col.add_child(sap_row)
	if _tree_tier >= 5:
		var maxl := _label("MAX TIER")
		maxl.add_theme_color_override("font_color", UI_ACCENT)
		col.add_child(maxl)
	else:
		var sap_frac := clampf(_sap / next, 0.0, 1.0) if next > 0.0 else 0.0
		col.add_child(_tech_value_bar(sap_frac, Color(0.95, 0.74, 0.22),
			"%.0f / %.0f to Tier %d" % [_sap, next, _tree_tier + 1], 20))
	col.add_child(_sep())

	# DEPOSIT -> Sap. The only interactive part of Col-1.
	col.add_child(_dim_label("DEPOSIT  ->  Sap"))
	for k in FP_SAP_CONVERSION:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = ITEM_CATEGORY_TINT.get(k, UI_TEXT)
		sw.custom_minimum_size = Vector2(16, 16)
		row_box.add_child(sw)
		var item := _label("%s x%d" % [ITEM_LABELS.get(k, k), _inv(k)])
		item.custom_minimum_size.x = 110
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_child(item)
		var rate := _dim_label("(x%.1f)" % float(FP_SAP_CONVERSION[k]))   # teaches metal>berry
		rate.custom_minimum_size.x = 40
		row_box.add_child(rate)
		var have := _inv(k)
		var b1 := Button.new()
		b1.text = "+1"; b1.custom_minimum_size.x = 30; b1.disabled = have <= 0
		b1.pressed.connect(_deposit_sap.bind(k, 1))
		row_box.add_child(b1)
		var b5 := Button.new()
		b5.text = "+5"; b5.custom_minimum_size.x = 30; b5.disabled = have <= 0
		b5.pressed.connect(_deposit_sap.bind(k, mini(5, have)))
		row_box.add_child(b5)
		var ball := Button.new()
		ball.text = "All"; ball.custom_minimum_size.x = 40; ball.disabled = have <= 0
		ball.pressed.connect(_deposit_sap.bind(k, have))
		row_box.add_child(ball)
		col.add_child(row_box)


# --- COL 2: TECH TREE (focus column) ----------------------------------------
func _build_tech_col_tree(col: VBoxContainer) -> void:
	col.add_child(_dim_label("Grow the Tree to unlock new branches."))
	var now := _now_secs()
	var new_live := _tech_new_until > now
	for row in TECH_ROWS:
		col.add_child(_tech_branch_row(row, new_live))
	# Footer: name the next concrete goal (the "what to farm next" anchor).
	var foot: Label
	if _tree_tier >= 5:
		foot = _dim_label("All tech unlocked.")
	else:
		var to_next := maxf(0.0, _tree_sap_to_next() - _sap)
		var next_branch := "?"
		for row in TECH_ROWS:
			if int(row["tier"]) == _tree_tier + 1:
				next_branch = String(row["branch"])
				break
		foot = _dim_label("Next: deposit %.0f more Sap to unlock %s." % [to_next, next_branch])
	col.add_child(_sep())
	col.add_child(foot)


# One branch row card. State = unlocked / locked / NEW (just-unlocked this tier-up).
func _tech_branch_row(row: Dictionary, new_live: bool) -> PanelContainer:
	var tier := int(row["tier"])
	var branch := String(row["branch"])
	var unlocked := _tree_tier >= tier
	var is_new := unlocked and new_live and tier == _tree_tier
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if is_new:
		sb.bg_color = Color(0.10, 0.13, 0.11)
		sb.border_color = UI_ACCENT
		sb.set_border_width_all(1)
	elif unlocked:
		sb.bg_color = Color(0.10, 0.13, 0.11)
	else:
		sb.bg_color = Color(0.08, 0.08, 0.10)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	# State pip: filled green disc (unlocked) or hollow ring (locked).
	hb.add_child(_tex_rect(_glyph_pip(12, unlocked), 12))
	var lead := Label.new()
	lead.add_theme_font_size_override("font_size", 13)
	lead.text = "TIER %d - %s" % [tier, branch]
	lead.add_theme_color_override("font_color", TECH_BRANCH_HUE.get(branch, UI_TEXT) if unlocked else Color(0.48, 0.51, 0.58))
	lead.custom_minimum_size.x = 120
	hb.add_child(lead)
	var body := Label.new()
	body.add_theme_font_size_override("font_size", 15)
	if unlocked:
		body.text = String(row["label"])
		body.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	else:
		body.text = "%s  -- needs Tier %d" % [String(row["label"]), tier]
		body.add_theme_color_override("font_color", Color(0.48, 0.51, 0.58))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(body)
	if is_new:
		var pill := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = UI_ACCENT
		psb.set_corner_radius_all(8)
		psb.content_margin_left = 6; psb.content_margin_right = 6
		psb.content_margin_top = 1; psb.content_margin_bottom = 1
		pill.add_theme_stylebox_override("panel", psb)
		var pl := Label.new()
		pl.text = "NEW"
		pl.add_theme_font_size_override("font_size", 12)
		pl.add_theme_color_override("font_color", Color(0.08, 0.08, 0.10))
		pill.add_child(pl)
		hb.add_child(pill)
	pc.add_child(hb)
	return pc


# --- COL 3: THREAT ----------------------------------------------------------
func _build_tech_col_threat(col: VBoxContainer) -> void:
	# Dens alive (count colored: green if winning, amber 1-2, red 3+).
	var n_dens := _dens.size()
	var dens_row := HBoxContainer.new()
	dens_row.add_theme_constant_override("separation", 8)
	dens_row.add_child(_tex_rect(_glyph_den(24), 24))
	var dlbl := Label.new()
	dlbl.add_theme_font_size_override("font_size", 22)
	dlbl.text = "%d / %d Dens" % [n_dens, FP_DEN_CAP]
	var dcol := HP_GREEN if n_dens == 0 else (HP_AMBER if n_dens <= 2 else HP_RED)
	dlbl.add_theme_color_override("font_color", dcol)
	dens_row.add_child(dlbl)
	col.add_child(dens_row)

	if _dens.is_empty() and _tree_tier >= 3:
		var wl := _label("ISLAND CLEARED")
		wl.add_theme_color_override("font_color", UI_ACCENT)
		col.add_child(wl)
	else:
		col.add_child(_dim_label("Win: clear all Dens at Tree Tier 3+"))
	col.add_child(_sep())

	# Next-Den ETA.
	if _dens.size() >= FP_DEN_CAP:
		col.add_child(_dim_label("Den frontier at cap"))
	else:
		var next_den := FP_DEN_NEW_EVERY_NIGHTS - (_nights_survived % FP_DEN_NEW_EVERY_NIGHTS)
		col.add_child(_icon_row(Color(0.70, 0.74, 0.82),
			_wrap_label("Next Den erupts in %d night%s" % [next_den, "" if next_den == 1 else "s"])))
	col.add_child(_icon_row(Color(0.60, 0.66, 0.85),
		_wrap_label("Night %d survived  (best %d)" % [_nights_survived, _best_nights])))
	col.add_child(_sep())

	# Den ledger, closest first.
	col.add_child(_dim_label("DENS"))
	var tree_cell := _tree_center_cell()
	var ledger := []
	for id in _dens:
		var d: Dictionary = _dens[id]
		ledger.append({"d": d, "dist": _chebyshev(d["origin"], tree_cell)})
	ledger.sort_custom(func(a, b): return int(a["dist"]) < int(b["dist"]))
	var dn := 0
	for entry in ledger:
		dn += 1
		col.add_child(_tech_den_row(dn, entry["d"], int(entry["dist"])))
	col.add_child(_sep())

	# Casings + dawn sweep.
	col.add_child(_icon_row(Color(0.72, 0.60, 0.28),
		_label("%d casings in field" % _casings.size())))
	var sweep := Button.new()
	sweep.text = "Sweep Casings (dawn only)"
	sweep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sweep.disabled = _is_night or _casings.is_empty()
	sweep.pressed.connect(_sweep_casings)
	col.add_child(sweep)


func _tech_den_row(n: int, d: Dictionary, dist: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_tex_rect(_glyph_den(12), 12))
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.text = "Den #%d" % n
	name_lbl.custom_minimum_size.x = 56
	hb.add_child(name_lbl)
	var mature := int(d["size"]) >= 3 or int(d["maturity"]) >= FP_DEN_EVOLVE_MATURITY
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 13)
	if mature:
		tag.text = "MATURE"
		tag.add_theme_color_override("font_color", Color(0.90, 0.45, 0.40))
	else:
		tag.text = "young"
		tag.add_theme_color_override("font_color", Color(0.55, 0.80, 0.55))
	tag.custom_minimum_size.x = 56
	hb.add_child(tag)
	var max_hp := float(d["max_hp"])
	var frac := float(d["hp"]) / max_hp if max_hp > 0.0 else 0.0
	hb.add_child(_mini_hp_bar(frac, 60, 10))
	var dl := _dim_label("dist %d" % dist)
	dl.add_theme_font_size_override("font_size", 13)
	hb.add_child(dl)
	return hb


# Two stacked ColorRects in a fixed-size frame = a cheap per-row HP bar (no full
# ProgressBar per Den). Trough + width-scaled hard-banded fill.
func _mini_hp_bar(frac: float, w: int, h: int) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = UI_BAR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(bg)
	var fill := ColorRect.new()
	fill.color = _hp_color(frac)
	fill.position = Vector2.ZERO
	fill.size = Vector2(maxf(1.0, w * clampf(frac, 0.0, 1.0)), h)
	frame.add_child(fill)
	return frame


# A ProgressBar-backed bar with a centered value Label overlaid (Tree HP / Sap).
func _tech_value_bar(frac: float, fill: Color, text: String, h: int) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size.y = h
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := _make_bar(fill)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.value = clampf(frac, 0.0, 1.0) * 100.0
	frame.add_child(bar)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(lbl)
	return frame


# --- TECH-hub baked glyphs (12-28px, _disc/_rect only -- zero external assets) --
func _tex_rect(tex: ImageTexture, sz: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(sz, sz)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


func _glyph_tree(sz: int) -> ImageTexture:
	var im := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var trunk_w := maxi(2, sz / 7)
	_rect(im, sz / 2 - trunk_w / 2, sz / 2, trunk_w, sz / 2 - 2, Color(0.40, 0.28, 0.14))
	_disc(im, sz / 2, sz / 2 - sz / 8, sz / 3, Color(0.30, 0.62, 0.28))
	return _mktex(im)


func _glyph_sap_drop(sz: int) -> ImageTexture:
	var im := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	_disc(im, sz / 2, sz / 2 + 1, sz / 2 - 2, Color(0.95, 0.74, 0.22))
	_rect(im, sz / 2 - 1, 2, 2, 3, Color(1.0, 0.92, 0.6))   # highlight
	return _mktex(im)


func _glyph_pip(sz: int, filled: bool) -> ImageTexture:
	var im := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	if filled:
		_disc(im, sz / 2, sz / 2, sz / 2 - 1, Color(0.40, 0.78, 0.42))
	else:
		_disc(im, sz / 2, sz / 2, sz / 2 - 1, Color(0.40, 0.43, 0.50))
		_disc_clear(im, sz / 2, sz / 2, sz / 2 - 3)   # hollow ring
	return _mktex(im)


func _glyph_den(sz: int) -> ImageTexture:
	var im := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	_rect(im, 1, 1, sz - 2, sz - 2, Color(0.20, 0.12, 0.10))
	_speckle(im, Color(0.78, 0.22, 0.18), Color(0.55, 0.18, 0.14), 7)
	return _mktex(im)


func _close_active_overlay() -> void:
	_active_overlay = Overlay.NONE
	if _tech_root:
		_tech_root.visible = false
	_mark_workspace_dirty()


# --- Options / window resolution ---------------------------------------------
func _set_window_size(sz: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(sz)
	var scr := DisplayServer.window_get_current_screen()
	var su := DisplayServer.screen_get_size(scr)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(scr) + (su - sz) / 2)


func _set_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# -----------------------------------------------------------------------------
# Title screen, main menu, settings overlay, and game save/load
# -----------------------------------------------------------------------------
func _build_menu_layer() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 100   # above everything (panels are layer 10)
	_menu_layer.visible = false
	add_child(_menu_layer)

	# Splash card: opaque black with a centred dedication.
	_splash_root = _overlay_root(1.0)
	var splash_box := _center_box(_splash_root)
	var dedication := Label.new()
	dedication.text = "For William."
	dedication.add_theme_font_size_override("font_size", 52)
	dedication.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	dedication.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash_box.add_child(dedication)
	_menu_layer.add_child(_splash_root)

	# Main menu.
	_menu_root = _overlay_root(1.0)
	var menu_box := _center_box(_menu_root)
	var mtitle := Label.new()
	mtitle.text = "GOLIRADILE ISLE"
	mtitle.add_theme_font_size_override("font_size", 46)
	mtitle.add_theme_color_override("font_color", UI_ACCENT)
	mtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(mtitle)
	var msub := Label.new()
	msub.text = "a gorilla-versus-crocodile survival island"
	msub.add_theme_font_size_override("font_size", 16)
	msub.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	msub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(msub)
	menu_box.add_child(_spacer(18))
	_menu_btns = VBoxContainer.new()
	_menu_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_btns.add_theme_constant_override("separation", 10)
	menu_box.add_child(_menu_btns)
	menu_box.add_child(_spacer(14))
	_lbl_menu_best = Label.new()
	_lbl_menu_best.add_theme_font_size_override("font_size", 15)
	_lbl_menu_best.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	_lbl_menu_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(_lbl_menu_best)
	_menu_layer.add_child(_menu_root)

	# Confirm dialog (for New Game), shown over the menu.
	_confirm_root = _overlay_root(0.95)
	_confirm_root.visible = false
	var cbox := _center_box(_confirm_root)
	var cq := Label.new()
	cq.text = "Start a NEW GAME?\nYour saved game will be erased."
	cq.add_theme_font_size_override("font_size", 22)
	cq.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	cq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(cq)
	cbox.add_child(_spacer(16))
	cbox.add_child(_menu_button("Yes, erase and start fresh", _confirm_new_game))
	cbox.add_child(_menu_button("Cancel", _cancel_new_game))
	_menu_layer.add_child(_confirm_root)

	# Settings overlay (controls + video), reachable from menu and in-game.
	_settings_root = _overlay_root(0.96)
	var sbox := _center_box(_settings_root)
	var stitle := Label.new()
	stitle.text = "SETTINGS"
	stitle.add_theme_font_size_override("font_size", 40)
	stitle.add_theme_color_override("font_color", UI_ACCENT)
	stitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sbox.add_child(stitle)
	sbox.add_child(_spacer(10))
	sbox.add_child(_settings_label("CONTROLS", 22, UI_ACCENT))
	for line in [
		"WASD - move          Left-click - gather / punch (aim at cursor)",
		"B build   C craft   I inventory   E eat   Q drink",
		"Save Game / Settings / Main Menu - buttons on the left panel",
	]:
		sbox.add_child(_settings_label(line, 16, Color(0.9, 0.92, 0.95)))
	sbox.add_child(_spacer(14))
	sbox.add_child(_settings_label("VIDEO", 22, UI_ACCENT))
	sbox.add_child(_settings_label("Window size (the whole view scales to fit):", 16, Color(0.9, 0.92, 0.95)))
	var sizes_row := HBoxContainer.new()
	sizes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sizes_row.add_theme_constant_override("separation", 8)
	for sz in WINDOW_SIZES:
		var b := Button.new()
		b.text = "%d x %d" % [sz.x, sz.y]
		b.pressed.connect(_set_window_size.bind(sz))
		sizes_row.add_child(b)
	var fb := Button.new()
	fb.text = "Fullscreen"
	fb.pressed.connect(_set_fullscreen)
	sizes_row.add_child(fb)
	sbox.add_child(sizes_row)
	sbox.add_child(_spacer(18))
	sbox.add_child(_menu_button("Back", _close_settings))
	_menu_layer.add_child(_settings_root)


func _overlay_root(dim: float) -> Control:
	# A full-screen control with a (semi-)opaque black backing that eats clicks,
	# so nothing behind the overlay receives input.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if _ui_theme:
		root.theme = _ui_theme   # menu/settings/confirm buttons inherit the identity
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	return root


func _center_box(parent: Control) -> VBoxContainer:
	# A CenterContainer (filling `parent`) holding a centred VBox, returned for content.
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	cc.add_child(box)
	return box


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _settings_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


# --- State transitions -------------------------------------------------------
func _set_overlay(mode: String) -> void:
	_menu_layer.visible = mode != "none"
	_splash_root.visible = mode == "splash"
	_menu_root.visible = mode == "menu"
	_settings_root.visible = mode == "settings"
	if mode != "menu":
		_confirm_root.visible = false


func _enter_splash() -> void:
	_app_state = AppState.SPLASH
	_splash_t = 0.0
	_splash_root.modulate.a = 1.0
	_set_overlay("splash")


func _tick_splash(delta: float) -> void:
	_splash_t += delta
	if _splash_t >= SPLASH_HOLD:
		var fade := (_splash_t - SPLASH_HOLD) / SPLASH_FADE
		_splash_root.modulate.a = clampf(1.0 - fade, 0.0, 1.0)
		if fade >= 1.0:
			_enter_menu()


func _enter_menu() -> void:
	_app_state = AppState.MENU
	_refresh_menu()
	_set_overlay("menu")


func _refresh_menu() -> void:
	for c in _menu_btns.get_children():
		_menu_btns.remove_child(c)
		c.queue_free()
	var has_save := FileAccess.file_exists(GAME_SAVE_PATH)
	if has_save:
		_menu_btns.add_child(_menu_button("Load Game", _menu_load))
		_menu_btns.add_child(_menu_button("New Game", _menu_new_game))
	else:
		_menu_btns.add_child(_menu_button("Start Game", _menu_start))
	_menu_btns.add_child(_menu_button("Settings", _open_settings.bind(AppState.MENU)))
	_menu_btns.add_child(_menu_button("Quit Game", _menu_quit))
	_lbl_menu_best.text = "Best nights survived: %d" % _best_nights


func _menu_start() -> void:
	_reset_game()
	_enter_playing()


func _menu_load() -> void:
	if not _load_game():
		_reset_game()
	_enter_playing()


func _menu_new_game() -> void:
	_confirm_root.visible = true


func _confirm_new_game() -> void:
	_delete_save()
	_reset_game()
	_enter_playing()


func _cancel_new_game() -> void:
	_confirm_root.visible = false


func _menu_quit() -> void:
	get_tree().quit()


func _open_settings(return_state: int) -> void:
	_settings_return = return_state
	_app_state = AppState.SETTINGS
	_set_overlay("settings")


func _close_settings() -> void:
	if _settings_return == AppState.PLAYING:
		_enter_playing()
	else:
		_enter_menu()


func _enter_playing() -> void:
	_app_state = AppState.PLAYING
	_set_overlay("none")
	# Keystone teaching beat: fires once ever (persisted), so it lands on the first
	# fresh run and never replays on a resumed game.
	_onboard("welcome", "This is the Mother Tree. Keep it alive -- if it dies, the island is lost. Gather wood, stone, and grass by day. Stand by the Mother Tree and click it to open its hub -- deposit Sap there to grow it and unlock tech.", 8.0)
	_mark_workspace_dirty()
	_update_status()
	queue_redraw()


# --- Full game-state save / load ---------------------------------------------
func _delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("goliradile_isle_game.save"):
		dir.remove("goliradile_isle_game.save")


func _has_game_save() -> bool:
	return FileAccess.file_exists(GAME_SAVE_PATH)


func _serialize_state() -> Dictionary:
	return {
		"v": 1,
		"seed": _seed,
		"terrain": _terrain, "banana": _banana, "berry": _berry, "growth": _growth,
		"block_count": _block_count,
		"cell": _cell, "facing": _facing, "player_pos": _player_pos,
		"health": _health, "energy": _energy, "hydration": _hydration, "lives": _lives,
		"level": _level, "xp": _xp, "xp_to_next": _xp_to_next,
		"nights": _nights_survived, "stat_points": _stat_points, "alloc": _alloc,
		"tool": _tool_equipped, "weapon": _weapon_equipped, "gear_armor": _gear_armor,
		"resources": _resources,
		"sap": _sap,
		"tree_tier": _tree_tier, "tree_hp": _tree_hp,
		"downed": _downed, "downed_timer": _downed_timer,
		"dens": _dens, "won": _won,
		"time": _time, "day": _day, "banana_timer": _banana_timer, "is_night": _is_night,
		"barrels": _barrels, "juicers": _juicers, "planters": _planters, "lamps": _lamps,
		"kilns": _kilns, "apiaries": _apiaries, "wormfarms": _wormfarms, "campfires": _campfires,
		"stills": _stills, "generators": _generators, "sprinklers": _sprinklers,
		"aquariums": _aquariums, "miners": _miners, "autoloaders": _autoloaders,
		"casings": _casings, "fish": _fish, "monsters": _monsters,
		"projectiles": _projectiles, "poison_clouds": _poison_clouds,
		"night_snapshot": _night_snapshot, "struct_hp": _struct_hp, "wrecks": _wrecks, "turrets": _turrets,
		"trap_cd": _trap_cd, "traps": _traps, "peels": _peels, "storage": _storage,
		"burn_t": _burn_t, "slow_t": _slow_t, "freeze_t": _freeze_t,
		"snow_count": _snow_count, "snow_window": _snow_window,
		"best_nights": _best_nights,
		"onboard": _onboard_seen, "tech_seen_tier": _tech_seen_tier,
	}


func _save_game() -> bool:
	var f := FileAccess.open(GAME_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(_serialize_state())
	f.close()
	return true


func _load_game() -> bool:
	if not FileAccess.file_exists(GAME_SAVE_PATH):
		return false
	var f := FileAccess.open(GAME_SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = f.get_var()
	f.close()
	if not (data is Dictionary):
		return false
	_deserialize_state(data as Dictionary)
	return true


func _deserialize_state(d: Dictionary) -> void:
	_seed = int(d.get("seed", _seed))
	if d.has("terrain"): _terrain = d["terrain"]
	if d.has("banana"): _banana = d["banana"]
	if d.has("berry"): _berry = d["berry"]
	if d.has("growth"): _growth = d["growth"]
	_block_count = int(d.get("block_count", 0))
	_cell = d.get("cell", _cell)
	_facing = d.get("facing", _facing)
	_player_pos = d.get("player_pos", _cell_center_world(_cell))
	_health = float(d.get("health", HEALTH_MAX))
	_energy = float(d.get("energy", ENERGY_MAX))
	_hydration = float(d.get("hydration", HYDRATION_MAX))
	_lives = int(d.get("lives", MAX_LIVES))
	_level = int(d.get("level", 1))
	_xp = int(d.get("xp", 0))
	_xp_to_next = int(d.get("xp_to_next", _xp_needed(_level)))
	_nights_survived = int(d.get("nights", 0))
	_stat_points = int(d.get("stat_points", 0))
	_alloc = d.get("alloc", {"health": 0, "attack": 0, "speed": 0, "armor": 0, "regen": 0})
	_tool_equipped = String(d.get("tool", ""))
	_weapon_equipped = String(d.get("weapon", ""))
	_gear_armor = float(d.get("gear_armor", 0.0))
	_resources = d.get("resources", _default_inventory())
	_sap = float(d.get("sap", 0.0))
	_tree_tier = int(d.get("tree_tier", 1))
	_tree_hp = float(d.get("tree_hp", _tree_max_hp(_tree_tier)))
	_downed = bool(d.get("downed", false))
	_downed_timer = float(d.get("downed_timer", 0.0))
	_dens = d.get("dens", {})
	_won = bool(d.get("won", false))
	if _victory_layer:
		_victory_layer.visible = _won
	_time = float(d.get("time", FP_DAY_START))
	_day = int(d.get("day", 1))
	_banana_timer = float(d.get("banana_timer", 0.0))
	_is_night = bool(d.get("is_night", false))
	_barrels = d.get("barrels", {})
	_juicers = d.get("juicers", {})
	_planters = d.get("planters", {})
	_lamps = d.get("lamps", {})
	_kilns = d.get("kilns", {})
	_apiaries = d.get("apiaries", {})
	_wormfarms = d.get("wormfarms", {})
	_campfires = d.get("campfires", {})
	_stills = d.get("stills", {})
	_generators = d.get("generators", {})
	_sprinklers = d.get("sprinklers", {})
	_aquariums = d.get("aquariums", {})
	_miners = d.get("miners", {})
	_autoloaders = d.get("autoloaders", {})
	_casings = d.get("casings", [])
	_fish = d.get("fish", [])
	_monsters = d.get("monsters", [])
	_projectiles = d.get("projectiles", [])
	_poison_clouds = d.get("poison_clouds", [])
	_night_snapshot = d.get("night_snapshot", {})
	_struct_hp = d.get("struct_hp", {})
	_wrecks = d.get("wrecks", {})
	_turrets = d.get("turrets", {})
	_trap_cd = d.get("trap_cd", {})
	_traps = d.get("traps", {})
	_peels = d.get("peels", [])
	_storage = d.get("storage", {})
	_burn_t = float(d.get("burn_t", 0.0))
	_slow_t = float(d.get("slow_t", 0.0))
	_freeze_t = float(d.get("freeze_t", 0.0))
	_snow_count = int(d.get("snow_count", 0))
	_snow_window = float(d.get("snow_window", 0.0))
	_best_nights = int(d.get("best_nights", _best_nights))
	_onboard_seen = d.get("onboard", {})
	_tech_seen_tier = int(d.get("tech_seen_tier", _tree_tier))
	_tech_new_until = 0.0   # transient; never carry a live NEW marker across a load
	_msg_queue.clear()

	# Derived / transient state rebuilt from the restored world.
	_energized = {}
	_watered = {}
	_ensure_mother_tree_footprint(false)
	_sync_tree_generator()
	_rebake_mother_tree()   # restored tier -> matching canopy art (§5)
	if not _won:
		_ensure_den_footprints()
	if not _is_walkable(_cell):
		_cell = _tree_respawn_cell()
		_player_pos = _cell_center_world(_cell)
	_compute_pool_shore()
	_invalidate_flow_fields()
	_ensure_flow_fields()
	_recompute_player_stats()
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_docked_station = -1
	_active_overlay = Overlay.NONE
	_punch_active = false
	_player_kb = Vector2.ZERO
	if _camera:
		_camera.position = _player_pos
	_apply_daylight()


func _build_util_panel(idx: int) -> void:
	match int(_terrain[idx]):
		Terrain.BARREL: _build_barrel_panel(idx)
		Terrain.JUICER: _build_juicer_panel(idx)
		Terrain.PLANTER: _build_planter_panel(idx)
		Terrain.KILN: _build_kiln_panel(idx)
		Terrain.BEE_ENCLOSURE: _build_apiary_panel(idx)
		Terrain.WORM_FARM: _build_wormfarm_panel(idx)
		Terrain.CAMPFIRE: _build_campfire_panel(idx)
		Terrain.STILL: _build_still_panel(idx)
		Terrain.GENERATOR: _build_generator_panel(idx)
		Terrain.AQUARIUM: _build_aquarium_panel(idx)
		Terrain.SPRINKLER: _build_sprinkler_panel(idx)
		Terrain.AUTO_MINER: _build_auto_miner_panel(idx)
		Terrain.AUTO_LOADER: _build_auto_loader_panel(idx)
		Terrain.PEEL_LAUNCHER: _build_peel_panel(idx)
		_: _close_util()


func _build_barrel_panel(idx: int) -> void:
	var b: Dictionary = _barrels.get(idx, {"kind": "", "amount": 0, "ferment": 0.0})
	_right_vbox.add_child(_header("BARREL"))
	var kind: String = b["kind"]
	var label := "empty" if kind == "" else kind
	_right_vbox.add_child(_label("Holds: %s  %d / %d" % [label, int(b["amount"]), BARREL_CAP]))
	if kind == "juice":
		var left: float = maxf(0.0, FERMENT_TIME - float(b["ferment"]))
		_right_vbox.add_child(_label("Fermenting to wine: %ds" % int(left)))
	_right_vbox.add_child(_sep())
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 6)
	var pw := Button.new(); pw.text = "Pour Water"; pw.pressed.connect(_barrel_store.bind(idx, "water"))
	var pj := Button.new(); pj.text = "Pour Juice"; pj.pressed.connect(_barrel_store.bind(idx, "juice"))
	r1.add_child(pw); r1.add_child(pj); _right_vbox.add_child(r1)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 6)
	var tk := Button.new(); tk.text = "Fill Cup"; tk.pressed.connect(_barrel_take.bind(idx))
	var em := Button.new(); em.text = "Empty"; em.pressed.connect(_barrel_empty.bind(idx))
	r2.add_child(tk); r2.add_child(em); _right_vbox.add_child(r2)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Juice left here ferments into"))
	_right_vbox.add_child(_label("berry wine over 2 day/nights."))


func _build_juicer_panel(idx: int) -> void:
	var j: Dictionary = _juicers.get(idx, {"juice": 0, "pending": 0, "conv": 0.0})
	_right_vbox.add_child(_header("JUICER"))
	_right_vbox.add_child(_label("Juice: %d / %d" % [int(j["juice"]), JUICER_CAP]))
	if int(j["pending"]) > 0:
		_right_vbox.add_child(_label("Pressing %d berry..." % int(j["pending"])))
	_right_vbox.add_child(_sep())
	var add := Button.new(); add.text = "Add Berry  (->2 juice)"
	add.pressed.connect(_juicer_add.bind(idx)); _right_vbox.add_child(add)
	var tk := Button.new(); tk.text = "Fill Cup with Juice"
	tk.pressed.connect(_juicer_take.bind(idx)); _right_vbox.add_child(tk)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Loose juice spoils; store it in"))
	_right_vbox.add_child(_label("a barrel to make wine."))


func _build_kiln_panel(idx: int) -> void:
	var kl: Dictionary = _kilns.get(idx, {"fuel": 0.0, "queue": [], "conv": 0.0})
	_right_vbox.add_child(_header("KILN"))
	_right_vbox.add_child(_label("Fuel: %d%%   Queue: %d" % [int(100.0 * float(kl["fuel"]) / KILN_FUEL_MAX), (kl["queue"] as Array).size()]))
	_right_vbox.add_child(_sep())
	var f1 := HBoxContainer.new(); f1.add_theme_constant_override("separation", 6)
	var fw := Button.new(); fw.text = "Stoke (wood)"; fw.pressed.connect(_kiln_fuel.bind(idx, "wood"))
	var fc := Button.new(); fc.text = "Stoke (charcoal)"; fc.pressed.connect(_kiln_fuel.bind(idx, "charcoal"))
	f1.add_child(fw); f1.add_child(fc); _right_vbox.add_child(f1)
	_right_vbox.add_child(_sep())
	var sm := Button.new(); sm.text = "Smelt Ore -> Metal"; sm.pressed.connect(_kiln_load.bind(idx, "metal_ore", "metal"))
	_right_vbox.add_child(sm)
	var gl := Button.new(); gl.text = "Melt Sand -> Glass"; gl.pressed.connect(_kiln_load.bind(idx, "sand", "glass"))
	_right_vbox.add_child(gl)
	var ch := Button.new(); ch.text = "Char Wood -> Charcoal"; ch.pressed.connect(_kiln_load.bind(idx, "wood", "charcoal"))
	_right_vbox.add_child(ch)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Outputs land in your pack."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_aquarium_panel(idx: int) -> void:
	var aq: Dictionary = _aquariums.get(idx, {"males": 0, "females": 0, "eggs": 0, "quality": 100.0, "water": 0, "feed": 0.0, "breed": 0.0})
	var cell := _index_cell(idx)
	_right_vbox.add_child(_header("FISH AQUARIUM"))
	_right_vbox.add_child(_label("Fish: %dM / %dF   Eggs: %d" % [int(aq["males"]), int(aq["females"]), int(aq["eggs"])]))
	_right_vbox.add_child(_label("Water: %d/%d   Quality: %d%%" % [int(aq["water"]), AQUARIUM_WATER_MAX, int(aq["quality"])]))
	var filt: String = "running" if (_is_powered(cell) and _is_piped_water(cell) and int(aq["water"]) > 0) else "OFF (needs power+pipe+water)"
	_right_vbox.add_child(_label("Filter: %s" % filt))
	if int(aq["males"]) + int(aq["females"]) > AQUARIUM_FISH_SAFE:
		_right_vbox.add_child(_label("OVERSTOCKED -- water fouling fast!"))
	_right_vbox.add_child(_label("Fed: %s" % ("yes" if float(aq["feed"]) > 0.0 else "NO -- fish may eat eggs")))
	_right_vbox.add_child(_sep())
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 6)
	var am := Button.new(); am.text = "Add M"; am.pressed.connect(_aquarium_add_fish.bind(idx, "m"))
	var af := Button.new(); af.text = "Add F"; af.pressed.connect(_aquarium_add_fish.bind(idx, "f"))
	var tk := Button.new(); tk.text = "Take"; tk.pressed.connect(_aquarium_take_fish.bind(idx))
	r1.add_child(am); r1.add_child(af); r1.add_child(tk); _right_vbox.add_child(r1)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 6)
	var wt := Button.new(); wt.text = "Pour Water"; wt.pressed.connect(_aquarium_water.bind(idx))
	var fd := Button.new(); fd.text = "Feed Worm"; fd.pressed.connect(_aquarium_feed.bind(idx))
	r2.add_child(wt); r2.add_child(fd); _right_vbox.add_child(r2)
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_peel_panel(idx: int) -> void:
	var tr: Dictionary = _traps.get(idx, {"ammo": 0, "hp": 0})
	_right_vbox.add_child(_header("PEEL LAUNCHER"))
	_right_vbox.add_child(_label("Peels loaded: %d   Durability: %d/%d" % [int(tr.get("ammo", 0)), int(tr.get("hp", 0)), int(TRAP_MAX_HP["peel_launcher"])]))
	_right_vbox.add_child(_sep())
	var ld := Button.new(); ld.text = "Load Banana Peel"; ld.pressed.connect(_peel_launcher_load.bind(idx))
	_right_vbox.add_child(ld)
	var rp := Button.new(); rp.text = "Repair (%s)" % _cost_text(TRAP_REPAIR_COST); rp.pressed.connect(_trap_repair.bind(idx))
	_right_vbox.add_child(rp)
	_right_vbox.add_child(_label("Fires peels: minor hit + drops a"))
	_right_vbox.add_child(_label("peel that stuns the next croc."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_sprinkler_panel(idx: int) -> void:
	_right_vbox.add_child(_header("SPRINKLER"))
	var ok := _is_piped_water(_index_cell(idx))
	_right_vbox.add_child(_label("Water supply: %s" % ("connected" if ok else "no pipe to the pool")))
	_right_vbox.add_child(_label("Auto-waters planted boxes within"))
	_right_vbox.add_child(_label("%d tiles when piped to water." % SPRINKLER_RADIUS))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_generator_panel(idx: int) -> void:
	var g: Dictionary = _generators.get(idx, {"oil": 0, "on": false, "drain": 0.0})
	_right_vbox.add_child(_header("GENERATOR"))
	_right_vbox.add_child(_label("Oil: %d / %d   %s" % [int(g["oil"]), GEN_OIL_MAX, ("RUNNING" if (g["on"] and int(g["oil"]) > 0) else "off")]))
	_right_vbox.add_child(_sep())
	var pf := Button.new(); pf.text = "Pour Berry Oil"; pf.pressed.connect(_generator_fuel.bind(idx))
	_right_vbox.add_child(pf)
	var tg := Button.new(); tg.text = "Turn Off" if g["on"] else "Turn On"
	tg.pressed.connect(_generator_toggle.bind(idx)); _right_vbox.add_child(tg)
	_right_vbox.add_child(_label("Run wires out to power turrets,"))
	_right_vbox.add_child(_label("bulbs and machines automatically."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_auto_miner_panel(idx: int) -> void:
	var m: Dictionary = _miners.get(idx, {"t": 0.0})
	_right_vbox.add_child(_header("AUTO-MINER"))
	_right_vbox.add_child(_label("Cycle: %d / %d sec" % [int(float(m.get("t", 0.0))), int(FP_AUTO_MINER_TICK)]))
	_right_vbox.add_child(_label("Output: stone, chance metal ore"))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_auto_loader_panel(_idx: int) -> void:
	_right_vbox.add_child(_header("AUTO-LOADER"))
	_right_vbox.add_child(_label("Gunpowder carried: %d" % _inv("gunpowder")))
	_right_vbox.add_child(_label("Loads adjacent turrets."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_still_panel(idx: int) -> void:
	var st: Dictionary = _stills.get(idx, {"pending": 0, "conv": 0.0})
	_right_vbox.add_child(_header("STILL"))
	_right_vbox.add_child(_label("Distilling: %d cup(s)" % int(st["pending"])))
	_right_vbox.add_child(_sep())
	var ad := Button.new(); ad.text = "Distill Juice -> Berry Oil"
	ad.pressed.connect(_still_add.bind(idx)); _right_vbox.add_child(ad)
	_right_vbox.add_child(_label("Berry oil is dense fuel -- no food"))
	_right_vbox.add_child(_label("or drink value. Powers generators."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_apiary_panel(idx: int) -> void:
	var ap: Dictionary = _apiaries.get(idx, {"bees": 0, "prod": 0.0, "starve": 0.0})
	_right_vbox.add_child(_header("BEE ENCLOSURE"))
	_right_vbox.add_child(_label("Bees: %d / %d" % [int(ap["bees"]), BEE_CAP]))
	if int(ap["bees"]) > 0 and not _plant_near(_index_cell(idx), BEE_PLANT_RADIUS):
		_right_vbox.add_child(_label("No plants nearby -- bees starving!"))
	_right_vbox.add_child(_sep())
	var ab := Button.new(); ab.text = "Add Bee (from jar)"
	ab.pressed.connect(_apiary_add_bee.bind(idx)); _right_vbox.add_child(ab)
	_right_vbox.add_child(_label("Bees make honey + beeswax and"))
	_right_vbox.add_child(_label("speed nearby plants. Keep greenery"))
	_right_vbox.add_child(_label("within %d tiles." % BEE_PLANT_RADIUS))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_wormfarm_panel(idx: int) -> void:
	var wf: Dictionary = _wormfarms.get(idx, {"worms": 0, "rot": 0, "mult": 0.0, "compost": 0.0})
	_right_vbox.add_child(_header("WORM HABITAT"))
	_right_vbox.add_child(_label("Worms: %d / %d   Rot: %d" % [int(wf["worms"]), WORM_CAP, int(wf["rot"])]))
	_right_vbox.add_child(_sep())
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 6)
	var aw := Button.new(); aw.text = "Add Worm"; aw.pressed.connect(_wormfarm_add_worm.bind(idx))
	var tw := Button.new(); tw.text = "Take Worm"; tw.pressed.connect(_wormfarm_take_worm.bind(idx))
	r1.add_child(aw); r1.add_child(tw); _right_vbox.add_child(r1)
	var ar := Button.new(); ar.text = "Add Rot (-> fertilizer)"
	ar.pressed.connect(_wormfarm_add_rot.bind(idx)); _right_vbox.add_child(ar)
	_right_vbox.add_child(_label("2+ worms breed up to %d." % WORM_CAP))
	_right_vbox.add_child(_label("Worms compost rot into fertilizer."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_campfire_panel(idx: int) -> void:
	var cf: Dictionary = _campfires.get(idx, {"item": "", "cook": 0.0})
	_right_vbox.add_child(_header("CAMPFIRE"))
	var state := "empty"
	if cf["item"] == "ash":
		state = "BURNT (ash)"
	elif cf["item"] == "fish_skewer":
		state = "cooked!" if float(cf["cook"]) >= COOK_TIME else "cooking... (%ds)" % int(COOK_TIME - float(cf["cook"]))
	_right_vbox.add_child(_label("On the fire: %s" % state))
	_right_vbox.add_child(_sep())
	var pb := Button.new(); pb.text = "Put Skewer On"; pb.pressed.connect(_campfire_put.bind(idx))
	_right_vbox.add_child(pb)
	var tb := Button.new(); tb.text = "Take Off"; tb.pressed.connect(_campfire_take.bind(idx))
	_right_vbox.add_child(tb)
	_right_vbox.add_child(_label("Leave it too long and it chars to ash."))
	_right_vbox.add_child(_label("[walk away to close]"))


func _build_planter_panel(idx: int) -> void:
	var p: Dictionary = _planters.get(idx, {"planted": false, "berries": 0, "grow": 0.0, "wet": 0.0})
	_right_vbox.add_child(_header("PLANTER BOX"))
	if not p["planted"]:
		_right_vbox.add_child(_label("Empty. Plant a seed to grow"))
		_right_vbox.add_child(_label("a permanent berry bush."))
		_right_vbox.add_child(_sep())
		var pl := Button.new(); pl.text = "Plant Seed"
		pl.pressed.connect(_planter_plant.bind(idx)); _right_vbox.add_child(pl)
	else:
		_right_vbox.add_child(_label("Berries: %d / %d" % [int(p["berries"]), BUSH_MAX_BERRIES]))
		_right_vbox.add_child(_label("Soil: %s" % ("moist" if float(p["wet"]) > 0.0 else "DRY -- water it!")))
		_right_vbox.add_child(_sep())
		if int(p.get("fert", 0)) > 0:
			_right_vbox.add_child(_label("Fertilized: %d harvests" % int(p["fert"])))
		_right_vbox.add_child(_sep())
		var wt := Button.new(); wt.text = "Water"; wt.pressed.connect(_planter_water.bind(idx))
		_right_vbox.add_child(wt)
		var hv := Button.new(); hv.text = "Harvest"; hv.pressed.connect(_planter_harvest.bind(idx))
		_right_vbox.add_child(hv)
		var fz := Button.new(); fz.text = "Fertilize"; fz.pressed.connect(_planter_fertilize.bind(idx))
		_right_vbox.add_child(fz)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Needs regular watering to grow."))


func _build_turret_panel(idx: int) -> void:
	if not _turrets.has(idx):
		_close_turret(); return
	var t: Dictionary = _turrets[idx]
	_right_vbox.add_child(_header("TURRET"))
	if t["type"] == "":
		# Two-step picker: category, then the specific type.
		if _turret_pick_cat == "":
			_right_vbox.add_child(_label("Choose a category:"))
			_right_vbox.add_child(_sep())
			for cat in TURRET_CATEGORIES:
				var b := Button.new()
				b.text = "%s" % TURRET_CAT_LABEL[cat]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.pressed.connect(_pick_turret_cat.bind(cat))
				_right_vbox.add_child(b)
				_right_vbox.add_child(_small(TURRET_CAT_BLURB[cat]))
		else:
			_right_vbox.add_child(_label("%s turret -- pick a type:" % TURRET_CAT_LABEL[_turret_pick_cat]))
			_right_vbox.add_child(_sep())
			for ty in TURRET_TYPES[_turret_pick_cat]:
				var b := Button.new()
				var ty_locked: bool = not _turret_tier_ok(ty)
				b.text = TURRET_DEFS[ty]["label"] + ("  (grow Tree->T%d)" % _turret_required_tier(ty) if ty_locked else "")
				b.tooltip_text = _stat_line(ty)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.disabled = ty_locked
				b.pressed.connect(_configure_turret.bind(idx, ty))
				_wire_hover(b, ty, "turret")
				_right_vbox.add_child(b)
				_right_vbox.add_child(_small(_stat_line(ty)))
			var back := Button.new(); back.text = "< back"
			back.pressed.connect(_pick_turret_cat.bind(""))
			_right_vbox.add_child(back)
		return
	# Configured turret status + management.
	var def: Dictionary = TURRET_DEFS[t["type"]]
	_right_vbox.add_child(_label("%s   Lv %d%s" % [def["label"], int(t["level"]), ("  (BROKEN)" if t["broken"] else "")]))
	_right_vbox.add_child(_small(_stat_line(t["type"])))
	_right_vbox.add_child(_label("HP %d / %d" % [int(t["hp"]), int(t["max_hp"])]))
	_right_vbox.add_child(_label("Ammo %d / %d   Fuel %d%%" % [int(t.get("ammo", 0)), int(t.get("max_ammo", FP_TURRET_AMMO_MAX)), int(100.0 * float(t["fuel"]) / float(t["max_fuel"]))]))
	_right_vbox.add_child(_label("XP %d / %d" % [int(t["xp"]), int(t["xp_to_next"])]))
	_right_vbox.add_child(_sep())
	if int(t["points"]) > 0:
		_right_vbox.add_child(_label("Upgrade points: %d" % int(t["points"])))
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4)
		for stat in TURRET_STAT_ORDER:
			var b := Button.new()
			b.text = "+%s" % TURRET_STAT_LABEL[stat]
			b.add_theme_font_size_override("font_size", 12)
			b.disabled = int(t["alloc"][stat]) >= STAT_UPGRADE_CAP
			b.pressed.connect(_turret_alloc.bind(idx, stat))
			row.add_child(b)
		_right_vbox.add_child(row)
		_right_vbox.add_child(_sep())
	var rf := Button.new(); rf.text = "Refuel (pour wine)"
	rf.pressed.connect(_turret_refuel.bind(idx)); _right_vbox.add_child(rf)
	var rl := Button.new(); rl.text = "Reload (gunpowder)"
	rl.pressed.connect(_turret_reload.bind(idx)); _right_vbox.add_child(rl)
	if t["broken"] or float(t["hp"]) < float(t["max_hp"]):
		var rp := Button.new(); rp.text = "Repair (%s)" % _cost_text(TURRET_REPAIR_COST)
		rp.pressed.connect(_turret_repair.bind(idx)); _right_vbox.add_child(rp)
	_right_vbox.add_child(_label("[walk away to close]"))


func _small(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _pick_turret_cat(cat: String) -> void:
	_turret_pick_cat = cat
	_mark_workspace_dirty()


func _stat_line(ty: String) -> String:
	if not TURRET_DEFS.has(ty):
		return ""
	var d: Dictionary = TURRET_DEFS[ty]
	return "Dmg %.1f  R %.1f  CD %.1f  %s" % [float(d["dmg"]), float(d["range"]), float(d["cd"]), TURRET_CAT_LABEL.get(d["cat"], d["cat"])]


# Generalized computed stat line for the tooltip: dispatches on the def family so
# every hovered thing surfaces its real numbers, always derived from the consts so
# they can't drift. Returns "" when there's nothing computed (the tooltip then
# skips the stat row -- that's the contract).
func _tooltip_stat_line(kind: String, source: String) -> String:
	match source:
		"turret":
			if not TURRET_DEFS.has(kind):
				return ""
			var d: Dictionary = TURRET_DEFS[kind]
			var base := "Dmg %.1f  R %.1f  CD %.1fs  %s" % [float(d["dmg"]), float(d["range"]), float(d["cd"]), TURRET_CAT_LABEL.get(d["cat"], d["cat"])]
			# Counter hint: pull the strongest/weakest croc-class for this category
			# straight from the matrix so the whole point of the matrix is legible.
			var hint := _turret_counter_hint(String(d["cat"]))
			return base + ("\n" + hint if hint != "" else "")
		"weapon":
			if not WEAPON_DEFS.has(kind):
				return ""
			var w: Dictionary = WEAPON_DEFS[kind]
			return "Dmg x%.1f  Reach %.2f  Speed %.1fx%s" % [
				float(w["dmg"]), float(w["reach"]), 1.0 / maxf(0.01, float(w["time"])),
				"  ranged" if bool(w.get("ranged", false)) else ""]
		"struct":
			# Walls show HP/armor from the wall-tier table; production structures lean
			# on their desc (no stat row) unless a tick const gives a throughput hint.
			var wall_id := _wall_tier_key_for_struct(kind)
			if wall_id != "":
				var wt: Dictionary = FP_WALL_TIERS[wall_id]
				return "HP %d  Armor %d" % [int(wt["break_hp"]), int(wt["armor"])]
			match kind:
				"kiln": return "~%.1fs / job" % KILN_TICK
				"juicer": return "~%.1fs / berry" % JUICE_TICK
				"still": return "~%.1fs / oil" % STILL_TICK
				"campfire": return "~%.1fs to cook" % COOK_TIME
				"auto_miner": return "~%ds / cycle" % int(FP_AUTO_MINER_TICK)
			return ""
		"croc":
			if not CROC_DEFS.has(kind):
				return ""
			var c: Dictionary = CROC_DEFS[kind]
			var aggro := String(c.get("aggro", ""))
			var tag := "Swarm"
			if aggro == "tree": tag = "Tree-seeker"
			elif aggro == "player": tag = "Hunts you"
			elif aggro == "support": tag = "Support"
			return "HP x%.1f  Atk x%.1f  Spd x%.1f  %s" % [float(c["hp"]), float(c["atk"]), float(c["spd"]), tag]
		"item":
			if EAT_ENERGY.has(kind):
				return "+%d hunger" % int(EAT_ENERGY[kind])
			if DRINKS.has(kind):
				var dr: Array = DRINKS[kind]
				var s := "+%d thirst" % int(dr[0])
				if float(dr[1]) > 0.0:
					s += "  +%d heal" % int(dr[1])
				return s
			if TOOL_DEFS.has(kind):
				var td: Dictionary = TOOL_DEFS[kind]
				return "+%d gather  uses %d%% energy" % [int(td["bonus"]), int(round(float(td["energy"]) * 100.0))]
			match kind:
				"coconut": return "+%d hunger  +%d thirst" % [int(COCONUT_ENERGY), int(COCONUT_HYDRATION)]
				"fish_m", "fish_f": return "+%d hunger" % int(FISH_ENERGY)
				"cooked_skewer": return "+%d hunger" % int(FISH_ENERGY * 3.0)
				"gunpowder": return "1 turret shot each"
			return ""
	return ""


# "strong vs <class>s  weak vs <class>s" for a turret category, read off the
# counter matrix (max-multiplier class is the strength, min is the weakness).
func _turret_counter_hint(cat: String) -> String:
	var row: Dictionary = FP_COUNTER_MATRIX.get(cat, {})
	if row.is_empty():
		return ""
	var best := ""
	var worst := ""
	var bestv := -1.0e9
	var worstv := 1.0e9
	for cls in row:
		var v := float(row[cls])
		if v > bestv:
			bestv = v; best = String(cls)
		if v < worstv:
			worstv = v; worst = String(cls)
	# A flat matrix row (support: all equal) has no real edge -- report a role note.
	if absf(bestv - worstv) < 0.001:
		return "utility -- low raw damage"
	return "strong vs %ss  weak vs %ss" % [best, worst]


# The FP_WALL_TIERS key for a structure id (handles the door + 4 wall tiers), or
# "" if the structure isn't a wall. Keeps the stat line keyed off the tier table.
func _wall_tier_key_for_struct(struct_id: String) -> String:
	if FP_WALL_TIERS.has(struct_id):
		return struct_id
	return ""


func _build_craft_panel() -> void:
	_right_vbox.add_child(_header("CRAFT"))
	_right_vbox.add_child(_label("Make items from materials."))
	_right_vbox.add_child(_sep())
	for key in CRAFT_ORDER:
		var r: Dictionary = CRAFT_RECIPES[key]
		var b := Button.new()
		b.text = "%s  (%s)" % [r["label"], _cost_text(r["cost"])]
		var tier_locked: bool = not _craft_tier_ok(key)
		if tier_locked:
			b.text += "  *grow Tree->T%d*" % _craft_required_tier(key)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = PANEL_W - 32.0
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = tier_locked or not _can_afford(r["cost"])
		b.pressed.connect(_craft.bind(key))
		_wire_hover(b, key, "recipe")
		_right_vbox.add_child(b)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Barrels, juicers + planters are"))
	_right_vbox.add_child(_label("placed from build mode (B)."))
	_right_vbox.add_child(_label("[C] close"))


# Hybrid inventory (decision #17): a fixed equipped-hotbar row (tool / weapon /
# ammo) pinned at the top, then the bulk list grouped into labeled category bands.
func _build_inventory_panel() -> void:
	_right_vbox.add_child(_header("INVENTORY"))
	_right_vbox.add_child(_build_hotbar_row())
	_right_vbox.add_child(_sep())
	# Bulk list, one band at a time -- a band header only prints if it has items.
	var bands := {}
	for kind in INV_ORDER:
		if _inv(kind) <= 0:
			continue
		var band: String = INV_CATEGORY.get(kind, "materials")
		if not bands.has(band):
			bands[band] = []
		(bands[band] as Array).append(kind)
	var any := false
	for band in INV_BAND_ORDER:
		if not bands.has(band):
			continue
		any = true
		var hdr := _label(INV_BAND_LABEL.get(band, band.to_upper()))
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", UI_SUBTLE)
		_right_vbox.add_child(hdr)
		for kind in bands[band]:
			_right_vbox.add_child(_inventory_item_row(kind, _inv_row_label(kind)))
			_right_vbox.add_child(_inv_action_row(kind))
		if band == "waste":
			var rotten := _inv("rotten_banana") + _inv("rotten_berry")
			if rotten > 0:
				var clr := Button.new()
				clr.text = "Toss all rotten (%d)" % rotten
				clr.add_theme_font_size_override("font_size", 12)
				clr.pressed.connect(_delete_rotten)
				_right_vbox.add_child(clr)
	if not any:
		_right_vbox.add_child(_label("(empty)"))
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("[I] close"))


# Line-1 label for a bulk-list item: name + count, plus a compact [E] tag when it's
# the equipped tool/weapon (replaces the old "[equipped]" text suffix).
func _inv_row_label(kind: String) -> String:
	var eqmark := ""
	if kind == _tool_equipped or (kind == _weapon_equipped and kind != ""):
		eqmark = "  [E]"
	return "%s  x%d%s" % [ITEM_LABELS.get(kind, kind), _inv(kind), eqmark]


# Line-2 action row for a bulk-list item: only the buttons that item supports.
func _inv_action_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if kind in TOOL_ITEMS or kind in WEAPON_ITEMS:
		var eq := Button.new()
		eq.text = "Unequip" if (kind == _tool_equipped or kind == _weapon_equipped) else "Equip"
		eq.add_theme_font_size_override("font_size", 12)
		eq.pressed.connect(_equip.bind(kind))
		row.add_child(eq)
	if DRINKS.has(kind):
		var dr := Button.new()
		dr.text = "Drink"
		dr.add_theme_font_size_override("font_size", 12)
		dr.pressed.connect(_drink.bind(kind))
		var em := Button.new()
		em.text = "Empty"
		em.add_theme_font_size_override("font_size", 12)
		em.pressed.connect(_empty_cup.bind(kind))
		row.add_child(dr)
		row.add_child(em)
	var d1 := Button.new()
	d1.text = "Drop 1"
	d1.add_theme_font_size_override("font_size", 12)
	d1.pressed.connect(_delete_item.bind(kind, false))
	var dall := Button.new()
	dall.text = "Drop all"
	dall.add_theme_font_size_override("font_size", 12)
	dall.pressed.connect(_delete_item.bind(kind, true))
	row.add_child(d1)
	row.add_child(dall)
	return row


func _inventory_item_row(kind: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP   # so the row reports hover for the tooltip
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _item_icons.has(kind):
		icon.texture = _item_icons[kind]
	row.add_child(icon)
	var lbl := _label(text)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	_wire_hover(row, kind, "item")
	return row


# The equipped hotbar: three fixed 44x44 slots (tool / weapon / ammo). Tool & weapon
# slots click to equip/unequip; the ammo slot is context-sensitive (slingshot tracks
# sling_ammo, otherwise the carried gunpowder reload stock) and display-only.
func _build_hotbar_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_equip_slot(_tool_equipped, "tool"))
	row.add_child(_equip_slot(_weapon_equipped, "weapon"))
	var ammo_kind := "sling_ammo" if _weapon_equipped == "slingshot" else "gunpowder"
	row.add_child(_equip_slot(ammo_kind, "ammo"))
	return row


# One 44x44 hotbar slot. role in {tool, weapon, ammo} sets the border color and the
# click/caption behaviour. The ammo slot carries a live count badge.
func _equip_slot(kind: String, role: String) -> Control:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 2)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(44, 44)
	var filled := kind != "" or (role == "ammo")
	var border := UI_BORDER
	match role:
		"tool": border = UI_TOOL if kind != "" else UI_BORDER
		"weapon": border = UI_WEAPON   # always filled (fists when "")
		"ammo": border = UI_AMMO
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.118, 0.149)   # #1B1E26
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)

	# Icon: tool/weapon use the equipped item's icon (or a faint placeholder when
	# empty); ammo uses its kind's icon, dimmed when the stock is 0.
	var icon_kind := kind
	if role == "weapon" and kind == "":
		icon_kind = "mallet"   # stand-in glyph for the fists slot (dimmed below)
	var tex: Texture2D = _item_icons.get(icon_kind, null)
	var ico := TextureRect.new()
	ico.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.texture = tex
	var empty := (role != "ammo" and kind == "")
	ico.modulate = Color(1, 1, 1, 0.30 if empty else 1.0)
	btn.add_child(ico)

	# Ammo count badge, bottom-right; red when the relevant stock is 0.
	if role == "ammo":
		var n := _inv(kind)
		var badge := Label.new()
		badge.text = "x%d" % n
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", UI_NAME if n > 0 else UI_SHORT)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		badge.add_theme_constant_override("outline_size", 3)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.offset_right = -3
		badge.offset_bottom = -2
		btn.add_child(badge)

	# Tool/weapon slots equip/unequip on click; ammo is display-only.
	if role == "tool" or role == "weapon":
		if kind != "":
			btn.pressed.connect(_equip.bind(kind))
		else:
			btn.disabled = true
	else:
		btn.disabled = true
	# Hover -> tooltip for whatever's in the slot (weapon family for the weapon slot).
	if role == "weapon":
		_wire_hover(btn, kind, "weapon")
	elif kind != "":
		_wire_hover(btn, kind, "item")
	slot.add_child(btn)

	# Caption under the slot.
	var cap := Label.new()
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", UI_SUBTLE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match role:
		"tool": cap.text = TOOL_DEFS[kind]["label"] if TOOL_DEFS.has(kind) else "no tool"
		"weapon": cap.text = String(_weapon()["label"])
		"ammo": cap.text = ITEM_LABELS.get(kind, kind)
	slot.add_child(cap)
	return slot


func _delete_rotten() -> void:
	_resources["rotten_banana"] = 0
	_resources["rotten_berry"] = 0
	_mark_workspace_dirty()


func _build_levelup_panel() -> void:
	_right_vbox.add_child(_header("LEVEL UP!"))
	_right_vbox.add_child(_label("Reached level %d." % _level))
	if _stat_points > 1:
		_right_vbox.add_child(_label("Points to spend: %d" % _stat_points))
	_right_vbox.add_child(_label("Raise one stat:"))
	_right_vbox.add_child(_sep())
	for stat in STAT_ORDER:
		var info: Dictionary = STAT_INFO[stat]
		var b := Button.new()
		b.text = "[%d] %s  -  %s" % [info["num"], info["label"], _stat_choice_text(stat)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_choose_stat.bind(stat))
		_right_vbox.add_child(b)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Press 1-5 or click. (Paused)"))


func _build_help_panel() -> void:
	_right_vbox.add_child(_header("CONTROLS"))
	var lines: Array[String]
	if _is_night:
		lines = [
			"WASD  -  move",
			"Left-click  -  PUNCH (aim at",
			"            cursor); click storage",
			"E eat   Q drink   I inventory",
			"Save / Settings: left panel",
		]
	else:
		lines = [
			"WASD  -  move",
			"Left-click adjacent  -  gather",
			"   tree/stone/bush/grass/water,",
			"   or open storage/barrel/etc.",
			"E eat   Q drink",
			"B build   C craft   I inventory",
			"Save / Settings: left panel",
		]
	for line in lines:
		_right_vbox.add_child(_label(line))
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_header("DAY / NIGHT"))
	if _is_night:
		_right_vbox.add_child(_label("Survive! No building at night."))
		_right_vbox.add_child(_label("Punch crocs (the fist hits)."))
		_right_vbox.add_child(_label("Storage still works."))
	else:
		_right_vbox.add_child(_label("Gather and build by day."))
		_right_vbox.add_child(_label("At night the land clears and"))
		_right_vbox.add_child(_label("crocodiles hunt you -- wall"))
		_right_vbox.add_child(_label("yourself in behind a door."))
		_right_vbox.add_child(_label("Build turrets + spike traps to"))
		_right_vbox.add_child(_label("let the base fight for you."))
		_right_vbox.add_child(_label("New croc colors arrive each"))
		_right_vbox.add_child(_label("night -- they fight differently."))


func _build_build_panel() -> void:
	_right_vbox.add_child(_header("BUILD"))
	_right_vbox.add_child(_label("Pick a structure, then left-click"))
	_right_vbox.add_child(_label("grass to place (drag for lines)."))
	_right_vbox.add_child(_label("Click structures to remove."))
	_right_vbox.add_child(_label("Blocks: %d / %d" % [_block_count, BLOCK_LIMIT]))
	_right_vbox.add_child(_sep())

	var near := _near_workbench()
	for key in STRUCTURE_ORDER:
		var s: Dictionary = STRUCTURES[key]
		var locked: bool = s["bench"] and not near
		var tier_locked: bool = not _struct_tier_ok(key)
		var txt := "[%d] %s  (%s)" % [s["num"], s["label"], _cost_text(s["cost"])]
		if tier_locked:
			txt += "  *grow Tree->T%d*" % _struct_required_tier(key)
		elif locked:
			txt += "  *needs workbench*"
		var b := Button.new()
		b.text = ("> " if key == _build_struct else "   ") + txt
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = PANEL_W - 32.0
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = tier_locked
		b.pressed.connect(_select_struct.bind(key))
		_wire_hover(b, key, "struct")
		_right_vbox.add_child(b)

	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("B to exit build mode"))


func _build_storage_panel(idx: int) -> void:
	var box: Dictionary = _storage.get(idx, _new_storage_box())
	_right_vbox.add_child(_header("STORAGE"))
	_right_vbox.add_child(_label("Move or drop items:"))
	_right_vbox.add_child(_sep())

	for res in INV_ORDER:
		if _inv(res) <= 0 and int(box.get(res, 0)) <= 0:
			continue   # hide empty item types
		_right_vbox.add_child(_label("%s    you %d  /  box %d" % [
			ITEM_LABELS.get(res, res), _inv(res), int(box.get(res, 0))
		]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dep := Button.new()
		dep.text = "Dep"
		dep.pressed.connect(_transfer.bind(idx, res, 1, true))
		var take := Button.new()
		take.text = "Take"
		take.pressed.connect(_transfer.bind(idx, res, 1, false))
		var drop := Button.new()
		drop.text = "Drop"
		drop.pressed.connect(_delete_box_item.bind(idx, res, false))
		row.add_child(dep)
		row.add_child(take)
		row.add_child(drop)
		_right_vbox.add_child(row)

	_right_vbox.add_child(_sep())
	var all_row := HBoxContainer.new()
	all_row.add_theme_constant_override("separation", 6)
	var dep_all := Button.new()
	dep_all.text = "Deposit all"
	dep_all.pressed.connect(_deposit_all.bind(idx))
	var take_all := Button.new()
	take_all.text = "Take all"
	take_all.pressed.connect(_take_all.bind(idx))
	all_row.add_child(dep_all)
	all_row.add_child(take_all)
	_right_vbox.add_child(all_row)

	var close := Button.new()
	close.text = "Close (or walk away)"
	close.pressed.connect(_close_storage)
	_right_vbox.add_child(close)


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [cost[k], k])
	return ", ".join(parts)


# -----------------------------------------------------------------------------
# Drawing (board only -- gameplay visual cues, no text)
# -----------------------------------------------------------------------------
func _visible_cell_rect(pad: int = 2) -> Rect2i:
	var vp := get_viewport_rect().size
	var center := _camera.position if _camera else _player_pos
	var zoom := CAMERA_ZOOM
	if _camera:
		zoom = maxf(0.01, _camera.zoom.x)
	var half_world := vp * 0.5 / zoom + Vector2(CELL_SIZE * float(pad), CELL_SIZE * float(pad))
	var min_c := Vector2i(
		clampi(int(floor((center.x - half_world.x) / CELL_SIZE)), 0, GRID_CELLS - 1),
		clampi(int(floor((center.y - half_world.y) / CELL_SIZE)), 0, GRID_CELLS - 1)
	)
	var max_c := Vector2i(
		clampi(int(floor((center.x + half_world.x) / CELL_SIZE)), 0, GRID_CELLS - 1),
		clampi(int(floor((center.y + half_world.y) / CELL_SIZE)), 0, GRID_CELLS - 1)
	)
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)


# Den maturity escalation (§4): overlay the warm/evolved tile art over each
# Den cell (the base CROC_DEN tile already paints the YOUNG look), then add the
# ember pulse keyed off the stage. The maturing pulse is the "evolves tomorrow"
# warning; the mature glow is steady + bone props. Drawn over terrain, under the
# HP bars. Stays legible at night because it's a warm glow punching through the
# blue wash.
func _draw_den_overlays(cell_vec: Vector2) -> void:
	if _dens.is_empty():
		return
	var vis := _visible_cell_rect()
	var t := float(Time.get_ticks_msec()) / 1000.0
	for id in _dens:
		var d: Dictionary = _dens[id]
		var origin: Vector2i = d["origin"]
		var size := int(d["size"])
		var stage := _den_stage(d)
		if stage == "young":
			continue   # base tile already carries the quiet young look
		var ov: ImageTexture = _tex_den_evolved if stage == "mature" else _tex_den_warm
		for c in _den_cells(origin, size):
			if not vis.has_point(c):
				continue
			draw_texture_rect(ov, Rect2(Vector2(c) * CELL_SIZE, cell_vec), false)
		# Ember pulse over the Den centre.
		var center := (Vector2(origin) + Vector2(float(size) * 0.5, float(size) * 0.5)) * CELL_SIZE
		var rad := CELL_SIZE * (float(size) * 0.5 + 0.2)
		if stage == "maturing":
			# Slow 0.5Hz pulse, alpha 0.15-0.35 -- the evolve-tomorrow warning.
			var a := 0.15 + 0.20 * (0.5 + 0.5 * sin(t * TAU * 0.5))
			draw_circle(center, rad, Color(DEN_EMBER.r, DEN_EMBER.g, DEN_EMBER.b, a))
		else:
			# Mature: steady rim glow + a heavier slow pulse, plus bone/spike props.
			draw_circle(center, rad, Color(DEN_EMBER.r, DEN_EMBER.g, DEN_EMBER.b, 0.30))
			var a2 := 0.10 + 0.12 * (0.5 + 0.5 * sin(t * TAU * 0.6))
			draw_circle(center, rad * 1.25, Color(DEN_EMBER.r, DEN_EMBER.g, DEN_EMBER.b, a2))
			var bone := Color(0.86, 0.84, 0.74, 0.9)
			for k in range(4):
				var ang := TAU * float(k) / 4.0 + 0.6
				var bp := center + Vector2(cos(ang), sin(ang)) * rad * 0.85
				draw_line(bp + Vector2(-2, 0), bp + Vector2(2, 0), bone, 1.5)
				draw_line(bp + Vector2(0, -2), bp + Vector2(0, 2), bone, 1.5)


# Mother Tree Sap aura ring (§5), inverted valence vs. the Den: gold + growing,
# radius from the tier table (4..12 cells). A soft gold fill + brighter stroke,
# baked bright so it reads under the night wash. Drawn under the HP bars.
func _draw_tree_aura() -> void:
	var center := _cell_center_world(_tree_center_cell())
	var r := float(_tree_aura_radius()) * CELL_SIZE
	if r <= 0.0:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * TAU * 0.25)
	draw_circle(center, r, Color(SAP_GLOW.r, SAP_GLOW.g, SAP_GLOW.b, 0.07 + 0.03 * pulse))
	draw_arc(center, r, 0.0, TAU, 64, Color(SAP_GLOW.r, SAP_GLOW.g, SAP_GLOW.b, 0.45 + 0.15 * pulse), 2.0)


func _draw_tree_hp_bar() -> void:
	var max_hp := _tree_max_hp()
	if max_hp <= 0.0:
		return
	var center := _cell_center_world(_tree_center_cell()) + Vector2(0, -CELL_SIZE * 1.65)
	var size := Vector2(CELL_SIZE * 2.5, 6)
	var rect := Rect2(center - size * 0.5, size)
	draw_rect(rect.grow(1.0), Color(0.03, 0.04, 0.03, 0.85), true)
	draw_rect(rect, Color(0.18, 0.12, 0.08, 0.85), true)
	var frac := clampf(_tree_hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(0.30, 0.78, 0.35, 0.90), true)


func _draw_den_hp_bars() -> void:
	var vis := _visible_cell_rect()
	for id in _dens:
		var d: Dictionary = _dens[id]
		var origin: Vector2i = d["origin"]
		var size := int(d["size"])
		var frac := clampf(float(d["hp"]) / maxf(1.0, float(d["max_hp"])), 0.0, 1.0)
		# Gate: show only when wounded OR on-screen, to keep a fresh swarm uncluttered
		# (mirrors the turret-bar/croc-bar gating).
		var on_screen := vis.has_point(origin) or vis.has_point(origin + Vector2i(size - 1, size - 1))
		if frac >= 0.999 and not on_screen:
			continue
		var center := (Vector2(origin) + Vector2(float(size) * 0.5, -0.25)) * CELL_SIZE
		# Thicker bar = bigger threat: 6px for a mature (3x3) Den, 4px for young.
		var bar_h := 6.0 if size >= 3 else 4.0
		var bar_size := Vector2(CELL_SIZE * float(size), bar_h)
		var rect := Rect2(center - bar_size * 0.5, bar_size)
		draw_rect(rect.grow(1.0), Color(UI_BAR_BG.r, UI_BAR_BG.g, UI_BAR_BG.b, 0.9), true)
		draw_rect(rect, Color(0.16, 0.08, 0.06, 0.85), true)
		# Fill lerps OK -> WARN -> BAD by hp fraction (same grammar as croc/Tree bars).
		var fill := UI_OK.lerp(UI_WARN, clampf((1.0 - frac) * 2.0, 0.0, 1.0)) if frac > 0.5 \
			else UI_WARN.lerp(UI_BAD, clampf((0.5 - frac) * 2.0, 0.0, 1.0))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(fill.r, fill.g, fill.b, 0.92), true)


# AGGRO telegraph (role is now carried by the silhouette -- §3). A UI_BAD-tinted
# downward chevron floats over Tree-seekers (the crocs that ignore you and march
# on the base), so the player can read the split-aggro at a glance and peel them
# off the Mother Tree. Support crocs (healers) keep a soft green tick so the
# "kill it first" target stays callable; everything else (hunts-you / swarm)
# carries no floaty -- its silhouette already tells you what it is.
func _draw_croc_role_tag(m: Dictionary, pos: Vector2) -> void:
	var p := pos + Vector2(0, -CELL_SIZE * 0.68)
	var def: Dictionary = CROC_DEFS.get(String(m.get("type", "")), {})
	var aggro := String(def.get("aggro", m.get("role", "")))
	match aggro:
		"tree":
			# Tree-seeker: a bold red chevron pointing down at the croc.
			var c := Color(UI_BAD.r, UI_BAD.g, UI_BAD.b, 0.95)
			draw_line(p + Vector2(-5, -3), p + Vector2(0, 3), c, 2.0)
			draw_line(p + Vector2(5, -3), p + Vector2(0, 3), c, 2.0)
		"support":
			# Healer: green "+" so the priority target stays callable.
			var hc := Color(0.55, 1.0, 0.65, 0.9)
			draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), hc, 2.0)
			draw_line(p + Vector2(0, -4), p + Vector2(0, 4), hc, 2.0)


# A slim HP bar floating over a wounded croc -- same idiom as the Tree/Den/turret
# bars (black underlay + dark track + colored fill). Only drawn while damaged so
# a fresh swarm stays uncluttered; the fill greens->yellows->reds with the wound.
func _draw_croc_hp_bar(m: Dictionary, pos: Vector2) -> void:
	var maxhp := float(m.get("max_hp", 0.0))
	if maxhp <= 0.0:
		return
	var frac := clampf(float(m["hp"]) / maxhp, 0.0, 1.0)
	if frac >= 0.999:
		return   # untouched -- keep the board clean
	var bw := CELL_SIZE * 0.7
	var bx := pos + Vector2(-bw * 0.5, -CELL_SIZE * 0.5)
	var rect := Rect2(bx, Vector2(bw, 3.0))
	draw_rect(rect.grow(1.0), Color(0.03, 0.03, 0.04, 0.85), true)
	draw_rect(rect, Color(0.18, 0.10, 0.10, 0.85), true)
	# Fill shifts green (healthy) -> amber -> red as the croc loses health.
	var fill := Color(0.78, 0.26, 0.20) if frac < 0.34 else (Color(0.86, 0.74, 0.26) if frac < 0.66 else Color(0.40, 0.80, 0.36))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(fill.r, fill.g, fill.b, 0.92), true)


func _draw() -> void:
	var cell_vec := Vector2(CELL_SIZE, CELL_SIZE)
	var vis := _visible_cell_rect()
	var vis_end := vis.position + vis.size
	for y in range(vis.position.y, vis_end.y):
		for x in range(vis.position.x, vis_end.x):
			var idx := y * GRID_CELLS + x
			var pos := Vector2(x, y) * CELL_SIZE
			draw_texture_rect(_tiles[_terrain[idx]], Rect2(pos, cell_vec), false)
			if _terrain[idx] == Terrain.TREE and _banana[idx] == 1:
				draw_texture_rect(_tex_banana, Rect2(pos, cell_vec), false)
			elif _terrain[idx] == Terrain.COCONUT and _banana[idx] == 1:
				draw_texture_rect(_tex_coconut, Rect2(pos, cell_vec), false)
			elif _terrain[idx] == Terrain.BUSH and _berry[idx] > 0:
				_draw_bush_berries(pos, _berry[idx])
			elif _terrain[idx] == Terrain.PLANTER and _planters.has(idx) and int(_planters[idx]["berries"]) > 0:
				_draw_bush_berries(pos, int(_planters[idx]["berries"]))
			# Damage overlay on harmed structures.
			if _struct_hp.has(idx):
				var frac := 1.0 - float(_struct_hp[idx]) / float(maxi(1, _tile_break_hp(_terrain[idx])))
				draw_rect(Rect2(pos, cell_vec), Color(0.0, 0.0, 0.0, 0.55 * frac), true)
	_draw_den_overlays(cell_vec)
	_draw_tree_aura()
	_draw_tree_hp_bar()
	_draw_den_hp_bars()

	# Light sources cast a soft glow when it's dark (glapple lamps for now).
	var dl := _daylight(_time)
	if dl < 0.55:
		var night_amt := clampf(1.0 - dl / 0.55, 0.0, 1.0)
		for ls in _light_sources():
			var lp: Vector2 = ls["pos"]
			var lr: float = ls["radius"]
			var lc: Color = ls["color"]
			for ri in range(5):
				var rr := lr * (1.0 - float(ri) / 5.0)
				draw_circle(lp, rr, Color(lc.r, lc.g, lc.b, 0.12 * night_amt))

	var gy0 := float(vis.position.y) * CELL_SIZE
	var gy1 := float(vis_end.y) * CELL_SIZE
	var gx0 := float(vis.position.x) * CELL_SIZE
	var gx1 := float(vis_end.x) * CELL_SIZE
	for i in range(vis.position.x, vis_end.x + 1):
		var off := float(i) * CELL_SIZE
		draw_line(Vector2(off, gy0), Vector2(off, gy1), COLOR_GRID, 1.0)
	for i in range(vis.position.y, vis_end.y + 1):
		var off := float(i) * CELL_SIZE
		draw_line(Vector2(gx0, off), Vector2(gx1, off), COLOR_GRID, 1.0)

	# Spawn-preview rings sit ON the ground (under the crocs), like the adhesive /
	# heal fields -- drawn here, early, not in the on-top _draw_fx pass (§9.3).
	_draw_fx_spawn_warn()

	if _build_mode:
		if _in_bounds(_hover_cell) and _mouse_in_board():
			_draw_build_ghost(cell_vec)
	elif _in_bounds(_hover_cell) and _mouse_in_board() and _chebyshev(_cell, _hover_cell) <= 1:
		# Highlight an adjacent interactable under the cursor (clickable).
		var ht := _terrain_at(_hover_cell)
		if ht == Terrain.TREE or ht == Terrain.STONE or ht == Terrain.STORAGE or ht == Terrain.BUSH \
				or ht == Terrain.WATER or ht == Terrain.BARREL or ht == Terrain.JUICER or ht == Terrain.PLANTER \
				or ht == Terrain.COCONUT or ht == Terrain.BAMBOO or ht == Terrain.GLAPPLE_LAMP \
				or ht == Terrain.SAND or ht == Terrain.KILN or ht == Terrain.HIVE \
				or ht == Terrain.BEE_ENCLOSURE or ht == Terrain.WORM_FARM or ht == Terrain.CAMPFIRE \
				or ht == Terrain.STILL or ht == Terrain.GENERATOR or ht == Terrain.AQUARIUM or ht == Terrain.SPRINKLER \
				or ht == Terrain.AUTO_MINER or ht == Terrain.AUTO_LOADER or ht == Terrain.PEEL_LAUNCHER \
				or ht == Terrain.WRECK or ht == Terrain.MOTHER_TREE:
			draw_rect(Rect2(Vector2(_hover_cell) * CELL_SIZE, cell_vec), COLOR_FACE_HL, false, 2.0)

	# White-croc heal auras (drawn under the crocs).
	var hpulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 160.0)
	for m in _monsters:
		if m["role"] == "healer" and m["hp"] > 0.0 and not m["dig"]:
			draw_circle(m["pos"], HEAL_RADIUS, Color(0.4, 1.0, 0.5, 0.07 + 0.05 * hpulse))
			draw_arc(m["pos"], HEAL_RADIUS, 0.0, TAU, 48, Color(0.5, 1.0, 0.6, 0.5), 2.0)

	# Monsters: crocodiles, facing the player (white flash when hit).
	for m in _monsters:
		var mp: Vector2 = m["pos"]
		var tex: Dictionary = _croc_tex.get(m["type"], _croc_tex["green"])
		# Burrowed brown crocs show only a churning dirt mound (can't be hit).
		if m.get("dig", false):
			draw_circle(mp, CELL_SIZE * 0.34, Color(0.34, 0.24, 0.13, 0.9))
			draw_circle(mp, CELL_SIZE * 0.20, Color(0.46, 0.33, 0.18, 0.9))
			continue
		# Dead-but-reviving black croc: greyed, lying in place.
		var reviving: bool = m["hp"] <= 0.0 and m["role"] == "reviver" and not m["revived"]
		var left: bool = (_player_pos.x - mp.x) < 0
		var rect := Rect2(mp - cell_vec * 0.5, cell_vec)
		draw_texture_rect(tex["l"] if left else tex["r"], rect, false,
			Color(0.5, 0.5, 0.55) if reviving else Color.WHITE)
		if m["flash"] > 0.0:
			var fa: float = clampf(m["flash"] / FLASH_TIME, 0.0, 1.0)
			draw_texture_rect(tex["fl"] if left else tex["fr"], rect, false, Color(1, 1, 1, fa))
		_draw_croc_role_tag(m, mp)
		# A floating HP bar over wounded crocs (skip the downed reviver -- no bar on a corpse).
		if not reviving and m["hp"] > 0.0:
			_draw_croc_hp_bar(m, mp)

	# Green "+" over crocs currently being mended by a white croc.
	for m in _monsters:
		if m.get("healing", false) and m["hp"] > 0.0:
			var hc: Vector2 = (m["pos"] as Vector2) + Vector2(0, -CELL_SIZE * 0.5)
			var hcol := Color(0.5, 1.0, 0.6, 0.7 + 0.3 * hpulse)
			draw_line(hc + Vector2(-3, 0), hc + Vector2(3, 0), hcol, 2.0)
			draw_line(hc + Vector2(0, -3), hc + Vector2(0, 3), hcol, 2.0)

	# Trickster marks (a purple diamond above the croc -- takes +20% damage).
	for m in _monsters:
		if m.get("marked", false) and m["hp"] > 0.0:
			var mk: Vector2 = (m["pos"] as Vector2) + Vector2(0, -CELL_SIZE * 0.55)
			var mc := Color(0.75, 0.4, 0.95)
			draw_colored_polygon(PackedVector2Array([
				mk + Vector2(0, -4), mk + Vector2(4, 0), mk + Vector2(0, 4), mk + Vector2(-4, 0)]), mc)

	# Purple poison clouds (lingering, only hurt the player while inside).
	for cl in _poison_clouds:
		var ca: float = (1.0 - float(cl["t"]) / POISON_TIME) * 0.55
		draw_circle(cl["pos"], POISON_RADIUS, Color(0.55, 0.20, 0.65, ca))
		draw_circle(cl["pos"], POISON_RADIUS * 0.6, Color(0.40, 0.10, 0.50, ca))

	# Projectiles: fireballs (red/orange), snowballs (pale blue), turret arrows (dark dart).
	for p in _projectiles:
		var pv: Vector2 = p["pos"]
		if p["kind"] == "fire":
			draw_circle(pv, PROJ_RADIUS * 1.4, Color(1.0, 0.45, 0.10, 0.45))
			draw_circle(pv, PROJ_RADIUS, Color(1.0, 0.72, 0.22))
			draw_circle(pv, PROJ_RADIUS * 0.5, Color(1.0, 0.95, 0.75))
		elif p["kind"] == "arrow" or p["kind"] == "snipe":
			var tail: Vector2 = pv - (p["vel"] as Vector2).normalized() * CELL_SIZE * (0.6 if p["kind"] == "snipe" else 0.35)
			draw_line(tail, pv, Color(0.95, 0.95, 0.75) if p["kind"] == "snipe" else Color(0.85, 0.82, 0.70), 3.0)
			draw_circle(pv, PROJ_RADIUS * 0.6, Color(0.98, 0.95, 0.82))
		elif p["kind"] == "bullet":
			draw_circle(pv, PROJ_RADIUS * 0.55, Color(0.95, 0.9, 0.55))
		elif p["kind"] == "sling":
			draw_circle(pv, PROJ_RADIUS * 0.6, Color(0.62, 0.60, 0.58))   # a flung stone
		elif p["kind"] == "peel":
			draw_circle(pv, PROJ_RADIUS * 0.7, Color(0.95, 0.86, 0.35))   # a tumbling peel
		elif p["kind"] == "rocket":
			var tail2: Vector2 = pv - (p["vel"] as Vector2).normalized() * CELL_SIZE * 0.4
			draw_line(tail2, pv, Color(1.0, 0.6, 0.2, 0.7), 3.0)
			draw_circle(pv, PROJ_RADIUS * 0.8, Color(0.85, 0.30, 0.18))
		else:
			draw_circle(pv, PROJ_RADIUS * 1.4, Color(0.55, 0.82, 1.0, 0.45))
			draw_circle(pv, PROJ_RADIUS, Color(0.82, 0.93, 1.0))

	# Fish swimming in the pool (males blue-finned, females pink-finned).
	for fsh in _fish:
		var fp: Vector2 = fsh["pos"]
		var fc := Color(0.55, 0.78, 1.0) if fsh["sex"] == "m" else Color(1.0, 0.62, 0.78)
		draw_circle(fp, CELL_SIZE * 0.16, Color(0.85, 0.88, 0.92))   # body
		draw_circle(fp + Vector2(CELL_SIZE * 0.14, 0), CELL_SIZE * 0.07, fc)  # tail/marking
		draw_circle(fp + Vector2(-CELL_SIZE * 0.1, -CELL_SIZE * 0.04), CELL_SIZE * 0.03, Color(0.1, 0.1, 0.12))  # eye

	# Dropped banana peels (slippery; stun the next croc to touch them).
	for pl in _peels:
		var plp: Vector2 = pl["pos"]
		var pa: float = 1.0 - clampf(float(pl["t"]) / PEEL_GROUND_LIFE, 0.0, 1.0)
		draw_circle(plp, CELL_SIZE * 0.18, Color(0.92, 0.82, 0.28, 0.5 + 0.4 * pa))
		draw_arc(plp, CELL_SIZE * 0.18, 0.0, TAU, 10, Color(0.6, 0.5, 0.15, pa), 1.5)

	# Loot lying on the ground: a small bobbing marker tinted by item type.
	for g in _ground_items:
		var gp: Vector2 = g["pos"]
		var bob := sin(float(g["t"]) * 4.0) * 2.0
		var gc: Color = LOOT_ITEM_COLOR.get(g["kind"], Color(0.7, 0.7, 0.72))
		draw_circle(gp + Vector2(0, bob) + Vector2(1, 2), CELL_SIZE * 0.16, Color(0, 0, 0, 0.30))
		draw_circle(gp + Vector2(0, bob), CELL_SIZE * 0.16, gc)
		draw_arc(gp + Vector2(0, bob), CELL_SIZE * 0.16, 0.0, TAU, 12, Color(1, 1, 1, 0.6), 1.0)

	# Death poofs (expanding ring + green debris).
	for p in _poofs:
		var pt: float = p["t"]
		var pp: Vector2 = p["pos"]
		var prad := lerpf(CELL_SIZE * 0.18, CELL_SIZE * 0.62, pt)
		var pa := 1.0 - pt
		draw_arc(pp, prad, 0.0, TAU, 18, Color(0.95, 0.85, 0.40, pa * 0.8), 2.0)
		for k in range(5):
			var ang := TAU * float(k) / 5.0
			draw_circle(pp + Vector2(cos(ang), sin(ang)) * prad * 0.9, maxf(1.0, CELL_SIZE * 0.07 * pa), Color(0.35, 0.58, 0.30, pa))

	# Punch: arm + fist (only the fist deals damage).
	if _punch_active:
		var fist := _fist_pos()
		draw_line(_player_pos, fist, Color(0.27, 0.25, 0.26), maxf(3.0, CELL_SIZE * 0.16))
		draw_circle(fist, FIST_R, Color(0.36, 0.30, 0.28))
		draw_circle(fist, FIST_R * 0.6, Color(0.20, 0.16, 0.15))

	# Punch-connect spark.
	if _spark_t < 1.0:
		var sa := 1.0 - _spark_t
		var srad := lerpf(CELL_SIZE * 0.1, CELL_SIZE * 0.38, _spark_t)
		for k in range(6):
			var ang := TAU * float(k) / 6.0
			draw_line(_spark_pos, _spark_pos + Vector2(cos(ang), sin(ang)) * srad, Color(1, 1, 0.85, sa), 2.0)

	# Turret status overlays (category dot, HP bar, broken X, unconfigured ring).
	# Adhesive slow fields (drawn under the turrets).
	for tidx0 in _turrets:
		var ta: Dictionary = _turrets[tidx0]
		if ta["type"] == "adhesive" and not ta["broken"] and (ta["field"] as Vector2) != Vector2.INF:
			var fr := float(TURRET_DEFS["adhesive"]["field"]) * CELL_SIZE
			draw_circle(ta["field"], fr, Color(0.45, 0.85, 0.55, 0.16))
			draw_arc(ta["field"], fr, 0.0, TAU, 40, Color(0.5, 0.9, 0.6, 0.5), 1.5)
	var tcat_col := {"physical": Color(0.95, 0.6, 0.25), "ranged": Color(0.5, 0.72, 1.0), "support": Color(0.55, 1.0, 0.6)}
	for tidx in _turrets:
		var tt: Dictionary = _turrets[tidx]
		var tp: Vector2 = tt["pos"]
		if tt["type"] == "":
			var pr := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 180.0)
			draw_arc(tp, CELL_SIZE * 0.42, 0.0, TAU, 24, Color(0.95, 0.85, 0.30, 0.4 + 0.4 * pr), 2.0)
			continue
		# Moving turrets (drill/engineer) are drawn at their roaming position.
		if TURRET_DEFS[tt["type"]].get("mover", false) and tp.distance_to(_cell_center_world(tt["cell"])) > 2.0:
			draw_texture_rect(_tiles[Terrain.TURRET], Rect2(tp - cell_vec * 0.5, cell_vec), false)
		var bw := CELL_SIZE * 0.8
		var frac := clampf(float(tt["hp"]) / float(tt["max_hp"]), 0.0, 1.0)
		var bx := tp + Vector2(-bw * 0.5, -CELL_SIZE * 0.58)
		draw_rect(Rect2(bx, Vector2(bw, 3.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx, Vector2(bw * frac, 3.0)), Color(0.4, 0.8, 0.4) if not tt["broken"] else Color(0.8, 0.3, 0.3))
		draw_circle(tp + Vector2(0, -CELL_SIZE * 0.48), 2.5, tcat_col[tt["category"]])
		if tt["broken"]:
			draw_line(tp + Vector2(-7, -7), tp + Vector2(7, 7), Color(0.85, 0.2, 0.2, 0.9), 3.0)
			draw_line(tp + Vector2(7, -7), tp + Vector2(-7, 7), Color(0.85, 0.2, 0.2, 0.9), 3.0)

	# Player: gorilla (white flash when hurt).
	var prect := Rect2(_player_pos - cell_vec * 0.5, cell_vec)
	draw_texture_rect(_tex_gorilla, prect, false)
	if _hurt_flash > 0.0:
		draw_texture_rect(_tex_gorilla_flash, prect, false, Color(1, 1, 1, clampf(_hurt_flash / FLASH_TIME, 0.0, 1.0) * 0.85))

	# Status overlays on the player.
	if _burn_t > 0.0:
		for k in range(4):
			var ang := TAU * float(k) / 4.0 + float(Time.get_ticks_msec()) / 90.0
			var fp := _player_pos + Vector2(cos(ang), sin(ang)) * CELL_SIZE * 0.32
			draw_circle(fp, CELL_SIZE * 0.12, Color(1.0, 0.45, 0.10, 0.7))
	if _freeze_t > 0.0:
		draw_rect(prect.grow(2.0), Color(0.6, 0.85, 1.0, 0.40), true)
		draw_rect(prect.grow(2.0), Color(0.85, 0.95, 1.0, 0.85), false, 2.0)
	elif _slow_t > 0.0:
		draw_circle(_player_pos, CELL_SIZE * 0.46, Color(0.6, 0.85, 1.0, 0.18))

	# Equipped-weapon ammo, read at a glance right beside the gorilla.
	_draw_weapon_ammo_readout()

	# Transient juice on top of every entity (bursts, combat numbers, the dawn bloom).
	_draw_fx()


# At-a-glance ammo for the equipped ranged weapon, drawn on the board anchored to
# the player (bottom-right of the sprite). Only the slingshot consumes carried shot,
# so this only appears for the slingshot, and only when it matters: at night or while
# crocs are about. The count pulses red when the pouch is empty.
func _draw_weapon_ammo_readout() -> void:
	if _weapon_equipped != "slingshot":
		return
	if not _is_night and _monsters.is_empty():
		return   # don't clutter a peaceful day
	var n := _inv("sling_ammo")
	var anchor := _player_pos + Vector2(CELL_SIZE * 0.6, CELL_SIZE * 0.5)
	var icon: Texture2D = _item_icons.get("sling_ammo", null)
	if icon != null:
		var isz := CELL_SIZE * 0.42
		draw_texture_rect(icon, Rect2(anchor, Vector2(isz, isz)), false)
	var font := ThemeDB.fallback_font
	var fs := int(CELL_SIZE * 0.42)
	var txt := "x%d" % n
	var tpos := anchor + Vector2(CELL_SIZE * 0.46, CELL_SIZE * 0.36)
	var col := Color(0.95, 0.96, 0.98)
	if n <= 0:
		# Empty -- pulse red so the dry pouch reads instantly mid-fight.
		var pulse := 0.6 + 0.4 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 160.0 * TAU * 0.5))
		col = Color(0.85, 0.36, 0.30, pulse)
	# A 1px shadow keeps the glyphs legible over busy grass.
	draw_string(font, tpos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# -----------------------------------------------------------------------------
# Juice rendering: the _fx transient-effects list (§1-7). Eases are inline (no
# tween nodes); per-instance jitter is derived arithmetically from each entry's
# baked "seed" so _draw stays deterministic for --selftest / --shot.
# -----------------------------------------------------------------------------
func _fx_ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _fx_ease_in(t: float) -> float:
	return t * t


# Ground-level spawn-preview rings, drawn EARLY (under the crocs) -- see _draw.
func _draw_fx_spawn_warn() -> void:
	for e in _fx:
		if e.get("kind", "") != "spawn_warn":
			continue
		var p: Vector2 = e["pos"]
		var t: float = e["t"]
		# As the window drains the ring swells + brightens, bubbling to a boil.
		var grow := 1.0 + t * 0.6
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 180.0)
		var a := (0.35 + 0.45 * pulse) * (0.4 + 0.6 * t)
		draw_circle(p, CELL_SIZE * 0.4 * grow, Color(0.7, 0.15, 0.12, (0.10 + 0.12 * pulse) * (0.4 + 0.6 * t)))
		draw_arc(p, CELL_SIZE * 0.45 * grow, 0.0, TAU, 20, Color(0.85, 0.22, 0.16, a), 2.0)


# Combat text via the built-in procedural font, drop-shadow first for legibility.
# Centered horizontally on `center_top` (x = midpoint). draw_string with width=-1
# left-aligns from the baseline, so we measure and shift to center at the point.
func _draw_fx_text(center_top: Vector2, text: String, size: int, fill: Color, shadow: Color) -> void:
	var w := _fx_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base := Vector2(center_top.x - w * 0.5, center_top.y)
	draw_string(_fx_font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	draw_string(_fx_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


# Everything that sits ON TOP of the entities. Switch on "kind".
func _draw_fx() -> void:
	for e in _fx:
		match String(e.get("kind", "")):
			"croc_gore": _draw_fx_croc_gore(e)
			"croc_chunks": _draw_fx_croc_chunks(e)
			"flash_dot": _draw_fx_flash_dot(e)
			"wall_hit": _draw_fx_wall_hit(e)
			"build": _draw_fx_build(e)
			"tier_bloom": _draw_fx_tier_bloom(e)
			"dmgnum": _draw_fx_dmgnum(e)
			"dusk_sweep": _draw_fx_dusk_sweep(e)
			# spawn_warn drawn early in _draw_fx_spawn_warn (under the crocs).


func _draw_fx_croc_gore(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var et := _fx_ease_out(t)
	var rad := lerpf(CELL_SIZE * 0.15, CELL_SIZE * 0.70, et)
	draw_circle(p, rad, Color(0.30, 0.50, 0.26, (1.0 - t) * 0.45))   # murky swamp-green fill
	draw_arc(p, rad, 0.0, TAU, 22, Color(0.55, 0.78, 0.40, (1.0 - t) * 0.85), 2.0)


func _draw_fx_croc_chunks(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var seed: int = int(e.get("seed", 0))
	var et := _fx_ease_out(t)
	var droop := _fx_ease_in(t) * CELL_SIZE * 0.5
	for k in range(7):
		var ang := TAU * float(k) / 7.0 + float(seed) * 0.013
		var dist := lerpf(CELL_SIZE * 0.1, CELL_SIZE * 0.85, et)
		var cp := p + Vector2(cos(ang), sin(ang)) * dist + Vector2(0, droop)
		var r := maxf(1.0, CELL_SIZE * 0.09 * (1.0 - t))
		var col: Color
		if k == 2 or k == 5:
			col = Color(0.85, 0.82, 0.70, 1.0 - t)              # bone-pale teeth (comedic)
		elif k % 2 == 0:
			col = Color(0.33, 0.55, 0.28, 1.0 - t)
		else:
			col = Color(0.22, 0.38, 0.20, 1.0 - t)
		draw_circle(cp, r, col)


func _draw_fx_flash_dot(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var rad := lerpf(CELL_SIZE * 0.4, CELL_SIZE * 0.05, t)       # snaps shut
	draw_circle(p, rad, Color(1, 1, 0.92, (1.0 - t) * 0.9))


func _draw_fx_wall_hit(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var seed: int = int(e.get("seed", 0))
	var et := _fx_ease_out(t)
	# Impact star: 5 short tan splinter spokes.
	for k in range(5):
		var ang := TAU * float(k) / 5.0 + float(seed) * 0.02
		var dir := Vector2(cos(ang), sin(ang))
		var reach := lerpf(CELL_SIZE * 0.12, CELL_SIZE * 0.34, et)
		draw_line(p, p + dir * reach, Color(0.85, 0.80, 0.66, (1.0 - t) * 0.9), 2.0)
	# Dust puff.
	draw_circle(p, lerpf(CELL_SIZE * 0.1, CELL_SIZE * 0.3, et), Color(0.62, 0.58, 0.50, (1.0 - t) * 0.4))
	# 3 splinter flecks.
	for k in range(3):
		var ang := TAU * float(k) / 3.0 + float(seed) * 0.05
		draw_circle(p + Vector2(cos(ang), sin(ang)) * CELL_SIZE * 0.28 * et, 1.5, Color(0.55, 0.45, 0.32, 1.0 - t))


func _draw_fx_build(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var repair: bool = bool(e.get("repair", false))
	var et := _fx_ease_out(t)
	# Slam ring: a square outline that COLLAPSES onto the cell border (gathers).
	var half := lerpf(CELL_SIZE * 0.95, CELL_SIZE * 0.5, et)
	var ring_col := Color(0.55, 0.85, 1.0, (1.0 - t) * 0.85) if repair else Color(0.40, 1.0, 0.45, (1.0 - t) * 0.9)
	draw_rect(Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), ring_col, false, lerpf(3.0, 1.0, t))
	# Dust kick-out along the bottom two corners (sells the tile landing).
	for k in range(6):
		var fx := lerpf(-0.45, 0.45, float(k) / 5.0)
		var dp := p + Vector2(fx * CELL_SIZE, CELL_SIZE * 0.42 - et * CELL_SIZE * 0.25)
		draw_circle(dp, CELL_SIZE * 0.08, Color(0.72, 0.66, 0.52, (1.0 - t) * 0.5))
	# Sparkle cross at center for the first 0.2s.
	if t < 0.44:
		var sc := Color(0.85, 1.0, 0.88, 1.0 - t)
		draw_line(p + Vector2(-CELL_SIZE * 0.18, 0), p + Vector2(CELL_SIZE * 0.18, 0), sc, 2.0)
		draw_line(p + Vector2(0, -CELL_SIZE * 0.18), p + Vector2(0, CELL_SIZE * 0.18), sc, 2.0)


func _draw_fx_tier_bloom(e: Dictionary) -> void:
	var t: float = e["t"]
	var c: Vector2 = e["pos"]
	var seed: int = int(e.get("seed", 0))
	var et := _fx_ease_out(t)
	# Core glow flash: the tree lights up from within.
	draw_circle(c, lerpf(CELL_SIZE * 1.4, CELL_SIZE * 0.3, t), Color(1.0, 0.97, 0.80, (1.0 - t) * 0.6))
	# Sunburst rays (the dawn fan), rotating slowly.
	for k in range(12):
		var ang := TAU * float(k) / 12.0 + t * 0.4
		var reach := lerpf(CELL_SIZE * 1.0, CELL_SIZE * 4.5, et)
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * reach, Color(1.0, 0.86, 0.45, pow(1.0 - t, 1.3) * 0.7), lerpf(6.0, 1.0, t))
	# Two concentric bloom rings (stagger the outer).
	var r_in := lerpf(CELL_SIZE * 0.6, CELL_SIZE * 3.8, et)
	draw_arc(c, r_in, 0.0, TAU, 40, Color(0.55, 1.0, 0.62, (1.0 - t) * 0.9), 3.0)
	if t > 0.15:
		var t2 := (t - 0.15) / 0.85
		var r_out := lerpf(CELL_SIZE * 0.6, CELL_SIZE * 3.8, _fx_ease_out(t2))
		draw_arc(c, r_out, 0.0, TAU, 40, Color(1.0, 0.90, 0.55, (1.0 - t2) * 0.7), 3.0)
	# Leaf burst: 16 flecks flung up-and-out, drooping under gravity with a sway.
	var leaf_cols := [FX_LEAF, FX_LEAF_L, FX_LEAF_D]
	for k in range(16):
		var ang := TAU * float(k) / 16.0 + float(seed) * 0.01
		var dist := lerpf(0.0, CELL_SIZE * 2.6, et)
		var lp := c + Vector2(cos(ang), sin(ang)) * dist
		lp += Vector2(0, _fx_ease_in(t) * CELL_SIZE * 1.4)          # gravity droop
		lp += Vector2(sin(t * 6.0 + float(k)) * 4.0, 0)            # gentle sway
		var lc: Color = leaf_cols[k % 3]
		lc.a = 1.0 - t
		var s := 5.0
		draw_colored_polygon(PackedVector2Array([
			lp + Vector2(0, -s), lp + Vector2(s * 0.6, 0), lp + Vector2(0, s), lp + Vector2(-s * 0.6, 0)]), lc)


func _draw_fx_dusk_sweep(e: Dictionary) -> void:
	var t: float = e["t"]
	var c: Vector2 = e["pos"]
	# A wide, low-alpha golden wash that swells then fades (subtle flourish).
	var a := sin(t * PI) * 0.12
	draw_circle(c, lerpf(CELL_SIZE * 2.0, CELL_SIZE * 9.0, _fx_ease_out(t)), Color(1.0, 0.80, 0.40, a))


func _draw_fx_dmgnum(e: Dictionary) -> void:
	var t: float = e["t"]
	var p: Vector2 = e["pos"]
	var seed: int = int(e.get("seed", 0))
	var channel := String(e.get("channel", "damage"))
	var n := int(round(float(e.get("amount", 0.0))))
	# Channel copy + color.
	var txt := ""
	var fill := Color.WHITE
	var shadow := Color(0.1, 0.1, 0.1)
	var base_size := 16
	match channel:
		"heal":
			txt = "+%d" % n
			fill = Color(0.40, 0.92, 0.48); shadow = Color(0.02, 0.12, 0.04)
		"blocked":
			txt = "%d" % n
			fill = Color(0.70, 0.72, 0.74); shadow = Color(0.10, 0.10, 0.12); base_size = 13
		"tier":
			txt = String(e.get("txt", "TIER"))
			fill = Color(1.0, 0.86, 0.40); shadow = Color(0.20, 0.10, 0.0); base_size = 26
		_:
			txt = "%d" % n
			fill = Color(0.95, 0.30, 0.26); shadow = Color(0.15, 0.02, 0.02)
			if n >= 25:
				base_size = 22                                     # crit emphasis
	if txt == "":
		return
	# Rise + seeded horizontal fan.
	var rise := CELL_SIZE * 0.9 if channel != "tier" else CELL_SIZE * 1.5
	var y := p.y - lerpf(0.0, rise, _fx_ease_out(t))
	var x := p.x + float((seed % 7) - 3) * 1.5
	# Pop scale: re-triggers on every aggregation re-pop (t was reset).
	var pop := 1.0 + 0.6 * (1.0 - _fx_ease_out(minf(t / 0.18, 1.0)))
	var size := int(round(float(base_size) * pop))
	# Alpha: full until t=0.6 then linear fade.
	var a := 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
	var fa := fill; fa.a = a
	var sa := shadow; sa.a = a
	_draw_fx_text(Vector2(x, y), txt, size, fa, sa)
	# Crit / tier: a one-frame white outline ring for weight on the first pop.
	if (channel == "damage" and n >= 25 and t < 0.12) or (channel == "tier" and t < 0.10):
		draw_arc(Vector2(x, y - float(size) * 0.35), float(size) * 0.8, 0.0, TAU, 18, Color(1, 1, 1, a * 0.7), 1.5)


# Screen-space radial countdown clock (§8A), drawn by the CountdownClock Control.
# `ctrl` is that Control (HUD space, top-center). Reads secs_left from _time.
func _draw_countdown_clock(ctrl: Control) -> void:
	if not _dusk_active:
		return
	var secs_left := maxf(0.0, (0.78 - _time) * DAY_LENGTH)
	var R := 40.0
	var center := Vector2(ctrl.size.x * 0.5, 24.0 + R)
	# Remaining fraction of the whole 15s warning window.
	var frac := clampf(secs_left / 15.0, 0.0, 1.0)
	# Color ramp gold->amber->red as night nears; bias fully red in the final 10s.
	var clockcol := Color(1.0, 0.84, 0.30).lerp(Color(0.92, 0.20, 0.16), 1.0 - frac)
	if secs_left <= 10.0:
		clockcol = Color(0.92, 0.20, 0.16).lerp(clockcol, 0.25)
		var fast := float(Time.get_ticks_msec()) / 120.0
		clockcol.a *= 0.7 + 0.3 * (0.5 + 0.5 * sin(fast)) * (0.5 + 0.5 * _clock_flash)
	# Dial ring (dark backdrop) + depleting wedge sweeping clockwise from top.
	ctrl.draw_arc(center, R, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 4.0)
	ctrl.draw_arc(center, R, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, clockcol, 5.0)
	# Center text.
	if secs_left <= 3.0:
		# Bare pulsing 3 / 2 / 1, re-kicked each second via _clock_flash.
		var big := "%d" % int(ceil(secs_left))
		var ps := int(round(30.0 * (1.0 + 0.25 * _clock_flash)))
		_draw_ctrl_text(ctrl, center + Vector2(0, 10), big, ps, clockcol, Color(0.1, 0, 0))
	else:
		_draw_ctrl_text(ctrl, center + Vector2(0, -6), "NIGHT IN", 11, Color(0.8, 0.8, 0.85), Color(0, 0, 0, 0.7))
		var cnt := "%d:%02d" % [int(secs_left) / 60, int(secs_left) % 60]
		_draw_ctrl_text(ctrl, center + Vector2(0, 16), cnt, 22, clockcol, Color(0.1, 0.05, 0.0, 0.9))


# Centered drop-shadowed text on a Control (HUD space). Measure + shift to center.
func _draw_ctrl_text(ctrl: Control, center_baseline: Vector2, text: String, size: int, fill: Color, shadow: Color) -> void:
	var w := _fx_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base := Vector2(center_baseline.x - w * 0.5, center_baseline.y)
	ctrl.draw_string(_fx_font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	ctrl.draw_string(_fx_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


# Build-mode cursor: a translucent ghost of the structure-to-place following the
# hover cell, tinted by placement legality (OK green / blocked-or-unaffordable red),
# or a red destroy outline when hovering an existing structure to remove. Replaces
# the old bare cell outline so the player sees WHAT lands and WHETHER it can.
func _draw_build_ghost(cell_vec: Vector2) -> void:
	var origin := Vector2(_hover_cell) * CELL_SIZE
	var cell_rect := Rect2(origin, cell_vec)
	# Removing: hovering a structure of our own -> show the destroy intent in red.
	if _structure_key_for_terrain(_terrain_at(_hover_cell)) != "":
		draw_rect(cell_rect, COLOR_DESTROY_HL, false, 3.0)
		return
	# No structure selected yet (just entered build): a neutral build outline.
	if _build_struct == "":
		draw_rect(cell_rect, COLOR_BUILD_HL, false, 3.0)
		return
	var s: Dictionary = STRUCTURES[_build_struct]
	var spot_ok := _build_placement_valid_spot(_hover_cell)
	var afford := _can_afford(s["cost"])
	var ok := spot_ok and afford
	# A soft pulse so the cursor reads as "live" even when stationary.
	var pulse := 0.78 + 0.22 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 220.0))
	# Tint: green when placeable, red when the spot is blocked or unaffordable.
	var tint := Color(0.55, 1.0, 0.55, 0.55 * pulse) if ok else Color(1.0, 0.45, 0.42, 0.5 * pulse)
	var ghost: Texture2D = _tiles.get(int(s["terrain"]), null)
	if ghost != null:
		draw_texture_rect(ghost, cell_rect, false, tint)
	else:
		draw_rect(cell_rect, Color(tint.r, tint.g, tint.b, tint.a * 0.6), true)
	# Outline echoes the verdict so it reads even where the sprite is faint.
	var edge := COLOR_BUILD_HL if ok else COLOR_DESTROY_HL
	draw_rect(cell_rect, edge, false, 3.0)
	# When the only problem is cost (the spot itself is valid), mark it with a small
	# red "no funds" coin pip so the player blames the wallet, not the tile.
	if spot_ok and not afford:
		var ctr := origin + cell_vec * Vector2(0.78, 0.22)
		draw_circle(ctr, CELL_SIZE * 0.13, Color(0.85, 0.30, 0.26, 0.9))
		draw_line(ctr + Vector2(-4, -4), ctr + Vector2(4, 4), Color(1, 1, 1, 0.95), 2.0)


# Little red berries clustered on a bush, one dot per berry (max 3).
func _draw_bush_berries(pos: Vector2, count: int) -> void:
	var spots := [Vector2(0.34, 0.40), Vector2(0.62, 0.52), Vector2(0.46, 0.64)]
	for i in range(mini(count, spots.size())):
		var p: Vector2 = pos + (spots[i] as Vector2) * CELL_SIZE
		draw_circle(p, CELL_SIZE * 0.10, Color(0.78, 0.16, 0.22))
		draw_circle(p, CELL_SIZE * 0.05, Color(0.95, 0.45, 0.45))


# -----------------------------------------------------------------------------
# Pixel-art sprite baking (16x16 textures, drawn nearest-neighbour)
# -----------------------------------------------------------------------------
func _img16() -> Image:
	return _img(16)


# Generalized N x N transparent canvas. _img16() is _img(16). Every primitive
# below bounds-checks against im.get_width()/get_height() so a 24px bake (item
# icons) clips correctly instead of silently writing into the 16px corner.
func _img(n: int) -> Image:
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im


func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < im.get_width() and y >= 0 and y < im.get_height():
		im.set_pixel(x, y, c)


func _disc(im: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var lo_x := maxi(0, cx - r)
	var hi_x := mini(im.get_width() - 1, cx + r)
	var lo_y := maxi(0, cy - r)
	var hi_y := mini(im.get_height() - 1, cy + r)
	for y in range(lo_y, hi_y + 1):
		for x in range(lo_x, hi_x + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r * r:
				im.set_pixel(x, y, c)


func _disc_clear(im: Image, cx: int, cy: int, r: int) -> void:
	_disc(im, cx, cy, r, Color(0, 0, 0, 0))


func _rect(im: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(im, x, y, c)


func _hline(im: Image, y: int, x0: int, x1: int, c: Color) -> void:
	for x in range(x0, x1 + 1):
		_px(im, x, y, c)


func _vline(im: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		_px(im, x, y, c)


# Filled triangle via scanline span (barycentric sign test per pixel inside the
# bounding box). Needed for the angular silhouettes (flanker spikes, sapper
# claw, fluid-vessel tapers, banana crescent). Bounds-checks via _px.
func _tri(im: Image, ax: int, ay: int, bx: int, by: int, cx: int, cy: int, c: Color) -> void:
	var minx := mini(ax, mini(bx, cx))
	var maxx := maxi(ax, maxi(bx, cx))
	var miny := mini(ay, mini(by, cy))
	var maxy := maxi(ay, maxi(by, cy))
	var area := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	if area == 0:
		return   # degenerate -- nothing to fill
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var w0 := (bx - ax) * (y - ay) - (by - ay) * (x - ax)
			var w1 := (cx - bx) * (y - by) - (cy - by) * (x - bx)
			var w2 := (ax - cx) * (y - cy) - (ay - cy) * (x - cx)
			# Inside iff all cross products share the triangle's winding sign.
			if area > 0:
				if w0 >= 0 and w1 >= 0 and w2 >= 0:
					_px(im, x, y, c)
			else:
				if w0 <= 0 and w1 <= 0 and w2 <= 0:
					_px(im, x, y, c)


# 1px keyline: paint color c into every transparent pixel that 4-borders an
# opaque one. The single biggest legibility lever at small render sizes -- the
# silhouette reads against grass AND the dark Den mound. Reads the source alpha
# first so the outline never eats into the subject.
func _outline(im: Image, c: Color, thickness: int = 1) -> void:
	for _t in range(maxi(1, thickness)):
		var w := im.get_width()
		var h := im.get_height()
		var add: Array = []
		for y in range(h):
			for x in range(w):
				if im.get_pixel(x, y).a > 0.0:
					continue
				var touch := false
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var o: Vector2i = off
					var nx := x + o.x
					var ny := y + o.y
					if nx >= 0 and nx < w and ny >= 0 and ny < h and im.get_pixel(nx, ny).a > 0.0:
						touch = true
						break
				if touch:
					add.append(Vector2i(x, y))
		for p in add:
			im.set_pixel(p.x, p.y, c)


func _speckle(im: Image, c1: Color, c2: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := im.get_width()
	var h := im.get_height()
	for i in range(18):
		im.set_pixel(rng.randi() % w, rng.randi() % h, c1 if i % 2 == 0 else c2)


func _mktex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)


func _mirror(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var out := _img(w)
	for y in range(h):
		for x in range(w):
			out.set_pixel(w - 1 - x, y, im.get_pixel(x, y))
	return out


func _bake_sprites() -> void:
	# Palette
	var GRASS := Color(0.42, 0.60, 0.31)
	var GRASS_D := Color(0.35, 0.52, 0.26)
	var GRASS_L := Color(0.50, 0.69, 0.37)
	var WATER := Color(0.26, 0.44, 0.62)
	var WATER_L := Color(0.37, 0.57, 0.75)
	var STONE := Color(0.52, 0.52, 0.55)
	var STONE_D := Color(0.40, 0.40, 0.43)
	var STONE_L := Color(0.66, 0.66, 0.70)
	var TRUNK := Color(0.42, 0.28, 0.15)
	var TRUNK_D := Color(0.30, 0.20, 0.10)
	var LEAF := Color(0.20, 0.42, 0.22)
	var LEAF_D := Color(0.14, 0.32, 0.16)
	var LEAF_L := Color(0.31, 0.55, 0.31)
	var WOOD := Color(0.55, 0.38, 0.20)
	var WOOD_D := Color(0.41, 0.27, 0.13)
	var BRICK := Color(0.62, 0.62, 0.66)
	var MORTAR := Color(0.34, 0.34, 0.38)
	var FLOORC := Color(0.74, 0.66, 0.48)
	var FLOOR_L := Color(0.83, 0.75, 0.57)
	var FLOOR_D := Color(0.60, 0.52, 0.36)
	var DOORC := Color(0.58, 0.40, 0.22)
	var DOOR_D := Color(0.40, 0.27, 0.13)
	var KNOB := Color(0.92, 0.82, 0.32)
	var BENCH := Color(0.72, 0.52, 0.26)
	var BENCH_D := Color(0.45, 0.30, 0.14)
	var CHEST := Color(0.52, 0.35, 0.17)
	var CHEST_D := Color(0.36, 0.23, 0.10)
	var LATCH := Color(0.86, 0.78, 0.40)
	var FUR := Color(0.27, 0.25, 0.26)
	var FUR_D := Color(0.16, 0.15, 0.16)
	var MUZZLE := Color(0.49, 0.43, 0.41)
	var EYEK := Color(0.05, 0.05, 0.06)
	var CROC := Color(0.32, 0.54, 0.30)
	var CROC_D := Color(0.20, 0.38, 0.20)
	var BELLY := Color(0.58, 0.72, 0.46)
	var CEYE := Color(0.95, 0.86, 0.30)
	var TOOTH := Color(0.96, 0.96, 0.90)
	var BANANA := Color(0.97, 0.83, 0.20)
	var BANANA_D := Color(0.80, 0.62, 0.12)
	var BANANA_TIP := Color(0.45, 0.34, 0.10)

	# GRASS
	var g := _img16(); g.fill(GRASS); _speckle(g, GRASS_D, GRASS_L, 1)
	_tiles[Terrain.GRASS] = _mktex(g)

	# WATER
	var w := _img16(); w.fill(WATER); _speckle(w, WATER_L, WATER, 2)
	_hline(w, 4, 2, 6, WATER_L); _hline(w, 10, 9, 13, WATER_L)
	_tiles[Terrain.WATER] = _mktex(w)

	# STONE
	var s := _img16(); s.fill(STONE)
	_disc(s, 5, 6, 3, STONE_L); _disc(s, 11, 10, 4, STONE_D); _vline(s, 8, 4, 11, STONE_D)
	_tiles[Terrain.STONE] = _mktex(s)

	# TREE
	var t := _img16(); t.fill(GRASS); _speckle(t, GRASS_D, GRASS_L, 3)
	_rect(t, 7, 8, 2, 7, TRUNK)
	_disc(t, 8, 5, 5, LEAF_D); _disc(t, 8, 5, 4, LEAF); _disc(t, 6, 4, 2, LEAF_L)
	_tiles[Terrain.TREE] = _mktex(t)

	# STUMP
	var su := _img16(); su.fill(GRASS); _speckle(su, GRASS_D, GRASS_L, 4)
	_disc(su, 8, 9, 3, TRUNK_D); _disc(su, 8, 9, 2, TRUNK)
	_tiles[Terrain.STUMP] = _mktex(su)

	# SAPLING
	var sa := _img16(); sa.fill(GRASS); _speckle(sa, GRASS_D, GRASS_L, 5)
	_vline(sa, 8, 8, 12, TRUNK); _disc(sa, 8, 7, 2, LEAF)
	_px(sa, 6, 8, LEAF); _px(sa, 10, 8, LEAF)
	_tiles[Terrain.SAPLING] = _mktex(sa)

	# WOOD WALL
	var ww := _img16(); ww.fill(WOOD)
	for yy in [0, 5, 10, 15]:
		_hline(ww, yy, 0, 15, WOOD_D)
	_vline(ww, 8, 1, 4, WOOD_D); _vline(ww, 4, 6, 9, WOOD_D)
	_vline(ww, 12, 6, 9, WOOD_D); _vline(ww, 8, 11, 14, WOOD_D)
	_tiles[Terrain.WOOD_WALL] = _mktex(ww)

	# STONE WALL
	var sw := _img16(); sw.fill(BRICK)
	_hline(sw, 0, 0, 15, MORTAR); _hline(sw, 8, 0, 15, MORTAR); _hline(sw, 15, 0, 15, MORTAR)
	_vline(sw, 0, 1, 7, MORTAR); _vline(sw, 8, 1, 7, MORTAR)
	_vline(sw, 4, 9, 14, MORTAR); _vline(sw, 12, 9, 14, MORTAR)
	_tiles[Terrain.STONE_WALL] = _mktex(sw)

	# DOOR
	var d := _img16(); d.fill(DOORC)
	_vline(d, 3, 0, 15, DOOR_D); _vline(d, 8, 0, 15, DOOR_D); _vline(d, 12, 0, 15, DOOR_D)
	_hline(d, 0, 0, 15, DOOR_D); _hline(d, 15, 0, 15, DOOR_D)
	_disc(d, 11, 8, 1, KNOB)
	_tiles[Terrain.DOOR] = _mktex(d)

	# FLOOR
	var fl := _img16(); fl.fill(FLOORC)
	for yy in [0, 5, 10, 15]:
		_hline(fl, yy, 0, 15, FLOOR_D)
	for yy in [2, 7, 12]:
		_hline(fl, yy, 0, 15, FLOOR_L)
	_tiles[Terrain.FLOOR] = _mktex(fl)

	# WORKBENCH
	var wb := _img16(); wb.fill(GRASS); _speckle(wb, GRASS_D, GRASS_L, 6)
	_rect(wb, 2, 4, 12, 3, BENCH)
	_rect(wb, 3, 7, 2, 8, BENCH_D); _rect(wb, 11, 7, 2, 8, BENCH_D)
	_px(wb, 5, 5, BENCH_D); _px(wb, 10, 5, BENCH_D)
	_tiles[Terrain.WORKBENCH] = _mktex(wb)

	# STORAGE (chest)
	var ch := _img16(); ch.fill(GRASS); _speckle(ch, GRASS_D, GRASS_L, 7)
	_rect(ch, 3, 5, 10, 9, CHEST)
	_hline(ch, 5, 3, 12, CHEST_D); _hline(ch, 9, 3, 12, CHEST_D); _hline(ch, 13, 3, 12, CHEST_D)
	_vline(ch, 3, 5, 13, CHEST_D); _vline(ch, 12, 5, 13, CHEST_D)
	_rect(ch, 7, 8, 2, 3, LATCH)
	_tiles[Terrain.STORAGE] = _mktex(ch)

	# TURRET (stone mount + barrel + glowing core)
	var tu := _img16(); tu.fill(GRASS); _speckle(tu, GRASS_D, GRASS_L, 8)
	_disc(tu, 8, 10, 5, STONE_D); _disc(tu, 8, 10, 4, STONE)   # base
	_rect(tu, 7, 1, 2, 8, Color(0.26, 0.26, 0.30))             # barrel
	_rect(tu, 6, 1, 4, 2, Color(0.34, 0.34, 0.38))             # muzzle
	_disc(tu, 8, 10, 2, Color(0.85, 0.30, 0.22))               # core
	_tiles[Terrain.TURRET] = _mktex(tu)

	# SPIKE TRAP (dark pit + metal spikes)
	var tp := _img16(); tp.fill(GRASS); _speckle(tp, GRASS_D, GRASS_L, 9)
	_disc(tp, 8, 8, 6, Color(0.16, 0.16, 0.18)); _disc(tp, 8, 8, 5, Color(0.24, 0.24, 0.27))
	for sx in [4, 8, 12]:
		_vline(tp, sx, 4, 12, Color(0.78, 0.80, 0.86))
		_px(tp, sx - 1, 11, Color(0.55, 0.57, 0.62)); _px(tp, sx + 1, 11, Color(0.55, 0.57, 0.62))
	_tiles[Terrain.TRAP] = _mktex(tp)

	# BUSH (leafy shrub; berries drawn as an overlay)
	var bs := _img16(); bs.fill(GRASS); _speckle(bs, GRASS_D, GRASS_L, 11)
	_disc(bs, 8, 10, 5, LEAF_D); _disc(bs, 6, 8, 3, LEAF); _disc(bs, 11, 9, 3, LEAF)
	_disc(bs, 8, 11, 4, LEAF); _px(bs, 5, 7, LEAF_L); _px(bs, 12, 8, LEAF_L)
	_tiles[Terrain.BUSH] = _mktex(bs)

	# BARREL (wooden cask with hoops)
	var br := _img16(); br.fill(GRASS); _speckle(br, GRASS_D, GRASS_L, 12)
	_rect(br, 3, 2, 10, 12, WOOD); _rect(br, 3, 2, 10, 12, WOOD)
	_vline(br, 3, 2, 13, WOOD_D); _vline(br, 12, 2, 13, WOOD_D)
	_hline(br, 2, 4, 11, WOOD_D); _hline(br, 13, 4, 11, WOOD_D)
	_hline(br, 5, 3, 12, Color(0.30, 0.20, 0.10)); _hline(br, 10, 3, 12, Color(0.30, 0.20, 0.10))
	_px(br, 6, 8, WOOD_D); _px(br, 9, 8, WOOD_D)
	_tiles[Terrain.BARREL] = _mktex(br)

	# JUICER (press with a reddish vat)
	var ju := _img16(); ju.fill(GRASS); _speckle(ju, GRASS_D, GRASS_L, 13)
	_rect(ju, 3, 7, 10, 7, Color(0.40, 0.40, 0.45))          # vat
	_rect(ju, 4, 8, 8, 5, Color(0.62, 0.20, 0.28))           # juice
	_rect(ju, 5, 2, 6, 2, Color(0.55, 0.55, 0.60))           # press head
	_vline(ju, 7, 4, 6, Color(0.45, 0.45, 0.50)); _vline(ju, 8, 4, 6, Color(0.45, 0.45, 0.50))
	_tiles[Terrain.JUICER] = _mktex(ju)

	# PLANTER BOX (soil-filled wooden box; berries drawn as overlay)
	var pb := _img16(); pb.fill(GRASS); _speckle(pb, GRASS_D, GRASS_L, 14)
	_rect(pb, 2, 7, 12, 7, WOOD_D)                           # box
	_rect(pb, 3, 8, 10, 5, Color(0.34, 0.22, 0.12))          # soil
	_vline(pb, 2, 7, 13, WOOD); _vline(pb, 13, 7, 13, WOOD)
	_disc(pb, 8, 8, 2, LEAF_D); _disc(pb, 8, 8, 1, LEAF)     # sprout
	_tiles[Terrain.PLANTER] = _mktex(pb)

	# COCONUT PALM (tall trunk + fronds; coconuts drawn as an overlay)
	var co := _img16(); co.fill(GRASS); _speckle(co, GRASS_D, GRASS_L, 15)
	_rect(co, 7, 6, 2, 9, TRUNK); _px(co, 8, 9, TRUNK_D); _px(co, 7, 12, TRUNK_D)
	for fr in [Vector2i(2, 4), Vector2i(13, 4), Vector2i(4, 2), Vector2i(11, 2), Vector2i(8, 1)]:
		_disc(co, fr.x, fr.y, 2, LEAF_D); _px(co, fr.x, fr.y, LEAF_L)
	_disc(co, 8, 4, 2, LEAF)
	_tiles[Terrain.COCONUT] = _mktex(co)

	# BAMBOO (a clump of bright green canes with nodes)
	var bm := _img16(); bm.fill(GRASS); _speckle(bm, GRASS_D, GRASS_L, 16)
	var CANE := Color(0.46, 0.66, 0.30); var CANE_D := Color(0.33, 0.50, 0.22)
	for cxn in [4, 8, 12]:
		_vline(bm, cxn, 1, 15, CANE); _vline(bm, cxn + 1, 1, 15, CANE_D)
		for ny in [3, 7, 11]:
			_px(bm, cxn, ny, CANE_D); _px(bm, cxn + 1, ny, CANE_D)
	_tiles[Terrain.BAMBOO] = _mktex(bm)

	# SAND (pale speckled beach)
	var sd := _img16(); sd.fill(Color(0.82, 0.74, 0.52)); _speckle(sd, Color(0.74, 0.66, 0.44), Color(0.90, 0.83, 0.62), 20)
	_tiles[Terrain.SAND] = _mktex(sd)

	# KILN (stone furnace with a glowing mouth)
	var kn := _img16(); kn.fill(GRASS); _speckle(kn, GRASS_D, GRASS_L, 21)
	_rect(kn, 3, 3, 10, 11, STONE_D); _rect(kn, 4, 4, 8, 9, STONE)
	_rect(kn, 6, 8, 4, 5, Color(0.14, 0.12, 0.12))           # mouth
	_rect(kn, 6, 10, 4, 3, Color(1.0, 0.55, 0.18))           # embers
	_hline(kn, 3, 3, 12, MORTAR); _hline(kn, 8, 3, 12, MORTAR)
	_tiles[Terrain.KILN] = _mktex(kn)

	# HIVE (a striped golden beehive)
	var hv := _img16(); hv.fill(GRASS); _speckle(hv, GRASS_D, GRASS_L, 22)
	_disc(hv, 8, 9, 5, Color(0.62, 0.46, 0.16)); _disc(hv, 8, 8, 5, Color(0.86, 0.68, 0.24))
	_hline(hv, 6, 4, 12, Color(0.62, 0.46, 0.16)); _hline(hv, 10, 4, 12, Color(0.62, 0.46, 0.16))
	_rect(hv, 7, 11, 2, 2, Color(0.20, 0.16, 0.10))   # entrance
	_tiles[Terrain.HIVE] = _mktex(hv)

	# BEE ENCLOSURE (a wood-framed glass box with bees inside)
	var be := _img16(); be.fill(GRASS); _speckle(be, GRASS_D, GRASS_L, 23)
	_rect(be, 2, 3, 12, 11, WOOD_D); _rect(be, 3, 4, 10, 9, Color(0.62, 0.80, 0.88, 0.7))
	_px(be, 6, 7, Color(0.95, 0.82, 0.2)); _px(be, 9, 9, Color(0.95, 0.82, 0.2)); _px(be, 7, 10, Color(0.95, 0.82, 0.2))
	_vline(be, 8, 4, 12, WOOD_D)
	_tiles[Terrain.BEE_ENCLOSURE] = _mktex(be)

	# WORM HABITAT (a tall jar of dark soil with worms)
	var wf := _img16(); wf.fill(GRASS); _speckle(wf, GRASS_D, GRASS_L, 24)
	_rect(wf, 4, 2, 8, 12, Color(0.66, 0.78, 0.84, 0.6)); _rect(wf, 4, 7, 8, 7, Color(0.32, 0.22, 0.13))
	_px(wf, 6, 9, Color(0.85, 0.55, 0.55)); _px(wf, 9, 11, Color(0.85, 0.55, 0.55)); _px(wf, 7, 12, Color(0.85, 0.55, 0.55))
	_hline(wf, 2, 4, 11, WOOD_D)
	_tiles[Terrain.WORM_FARM] = _mktex(wf)

	# CAMPFIRE (logs + flame)
	var cf := _img16(); cf.fill(GRASS); _speckle(cf, GRASS_D, GRASS_L, 25)
	_rect(cf, 3, 11, 10, 2, TRUNK_D); _rect(cf, 5, 12, 7, 2, TRUNK)
	_disc(cf, 8, 8, 3, Color(1.0, 0.5, 0.15)); _disc(cf, 8, 9, 2, Color(1.0, 0.78, 0.3))
	_px(cf, 8, 5, Color(1.0, 0.9, 0.5))
	_tiles[Terrain.CAMPFIRE] = _mktex(cf)

	# GENERATOR (a metal box with a flywheel + warning light)
	var gn := _img16(); gn.fill(GRASS); _speckle(gn, GRASS_D, GRASS_L, 27)
	_rect(gn, 2, 4, 12, 10, STONE_D); _rect(gn, 3, 5, 10, 8, Color(0.50, 0.50, 0.56))
	_disc(gn, 6, 9, 2, Color(0.30, 0.30, 0.34)); _px(gn, 6, 9, Color(0.75, 0.75, 0.8))   # flywheel
	_rect(gn, 10, 6, 2, 2, Color(0.95, 0.7, 0.2))     # indicator
	_tiles[Terrain.GENERATOR] = _mktex(gn)

	# WIRE (a thin vine-wrapped cable lying on the ground)
	var wr := _img16(); wr.fill(GRASS); _speckle(wr, GRASS_D, GRASS_L, 28)
	_hline(wr, 7, 0, 15, Color(0.45, 0.32, 0.16)); _hline(wr, 8, 0, 15, Color(0.58, 0.42, 0.22))
	for wx in [2, 6, 10, 14]:
		_px(wr, wx, 6, Color(0.36, 0.50, 0.26)); _px(wr, wx, 9, Color(0.36, 0.50, 0.26))
	_tiles[Terrain.WIRE] = _mktex(wr)

	# ELECTRIC BULB (glass bulb on a small base)
	var bl := _img16(); bl.fill(GRASS); _speckle(bl, GRASS_D, GRASS_L, 29)
	_disc(bl, 8, 6, 4, Color(0.95, 0.92, 0.6)); _disc(bl, 8, 6, 3, Color(1.0, 0.98, 0.82))
	_rect(bl, 6, 10, 4, 3, Color(0.45, 0.45, 0.5)); _px(bl, 8, 4, Color(1.0, 1.0, 0.95))
	_tiles[Terrain.BULB] = _mktex(bl)

	# LAND MINE (a small buried disc with a trigger nub)
	var lm2 := _img16(); lm2.fill(GRASS); _speckle(lm2, GRASS_D, GRASS_L, 33)
	_disc(lm2, 8, 9, 4, Color(0.30, 0.26, 0.24)); _disc(lm2, 8, 9, 3, Color(0.46, 0.40, 0.36))
	_rect(lm2, 7, 5, 2, 2, Color(0.85, 0.2, 0.15))   # red trigger
	_tiles[Terrain.LAND_MINE] = _mktex(lm2)

	# PEEL LAUNCHER (a bamboo cannon angled up, loaded with a peel)
	var plr := _img16(); plr.fill(GRASS); _speckle(plr, GRASS_D, GRASS_L, 34)
	_rect(plr, 3, 9, 8, 4, TRUNK); _rect(plr, 9, 5, 3, 5, Color(0.46, 0.62, 0.30))
	_px(plr, 11, 4, Color(0.95, 0.86, 0.3)); _px(plr, 12, 4, Color(0.95, 0.86, 0.3))   # peel
	_tiles[Terrain.PEEL_LAUNCHER] = _mktex(plr)

	# ELECTRIC FENCE (posts + a sparking wire)
	var ef := _img16(); ef.fill(GRASS); _speckle(ef, GRASS_D, GRASS_L, 35)
	_vline(ef, 3, 3, 14, TRUNK); _vline(ef, 12, 3, 14, TRUNK)
	_hline(ef, 5, 3, 12, Color(0.70, 0.72, 0.40)); _hline(ef, 9, 3, 12, Color(0.70, 0.72, 0.40))
	_px(ef, 7, 5, Color(0.7, 0.9, 1.0)); _px(ef, 9, 9, Color(0.7, 0.9, 1.0))   # sparks
	_tiles[Terrain.ELECTRIC_FENCE] = _mktex(ef)

	# WRECK (passable rubble left by broken structures)
	var wk := _img16(); wk.fill(GRASS); _speckle(wk, GRASS_D, GRASS_L, 36)
	_rect(wk, 2, 10, 12, 3, Color(0.23, 0.21, 0.18))
	_rect(wk, 3, 8, 4, 2, WOOD_D); _rect(wk, 9, 7, 4, 2, STONE_D)
	_px(wk, 5, 6, Color(0.75, 0.70, 0.58)); _px(wk, 11, 10, Color(0.70, 0.64, 0.52))
	_tiles[Terrain.WRECK] = _mktex(wk)

	# BARRICADE (emergency rough wood)
	var bc := _img16(); bc.fill(GRASS); _speckle(bc, GRASS_D, GRASS_L, 37)
	for bx in [3, 7, 11]:
		_vline(bc, bx, 3, 13, WOOD)
		_vline(bc, bx + 1, 3, 13, WOOD_D)
	_hline(bc, 6, 2, 14, WOOD_D); _hline(bc, 11, 2, 14, WOOD_D)
	_tiles[Terrain.BARRICADE] = _mktex(bc)

	# REINFORCED WALL (stone and metal braces)
	var rw := _img16(); rw.fill(BRICK)
	_hline(rw, 0, 0, 15, MORTAR); _hline(rw, 8, 0, 15, MORTAR); _hline(rw, 15, 0, 15, MORTAR)
	_vline(rw, 3, 0, 15, Color(0.38, 0.40, 0.44)); _vline(rw, 12, 0, 15, Color(0.38, 0.40, 0.44))
	_hline(rw, 4, 1, 14, Color(0.56, 0.58, 0.62)); _hline(rw, 12, 1, 14, Color(0.56, 0.58, 0.62))
	_tiles[Terrain.REINFORCED_WALL] = _mktex(rw)

	# MOTHER TREE -- canopy color + size driven by tier (§5); baked at the live tier.
	_bake_mother_tree_tile(_tree_tier)

	# CROC DEN -- YOUNG (cool, quiet): low mound, small black maw, no embers.
	var dn := _img16(); dn.fill(GRASS); _speckle(dn, GRASS_D, GRASS_L, 39)
	_disc(dn, 8, 11, 6, DEN_MOUND)
	_disc(dn, 8, 11, 3, DEN_MAW)
	_rect(dn, 4, 9, 8, 2, DEN_MOUND.lightened(0.12))
	_tiles[Terrain.CROC_DEN] = _mktex(dn)

	# CROC DEN -- MATURING (warming): wider maw, ember flecks, claw scratches.
	# Drawn as a per-cell overlay so the SAME footprint warms without a new tile.
	var dw := _img16()
	_disc(dw, 8, 11, 6, DEN_MOUND)
	_disc(dw, 8, 11, 4, DEN_MAW)                       # widened maw
	_px(dw, 6, 8, DEN_EMBER); _px(dw, 10, 8, DEN_EMBER)  # ember flecks at the lip
	_px(dw, 5, 13, DEN_MOUND.darkened(0.3)); _px(dw, 11, 12, DEN_MOUND.darkened(0.3))  # claw scratches
	_px(dw, 4, 11, DEN_MOUND.darkened(0.3))
	_tex_den_warm = _mktex(dw)

	# CROC DEN -- MATURE (hot, loud): larger maw, cracked earth, ember veins,
	# raised rock lip. The "fortified -- bring an outpost" read.
	var de := _img16()
	_disc(de, 8, 10, 7, DEN_MOUND.darkened(0.1))
	_disc(de, 8, 10, 5, DEN_MAW)                       # larger central maw
	_speckle(de, DEN_MOUND.darkened(0.25), DEN_EMBER.darkened(0.2), 47)  # cracked earth
	_hline(de, 6, 2, 6, DEN_EMBER); _hline(de, 14, 9, 13, DEN_EMBER)     # ember-vein cracks
	_rect(de, 3, 14, 10, 2, Color(0.30, 0.26, 0.22))   # raised rock lip
	_px(de, 5, 5, DEN_EMBER.lightened(0.2)); _px(de, 12, 6, DEN_EMBER.lightened(0.2))
	_tex_den_evolved = _mktex(de)

	# IRON VEIN / AUTO-MINER / AUTO-LOADER (functional placeholders)
	var iv := _img16(); iv.fill(GRASS); _speckle(iv, GRASS_D, GRASS_L, 40)
	_disc(iv, 8, 9, 6, STONE_D); _disc(iv, 8, 9, 4, STONE)
	_hline(iv, 7, 4, 12, Color(0.78, 0.58, 0.42)); _hline(iv, 10, 5, 11, Color(0.78, 0.58, 0.42))
	_tiles[Terrain.IRON_VEIN] = _mktex(iv)

	var am := _img16(); am.fill(GRASS); _speckle(am, GRASS_D, GRASS_L, 41)
	_rect(am, 3, 7, 10, 6, Color(0.36, 0.38, 0.42)); _rect(am, 6, 3, 4, 8, Color(0.50, 0.52, 0.56))
	_disc(am, 5, 12, 2, Color(0.12, 0.12, 0.14)); _disc(am, 11, 12, 2, Color(0.12, 0.12, 0.14))
	_tiles[Terrain.AUTO_MINER] = _mktex(am)

	var al := _img16(); al.fill(GRASS); _speckle(al, GRASS_D, GRASS_L, 42)
	_rect(al, 3, 5, 10, 8, WOOD); _rect(al, 5, 7, 6, 4, Color(0.22, 0.18, 0.12))
	_hline(al, 4, 4, 12, Color(0.78, 0.68, 0.36)); _hline(al, 12, 4, 12, Color(0.78, 0.68, 0.36))
	_tiles[Terrain.AUTO_LOADER] = _mktex(al)

	# PIPE (a horizontal bamboo conduit lying on the ground)
	var pp := _img16(); pp.fill(GRASS); _speckle(pp, GRASS_D, GRASS_L, 30)
	_rect(pp, 0, 6, 16, 4, Color(0.42, 0.54, 0.30)); _hline(pp, 6, 0, 15, Color(0.54, 0.68, 0.38))
	for px2 in [3, 8, 13]:
		_vline(pp, px2, 6, 9, Color(0.30, 0.42, 0.22))
	_tiles[Terrain.PIPE] = _mktex(pp)

	# SPRINKLER (a nozzle on a post)
	var sp := _img16(); sp.fill(GRASS); _speckle(sp, GRASS_D, GRASS_L, 31)
	_vline(sp, 8, 6, 14, Color(0.45, 0.45, 0.5)); _disc(sp, 8, 5, 2, Color(0.6, 0.66, 0.72))
	_px(sp, 5, 4, Color(0.55, 0.78, 1.0)); _px(sp, 11, 4, Color(0.55, 0.78, 1.0)); _px(sp, 8, 2, Color(0.55, 0.78, 1.0))
	_tiles[Terrain.SPRINKLER] = _mktex(sp)

	# AQUARIUM (a glass tank with water + a fish)
	var aq := _img16(); aq.fill(GRASS); _speckle(aq, GRASS_D, GRASS_L, 32)
	_rect(aq, 2, 3, 12, 11, Color(0.55, 0.40, 0.22)); _rect(aq, 3, 4, 10, 9, Color(0.40, 0.62, 0.80))
	_rect(aq, 3, 4, 10, 2, Color(0.62, 0.80, 0.92))
	_disc(aq, 8, 9, 1, Color(0.95, 0.95, 0.98)); _px(aq, 10, 9, Color(1.0, 0.62, 0.78))
	_tiles[Terrain.AQUARIUM] = _mktex(aq)

	# STILL (a copper pot with a coiled bamboo condenser)
	var stl := _img16(); stl.fill(GRASS); _speckle(stl, GRASS_D, GRASS_L, 26)
	_disc(stl, 6, 10, 4, Color(0.62, 0.42, 0.22)); _disc(stl, 6, 9, 3, Color(0.78, 0.54, 0.30))  # pot
	_vline(stl, 9, 4, 9, Color(0.50, 0.66, 0.34)); _vline(stl, 10, 4, 9, Color(0.40, 0.54, 0.26)) # coil
	_px(stl, 11, 5, Color(0.50, 0.66, 0.34)); _px(stl, 12, 6, Color(0.50, 0.66, 0.34))
	_rect(stl, 11, 11, 2, 3, Color(0.40, 0.34, 0.30))        # spout/jar
	_tiles[Terrain.STILL] = _mktex(stl)

	# GLAPPLE LAMP (a glowing blue apple on a short rod)
	var gl := _img16(); gl.fill(GRASS); _speckle(gl, GRASS_D, GRASS_L, 17)
	_rect(gl, 7, 8, 2, 7, TRUNK)                              # rod
	_disc(gl, 8, 5, 4, Color(0.20, 0.42, 0.78))              # apple (dark rim)
	_disc(gl, 8, 5, 3, Color(0.36, 0.62, 1.0))               # apple body
	_px(gl, 7, 3, Color(0.80, 0.92, 1.0)); _px(gl, 8, 3, Color(0.80, 0.92, 1.0))  # glints
	_tiles[Terrain.GLAPPLE_LAMP] = _mktex(gl)

	# COCONUT (overlay): a couple of brown nuts under the fronds
	var cn := _img16()
	_disc(cn, 6, 7, 2, Color(0.34, 0.22, 0.12)); _disc(cn, 6, 7, 1, Color(0.50, 0.34, 0.20))
	_disc(cn, 10, 8, 2, Color(0.34, 0.22, 0.12)); _disc(cn, 10, 8, 1, Color(0.50, 0.34, 0.20))
	_tex_coconut = _mktex(cn)

	# BANANA (overlay)
	var ba := _img16()
	_disc(ba, 8, 8, 5, BANANA_D)
	_disc(ba, 8, 7, 5, BANANA)
	_disc_clear(ba, 8, 2, 5)
	for p in [Vector2i(3, 9), Vector2i(13, 9)]:
		if ba.get_pixel(p.x, p.y).a > 0.0:
			ba.set_pixel(p.x, p.y, BANANA_TIP)
	_tex_banana = _mktex(ba)

	# GORILLA
	var go := _img16()
	_disc(go, 3, 5, 2, FUR_D); _disc(go, 12, 5, 2, FUR_D)   # ears
	_disc(go, 8, 8, 6, FUR_D); _disc(go, 8, 8, 5, FUR)      # head (dark rim)
	_disc(go, 8, 10, 3, MUZZLE)                              # muzzle
	_rect(go, 5, 7, 2, 2, EYEK); _rect(go, 9, 7, 2, 2, EYEK) # eyes
	_px(go, 7, 11, EYEK); _px(go, 9, 11, EYEK)               # nostrils
	_tex_gorilla = _mktex(go)
	_tex_gorilla_flash = _mktex(_whiteout(go))

	# CROCODILES -- a distinct baked SILHOUETTE per role (not just a tint swap),
	# so role reads at a glance even under the night wash (the split-aggro
	# telegraph depends on it). Color stays the family, shape carries the role.
	for type in CROC_DEFS:
		var def: Dictionary = CROC_DEFS[type]
		# yellow is the flanker -- same "melee" role as the green grunt but its own
		# smaller/spikier silhouette, so the two never collapse to a tint swap.
		var cr := _bake_croc_flanker_img(def["body"], def["belly"]) if type == "yellow" \
			else _bake_croc_img(def["body"], def["belly"], String(def["role"]))
		_croc_tex[type] = {
			"r": _mktex(cr), "l": _mktex(_mirror(cr)),
			"fr": _mktex(_whiteout(cr)), "fl": _mktex(_whiteout(_mirror(cr))),
		}
	# Keep the legacy green handles for the demo/back-compat.
	_tex_croc_r = _croc_tex["green"]["r"]
	_tex_croc_l = _croc_tex["green"]["l"]
	_tex_croc_flash_r = _croc_tex["green"]["fr"]
	_tex_croc_flash_l = _croc_tex["green"]["fl"]


# A crocodile sprite (facing right), with a per-ROLE silhouette so the role is
# legible from the shape alone (test: recognizable as black-on-grey). Color is
# the family; the profile + one role-prop is the telegraph. Universal eye/teeth
# keep every variant reading as a croc. A 1px keyline pops it on grass AND the
# dark Den mound. The mirror/whiteout pipeline is silhouette-agnostic.
func _bake_croc_img(body: Color, belly: Color, role: String = "melee") -> Image:
	var bd := body.darkened(0.35)
	var bdd := body.darkened(0.5)
	var ceye := Color(0.95, 0.86, 0.30)
	var tooth := Color(0.96, 0.96, 0.90)
	var cr := _img16()
	match role:
		"wrecker":
			# Tree-rammer: bulky, armored, blunt squared snout, brow horns. Heaviest.
			_rect(cr, 0, 8, 3, 3, bd)                            # thick tail
			_rect(cr, 1, 6, 12, 5, body)                         # full-width body
			_disc(cr, 3, 9, 2, body)
			_rect(cr, 5, 5, 6, 2, bdd)                           # armor plate across the back
			_rect(cr, 11, 7, 4, 3, body)                         # blunt squared snout
			_hline(cr, 10, 1, 12, belly)                         # belly
			_tri(cr, 5, 5, 7, 5, 6, 3, bd); _tri(cr, 8, 5, 10, 5, 9, 3, bd)  # 2 brow horn nubs
			_px(cr, 8, 5, ceye)                                  # eye
			_px(cr, 12, 10, tooth); _px(cr, 14, 10, tooth)
		"digger":
			# Sapper: hunched + low, big forward digging claw, dirt mound, round head.
			_rect(cr, 0, 9, 3, 2, bd)                            # tail (dropped 1px)
			_rect(cr, 2, 8, 9, 4, body)                          # low body
			_disc(cr, 11, 9, 3, body)                            # round snoutless head
			_hline(cr, 11, 2, 10, belly)
			_tri(cr, 9, 11, 14, 11, 12, 15, bd)                  # digging claw poking down-forward
			_speckle(cr, Color(0.30, 0.22, 0.12), Color(0.42, 0.30, 0.16), 91)  # dirt mound
			_px(cr, 11, 8, ceye)
			_px(cr, 13, 11, tooth)
		"healer":
			# Healer: upright, slender, rears up; baked + heal sigil on the back.
			var hl := belly.lightened(0.2)
			_rect(cr, 0, 9, 3, 2, bd)                            # tail
			_rect(cr, 2, 7, 7, 3, body)                          # thin body
			_rect(cr, 8, 3, 3, 5, body)                          # raised neck (rears up)
			_disc(cr, 9, 3, 2, body)                             # head up high
			_rect(cr, 10, 3, 4, 2, body)                         # snout
			_hline(cr, 9, 2, 8, belly)
			_px(cr, 4, 6, hl); _px(cr, 3, 5, hl); _px(cr, 5, 5, hl); _px(cr, 4, 4, hl); _px(cr, 4, 7, hl)  # + heal cross
			_px(cr, 10, 3, ceye)
			_px(cr, 12, 5, tooth); _px(cr, 13, 5, tooth)
		"reviver":
			# Necro: gaunt, jagged dorsal ridge, hollow ring eye. Darkest/spikiest.
			_rect(cr, 0, 8, 3, 2, bdd)                           # tail
			_rect(cr, 2, 8, 9, 3, body)                          # gaunt thin body
			_disc(cr, 3, 9, 1, body)
			_rect(cr, 10, 8, 6, 2, body)                         # snout
			_hline(cr, 10, 2, 9, belly)
			_tri(cr, 3, 8, 5, 8, 4, 4, bd)                       # tall jagged ridge
			_tri(cr, 6, 8, 8, 8, 7, 3, bd)
			_tri(cr, 9, 8, 11, 8, 10, 4, bd)
			_disc(cr, 7, 6, 1, ceye); _disc_clear(cr, 7, 6, 0)   # hollow ring eye
			_px(cr, 12, 10, tooth); _px(cr, 14, 10, tooth)
		"fire", "ice":
			# Artillery: thin raised head on a neck, throat charge node. ice = back shards.
			_rect(cr, 0, 9, 3, 2, bd)                            # tail
			_rect(cr, 2, 8, 7, 3, body)                          # narrow body
			_vline(cr, 9, 5, 9, body); _vline(cr, 10, 5, 9, body)  # thin raised neck
			_disc(cr, 11, 5, 2, body)                            # raised head
			_rect(cr, 12, 5, 4, 2, body)                         # raised muzzle
			_hline(cr, 10, 2, 8, belly)
			_disc(cr, 10, 8, 1, belly.lightened(0.2))            # throat charge node bump
			if role == "ice":
				_tri(cr, 3, 8, 5, 8, 4, 5, belly.lightened(0.3))  # crystalline shards
				_tri(cr, 5, 8, 7, 8, 6, 4, belly.lightened(0.3))
				_tri(cr, 7, 8, 9, 8, 8, 5, belly.lightened(0.3))
			else:
				_px(cr, 4, 7, bd); _px(cr, 6, 7, bd); _px(cr, 8, 7, bd)  # smooth back ridges
			_px(cr, 11, 5, ceye)
			_px(cr, 14, 7, tooth)
		"poison":
			# Swarm-caster: bloated drippy midsection (gas sac), low head, belly drips.
			_rect(cr, 0, 9, 3, 2, bd)                            # tail
			_rect(cr, 2, 8, 8, 3, body)
			_disc(cr, 6, 8, 4, body)                             # swollen gas-sac midsection
			_rect(cr, 10, 9, 6, 2, body)                         # low head/snout
			_hline(cr, 11, 2, 9, belly)
			_px(cr, 5, 12, bd); _px(cr, 8, 12, bd)               # belly drips
			_px(cr, 11, 9, ceye)
			_px(cr, 13, 11, tooth); _px(cr, 15, 11, tooth)
		"melee":
			# Grunt baseline: low, broad, default croc. (Flanker/yellow is baked
			# separately via _bake_croc_flanker_img.)
			_rect(cr, 0, 8, 3, 2, bd)                            # tail
			_rect(cr, 2, 7, 9, 4, body)                          # body
			_disc(cr, 3, 9, 2, body)
			_rect(cr, 10, 8, 6, 2, body)                         # snout
			_hline(cr, 10, 2, 9, belly)
			_px(cr, 4, 6, bd); _px(cr, 6, 6, bd); _px(cr, 8, 6, bd)  # ridges
			_px(cr, 7, 6, body); _px(cr, 7, 5, ceye)             # eye
			_px(cr, 12, 10, tooth); _px(cr, 14, 10, tooth)       # teeth
		_:
			# Fallback (and any future role): the grunt baseline so it still reads.
			_rect(cr, 0, 8, 3, 2, bd)
			_rect(cr, 2, 7, 9, 4, body)
			_disc(cr, 3, 9, 2, body)
			_rect(cr, 10, 8, 6, 2, body)
			_hline(cr, 10, 2, 9, belly)
			_px(cr, 7, 5, ceye)
			_px(cr, 12, 10, tooth); _px(cr, 14, 10, tooth)
	_outline(cr, body.darkened(0.55))
	return cr


# Flanker (yellow) shares the "melee" role with the green grunt but must read as
# its own, smaller/spikier silhouette -- so it gets a dedicated baker keyed off
# the type, called only for "yellow" in the croc bake loop.
func _bake_croc_flanker_img(body: Color, belly: Color) -> Image:
	var bd := body.darkened(0.35)
	var ceye := Color(0.95, 0.86, 0.30)
	var tooth := Color(0.96, 0.96, 0.90)
	var cr := _img16()
	_rect(cr, 0, 9, 3, 2, bd)                                # tail
	_rect(cr, 3, 8, 7, 3, body)                              # smaller body, back raised
	_disc(cr, 3, 9, 1, body)
	_tri(cr, 4, 8, 6, 8, 5, 5, bd)                           # 3 dorsal spikes
	_tri(cr, 6, 8, 8, 8, 7, 5, bd)
	_tri(cr, 8, 8, 10, 8, 9, 5, bd)
	_tri(cr, 10, 9, 15, 10, 11, 12, body)                   # long thin head-down snout
	_hline(cr, 11, 3, 9, belly)
	_px(cr, 9, 7, ceye)                                     # eye
	_px(cr, 13, 11, tooth)                                  # tooth
	_outline(cr, body.darkened(0.55))
	return cr


# Mother Tree tile keyed to its tier (§5): canopy brightens GREEN and grows by a
# pixel per tier (inverted valence vs. the menacing Den -- the Tree growing is
# good). Re-bakable, so a tier-up swaps the tile in place. Trunk uses TREE_BARK.
func _bake_mother_tree_tile(tier: int) -> void:
	var t := clampi(tier, 1, 5)
	var leaf: Color = TREE_LEAF_TIERS[t - 1]
	var leaf_d := leaf.darkened(0.3)
	var leaf_l := leaf.lightened(0.3)
	var grass := Color(0.42, 0.60, 0.31)
	var grass_d := Color(0.35, 0.52, 0.26)
	var grass_l := Color(0.50, 0.69, 0.37)
	var mt := _img16(); mt.fill(grass); _speckle(mt, grass_d, grass_l, 38)
	var cr := 5 + t           # canopy grows +1px per tier (radius 6 -> 10)
	_disc(mt, 8, 7, mini(7, cr), leaf_d)
	_disc(mt, 5, 6, maxi(2, cr - 3), leaf)
	_disc(mt, 11, 5, maxi(2, cr - 3), leaf)
	_rect(mt, 6, 8, 4, 7, TREE_BARK); _vline(mt, 8, 8, 14, TREE_BARK.darkened(0.25))  # trunk
	_px(mt, 7, 5, leaf_l); _px(mt, 10, 8, leaf_l)
	_tiles[Terrain.MOTHER_TREE] = _mktex(mt)


# Swap the Mother Tree tile to its current tier's art (called on tier change).
# The tile is shared across the footprint, so one rebake updates the whole tree.
func _rebake_mother_tree() -> void:
	_bake_mother_tree_tile(_tree_tier)
	queue_redraw()


# White silhouette of a sprite (same alpha) -- used for hit flashes.
func _whiteout(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var out := _img(w)
	for y in range(h):
		for x in range(w):
			var px := im.get_pixel(x, y)
			if px.a > 0.0:
				out.set_pixel(x, y, Color(1, 1, 1, px.a))
	return out


# The item-icon family tint for a kind (falls back to a neutral grey so a future
# item without a mapping still bakes something legible). The bake leans on this
# both for the icon base color and (at runtime) for the slot border.
func _item_tint(kind: String) -> Color:
	return ITEM_CATEGORY_TINT.get(kind, Color("#8B8F99"))


# One distinct, legible 24px icon per INV_ORDER id. Shape is the identifier,
# the category tint is the family (see ITEM_CATEGORY_TINT). Every icon gets a
# 1px keyline (_outline) + a light/shadow pixel pair for cheap volume. Replaces
# the old HSV-by-index disc hack -- two items now never rely on hue alone.
func _bake_item_icons() -> void:
	_item_icons.clear()
	for i in range(INV_ORDER.size()):
		var kind: String = INV_ORDER[i]
		var im := _img(24)
		var base := _item_tint(kind)
		var dk := base.darkened(0.4)
		var lt := base.lightened(0.4)
		_bake_one_item_icon(im, kind, base, dk, lt)
		# Cheap volume: a light pixel top-left of mass, a shadow pixel bottom-right.
		if im.get_pixel(8, 8).a > 0.0:
			im.set_pixel(8, 8, lt)
		if im.get_pixel(15, 15).a > 0.0:
			im.set_pixel(15, 15, dk)
		# Keyline last so the silhouette pops at slot size and on dark panels.
		_outline(im, base.darkened(0.55))
		_item_icons[kind] = _mktex(im)


# Per-id silhouette painter (24x24, subject ~ center 18x18, 3px margin). Grouped
# by INV_ORDER family; the per-item distinguisher is the SHAPE, never the hue.
func _bake_one_item_icon(im: Image, kind: String, base: Color, dk: Color, lt: Color) -> void:
	match kind:
		# --- Wood / plant (vertical log) -------------------------------------
		"wood":
			_rect(im, 9, 4, 6, 16, base); _vline(im, 9, 4, 19, dk)
			_px(im, 11, 8, dk); _px(im, 12, 14, dk)   # rings
		"bamboo":
			_rect(im, 9, 3, 5, 18, CAT_ORGANIC); _vline(im, 9, 3, 20, CAT_ORGANIC.darkened(0.4))
			_hline(im, 9, 9, 13, CAT_ORGANIC.darkened(0.5))
			_hline(im, 15, 9, 13, CAT_ORGANIC.darkened(0.5))   # segments
		"charcoal":
			var coal := Color("#2A2A2A")
			_rect(im, 8, 6, 8, 13, coal); _rect(im, 10, 4, 4, 4, coal)
			_px(im, 11, 12, DEN_EMBER); _px(im, 13, 15, DEN_EMBER.darkened(0.3))   # embers
		"wooden_rod":
			_rect(im, 10, 3, 4, 18, base.lightened(0.15)); _vline(im, 10, 3, 20, dk)
		# --- Raw mineral (irregular chunk) -----------------------------------
		"stone":
			_disc(im, 9, 12, 4, base); _disc(im, 14, 11, 4, base); _disc(im, 12, 15, 3, base)
			_hline(im, 18, 6, 17, dk)   # flat bottom
		"sand":
			for s in [Vector2i(7, 14), Vector2i(9, 11), Vector2i(11, 15), Vector2i(13, 12),
					Vector2i(15, 16), Vector2i(8, 17), Vector2i(12, 9), Vector2i(16, 13),
					Vector2i(10, 17), Vector2i(14, 10), Vector2i(6, 12), Vector2i(17, 15)]:
				_px(im, s.x, s.y, base); _px(im, s.x + 1, s.y, lt)
		"scrap":
			_rect(im, 7, 8, 11, 9, base); _tri(im, 14, 8, 18, 8, 18, 13, Color(0, 0, 0, 0))  # notch
			_px(im, 9, 10, dk); _px(im, 12, 14, dk); _px(im, 15, 11, lt)   # jagged scratches
		"metal_ore":
			_disc(im, 10, 12, 4, base); _disc(im, 14, 13, 4, base)
			_hline(im, 10, 8, 12, CAT_METAL.lightened(0.2)); _hline(im, 14, 11, 16, CAT_METAL.lightened(0.2))  # ore veins
		# --- Refined metal (tight bar) ---------------------------------------
		"metal":
			_rect(im, 6, 11, 13, 6, base); _tri(im, 6, 11, 19, 11, 16, 7, base); _tri(im, 6, 11, 16, 7, 9, 7, base)
			_hline(im, 11, 6, 18, lt)   # top sheen
		"nails":
			_vline(im, 9, 6, 19, base); _vline(im, 14, 8, 19, base)
			_disc(im, 9, 6, 2, lt); _disc(im, 14, 8, 2, lt)   # heads
		"casing":
			_rect(im, 9, 8, 6, 11, base); _hline(im, 8, 8, 15, lt); _hline(im, 18, 8, 15, dk)  # rim + base
			_vline(im, 10, 9, 17, lt)
		"gunpowder":
			_rect(im, 7, 9, 10, 10, dk); _hline(im, 9, 7, 16, base); _hline(im, 18, 7, 16, base)  # keg bands
			_vline(im, 12, 4, 9, CAT_WOOD); _px(im, 12, 3, UI_WARN)   # fuse + spark
		# --- Fiber (thin strands) --------------------------------------------
		"grass":
			_vline(im, 8, 6, 19, base); _vline(im, 12, 4, 19, base); _vline(im, 16, 7, 19, base)
			_px(im, 7, 7, lt); _px(im, 11, 5, lt); _px(im, 17, 8, lt)   # splayed blade tips
		"string":
			for y in range(5, 20):
				_px(im, 11 + (1 if (y / 2) % 2 == 0 else -1), y, base)   # single wavy strand
		"rope":
			for y in range(5, 20):
				var j := 1 if (y / 2) % 2 == 0 else -1
				_px(im, 10 + j, y, base); _px(im, 13 - j, y, dk)   # two twisted strands
		"glue":
			_disc(im, 11, 11, 5, base); _vline(im, 11, 14, 19, base)   # blob + drip
			_px(im, 9, 9, lt); _px(im, 11, 20, base.lightened(0.2))
		# --- Seed / soil -----------------------------------------------------
		"seed":
			_disc(im, 11, 13, 4, base); _tri(im, 8, 8, 14, 8, 11, 13, base)   # teardrop
		"fertilizer":
			_disc(im, 9, 11, 3, base); _disc(im, 14, 13, 3, base); _disc(im, 11, 16, 3, base)  # pellets
		"worm":
			_disc(im, 8, 9, 2, CAT_CREATURE); _disc(im, 11, 12, 2, CAT_CREATURE)
			_disc(im, 14, 11, 2, CAT_CREATURE); _disc(im, 16, 14, 2, CAT_CREATURE)   # S-curve
		"beeswax":
			_disc(im, 11, 12, 5, base); _px(im, 9, 10, lt); _hline(im, 12, 8, 14, dk)  # honeycomb block
		# --- Fruit / food ----------------------------------------------------
		"banana":
			_tri(im, 6, 7, 9, 5, 17, 16, CAT_FOOD); _tri(im, 6, 7, 17, 16, 8, 12, CAT_FOOD)
			_disc(im, 13, 12, 4, CAT_FOOD); _px(im, 6, 7, dk); _px(im, 16, 16, dk)   # crescent
		"berry":
			_disc(im, 9, 12, 3, Color("#9C3C8C")); _disc(im, 14, 11, 3, Color("#9C3C8C"))
			_disc(im, 12, 15, 3, Color("#9C3C8C")); _px(im, 8, 10, lt)   # cluster
		"coconut":
			_disc(im, 12, 12, 6, CAT_WOOD.darkened(0.2))
			_px(im, 10, 10, Color("#2A1C10")); _px(im, 13, 10, Color("#2A1C10")); _px(im, 11, 13, Color("#2A1C10"))  # 3 eyes
		"honey":
			_disc(im, 11, 11, 5, CAT_FOOD); _vline(im, 11, 14, 20, CAT_FOOD.darkened(0.2))
			_px(im, 9, 9, lt)   # amber drip
		# --- Fish / bone -----------------------------------------------------
		"fish_m":
			_disc(im, 11, 12, 4, base); _tri(im, 15, 12, 19, 8, 19, 16, base)   # body + tail
			_hline(im, 14, 7, 13, base.lightened(0.25)); _px(im, 8, 11, Color.WHITE)  # belly + eye
		"fish_f":
			_disc(im, 11, 12, 4, base.lightened(0.1)); _tri(im, 15, 12, 19, 8, 19, 16, base)
			_hline(im, 13, 7, 13, base.lightened(0.35)); _px(im, 13, 8, base)  # fin
			_px(im, 8, 11, Color.WHITE)
		"fish_bones":
			_vline(im, 11, 5, 19, base)
			for y in [7, 10, 13, 16]:
				_hline(im, y, 8, 14, base)   # ribs off the spine
			_disc(im, 11, 5, 2, base)   # skull
		"fish_skewer":
			_vline(im, 11, 3, 21, CAT_WOOD); _disc(im, 11, 7, 3, CAT_FOOD)
			_disc(im, 11, 12, 3, CAT_FOOD); _disc(im, 11, 17, 3, CAT_FOOD)   # 3 on a rod
		"cooked_skewer":
			_vline(im, 11, 3, 21, CAT_WOOD); _disc(im, 11, 7, 3, CAT_FOOD.darkened(0.25))
			_disc(im, 11, 12, 3, CAT_FOOD.darkened(0.25)); _disc(im, 11, 17, 3, CAT_FOOD.darkened(0.25))
			_px(im, 10, 6, Color("#3A2A1A")); _px(im, 12, 16, Color("#3A2A1A"))   # char marks
		# --- Cups / fluid (trapezoid vessel) ---------------------------------
		"cup", "cup_water", "cup_juice", "cup_wine", "cup_oil":
			_tri(im, 7, 6, 17, 6, 15, 19, CAT_FLUID.lightened(0.25))
			_tri(im, 7, 6, 15, 19, 9, 19, CAT_FLUID.lightened(0.25))
			_outline(im, CAT_FLUID.darkened(0.3))   # glass rim outline before fill
			var fill := Color(0, 0, 0, 0)
			match kind:
				"cup_water": fill = Color("#4FB0D8")
				"cup_juice": fill = Color("#C84848")
				"cup_wine": fill = Color("#7A2E5A")
				"cup_oil": fill = Color("#D89A3C")
			if fill.a > 0.0:
				_tri(im, 9, 11, 15, 11, 14, 18, fill); _tri(im, 9, 11, 14, 18, 10, 18, fill)
				if kind == "cup_wine":
					_hline(im, 11, 9, 14, Color("#C46A9A"))   # foam line
				if kind == "cup_oil":
					_px(im, 11, 13, lt)   # sheen
			else:
				_px(im, 9, 8, Color.WHITE)   # empty cup glint
		"glass_jar":
			_rect(im, 8, 8, 8, 11, CAT_FLUID.lightened(0.3)); _disc(im, 11, 8, 4, CAT_FLUID.lightened(0.3))
			_hline(im, 5, 8, 15, CAT_FLUID.darkened(0.2))   # lid
			_outline(im, CAT_FLUID.darkened(0.35))
		"glass":
			_rect(im, 7, 5, 10, 14, CAT_FLUID.lightened(0.35))
			_outline(im, CAT_STONE.darkened(0.2))
			_px(im, 9, 7, Color.WHITE); _px(im, 12, 11, Color.WHITE); _px(im, 14, 15, Color.WHITE)  # diagonal glint
		# --- Tools / weapons (handle + head) ---------------------------------
		"stone_tool":
			_vline(im, 11, 8, 20, CAT_WOOD); _vline(im, 12, 8, 20, CAT_WOOD.darkened(0.2))
			_tri(im, 6, 4, 14, 4, 10, 10, base)   # axe wedge
		"metal_tool":
			_vline(im, 11, 8, 20, CAT_WOOD); _vline(im, 12, 8, 20, CAT_WOOD.darkened(0.2))
			_tri(im, 6, 4, 14, 4, 10, 10, CAT_METAL)
			_px(im, 9, 5, Color.WHITE)
		"slingshot":
			_vline(im, 11, 11, 21, CAT_WOOD); _vline(im, 12, 11, 21, CAT_WOOD.darkened(0.2))
			_tri(im, 5, 3, 11, 11, 9, 11, base); _tri(im, 18, 3, 14, 11, 12, 11, base)   # Y-fork
		"mallet":
			_vline(im, 11, 9, 21, CAT_WOOD); _vline(im, 12, 9, 21, CAT_WOOD.darkened(0.2))
			_rect(im, 6, 4, 11, 6, base)   # fat head
		"spear":
			_vline(im, 11, 8, 21, CAT_WOOD); _vline(im, 12, 8, 21, CAT_WOOD.darkened(0.2))
			_tri(im, 8, 3, 15, 3, 11, 10, base)   # point
		"sling_ammo":
			_disc(im, 9, 11, 3, base); _disc(im, 15, 10, 3, base); _disc(im, 12, 16, 3, base)  # pebbles
		"glapple_lamp":
			_disc(im, 11, 11, 5, Color("#5A9EFF")); _disc(im, 11, 11, 3, Color("#8AC0FF"))
			_rect(im, 9, 16, 6, 4, CAT_METAL)   # lamp base
			_px(im, 9, 8, Color.WHITE)
		"glapple":
			_disc(im, 11, 12, 5, Color("#5A9EFF")); _disc(im, 9, 10, 2, Color("#9EC8FF"))
			_vline(im, 11, 6, 8, CAT_ORGANIC)   # stem
		# --- Creature drops --------------------------------------------------
		"croc_hide":
			_tri(im, 4, 9, 12, 4, 19, 11, base); _tri(im, 4, 9, 19, 11, 11, 18, base)
			_px(im, 8, 8, lt); _px(im, 14, 13, dk)   # stretched skin pentagon
		"bone":
			_rect(im, 9, 8, 6, 9, base)   # shaft
			_disc(im, 9, 7, 2, base); _disc(im, 14, 7, 2, base)
			_disc(im, 9, 17, 2, base); _disc(im, 14, 17, 2, base)   # dogbone knobs
		"bee":
			_disc(im, 11, 13, 4, CAT_FOOD); _hline(im, 11, 8, 14, Color("#1A1A1A")); _hline(im, 14, 8, 14, Color("#1A1A1A"))
			_disc(im, 7, 9, 2, Color("#DDEEFF"))   # wing
		# --- Waste (drooping / dull) -----------------------------------------
		"rot":
			_disc(im, 11, 13, 5, base); _vline(im, 14, 16, 19, base)   # melted
			_px(im, 8, 8, Color("#3A3020"))   # fly
		"ash":
			_disc(im, 11, 16, 5, base); _hline(im, 18, 6, 16, base.darkened(0.2))
			_speckle(im, base.lightened(0.2), base.darkened(0.2), 71)
		"banana_peel":
			_tri(im, 11, 13, 6, 4, 9, 13, base); _tri(im, 11, 13, 12, 3, 14, 13, base)
			_tri(im, 11, 13, 18, 6, 14, 14, base)   # splayed 3-tri star
		"rotten_banana":
			_tri(im, 6, 8, 9, 6, 16, 16, base); _disc(im, 13, 12, 4, base)
			_px(im, 11, 11, Color("#2A2014")); _px(im, 14, 14, Color("#2A2014"))   # spots
		"rotten_berry":
			_disc(im, 9, 12, 3, base); _disc(im, 14, 11, 3, base); _disc(im, 12, 15, 3, base)
			_px(im, 10, 12, Color("#2A2014")); _px(im, 13, 14, Color("#2A2014"))
		"coconut_shell":
			_disc(im, 11, 12, 6, base); _disc_clear(im, 16, 8, 3)   # cracked bite
			_px(im, 9, 9, lt)
		_:
			# Fallback for any unmapped id: a chunky disc + volume so it still reads.
			_disc(im, 11, 12, 6, base)
			_px(im, 9, 9, lt); _px(im, 14, 15, dk)


# -----------------------------------------------------------------------------
# Dev affordance: `--selftest` exercises the logic and quits.
# -----------------------------------------------------------------------------
func _inv_flow_mark(flow: Dictionary, kind: String, why: String) -> void:
	if not (kind in INV_ORDER):
		return
	if not flow.has(kind):
		flow[kind] = []
	(flow[kind] as Array).append(why)


func _inventory_flow_evidence() -> Dictionary:
	var produced := {}
	var consumed := {}

	for key in CRAFT_RECIPES:
		var r: Dictionary = CRAFT_RECIPES[key]
		var out := String(r.get("out", ""))
		if out != "":
			_inv_flow_mark(produced, out, "craft:%s" % key)
		var cost: Dictionary = r.get("cost", {})
		for kind in cost:
			_inv_flow_mark(consumed, String(kind), "craft:%s" % key)
		if int(r.get("rot", 0)) > 0:
			for kind in ["rotten_banana", "rotten_berry", "rot"]:
				_inv_flow_mark(consumed, kind, "craft:%s" % key)
		if int(r.get("fish", 0)) > 0:
			_inv_flow_mark(consumed, "fish_m", "craft:%s" % key)
			_inv_flow_mark(consumed, "fish_f", "craft:%s" % key)

	for key in STRUCTURES:
		var s: Dictionary = STRUCTURES[key]
		var cost: Dictionary = s.get("cost", {})
		for kind in cost:
			_inv_flow_mark(consumed, String(kind), "build:%s" % key)

	for fresh in PERISHABLE:
		_inv_flow_mark(produced, String(PERISHABLE[fresh]), "spoil:%s" % fresh)
	for kind in DRINKS:
		_inv_flow_mark(consumed, String(kind), "drink:%s" % kind)
	_inv_flow_mark(produced, "cup", "drink/empty returns cup")

	for kind in FP_SAP_CONVERSION:
		_inv_flow_mark(consumed, String(kind), "Mother Tree Sap deposit")

	var manual_producers := {
		"wood": ["tree harvest"], "stone": ["stone harvest", "auto-miner"],
		"grass": ["grass harvest"], "seed": ["berry bush harvest"], "bamboo": ["bamboo harvest"],
		"metal_ore": ["rock ore drop", "auto-miner"], "coconut": ["palm harvest"],
		"coconut_shell": ["eat coconut"], "glapple": ["glapple tree"],
		"sand": ["beach harvest"], "metal": ["kiln ore", "scrap craft"],
		"charcoal": ["kiln wood"], "scrap": ["croc drop"], "casing": ["dawn casing sweep"],
		"glass": ["kiln sand"], "worm": ["jarred wild worm", "worm farm take"],
		"bee": ["jarred wild bee"], "honey": ["wild hive", "bee enclosure"],
		"beeswax": ["bee enclosure"], "fertilizer": ["worm compost", "bone meal"],
		"croc_hide": ["croc drop"], "bone": ["croc drop"], "fish_m": ["pool catch", "aquarium"],
		"fish_f": ["pool catch", "aquarium"], "fish_bones": ["eat fish"],
		"cooked_skewer": ["campfire cook"], "ash": ["burnt skewer"], "glue": ["spoiled fruit craft"],
		"banana": ["tree fruit"], "berry": ["bush/planter harvest"], "banana_peel": ["eat banana"],
		"cup_water": ["fill cup"], "cup_juice": ["juicer"], "cup_wine": ["barrel ferment"],
		"cup_oil": ["still"],
	}
	for kind in manual_producers:
		for why in manual_producers[kind]:
			_inv_flow_mark(produced, kind, String(why))

	var manual_consumers := {
		"stone_tool": ["equip/use"], "metal_tool": ["equip/use"], "slingshot": ["equip/use"],
		"mallet": ["equip/use"], "spear": ["equip/use"], "sling_ammo": ["slingshot shot"],
		"glapple_lamp": ["place lamp"], "cup": ["fill from pool/juicer/barrel"],
		"coconut": ["eat"], "banana": ["eat"], "berry": ["eat/juice"], "cooked_skewer": ["eat"],
		"coconut_shell": ["discard waste"], "fish_m": ["eat/cook/aquarium"],
		"fish_f": ["eat/cook/aquarium"], "fish_skewer": ["campfire cook"],
		"fish_bones": ["discard waste"], "ash": ["discard waste"], "glass_jar": ["catch critter"],
		"seed": ["planter"], "sand": ["kiln glass"], "worm": ["farm/aquarium feed"],
		"bee": ["bee enclosure"], "honey": ["Mother Tree Sap deposit"], "fertilizer": ["planter boost"],
		"banana_peel": ["peel launcher"], "cup_water": ["drink/barrel/aquarium"],
		"cup_juice": ["drink/barrel/still/spoil"], "cup_wine": ["drink/turret fuel"],
		"cup_oil": ["generator fuel"], "gunpowder": ["turret reload/auto-loader"],
		"scrap": ["scrap metal craft"],
	}
	for kind in manual_consumers:
		for why in manual_consumers[kind]:
			_inv_flow_mark(consumed, kind, String(why))

	return {"produced": produced, "consumed": consumed}


func _pathing_probe_result(seed_count: int = 20, crocs_per_seed: int = 20) -> Dictionary:
	var total := 0
	var reached := 0
	var stuck := 0
	var steps := 700
	var dt := 0.05
	var saved_seed := _seed
	var saved_monsters := _monsters
	var saved_cell := _cell
	_monsters = []

	for si in range(seed_count):
		_seed = WORLD_SEED + si
		seed(_seed)
		_generate_world()
		_ensure_flow_fields()
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + 99173
		for _ci in range(crocs_per_seed):
			var start := Vector2i(-1, -1)
			var tries := 0
			while tries < 900 and start.x < 0:
				tries += 1
				var c := Vector2i(rng.randi_range(0, GRID_CELLS - 1), rng.randi_range(0, GRID_CELLS - 1))
				if _tile_monster_walk(_terrain_at(c)) and _chebyshev(c, _tree_center_cell()) >= 18:
					start = c
			if start.x < 0:
				continue
			total += 1
			var start_pos := _cell_center_world(start)
			var m := {
				"pos": start_pos, "slow_t": 0.0, "brk_cd": 0.0,
			}
			var hit_tree := false
			for _step in range(steps):
				var pos: Vector2 = m["pos"]
				if pos.distance_to(_cell_center_world(_nearest_tree_cell_to(pos))) <= CELL_SIZE * 1.6:
					hit_tree = true
					break
				var fallback := _cell_center_world(_nearest_tree_cell_to(pos)) - pos
				var dir := _flow_dir_from_pos(_field_tree, pos, fallback)
				_move_monster_toward(m, dir, dt, CROC_SPEED)
			if hit_tree:
				reached += 1
			elif (m["pos"] as Vector2).distance_to(start_pos) < CELL_SIZE * 0.5:
				stuck += 1

	_seed = saved_seed
	_cell = saved_cell
	_monsters = saved_monsters
	_generate_world()
	_ensure_flow_fields()
	return {"seeds": seed_count, "crocs": total, "reached": reached, "stuck": stuck}


func _run_pathing_probe() -> void:
	var r := _pathing_probe_result(20, 20)
	print("PATHING_PROBE seeds=%d crocs=%d reached_tree=%d stuck_whole_run=%d" % [
		int(r["seeds"]), int(r["crocs"]), int(r["reached"]), int(r["stuck"]),
	])
	get_tree().quit(0)


func _run_selftest() -> void:
	var fails := 0

	var tree := Vector2i(-1, -1)
	var stone := Vector2i(-1, -1)
	var water := Vector2i(-1, -1)
	for y in range(GRID_CELLS):
		for x in range(GRID_CELLS):
			var c := Vector2i(x, y)
			if tree.x < 0 and _terrain_at(c) == Terrain.TREE:
				tree = c
			if stone.x < 0 and _terrain_at(c) == Terrain.STONE:
				stone = c
			if water.x < 0 and _terrain_at(c) == Terrain.WATER:
				water = c

	var ok_world := _terrain.size() == GRID_CELLS * GRID_CELLS
	_report("world sized", ok_world); fails += int(not ok_world)

	var ok_tile_defs := true
	var ok_no_silent_block := true
	for tid in Terrain.values():
		if not TILE_DEF.has(tid):
			ok_tile_defs = false
			continue
		var td: Dictionary = TILE_DEF[tid]
		var blocks_monster := not bool(td.get("monster_walk", false))
		if blocks_monster and int(td.get("break_hp", 0)) <= 0 and not bool(td.get("impassable", false)):
			ok_no_silent_block = false
	_report("every Terrain has TILE_DEF", ok_tile_defs); fails += int(not ok_tile_defs)
	_report("no monster-blocking tile lacks break_hp/impassable", ok_no_silent_block); fails += int(not ok_no_silent_block)

	# INVARIANT: pather-walkability and collider-walkability must AGREE for every
	# Terrain at the real monster/player radius. The old test used a zero-size body,
	# which missed radius-vs-cell-corner stalls.
	var ok_walk_agree := true
	var pc := Vector2i(20, 20)
	var pcen := _cell_center_world(pc)
	var pc_orig := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var rc := pc + Vector2i(dx, dy)
			pc_orig[_cell_index(rc)] = _terrain_at(rc)
			_set_terrain(rc, Terrain.GRASS)
	for tid in Terrain.values():
		_set_terrain(pc, tid)
		# Pather: cost 1 means freely walkable (no break/impassable involved).
		var pather_walk := _flow_step_cost(pc) == 1
		# Collider: real-sized bodies at the cell centre must agree with TILE_DEF.
		var coll_monster := not _box_blocked(pcen, MONSTER_RADIUS, true)
		var coll_player := not _box_blocked(pcen, PLAYER_RADIUS, false)
		if pather_walk != _tile_monster_walk(tid):
			ok_walk_agree = false
		if coll_monster != _tile_monster_walk(tid):
			ok_walk_agree = false
		if coll_player != _tile_player_walk(tid):
			ok_walk_agree = false
	for idx in pc_orig:
		_terrain[idx] = pc_orig[idx]
	_report("pather and collider walkability agree", ok_walk_agree); fails += int(not ok_walk_agree)

	var corner_patch := {}
	for y in range(28, 33):
		for x in range(28, 33):
			var cc := Vector2i(x, y)
			corner_patch[_cell_index(cc)] = _terrain_at(cc)
			_set_terrain(cc, Terrain.GRASS)
	_set_terrain(Vector2i(31, 30), Terrain.TREE)
	var corner_start := _cell_center_world(Vector2i(30, 30))
	var corner_croc := {"pos": corner_start, "slow_t": 0.0, "brk_cd": 0.0}
	for _corner_i in range(12):
		_move_monster_toward(corner_croc, Vector2.RIGHT, 0.08, CROC_SPEED)
	var ok_corner_progress := (corner_croc["pos"] as Vector2).distance_to(corner_start) > CELL_SIZE * 0.25
	for idx in corner_patch:
		_terrain[idx] = corner_patch[idx]
	_report("radius croc makes progress at obstacle corner", ok_corner_progress); fails += int(not ok_corner_progress)

	var ok_icons := true
	for item_id in INV_ORDER:
		if not _item_icons.has(item_id):
			ok_icons = false
			break
	_report("every inventory item has a crude icon hook", ok_icons); fails += int(not ok_icons)
	var ok_theme: bool = _ui_theme != null and _stat_line("sniper") != ""
	_report("Theme + stat-line hooks exist", ok_theme); fails += int(not ok_theme)

	# --- INVARIANT: the programmatic Theme is a real identity, not a stub. Proves
	# _apply_theme populated font sizes + the slot/card/button StyleBoxFlats + the
	# palette font colors at the type level, so the whole UI cascades one identity.
	# Trips if a future editor reverts _apply_theme to the placeholder font-size hook.
	var ok_theme_identity := _ui_theme != null
	if ok_theme_identity:
		var t := _ui_theme
		# Font sizes set for the core types.
		ok_theme_identity = ok_theme_identity \
			and t.has_font_size("font_size", "Label") and t.get_font_size("font_size", "Label") == FS_BODY \
			and t.has_font_size("font_size", "Button") and t.get_font_size("font_size", "Button") == FS_BUTTON
		# Button carries all four interaction-state boxes plus focus.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			ok_theme_identity = ok_theme_identity and t.has_stylebox(state, "Button") \
				and t.get_stylebox(state, "Button") is StyleBoxFlat
		# Cards + bars + separator are styled.
		ok_theme_identity = ok_theme_identity \
			and t.has_stylebox("panel", "PanelContainer") \
			and t.has_stylebox("background", "ProgressBar") and t.has_stylebox("fill", "ProgressBar") \
			and t.has_stylebox("separator", "HSeparator")
		# Identity text color is the brief's UI_TEXT, and the pressed-button accent is gold.
		ok_theme_identity = ok_theme_identity \
			and t.has_color("font_color", "Label") and t.get_color("font_color", "Label") == UI_TEXT \
			and t.has_color("font_pressed_color", "Button") and t.get_color("font_pressed_color", "Button") == UI_ACCENT
	_report("Theme is a populated visual identity (fonts+styleboxes+palette)", ok_theme_identity)
	fails += int(not ok_theme_identity)

	# --- INVARIANT: every def family has the desc/category content the tooltip reads.
	# This proves the desc/legibility layer is COMPLETE (no silent missing flavor),
	# matching the icon-hook assert one block up. A new item without a desc/band, or
	# a new turret/struct/croc/weapon without a desc, trips the harness here.
	var ok_item_desc := true
	var ok_item_band := true
	var missing_desc := []
	var missing_band := []
	for item_id in INV_ORDER:
		if not ITEM_DESC.has(item_id) or String(ITEM_DESC[item_id]).is_empty():
			ok_item_desc = false; missing_desc.append(item_id)
		if not INV_CATEGORY.has(item_id) or not (String(INV_CATEGORY[item_id]) in INV_BAND_ORDER):
			ok_item_band = false; missing_band.append(item_id)
	if not missing_desc.is_empty():
		push_warning("INV_ORDER missing ITEM_DESC: %s" % str(missing_desc))
	if not missing_band.is_empty():
		push_warning("INV_ORDER missing INV_CATEGORY band: %s" % str(missing_band))
	_report("every inventory item has a desc string", ok_item_desc); fails += int(not ok_item_desc)
	_report("every inventory item maps to a category band", ok_item_band); fails += int(not ok_item_band)

	var ok_def_desc := true
	var no_desc := []
	for k in TURRET_DEFS:
		if String(TURRET_DEFS[k].get("desc", "")).is_empty():
			ok_def_desc = false; no_desc.append("turret:" + k)
	for k in STRUCTURES:
		if String(STRUCTURES[k].get("desc", "")).is_empty():
			ok_def_desc = false; no_desc.append("struct:" + k)
	for k in CROC_DEFS:
		if String(CROC_DEFS[k].get("desc", "")).is_empty():
			ok_def_desc = false; no_desc.append("croc:" + k)
	for k in WEAPON_DEFS:
		if String(WEAPON_DEFS[k].get("desc", "")).is_empty():
			ok_def_desc = false; no_desc.append("weapon:" + k)
	if not no_desc.is_empty():
		push_warning("def families missing desc: %s" % str(no_desc))
	_report("every turret/struct/croc/weapon def has a desc", ok_def_desc); fails += int(not ok_def_desc)

	# --- INVARIANT: the generalized tooltip stat-line dispatches per family and the
	# frame is built. This proves _stat_line was actually generalized (part 2), not
	# just left turret-only: each family must yield a non-empty computed line for a
	# representative member, and the tooltip root nodes must exist.
	var ok_stat_dispatch: bool = \
		_tooltip_stat_line("sniper", "turret").contains("Dmg") \
		and _tooltip_stat_line("spear", "weapon").contains("Reach") \
		and _tooltip_stat_line("stone_wall", "struct").contains("HP") \
		and _tooltip_stat_line("green", "croc").contains("HP") \
		and _tooltip_stat_line("banana", "item").contains("hunger") \
		and _tooltip_stat_line("stone_tool", "item").contains("+1 gather") \
		and _tooltip_stat_line("gunpowder", "item").contains("shot") \
		and _tooltip_stat_line("wood", "item") == ""   # plain materials carry no stat row
	_report("tooltip stat-line dispatches across all def families", ok_stat_dispatch)
	fails += int(not ok_stat_dispatch)
	var ok_remediation_beats: bool = "tier_locked" in ONBOARD_BEATS and "first_vein" in ONBOARD_BEATS \
		and _tooltip_desc("bare_grass", "special").contains("Click bare grass") \
		and _tooltip_desc("mother_tree_hub", "special").contains("Open Tree hub") \
		and String(ITEM_DESC["stone_tool"]).contains("+1 yield") \
		and String(ITEM_DESC["metal_tool"]).contains("+2 yield")
	_report("remediation onboarding/tooltips are wired", ok_remediation_beats)
	fails += int(not ok_remediation_beats)
	# The turret counter hint must read the matrix (physical strong vs swarms).
	var ok_counter_hint: bool = _turret_counter_hint("physical").contains("swarm") \
		and _turret_counter_hint("ranged").contains("armored")
	_report("turret tooltip counter hint reads the matrix", ok_counter_hint)
	fails += int(not ok_counter_hint)
	# The tooltip frame must be constructed (root panel + the desc/name labels), and
	# filling it from a def must populate the visible name/desc rows.
	_refresh_tooltip_content("sniper", "turret")
	var ok_tooltip_frame: bool = _tooltip_panel != null and _tt_name != null and _tt_desc != null \
		and _tt_name.text == String(TURRET_DEFS["sniper"]["label"]) \
		and not _tt_desc.text.is_empty()
	_report("tooltip frame builds + fills from a def", ok_tooltip_frame)
	fails += int(not ok_tooltip_frame)
	_hide_tooltip()

	# --- INVARIANT: legibility draw layer (HP bars / ammo readout / build ghost) ---
	# These exercise the *gating logic* behind the three new draw cues so a future
	# edit that breaks the "only show when it matters" contract trips the harness,
	# not just a missing-method check.

	# (1) Croc HP bar: hidden at full health, shown once wounded. We assert the exact
	# fraction gate the draw uses (frac >= 0.999 -> no bar) against a built monster.
	var croc_full := _croc_for_night(Vector2.ZERO, 1, "green")
	var croc_full_frac := float(croc_full["hp"]) / maxf(1.0, float(croc_full["max_hp"]))
	var croc_hurt := _croc_for_night(Vector2.ZERO, 1, "green")
	croc_hurt["hp"] = float(croc_hurt["max_hp"]) * 0.4
	var croc_hurt_frac := float(croc_hurt["hp"]) / maxf(1.0, float(croc_hurt["max_hp"]))
	var ok_croc_bar: bool = has_method("_draw_croc_hp_bar") \
		and croc_full_frac >= 0.999 and croc_hurt_frac < 0.999 \
		and float(croc_full["max_hp"]) > 0.0
	_report("croc HP bar gates on damage (full hidden, wounded shown)", ok_croc_bar)
	fails += int(not ok_croc_bar)

	# (2) Equipped-weapon ammo readout: only the slingshot draws it, and only at
	# night or when crocs are present (no day clutter). Assert the gate truth table.
	var saved_weap := _weapon_equipped
	var saved_night := _is_night
	var saved_mons := _monsters
	_monsters = []
	_weapon_equipped = "slingshot"; _is_night = false
	var ammo_hidden_day: bool = not (_weapon_equipped == "slingshot" and (_is_night or not _monsters.is_empty()))
	_is_night = true
	var ammo_shown_night: bool = (_weapon_equipped == "slingshot" and (_is_night or not _monsters.is_empty()))
	_weapon_equipped = "spear"; _is_night = true
	var ammo_hidden_melee: bool = not (_weapon_equipped == "slingshot" and (_is_night or not _monsters.is_empty()))
	var ok_ammo_readout: bool = has_method("_draw_weapon_ammo_readout") \
		and ammo_hidden_day and ammo_shown_night and ammo_hidden_melee
	_report("weapon ammo readout shows only for ranged when it matters", ok_ammo_readout)
	fails += int(not ok_ammo_readout)
	_weapon_equipped = saved_weap; _is_night = saved_night; _monsters = saved_mons

	# (3) Build ghost: the OK/blocked colour comes from _build_placement_ok, which
	# must agree with whether a real placement at that cell would actually land.
	# Find a clear grass cell, prove valid+afford vs blocked vs unaffordable.
	var grass_c := Vector2i(-1, -1)
	for gy in range(GRID_CELLS):
		for gx in range(GRID_CELLS):
			var gc := Vector2i(gx, gy)
			if _terrain_at(gc) == Terrain.GRASS and gc != _cell and _monster_at(gc) == -1:
				grass_c = gc
				break
		if grass_c.x >= 0:
			break
	var saved_struct := _build_struct
	var saved_res := _resources.duplicate(true)
	_build_struct = "wood_wall"
	_resources = _default_inventory()
	for k in STRUCTURES["wood_wall"]["cost"]:
		_resources[k] = int(STRUCTURES["wood_wall"]["cost"][k]) + 5
	var ghost_ok_on_grass: bool = grass_c.x >= 0 and _build_placement_ok(grass_c)
	# A non-grass / out-of-bounds cell is never a valid spot.
	var ghost_blocked_oob: bool = not _build_placement_valid_spot(Vector2i(-1, -1))
	# Strip the wallet: spot stays valid, but _build_placement_ok flips to false
	# (this is exactly the cost-pip branch in the ghost draw).
	for k in STRUCTURES["wood_wall"]["cost"]:
		_resources[k] = 0
	var ghost_spot_valid_unaffordable: bool = grass_c.x < 0 or (_build_placement_valid_spot(grass_c) and not _build_placement_ok(grass_c))
	var ok_build_ghost: bool = has_method("_draw_build_ghost") \
		and ghost_ok_on_grass and ghost_blocked_oob and ghost_spot_valid_unaffordable
	_report("build ghost legality matches real placement gates", ok_build_ghost)
	fails += int(not ok_build_ghost)
	_build_struct = saved_struct
	_resources = saved_res

	var flow := _inventory_flow_evidence()
	var produced: Dictionary = flow["produced"]
	var consumed: Dictionary = flow["consumed"]
	var missing_producers := []
	var missing_consumers := []
	for item_id in INV_ORDER:
		if not produced.has(item_id):
			missing_producers.append(item_id)
		if not consumed.has(item_id):
			missing_consumers.append(item_id)
	if not missing_producers.is_empty():
		push_warning("INV_ORDER missing producers: %s" % str(missing_producers))
	if not missing_consumers.is_empty():
		push_warning("INV_ORDER missing consumers: %s" % str(missing_consumers))
	var ok_inventory_flow := missing_producers.is_empty() and missing_consumers.is_empty()
	_report("every inventory item has a producer and consumer", ok_inventory_flow); fails += int(not ok_inventory_flow)

	_cell = tree + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = tree + Vector2i(1, 0)
	_banana[_cell_index(tree)] = 1
	var ok_adj: bool = _click_interact(tree)  # adjacent click harvests
	var ok_pick: bool = ok_adj and _resources["banana"] == 1 and _terrain_at(tree) == Terrain.TREE
	_report("click-pick banana -> +banana, tree remains", ok_pick); fails += int(not ok_pick)
	_harvest_cell(tree)
	var ok_chop: bool = _resources["wood"] == 2 and _terrain_at(tree) == Terrain.STUMP
	_report("chop bare tree -> stump", ok_chop); fails += int(not ok_chop)

	_cell = stone + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = stone + Vector2i(1, 0)
	_harvest_cell(stone)
	var ok_stone: bool = _resources["stone"] == 2 and _terrain_at(stone) == Terrain.GRASS
	_report("stone -> +2 stone (finite)", ok_stone); fails += int(not ok_stone)

	# Interact requires adjacency.
	_cell = Vector2i(0, 0)
	var ok_far: bool = not _click_interact(Vector2i(20, 20))
	_report("interact needs adjacency", ok_far); fails += int(not ok_far)

	_resources["banana"] = 1
	_energy = 50.0
	_try_eat()
	var ok_eat: bool = absf(_energy - 80.0) < 0.01 and _resources["banana"] == 0
	_report("eat banana -> +energy", ok_eat); fails += int(not ok_eat)

	# Rotten food can't be eaten.
	_resources = _default_inventory()
	_resources["rotten_banana"] = 2
	_energy = 50.0
	_try_eat()
	var ok_rot: bool = absf(_energy - 50.0) < 0.01 and _resources["rotten_banana"] == 2
	_report("rotten food can't be eaten", ok_rot); fails += int(not ok_rot)

	# Spoilage turns a fresh banana rotten.
	_resources = _default_inventory()
	_resources["banana"] = 1
	_decay_timer = DECAY_INTERVAL
	var spoiled := false
	for _i in range(400):
		_resources["banana"] = 1; _resources["rotten_banana"] = 0
		_decay_timer = DECAY_INTERVAL
		_decay_tick(0.1)
		if _resources["rotten_banana"] == 1 and _resources["banana"] == 0:
			spoiled = true
			break
	_report("food spoils into rotten", spoiled); fails += int(not spoiled)

	var ok_block := water.x >= 0 and not _is_walkable(water)
	_report("water blocks", ok_block); fails += int(not ok_block)

	# Crafting + gating.
	var bench := Vector2i(25, 25)
	var floor_c := Vector2i(26, 25)
	for cc in [bench, floor_c]:
		_set_terrain(cc, Terrain.GRASS)
	_resources = {"wood": 20, "stone": 20, "banana": 0, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_cell = Vector2i(24, 25)

	_build_struct = "floor"
	_drag_action = BuildAction.BUILD
	_apply_build_at(floor_c)
	var ok_locked: bool = _terrain_at(floor_c) == Terrain.GRASS
	_report("floor locked without bench", ok_locked); fails += int(not ok_locked)

	_build_struct = "workbench"
	_apply_build_at(bench)
	var ok_bench: bool = _terrain_at(bench) == Terrain.WORKBENCH and _resources["wood"] == 16 and _resources["stone"] == 18
	_report("workbench builds (4w+2s)", ok_bench); fails += int(not ok_bench)

	_build_struct = "floor"
	_apply_build_at(floor_c)
	var ok_unlock: bool = _terrain_at(floor_c) == Terrain.FLOOR
	_report("floor unlocks by workbench", ok_unlock); fails += int(not ok_unlock)

	# Storage.
	var st_c := Vector2i(24, 26)
	_set_terrain(st_c, Terrain.GRASS)
	_resources = {"wood": 10, "stone": 5, "banana": 3, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_build_struct = "storage"
	_drag_action = BuildAction.BUILD
	_apply_build_at(st_c)
	var sidx := _cell_index(st_c)
	var ok_sbuild: bool = _terrain_at(st_c) == Terrain.STORAGE and _storage.has(sidx) and _resources["wood"] == 7
	_report("storage builds (3 wood)", ok_sbuild); fails += int(not ok_sbuild)
	_deposit_all(sidx)
	var ok_dep: bool = _storage[sidx]["wood"] == 7 and _storage[sidx]["banana"] == 3 and _resources["wood"] == 0
	_report("deposit all", ok_dep); fails += int(not ok_dep)
	_drag_action = BuildAction.DESTROY
	_apply_build_at(st_c)
	var ok_srm: bool = not _storage.has(sidx) and _resources["wood"] == 10 and _resources["banana"] == 3
	_report("remove storage returns contents", ok_srm); fails += int(not ok_srm)

	# --- Night / day cycle ---
	var nt := Vector2i(10, 10)
	var ns := Vector2i(11, 10)
	_set_terrain(nt, Terrain.TREE); _banana[_cell_index(nt)] = 0
	_set_terrain(ns, Terrain.STONE)
	_monsters.clear(); _night_snapshot.clear()
	_cell = Vector2i(30, 30)
	_day = 1
	_begin_night()
	var ok_night: bool = _terrain_at(nt) == Terrain.TREE and _terrain_at(ns) == Terrain.STONE \
		and _monsters.size() == 0 and _night_snapshot.is_empty() and _is_night
	_report("night 1 keeps persistent world and is horde-free", ok_night); fails += int(not ok_night)

	_begin_day()
	var ok_dayb: bool = _terrain_at(nt) == Terrain.TREE and _banana[_cell_index(nt)] == 0 \
		and _terrain_at(ns) == Terrain.STONE and _monsters.size() == 0 and not _is_night
	_report("dawn clears combat without snapshot restore", ok_dayb); fails += int(not ok_dayb)

	# --- Continuous movement / collision ---
	for xx in range(18, 28):
		_set_terrain(Vector2i(xx, 20), Terrain.GRASS)
	var start := _cell_center_world(Vector2i(20, 20))
	var moved := _move_collide(start, Vector2(12, 0), PLAYER_RADIUS, false)
	var ok_free: bool = moved.x > start.x + 1.0
	_report("free movement across open ground", ok_free); fails += int(not ok_free)

	_set_terrain(Vector2i(21, 20), Terrain.WOOD_WALL)
	var blocked := _move_collide(start, Vector2(40, 0), PLAYER_RADIUS, false)
	var ok_wall: bool = absf(blocked.x - start.x) < 0.01   # wall stopped the move
	_report("walls block free movement", ok_wall); fails += int(not ok_wall)

	# A wall with a gap should steer crocs to the gap instead of straight into the wall.
	for y in range(17, 24):
		for x in range(19, 27):
			_set_terrain(Vector2i(x, y), Terrain.GRASS)
	_player_pos = _cell_center_world(Vector2i(20, 20))
	_cell = Vector2i(20, 20)
	for yy in range(18, 22):
		_set_terrain(Vector2i(22, yy), Terrain.STONE_WALL)
	_recompute_player_field(true)
	var detour_dir := _flow_dir_from_cell(_field_player, Vector2i(23, 20))
	var ok_detour: bool = detour_dir.y > 0.25 and absf(detour_dir.x) < 0.25
	_report("flow field detours through wall gap", ok_detour); fails += int(not ok_detour)
	for y in range(17, 24):
		for x in range(19, 27):
			_set_terrain(Vector2i(x, y), Terrain.GRASS)

	# --- Monster behaviour (continuous) ---
	_is_night = true
	# Chase: a monster on open ground closes distance to the player.
	_set_terrain(Vector2i(21, 20), Terrain.GRASS)
	_player_pos = _cell_center_world(Vector2i(20, 20))
	_monsters = [_mk_croc(_cell_center_world(Vector2i(25, 20)), MONSTER_HP)]
	var d0 := _player_pos.distance_to(_monsters[0]["pos"])
	_monster_update(0.1)
	var ok_chase: bool = _player_pos.distance_to(_monsters[0]["pos"]) < d0
	_report("monster chases the player", ok_chase); fails += int(not ok_chase)

	# Blocked by a breakable gate in a long barrier -> chews through it.
	for yy in range(5, 36):
		_set_terrain(Vector2i(21, yy), Terrain.WATER)
	_set_terrain(Vector2i(21, 20), Terrain.WOOD_WALL)
	_struct_hp.clear()
	_monsters = [_mk_croc(_cell_center_world(Vector2i(22, 20)), MONSTER_HP)]
	_monster_update(0.1)
	var widx := _cell_index(Vector2i(21, 20))
	var ok_break: bool = _struct_hp.get(widx, 99) == _tile_break_hp(Terrain.WOOD_WALL) - 1
	_report("monster breaks a blocking wall", ok_break); fails += int(not ok_break)
	for yy in range(5, 36):
		_set_terrain(Vector2i(21, yy), Terrain.GRASS)

	_struct_hp.clear()
	_wrecks.clear()
	_set_terrain(Vector2i(21, 20), Terrain.WOOD_WALL)
	var wood_before := _inv("wood")
	for _wb in range(_tile_break_hp(Terrain.WOOD_WALL)):
		_damage_structure(Vector2i(21, 20))
	var ok_wreck: bool = _terrain_at(Vector2i(21, 20)) == Terrain.WRECK and _wrecks.has(widx) \
		and _tile_monster_walk(Terrain.WRECK) and _inv("wood") == wood_before
	_resources["wood"] = 99
	_repair_structure(widx)
	var ok_wrepair: bool = _terrain_at(Vector2i(21, 20)) == Terrain.WOOD_WALL and not _wrecks.has(widx)
	_report("destroyed wall becomes passable wreck + repairs", ok_wreck and ok_wrepair); fails += int(not (ok_wreck and ok_wrepair))

	# Adjacent monster damages the player and knocks them back.
	_set_terrain(Vector2i(21, 20), Terrain.GRASS)
	_health = 50.0
	_player_kb = Vector2.ZERO
	_monsters = [_mk_croc(_player_pos + Vector2(15, 0), MONSTER_HP)]
	_monster_update(0.1)
	var ok_pdmg: bool = absf(_health - (50.0 - MONSTER_HIT)) < 0.01 and _player_kb.length() > 1.0
	_report("monster hit damages + knocks back player", ok_pdmg); fails += int(not ok_pdmg)

	# Night punch: the fist hits a croc and knocks it back.
	# (Aim tracks the cursor, so place the croc along the actual aim direction.)
	_punch_active = false
	var aim := get_global_mouse_position() - _player_pos
	aim = aim.normalized() if aim.length() > 1.0 else Vector2.RIGHT
	_monsters = [_mk_croc(_player_pos + aim * (PLAYER_RADIUS + PUNCH_REACH), PLAYER_DMG)]
	_start_punch(_player_pos + aim * 100.0)
	_update_punch(PUNCH_TIME * 0.5)   # advance to full extension
	var ok_punch: bool = _monsters[0]["hp"] <= 0 and (_monsters[0]["kb"] as Vector2).length() > 1.0
	_report("punch fist hits + knocks back croc", ok_punch); fails += int(not ok_punch)

	# Landing a punch triggers a hit-stop freeze.
	var ok_hitstop: bool = _hitstop > 0.0
	_report("landing a punch triggers hit-stop", ok_hitstop); fails += int(not ok_hitstop)
	_hitstop = 0.0

	# Punch is canceled if the player is hurt mid-extension.
	_punch_active = false
	_monsters = []
	_start_punch(_player_pos + Vector2(100, 0))
	_update_punch(PUNCH_TIME * 0.2)   # still extending
	_damage_player(1.0, _player_pos + Vector2(10, 0))
	var ok_cancel: bool = not _punch_active
	_report("getting hurt cancels an extending punch", ok_cancel); fails += int(not ok_cancel)

	# No punching during the day.
	_is_night = false
	_punch_active = false
	_start_punch(_player_pos + Vector2(100, 0))
	var ok_daypunch: bool = not _punch_active
	_report("no attacks during the day", ok_daypunch); fails += int(not ok_daypunch)

	# --- Mother Tree / downed player / game over ---
	_is_night = false
	_lives = MAX_LIVES
	_sap = 20.0
	_downed = false
	_health = 10.0
	_damage_player(50.0)   # death
	var ok_downed: bool = _downed and _lives == MAX_LIVES and _health == 0.0
	_report("player death starts downed state, not game over", ok_downed); fails += int(not ok_downed)
	_tick_downed(FP_RESPAWN_DELAY)
	var ok_respawn: bool = not _downed and absf(_sap - 5.0) < 0.01 and _health == _p_max_health \
		and _chebyshev(_cell, _tree_center_cell()) == 2
	_report("downed player respawns at Tree and spends Sap", ok_respawn); fails += int(not ok_respawn)

	_tree_tier = 1
	_tree_hp = _tree_max_hp(1)
	_sap = 40.0
	_try_tree_tier_up()
	var ok_tree_up: bool = _tree_tier == 2 and absf(_tree_hp - _tree_max_hp(2)) < 0.01 and _sap < 0.01
	_report("Sap grows the Mother Tree tier + full-heals", ok_tree_up); fails += int(not ok_tree_up)
	_damage_tree(80.0)
	var ok_tree_down: bool = _tree_tier == 1 and absf(_tree_hp - _tree_max_hp(1)) < 0.01
	_report("Tree HP crossing threshold drops a tier", ok_tree_down); fails += int(not ok_tree_down)

	_turrets.clear()
	var aura_cell := _tree_center_cell() + Vector2i(0, 3)
	_set_terrain(aura_cell, Terrain.TURRET)
	var aura_idx := _cell_index(aura_cell)
	_turrets[aura_idx] = _new_turret(aura_cell)
	_turrets[aura_idx]["type"] = "sniper"
	_turrets[aura_idx]["fuel"] = 0.0
	_turret_update(0.01)
	var ok_aura_power: bool = bool(_turrets[aura_idx]["powered"])
	_report("Tree aura powers nearby turrets", ok_aura_power); fails += int(not ok_aura_power)
	_turrets.clear()
	_set_terrain(aura_cell, Terrain.GRASS)

	_resources = {"wood": 9, "stone": 9, "banana": 9, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_day = 5
	_tree_hp = 1.0
	_damage_tree(5.0)
	var ok_over: bool = _day == 1 and _resources["wood"] == 0 and _tree_tier == 1 and _tree_hp == _tree_max_hp(1)
	_report("Tree death is the only game-over reset", ok_over); fails += int(not ok_over)

	_clear_den_terrain()
	_dens.clear()
	_won = false
	var did := _create_den(Vector2i(45, 45), 2, 0)
	var ok_den_make: bool = _dens.has(did) and _terrain_at(Vector2i(45, 45)) == Terrain.CROC_DEN \
		and _terrain_at(Vector2i(46, 46)) == Terrain.CROC_DEN
	_report("Den creates a persistent footprint", ok_den_make); fails += int(not ok_den_make)
	_dens[did]["maturity"] = FP_DEN_EVOLVE_MATURITY - 1
	_nights_survived = 1
	_advance_dens_day()
	var ok_den_evolve: bool = int(_dens[did]["size"]) == 3 and _terrain_at(Vector2i(47, 47)) == Terrain.CROC_DEN
	_report("Den maturity evolves footprint", ok_den_evolve); fails += int(not ok_den_evolve)
	_monsters.clear()
	_nights_survived = 3
	_spawn_monsters(5)
	var tree_seekers := 0
	for dm in _monsters:
		if String(dm.get("target", "player")) == "tree":
			tree_seekers += 1
	var ok_den_spawn: bool = _monsters.size() == 5 and tree_seekers >= 1
	_report("Dens spawn waves with Tree-seeker split", ok_den_spawn); fails += int(not ok_den_spawn)
	_monsters.clear()
	_tree_tier = 3
	_damage_den_at(Vector2i(45, 45), 9999.0)
	var ok_win: bool = _won and _dens.is_empty() and _terrain_at(Vector2i(45, 45)) == Terrain.WRECK
	_report("last Den down at Tree tier 3 wins", ok_win); fails += int(not ok_win)

	# --- Stats / leveling / escalation ---
	_init_progression()
	var atk0 := _p_attack
	_gain_xp(_xp_to_next)   # exactly one level
	var ok_level: bool = _level == 2 and _stat_points == 1 and _active_overlay == Overlay.LEVELUP
	_report("leveling grants a stat point + choice", ok_level); fails += int(not ok_level)

	# Spending the point raises the chosen stat, full-heals, and clears the choice.
	_choose_stat("attack")
	var ok_choose: bool = _p_attack > atk0 and _stat_points == 0 and _active_overlay == Overlay.NONE \
		and _health == _p_max_health and _alloc["attack"] == 1
	_report("choosing a stat raises it + clears prompt", ok_choose); fails += int(not ok_choose)

	# Armor reduces incoming damage.
	_init_progression()
	_alloc["armor"] = 10
	_recompute_player_stats()
	_health = _p_max_health
	_damage_player(10.0)
	var ok_armor: bool = absf(_health - (_p_max_health - 10.0 * (1.0 - _p_armor))) < 0.01 and _p_armor > 0.0
	_report("armor reduces incoming damage", ok_armor); fails += int(not ok_armor)

	# Crocs scale with the night number.
	var c1 := _croc_for_night(Vector2.ZERO, 1)
	var c5 := _croc_for_night(Vector2.ZERO, 5)
	var ok_escal: bool = c5["max_hp"] > c1["max_hp"] and c5["attack"] > c1["attack"] and c5["armor"] > c1["armor"]
	_report("crocs get tougher each night", ok_escal); fails += int(not ok_escal)

	# Killing a croc grants XP.
	_init_progression()
	_is_night = true
	var dead := _mk_croc(_player_pos + Vector2(500, 0), 0.0)
	dead["xp"] = 3
	_monsters = [dead]
	_monster_update(0.01)
	var ok_xp: bool = _xp == 3 and _monsters.size() == 0
	_report("killing a croc grants XP", ok_xp); fails += int(not ok_xp)

	# Surviving to dawn counts a night.
	_init_progression()
	_is_night = true
	_time = 0.20
	_advance_time(1.5)   # crosses into daylight
	var ok_nights: bool = _nights_survived == 1 and not _is_night
	_report("reaching dawn counts a survived night", ok_nights); fails += int(not ok_nights)

	# --- Combat juice ---
	_shake = 0.0; _hurt_flash = 0.0; _poofs = []
	_player_pos = _cell_center_world(Vector2i(20, 20))
	_damage_player(5.0, _player_pos + Vector2(10, 0))
	var ok_feel: bool = _hurt_flash > 0.0 and _shake > 0.0
	_report("getting hit triggers flash + shake", ok_feel); fails += int(not ok_feel)

	_init_progression()
	_is_night = true
	var dead2 := _mk_croc(_player_pos + Vector2(500, 0), 0.0)
	_monsters = [dead2]
	_monster_update(0.01)
	var ok_poof: bool = _poofs.size() == 1
	_report("croc death spawns a poof", ok_poof); fails += int(not ok_poof)

	# Shake decays back to zero over time.
	_shake = 10.0
	for _i in range(60):
		_update_juice(0.05)
	var ok_decay: bool = _shake == 0.0
	_report("screen shake decays", ok_decay); fails += int(not ok_decay)

	# === Juice / _fx transient-effects list (§ juice brief) ===
	# A croc death layers a meatier burst (gore ring + chunks + flash) on the _fx list.
	_fx = []; _dusk_active = false; _tier_glow = 0.0; _clock_flash = 0.0
	_fx_croc_death(_cell_center_world(Vector2i(20, 20)))
	var kinds := {}
	for e in _fx:
		kinds[e["kind"]] = true
	var ok_death_fx: bool = kinds.has("croc_gore") and kinds.has("croc_chunks") and kinds.has("flash_dot")
	_report("croc death layers gore+chunks+flash fx", ok_death_fx); fails += int(not ok_death_fx)

	# The single advance loop normalizes t by per-entry life and culls at t>=1.
	_fx = [{"kind": "flash_dot", "pos": Vector2.ZERO, "t": 0.0, "life": FX_FLASH_LIFE, "seed": 0}]
	for _i in range(20):
		_update_juice(0.05)   # 1.0s elapsed >> 0.12s life
	var ok_cull: bool = _fx.is_empty()
	_report("fx entries advance + cull by per-entry life", ok_cull); fails += int(not ok_cull)

	# Damage-number aggregation: a second hit near a young same-channel number folds
	# into it (sums amount, re-pops t, bumps hits) instead of stacking a new entry.
	_fx = []
	var dn_pos := _cell_center_world(Vector2i(30, 30))
	_fx_damage_number(dn_pos, 12.0, "damage")
	_fx[0]["t"] = 0.2   # young (< FX_DMGNUM_AGG_T)
	_fx_damage_number(dn_pos + Vector2(4, 0), 7.0, "damage")
	var dmg_entries := 0
	var agg_amount := 0.0
	var agg_hits := 0
	var agg_t := 1.0
	for e in _fx:
		if e["kind"] == "dmgnum":
			dmg_entries += 1
			agg_amount = float(e["amount"]); agg_hits = int(e["hits"]); agg_t = float(e["t"])
	var ok_agg: bool = dmg_entries == 1 and agg_amount == 19.0 and agg_hits == 2 and agg_t == 0.0
	_report("damage numbers aggregate + re-pop on multi-hit", ok_agg); fails += int(not ok_agg)

	# Distinct channels never aggregate together; a 0-amount number is skipped.
	_fx = []
	_fx_damage_number(dn_pos, 5.0, "damage")
	_fx_damage_number(dn_pos, 5.0, "heal")
	_fx_damage_number(dn_pos, 0.4, "damage")   # rounds to 0 -> skipped
	var ok_channels: bool = _fx.size() == 2
	_report("dmgnum channels stay distinct, zero is skipped", ok_channels); fails += int(not ok_channels)

	# Build flash appends a build fx (+thunk shake); repair appends a mended variant.
	_fx = []; _shake = 0.0
	_fx_build(Vector2i(10, 10))
	var ok_build_fx: bool = _fx.size() == 1 and _fx[0]["kind"] == "build" \
		and not bool(_fx[0]["repair"]) and _shake > 0.0
	_report("build fx appends + thunks; repair flag carried", ok_build_fx); fails += int(not ok_build_fx)
	_fx = []
	_fx_build(Vector2i(10, 10), true)
	var ok_repair_fx: bool = _fx.size() == 1 and bool(_fx[0]["repair"])
	_report("repair fx tagged repair (mended cyan)", ok_repair_fx); fails += int(not ok_repair_fx)

	# Tier-up arms the dawn-wash glow and appends a bloom + a gold TIER number.
	_fx = []; _tier_glow = 0.0
	_fx_tier_up()
	var tier_kinds := {}
	for e in _fx:
		tier_kinds[e["kind"]] = true
	var ok_tier_fx: bool = _tier_glow == 1.0 and tier_kinds.has("tier_bloom") and tier_kinds.has("dmgnum")
	_report("tier-up arms dawn glow + bloom + TIER text", ok_tier_fx); fails += int(not ok_tier_fx)
	# The glow decays toward 0 over the next ~0.5s (and is OR'd into the redraw gate).
	for _i in range(20):
		_update_juice(0.05)
	var ok_glow_decay: bool = _tier_glow == 0.0
	_report("tier-up dawn glow decays", ok_glow_decay); fails += int(not ok_glow_decay)

	# Dusk telegraph: crossing into [0.68,0.78) arms _dusk_active, warms the canvas
	# away from the plain daylight tint, and (in the final 10s) paints spawn-warn rings.
	_fx = []; _dusk_active = false; _dusk_telegraphed = false; _incoming_telegraphed = false
	_time = 0.69
	_apply_daylight()
	var plain := NIGHT_COLOR.lerp(Color.WHITE, _daylight(_time))
	_update_dusk_telegraph(); _update_dusk_state(0.0)
	var ok_dusk_active: bool = _dusk_active and _dusk_phase > 0.0 and _dusk_phase < 1.0
	_report("dusk window arms _dusk_active + phase", ok_dusk_active); fails += int(not ok_dusk_active)
	var ok_warm: bool = _canvas_mod != null and _canvas_mod.color != plain
	_report("dusk warms the canvas toward sunset", ok_warm); fails += int(not ok_warm)
	# Final 10s: spawn-preview rings appear at the den/shore cells crocs surface on.
	_ensure_den_footprints()   # guarantee dens + their shore cells exist for this check
	_fx = []; _incoming_telegraphed = false
	_time = 0.78 - (8.0 / DAY_LENGTH)   # ~8s before night
	_update_dusk_telegraph()
	var warn_count := 0
	for e in _fx:
		if e["kind"] == "spawn_warn":
			warn_count += 1
	var expected_warn := mini(_den_spawn_cells().size(), 24)
	var ok_warn: bool = warn_count == expected_warn and warn_count > 0
	_report("night-incoming paints spawn-warn rings at shore cells", ok_warn); fails += int(not ok_warn)
	# Leaving the window clears _dusk_active (state self-heals from _time).
	_time = 0.5
	_update_dusk_state(0.0)
	var ok_dusk_clear: bool = not _dusk_active
	_report("dusk state clears outside the window", ok_dusk_clear); fails += int(not ok_dusk_clear)
	_fx = []; _dusk_active = false; _tier_glow = 0.0; _clock_flash = 0.0
	_dusk_telegraphed = false; _incoming_telegraphed = false

	# === New croc roster + status effects + defenses ===
	_is_night = true
	_cell = Vector2i(25, 25)
	_player_pos = _cell_center_world(_cell)

	# Roster unlocks scale with the night number.
	var only_green := true
	for tp in _unlocked_croc_pool(1):
		if tp != "green":
			only_green = false
	var distinct9 := {}
	for tp in _unlocked_croc_pool(9):
		distinct9[tp] = true
	var ok_pool: bool = only_green and distinct9.size() == CROC_DEFS.size()
	_report("croc roster unlocks by night", ok_pool); fails += int(not ok_pool)

	# Yellow is faster but weaker than green.
	var gc := _croc_for_night(Vector2.ZERO, 3, "green")
	var yc := _croc_for_night(Vector2.ZERO, 3, "yellow")
	var ok_yellow: bool = yc["speed"] > gc["speed"] and yc["attack"] < gc["attack"]
	_report("yellow croc is fast + weak", ok_yellow); fails += int(not ok_yellow)

	# Fireball burns over time.
	_clear_status_effects(); _health = 100.0
	_apply_fire_hit(_player_pos + Vector2(40, 0))
	var burn_started: bool = _burn_t > 0.0 and _health < 100.0
	var hp_after_fire := _health
	_update_status_effects(0.5)
	var ok_burn: bool = burn_started and _health < hp_after_fire
	_report("fireball burns over time", ok_burn); fails += int(not ok_burn)

	# Snowball slows; slow does not re-stack while already slowed.
	_clear_status_effects(); _health = 100.0
	_apply_snow_hit(_player_pos + Vector2(40, 0))
	var slow1 := _slow_t
	_slow_t = 0.4
	_apply_snow_hit(_player_pos + Vector2(40, 0))
	var ok_slow: bool = slow1 == SLOW_TIME and _slow_t == 0.4
	_report("snowball slows (no re-stack)", ok_slow); fails += int(not ok_slow)

	# Three snowballs freeze; a fourth doesn't extend the freeze.
	_clear_status_effects(); _health = 100.0
	_apply_snow_hit(_player_pos); _apply_snow_hit(_player_pos); _apply_snow_hit(_player_pos)
	var froze := _freeze_t
	_apply_snow_hit(_player_pos)
	var ok_freeze: bool = froze == FREEZE_TIME and _freeze_t == FREEZE_TIME
	_report("3 snowballs freeze (no stack)", ok_freeze); fails += int(not ok_freeze)

	# Walls block enemy projectiles.
	_clear_status_effects(); _health = 100.0; _projectiles = []
	_set_terrain(Vector2i(27, 25), Terrain.STONE_WALL)
	_fire_projectile(_cell_center_world(Vector2i(29, 25)), "fire")
	for _i in range(40):
		_update_projectiles(0.05)
	var ok_proj_block: bool = _health == 100.0 and _projectiles.is_empty()
	_set_terrain(Vector2i(27, 25), Terrain.GRASS)
	_report("walls block enemy projectiles", ok_proj_block); fails += int(not ok_proj_block)

	# Poison cloud only hurts the player while inside it.
	_clear_status_effects(); _health = 100.0
	_poison_clouds = [{"pos": _player_pos + Vector2(500, 0), "t": 0.0}]
	_update_status_effects(0.5)
	var poison_far_ok := _health == 100.0
	_poison_clouds = [{"pos": _player_pos, "t": 0.0}]
	_update_status_effects(0.5)
	var ok_poison: bool = poison_far_ok and _health < 100.0
	_poison_clouds = []
	_report("poison cloud hurts only inside", ok_poison); fails += int(not ok_poison)

	# White croc heals a wounded ally in range.
	var ally := _mk_croc(_player_pos + Vector2(CELL_SIZE, 0), 10.0, "green")
	ally["hp"] = 2.0; ally["max_hp"] = 10.0
	_monsters = [_mk_croc(_player_pos, 10.0, "white"), ally]
	_apply_heal_auras(1.0)
	var ok_heal: bool = _monsters[1]["hp"] > 2.0 and _monsters[1]["healing"]
	_report("white croc heals allies", ok_heal); fails += int(not ok_heal)

	# Burrowed brown SAPPER can't be punched; it surfaces next to the TREE
	# (decision #15), not the player, since it tunnels to the trunk.
	var aim2 := get_global_mouse_position() - _player_pos
	aim2 = aim2.normalized() if aim2.length() > 1.0 else Vector2.RIGHT
	_monsters = [_mk_croc(_player_pos + aim2 * (PLAYER_RADIUS + PUNCH_REACH), 8.0, "brown")]
	_monsters[0]["target"] = "tree"
	_punch_active = false
	_start_punch(_player_pos + aim2 * 100.0)
	_update_punch(PUNCH_TIME * 0.5)
	var dig_invuln: bool = _monsters[0]["hp"] == 8.0
	# Sat adjacent to the Tree footprint while burrowed -> next tick it surfaces.
	_monsters[0]["dig"] = true
	_monsters[0]["pos"] = _cell_center_world(_tree_center_cell() + Vector2i(0, 2))
	_is_night = true
	_monster_update(0.05)
	var ok_dig: bool = dig_invuln and not _monsters[0]["dig"]
	_report("brown croc digs (invuln) then surfaces", ok_dig); fails += int(not ok_dig)
	_monsters.clear()

	# Black croc revives once and grants no XP on the first kill.
	_init_progression(); _is_night = true
	var blk := _mk_croc(_player_pos + Vector2(400, 0), 8.0, "black")
	blk["hp"] = 0.0
	_monsters = [blk]
	var xp_before := _xp
	_monster_update(0.05)
	var black_kept := _monsters.size() == 1 and _xp == xp_before
	_monster_update(REVIVE_TIME + 0.1)
	var black_revived: bool = _monsters.size() == 1 and _monsters[0]["hp"] > 0.0 and _monsters[0]["revived"]
	_monsters[0]["hp"] = 0.0
	_monster_update(0.05)
	var ok_black: bool = black_kept and black_revived and _monsters.is_empty() and _xp > xp_before
	_report("black croc revives once (no first-kill XP)", ok_black); fails += int(not ok_black)
	_active_overlay = Overlay.NONE

	# Pink croc beelines for and wrecks a structure.
	_monsters = []
	_set_terrain(Vector2i(6, 5), Terrain.WOOD_WALL)
	_monsters = [_mk_croc(_cell_center_world(Vector2i(5, 5)), 30.0, "pink")]
	for _i in range(25):
		_monsters[0]["brk_cd"] = 0.0   # (the cooldown normally ticks in _monster_update)
		_update_wrecker(_monsters[0], 0.1, Vector2.RIGHT)
	var ok_pink: bool = _terrain_at(Vector2i(6, 5)) == Terrain.WRECK
	_struct_hp.erase(_cell_index(Vector2i(6, 5)))
	_report("pink croc wrecks structures first", ok_pink); fails += int(not ok_pink)

	# A configured ranged turret fires at a croc in range (with line of sight).
	_monsters = []; _projectiles = []; _turrets.clear()
	for cx in range(10, 14):
		_set_terrain(Vector2i(cx, 10), Terrain.GRASS)
	_set_terrain(Vector2i(10, 10), Terrain.TURRET)
	var tcell := _cell_index(Vector2i(10, 10))
	_turrets[tcell] = _new_turret(Vector2i(10, 10))
	# Unconfigured turret does nothing.
	_monsters = [_mk_croc(_cell_center_world(Vector2i(13, 10)), 30.0, "green")]
	_turret_update(0.1)
	var ok_unconf: bool = _projectiles.is_empty()
	_report("unconfigured turret does nothing", ok_unconf); fails += int(not ok_unconf)
	# Configure as a machine gun -> it shoots bullets.
	_configure_turret(tcell, "mg")
	_turret_update(0.1)
	var ok_turret: bool = _projectiles.size() >= 1 and _projectiles[0]["kind"] == "bullet"
	_report("ranged turret fires at crocs", ok_turret); fails += int(not ok_turret)

	# That bullet damages the croc and the turret earns the XP (not the player).
	var ok_arrow := false
	if ok_turret:
		var hp0t: float = _monsters[0]["hp"]
		_monsters[0]["pos"] = (_projectiles[0]["pos"] as Vector2) + (_projectiles[0]["vel"] as Vector2).normalized() * 5.0
		_update_projectiles(0.05)
		ok_arrow = _monsters[0]["hp"] < hp0t
	_report("turret bullet damages crocs", ok_arrow); fails += int(not ok_arrow)

	# A turret keeps the XP from its own kills (no sharing with the player).
	_monsters = [_mk_croc(_cell_center_world(Vector2i(11, 10)), 1.0, "green")]
	_xp = 0
	_hurt_croc(_monsters[0], 999.0, Vector2.RIGHT, 0.0, tcell)
	_monster_update(0.05)
	var ok_txp: bool = int(_turrets[tcell]["xp"]) > 0 and _xp == 0
	_report("turret earns its own kill XP", ok_txp); fails += int(not ok_txp)

	# Outdoor placement rule: a tile sealed by walls is not outdoors.
	for wc in [Vector2i(40, 40), Vector2i(42, 40), Vector2i(40, 42), Vector2i(42, 42), Vector2i(41, 40), Vector2i(40, 41), Vector2i(42, 41), Vector2i(41, 42)]:
		_set_terrain(wc, Terrain.WOOD_WALL)
	var ok_indoor: bool = not _is_outdoors(Vector2i(41, 41)) and _is_outdoors(Vector2i(5, 40))
	for wc in [Vector2i(40, 40), Vector2i(42, 40), Vector2i(40, 42), Vector2i(42, 42), Vector2i(41, 40), Vector2i(40, 41), Vector2i(42, 41), Vector2i(41, 42)]:
		_set_terrain(wc, Terrain.GRASS)
	_report("turrets blocked from indoors", ok_indoor); fails += int(not ok_indoor)

	# Broken turret stays in place (not demolished).
	_turrets[tcell]["hp"] = 1.0; _turrets[tcell]["broken"] = false
	_turret_take_damage(_turrets[tcell], 999.0)
	var ok_broken: bool = _turrets[tcell]["broken"] and _terrain_at(Vector2i(10, 10)) == Terrain.TURRET
	# Day repair brings it back.
	_is_night = false
	_resources = _default_inventory(); _resources["wood"] = 5; _resources["stone"] = 5
	_turret_repair(tcell)
	ok_broken = ok_broken and not _turrets[tcell]["broken"] and float(_turrets[tcell]["hp"]) > 0.0
	_report("turret breaks in place + day-repairs", ok_broken); fails += int(not ok_broken)

	# Refueling pours a cup of wine into the tank.
	_turrets[tcell]["fuel"] = 0.0
	_resources["cup_wine"] = 1
	_turret_refuel(tcell)
	var ok_fuel: bool = float(_turrets[tcell]["fuel"]) > 0.0 and _inv("cup_wine") == 0
	_report("turret refuels from berry wine", ok_fuel); fails += int(not ok_fuel)

	_resources = _default_inventory(); _resources["stone"] = 1; _resources["charcoal"] = 1
	_craft("gunpowder")
	var ok_gunpowder: bool = _inv("gunpowder") == 4 and _inv("stone") == 0 and _inv("charcoal") == 0
	_report("craft gunpowder from stone + charcoal", ok_gunpowder); fails += int(not ok_gunpowder)

	_turrets[tcell]["ammo"] = 0
	_resources["gunpowder"] = 5
	_turret_reload(tcell)
	var ok_reload: bool = int(_turrets[tcell]["ammo"]) == 5 and _inv("gunpowder") == 0
	_report("manual turret reload uses gunpowder", ok_reload); fails += int(not ok_reload)

	var lcell := _cell_index(Vector2i(11, 10))
	_set_terrain(Vector2i(11, 10), Terrain.AUTO_LOADER)
	_autoloaders[lcell] = {"t": 0.0}
	_turrets[tcell]["ammo"] = 0
	_resources["gunpowder"] = 3
	_autoloader_tick(0.1)
	var ok_loader: bool = int(_turrets[tcell]["ammo"]) == 3 and _inv("gunpowder") == 0
	_report("auto-loader fills adjacent turret", ok_loader); fails += int(not ok_loader)

	var midx := _cell_index(Vector2i(12, 10))
	_set_terrain(Vector2i(12, 10), Terrain.AUTO_MINER)
	_miners[midx] = {"t": FP_AUTO_MINER_TICK}
	_resources["stone"] = 0
	_miner_tick(0.1)
	var ok_miner: bool = _inv("stone") >= FP_AUTO_MINER_STONE and REGROW_STONE == 0
	_report("auto-miner replaces dawn stone regrow", ok_miner); fails += int(not ok_miner)

	_casings = [{"pos": _player_pos}, {"pos": _player_pos}]
	_resources["casing"] = 0
	_is_night = false
	_sweep_casings()
	var ok_casings: bool = _inv("casing") == 2 and _casings.is_empty()
	_report("manual dawn casing sweep recovers casings", ok_casings); fails += int(not ok_casings)

	var cm_owner := _cell_index(Vector2i(13, 10))
	_turrets[cm_owner] = _new_turret(Vector2i(13, 10)); _configure_turret(cm_owner, "sniper")
	var armored := _mk_croc(_cell_center_world(Vector2i(14, 10)), 100.0, "pink")
	var armored_hp := float(armored["hp"])
	_hurt_croc(armored, 10.0, Vector2.ZERO, 0.0, cm_owner)
	var ok_counter: bool = armored_hp - float(armored["hp"]) > 10.0
	_report("turret counter matrix modifies damage", ok_counter); fails += int(not ok_counter)

	_set_terrain(Vector2i(10, 10), Terrain.GRASS); _turrets.clear()

	# === T2: the nine distinct turret behaviours ===
	_is_night = true; _monsters = []; _projectiles = []; _turrets.clear()

	# Sniper fires a dedicated "snipe" projectile.
	var si := _cell_index(Vector2i(20, 20))
	for cx in range(20, 24):
		_set_terrain(Vector2i(cx, 20), Terrain.GRASS)
	_set_terrain(Vector2i(20, 20), Terrain.TURRET)
	_turrets[si] = _new_turret(Vector2i(20, 20)); _configure_turret(si, "sniper")
	_monsters = [_mk_croc(_cell_center_world(Vector2i(23, 20)), 50.0, "green")]
	_turret_ranged(_turrets[si], 0.1)
	var ok_snipe: bool = _projectiles.size() >= 1 and _projectiles[0]["kind"] == "snipe"
	_report("sniper fires a snipe shot", ok_snipe); fails += int(not ok_snipe)

	# Rocket splash damages + slows nearby crocs.
	_projectiles = []; _monsters = []
	var rm1 := _mk_croc(_cell_center_world(Vector2i(30, 20)), 50.0, "green")
	var rm2 := _mk_croc((_cell_center_world(Vector2i(30, 20)) as Vector2) + Vector2(12, 0), 50.0, "green")
	_monsters = [rm1, rm2]
	var rhp2: float = _monsters[1]["hp"]
	_rocket_splash(_monsters[0]["pos"], 5.0, CELL_SIZE * 1.8, 1.0, "player", _monsters[0])
	var ok_rocket: bool = _monsters[1]["hp"] < rhp2 and _monsters[1]["slow_t"] > 0.0
	_report("rocket splash damages + slows area", ok_rocket); fails += int(not ok_rocket)

	# Slicer strikes several crocs in one swing.
	_turrets.clear(); _projectiles = []
	var sl := _cell_index(Vector2i(25, 30))
	_set_terrain(Vector2i(25, 30), Terrain.TURRET)
	_turrets[sl] = _new_turret(Vector2i(25, 30)); _configure_turret(sl, "slicer")
	var slp: Vector2 = _turrets[sl]["pos"]
	_monsters = [_mk_croc(slp + Vector2(22, 0), 50.0, "green"), _mk_croc(slp + Vector2(-22, 0), 50.0, "green")]
	var slh0: float = _monsters[0]["hp"]
	var slh1: float = _monsters[1]["hp"]
	_turret_melee(_turrets[sl], 0.1)
	var ok_slicer: bool = _monsters[0]["hp"] < slh0 and _monsters[1]["hp"] < slh1
	_report("slicer hits multiple targets", ok_slicer); fails += int(not ok_slicer)

	# Drill prioritises a support (healer) croc over a closer physical one.
	_turrets.clear()
	var di := _cell_index(Vector2i(25, 25))
	_turrets[di] = _new_turret(Vector2i(25, 25)); _configure_turret(di, "drill")
	_turrets[di]["pos"] = _cell_center_world(Vector2i(25, 25))
	_monsters = [_mk_croc(_cell_center_world(Vector2i(26, 25)), 50.0, "green"), _mk_croc(_cell_center_world(Vector2i(29, 25)), 50.0, "white")]
	var dtgt = _drill_target(_turrets[di]["pos"])
	var ok_drill: bool = dtgt != null and dtgt["type"] == "white"
	_report("drill targets support crocs first", ok_drill); fails += int(not ok_drill)

	# Engineer mends a wounded neighbouring turret.
	_turrets.clear()
	var ei := _cell_index(Vector2i(25, 25))
	_turrets[ei] = _new_turret(Vector2i(25, 25)); _configure_turret(ei, "engineer")
	_turrets[ei]["pos"] = _cell_center_world(Vector2i(25, 25))
	var wi := _cell_index(Vector2i(26, 25))
	_turrets[wi] = _new_turret(Vector2i(26, 25)); _configure_turret(wi, "boxer")
	_turrets[wi]["hp"] = 2.0
	_turret_engineer(_turrets[ei], 0.5)
	var ok_eng: bool = float(_turrets[wi]["hp"]) > 2.0
	_report("engineer heals wounded turrets", ok_eng); fails += int(not ok_eng)

	# Adhesive lays a field that slows crocs inside it.
	_turrets.clear()
	var ai := _cell_index(Vector2i(25, 25))
	for cx in range(25, 29):
		_set_terrain(Vector2i(cx, 25), Terrain.GRASS)
	_set_terrain(Vector2i(25, 25), Terrain.TURRET)
	_turrets[ai] = _new_turret(Vector2i(25, 25)); _configure_turret(ai, "adhesive")
	_turrets[ai]["pos"] = _cell_center_world(Vector2i(25, 25))
	_monsters = [_mk_croc(_cell_center_world(Vector2i(28, 25)), 50.0, "green")]
	_turret_adhesive(_turrets[ai], 0.1)
	var ok_adh: bool = (_turrets[ai]["field"] as Vector2) != Vector2.INF and _adhesive_factor(_turrets[ai]["field"]) < 1.0
	_report("adhesive lays a slowing field", ok_adh); fails += int(not ok_adh)
	_set_terrain(Vector2i(25, 25), Terrain.GRASS)

	# Trickster marks the toughest crocs in range; marked crocs take +20% damage.
	_turrets.clear()
	var tri := _cell_index(Vector2i(25, 25))
	_turrets[tri] = _new_turret(Vector2i(25, 25)); _configure_turret(tri, "trickster")
	_turrets[tri]["pos"] = _cell_center_world(Vector2i(25, 25))
	var tcl := _mk_croc(_cell_center_world(Vector2i(26, 25)), 50.0, "green"); tcl["hp"] = 5.0
	var tcb := _mk_croc(_cell_center_world(Vector2i(27, 25)), 50.0, "green"); tcb["hp"] = 40.0
	var tcm := _mk_croc(_cell_center_world(Vector2i(28, 25)), 50.0, "green"); tcm["hp"] = 20.0
	_monsters = [tcl, tcb, tcm]
	_update_trickster_marks(0.1)
	var ok_mark: bool = _monsters[1]["marked"] and _monsters[2]["marked"] and not _monsters[0]["marked"]
	_report("trickster marks toughest crocs", ok_mark); fails += int(not ok_mark)
	var mhp: float = _monsters[1]["hp"]
	_hurt_croc(_monsters[1], 10.0, Vector2.ZERO, 0.0, "player")
	var ok_markdmg: bool = absf((mhp - float(_monsters[1]["hp"])) - 12.0) < 0.01
	_report("marked croc takes +20% damage", ok_markdmg); fails += int(not ok_markdmg)

	_turrets.clear(); _monsters = []; _projectiles = []; _is_night = false

	# === T3: crocs damage turrets; firing burns wine fuel ===
	_turrets.clear()
	var ci := _cell_index(Vector2i(18, 18))
	_set_terrain(Vector2i(18, 18), Terrain.TURRET)
	_turrets[ci] = _new_turret(Vector2i(18, 18)); _configure_turret(ci, "mg")
	var thp0: float = _turrets[ci]["hp"]
	_damage_structure(Vector2i(18, 18))   # a croc chewing the turret
	var ok_tdmg: bool = float(_turrets[ci]["hp"]) < thp0 and _terrain_at(Vector2i(18, 18)) == Terrain.TURRET
	_report("crocs damage turret HP (tile stays)", ok_tdmg); fails += int(not ok_tdmg)

	# Firing burns fuel.
	_is_night = true
	_turrets[ci]["hp"] = _turrets[ci]["max_hp"]; _turrets[ci]["broken"] = false
	_turrets[ci]["fuel"] = 50.0; _turrets[ci]["cd"] = 0.0
	for cx in range(15, 19):
		_set_terrain(Vector2i(cx, 18), Terrain.GRASS)
	_set_terrain(Vector2i(18, 18), Terrain.TURRET)
	_monsters = [_mk_croc(_cell_center_world(Vector2i(15, 18)), 50.0, "green")]
	_turret_ranged(_turrets[ci], 0.1)
	var ok_fuelburn: bool = float(_turrets[ci]["fuel"]) < 50.0
	_report("firing burns wine fuel", ok_fuelburn); fails += int(not ok_fuelburn)
	_set_terrain(Vector2i(18, 18), Terrain.GRASS); _turrets.clear()
	_monsters = []; _projectiles = []; _is_night = false

	# === T4: global level + stat caps ===
	var c_capped := _croc_for_night(Vector2.ZERO, 999, "green")
	var c_at_cap := _croc_for_night(Vector2.ZERO, LEVEL_CAP, "green")
	var ok_croccap: bool = absf(float(c_capped["max_hp"]) - float(c_at_cap["max_hp"])) < 0.01
	_report("croc scaling caps at level 122", ok_croccap); fails += int(not ok_croccap)

	_init_progression()
	_level = LEVEL_CAP
	_xp_to_next = 1
	_gain_xp(100)   # should not exceed the cap
	var ok_plvlcap: bool = _level == LEVEL_CAP
	_report("player level caps at 122", ok_plvlcap); fails += int(not ok_plvlcap)

	_init_progression()
	_alloc["attack"] = STAT_UPGRADE_CAP
	_stat_points = 5
	_choose_stat("attack")   # already at the per-stat cap
	var ok_statcap: bool = _alloc["attack"] == STAT_UPGRADE_CAP
	_report("player stat upgrades cap at 70", ok_statcap); fails += int(not ok_statcap)
	_init_progression()

	# === T5: turret cap of five + the reworked XP attribution ===
	# Only five turrets may stand at once; a sixth placement is refused.
	_turrets.clear(); _monsters = []
	_is_night = false
	_cell = Vector2i(5, 5); _player_pos = _cell_center_world(_cell)
	_set_terrain(Vector2i(5, 6), Terrain.WORKBENCH)   # adjacent bench satisfies the gate
	_resources = _default_inventory(); _resources["wood"] = 100; _resources["stone"] = 100
	_build_struct = "turret"; _drag_action = BuildAction.BUILD
	for t5_i in range(6):
		var t5_c := Vector2i(7 + t5_i, 5)
		_set_terrain(t5_c, Terrain.GRASS)
		_apply_build_at(t5_c)
	var ok_cap: bool = _turrets.size() == MAX_TURRETS
	_report("turret cap stops the sixth placement", ok_cap); fails += int(not ok_cap)
	for t5_i2 in range(7, 13):
		_set_terrain(Vector2i(t5_i2, 5), Terrain.GRASS)
	_set_terrain(Vector2i(5, 6), Terrain.GRASS)
	_build_struct = ""; _turrets.clear()

	# Kill pays full XP; a recent direct-damage hit pays a half-XP assist.
	_is_night = true; _monsters = []; _projectiles = []
	var t5_ka := _cell_index(Vector2i(30, 30)); _turrets[t5_ka] = _new_turret(Vector2i(30, 30)); _configure_turret(t5_ka, "boxer")
	var t5_kb := _cell_index(Vector2i(32, 30)); _turrets[t5_kb] = _new_turret(Vector2i(32, 30)); _configure_turret(t5_kb, "boxer")
	var t5_m := _mk_croc(_cell_center_world(Vector2i(31, 30)), 50.0, "green"); t5_m["xp"] = 2
	_monsters = [t5_m]
	_hurt_croc(t5_m, 5.0, Vector2.ZERO, 0.0, t5_ka)     # A chips in -> assist
	_hurt_croc(t5_m, 999.0, Vector2.ZERO, 0.0, t5_kb)   # B lands the kill
	_monster_update(0.05)
	# Full bounty = 2 to the killer, half (rounded up) = 1 to the assister.
	var ok_assist: bool = int(_turrets[t5_kb]["xp"]) == 2 and int(_turrets[t5_ka]["xp"]) == 1
	_report("kill pays full XP, assist pays half", ok_assist); fails += int(not ok_assist)
	_turrets.clear(); _monsters = []

	# Trickster earns full XP when a croc it marked is killed (even by the player).
	_turrets.clear(); _monsters = []
	var t5_tr := _cell_index(Vector2i(25, 25)); _turrets[t5_tr] = _new_turret(Vector2i(25, 25)); _configure_turret(t5_tr, "trickster")
	_turrets[t5_tr]["pos"] = _cell_center_world(Vector2i(25, 25))
	var t5_tm := _mk_croc(_cell_center_world(Vector2i(26, 25)), 8.0, "green"); t5_tm["xp"] = 2
	_monsters = [t5_tm]
	_update_trickster_marks(0.1)
	var ok_trcredit: bool = (t5_tm["debuff_by"] as Dictionary).has(t5_tr)
	_hurt_croc(t5_tm, 999.0, Vector2.ZERO, 0.0, "player")
	_monster_update(0.05)
	ok_trcredit = ok_trcredit and int(_turrets[t5_tr]["xp"]) == 2
	_report("trickster earns full XP on a marked kill", ok_trcredit); fails += int(not ok_trcredit)
	_turrets.clear(); _monsters = []

	# Adhesive earns full XP when a croc caught in its field is killed.
	_turrets.clear(); _monsters = []
	var t5_ad := _cell_index(Vector2i(25, 25)); _turrets[t5_ad] = _new_turret(Vector2i(25, 25)); _configure_turret(t5_ad, "adhesive")
	_turrets[t5_ad]["pos"] = _cell_center_world(Vector2i(25, 25))
	var t5_am := _mk_croc(_cell_center_world(Vector2i(27, 25)), 8.0, "green"); t5_am["xp"] = 2
	_monsters = [t5_am]
	_turrets[t5_ad]["field"] = t5_am["pos"]
	_tag_adhesive_debuffs()
	var ok_adcredit: bool = (t5_am["debuff_by"] as Dictionary).has(t5_ad)
	_hurt_croc(t5_am, 999.0, Vector2.ZERO, 0.0, "player")
	_monster_update(0.05)
	ok_adcredit = ok_adcredit and int(_turrets[t5_ad]["xp"]) == 2
	_report("adhesive earns full XP on a slowed kill", ok_adcredit); fails += int(not ok_adcredit)
	_turrets.clear(); _monsters = []

	# Engineer banks XP off kills while it's been actively mending allies.
	_turrets.clear(); _monsters = []
	var t5_en := _cell_index(Vector2i(25, 25)); _turrets[t5_en] = _new_turret(Vector2i(25, 25)); _configure_turret(t5_en, "engineer")
	_turrets[t5_en]["pos"] = _cell_center_world(Vector2i(25, 25))
	var t5_wt := _cell_index(Vector2i(26, 25)); _turrets[t5_wt] = _new_turret(Vector2i(26, 25)); _configure_turret(t5_wt, "boxer")
	_turrets[t5_wt]["hp"] = 2.0
	_turret_engineer(_turrets[t5_en], 0.5)   # heals -> arms the heal_t window
	var t5_em := _mk_croc(_cell_center_world(Vector2i(20, 25)), 8.0, "green"); t5_em["xp"] = 6
	_monsters = [t5_em]
	_hurt_croc(t5_em, 999.0, Vector2.ZERO, 0.0, "player")
	_monster_update(0.05)
	var ok_engxp: bool = float(_turrets[t5_en]["heal_t"]) > 0.0 and int(_turrets[t5_en]["xp"]) > 0
	_report("engineer banks XP from healing during kills", ok_engxp); fails += int(not ok_engxp)
	_turrets.clear(); _monsters = []; _projectiles = []; _is_night = false

	# Tougher, later-night crocs are worth more XP than night-one ones.
	var t5_late := _croc_for_night(Vector2.ZERO, 20, "green")
	var t5_early := _croc_for_night(Vector2.ZERO, 1, "green")
	var ok_xpscale: bool = int(t5_late["xp"]) > int(t5_early["xp"])
	_report("croc XP scales up with night", ok_xpscale); fails += int(not ok_xpscale)

	# Spike trap damages and slows a croc standing on it, then re-arms.
	_monsters = []; _trap_cd.clear()
	_set_terrain(Vector2i(15, 15), Terrain.TRAP)
	_monsters = [_mk_croc(_cell_center_world(Vector2i(15, 15)), 30.0, "green")]
	var hp0tr: float = _monsters[0]["hp"]
	_trap_update(0.0)
	var ok_trap: bool = _monsters[0]["hp"] < hp0tr and _monsters[0]["slow_t"] > 0.0 \
		and float(_trap_cd.get(_cell_index(Vector2i(15, 15)), 0.0)) > 0.0
	_set_terrain(Vector2i(15, 15), Terrain.GRASS); _trap_cd.clear()
	_report("spike trap hurts + slows crocs", ok_trap); fails += int(not ok_trap)

	_monsters = []; _projectiles = []; _poison_clouds = []; _clear_status_effects()

	# === Stage 3: hydration + crafting + utility blocks ===
	_resources = _default_inventory()

	# Craft string from grass, and a cup from wood.
	_resources["grass"] = GRASS_PER_STRING
	_craft("string")
	var ok_string: bool = _inv("string") == 1 and _inv("grass") == 0
	_report("craft string from grass", ok_string); fails += int(not ok_string)
	_resources["wood"] = WOOD_PER_CUP
	_craft("cup")
	var ok_cup: bool = _inv("cup") == 1
	_report("craft cup from wood", ok_cup); fails += int(not ok_cup)

	# Fill a cup at the pool (day), then drink it for hydration.
	_is_night = false
	_resources["cup"] = 1; _resources["cup_water"] = 0
	_fill_cup_from_pool()
	var ok_fill: bool = _inv("cup_water") == 1 and _inv("cup") == 0
	_report("fill cup with water", ok_fill); fails += int(not ok_fill)
	_hydration = 20.0
	_drink("cup_water")
	var ok_drink: bool = _hydration > 20.0 and _inv("cup_water") == 0 and _inv("cup") == 1
	_report("drinking water restores hydration", ok_drink); fails += int(not ok_drink)

	# Water can't be gathered at night.
	var wcell := Vector2i(34, 34)
	_set_terrain(wcell, Terrain.WATER)
	_cell = wcell + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = wcell + Vector2i(1, 0)
	_is_night = true; _resources["cup"] = 1; _resources["cup_water"] = 0
	_click_interact(wcell)
	var ok_nightwater: bool = _inv("cup_water") == 0
	_set_terrain(wcell, Terrain.GRASS); _is_night = false
	_report("no water gathering at night", ok_nightwater); fails += int(not ok_nightwater)

	# Juicer presses a berry into juice, then fills a cup.
	var ji := _cell_index(Vector2i(30, 30))
	_set_terrain(Vector2i(30, 30), Terrain.JUICER)
	_juicers[ji] = {"juice": 0, "pending": 0, "conv": 0.0}
	_resources["berry"] = 1
	_juicer_add(ji)
	for _i in range(int(JUICE_TICK / 0.5) + 3):
		_utility_tick(0.5)
	var ok_juice: bool = int(_juicers[ji]["juice"]) == JUICE_PER_BERRY and _inv("berry") == 0
	_report("juicer presses berry into juice", ok_juice); fails += int(not ok_juice)
	_resources["cup"] = 1
	_juicer_take(ji)
	var ok_takejuice: bool = _inv("cup_juice") == 1 and int(_juicers[ji]["juice"]) == JUICE_PER_BERRY - 1
	_report("draw juice into a cup", ok_takejuice); fails += int(not ok_takejuice)

	# Barrel stores juice, ferments it to wine, then pours a cup of wine.
	var bi := _cell_index(Vector2i(31, 31))
	_set_terrain(Vector2i(31, 31), Terrain.BARREL)
	_barrels[bi] = {"kind": "", "amount": 0, "ferment": 0.0}
	_resources["cup_juice"] = 1; _resources["cup"] = 0
	_barrel_store(bi, "juice")
	var ok_store: bool = _barrels[bi]["kind"] == "juice" and int(_barrels[bi]["amount"]) == 1 and _inv("cup") == 1
	_report("store juice in a barrel", ok_store); fails += int(not ok_store)
	_barrels[bi]["ferment"] = FERMENT_TIME
	_utility_tick(0.1)
	var ok_ferment: bool = _barrels[bi]["kind"] == "wine"
	_report("barrel juice ferments into wine", ok_ferment); fails += int(not ok_ferment)
	_resources["cup"] = 1
	_barrel_take(bi)
	var ok_wine: bool = _inv("cup_wine") == 1
	_report("pour wine from the barrel", ok_wine); fails += int(not ok_wine)

	# Planter: plant a seed, grow berries only while watered, then harvest.
	var pi := _cell_index(Vector2i(32, 32))
	_set_terrain(Vector2i(32, 32), Terrain.PLANTER)
	_planters[pi] = {"planted": false, "berries": 0, "grow": 0.0, "wet": 0.0}
	_resources["seed"] = 1
	_planter_plant(pi)
	var ok_plant: bool = _planters[pi]["planted"] and _inv("seed") == 0
	_report("plant a seed in the planter", ok_plant); fails += int(not ok_plant)
	_planters[pi]["wet"] = PLANTER_DRY; _planters[pi]["grow"] = PLANTER_GROW
	_utility_tick(0.2)
	var ok_grow: bool = int(_planters[pi]["berries"]) >= 1
	_report("watered planter grows berries", ok_grow); fails += int(not ok_grow)
	_planters[pi]["wet"] = 0.0; _planters[pi]["berries"] = 0; _planters[pi]["grow"] = PLANTER_GROW
	_utility_tick(0.2)
	var ok_dry: bool = int(_planters[pi]["berries"]) == 0
	_report("dry planter won't grow", ok_dry); fails += int(not ok_dry)
	_planters[pi]["berries"] = 2; _resources["berry"] = 0
	_planter_harvest(pi)
	var ok_harv: bool = _inv("berry") == 2 and int(_planters[pi]["berries"]) == 0
	_report("harvest planter berries", ok_harv); fails += int(not ok_harv)

	# Harvesting a wild bush yields berries and a seed.
	var bushc := Vector2i(33, 33)
	_set_terrain(bushc, Terrain.BUSH); _berry[_cell_index(bushc)] = 2
	_resources["seed"] = 0; _resources["berry"] = 0
	_cell = bushc + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = bushc + Vector2i(1, 0)
	_harvest_cell(bushc)
	var ok_seed: bool = _inv("seed") >= 1 and _inv("berry") == 2
	_report("harvesting a bush drops a seed", ok_seed); fails += int(not ok_seed)

	# Tidy up the scratch tiles + state.
	for cc in [Vector2i(30, 30), Vector2i(31, 31), Vector2i(32, 32), Vector2i(33, 33)]:
		_set_terrain(cc, Terrain.GRASS)
	_juicers.clear(); _barrels.clear(); _planters.clear()
	_resources = _default_inventory()

	# Best-nights score round-trips through disk.
	var prev_best := _best_nights
	_best_nights = 7
	_save_progress()
	_best_nights = 0
	_load_progress()
	var ok_save: bool = _best_nights == 7
	_report("best-nights score persists to disk", ok_save); fails += int(not ok_save)
	# Restore so the test run doesn't clobber a real high score.
	_best_nights = maxi(prev_best, 0)
	_save_progress()

	# === Phase 0: loot auto-collect, banana->peel, block limit, 360 turrets ===
	# Ground loot is vacuumed up when the player walks near it.
	_ground_items = []; _resources = _default_inventory()
	_player_pos = _cell_center_world(Vector2i(24, 24))
	_spawn_loot("wood", 3, _player_pos + Vector2(4, 0))   # right on top of us
	_collect_ground_items(0.05)
	var ok_loot: bool = _inv("wood") == 3 and _ground_items.is_empty()
	_report("nearby loot auto-collects", ok_loot); fails += int(not ok_loot)
	# Far-away loot is left on the ground until approached.
	_ground_items = []; _resources = _default_inventory()
	_spawn_loot("stone", 2, _player_pos + Vector2(CELL_SIZE * 6.0, 0))
	_collect_ground_items(0.05)
	var ok_loot_far: bool = _inv("stone") == 0 and _ground_items.size() == 1
	_report("distant loot stays on the ground", ok_loot_far); fails += int(not ok_loot_far)
	_ground_items = []

	# Eating a banana leaves a peel behind.
	_resources = _default_inventory(); _resources["banana"] = 1; _energy = 0.0
	_try_eat()
	var ok_peel: bool = _inv("banana") == 0 and _inv("banana_peel") == 1
	_report("eating a banana yields a peel", ok_peel); fails += int(not ok_peel)

	# Block limit: walls/floors count and are capped; workstations/turrets don't.
	_resources = _default_inventory(); _resources["wood"] = 9999; _resources["stone"] = 9999; _resources["string"] = 9999
	_block_count = BLOCK_LIMIT
	_drag_action = BuildAction.BUILD; _build_struct = "wood_wall"
	_set_terrain(Vector2i(35, 35), Terrain.GRASS)
	_apply_build_at(Vector2i(35, 35))
	var ok_cap_block: bool = _terrain_at(Vector2i(35, 35)) == Terrain.GRASS   # refused at cap
	# A workstation (juicer needs a bench) is exempt from the cap; give it a bench.
	_set_terrain(Vector2i(36, 35), Terrain.WORKBENCH)
	_set_terrain(Vector2i(35, 34), Terrain.GRASS)   # ensure the build cell is clear
	_cell = Vector2i(35, 35); _player_pos = _cell_center_world(_cell)
	_build_struct = "juicer"; _monsters = []
	_apply_build_at(Vector2i(35, 34))
	var bc_before := _block_count
	ok_cap_block = ok_cap_block and _terrain_at(Vector2i(35, 34)) == Terrain.JUICER and _block_count == bc_before
	_report("block limit caps walls, not workstations", ok_cap_block); fails += int(not ok_cap_block)
	# _set_terrain keeps the block tally honest (place then remove a wall).
	_block_count = 0
	_set_terrain(Vector2i(35, 34), Terrain.GRASS)   # clear the juicer tile
	_set_terrain(Vector2i(37, 37), Terrain.WOOD_WALL)
	var ok_tally: bool = _block_count == 1
	_set_terrain(Vector2i(37, 37), Terrain.GRASS)
	ok_tally = ok_tally and _block_count == 0
	_report("block tally tracks place/remove", ok_tally); fails += int(not ok_tally)
	_set_terrain(Vector2i(36, 35), Terrain.GRASS); _juicers.clear()
	_build_struct = ""; _drag_action = BuildAction.NONE

	# Turrets have no facing arc: one targets a croc placed directly behind/left of it.
	_is_night = true; _turrets.clear(); _monsters = []; _projectiles = []
	var p0_t := _cell_index(Vector2i(20, 40))
	for cx in range(16, 21):
		_set_terrain(Vector2i(cx, 40), Terrain.GRASS)
	_set_terrain(Vector2i(20, 40), Terrain.TURRET)
	_turrets[p0_t] = _new_turret(Vector2i(20, 40)); _configure_turret(p0_t, "sniper")
	_monsters = [_mk_croc(_cell_center_world(Vector2i(17, 40)), 50.0, "green")]   # to the LEFT
	_turret_ranged(_turrets[p0_t], 0.1)
	var ok_360: bool = _projectiles.size() >= 1
	_report("turret targets crocs in any direction (360)", ok_360); fails += int(not ok_360)
	_set_terrain(Vector2i(20, 40), Terrain.GRASS); _turrets.clear(); _monsters = []; _projectiles = []
	_is_night = false; _resources = _default_inventory()

	# === Phase 1: new naturals + simple materials ===
	_resources = _default_inventory()
	# Harvest a coconut palm bearing fruit -> a coconut.
	_set_terrain(Vector2i(22, 22), Terrain.COCONUT); _banana[_cell_index(Vector2i(22, 22))] = 1
	_harvest_cell(Vector2i(22, 22))
	var ok_coco: bool = _inv("coconut") == 1
	_report("harvest coconut palm yields a coconut", ok_coco); fails += int(not ok_coco)
	# Eat the coconut -> hunger + hydration + a shell.
	_energy = 0.0; _hydration = 0.0
	_try_eat()
	var ok_ceat: bool = _inv("coconut") == 0 and _inv("coconut_shell") == 1 and _energy > 0.0 and _hydration > 0.0
	_report("eating a coconut feeds, hydrates, leaves a shell", ok_ceat); fails += int(not ok_ceat)
	# Harvest bamboo -> a couple of canes.
	_resources = _default_inventory()
	_set_terrain(Vector2i(23, 22), Terrain.BAMBOO)
	_harvest_cell(Vector2i(23, 22))
	var ok_bam: bool = _inv("bamboo") == 2 and _terrain_at(Vector2i(23, 22)) == Terrain.GRASS
	_report("harvest bamboo yields canes", ok_bam); fails += int(not ok_bam)
	# Smashing rocks sometimes turns up metal ore (probabilistic over many hits).
	_resources = _default_inventory()
	for oi in range(60):
		_set_terrain(Vector2i(24, 22), Terrain.STONE)
		_harvest_cell(Vector2i(24, 22))
	var ok_ore: bool = _inv("metal_ore") > 0 and _inv("stone") == 120
	_report("rock harvest can drop metal ore", ok_ore); fails += int(not ok_ore)
	# Craft the simple materials.
	_resources = _default_inventory(); _resources["string"] = 3
	_craft("rope")
	var ok_rope: bool = _inv("rope") == 1 and _inv("string") == 0
	_report("craft rope from string", ok_rope); fails += int(not ok_rope)
	_resources = _default_inventory(); _resources["wood"] = 2
	_craft("wooden_rod")
	var ok_rod: bool = _inv("wooden_rod") == 1
	_report("craft wooden rod from wood", ok_rod); fails += int(not ok_rod)
	_resources = _default_inventory(); _resources["stone"] = 1
	_craft("nails")
	var ok_nails: bool = _inv("nails") == 2
	_report("craft nails from stone (x2)", ok_nails); fails += int(not ok_nails)
	_resources = _default_inventory(); _resources["rotten_banana"] = 1; _resources["rotten_berry"] = 1
	_craft("glue")
	var ok_glue: bool = _inv("glue") == 1 and _rot_total() == 0
	_report("craft glue from spoiled fruit", ok_glue); fails += int(not ok_glue)
	_set_terrain(Vector2i(22, 22), Terrain.GRASS); _set_terrain(Vector2i(24, 22), Terrain.GRASS)
	_resources = _default_inventory(); _ground_items = []

	# === Phase 2: tool + weapon equipment ===
	_resources = _default_inventory()
	# Craft + equip a stone tool; it boosts wood/stone yield and cuts energy use.
	_resources["wood"] = 3; _resources["stone"] = 3; _resources["rope"] = 1
	_craft("stone_tool")
	var ok_stcraft: bool = _inv("stone_tool") == 1
	_equip("stone_tool")
	var ok_equip: bool = _tool_equipped == "stone_tool"
	_report("craft + equip a stone tool", ok_stcraft and ok_equip); fails += int(not (ok_stcraft and ok_equip))
	_resources = _default_inventory(); _tool_equipped = "stone_tool"; _energy = ENERGY_MAX
	_set_terrain(Vector2i(26, 26), Terrain.STONE)
	_harvest_cell(Vector2i(26, 26))
	var ok_toolyield: bool = _inv("stone") == 3   # 2 base + 1 tool bonus
	_report("tool boosts gather yield", ok_toolyield); fails += int(not ok_toolyield)
	_tool_equipped = ""
	# Slingshot: equip, then a night click fires a stone projectile that costs ammo.
	_resources = _default_inventory(); _resources["sling_ammo"] = 2
	_weapon_equipped = "slingshot"
	_is_night = true; _projectiles = []
	_player_pos = _cell_center_world(Vector2i(25, 25))
	_fire_slingshot(_player_pos + Vector2(100, 0))
	var ok_sling: bool = _projectiles.size() == 1 and _projectiles[0]["kind"] == "sling" and _inv("sling_ammo") == 1
	_report("slingshot fires + spends ammo", ok_sling); fails += int(not ok_sling)
	# A sling stone damages a croc it flies into.
	_monsters = [_mk_croc(_player_pos + Vector2(40, 0), 50.0, "green")]
	var shp0: float = _monsters[0]["hp"]
	for _si in range(20):
		_update_projectiles(0.03)
	var ok_slinghit: bool = _monsters[0]["hp"] < shp0
	_report("sling stone damages crocs", ok_slinghit); fails += int(not ok_slinghit)
	_weapon_equipped = ""; _projectiles = []; _monsters = []
	# Spear out-reaches fists: a croc just past fist range is missed by fists, hit by spear.
	# (Aim tracks the cursor, so place the croc along the real aim direction.)
	_punch_active = false
	var aim3 := get_global_mouse_position() - _player_pos
	aim3 = aim3.normalized() if aim3.length() > 1.0 else Vector2.RIGHT
	var dcroc := PLAYER_RADIUS + PUNCH_REACH + 22.0   # beyond a fist's full reach
	_weapon_equipped = ""
	_monsters = [_mk_croc(_player_pos + aim3 * dcroc, 50.0, "green")]
	var fhp0: float = _monsters[0]["hp"]
	_start_punch(_player_pos + aim3 * 100.0)
	_update_punch(PUNCH_TIME * 0.5)
	var fist_missed: bool = absf(_monsters[0]["hp"] - fhp0) < 0.01
	_punch_active = false
	_weapon_equipped = "spear"
	_monsters = [_mk_croc(_player_pos + aim3 * dcroc, 50.0, "green")]
	var sphp0: float = _monsters[0]["hp"]
	_start_punch(_player_pos + aim3 * 100.0)
	_update_punch(PUNCH_TIME * float(WEAPON_DEFS["spear"]["time"]) * 0.5)
	var ok_spear: bool = fist_missed and _monsters[0]["hp"] < sphp0
	_report("spear reaches farther than fists", ok_spear); fails += int(not ok_spear)
	_weapon_equipped = ""; _monsters = []; _projectiles = []; _punch_active = false
	_is_night = false; _resources = _default_inventory()
	_set_terrain(Vector2i(26, 26), Terrain.GRASS)

	# === Phase 3: glapple lamp + lighting + generic rot ===
	# A raw glapple spoils into generic rot over time.
	_resources = _default_inventory(); _resources["glapple"] = 80; _decay_timer = 0.0
	for _di in range(80):
		_decay_tick(DECAY_INTERVAL)
	var ok_grot: bool = _inv("rot") > 0 and _inv("glapple") < 80
	_report("glapples spoil into rot", ok_grot); fails += int(not ok_grot)
	# Craft a glapple lamp from a glapple + wooden rod.
	_resources = _default_inventory(); _resources["glapple"] = 1; _resources["wooden_rod"] = 1
	_craft("glapple_lamp")
	var ok_lampcraft: bool = _inv("glapple_lamp") == 1 and _inv("glapple") == 0 and _inv("wooden_rod") == 0
	_report("craft glapple lamp", ok_lampcraft); fails += int(not ok_lampcraft)
	# Place it; it lights up and counts as a light source.
	_lamps.clear()
	_set_terrain(Vector2i(28, 28), Terrain.GRASS)
	_cell = Vector2i(29, 29); _player_pos = _cell_center_world(_cell); _monsters = []
	_drag_action = BuildAction.BUILD; _build_struct = "glapple_lamp"
	_apply_build_at(Vector2i(28, 28))
	var lampidx := _cell_index(Vector2i(28, 28))
	var ok_lampplace: bool = _terrain_at(Vector2i(28, 28)) == Terrain.GLAPPLE_LAMP and _lamps.has(lampidx) \
		and _inv("glapple_lamp") == 0 and _light_sources().size() == 1
	_report("place glapple lamp -> a light source", ok_lampplace); fails += int(not ok_lampplace)
	# It burns down to dark, then stops being a light source.
	_lamps[lampidx]["life"] = 0.1
	_utility_tick(0.2)
	var ok_lampdead: bool = _lamps[lampidx]["dead"] and _light_sources().is_empty()
	_report("glapple lamp burns out + stops glowing", ok_lampdead); fails += int(not ok_lampdead)
	# Salvaging a dead lamp returns a rod + rot, frees the tile.
	_resources = _default_inventory()
	_remove_lamp(lampidx)
	var ok_lampsalv: bool = _inv("wooden_rod") == 1 and _inv("rot") == 1 \
		and _terrain_at(Vector2i(28, 28)) == Terrain.GRASS and not _lamps.has(lampidx)
	_report("salvage dead lamp -> rod + rot", ok_lampsalv); fails += int(not ok_lampsalv)
	_build_struct = ""; _drag_action = BuildAction.NONE; _lamps.clear()
	_resources = _default_inventory(); _ground_items = []

	# === Phase 4: kiln + metal + glass + sand ===
	_resources = _default_inventory()
	# Sand is harvested off the beach; the tile persists.
	_set_terrain(Vector2i(14, 14), Terrain.SAND)
	_harvest_cell(Vector2i(14, 14))
	var ok_sand: bool = _inv("sand") == 1 and _terrain_at(Vector2i(14, 14)) == Terrain.SAND
	_report("harvest sand from the beach", ok_sand); fails += int(not ok_sand)
	# Kiln: stoke with wood, smelt ore into metal over time.
	_kilns.clear()
	var kidx := _cell_index(Vector2i(40, 12)); _set_terrain(Vector2i(40, 12), Terrain.KILN)
	_kilns[kidx] = {"fuel": 0.0, "queue": [], "conv": 0.0}
	_resources = _default_inventory(); _resources["wood"] = 3; _resources["metal_ore"] = 1; _resources["sand"] = 1
	_kiln_fuel(kidx, "wood"); _kiln_fuel(kidx, "wood")   # plenty of fuel
	var ok_kfuel: bool = float(_kilns[kidx]["fuel"]) > 0.0 and _inv("wood") == 1
	_kiln_load(kidx, "metal_ore", "metal")
	var ok_kload: bool = _inv("metal_ore") == 0 and (_kilns[kidx]["queue"] as Array).size() == 1
	_utility_tick(KILN_TICK + 0.1)
	var ok_smelt: bool = _inv("metal") == 1 and (_kilns[kidx]["queue"] as Array).is_empty()
	_report("kiln stokes + smelts ore into metal", ok_kfuel and ok_kload and ok_smelt); fails += int(not (ok_kfuel and ok_kload and ok_smelt))
	# Melt sand into glass + char wood into charcoal.
	_kiln_load(kidx, "sand", "glass")
	_kiln_load(kidx, "wood", "charcoal")
	_utility_tick(KILN_TICK + 0.1)
	_utility_tick(KILN_TICK + 0.1)
	var ok_glasschar: bool = _inv("glass") == 1 and _inv("charcoal") == 1
	_report("kiln melts glass + chars charcoal", ok_glasschar); fails += int(not ok_glasschar)
	# Craft a glass jar + the upgraded metal tool.
	_resources = _default_inventory(); _resources["glass"] = 1
	_craft("glass_jar")
	var ok_jar: bool = _inv("glass_jar") == 1
	_report("craft a glass jar", ok_jar); fails += int(not ok_jar)
	_resources = _default_inventory(); _resources["metal"] = 2; _resources["wooden_rod"] = 1; _resources["rope"] = 1
	_craft("metal_tool")
	var ok_mtool: bool = _inv("metal_tool") == 1
	_report("craft the metal tool", ok_mtool); fails += int(not ok_mtool)
	_set_terrain(Vector2i(40, 12), Terrain.GRASS); _set_terrain(Vector2i(14, 14), Terrain.GRASS)
	_kilns.clear(); _resources = _default_inventory(); _ground_items = []

	# === Phase 5: bees, worms, fish, cooking ===
	# Worms need a glass jar to be scooped off the ground.
	_resources = _default_inventory(); _ground_items = []
	_player_pos = _cell_center_world(Vector2i(20, 20))
	_spawn_loot("worm", 1, _player_pos + Vector2(4, 0))
	_collect_ground_items(0.05)
	var ok_nojar: bool = _inv("worm") == 0 and _ground_items.size() == 1
	_resources["glass_jar"] = 1
	_collect_ground_items(0.05)
	var ok_wjar: bool = _inv("worm") == 1 and _inv("glass_jar") == 0 and _ground_items.is_empty()
	_report("worms need a jar to catch", ok_nojar and ok_wjar); fails += int(not (ok_nojar and ok_wjar))
	# Worm habitat breeds worms + composts rot into fertilizer.
	_wormfarms.clear(); _resources = _default_inventory()
	var wfi := _cell_index(Vector2i(20, 18)); _set_terrain(Vector2i(20, 18), Terrain.WORM_FARM)
	_wormfarms[wfi] = {"worms": 2, "rot": 1, "mult": 0.0, "compost": 0.0}
	_utility_tick(WORM_MULTIPLY_TIME + 0.1)
	var ok_worm: bool = int(_wormfarms[wfi]["worms"]) == 3 and _inv("fertilizer") >= 1 and int(_wormfarms[wfi]["rot"]) == 0
	_report("worm habitat breeds + composts to fertilizer", ok_worm); fails += int(not ok_worm)
	# Fertilizer makes a planter yield an extra berry.
	_planters.clear()
	var pli := _cell_index(Vector2i(21, 18)); _set_terrain(Vector2i(21, 18), Terrain.PLANTER)
	_planters[pli] = {"planted": true, "berries": 2, "grow": 0.0, "wet": 0.0, "fert": 0}
	_resources = _default_inventory(); _resources["fertilizer"] = 1
	_planter_fertilize(pli)
	_planter_harvest(pli)
	var ok_fert: bool = _inv("berry") == 3 and int(_planters[pli]["fert"]) == FERTILIZER_BONUS_HARVESTS - 1
	_report("fertilizer boosts planter yield", ok_fert); fails += int(not ok_fert)
	# A wild hive gives honey.
	_resources = _default_inventory()
	_set_terrain(Vector2i(22, 18), Terrain.HIVE); _cell = Vector2i(22, 19)
	_harvest_hive(Vector2i(22, 18))
	var ok_honey: bool = _inv("honey") >= 1
	_report("harvest a hive for honey", ok_honey); fails += int(not ok_honey)
	# Bee enclosure: deposit a bee (jar returns), then it makes honey near plants.
	_apiaries.clear(); _planters.clear(); _wormfarms.clear()
	for cy in range(14, 23):
		for cx in range(20, 29):
			_set_terrain(Vector2i(cx, cy), Terrain.GRASS)   # wipe all plants for a clean test
	var bei := _cell_index(Vector2i(24, 18)); _set_terrain(Vector2i(24, 18), Terrain.BEE_ENCLOSURE)
	_apiaries[bei] = {"bees": 0, "prod": 0.0, "starve": 0.0}
	_resources = _default_inventory(); _resources["bee"] = 1
	_apiary_add_bee(bei)
	var ok_addbee: bool = int(_apiaries[bei]["bees"]) == 1 and _inv("bee") == 0 and _inv("glass_jar") == 1
	_set_terrain(Vector2i(25, 18), Terrain.BUSH); _resources["honey"] = 0
	_utility_tick(BEE_PROD_TIME + 0.1)
	var ok_beehoney: bool = _inv("honey") >= 1
	_report("bee enclosure houses bees + makes honey", ok_addbee and ok_beehoney); fails += int(not (ok_addbee and ok_beehoney))
	# With no plants near, a bee starves off.
	_set_terrain(Vector2i(25, 18), Terrain.GRASS); _apiaries[bei]["starve"] = 0.0
	_utility_tick(BEE_STARVE_TIME + 0.1)
	var ok_starve: bool = int(_apiaries[bei]["bees"]) == 0
	_report("bees starve without nearby plants", ok_starve); fails += int(not ok_starve)
	# Fish: the pool restocks daily and can be caught.
	_fish.clear(); _spawn_fish_daily()
	var nfish0 := _fish.size()
	var ok_fishspawn: bool = nfish0 >= 1
	_resources = _default_inventory()
	var caught := _try_catch_fish(_fish[0]["pos"]) if not _fish.is_empty() else false
	var ok_fishcatch: bool = caught and (_inv("fish_m") + _inv("fish_f")) == 1 and _fish.size() == nfish0 - 1
	_report("fish spawn in the pool + are catchable", ok_fishspawn and ok_fishcatch); fails += int(not (ok_fishspawn and ok_fishcatch))
	# Eating raw fish feeds + leaves a bone.
	_resources = _default_inventory(); _resources["fish_m"] = 1; _energy = 0.0
	_try_eat()
	var ok_eatfish: bool = _inv("fish_m") == 0 and _inv("fish_bones") == 1 and _energy > 0.0
	_report("eating fish feeds + leaves bones", ok_eatfish); fails += int(not ok_eatfish)
	# Cooking: skewer 3 fish, cook on a campfire, retrieve the cooked meal.
	_resources = _default_inventory(); _resources["wooden_rod"] = 1; _resources["fish_m"] = 3
	_craft("fish_skewer")
	var ok_skewer: bool = _inv("fish_skewer") == 1 and (_inv("fish_m") + _inv("fish_f")) == 0
	_campfires.clear()
	var cfi := _cell_index(Vector2i(26, 18)); _set_terrain(Vector2i(26, 18), Terrain.CAMPFIRE)
	_campfires[cfi] = {"item": "", "cook": 0.0}
	_campfire_put(cfi)
	_utility_tick(COOK_TIME + 0.1)
	_campfire_take(cfi)
	var ok_cooked: bool = _inv("cooked_skewer") == 1 and _campfires[cfi]["item"] == ""
	_report("skewer cooks on a campfire", ok_skewer and ok_cooked); fails += int(not (ok_skewer and ok_cooked))
	# Left too long, the skewer chars to ash.
	_resources = _default_inventory(); _resources["wooden_rod"] = 1; _resources["fish_f"] = 3
	_craft("fish_skewer"); _campfire_put(cfi)
	_utility_tick(COOK_BURN_TIME + 0.1)
	_campfire_take(cfi)
	var ok_ash: bool = _inv("ash") == 1
	_report("overcooked skewer becomes ash", ok_ash); fails += int(not ok_ash)
	# Tidy up.
	for cc in [Vector2i(20, 18), Vector2i(21, 18), Vector2i(22, 18), Vector2i(24, 18), Vector2i(26, 18)]:
		_set_terrain(cc, Terrain.GRASS)
	_wormfarms.clear(); _planters.clear(); _apiaries.clear(); _campfires.clear(); _fish.clear()
	_resources = _default_inventory(); _ground_items = []

	# === Phase 6: berry-oil still ===
	_stills.clear(); _resources = _default_inventory(); _resources["cup_juice"] = 2
	var sti := _cell_index(Vector2i(30, 18)); _set_terrain(Vector2i(30, 18), Terrain.STILL)
	_stills[sti] = {"pending": 0, "conv": 0.0}
	_still_add(sti)
	var ok_stilladd: bool = int(_stills[sti]["pending"]) == 1 and _inv("cup_juice") == 1
	_utility_tick(STILL_TICK + 0.1)
	var ok_oil: bool = _inv("cup_oil") == 1 and int(_stills[sti]["pending"]) == 0
	_report("still refines juice into berry oil", ok_stilladd and ok_oil); fails += int(not (ok_stilladd and ok_oil))
	_set_terrain(Vector2i(30, 18), Terrain.GRASS); _stills.clear()
	_resources = _default_inventory(); _ground_items = []

	# === Phase 7: power network ===
	_generators.clear(); _lamps.clear(); _turrets.clear()
	# Clear a work area.
	for cy in range(10, 14):
		for cx in range(10, 18):
			_set_terrain(Vector2i(cx, cy), Terrain.GRASS)
	# Generator fueled + on; wires run to a turret two tiles away.
	var gi := _cell_index(Vector2i(10, 12)); _set_terrain(Vector2i(10, 12), Terrain.GENERATOR)
	_generators[gi] = {"oil": 3, "on": true, "drain": 0.0}
	_set_terrain(Vector2i(11, 12), Terrain.WIRE)
	_set_terrain(Vector2i(12, 12), Terrain.WIRE)
	var pti := _cell_index(Vector2i(13, 12)); _set_terrain(Vector2i(13, 12), Terrain.TURRET)
	_turrets[pti] = _new_turret(Vector2i(13, 12)); _configure_turret(pti, "sniper")
	_compute_power(0.01)
	var ok_energize: bool = _energized.has(gi) and _energized.has(_cell_index(Vector2i(11, 12))) and _energized.has(_cell_index(Vector2i(12, 12)))
	var ok_powered: bool = _is_powered(Vector2i(13, 12)) and not _is_powered(Vector2i(40, 40))
	_report("generator energizes its wire network", ok_energize and ok_powered); fails += int(not (ok_energize and ok_powered))
	# A powered turret fires on empty fuel and burns no wine.
	_is_night = true; _projectiles = []
	_turrets[pti]["fuel"] = 0.0; _turrets[pti]["cd"] = 0.0
	_monsters = [_mk_croc(_cell_center_world(Vector2i(13, 9)), 50.0, "green")]
	_turret_update(0.05)
	var ok_powerfire: bool = _projectiles.size() >= 1 and float(_turrets[pti]["fuel"]) == 0.0 and bool(_turrets[pti]["powered"])
	_report("powered turret fires with no wine", ok_powerfire); fails += int(not ok_powerfire)
	# Turning the generator off (or draining oil) un-powers the turret.
	_generators[gi]["on"] = false
	_compute_power(0.01)
	var ok_off: bool = not _is_powered(Vector2i(13, 12)) and _energized.is_empty()
	_report("generator off cuts the network", ok_off); fails += int(not ok_off)
	# Electric bulb only counts as a light while powered.
	_generators[gi]["on"] = true
	var blix := _cell_index(Vector2i(11, 11)); _set_terrain(Vector2i(11, 11), Terrain.BULB)
	_lamps[blix] = {"kind": "electric", "life": 0.0, "dead": false}
	_compute_power(0.01)
	var ok_bulb_on: bool = _light_sources().size() >= 1
	_generators[gi]["on"] = false; _compute_power(0.01)
	var ok_bulb_off: bool = _light_sources().is_empty()
	_report("electric bulb lights only when powered", ok_bulb_on and ok_bulb_off); fails += int(not (ok_bulb_on and ok_bulb_off))
	# Pour oil from a cup into the generator.
	_resources = _default_inventory(); _resources["cup_oil"] = 1
	_generators[gi]["oil"] = 0
	_generator_fuel(gi)
	var ok_genfuel: bool = int(_generators[gi]["oil"]) == 1 and _inv("cup_oil") == 0 and _inv("cup") == 1
	_report("pour berry oil into generator", ok_genfuel); fails += int(not ok_genfuel)
	for cc in [Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12), Vector2i(13, 12), Vector2i(11, 11)]:
		_set_terrain(cc, Terrain.GRASS)
	_generators.clear(); _lamps.clear(); _turrets.clear(); _monsters = []; _projectiles = []
	_is_night = false; _energized.clear(); _resources = _default_inventory()

	# === Phase 8: plumbing + auto-watering + fish aquarium ===
	# Pipes touching the water carry it along the network.
	for cy in range(28, 33):
		for cx in range(35, 44):
			_set_terrain(Vector2i(cx, cy), Terrain.GRASS)
	_set_terrain(Vector2i(35, 30), Terrain.WATER)
	_set_terrain(Vector2i(36, 30), Terrain.PIPE)
	_set_terrain(Vector2i(37, 30), Terrain.PIPE)
	_compute_water()
	var ok_pipe: bool = _watered.has(_cell_index(Vector2i(36, 30))) and _watered.has(_cell_index(Vector2i(37, 30))) \
		and _is_piped_water(Vector2i(38, 30)) and not _is_piped_water(Vector2i(43, 30))
	_report("pipes carry pool water along the network", ok_pipe); fails += int(not ok_pipe)
	# Sprinkler fed by a pipe auto-waters a nearby planter.
	_sprinklers.clear(); _planters.clear()
	var spi := _cell_index(Vector2i(38, 30)); _set_terrain(Vector2i(38, 30), Terrain.SPRINKLER); _sprinklers[spi] = {}
	var plw := _cell_index(Vector2i(38, 31)); _set_terrain(Vector2i(38, 31), Terrain.PLANTER)
	_planters[plw] = {"planted": true, "berries": 0, "grow": 0.0, "wet": 0.0, "fert": 0}
	_utility_tick(0.1)
	var ok_sprink: bool = float(_planters[plw]["wet"]) > 0.0
	_report("sprinkler auto-waters planters", ok_sprink); fails += int(not ok_sprink)
	# Aquarium: deposit fish, pour water, feed a worm.
	_aquariums.clear()
	var aqi := _cell_index(Vector2i(40, 30)); _set_terrain(Vector2i(40, 30), Terrain.AQUARIUM)
	_aquariums[aqi] = {"males": 0, "females": 0, "eggs": 0, "quality": 100.0, "water": 0, "feed": 0.0, "breed": 0.0}
	_resources = _default_inventory(); _resources["fish_m"] = 1; _resources["fish_f"] = 1; _resources["cup_water"] = 1; _resources["worm"] = 1
	_aquarium_add_fish(aqi, "m"); _aquarium_add_fish(aqi, "f"); _aquarium_water(aqi); _aquarium_feed(aqi)
	var ok_aqset: bool = int(_aquariums[aqi]["males"]) == 1 and int(_aquariums[aqi]["females"]) == 1 \
		and int(_aquariums[aqi]["water"]) == 1 and float(_aquariums[aqi]["feed"]) > 0.0 and _inv("glass_jar") == 1
	_report("aquarium stocks fish + water + feed", ok_aqset); fails += int(not ok_aqset)
	# Overstocked, unfiltered tank fouls to zero and the fish die.
	_aquariums[aqi] = {"males": 8, "females": 7, "eggs": 3, "quality": 5.0, "water": 5, "feed": 0.0, "breed": 0.0}
	_aquarium_tick(_aquariums[aqi], Vector2i(40, 30), 1.0)
	var ok_aqdeath: bool = int(_aquariums[aqi]["males"]) == 0 and int(_aquariums[aqi]["females"]) == 0
	_report("overstocked tank poisons its fish", ok_aqdeath); fails += int(not ok_aqdeath)
	# A filtered (powered + piped), fed tank with both sexes breeds new fish.
	_generators.clear()
	var agi := _cell_index(Vector2i(40, 29)); _set_terrain(Vector2i(40, 29), Terrain.GENERATOR)
	_generators[agi] = {"oil": 5, "on": true, "drain": 0.0}
	_set_terrain(Vector2i(42, 30), Terrain.WATER); _set_terrain(Vector2i(41, 30), Terrain.PIPE)
	_aquariums[aqi] = {"males": 1, "females": 1, "eggs": 0, "quality": 90.0, "water": 15, "feed": 100000.0, "breed": 0.0}
	_compute_power(0.01); _compute_water()
	var aq_before := int(_aquariums[aqi]["males"]) + int(_aquariums[aqi]["females"])
	# Step in small slices so the filter keeps pace (big slices can overstock-wipe).
	for _bk in range(90):
		_aquarium_tick(_aquariums[aqi], Vector2i(40, 30), 1.0)
	# Breeding shows up as more fish and/or eggs than we started with.
	var ok_breed: bool = (int(_aquariums[aqi]["males"]) + int(_aquariums[aqi]["females"]) + int(_aquariums[aqi]["eggs"])) > aq_before
	_report("filtered fed tank breeds fish", ok_breed); fails += int(not ok_breed)
	# Tidy.
	for cy2 in range(28, 33):
		for cx2 in range(35, 44):
			_set_terrain(Vector2i(cx2, cy2), Terrain.GRASS)
	_sprinklers.clear(); _planters.clear(); _aquariums.clear(); _generators.clear()
	_energized.clear(); _watered.clear(); _resources = _default_inventory()

	# === Phase 9: new traps ===
	_is_night = true; _traps.clear(); _peels = []; _monsters = []; _projectiles = []; _generators.clear()
	# Land mine: a croc stepping on it sets off a blast, consuming the mine.
	var mi := _cell_index(Vector2i(45, 45)); _set_terrain(Vector2i(45, 45), Terrain.LAND_MINE)
	_traps[mi] = {"type": "land_mine"}
	_monsters = [_mk_croc(_cell_center_world(Vector2i(45, 45)), 50.0, "green")]
	var mhp0: float = _monsters[0]["hp"]
	_trap_update(0.1)
	var ok_mine: bool = _monsters[0]["hp"] < mhp0 and not _traps.has(mi) and _terrain_at(Vector2i(45, 45)) == Terrain.GRASS
	_report("land mine explodes + is spent", ok_mine); fails += int(not ok_mine)
	# Peel launcher: load a peel, fire it (wears the launcher), drop a peel on hit.
	_traps.clear(); _projectiles = []; _peels = []
	for cx in range(40, 47):
		_set_terrain(Vector2i(cx, 45), Terrain.GRASS)
	var pli2 := _cell_index(Vector2i(40, 45)); _set_terrain(Vector2i(40, 45), Terrain.PEEL_LAUNCHER)
	_traps[pli2] = {"type": "peel_launcher", "hp": 8, "ammo": 0, "cd": 0.0}
	_resources = _default_inventory(); _resources["banana_peel"] = 1
	_peel_launcher_load(pli2)
	var ok_peelload: bool = int(_traps[pli2]["ammo"]) == 1 and _inv("banana_peel") == 0
	_monsters = [_mk_croc(_cell_center_world(Vector2i(43, 45)), 50.0, "green")]
	_trap_update(0.1)
	var ok_peelfire: bool = _projectiles.size() >= 1 and _projectiles[0]["kind"] == "peel" \
		and int(_traps[pli2]["ammo"]) == 0 and int(_traps[pli2]["hp"]) == 7
	for _pk in range(25):
		_update_projectiles(0.03)
	var ok_peeldrop: bool = _peels.size() >= 1
	_report("peel launcher fires + drops a peel", ok_peelload and ok_peelfire and ok_peeldrop); fails += int(not (ok_peelload and ok_peelfire and ok_peeldrop))
	# A croc that touches the dropped peel is stunned (and the peel is used up).
	var peelpos: Vector2 = _peels[0]["pos"]
	_monsters = [_mk_croc(peelpos, 50.0, "green")]
	_trap_update(0.05)
	var ok_peelstun: bool = float(_monsters[0]["stun_t"]) > 0.0 and _peels.is_empty()
	# Stun freezes movement.
	var spos: Vector2 = _monsters[0]["pos"]
	_player_pos = spos + Vector2(300, 0)
	_monster_update(0.05)
	var ok_stunmove: bool = (_monsters[0]["pos"] as Vector2).distance_to(spos) < 0.5
	_report("dropped peel stuns + freezes a croc", ok_peelstun and ok_stunmove); fails += int(not (ok_peelstun and ok_stunmove))
	# Repair a worn peel launcher.
	_traps[pli2]["hp"] = 3; _resources = _default_inventory(); _resources["wood"] = 5
	_trap_repair(pli2)
	var ok_traprepair: bool = int(_traps[pli2]["hp"]) == TRAP_MAX_HP["peel_launcher"]
	_report("worn trap repairs", ok_traprepair); fails += int(not ok_traprepair)
	# Electric fence zaps an adjacent croc only while powered.
	_traps.clear(); _generators.clear(); _monsters = []; _energized.clear()
	var efi := _cell_index(Vector2i(38, 45)); _set_terrain(Vector2i(38, 45), Terrain.ELECTRIC_FENCE)
	_traps[efi] = {"type": "electric_fence", "cd": 0.0}
	var egi := _cell_index(Vector2i(38, 44)); _set_terrain(Vector2i(38, 44), Terrain.GENERATOR)
	_generators[egi] = {"oil": 3, "on": true, "drain": 0.0}
	_compute_power(0.01)
	_monsters = [_mk_croc(_cell_center_world(Vector2i(39, 45)), 50.0, "green")]
	var efhp0: float = _monsters[0]["hp"]
	_trap_update(0.1)
	var ok_fence_on: bool = _monsters[0]["hp"] < efhp0
	_generators[egi]["on"] = false; _compute_power(0.01)
	_monsters[0]["hp"] = 50.0; _traps[efi]["cd"] = 0.0
	_trap_update(0.1)
	var ok_fence_off: bool = absf(float(_monsters[0]["hp"]) - 50.0) < 0.01
	_report("electric fence zaps only when powered", ok_fence_on and ok_fence_off); fails += int(not (ok_fence_on and ok_fence_off))
	# Trap cap: with 10 traps placed, an 11th is refused.
	for i in range(_terrain.size()):
		if TRAP_TERRAIN.has(_terrain[i]):
			_set_terrain(_index_cell(i), Terrain.GRASS)
	_traps.clear(); _trap_cd.clear(); _generators.clear()
	for i2 in range(10):
		_set_terrain(Vector2i(2 + i2, 48), Terrain.TRAP)
	var ok_trapcount: bool = _count_traps() == 10
	_resources = _default_inventory(); _resources["metal"] = 9; _resources["charcoal"] = 9
	_set_terrain(Vector2i(2, 47), Terrain.WORKBENCH); _set_terrain(Vector2i(3, 47), Terrain.GRASS)
	_cell = Vector2i(3, 48); _player_pos = _cell_center_world(_cell); _monsters = []
	_drag_action = BuildAction.BUILD; _build_struct = "land_mine"
	_apply_build_at(Vector2i(3, 47))
	var ok_trapcap: bool = ok_trapcount and _terrain_at(Vector2i(3, 47)) == Terrain.GRASS
	_report("trap cap stops the 11th trap", ok_trapcap); fails += int(not ok_trapcap)
	# Tidy.
	for i3 in range(_terrain.size()):
		if TRAP_TERRAIN.has(_terrain[i3]) or _terrain[i3] == Terrain.WORKBENCH:
			_set_terrain(_index_cell(i3), Terrain.GRASS)
	_set_terrain(Vector2i(38, 44), Terrain.GRASS)
	_traps.clear(); _trap_cd.clear(); _peels = []; _generators.clear(); _monsters = []; _projectiles = []
	_is_night = false; _energized.clear(); _build_struct = ""; _drag_action = BuildAction.NONE
	_resources = _default_inventory()

	# === Phase 10: croc drops + required-progression ramp ===
	# A slain croc drops a bone (and often hide) as auto-collect loot.
	_is_night = true; _monsters = []; _ground_items = []; _turrets.clear()
	_monsters = [_mk_croc(_cell_center_world(Vector2i(30, 40)), 1.0, "green")]
	_hurt_croc(_monsters[0], 999.0, Vector2.ZERO, 0.0, "player")
	_monster_update(0.05)
	var ok_drop: bool = false
	for g in _ground_items:
		if g["kind"] == "bone":
			ok_drop = true
	_report("slain crocs drop bone/hide loot", ok_drop); fails += int(not ok_drop)
	_ground_items = []; _monsters = []
	# Bone meal crafts into fertilizer; hide armor raises player armor.
	_resources = _default_inventory(); _resources["bone"] = 2
	_craft("bone_meal")
	var ok_bonemeal: bool = _inv("fertilizer") == 1 and _inv("bone") == 0
	_init_progression(); _gear_armor = 0.0; _resources = _default_inventory(); _resources["croc_hide"] = 3
	var arm0: float = _p_armor
	_craft("hide_armor")
	var ok_hidearmor: bool = _inv("croc_hide") == 0 and _p_armor > arm0
	_report("croc drops craft into fertilizer + armor", ok_bonemeal and ok_hidearmor); fails += int(not (ok_bonemeal and ok_hidearmor))
	# Required-progression: an UNPOWERED turret burns wine faster on a deep night
	# than a POWERED one (which burns none).
	_turrets.clear(); _energized.clear()
	_nights_survived = POWER_DEMAND_NIGHT * 2   # push the night index deep
	var ut := _new_turret(Vector2i(5, 5)); ut["type"] = "sniper"; ut["powered"] = false; ut["fuel"] = 100.0
	_turret_spend_fuel(ut)
	var deep_burn: float = 100.0 - float(ut["fuel"])
	var ut2 := _new_turret(Vector2i(6, 6)); ut2["type"] = "sniper"; ut2["powered"] = false; ut2["fuel"] = 100.0
	_nights_survived = 0
	_turret_spend_fuel(ut2)
	var early_burn: float = 100.0 - float(ut2["fuel"])
	var pt2 := _new_turret(Vector2i(7, 7)); pt2["type"] = "sniper"; pt2["powered"] = true; pt2["fuel"] = 100.0
	_turret_spend_fuel(pt2)
	var ok_ramp: bool = deep_burn > early_burn and absf(float(pt2["fuel"]) - 100.0) < 0.01
	_report("deep-night wine burn ramps; powered turrets free", ok_ramp); fails += int(not ok_ramp)
	_turrets.clear(); _monsters = []; _ground_items = []; _is_night = false
	_nights_survived = 0; _init_progression(); _day = 1; _resources = _default_inventory()

	# --- Save / load round-trip (world + player + base machines + storage) ---
	_reset_game()
	_resources["wood"] = 42
	_set_terrain(_cell + Vector2i(3, 0), Terrain.STORAGE)
	var sl_sidx := _cell_index(_cell + Vector2i(3, 0))
	_storage[sl_sidx] = {"wood": 7}
	_day = 4; _nights_survived = 3; _level = 5; _xp = 9
	_set_terrain(_cell + Vector2i(2, 0), Terrain.TURRET)
	var sl_tcell := _cell_index(_cell + Vector2i(2, 0))
	_turrets[sl_tcell] = _new_turret(_cell + Vector2i(2, 0))
	_configure_turret(sl_tcell, "sniper")
	var sl_snap := _serialize_state()
	# Exercise real Variant disk (de)serialization via a throwaway temp path,
	# so the player's actual save is never touched by the test.
	var sl_tmp := "user://__selftest_roundtrip.save"
	var sl_wf := FileAccess.open(sl_tmp, FileAccess.WRITE); sl_wf.store_var(sl_snap); sl_wf.close()
	var sl_rf := FileAccess.open(sl_tmp, FileAccess.READ); var sl_back: Variant = sl_rf.get_var(); sl_rf.close()
	var sl_dir := DirAccess.open("user://")
	if sl_dir: sl_dir.remove("__selftest_roundtrip.save")
	var ok_ser: bool = sl_back is Dictionary
	# Scramble the live state, then restore from the round-tripped copy.
	_resources["wood"] = 0; _day = 99; _nights_survived = 0; _level = 1; _turrets.clear(); _storage.clear()
	if ok_ser: _deserialize_state(sl_back as Dictionary)
	var ok_round: bool = ok_ser and _resources["wood"] == 42 and _day == 4 and _nights_survived == 3 \
		and _level == 5 and _turrets.has(sl_tcell) and String(_turrets[sl_tcell]["type"]) == "sniper" \
		and _storage.has(sl_sidx) and int(_storage[sl_sidx]["wood"]) == 7
	_report("save/load round-trip restores world+player+machines", ok_round); fails += int(not ok_round)

	# --- Title-screen state machine ---
	_enter_splash()
	var ok_splash: bool = _app_state == AppState.SPLASH and _splash_root.visible and _menu_layer.visible
	_tick_splash(SPLASH_HOLD + SPLASH_FADE + 0.2)
	ok_splash = ok_splash and _app_state == AppState.MENU
	_report("splash holds then fades into the menu", ok_splash); fails += int(not ok_splash)

	_enter_menu()
	var ok_menu: bool = _app_state == AppState.MENU and _menu_root.visible and not _settings_root.visible
	_report("main menu visible with buttons", ok_menu and _menu_btns.get_child_count() >= 3); fails += int(not (ok_menu and _menu_btns.get_child_count() >= 3))

	_open_settings(AppState.MENU)
	var ok_settings: bool = _app_state == AppState.SETTINGS and _settings_root.visible and not _menu_root.visible
	_report("settings overlay opens from menu", ok_settings); fails += int(not ok_settings)
	_close_settings()
	var ok_back: bool = _app_state == AppState.MENU and _menu_root.visible
	_report("settings Back returns to the menu", ok_back); fails += int(not ok_back)

	_enter_playing()
	var ok_play: bool = _app_state == AppState.PLAYING and not _menu_layer.visible
	_report("entering play hides the menu layer", ok_play); fails += int(not ok_play)

	_app_state = AppState.PLAYING; _set_overlay("none")
	_turrets.clear(); _storage.clear(); _monsters = []
	_nights_survived = 0; _init_progression(); _day = 1; _resources = _default_inventory()

	# --- INVARIANT (a): a sapper crosses a fully sealed wall ring ---------------
	# Seal a stone-wall ring around the Tree, drop a burrowed sapper just outside
	# it, and run the sim. The tunnel field must carry it UNDER the ring and
	# surface it INSIDE, next to the Tree -- proving the wall ring is no defense
	# against the sapper (decision #15).
	_reset_tree_state()
	_monsters.clear()
	var tc := _tree_center_cell()
	var ring_r := 3
	for ry in range(tc.y - ring_r, tc.y + ring_r + 1):
		for rx in range(tc.x - ring_r, tc.x + ring_r + 1):
			if absi(rx - tc.x) == ring_r or absi(ry - tc.y) == ring_r:
				_set_terrain(Vector2i(rx, ry), Terrain.STONE_WALL)
	_invalidate_flow_fields()
	_ensure_flow_fields()
	# Sapper starts outside the sealed ring, burrowed.
	var sap_start := _cell_center_world(tc + Vector2i(0, ring_r + 2))
	var sapper := _croc_for_night(sap_start, 6, "brown")
	# Confirm the ring really is sealed: every perimeter cell is a wall (no gap).
	var ring_sealed := true
	for ry2 in range(tc.y - ring_r, tc.y + ring_r + 1):
		for rx2 in range(tc.x - ring_r, tc.x + ring_r + 1):
			if absi(rx2 - tc.x) == ring_r or absi(ry2 - tc.y) == ring_r:
				if _terrain_at(Vector2i(rx2, ry2)) != Terrain.STONE_WALL:
					ring_sealed = false
	_monsters = [sapper]
	_is_night = true
	var surfaced_inside := false
	for _step in range(600):
		_monster_update(0.05)
		if _monsters.is_empty():
			break
		var sm: Dictionary = _monsters[0]
		if not bool(sm.get("dig", true)):
			# Surfaced: must be INSIDE the ring (Chebyshev to Tree center < ring_r).
			if _chebyshev(_world_to_cell(sm["pos"]), tc) < ring_r:
				surfaced_inside = true
			break
	var ok_sapper: bool = ring_sealed and surfaced_inside
	_report("sapper tunnels under a sealed wall ring and surfaces inside", ok_sapper); fails += int(not ok_sapper)
	_monsters.clear()
	_is_night = false
	_reset_tree_state()

	# --- INVARIANT (b): tier-gated items lock below tier, unlock at/above -------
	# Build path (structure), turret-type path, and the helper all agree; a
	# downgrade re-locks.
	_tree_tier = 1
	var ok_gate_locked: bool = not _struct_tier_ok("generator") and not _turret_tier_ok("rocket") \
		and not _struct_tier_ok("reinforced_wall")
	_tree_tier = 3
	var ok_gate_open: bool = _struct_tier_ok("generator") and _turret_tier_ok("rocket") \
		and _struct_tier_ok("kiln") and _turret_tier_ok("drill")
	_tree_tier = 5
	var ok_gate_top: bool = _struct_tier_ok("reinforced_wall")
	# A downgrade re-locks the tier-3 generator.
	_tree_tier = 2
	var ok_gate_relock: bool = not _struct_tier_ok("generator") and _struct_tier_ok("kiln")
	# Enforced in the real build path: a tier-2 tree can't place a generator.
	_resources = {"metal": 99, "bamboo": 99, "glue": 99, "wooden_rod": 99}
	_monsters.clear()
	var gen_cell := _tree_center_cell() + Vector2i(8, 0)
	# Stand the player by a workbench (generator is a bench structure) and clear
	# the build target -- isolate the TIER gate from the other build guards.
	_cell = gen_cell + Vector2i(0, 2)
	_player_pos = _cell_center_world(_cell)
	_set_terrain(_cell + Vector2i(1, 0), Terrain.WORKBENCH)
	_set_terrain(gen_cell, Terrain.GRASS)
	_build_struct = "generator"
	_drag_action = BuildAction.BUILD
	_tree_tier = 2
	_apply_build_at(gen_cell)
	var ok_gate_build: bool = _terrain_at(gen_cell) != Terrain.GENERATOR
	_tree_tier = 3
	_apply_build_at(gen_cell)
	var ok_gate_build_ok: bool = _terrain_at(gen_cell) == Terrain.GENERATOR
	_clear_cell_runtime_state(_cell_index(gen_cell)); _set_terrain(gen_cell, Terrain.GRASS)
	_set_terrain(_cell + Vector2i(1, 0), Terrain.GRASS)
	_build_struct = ""; _drag_action = BuildAction.NONE
	var ok_tier_gate: bool = ok_gate_locked and ok_gate_open and ok_gate_top and ok_gate_relock \
		and ok_gate_build and ok_gate_build_ok
	_report("tier-gated item blocked below tier, buildable at/above", ok_tier_gate); fails += int(not ok_tier_gate)
	_resources = _default_inventory()

	# --- INVARIANT (c): WIN sets the halt/end state ----------------------------
	# Clearing the last Den at Tree tier >= 3 must flip _won AND raise the
	# victory halt (banner + sim freeze), not merely toast.
	_clear_den_terrain(); _dens.clear(); _won = false
	if _victory_layer: _victory_layer.visible = false
	_tree_tier = 3
	var win_den := _create_den(Vector2i(45, 45), 2, 0)
	_damage_den_at(Vector2i(45, 45), 9999.0)
	var ok_win_halt: bool = _won and _dens.is_empty() \
		and (_victory_layer == null or _victory_layer.visible) and not _build_mode
	_report("WIN sets the halt/end state (victory banner)", ok_win_halt); fails += int(not ok_win_halt)
	# A fresh run clears the win halt.
	_reset_game()
	var ok_win_reset: bool = not _won and (_victory_layer == null or not _victory_layer.visible)
	_report("new run clears the victory halt", ok_win_reset); fails += int(not ok_win_reset)

	# --- INVARIANT (d): casing has a real consumer recipe ----------------------
	# Casing -> gunpowder closes the reclaim loop by MECHANISM (not a hand ledger).
	var ok_casing_recipe: bool = CRAFT_RECIPES.has("casing_powder") \
		and CRAFT_RECIPES["casing_powder"]["cost"].has("casing") \
		and String(CRAFT_RECIPES["casing_powder"]["out"]) == "gunpowder"
	_resources = _default_inventory()
	_resources["casing"] = 6
	_resources["gunpowder"] = 0
	_craft("casing_powder")
	var ok_casing_craft: bool = _inv("casing") == 3 and _inv("gunpowder") == 2
	var ok_casing: bool = ok_casing_recipe and ok_casing_craft
	_report("casing is consumed by a real gunpowder recipe", ok_casing); fails += int(not ok_casing)
	_resources = _default_inventory()

	# --- VISUAL IDENTITY (procedural-art editor) -------------------------------
	# INVARIANT: every inventory item bakes a DISTINCT, non-trivial 24px icon.
	# Proves _bake_item_icons paints a real per-id silhouette (not the old shared
	# disc) at the new source size -- a duplicate signature or a near-empty image
	# would mean two items collapsed to the same art, the exact regression the
	# shape-language rewrite kills. Signature = opaque-pixel-count + a coarse hash.
	var icon_sigs := {}
	var ok_icon_size := true
	var ok_icon_nonempty := true
	var ok_icon_distinct := true
	var icon_dupes := []
	for item_id in INV_ORDER:
		var tex: ImageTexture = _item_icons.get(item_id, null)
		if tex == null:
			ok_icon_nonempty = false
			continue
		var img := tex.get_image()
		if img.get_width() != 24 or img.get_height() != 24:
			ok_icon_size = false
		var opaque := 0
		for yy in range(img.get_height()):
			for xx in range(img.get_width()):
				if img.get_pixel(xx, yy).a > 0.0:
					opaque += 1
		if opaque < 8:
			ok_icon_nonempty = false   # an almost-blank icon is not legible
		# Signature spans shape AND color, so two same-shaped items in different
		# families still count as distinct (their tint carries the family).
		var key := _img_signature(img)
		if icon_sigs.has(key):
			ok_icon_distinct = false   # two items baked identical art
			icon_dupes.append("%s==%s" % [item_id, icon_sigs[key]])
		icon_sigs[key] = item_id
	if not icon_dupes.is_empty():
		push_warning("item icons collided: %s" % str(icon_dupes))
	_report("every item icon bakes at 24px source", ok_icon_size); fails += int(not ok_icon_size)
	_report("every item icon is non-empty (legible mass)", ok_icon_nonempty); fails += int(not ok_icon_nonempty)
	_report("every item icon is a distinct silhouette", ok_icon_distinct); fails += int(not ok_icon_distinct)
	# INVARIANT: every INV_ORDER id maps to a category tint (slot border + base).
	var ok_icon_tint := true
	for item_id in INV_ORDER:
		if not ITEM_CATEGORY_TINT.has(item_id):
			ok_icon_tint = false
	_report("every item icon maps to a category tint", ok_icon_tint); fails += int(not ok_icon_tint)

	# INVARIANT: each croc ROLE bakes a DISTINCT silhouette, not just a tint swap.
	# Render every role on the SAME body/belly so any difference is pure shape;
	# all 9 role bakes (incl. the flanker variant) must differ pairwise -- that's
	# what makes role readable at a glance and the split-aggro telegraph work.
	var test_body := Color(0.5, 0.5, 0.5)
	var test_belly := Color(0.8, 0.8, 0.8)
	var role_sigs := {}
	var ok_role_distinct := true
	var roles := ["melee", "wrecker", "digger", "healer", "reviver", "fire", "ice", "poison"]
	for r in roles:
		var rim := _bake_croc_img(test_body, test_belly, r)
		var rsig := _img_signature(rim)
		if role_sigs.has(rsig):
			ok_role_distinct = false
		role_sigs[rsig] = r
	# The flanker (yellow) baker must differ from the grunt baseline too.
	var flank_sig := _img_signature(_bake_croc_flanker_img(test_body, test_belly))
	if role_sigs.has(flank_sig):
		ok_role_distinct = false
	_report("each croc role bakes a distinct silhouette", ok_role_distinct); fails += int(not ok_role_distinct)
	# INVARIANT: a real croc roster yields 9 distinct silhouettes (color + shape).
	var roster_sigs := {}
	var ok_roster_distinct := true
	for type in CROC_DEFS:
		var def: Dictionary = CROC_DEFS[type]
		var cim := _bake_croc_flanker_img(def["body"], def["belly"]) if type == "yellow" \
			else _bake_croc_img(def["body"], def["belly"], String(def["role"]))
		var csig := _img_signature(cim)
		if roster_sigs.has(csig):
			ok_roster_distinct = false
		roster_sigs[csig] = type
	_report("the 9-croc roster bakes 9 distinct sprites", ok_roster_distinct); fails += int(not ok_roster_distinct)

	# INVARIANT: Den maturity escalates young -> maturing -> mature by state, and
	# each stage has its own art. Proves the at-a-glance threat read is driven by
	# real state (not a hand flag) and that the warm/evolved overlays exist and
	# differ from the quiet base tile.
	var ok_stage := \
		_den_stage({"size": 2, "maturity": 0}) == "young" \
		and _den_stage({"size": 2, "maturity": 1}) == "maturing" \
		and _den_stage({"size": 2, "maturity": 2}) == "maturing" \
		and _den_stage({"size": 3, "maturity": 3}) == "mature"
	_report("Den stage escalates young->maturing->mature by state", ok_stage); fails += int(not ok_stage)
	var base_den_sig := _img_signature(_tiles[Terrain.CROC_DEN].get_image())
	var warm_sig := _img_signature(_tex_den_warm.get_image())
	var evolved_sig := _img_signature(_tex_den_evolved.get_image())
	var ok_den_art := _tex_den_warm != null and _tex_den_evolved != null \
		and base_den_sig != warm_sig and warm_sig != evolved_sig and base_den_sig != evolved_sig
	_report("Den stages bake three distinct tile arts", ok_den_art); fails += int(not ok_den_art)
	# INVARIANT: an evolved Den's footprint grows 2x2 -> 3x3 (4 -> 9 cells).
	var ok_den_grow: bool = _den_cells(Vector2i(5, 5), 2).size() == 4 \
		and _den_cells(Vector2i(5, 5), 3).size() == 9
	_report("an evolved Den footprint grows 2x2 to 3x3", ok_den_grow); fails += int(not ok_den_grow)

	# INVARIANT: the Mother Tree tile re-bakes its canopy color per tier (§5) --
	# brightening GREEN as it climbs. Bake tier 1 vs tier 5 and require different
	# art, and require the tier-5 canopy to be the lighter of the two palettes.
	_bake_mother_tree_tile(1)
	var tree_t1_sig := _img_signature(_tiles[Terrain.MOTHER_TREE].get_image())
	_bake_mother_tree_tile(5)
	var tree_t5_sig := _img_signature(_tiles[Terrain.MOTHER_TREE].get_image())
	var ok_tree_tier_art: bool = tree_t1_sig != tree_t5_sig \
		and TREE_LEAF_TIERS[4].get_luminance() > TREE_LEAF_TIERS[0].get_luminance()
	_bake_mother_tree_tile(_tree_tier)   # restore the live tier's art
	_report("Mother Tree canopy re-bakes brighter per tier", ok_tree_tier_art); fails += int(not ok_tree_tier_art)

	# === Editor 8: TECH hub + onboarding ===

	# INVARIANT: each TECH_ROWS branch is locked iff the Tree tier is below its gate.
	# This is the at-a-glance "what's still locked" read; it must track the REAL tier
	# (not a hand flag), so iterate tier 1..5 and require row.unlocked == (tier>=gate).
	var ok_tech_gate := true
	var saved_tier := _tree_tier
	for tier_v in range(1, 6):
		_tree_tier = tier_v
		for row in TECH_ROWS:
			var gate := int(row["tier"])
			var unlocked := _tree_tier >= gate
			if unlocked != (tier_v >= gate):
				ok_tech_gate = false
	_tree_tier = saved_tier
	_report("TECH branch rows lock/unlock by Tree tier", ok_tech_gate); fails += int(not ok_tech_gate)

	# INVARIANT: every branch hue + the 5 gates are present and distinct gates 1..5,
	# so the data-driven column can never silently drop or double a branch.
	var ok_tech_data := TECH_ROWS.size() == 5
	var seen_gates := {}
	for row in TECH_ROWS:
		seen_gates[int(row["tier"])] = true
		if not TECH_BRANCH_HUE.has(String(row["branch"])):
			ok_tech_data = false
	if seen_gates.size() != 5:
		ok_tech_data = false
	_report("TECH_ROWS covers 5 distinct gates with branch hues", ok_tech_data); fails += int(not ok_tech_data)

	# INVARIANT: HP-state color is hard-banded -- green >=50%, amber 25-50%, red <25%.
	# The whole "danger reads instantly" premise rests on these exact thresholds.
	var ok_hp_band: bool = _hp_color(1.0) == HP_GREEN and _hp_color(0.5) == HP_GREEN \
		and _hp_color(0.49) == HP_AMBER and _hp_color(0.25) == HP_AMBER \
		and _hp_color(0.24) == HP_RED and _hp_color(0.0) == HP_RED
	_report("HP color bands hard-switch at 50%/25%", ok_hp_band); fails += int(not ok_hp_band)

	# INVARIANT: an onboarding beat fires at most once ever. _onboard flips the seen
	# flag, so a second call with the SAME id is a no-op (it must not re-queue/re-show).
	_onboard_seen = {}; _msg_queue = []; _msg = ""; _msg_timer = 0.0
	_onboard("welcome", "ONE", 6.0)
	var ok_onboard_first: bool = _msg == "ONE" and _msg_onboard and _onboard_seen.get("welcome", false)
	_msg = ""; _msg_timer = 0.0
	_onboard("welcome", "TWO", 6.0)   # same id -> suppressed
	var ok_onboard_once: bool = _msg == "" and _msg_queue.is_empty()
	_report("an onboarding beat fires at most once", ok_onboard_first and ok_onboard_once); fails += int(not (ok_onboard_first and ok_onboard_once))

	# INVARIANT: a beat raised while the banner is busy is QUEUED, not dropped, and
	# drains the instant the banner frees (so a tutorial line behind a threat/SFX
	# message still lands). Mirrors the _process_world drain.
	_onboard_seen = {}; _msg_queue = []; _set_msg("threat line")   # banner busy (2.5s)
	_onboard("first_thirst", "THIRST", 5.0)
	var ok_queued: bool = _msg == "threat line" and _msg_queue.size() == 1
	_msg_timer = 0.0
	if not _msg_queue.is_empty():
		var qb: Dictionary = _msg_queue.pop_front()
		_set_msg_long(String(qb["text"]), float(qb["secs"]))
	var ok_drained: bool = _msg == "THIRST" and _msg_onboard
	_report("a busy-banner beat queues then drains", ok_queued and ok_drained); fails += int(not (ok_queued and ok_drained))

	# INVARIANT: a tier-up lights the NEW marker (window in the future) and opening
	# the TECH hub acknowledges it (advances _tech_seen_tier, clears the window).
	_tree_tier = 2; _tech_seen_tier = 1
	_tech_new_until = _now_secs() + TECH_NEW_DWELL
	var ok_new_live: bool = _tech_new_until > _now_secs()
	# Simulate the acknowledge-on-open guard from _build_tech_overlay_panel.
	if _tree_tier > _tech_seen_tier:
		_tech_seen_tier = _tree_tier
		_tech_new_until = 0.0
	var ok_new_ack: bool = _tech_seen_tier == 2 and _tech_new_until == 0.0
	_report("tier-up NEW marker lights then clears on open", ok_new_live and ok_new_ack); fails += int(not (ok_new_live and ok_new_ack))

	# INVARIANT: onboarding + TECH-discovery state survives a save/load round-trip
	# (additive fields), so the tutorial never replays on a resumed game.
	_onboard_seen = {"welcome": true, "casings": true}; _tech_seen_tier = 3
	var ob_snap := _serialize_state()
	_onboard_seen = {}; _tech_seen_tier = 1
	_deserialize_state(ob_snap)
	var ok_ob_round: bool = _onboard_seen.get("welcome", false) and _onboard_seen.get("casings", false) \
		and _onboard_seen.size() == 2 and _tech_seen_tier == 3
	_report("onboarding/tech state round-trips through save", ok_ob_round); fails += int(not ok_ob_round)

	# INVARIANT: the full-screen TECH hub builds end-to-end without error and its body
	# is populated (title bar + columns) -- proving the rewrite off _right_vbox onto the
	# dedicated layer actually renders. Also: closing it hides the layer + clears overlay.
	var ok_tech_build := false
	if _tech_body != null:
		_tree_tier = 2; _sap = 10.0
		_active_overlay = Overlay.TECH
		_build_tech_overlay_panel()
		ok_tech_build = _tech_body.get_child_count() >= 3   # title bar + sep + columns HBox
		_close_active_overlay()
		ok_tech_build = ok_tech_build and _active_overlay == Overlay.NONE \
			and (_tech_root == null or not _tech_root.visible)
	_report("TECH hub builds full-screen and closes clean", ok_tech_build); fails += int(not ok_tech_build)

	# Restore the live state these tests scrambled.
	_onboard_seen = {}; _msg_queue = []; _msg = ""; _msg_timer = 0.0; _msg_onboard = false
	_tech_new_until = 0.0; _tech_seen_tier = 1; _tree_tier = saved_tier; _sap = 0.0

	_app_state = AppState.PLAYING; _set_overlay("none")
	_turrets.clear(); _storage.clear(); _monsters = []
	_fx = []; _dusk_active = false; _tier_glow = 0.0; _clock_flash = 0.0
	_dusk_telegraphed = false; _incoming_telegraphed = false
	_nights_survived = 0; _init_progression(); _day = 1; _resources = _default_inventory()

	print("SELFTEST DONE, failures=%d" % fails)
	get_tree().quit()


# A coarse pixel signature for a baked Image: opaque-pixel count + a position-
# weighted hash. Two images with the same silhouette share a signature; any
# shape difference (the whole point of the per-role / per-item bakes) changes it.
# Used only by the visual-identity selftest invariants.
func _img_signature(img: Image) -> String:
	var opaque := 0
	var sig := 0
	for yy in range(img.get_height()):
		for xx in range(img.get_width()):
			var px := img.get_pixel(xx, yy)
			if px.a > 0.0:
				opaque += 1
				var qr := int(px.r * 7.0)
				var qg := int(px.g * 7.0)
				var qb := int(px.b * 7.0)
				sig = (sig * 31 + (xx * 7 + yy * 13) + (qr * 3 + qg * 5 + qb * 11)) % 1000000007
	return "%d:%d" % [opaque, sig]


func _report(name: String, ok: bool) -> void:
	print("PASS  " if ok else "FAIL  ", name)


func _mk_croc(pos: Vector2, hp: float, type: String = "green") -> Dictionary:
	return {
		"pos": pos, "hp": hp, "max_hp": hp, "type": type, "role": CROC_DEFS[type]["role"],
		"attack": MONSTER_HIT, "speed": CROC_SPEED, "armor": 0.0, "regen": 0.0,
		"xp": MON_XP_BASE, "atk_cd": 0.0, "brk_cd": 0.0, "shoot_cd": RANGED_CD,
		"kb": Vector2.ZERO, "flash": 0.0,
		"dig": CROC_DEFS[type]["role"] == "digger", "revived": false, "dead_t": 0.0, "healing": false,
		"slow_t": 0.0, "stun_t": 0.0, "marked": false, "killer": "",
		"target": "tree" if String(CROC_DEFS[type].get("aggro", "")) == "tree" else "player",
		"dmg_log": {}, "debuff_by": {},
	}


func _demo_setup() -> void:
	var b := _cell
	_set_terrain(b + Vector2i(1, 0), Terrain.STORAGE)
	_storage[_cell_index(b + Vector2i(1, 0))] = {"wood": 12, "stone": 4, "banana": 6, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_set_terrain(b + Vector2i(2, 0), Terrain.WORKBENCH)
	_set_terrain(b + Vector2i(-1, 0), Terrain.WOOD_WALL)
	_set_terrain(b + Vector2i(-1, -1), Terrain.STONE_WALL)
	_set_terrain(b + Vector2i(0, 1), Terrain.DOOR)
	_set_terrain(b + Vector2i(1, 1), Terrain.FLOOR)
	_resources = {"wood": 8, "stone": 3, "banana": 2, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_facing = Vector2i(1, 0)
	_docked_station = _cell_index(b + Vector2i(1, 0))
	_mark_workspace_dirty()
	queue_redraw()


func _demo_night() -> void:
	_time = 0.85
	_apply_daylight()
	_begin_night()
	# A varied raid for the screenshot: one of several croc types around the base.
	_monsters = []
	var lineup := [
		[Vector2(4, -1), "red"], [Vector2(5, 1), "blue"], [Vector2(-4, 1), "pink"],
		[Vector2(0, 5), "white"], [Vector2(2, 5), "green"], [Vector2(-3, 4), "black"],
		[Vector2(-5, -2), "purple"],
	]
	for entry in lineup:
		_monsters.append(_mk_croc(_player_pos + (entry[0] as Vector2) * CELL_SIZE, MONSTER_HP, entry[1]))
	_monsters[5]["hp"] = 0.0   # black croc lying dead, mid-revive
	# A burrowed brown croc approaching (shows as a dirt mound).
	var dug := _mk_croc(_player_pos + Vector2(-2, -4) * CELL_SIZE, MONSTER_HP, "brown")
	_monsters.append(dug)
	_monsters[0]["flash"] = FLASH_TIME              # a croc mid hit-flash
	# Projectiles + a poison cloud mid-scene.
	_projectiles = [
		{"pos": _player_pos + Vector2(2.4, -0.6) * CELL_SIZE, "vel": Vector2(-1, 0.2) * PROJ_SPEED, "kind": "fire"},
		{"pos": _player_pos + Vector2(3.0, 0.6) * CELL_SIZE, "vel": Vector2(-1, -0.1) * PROJ_SPEED, "kind": "snow"},
	]
	_poison_clouds = [{"pos": _player_pos + Vector2(-3.2, 2.0) * CELL_SIZE, "t": 0.8}]
	_apply_heal_auras(0.0)                          # flag the white croc's aura/targets
	_punch_active = true                            # show the punch arm/fist
	_punch_dir = Vector2.RIGHT
	_punch_t = 0.5
	_spark_pos = _fist_pos(); _spark_t = 0.3        # connect spark
	_poofs = [{"pos": _player_pos + Vector2(2, 5) * CELL_SIZE, "t": 0.4}]
	_burn_t = BURN_TIME                             # player on fire (status overlay)
	_slow_t = SLOW_TIME
	_health = _p_max_health * 0.30                  # show the low-health vignette
	_hurt_flash = FLASH_TIME
	_update_juice(0.0)                              # push overlay alphas
	# A little defended base: walls, a door, a turret, and a spike trap.
	_set_terrain(_cell + Vector2i(1, 0), Terrain.WOOD_WALL)
	_set_terrain(_cell + Vector2i(1, 1), Terrain.WOOD_WALL)
	_set_terrain(_cell + Vector2i(1, -1), Terrain.DOOR)
	_set_terrain(_cell + Vector2i(2, -1), Terrain.TURRET)
	_set_terrain(_cell + Vector2i(-1, 2), Terrain.TRAP)
	queue_redraw()


# -----------------------------------------------------------------------------
# Dev affordance: `--shot <path>` renders a frame, saves a PNG, and quits.
# -----------------------------------------------------------------------------
func _handle_shot_arg() -> void:
	var args := OS.get_cmdline_user_args()
	var shot_idx := args.find("--shot")
	if shot_idx != -1 and shot_idx + 1 < args.size():
		var path := args[shot_idx + 1]
		if "--demo" in args:
			_demo_setup()
		if "--night" in args:
			_demo_night()
		if "--roster" in args:
			_time = 0.85; _apply_daylight(); _is_night = true
			_monsters = []
			var i := 0
			for type in CROC_DEFS:
				var cpos := _player_pos + Vector2(-4 + i * 1.0, -3) * CELL_SIZE
				var mc := _mk_croc(cpos, 6.0, type)
				mc["dig"] = false   # show the sprite, not the mound
				_monsters.append(mc)
				i += 1
			queue_redraw()
		if "--levelup" in args:
			_level = 4
			_alloc = {"health": 1, "attack": 1, "speed": 0, "armor": 1, "regen": 0}
			_recompute_player_stats()
			_stat_points = 1
			_active_overlay = Overlay.LEVELUP
			_mark_workspace_dirty()
			_update_status()
		if "--turretfight" in args:
			_time = 0.85; _apply_daylight(); _is_night = true
			_monsters = []; _turrets.clear()
			var setups := [[Vector2i(2, -1), "sniper"], [Vector2i(2, 1), "mg"], [Vector2i(-2, -1), "boxer"], [Vector2i(-2, 1), "adhesive"], [Vector2i(0, -2), "trickster"]]
			for su in setups:
				var tcc: Vector2i = _cell + (su[0] as Vector2i)
				_set_terrain(tcc, Terrain.TURRET)
				var tixx := _cell_index(tcc)
				_turrets[tixx] = _new_turret(tcc)
				_configure_turret(tixx, su[1])
			for o in [Vector2(4, 0), Vector2(4, 2), Vector2(-4, 0), Vector2(0, 4), Vector2(3, -3)]:
				_monsters.append(_mk_croc(_player_pos + (o as Vector2) * CELL_SIZE, MONSTER_HP * 4.0, "green"))
			_monsters[0]["marked"] = true; _monsters[1]["marked"] = true
			_projectiles = [
				{"pos": _player_pos + Vector2(3, 0) * CELL_SIZE, "vel": Vector2(1, 0) * TURRET_PROJ_SPEED, "kind": "snipe", "dmg": 10, "owner": 0},
				{"pos": _player_pos + Vector2(2.5, 1.2) * CELL_SIZE, "vel": Vector2(1, 0.3) * TURRET_PROJ_SPEED, "kind": "bullet", "dmg": 4, "owner": 0},
			]
			var afield := _cell_index(_cell + Vector2i(-2, 1))
			if _turrets.has(afield):
				_turrets[afield]["field"] = _player_pos + Vector2(-4, 1) * CELL_SIZE
			queue_redraw()
		if "--turretsel" in args:
			var tc := _cell + Vector2i(1, 0)
			_set_terrain(tc, Terrain.TURRET)
			var tix := _cell_index(tc)
			_turrets[tix] = _new_turret(tc)
			_docked_station = tix
			_mark_workspace_dirty(); _update_status()
		if "--turretmgr" in args:
			var tc2 := _cell + Vector2i(1, 0)
			_set_terrain(tc2, Terrain.TURRET)
			var tix2 := _cell_index(tc2)
			_turrets[tix2] = _new_turret(tc2)
			_configure_turret(tix2, "sniper")
			_turrets[tix2]["level"] = 5; _turrets[tix2]["points"] = 2
			_turrets[tix2]["xp"] = 7; _turrets[tix2]["hp"] = 9.0; _turrets[tix2]["fuel"] = 64.0
			_docked_station = tix2
			_mark_workspace_dirty(); _update_status()
		if "--craft" in args:
			_resources = _default_inventory()
			_resources["grass"] = 9; _resources["wood"] = 12; _resources["cup_water"] = 2; _resources["cup_juice"] = 1
			_hydration = 46.0
			_build_mode = false
			_mark_workspace_dirty(); _update_status()
		if "--util" in args:
			var jc := _cell + Vector2i(1, 0)
			_set_terrain(jc, Terrain.PLANTER)
			var pidx := _cell_index(jc)
			_planters[pidx] = {"planted": true, "berries": 2, "grow": 0.0, "wet": PLANTER_DRY}
			_set_terrain(_cell + Vector2i(2, 0), Terrain.BARREL)
			_set_terrain(_cell + Vector2i(1, 1), Terrain.JUICER)
			_resources = _default_inventory()
			_resources["seed"] = 3; _resources["cup_water"] = 2; _resources["berry"] = 4
			_docked_station = pidx
			_mark_workspace_dirty(); _update_status()
		if "--inv" in args:
			_resources = _default_inventory()
			var inv_demo := {"wood": 24, "stone": 9, "metal": 4, "gunpowder": 12, "string": 5, "metal_tool": 1, "spear": 1, "sling_ammo": 8, "cup_water": 2, "worm": 2, "banana": 5, "berry": 7, "rotten_banana": 2, "rotten_berry": 1}
			for k in inv_demo:
				_resources[k] = inv_demo[k]
			_tool_equipped = "metal_tool"
			_weapon_equipped = "spear"
			_build_mode = false
			_mark_workspace_dirty()
			_update_status()
		if "--poolcam" in args:
			_player_pos = _cell_center_world(Vector2i(int(POOL_CENTER.x) + 6, int(POOL_CENTER.y)))
			_camera.position = _player_pos
		if "--splashscreen" in args:
			_enter_splash()
		if "--menu" in args:
			_enter_menu()
		if "--settingsmenu" in args:
			_enter_menu(); _open_settings(AppState.MENU)
		if "--confirmnew" in args:
			_enter_menu(); _menu_new_game()
		if "--dusk" in args:
			# Mid-dusk: warmed canvas, the countdown clock, and spawn-warn rings boiling.
			_ensure_den_footprints()
			_time = 0.78 - (6.0 / DAY_LENGTH)   # ~6s before night
			_dusk_telegraphed = true
			_fx_dusk_enter()
			_fx_night_incoming()
			_update_dusk_state(0.0)
			queue_redraw()
		if "--tierup" in args:
			# The dawn bloom mid-celebration on the Mother Tree.
			_fx_tier_up()
			for e in _fx:
				e["t"] = 0.35   # caught mid-bloom for the screenshot
			_apply_daylight()
			queue_redraw()
		if "--tech" in args:
			# The full-screen TECH hub mid-progression: T3 with a live NEW marker,
			# a partial Sap bar, stocked deposit inventory, and a Den or two alive.
			_ensure_den_footprints()
			_tree_tier = 3; _tech_seen_tier = 2; _tech_new_until = _now_secs() + TECH_NEW_DWELL
			_tree_hp = _tree_max_hp() * 0.62; _sap = 70.0; _nights_survived = 4
			_resources = _default_inventory()
			for kk in {"wood": 28, "stone": 16, "metal": 5, "glass": 3, "honey": 6, "berry": 9, "banana": 4}:
				_resources[kk] = {"wood": 28, "stone": 16, "metal": 5, "glass": 3, "honey": 6, "berry": 9, "banana": 4}[kk]
			_casings = [{"pos": _player_pos}, {"pos": _player_pos}, {"pos": _player_pos}]
			_active_overlay = Overlay.TECH
			_mark_workspace_dirty(); _refresh_workspace(); _update_status()
		if "--victory" in args:
			_nights_survived = 7; _tree_tier = 4; _best_nights = 9
			_trigger_victory()
			queue_redraw()
		for _i in range(3):
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
