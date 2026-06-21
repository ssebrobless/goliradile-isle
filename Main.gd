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
## WORLD: 50 x 50 data tiles. Grass/stumps/saplings/doors/floors are walkable
## for the player; doors/walls/etc. block. Survival systems: energy, health,
## food (apples), renewable trees, day/night.
##
## DAY/NIGHT COMBAT:
##   * At nightfall every NATURAL tile (water/tree/stone/stump/sapling) is
##     cleared to grass, leaving only player-built structures -- an open arena.
##   * Monsters spawn (more each night) and path toward the player. They cannot
##     pass doors or walls, so they attack the blocking structure until it
##     breaks. Adjacent, they damage Health. Face one + Space to fight back.
##   * At dawn the natural world is restored exactly and resource providers are
##     replenished (stumps -> trees, every tree bears an apple). Mined stone
##     stays gone (it was grass at nightfall).
##   * Health 0 at night -> you black out and wake at dawn.
##

const GRID_CELLS: int = 50
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
const DAY_LENGTH: float = 165.0   # longer cycle: ~117s day, night held to ~48s (see _daylight)
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
	"sand", "metal", "charcoal", "glass", "glass_jar",
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
	"glapple": "Glapple", "sand": "Sand", "metal": "Metal", "charcoal": "Charcoal", "glass": "Glass", "glass_jar": "Glass Jar",
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
const HIVE_BEE_CHANCE: float = 0.5         # chance a wild hive looses a bee each dawn
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
const CRAFT_ORDER := ["string", "cup", "rope", "wooden_rod", "nails", "glue",
	"sling_ammo", "metal_ammo", "stone_tool", "metal_tool", "slingshot", "mallet", "spear",
	"glapple_lamp", "glass_jar", "fish_skewer", "bone_meal", "hide_armor"]
const CRAFT_RECIPES := {
	"string":     {"label": "String", "out": "string", "cost": {"grass": GRASS_PER_STRING}},
	"cup":        {"label": "Empty Cup", "out": "cup", "cost": {"wood": WOOD_PER_CUP}},
	"rope":       {"label": "Rope", "out": "rope", "cost": {"string": 3}},
	"wooden_rod": {"label": "Wooden Rod", "out": "wooden_rod", "cost": {"wood": 2}},
	"nails":      {"label": "Nails (x2)", "out": "nails", "cost": {"stone": 1}, "out_count": 2},
	"glue":       {"label": "Glue", "out": "glue", "cost": {}, "rot": GLUE_PER_ROT},
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
const REGROW_TREES: int = 6              # new resources sprinkled onto empty grass each dawn
const REGROW_STONE: int = 3
const REGROW_BUSHES: int = 4

# --- Combat / monster tuning -------------------------------------------------
# These are the *base* (night-1 / level-1) stats; both sides scale from here.
const MONSTER_HP: float = 4.0          # base croc health
const PLAYER_DMG: float = 2.0          # base player attack
const MONSTER_HIT: float = 8.0         # base croc attack
const MONSTER_ATK_INTERVAL: float = 0.8   # seconds between a monster's attacks
const MONSTER_BRK_INTERVAL: float = 0.7   # seconds between hits on a blocking wall
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
	"":          {"label": "Fists",     "dmg": 1.0, "reach": 1.0, "time": 1.0, "kb": 1.0, "ranged": false},
	"mallet":    {"label": "Mallet",    "dmg": 2.4, "reach": 0.95, "time": 1.8, "kb": 2.4, "ranged": false},
	"spear":     {"label": "Spear",     "dmg": 1.5, "reach": 1.9,  "time": 1.1, "kb": 1.0, "ranged": false},
	"slingshot": {"label": "Slingshot", "dmg": 1.3, "reach": 1.0,  "time": 1.0, "kb": 0.6, "ranged": true},
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
const MONSTER_BASE: int = 3            # monsters on night 1
const MONSTER_PER_DAY: int = 2         # extra monsters each subsequent night
const MONSTER_CAP: int = 28
const SPAWN_MIN_DIST: int = 11         # spawn at least this far from the player
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
	"green":  {"body": Color(0.32, 0.54, 0.30), "belly": Color(0.58, 0.72, 0.46), "hp": 1.0, "atk": 1.0, "spd": 1.0, "role": "melee",   "unlock": 1, "weight": 5},
	"yellow": {"body": Color(0.88, 0.78, 0.20), "belly": Color(0.96, 0.90, 0.55), "hp": 0.7, "atk": 0.5, "spd": 1.7, "role": "melee",   "unlock": 2, "weight": 3},
	"red":    {"body": Color(0.78, 0.26, 0.22), "belly": Color(0.93, 0.56, 0.45), "hp": 1.0, "atk": 1.0, "spd": 0.9, "role": "fire",    "unlock": 3, "weight": 3},
	"blue":   {"body": Color(0.28, 0.50, 0.82), "belly": Color(0.62, 0.82, 0.97), "hp": 1.0, "atk": 0.8, "spd": 0.9, "role": "ice",     "unlock": 4, "weight": 3},
	"pink":   {"body": Color(0.86, 0.46, 0.68), "belly": Color(0.97, 0.74, 0.86), "hp": 1.6, "atk": 1.0, "spd": 0.7, "role": "wrecker", "unlock": 5, "weight": 2},
	"brown":  {"body": Color(0.48, 0.34, 0.20), "belly": Color(0.68, 0.54, 0.36), "hp": 1.1, "atk": 1.1, "spd": 1.0, "role": "digger",  "unlock": 6, "weight": 2},
	"purple": {"body": Color(0.56, 0.34, 0.74), "belly": Color(0.80, 0.62, 0.92), "hp": 1.0, "atk": 1.0, "spd": 0.85,"role": "poison",  "unlock": 7, "weight": 2},
	"white":  {"body": Color(0.86, 0.88, 0.92), "belly": Color(0.97, 0.98, 1.00), "hp": 1.2, "atk": 0.0, "spd": 1.0, "role": "healer",  "unlock": 8, "weight": 2},
	"black":  {"body": Color(0.20, 0.20, 0.25), "belly": Color(0.40, 0.40, 0.47), "hp": 1.2, "atk": 1.0, "spd": 1.0, "role": "reviver", "unlock": 9, "weight": 2},
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
const TRAP_MAX_HP := {"trap": 6, "peel_launcher": 8}  # wear HP (lost per trigger/shot)
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
	"sniper":    {"label": "Sniper",      "cat": "ranged",   "hp": 12.0, "range": 9.0, "cd": 2.2,  "dmg": 14.0, "kb": 1.2,  "crit": 0.25, "proj": "snipe"},
	"mg":        {"label": "Machine Gun", "cat": "ranged",   "hp": 10.0, "range": 6.0, "cd": 0.25, "dmg": 4.0,  "kb": 0.0,  "proj": "bullet", "spread": 0.18},
	"rocket":    {"label": "Rocket",      "cat": "ranged",   "hp": 11.0, "range": 7.0, "cd": 2.5,  "dmg": 9.0,  "kb": 0.0,  "proj": "rocket", "aoe": 1.8, "aoefrac": 0.4, "slow": 1.0},
	"boxer":     {"label": "Boxer",       "cat": "physical", "hp": 18.0, "range": 1.4, "cd": 0.35, "dmg": 6.0,  "kb": 0.4},
	"drill":     {"label": "Drill",       "cat": "physical", "hp": 12.0, "range": 1.3, "cd": 0.2,  "dmg": 3.0,  "kb": 0.15, "mover": true},
	"slicer":    {"label": "Slicer",      "cat": "physical", "hp": 14.0, "range": 1.9, "cd": 1.2,  "dmg": 9.0,  "kb": 0.5,  "multi": true},
	"engineer":  {"label": "Engineer",    "cat": "support",  "hp": 12.0, "range": 2.2, "cd": 0.0,  "dmg": 0.0,  "kb": 0.0,  "mover": true, "heal": 5.0},
	"adhesive":  {"label": "Adhesive",    "cat": "support",  "hp": 10.0, "range": 8.0, "cd": 2.5,  "dmg": 0.0,  "kb": 0.0,  "field": 2.6, "fieldslow": 0.12},
	"trickster": {"label": "Trickster",   "cat": "support",  "hp": 10.0, "range": 6.5, "cd": 0.0,  "dmg": 0.0,  "kb": 0.0,  "marks": 2, "markdmg": 0.2},
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
}

const WALKABLE := {
	Terrain.GRASS: true, Terrain.STUMP: true, Terrain.SAPLING: true,
	Terrain.DOOR: true, Terrain.FLOOR: true, Terrain.TRAP: true,
	Terrain.SAND: true, Terrain.WIRE: true, Terrain.PIPE: true, Terrain.LAND_MINE: true,
}

# Natural tiles that clear at night and are restored at dawn.
# (WATER is NOT here -- the pool is a permanent fixture that never clears.)
const NATURAL := {
	Terrain.TREE: true, Terrain.STONE: true,
	Terrain.STUMP: true, Terrain.SAPLING: true, Terrain.BUSH: true,
	Terrain.COCONUT: true, Terrain.BAMBOO: true, Terrain.HIVE: true,
}

# Tiles monsters can walk on (everything else blocks them; doors included).
# Traps are walkable so crocs stroll over them and get hurt.
const MONSTER_WALK := { Terrain.GRASS: true, Terrain.FLOOR: true, Terrain.TRAP: true, Terrain.SAND: true, Terrain.WIRE: true, Terrain.PIPE: true, Terrain.LAND_MINE: true }

# Structures monsters attack to break through, with their break HP.
const BREAK_HP := {
	Terrain.WOOD_WALL: 8, Terrain.STONE_WALL: 14, Terrain.DOOR: 5,
	Terrain.WORKBENCH: 4, Terrain.STORAGE: 4, Terrain.TURRET: 5,
	Terrain.BARREL: 6, Terrain.JUICER: 5, Terrain.PLANTER: 5, Terrain.KILN: 7,
	Terrain.BEE_ENCLOSURE: 5, Terrain.WORM_FARM: 5, Terrain.CAMPFIRE: 4, Terrain.STILL: 6,
	Terrain.GENERATOR: 8, Terrain.SPRINKLER: 4, Terrain.AQUARIUM: 8,
	Terrain.ELECTRIC_FENCE: 4,   # a light barricade crocs can chew through
}

const STRUCTURES := {
	"wood_wall":  {"num": 1, "terrain": Terrain.WOOD_WALL,  "cost": {"wood": 1},             "label": "Wood Wall",  "bench": false},
	"stone_wall": {"num": 2, "terrain": Terrain.STONE_WALL, "cost": {"stone": 1},            "label": "Stone Wall", "bench": false},
	"door":       {"num": 3, "terrain": Terrain.DOOR,       "cost": {"wood": 2},             "label": "Door",       "bench": false},
	"workbench":  {"num": 4, "terrain": Terrain.WORKBENCH,  "cost": {"wood": 4, "stone": 2}, "label": "Workbench",  "bench": false},
	"floor":      {"num": 5, "terrain": Terrain.FLOOR,      "cost": {"wood": 1},             "label": "Floor",      "bench": true},
	"storage":    {"num": 6, "terrain": Terrain.STORAGE,    "cost": {"wood": 3},             "label": "Storage",    "bench": true},
	"turret":     {"num": 7, "terrain": Terrain.TURRET,     "cost": {"wood": 3, "stone": 3}, "label": "Turret",     "bench": true},
	"trap":       {"num": 8, "terrain": Terrain.TRAP,       "cost": {"wood": 2, "stone": 2}, "label": "Spike Trap", "bench": true},
	"barrel":     {"num": 9, "terrain": Terrain.BARREL,     "cost": {"wood": 8, "stone": 3, "string": 2}, "label": "Barrel",   "bench": true},
	"juicer":     {"num": 10, "terrain": Terrain.JUICER,    "cost": {"wood": 5, "stone": 3, "string": 1}, "label": "Juicer",   "bench": true},
	"planter":    {"num": 11, "terrain": Terrain.PLANTER,   "cost": {"wood": 6, "string": 2}, "label": "Planter Box", "bench": true},
	"glapple_lamp": {"num": 12, "terrain": Terrain.GLAPPLE_LAMP, "cost": {"glapple_lamp": 1}, "label": "Glapple Lamp", "bench": false},
	"kiln":       {"num": 13, "terrain": Terrain.KILN,      "cost": {"stone": 12, "nails": 4}, "label": "Kiln", "bench": true},
	"campfire":   {"num": 14, "terrain": Terrain.CAMPFIRE,  "cost": {"wood": 4, "stone": 4}, "label": "Campfire", "bench": false},
	"bee_enclosure": {"num": 15, "terrain": Terrain.BEE_ENCLOSURE, "cost": {"wood": 6, "glass": 2, "rope": 2}, "label": "Bee Enclosure", "bench": true},
	"worm_farm":  {"num": 16, "terrain": Terrain.WORM_FARM,  "cost": {"glass": 3, "wood": 2}, "label": "Worm Habitat", "bench": true},
	"still":      {"num": 17, "terrain": Terrain.STILL,      "cost": {"bamboo": 4, "metal": 2, "glass": 1}, "label": "Still", "bench": true},
	"generator":  {"num": 18, "terrain": Terrain.GENERATOR,  "cost": {"metal": 4, "bamboo": 4, "glue": 2, "wooden_rod": 2}, "label": "Generator", "bench": true},
	"wire":       {"num": 19, "terrain": Terrain.WIRE,       "cost": {"string": 1, "metal_ore": 1, "glue": 1}, "label": "Wire", "bench": false},
	"bulb":       {"num": 20, "terrain": Terrain.BULB,       "cost": {"glass": 2, "metal": 1, "nails": 2}, "label": "Electric Bulb", "bench": true},
	"pipe":       {"num": 21, "terrain": Terrain.PIPE,       "cost": {"bamboo": 1, "glue": 1, "rope": 1}, "label": "Pipe", "bench": false},
	"sprinkler":  {"num": 22, "terrain": Terrain.SPRINKLER,  "cost": {"bamboo": 3, "metal": 1}, "label": "Sprinkler", "bench": true},
	"aquarium":   {"num": 23, "terrain": Terrain.AQUARIUM,   "cost": {"glass": 8, "metal": 2, "rope": 2}, "label": "Fish Aquarium", "bench": true},
	"land_mine":  {"num": 24, "terrain": Terrain.LAND_MINE,  "cost": {"metal": 1, "charcoal": 1}, "label": "Land Mine", "bench": true},
	"peel_launcher": {"num": 25, "terrain": Terrain.PEEL_LAUNCHER, "cost": {"bamboo": 3, "wooden_rod": 1, "rope": 1}, "label": "Peel Launcher", "bench": true},
	"electric_fence": {"num": 26, "terrain": Terrain.ELECTRIC_FENCE, "cost": {"metal": 2, "wooden_rod": 1}, "label": "Electric Fence", "bench": true},
}
const STRUCTURE_ORDER := ["wood_wall", "stone_wall", "door", "workbench", "floor", "storage", "turret", "trap", "barrel", "juicer", "planter", "glapple_lamp", "kiln", "campfire", "bee_enclosure", "worm_farm", "still", "generator", "wire", "bulb", "pipe", "sprinkler", "aquarium", "land_mine", "peel_launcher", "electric_fence"]
# Every trap kind, for the 10-trap placement cap.
const TRAP_TERRAIN := {Terrain.TRAP: true, Terrain.LAND_MINE: true, Terrain.PEEL_LAUNCHER: true, Terrain.ELECTRIC_FENCE: true}

# Placed-block cap: only the structural pieces that shape/obstruct the base count.
# Turrets, workstations (bench/storage/barrel/juicer/planter/etc), traps, pipes and
# wires are all exempt -- they have their own limits or none.
const BLOCK_LIMIT: int = 80
const BLOCK_TERRAIN := {
	Terrain.WOOD_WALL: true, Terrain.STONE_WALL: true, Terrain.DOOR: true, Terrain.FLOOR: true,
}
# Loot lying on the ground is vacuumed up when the player wanders within this range.
const LOOT_PICKUP_R: float = CELL_SIZE * 0.9
# Live critters (worm/bee) need a jar to catch; if none turns up in time they
# crawl/buzz off rather than littering the ground forever (was an endless-orb bug).
const CRITTER_LOOT_LIFE: float = 18.0
# Dawn re-seeding never lets wild resources exceed the world's starting density,
# and keeps new growth this many tiles clear of anything the player has built.
const REGROW_STRUCT_BUFFER: int = 1
const NATURAL_BASELINE_MIN: int = 200   # fallback target if an old save lacks one

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
var _inv_open: bool = false        # inventory-management panel toggle (key I)
var _craft_open: bool = false      # crafting panel toggle (key C)
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
var _fish: Array = []              # [{pos:Vector2, sex:"m"|"f", t:float}] swimming in the pool
var _tool_equipped: String = ""    # "" / "stone_tool" / "metal_tool"
var _weapon_equipped: String = ""  # "" (fists) / "slingshot" / "mallet" / "spear"
var _gear_armor: float = 0.0       # bonus armor from crafted hide armor (capped)
var _energy: float = ENERGY_MAX
var _hydration: float = HYDRATION_MAX
var _health: float = HEALTH_MAX
var _lives: int = MAX_LIVES
var _seed: int = WORLD_SEED         # world seed (randomized on a fresh run)
var _natural_baseline: int = 0      # target wild-resource tile count (set at world-gen)

# Progression
var _level: int = 1
var _xp: int = 0
var _xp_to_next: int = 5
var _nights_survived: int = 0
var _best_nights: int = 0           # best across all runs (persisted to disk)

# Player-directed stat allocation: each level grants one point to spend.
var _stat_points: int = 0           # unspent points (queues if you level mid-fight)
var _choosing_levelup: bool = false # world is frozen while a choice is pending
var _alloc := {"health": 0, "attack": 0, "speed": 0, "armor": 0, "regen": 0}
const STAT_ORDER: Array = ["health", "attack", "speed", "armor", "regen"]

const SAVE_PATH := "user://goliradile_isle.save"

# Derived player stats (recomputed from _level)
var _p_max_health: float = HEALTH_MAX
var _p_attack: float = PLAYER_DMG
var _p_speed: float = PLAYER_SPEED
var _p_armor: float = 0.0
var _p_regen: float = HEALTH_REGEN
var _time: float = 0.30
var _day: int = 1
var _banana_timer: float = 0.0
var _msg: String = ""               # transient banner (death / game over)
var _msg_timer: float = 0.0
var _water_hint_cd: float = 0.0     # throttle for the "click water to fill a cup" hint
var _cup_filled_once: bool = false  # once the player scoops water, stop nagging

var _storage := {}
var _open_storage: int = -1
var _open_util: int = -1            # open barrel/juicer/planter cell index (-1 = none)
var _open_turret: int = -1          # open turret cell index (-1 = none)
var _turret_pick_cat: String = ""   # two-step turret picker: chosen category, no type yet
var _util_refresh_t: float = 0.0    # coarse timer to refresh an open utility panel

var _build_mode: bool = false
var _build_struct: String = ""
var _dragging: bool = false
var _drag_action: int = BuildAction.NONE
var _last_applied_cell: Vector2i = Vector2i(-9999, -9999)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_near_bench: bool = false

# Night / combat
var _is_night: bool = false
var _monsters: Array = []          # [{pos, hp, type, role, ...}, ...]
var _projectiles: Array = []       # [{pos, vel, kind, dmg}, ...] kind = "fire"|"snow"
var _poison_clouds: Array = []     # [{pos, t}] purple lingering smoke
var _night_snapshot := {}          # idx -> {t:int, apple:int}
var _struct_hp := {}               # idx -> current break hp (only if damaged)
var _turrets := {}                 # home cell idx -> turret object dict
var _trap_cd := {}                 # idx -> seconds until a spike trap re-arms (0 = armed)
var _traps := {}                   # idx -> {type, hp, ammo, cd} for mine/peel/fence
var _peels: Array = []             # [{pos, t}] dropped banana peels (stun on contact)

# Player status effects (set by croc projectiles)
var _burn_t: float = 0.0           # remaining burn (DoT) time
var _slow_t: float = 0.0           # remaining snowball slow time
var _freeze_t: float = 0.0         # remaining frozen-in-place time
var _snow_count: int = 0           # snowball hits inside the current rolling window
var _snow_window: float = 0.0      # time left in that window (resets count at 0)

var _camera: Camera2D
var _canvas_mod: CanvasModulate

# Baked pixel-art textures
var _tiles := {}                  # Terrain -> ImageTexture
var _tex_gorilla: ImageTexture
var _tex_croc_r: ImageTexture
var _tex_croc_l: ImageTexture
var _tex_croc_flash_r: ImageTexture
var _tex_croc_flash_l: ImageTexture
var _tex_gorilla_flash: ImageTexture
var _tex_banana: ImageTexture
var _tex_coconut: ImageTexture    # overlay for a palm bearing coconuts
var _croc_tex := {}               # type -> {"r","l","fr","fl"} ImageTextures

# FX overlays
var _fx_layer: CanvasLayer
var _flash_rect: ColorRect
var _vignette: TextureRect

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
	_generate_world()
	_init_progression()

	_player_pos = _cell_center_world(_cell)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(_camera)
	_camera.make_current()
	_camera.position = _player_pos

	_canvas_mod = CanvasModulate.new()
	add_child(_canvas_mod)

	_build_ui()
	_build_fx()
	_build_menu_layer()
	_apply_daylight()
	_update_status()
	_refresh_context_panel()

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
		return

	# Level-up choice freezes the world until the player spends their point.
	if _choosing_levelup:
		_update_status()
		return

	# Hit-stop: hold the world frozen for a few ms on impact so hits land harder.
	if _hitstop > 0.0:
		_hitstop = maxf(0.0, _hitstop - delta)
		queue_redraw()   # keep the frozen frame (with its hit-flash) on screen
		return

	_advance_time(delta)
	_decay_tick(delta)   # loose food spoils over time, day or night

	# Continuous free movement (8-directional, WASD).
	var input := Vector2.ZERO
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
		_player_pos = _move_collide(_player_pos, input * spd * delta, PLAYER_RADIUS, WALKABLE)
		_energy = maxf(0.0, _energy - ENERGY_MOVE * delta)
		_cell = _world_to_cell(_player_pos)

	# Knockback (decays each frame).
	if _player_kb.length() > 1.0:
		_player_pos = _move_collide(_player_pos, _player_kb * delta, PLAYER_RADIUS, WALKABLE)
		_player_kb = _player_kb.move_toward(Vector2.ZERO, KB_DECAY * delta)
		_cell = _world_to_cell(_player_pos)

	_camera.position = _player_pos

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
		# Teach the non-obvious "fill a cup at the pool" step: a gentle, throttled
		# nudge while you're standing by the water and haven't worked it out yet.
		_water_hint_cd = maxf(0.0, _water_hint_cd - delta)
		if _water_hint_cd <= 0.0 and _msg_timer <= 0.0 and _adjacent_to_water():
			if _inv("cup") > 0 and not _cup_filled_once:
				_set_msg("By the pool: left-click the water to fill your cup (Q to drink).")
				_water_hint_cd = 8.0
			elif _inv("cup") <= 0 and _inv("cup_water") + _inv("cup_juice") + _inv("cup_wine") == 0:
				_set_msg("Thirsty? Craft an empty cup (C), then click the pool to fill it.")
				_water_hint_cd = 8.0

	_utility_tick(delta)   # barrels ferment, juicers press, planters grow (always)

	if _open_storage >= 0 and _chebyshev(_cell, _index_cell(_open_storage)) > 1:
		_close_storage()
	if _open_util >= 0 and _chebyshev(_cell, _index_cell(_open_util)) > 1:
		_close_util()
	if _open_turret >= 0 and _chebyshev(_cell, _index_cell(_open_turret)) > 1:
		_close_turret()

	if _build_mode:
		var near := _near_workbench()
		if near != _last_near_bench:
			_last_near_bench = near
			_refresh_context_panel()

	var hc := _mouse_cell()
	if hc != _hover_cell:
		_hover_cell = hc
		queue_redraw()

	_update_juice(delta)

	# Things move continuously now, so redraw while anything is animating.
	if input != Vector2.ZERO or _player_kb.length() > 1.0 or _punch_active \
			or not _monsters.is_empty() or not _poofs.is_empty() or _spark_t < 1.0 or _shake > 0.0 \
			or not _projectiles.is_empty() or not _poison_clouds.is_empty() \
			or not _ground_items.is_empty() or not _fish.is_empty() or not _peels.is_empty() \
			or _burn_t > 0.0 or _freeze_t > 0.0 or _slow_t > 0.0:
		queue_redraw()

	_update_status()


# -----------------------------------------------------------------------------
# Time, daylight, health, growth, day/night transitions
# -----------------------------------------------------------------------------
func _advance_time(delta: float) -> void:
	_time += delta / DAY_LENGTH
	while _time >= 1.0:
		_time -= 1.0
		_day += 1
	_apply_daylight()

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


func _daylight(f: float) -> float:
	# Night is held to ~29% of the cycle (~48s at DAY_LENGTH 165) so lengthening the
	# day gives more gather/build time without making nights drag on.
	if f < 0.145 or f >= 0.855:
		return 0.0
	elif f < 0.245:
		return smoothstep(0.145, 0.245, f)
	elif f < 0.755:
		return 1.0
	else:
		return 1.0 - smoothstep(0.755, 0.855, f)


func _apply_daylight() -> void:
	if _canvas_mod:
		_canvas_mod.color = NIGHT_COLOR.lerp(Color.WHITE, _daylight(_time))


func _begin_night() -> void:
	_is_night = true
	# No building at night: force-exit build mode.
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_night_snapshot.clear()
	for i in range(_terrain.size()):
		var t: int = _terrain[i]
		if NATURAL.has(t):
			_night_snapshot[i] = {"t": t, "banana": _banana[i], "berry": _berry[i]}
			_terrain[i] = Terrain.GRASS
			_banana[i] = 0
			_berry[i] = 0
			_growth[i] = 0.0
	_spawn_monsters(_monster_count_for_day())
	# Telegraph the wall: deep nights demand wired, generator-powered defenses.
	if _night_index() == POWER_DEMAND_NIGHT:
		_set_msg("The horde swells -- wine alone can't keep turrets firing. Wire them to a generator!")
	elif _night_index() > POWER_DEMAND_NIGHT:
		_set_msg("Night %d: power your turrets or they'll run dry." % _night_index())
	_refresh_context_panel()
	queue_redraw()


func _begin_day() -> void:
	_is_night = false
	for idx in _night_snapshot:
		if _terrain[idx] != Terrain.GRASS:
			continue  # player built here during the night -- keep their structure
		var t: int = _night_snapshot[idx]["t"]
		if t == Terrain.STUMP or t == Terrain.SAPLING:
			t = Terrain.TREE                       # replenish: regrow to a full tree
		# Don't regrow a solid tile on top of the player -- that wedges them in
		# place until they shove free. Leave it grass; it returns next dawn.
		if not WALKABLE.has(t) and _cell_overlaps_player(_index_cell(idx)):
			continue
		_terrain[idx] = t
		_growth[idx] = 0.0
		_banana[idx] = 1 if t == Terrain.TREE else 0   # replenish bananas
		_berry[idx] = 1 if t == Terrain.BUSH else 0    # replenish berries
	_night_snapshot.clear()
	_regrow_world()
	_monsters.clear()
	_projectiles.clear()
	_poison_clouds.clear()
	_clear_status_effects()
	# Clear stale support-turret fields: an adhesive turret's slow-zone is only laid
	# (and only matters) at night, so it must not stay painted on the ground all day.
	for ti in _turrets:
		if _turrets[ti]["type"] == "adhesive":
			_turrets[ti]["field"] = Vector2.INF
	_punch_active = false
	_player_kb = Vector2.ZERO
	_refresh_context_panel()
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
	return mini(MONSTER_CAP, MONSTER_BASE + (_night_index() - 1) * MONSTER_PER_DAY)


# Build a crocodile of `type` with stats scaled to night `n` (n = 1 on night one).
func _croc_for_night(pos: Vector2, n: int, type: String = "green") -> Dictionary:
	n = mini(n, LEVEL_CAP)        # crocs stop scaling past the global level cap
	var lv := n - 1
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
	var night := _night_index()
	var pool := _unlocked_croc_pool(night)
	# Crocs emerge from the pool: spawn on its shore where there's room.
	var shore := _pool_shore.duplicate()
	shore.shuffle()
	var placed := 0
	for c in shore:
		if placed >= n:
			break
		if not MONSTER_WALK.has(_terrain_at(c)):
			continue
		var type: String = pool[randi() % pool.size()]
		_monsters.append(_croc_for_night(_cell_center_world(c), night, type))
		_poofs.append({"pos": _cell_center_world(c), "t": 0.2})  # a splash as it surfaces
		placed += 1
	# If the pool can't seat them all, the rest wade in from random far ground.
	var attempts := 0
	while placed < n and attempts < 3000:
		attempts += 1
		var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
		if not MONSTER_WALK.has(_terrain_at(c)) or _chebyshev(c, _cell) < SPAWN_MIN_DIST:
			continue
		var type: String = pool[randi() % pool.size()]
		_monsters.append(_croc_for_night(_cell_center_world(c), night, type))
		placed += 1


# How many wild-resource tiles (trees/stone/bushes/etc.) currently exist.
func _natural_tile_count() -> int:
	var n := 0
	for i in range(_terrain.size()):
		if NATURAL.has(_terrain[i]):
			n += 1
	return n


# A player-built tile is anything that isn't open grass, the pool, or wild growth.
func _is_built(t: int) -> bool:
	return t != Terrain.GRASS and t != Terrain.WATER and not NATURAL.has(t)


# True if any built tile sits within `r` cells of `c` (keeps regrowth out of bases).
func _near_structure(c: Vector2i, r: int) -> bool:
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var n := c + Vector2i(ox, oy)
			if _in_bounds(n) and _is_built(_terrain_at(n)):
				return true
	return false


# Sprinkle fresh resources onto empty grass each dawn (never onto water, the
# player, the base, or any built structure -- and never past the world's starting
# density, so the isle stays open instead of silting up into an obstacle course).
func _regrow_world() -> void:
	if _natural_baseline <= 0:
		_natural_baseline = maxi(_natural_tile_count(), NATURAL_BASELINE_MIN)
	var budget := maxi(0, _natural_baseline - _natural_tile_count())
	var kinds := []
	for _i in range(REGROW_TREES): kinds.append(Terrain.TREE)
	for _i in range(REGROW_STONE): kinds.append(Terrain.STONE)
	for _i in range(REGROW_BUSHES): kinds.append(Terrain.BUSH)
	for _i in range(2): kinds.append(Terrain.COCONUT)
	for _i in range(2): kinds.append(Terrain.BAMBOO)
	if randf() < 0.4: kinds.append(Terrain.HIVE)   # hives re-seed only some dawns, not every one
	kinds.shuffle()   # so a tight budget doesn't always starve the same kinds
	for t in kinds:
		if budget <= 0:
			break
		var attempts := 0
		while attempts < 60:
			attempts += 1
			var c := Vector2i(randi() % GRID_CELLS, randi() % GRID_CELLS)
			if _terrain_at(c) != Terrain.GRASS or c == _cell:
				continue
			if _near_structure(c, REGROW_STRUCT_BUFFER):
				continue
			_set_terrain(c, t)
			if t == Terrain.TREE or t == Terrain.COCONUT:
				_banana[_cell_index(c)] = 1
			elif t == Terrain.BUSH:
				_berry[_cell_index(c)] = 1
			budget -= 1
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
			m["pos"] = _move_collide(m["pos"], kb * delta, MONSTER_RADIUS, MONSTER_WALK)
			m["kb"] = kb.move_toward(Vector2.ZERO, KB_DECAY * delta)
			continue
		m["kb"] = kb.move_toward(Vector2.ZERO, KB_DECAY * delta)

		var to: Vector2 = _player_pos - m["pos"]
		var dist: float = to.length()
		var dir: Vector2 = to / dist if dist > 0.01 else Vector2.RIGHT

		match role:
			"digger":
				_update_digger(m, delta, dir, dist)
				continue
			"healer":
				# Support unit: never attacks; trails the pack, keeping its distance.
				if dist > CELL_SIZE * 3.5:
					_move_monster_toward(m, dir, delta, m["speed"] * 0.85)
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
		_move_monster_toward(m, dir, delta, m["speed"])

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
			_poofs.append({"pos": m["pos"], "t": 0.0})
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
	if m["slow_t"] > 0.0:
		speed *= 0.5   # slowed by a spike trap / rocket
	speed *= _adhesive_factor(m["pos"])   # adhesive support-turret slow field
	var motion: Vector2 = dir * speed * delta
	var before: Vector2 = m["pos"]
	m["pos"] = _move_collide(before, motion, MONSTER_RADIUS, MONSTER_WALK)
	if (m["pos"] as Vector2).distance_to(before) < motion.length() * 0.5 and m["brk_cd"] <= 0.0:
		var probe: Vector2 = before + dir * (MONSTER_RADIUS + CELL_SIZE * 0.5)
		var c := _world_to_cell(probe)
		if _in_bounds(c) and BREAK_HP.has(_terrain_at(c)):
			_damage_structure(c)
			m["brk_cd"] = MONSTER_BRK_INTERVAL


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


# Brown croc: tunnels invulnerably toward the player, surfacing nearby -- but
# pops out *outside* any wall rather than digging into the player's home.
func _update_digger(m: Dictionary, delta: float, dir: Vector2, dist: float) -> void:
	if m["dig"]:
		var ahead := _world_to_cell((m["pos"] as Vector2) + dir * (MONSTER_RADIUS + CELL_SIZE * 0.5))
		if dist <= DIG_SURFACE_RANGE or (_in_bounds(ahead) and BREAK_HP.has(_terrain_at(ahead))):
			m["dig"] = false          # surface (stays on the outside of the wall)
			m["atk_cd"] = MONSTER_ATK_INTERVAL * 0.5
			_add_shake(4.0)
			return
		var nxt: Vector2 = (m["pos"] as Vector2) + dir * float(m["speed"]) * delta
		if _in_bounds(_world_to_cell(nxt)):
			m["pos"] = nxt
		return
	# Surfaced -> ordinary melee.
	if dist <= ATTACK_RANGE:
		if m["atk_cd"] <= 0.0:
			_damage_player(m["attack"], m["pos"])
			m["atk_cd"] = MONSTER_ATK_INTERVAL
		return
	_move_monster_toward(m, dir, delta, m["speed"])


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
				if _in_bounds(target) and BREAK_HP.has(_terrain_at(target)):
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
		if BREAK_HP.has(_terrain[i]):
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


func _damage_structure(c: Vector2i) -> void:
	var idx := _cell_index(c)
	var t := _terrain_at(c)
	# Turrets don't get demolished -- they take object HP and "break" in place.
	if t == Terrain.TURRET and _turrets.has(idx):
		_turret_take_damage(_turrets[idx], float(BREAK_HP[Terrain.TURRET]) * 0.5)
		queue_redraw()
		return
	var maxhp: int = BREAK_HP[t]
	var hp: int = _struct_hp.get(idx, maxhp) - 1
	if hp <= 0:
		if t == Terrain.STORAGE:
			_storage.erase(idx)
			if _open_storage == idx:
				_close_storage()
		_struct_hp.erase(idx)
		_barrels.erase(idx)
		_juicers.erase(idx)
		_planters.erase(idx)
		_lamps.erase(idx); _kilns.erase(idx); _apiaries.erase(idx); _wormfarms.erase(idx)
		_campfires.erase(idx); _stills.erase(idx); _generators.erase(idx)
		_sprinklers.erase(idx); _aquariums.erase(idx); _traps.erase(idx)
		if _open_util == idx:
			_close_util()
		_set_terrain(c, Terrain.GRASS)
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
	var def: Dictionary = TURRET_DEFS[type]
	t["type"] = type
	t["category"] = def["cat"]
	t["max_hp"] = float(def["hp"])
	t["hp"] = t["max_hp"]
	t["fuel"] = TURRET_FUEL_MAX            # ships with a starter charge of wine
	t["dig"] = bool(def.get("mover", false)) and type == "drill"
	_refresh_context_panel()


# Effective stat including this turret's spent upgrade points.
func _turret_stat(t: Dictionary, key: String) -> float:
	var def: Dictionary = TURRET_DEFS[t["type"]]
	var a: Dictionary = t["alloc"]
	match key:
		"max_hp": return float(def["hp"]) + int(a["hp"]) * TURRET_HP_PER
		"dmg": return float(def["dmg"]) + int(a["dmg"]) * TURRET_DMG_PER
		"cd": return maxf(0.05, float(def["cd"]) * (1.0 - int(a["rate"]) * TURRET_RATE_PER))
		"range": return (float(def["range"]) + int(a["range"]) * TURRET_RANGE_PER) * CELL_SIZE
	return 0.0


func _turret_spend_fuel(t: Dictionary) -> void:
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
	_refresh_context_panel()


func _toggle_turret(idx: int) -> void:
	_open_turret = -1 if _open_turret == idx else idx
	_turret_pick_cat = ""
	if _open_turret != -1:
		_close_storage(); _close_util()
	_refresh_context_panel()


func _close_turret() -> void:
	if _open_turret != -1:
		_open_turret = -1
		_turret_pick_cat = ""
		_refresh_context_panel()


func _turret_repair(idx: int) -> void:
	if _is_night or not _turrets.has(idx):
		_set_msg("Repairs can only be made by day."); return
	var t: Dictionary = _turrets[idx]
	if float(t["hp"]) >= float(t["max_hp"]):
		return
	if not _can_afford(TURRET_REPAIR_COST):
		_set_msg("Need %s to repair." % _cost_text(TURRET_REPAIR_COST)); return
	_spend(TURRET_REPAIR_COST)
	t["hp"] = minf(float(t["max_hp"]), float(t["hp"]) + float(t["max_hp"]) * TURRET_REPAIR_FRAC)
	if t["hp"] > 0.0:
		t["broken"] = false
	_refresh_context_panel()


func _turret_refuel(idx: int) -> void:
	if not _turrets.has(idx) or _inv("cup_wine") <= 0:
		_set_msg("Need a cup of berry wine."); return
	var t: Dictionary = _turrets[idx]
	_resources["cup_wine"] = _inv("cup_wine") - 1
	_resources["cup"] = _inv("cup") + 1
	t["fuel"] = minf(float(t["max_fuel"]), float(t["fuel"]) + TURRET_FUEL_PER_CUP)
	_refresh_context_panel()


func _turret_update(delta: float) -> void:
	_update_trickster_marks(delta)   # tricksters maintain their marks globally
	_tag_adhesive_debuffs()          # credit adhesive fields for the crocs they slow
	for idx in _turrets:
		var t: Dictionary = _turrets[idx]
		t["heal_t"] = maxf(0.0, float(t["heal_t"]) - delta)
		if t["type"] == "" or t["broken"]:
			continue
		t["powered"] = _is_powered(t["cell"])   # wired to a live generator?
		t["cd"] = maxf(0.0, float(t["cd"]) - delta)
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


# Central croc-damage entry: applies armor + trickster mark, knockback, flash,
# and records who gets the kill (a turret cell idx, or "player").
func _hurt_croc(m: Dictionary, dmg: float, kb_vec: Vector2, kb_mult: float, killer) -> void:
	var mult := 1.2 if m["marked"] else 1.0
	m["hp"] = float(m["hp"]) - dmg * (1.0 - float(m["armor"])) * mult
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
	_refresh_context_panel()


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
	_refresh_context_panel()


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
	_choosing_levelup = false
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
	_choosing_levelup = true
	_msg = "LEVEL UP!  Choose a stat to raise"
	_msg_timer = 2.5
	_refresh_context_panel()


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
		_choosing_levelup = false
	_refresh_context_panel()
	_update_status()
	queue_redraw()


func _night_index() -> int:
	return _nights_survived + 1


func _on_death() -> void:
	_lives -= 1
	if _lives <= 0:
		_reset_game()
		_msg = "GAME OVER  -  new run"
		_msg_timer = 3.5
	else:
		_respawn_after_death()
		_msg = "You went down! Lives left: %d" % _lives
		_msg_timer = 3.0


func _respawn_after_death() -> void:
	# Wake at dawn at the world centre with restored health.
	_health = _p_max_health
	_energy = maxf(_energy, ENERGY_MAX * 0.5)
	_hydration = maxf(_hydration, HYDRATION_MAX * 0.5)
	_player_kb = Vector2.ZERO
	_punch_active = false
	_clear_status_effects()
	_projectiles.clear()
	_poison_clouds.clear()
	_cell = Vector2i(GRID_CELLS / 2, GRID_CELLS / 2)
	_player_pos = _cell_center_world(_cell)
	_camera.position = _player_pos
	_time = 0.30
	_apply_daylight()
	if _is_night:
		_begin_day()


func _reset_game() -> void:
	# Wipe everything and start a brand-new run on a fresh world.
	# (_best_nights is intentionally preserved across runs.)
	_seed = randi()
	_generate_world()
	_init_progression()
	_resources = _default_inventory()
	_decay_timer = 0.0
	_juice_spoil_t = 0.0
	_inv_open = false
	_craft_open = false
	_hydration = HYDRATION_MAX
	_tool_equipped = ""
	_weapon_equipped = ""
	_gear_armor = 0.0
	_lives = MAX_LIVES
	_time = 0.30
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
	_traps.clear()
	_peels.clear()
	_fish.clear()
	_night_snapshot.clear()
	_struct_hp.clear()
	_storage.clear()
	_is_night = false
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_open_storage = -1
	_punch_active = false
	_player_kb = Vector2.ZERO
	_cell = Vector2i(GRID_CELLS / 2, GRID_CELLS / 2)
	_player_pos = _cell_center_world(_cell)
	_camera.position = _player_pos
	_apply_daylight()
	_refresh_context_panel()
	queue_redraw()


# -----------------------------------------------------------------------------
# Build-mode input and mouse
# -----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Menu / splash / settings consume their own GUI input; ignore gameplay keys.
	if _app_state != AppState.PLAYING:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		# Pending level-up choice eats number keys 1-5.
		if _choosing_levelup:
			if kc >= KEY_1 and kc <= KEY_5:
				_choose_stat(STAT_ORDER[kc - KEY_1])
			return
		if kc == KEY_B:
			# Build mode is daytime-only. B toggles it; pressing B again exits.
			if _build_mode:
				_build_mode = false
				_build_struct = ""
				_dragging = false
				_drag_action = BuildAction.NONE
				_refresh_context_panel()
				queue_redraw()
			elif not _is_night:
				_build_mode = true
				_close_storage()
				_refresh_context_panel()
				queue_redraw()
		elif kc == KEY_E:
			_try_eat()
		elif kc == KEY_Q:
			_drink_best()
		elif kc == KEY_I:
			# Toggle the inventory-management panel (drop items).
			_inv_open = not _inv_open
			if _inv_open:
				_build_mode = false
				_craft_open = false
				_close_storage()
			_refresh_context_panel()
			queue_redraw()
		elif kc == KEY_C:
			# Toggle the crafting panel.
			_craft_open = not _craft_open
			if _craft_open:
				_build_mode = false
				_inv_open = false
				_close_storage()
			_refresh_context_panel()
			queue_redraw()
		elif _build_mode and kc >= KEY_1 and kc <= KEY_9:
			_select_by_num(kc - KEY_0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _choosing_levelup or not _mouse_in_board():
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
	_refresh_context_panel()


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


func _apply_build_at(c: Vector2i) -> void:
	if not _in_bounds(c):
		return
	_last_applied_cell = c

	if _drag_action == BuildAction.BUILD:
		if _build_struct == "":
			return
		var s: Dictionary = STRUCTURES[_build_struct]
		if c == _cell or _monster_at(c) != -1:
			return
		if _terrain_at(c) != Terrain.GRASS:
			return
		# Don't let the player wall themselves into a tile: refuse a solid block
		# whose cell their body already overlaps.
		if not WALKABLE.has(int(s["terrain"])) and _cell_overlaps_player(c):
			_set_msg("Too close -- step back to place that.")
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
			Terrain.LAND_MINE:
				_traps[bidx] = {"type": "land_mine"}
			Terrain.PEEL_LAUNCHER:
				_traps[bidx] = {"type": "peel_launcher", "hp": TRAP_MAX_HP["peel_launcher"], "ammo": 0, "cd": 0.0}
			Terrain.ELECTRIC_FENCE:
				_traps[bidx] = {"type": "electric_fence", "cd": 0.0}
			Terrain.TURRET:
				_turrets[bidx] = _new_turret(c)
		_energy = maxf(0.0, _energy - ENERGY_BUILD)
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
			if _open_storage == idx:
				_close_storage()
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
		if _open_util == didx:
			_close_util()
		if _open_turret == didx:
			_close_turret()
		_refund(STRUCTURES[key]["cost"])
		_set_terrain(c, Terrain.GRASS)
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
	_refresh_context_panel()


func _structure_key_for_terrain(t: int) -> String:
	for key in STRUCTURE_ORDER:
		if STRUCTURES[key]["terrain"] == t:
			return key
	return ""


func _near_workbench() -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var c := _cell + Vector2i(ox, oy)
			if _in_bounds(c) and _terrain_at(c) == Terrain.WORKBENCH:
				return true
	return false


func _adjacent_to_water() -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var c := _cell + Vector2i(ox, oy)
			if _in_bounds(c) and _terrain_at(c) == Terrain.WATER:
				return true
	return false


func _can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if _resources[k] < cost[k]:
			return false
	return true


func _spend(cost: Dictionary) -> void:
	for k in cost:
		_resources[k] -= cost[k]


func _refund(cost: Dictionary) -> void:
	for k in cost:
		_resources[k] += cost[k]


# -----------------------------------------------------------------------------
# Movement / interact / harvest / eat
# -----------------------------------------------------------------------------
# Move a circle (radius hs) by `motion`, resolved per-axis so it slides along
# blocking tiles. `walkset` is the set of terrains this body may stand on.
func _move_collide(pos: Vector2, motion: Vector2, hs: float, walkset: Dictionary) -> Vector2:
	var p := pos
	var nx := Vector2(p.x + motion.x, p.y)
	if not _box_blocked(nx, hs, walkset):
		p = nx
	var ny := Vector2(p.x, p.y + motion.y)
	if not _box_blocked(ny, hs, walkset):
		p = ny
	return p


func _box_blocked(center: Vector2, hs: float, walkset: Dictionary) -> bool:
	var minx := int(floor((center.x - hs) / CELL_SIZE))
	var maxx := int(floor((center.x + hs) / CELL_SIZE))
	var miny := int(floor((center.y - hs) / CELL_SIZE))
	var maxy := int(floor((center.y + hs) / CELL_SIZE))
	for cy in range(miny, maxy + 1):
		for cx in range(minx, maxx + 1):
			var c := Vector2i(cx, cy)
			if not _in_bounds(c):
				return true
			if not walkset.has(_terrain_at(c)):
				return true
	return false


# True if the player's body (a circle of PLAYER_RADIUS) overlaps cell `c`. Used
# to avoid wedging the player inside a tile -- when dawn regrows terrain or when
# a block is placed too close.
func _cell_overlaps_player(c: Vector2i) -> bool:
	var hs := PLAYER_RADIUS
	var minx := int(floor((_player_pos.x - hs) / CELL_SIZE))
	var maxx := int(floor((_player_pos.x + hs) / CELL_SIZE))
	var miny := int(floor((_player_pos.y - hs) / CELL_SIZE))
	var maxy := int(floor((_player_pos.y + hs) / CELL_SIZE))
	return c.x >= minx and c.x <= maxx and c.y >= miny and c.y <= maxy


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
	if t == Terrain.BARREL or t == Terrain.JUICER or t == Terrain.PLANTER or t == Terrain.KILN \
			or t == Terrain.BEE_ENCLOSURE or t == Terrain.WORM_FARM or t == Terrain.CAMPFIRE or t == Terrain.STILL \
			or t == Terrain.GENERATOR or t == Terrain.AQUARIUM or t == Terrain.SPRINKLER \
			or t == Terrain.PEEL_LAUNCHER:
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
	_cup_filled_once = true   # they've learned it -- drop the pool hint


func _set_msg(text: String) -> void:
	_msg = text
	_msg_timer = 2.5


# --- Drinking + crafting -----------------------------------------------------
func _drink(kind: String) -> void:
	if _inv(kind) <= 0 or not DRINKS.has(kind):
		return
	var eff: Array = DRINKS[kind]
	_hydration = minf(HYDRATION_MAX, _hydration + float(eff[0]))
	_health = minf(_p_max_health, _health + float(eff[1]))
	_energy = minf(ENERGY_MAX, _energy + float(eff[2]))
	_resources[kind] = _inv(kind) - 1
	_resources["cup"] = _inv("cup") + 1   # cup returns empty
	_refresh_context_panel()


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
	_refresh_context_panel()


func _craft(key: String) -> void:
	var r: Dictionary = CRAFT_RECIPES[key]
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
	_refresh_context_panel()


# --- Equipment ---------------------------------------------------------------
# Toggle a tool/weapon into its slot (clicking the equipped one bares fists again).
func _equip(kind: String) -> void:
	if _inv(kind) <= 0:
		return
	if kind in TOOL_ITEMS:
		_tool_equipped = "" if _tool_equipped == kind else kind
	elif kind in WEAPON_ITEMS:
		_weapon_equipped = "" if _weapon_equipped == kind else kind
	_refresh_context_panel()


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
			_resources["wood"] = _inv("wood") + 1 + _tool_bonus()
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
			_resources["wood"] = _inv("wood") + 1 + _tool_bonus()
	elif t == Terrain.BAMBOO:
		_set_terrain(c, Terrain.GRASS)
		_resources["bamboo"] = _inv("bamboo") + 2   # a clump yields a couple of canes
	elif t == Terrain.SAND:
		_resources["sand"] = _inv("sand") + 1        # the beach is an endless sand source
		# (tile stays sand; energy is the only limit)
	elif t == Terrain.STONE:
		_set_terrain(c, Terrain.GRASS)
		_resources["stone"] = _inv("stone") + 1 + _tool_bonus()
		if randf() < ORE_DROP_CHANCE:               # rocks sometimes hide metal ore
			_resources["metal_ore"] = _inv("metal_ore") + 1
		if randf() < 0.5:                            # ...and disturb a worm or two
			var nworms := 1 + (1 if randf() < 0.4 else 0)
			for _wi in range(nworms):
				_spawn_loot("worm", 1, _cell_center_world(c))
	else:
		return
	_facing = _cardinal(Vector2(c - _cell))
	_energy = maxf(0.0, _energy - ENERGY_HARVEST * _tool_energy_mult())
	queue_redraw()


# --- Punch (night melee, with a built-in out-and-back delay) ------------------
func _start_punch(aim_world: Vector2) -> void:
	if not _is_night or _punch_active or _build_mode or _freeze_t > 0.0:
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
		var kind: String = g["kind"]
		# Live critters (worm/bee) wander off if not jarred in time, so unclaimed
		# ones stop piling up on the ground forever (the "orbs never clear" bug).
		if (kind == "worm" or kind == "bee") and float(g["t"]) >= CRITTER_LOOT_LIFE:
			continue
		if (g["pos"] as Vector2).distance_to(_player_pos) <= LOOT_PICKUP_R + PLAYER_RADIUS:
			# Live critters (worm/bee) can only be scooped up if you have a glass jar.
			if kind == "worm" or kind == "bee":
				if _inv("glass_jar") <= 0:
					keep.append(g)   # no jar -> leave it crawling/buzzing (until it ages out)
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
	_refresh_context_panel()


func _delete_box_item(idx: int, kind: String, all: bool) -> void:
	if not _storage.has(idx):
		return
	var box: Dictionary = _storage[idx]
	if int(box.get(kind, 0)) <= 0:
		return
	box[kind] = 0 if all else int(box[kind]) - 1
	_refresh_context_panel()


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
	_open_storage = -1 if _open_storage == idx else idx
	_refresh_context_panel()


func _close_storage() -> void:
	if _open_storage != -1:
		_open_storage = -1
		_refresh_context_panel()


func _toggle_util(idx: int) -> void:
	_open_util = -1 if _open_util == idx else idx
	if _open_util != -1:
		_close_storage()
	_refresh_context_panel()


func _close_util() -> void:
	if _open_util != -1:
		_open_util = -1
		_refresh_context_panel()


# Barrels ferment, juicers press, planters grow -- runs every frame, day or night.
# Rebuild the set of energized tiles (live generators + the wires they reach) and
# drain a little oil from each running generator.
func _compute_power(delta: float) -> void:
	_energized.clear()
	var frontier := []
	for idx in _generators:
		var g: Dictionary = _generators[idx]
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
	_refresh_context_panel()


func _generator_toggle(idx: int) -> void:
	var g: Dictionary = _generators[idx]
	g["on"] = not bool(g["on"])
	_refresh_context_panel()


func _utility_tick(delta: float) -> void:
	_compute_power(delta)   # refresh the wire network + drain generators
	_compute_water()        # refresh which pipes carry pool water
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
	if _open_util >= 0:
		_util_refresh_t += delta
		if _util_refresh_t >= 0.5:
			_util_refresh_t = 0.0
			_refresh_context_panel()


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
	_refresh_context_panel()


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
	_refresh_context_panel()


func _barrel_empty(idx: int) -> void:
	var b: Dictionary = _barrels[idx]
	b["kind"] = ""; b["amount"] = 0; b["ferment"] = 0.0
	_refresh_context_panel()


func _juicer_add(idx: int) -> void:
	var j: Dictionary = _juicers[idx]
	if _inv("berry") <= 0:
		_set_msg("No fresh berries (rotten won't juice)."); return
	if int(j["juice"]) + int(j["pending"]) * JUICE_PER_BERRY >= JUICER_CAP:
		_set_msg("Juicer is full."); return
	_resources["berry"] = _inv("berry") - 1
	j["pending"] = int(j["pending"]) + 1
	_refresh_context_panel()


func _juicer_take(idx: int) -> void:
	var j: Dictionary = _juicers[idx]
	if int(j["juice"]) <= 0:
		return
	if _inv("cup") <= 0:
		_set_msg("Need an empty cup."); return
	_resources["cup"] = _inv("cup") - 1
	_resources["cup_juice"] = _inv("cup_juice") + 1
	j["juice"] = int(j["juice"]) - 1
	_refresh_context_panel()


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
	_refresh_context_panel()


# Queue a conversion: consume the raw input now, produce the output over time.
func _kiln_load(idx: int, input_item: String, output_item: String) -> void:
	var kl: Dictionary = _kilns[idx]
	if _inv(input_item) <= 0:
		_set_msg("No %s to process." % ITEM_LABELS.get(input_item, input_item)); return
	_resources[input_item] = _inv(input_item) - 1
	(kl["queue"] as Array).append(output_item)
	_refresh_context_panel()


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
	if randf() < 0.4:
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
	_refresh_context_panel()


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
	_refresh_context_panel()


func _wormfarm_take_worm(idx: int) -> void:
	var wf: Dictionary = _wormfarms[idx]
	if int(wf["worms"]) <= 0:
		return
	if _inv("glass_jar") <= 0:
		_set_msg("Need a glass jar to take a worm."); return
	_resources["glass_jar"] = _inv("glass_jar") - 1
	_resources["worm"] = _inv("worm") + 1
	wf["worms"] = int(wf["worms"]) - 1
	_refresh_context_panel()


func _wormfarm_add_rot(idx: int) -> void:
	var wf: Dictionary = _wormfarms[idx]
	if _rot_total() <= 0:
		_set_msg("No rot to compost."); return
	_consume_rot(1)
	wf["rot"] = int(wf["rot"]) + 1
	_refresh_context_panel()


# --- Campfire cooking --------------------------------------------------------
func _campfire_put(idx: int) -> void:
	var cf: Dictionary = _campfires[idx]
	if cf["item"] != "":
		_set_msg("Something's already on the fire."); return
	if _inv("fish_skewer") <= 0:
		_set_msg("Make a raw skewer first (rod + 3 fish)."); return
	_resources["fish_skewer"] = _inv("fish_skewer") - 1
	cf["item"] = "fish_skewer"; cf["cook"] = 0.0
	_refresh_context_panel()


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
	_refresh_context_panel()


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
	_refresh_context_panel()


func _aquarium_take_fish(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if int(aq["females"]) > 0:
		aq["females"] = int(aq["females"]) - 1; _give_item("fish_f", 1)
	elif int(aq["males"]) > 0:
		aq["males"] = int(aq["males"]) - 1; _give_item("fish_m", 1)
	else:
		return
	_refresh_context_panel()


func _aquarium_water(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if _inv("cup_water") <= 0:
		_set_msg("Need a cup of water."); return
	if int(aq["water"]) >= AQUARIUM_WATER_MAX:
		_set_msg("Tank is full."); return
	_resources["cup_water"] = _inv("cup_water") - 1
	_resources["cup"] = _inv("cup") + 1
	aq["water"] = int(aq["water"]) + 1
	_refresh_context_panel()


func _aquarium_feed(idx: int) -> void:
	var aq: Dictionary = _aquariums[idx]
	if _inv("worm") <= 0:
		_set_msg("Need a worm to feed the fish."); return
	_resources["worm"] = _inv("worm") - 1
	_resources["glass_jar"] = _inv("glass_jar") + 1
	aq["feed"] = float(aq["feed"]) + AQUARIUM_FEED_TIME
	_refresh_context_panel()


# --- Still: refine cups of juice into berry oil (dense, food-less fuel) -------
func _still_add(idx: int) -> void:
	var st: Dictionary = _stills[idx]
	if _inv("cup_juice") <= 0:
		_set_msg("Need a cup of juice to distill."); return
	_resources["cup_juice"] = _inv("cup_juice") - 1
	st["pending"] = int(st["pending"]) + 1
	_refresh_context_panel()


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


func _planter_plant(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if p["planted"]:
		return
	if _inv("seed") <= 0:
		_set_msg("Need a seed (harvest berries)."); return
	_resources["seed"] = _inv("seed") - 1
	p["planted"] = true; p["berries"] = 0; p["grow"] = 0.0; p["wet"] = PLANTER_DRY
	_refresh_context_panel()


func _planter_water(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if not p["planted"]:
		return
	if _inv("cup_water") <= 0:
		_set_msg("Need a cup of water."); return
	_resources["cup_water"] = _inv("cup_water") - 1
	_resources["cup"] = _inv("cup") + 1
	p["wet"] = PLANTER_DRY
	_refresh_context_panel()


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
	_refresh_context_panel()


func _planter_fertilize(idx: int) -> void:
	var p: Dictionary = _planters[idx]
	if not p["planted"]:
		return
	if _inv("fertilizer") <= 0:
		_set_msg("No fertilizer (compost rot in a worm habitat)."); return
	_resources["fertilizer"] = _inv("fertilizer") - 1
	p["fert"] = int(p.get("fert", 0)) + FERTILIZER_BONUS_HARVESTS
	_refresh_context_panel()


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
	_refresh_context_panel()


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
				if n > 0.45:
					t = Terrain.STONE
				elif rng.randf() < 0.10:
					t = Terrain.TREE
				elif rng.randf() < 0.04:
					t = Terrain.BUSH
				elif rng.randf() < 0.025:
					t = Terrain.COCONUT
				elif rng.randf() < 0.03:
					t = Terrain.BAMBOO
				elif rng.randf() < 0.006:
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
	# Lock in the starting wild-resource density; dawn re-seeding refills toward
	# this number but never past it, so the isle can't silt up into a maze.
	_natural_baseline = _natural_tile_count()
	_compute_pool_shore()


# Walkable land cells adjacent to the pool -- where crocs surface at night.
func _compute_pool_shore() -> void:
	_pool_shore = []
	for i in range(_terrain.size()):
		if _terrain[i] != Terrain.WATER:
			continue
		var c := _index_cell(i)
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if _in_bounds(n) and MONSTER_WALK.has(_terrain_at(n)) and not _pool_shore.has(n):
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
			if seen.has(ni) or BREAK_HP.has(_terrain[ni]):
				continue   # player structures act as walls of the enclosure
			seen[ni] = true
			stack.append(n)
	return false


func _set_terrain(c: Vector2i, t: int) -> void:
	var i := _cell_index(c)
	# Keep the structural-block tally in sync as tiles change (single choke point).
	if BLOCK_TERRAIN.has(_terrain[i]):
		_block_count -= 1
	if BLOCK_TERRAIN.has(t):
		_block_count += 1
	_terrain[i] = t
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
	return _in_bounds(c) and WALKABLE.get(_terrain_at(c), false)


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
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UI_ACCENT)
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
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
		_lbl_threat.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	elif _is_night:
		_lbl_threat.text = "NIGHT - monsters: %d" % _monsters.size()
		_lbl_threat.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		_lbl_threat.text = "Daytime - gather & build"
		_lbl_threat.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	for i in range(_life_pips.size()):
		_life_pips[i].color = Color(0.85, 0.25, 0.25) if i < _lives else Color(0.22, 0.22, 0.26)
	_lbl_nights.text = "Nights survived: %d   (best %d)" % [_nights_survived, _best_nights]
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
	var weapon_name := String(_weapon()["label"])
	if bool(_weapon().get("ranged", false)):
		weapon_name += "  (Ammo %d)" % _inv("sling_ammo")   # only ranged weapons show ammo
	_lbl_stats.text = "Atk %d   Armor %d%%\nSpd %.2fx   Regen %.1f/s\nTool: %s   Weapon: %s" % [
		int(round(_p_attack)), int(round(_p_armor * 100.0)),
		_p_speed / PLAYER_SPEED, _p_regen,
		tool_name, weapon_name
	]
	_lbl_wood.text = "Wood:  %d" % _inv("wood")
	_lbl_stone.text = "Stone: %d" % _inv("stone")
	var food_bits := []
	if _inv("banana") > 0: food_bits.append("Banana %d" % _inv("banana"))
	if _inv("berry") > 0: food_bits.append("Berry %d" % _inv("berry"))
	var rot := _inv("rotten_banana") + _inv("rotten_berry")
	if rot > 0: food_bits.append("Rotten %d" % rot)
	_lbl_food.text = "Food:  " + (", ".join(food_bits) if not food_bits.is_empty() else "none")


func _refresh_context_panel() -> void:
	if not _right_vbox:
		return
	for c in _right_vbox.get_children():
		_right_vbox.remove_child(c)
		c.queue_free()

	if _choosing_levelup:
		_build_levelup_panel()
	elif _craft_open:
		_build_craft_panel()
	elif _inv_open:
		_build_inventory_panel()
	elif _open_turret >= 0:
		_build_turret_panel(_open_turret)
	elif _open_util >= 0:
		_build_util_panel(_open_util)
	elif _open_storage >= 0:
		_build_storage_panel(_open_storage)
	elif _build_mode:
		_build_build_panel()
	else:
		_build_help_panel()


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
	_refresh_context_panel()
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
		"seed": _seed, "natural_baseline": _natural_baseline,
		"terrain": _terrain, "banana": _banana, "berry": _berry, "growth": _growth,
		"block_count": _block_count,
		"cell": _cell, "facing": _facing, "player_pos": _player_pos,
		"health": _health, "energy": _energy, "hydration": _hydration, "lives": _lives,
		"level": _level, "xp": _xp, "xp_to_next": _xp_to_next,
		"nights": _nights_survived, "stat_points": _stat_points, "alloc": _alloc,
		"tool": _tool_equipped, "weapon": _weapon_equipped, "gear_armor": _gear_armor,
		"resources": _resources,
		"time": _time, "day": _day, "banana_timer": _banana_timer, "is_night": _is_night,
		"barrels": _barrels, "juicers": _juicers, "planters": _planters, "lamps": _lamps,
		"kilns": _kilns, "apiaries": _apiaries, "wormfarms": _wormfarms, "campfires": _campfires,
		"stills": _stills, "generators": _generators, "sprinklers": _sprinklers,
		"aquariums": _aquariums, "fish": _fish, "monsters": _monsters,
		"projectiles": _projectiles, "poison_clouds": _poison_clouds,
		"night_snapshot": _night_snapshot, "struct_hp": _struct_hp, "turrets": _turrets,
		"trap_cd": _trap_cd, "traps": _traps, "peels": _peels, "storage": _storage,
		"burn_t": _burn_t, "slow_t": _slow_t, "freeze_t": _freeze_t,
		"snow_count": _snow_count, "snow_window": _snow_window,
		"best_nights": _best_nights,
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
	_natural_baseline = int(d.get("natural_baseline", 0))   # 0 -> lazily set on next dawn
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
	_time = float(d.get("time", 0.30))
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
	_fish = d.get("fish", [])
	_monsters = d.get("monsters", [])
	_projectiles = d.get("projectiles", [])
	_poison_clouds = d.get("poison_clouds", [])
	_night_snapshot = d.get("night_snapshot", {})
	_struct_hp = d.get("struct_hp", {})
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

	# Derived / transient state rebuilt from the restored world.
	_energized = {}
	_watered = {}
	_compute_pool_shore()
	_recompute_player_stats()
	_inv_open = false
	_craft_open = false
	_build_mode = false
	_build_struct = ""
	_dragging = false
	_drag_action = BuildAction.NONE
	_open_storage = -1
	_open_util = -1
	_open_turret = -1
	_choosing_levelup = false
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
				b.text = TURRET_DEFS[ty]["label"]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.pressed.connect(_configure_turret.bind(idx, ty))
				_right_vbox.add_child(b)
			var back := Button.new(); back.text = "< back"
			back.pressed.connect(_pick_turret_cat.bind(""))
			_right_vbox.add_child(back)
		return
	# Configured turret status + management.
	var def: Dictionary = TURRET_DEFS[t["type"]]
	_right_vbox.add_child(_label("%s   Lv %d%s" % [def["label"], int(t["level"]), ("  (BROKEN)" if t["broken"] else "")]))
	_right_vbox.add_child(_label("HP %d / %d" % [int(t["hp"]), int(t["max_hp"])]))
	_right_vbox.add_child(_label("Fuel %d%%   XP %d / %d" % [int(100.0 * float(t["fuel"]) / float(t["max_fuel"])), int(t["xp"]), int(t["xp_to_next"])]))
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
	_refresh_context_panel()


func _build_craft_panel() -> void:
	_right_vbox.add_child(_header("CRAFT"))
	_right_vbox.add_child(_label("Make items from materials."))
	_right_vbox.add_child(_sep())
	for key in CRAFT_ORDER:
		var r: Dictionary = CRAFT_RECIPES[key]
		var b := Button.new()
		b.text = "%s  (%s)" % [r["label"], _cost_text(r["cost"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = not _can_afford(r["cost"])
		b.pressed.connect(_craft.bind(key))
		_right_vbox.add_child(b)
	_right_vbox.add_child(_sep())
	_right_vbox.add_child(_label("Barrels, juicers + planters are"))
	_right_vbox.add_child(_label("placed from build mode (B)."))
	_right_vbox.add_child(_label("[C] close"))


func _build_inventory_panel() -> void:
	_right_vbox.add_child(_header("INVENTORY"))
	_right_vbox.add_child(_label("Drop items you don't want."))
	_right_vbox.add_child(_sep())
	var any := false
	for kind in INV_ORDER:
		if _inv(kind) <= 0:
			continue
		any = true
		var eqmark := ""
		if kind == _tool_equipped or (kind == _weapon_equipped and kind != ""):
			eqmark = "  [equipped]"
		_right_vbox.add_child(_label("%s  x%d%s" % [ITEM_LABELS.get(kind, kind), _inv(kind), eqmark]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if kind in TOOL_ITEMS or kind in WEAPON_ITEMS:
			var eq := Button.new()
			eq.text = "Unequip" if (kind == _tool_equipped or kind == _weapon_equipped) else "Equip"
			eq.pressed.connect(_equip.bind(kind))
			row.add_child(eq)
		if DRINKS.has(kind):
			var dr := Button.new()
			dr.text = "Drink"
			dr.pressed.connect(_drink.bind(kind))
			var em := Button.new()
			em.text = "Empty"
			em.pressed.connect(_empty_cup.bind(kind))
			row.add_child(dr)
			row.add_child(em)
		var d1 := Button.new()
		d1.text = "Drop 1"
		d1.pressed.connect(_delete_item.bind(kind, false))
		var dall := Button.new()
		dall.text = "Drop all"
		dall.pressed.connect(_delete_item.bind(kind, true))
		row.add_child(d1)
		row.add_child(dall)
		_right_vbox.add_child(row)
	if not any:
		_right_vbox.add_child(_label("(empty)"))
	_right_vbox.add_child(_sep())
	var rotten := _inv("rotten_banana") + _inv("rotten_berry")
	if rotten > 0:
		var clr := Button.new()
		clr.text = "Toss all rotten (%d)" % rotten
		clr.pressed.connect(_delete_rotten)
		_right_vbox.add_child(clr)
	_right_vbox.add_child(_label("[I] close"))


func _delete_rotten() -> void:
	_resources["rotten_banana"] = 0
	_resources["rotten_berry"] = 0
	_refresh_context_panel()


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
		var txt := "[%d] %s  (%s)" % [s["num"], s["label"], _cost_text(s["cost"])]
		if locked:
			txt += "  *needs workbench*"
		var b := Button.new()
		b.text = ("> " if key == _build_struct else "   ") + txt
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_select_struct.bind(key))
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
func _draw() -> void:
	var cell_vec := Vector2(CELL_SIZE, CELL_SIZE)
	for y in range(GRID_CELLS):
		for x in range(GRID_CELLS):
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
				var frac := 1.0 - float(_struct_hp[idx]) / float(BREAK_HP.get(_terrain[idx], 1))
				draw_rect(Rect2(pos, cell_vec), Color(0.0, 0.0, 0.0, 0.55 * frac), true)

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

	var side := float(GRID_CELLS) * CELL_SIZE
	for i in range(GRID_CELLS + 1):
		var off := float(i) * CELL_SIZE
		draw_line(Vector2(off, 0.0), Vector2(off, side), COLOR_GRID, 1.0)
		draw_line(Vector2(0.0, off), Vector2(side, off), COLOR_GRID, 1.0)

	if _build_mode:
		if _in_bounds(_hover_cell) and _mouse_in_board():
			var will_remove := _structure_key_for_terrain(_terrain_at(_hover_cell)) != ""
			var hl := COLOR_DESTROY_HL if will_remove else COLOR_BUILD_HL
			draw_rect(Rect2(Vector2(_hover_cell) * CELL_SIZE, cell_vec), hl, false, 3.0)
	elif _in_bounds(_hover_cell) and _mouse_in_board() and _chebyshev(_cell, _hover_cell) <= 1:
		# Highlight an adjacent interactable under the cursor (clickable).
		var ht := _terrain_at(_hover_cell)
		if ht == Terrain.TREE or ht == Terrain.STONE or ht == Terrain.STORAGE or ht == Terrain.BUSH \
				or ht == Terrain.WATER or ht == Terrain.BARREL or ht == Terrain.JUICER or ht == Terrain.PLANTER \
				or ht == Terrain.COCONUT or ht == Terrain.BAMBOO or ht == Terrain.GLAPPLE_LAMP \
				or ht == Terrain.SAND or ht == Terrain.KILN or ht == Terrain.HIVE \
				or ht == Terrain.BEE_ENCLOSURE or ht == Terrain.WORM_FARM or ht == Terrain.CAMPFIRE \
				or ht == Terrain.STILL or ht == Terrain.GENERATOR or ht == Terrain.AQUARIUM or ht == Terrain.SPRINKLER \
				or ht == Terrain.PEEL_LAUNCHER:
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
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im


func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < 16 and y >= 0 and y < 16:
		im.set_pixel(x, y, c)


func _disc(im: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(16):
		for x in range(16):
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


func _speckle(im: Image, c1: Color, c2: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(18):
		im.set_pixel(rng.randi() % 16, rng.randi() % 16, c1 if i % 2 == 0 else c2)


func _mktex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)


func _mirror(im: Image) -> Image:
	var out := _img16()
	for y in range(16):
		for x in range(16):
			out.set_pixel(15 - x, y, im.get_pixel(x, y))
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

	# CROCODILES -- one tinted set per roster type.
	for type in CROC_DEFS:
		var def: Dictionary = CROC_DEFS[type]
		var cr := _bake_croc_img(def["body"], def["belly"])
		_croc_tex[type] = {
			"r": _mktex(cr), "l": _mktex(_mirror(cr)),
			"fr": _mktex(_whiteout(cr)), "fl": _mktex(_whiteout(_mirror(cr))),
		}
	# Keep the legacy green handles for the demo/back-compat.
	_tex_croc_r = _croc_tex["green"]["r"]
	_tex_croc_l = _croc_tex["green"]["l"]
	_tex_croc_flash_r = _croc_tex["green"]["fr"]
	_tex_croc_flash_l = _croc_tex["green"]["fl"]


# A crocodile sprite (facing right) in the given body/belly colors.
func _bake_croc_img(body: Color, belly: Color) -> Image:
	var bd := body.darkened(0.35)
	var ceye := Color(0.95, 0.86, 0.30)
	var tooth := Color(0.96, 0.96, 0.90)
	var cr := _img16()
	_rect(cr, 0, 8, 3, 2, bd)                                # tail
	_rect(cr, 2, 7, 9, 4, body)                              # body
	_disc(cr, 3, 9, 2, body)
	_rect(cr, 10, 8, 6, 2, body)                             # snout
	_hline(cr, 10, 2, 9, belly)                              # belly
	_px(cr, 4, 6, bd); _px(cr, 6, 6, bd); _px(cr, 8, 6, bd)  # ridges
	_px(cr, 7, 6, body); _px(cr, 7, 5, ceye)                 # eye
	_px(cr, 12, 10, tooth); _px(cr, 14, 10, tooth)           # teeth
	return cr


# White silhouette of a sprite (same alpha) -- used for hit flashes.
func _whiteout(im: Image) -> Image:
	var out := _img16()
	for y in range(16):
		for x in range(16):
			var px := im.get_pixel(x, y)
			if px.a > 0.0:
				out.set_pixel(x, y, Color(1, 1, 1, px.a))
	return out


# -----------------------------------------------------------------------------
# Dev affordance: `--selftest` exercises the logic and quits.
# -----------------------------------------------------------------------------
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

	_cell = tree + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = tree + Vector2i(1, 0)
	_banana[_cell_index(tree)] = 1
	var ok_adj: bool = _click_interact(tree)  # adjacent click harvests
	var ok_pick: bool = ok_adj and _resources["banana"] == 1 and _terrain_at(tree) == Terrain.TREE
	_report("click-pick banana -> +banana, tree remains", ok_pick); fails += int(not ok_pick)
	_harvest_cell(tree)
	var ok_chop: bool = _resources["wood"] == 1 and _terrain_at(tree) == Terrain.STUMP
	_report("chop bare tree -> stump", ok_chop); fails += int(not ok_chop)

	_cell = stone + Vector2i(-1, 0)
	if not _in_bounds(_cell): _cell = stone + Vector2i(1, 0)
	_harvest_cell(stone)
	var ok_stone: bool = _resources["stone"] == 1 and _terrain_at(stone) == Terrain.GRASS
	_report("stone -> +1 stone (finite)", ok_stone); fails += int(not ok_stone)

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
	_player_pos = _cell_center_world(_cell)   # keep body position consistent with the cell

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
	_player_pos = _cell_center_world(_cell)   # body away from the regrown tiles at dawn
	_day = 1
	_begin_night()
	var ok_night: bool = _terrain_at(nt) == Terrain.GRASS and _terrain_at(ns) == Terrain.GRASS \
		and _monsters.size() == MONSTER_BASE and _is_night
	_report("night clears nature + spawns monsters", ok_night); fails += int(not ok_night)

	_begin_day()
	var ok_dayb: bool = _terrain_at(nt) == Terrain.TREE and _banana[_cell_index(nt)] == 1 \
		and _terrain_at(ns) == Terrain.STONE and _monsters.size() == 0 and not _is_night
	_report("dawn restores + replenishes, clears monsters", ok_dayb); fails += int(not ok_dayb)

	# --- Continuous movement / collision ---
	for xx in range(18, 28):
		_set_terrain(Vector2i(xx, 20), Terrain.GRASS)
	var start := _cell_center_world(Vector2i(20, 20))
	var moved := _move_collide(start, Vector2(12, 0), PLAYER_RADIUS, WALKABLE)
	var ok_free: bool = moved.x > start.x + 1.0
	_report("free movement across open ground", ok_free); fails += int(not ok_free)

	_set_terrain(Vector2i(21, 20), Terrain.WOOD_WALL)
	var blocked := _move_collide(start, Vector2(40, 0), PLAYER_RADIUS, WALKABLE)
	var ok_wall: bool = absf(blocked.x - start.x) < 0.01   # wall stopped the move
	_report("walls block free movement", ok_wall); fails += int(not ok_wall)

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

	# Blocked by a wall -> chews through it.
	_set_terrain(Vector2i(21, 20), Terrain.WOOD_WALL)
	_struct_hp.clear()
	_monsters = [_mk_croc(_cell_center_world(Vector2i(22, 20)), MONSTER_HP)]
	_monster_update(0.1)
	var widx := _cell_index(Vector2i(21, 20))
	var ok_break: bool = _struct_hp.get(widx, 99) == BREAK_HP[Terrain.WOOD_WALL] - 1
	_report("monster breaks a blocking wall", ok_break); fails += int(not ok_break)

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

	# --- Lives / game over ---
	_is_night = false
	_lives = MAX_LIVES
	_health = 10.0
	_damage_player(50.0)   # death
	var ok_life: bool = _lives == MAX_LIVES - 1 and _health == HEALTH_MAX
	_report("death costs a life and respawns", ok_life); fails += int(not ok_life)

	_lives = 1
	_resources = {"wood": 9, "stone": 9, "banana": 9, "berry": 0, "rotten_banana": 0, "rotten_berry": 0}
	_day = 5
	_health = 10.0
	_damage_player(50.0)   # last life -> game over reset
	var ok_over: bool = _lives == MAX_LIVES and _day == 1 and _resources["wood"] == 0
	_report("losing last life resets to a new run", ok_over); fails += int(not ok_over)

	# --- Stats / leveling / escalation ---
	_init_progression()
	var atk0 := _p_attack
	_gain_xp(_xp_to_next)   # exactly one level
	var ok_level: bool = _level == 2 and _stat_points == 1 and _choosing_levelup
	_report("leveling grants a stat point + choice", ok_level); fails += int(not ok_level)

	# Spending the point raises the chosen stat, full-heals, and clears the choice.
	_choose_stat("attack")
	var ok_choose: bool = _p_attack > atk0 and _stat_points == 0 and not _choosing_levelup \
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
	_time = 0.143            # just before dawn (night ends at f=0.145)
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

	# Burrowed brown croc can't be punched; surfaces near the player.
	var aim2 := get_global_mouse_position() - _player_pos
	aim2 = aim2.normalized() if aim2.length() > 1.0 else Vector2.RIGHT
	_monsters = [_mk_croc(_player_pos + aim2 * (PLAYER_RADIUS + PUNCH_REACH), 8.0, "brown")]
	_punch_active = false
	_start_punch(_player_pos + aim2 * 100.0)
	_update_punch(PUNCH_TIME * 0.5)
	var dig_invuln: bool = _monsters[0]["hp"] == 8.0
	_monsters[0]["dig"] = true
	_monsters[0]["pos"] = _player_pos + Vector2(CELL_SIZE * 1.5, 0)
	_monster_update(0.05)
	var ok_dig: bool = dig_invuln and not _monsters[0]["dig"]
	_report("brown croc digs (invuln) then surfaces", ok_dig); fails += int(not ok_dig)

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
	_choosing_levelup = false

	# Pink croc beelines for and wrecks a structure.
	_monsters = []
	_set_terrain(Vector2i(6, 5), Terrain.WOOD_WALL)
	_monsters = [_mk_croc(_cell_center_world(Vector2i(5, 5)), 30.0, "pink")]
	for _i in range(25):
		_monsters[0]["brk_cd"] = 0.0   # (the cooldown normally ticks in _monster_update)
		_update_wrecker(_monsters[0], 0.1, Vector2.RIGHT)
	var ok_pink: bool = _terrain_at(Vector2i(6, 5)) == Terrain.GRASS
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
	var ok_ore: bool = _inv("metal_ore") > 0 and _inv("stone") == 60
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
	var ok_toolyield: bool = _inv("stone") == 2   # 1 base + 1 tool bonus
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

	# --- Regression: playtest fixes (loot despawn, regrow cap, anti-wedge) ---
	# Uncollected worm/bee loot crawls off instead of piling up forever.
	_ground_items.clear()
	_cell = Vector2i(40, 40); _player_pos = _cell_center_world(_cell)
	_resources = _default_inventory()   # no glass jar
	_spawn_loot("worm", 1, _cell_center_world(Vector2i(5, 5)))   # far away, can't be reached
	_collect_ground_items(CRITTER_LOOT_LIFE + 1.0)
	var ok_critter: bool = _ground_items.is_empty()
	_report("uncollected worm/bee loot despawns", ok_critter); fails += int(not ok_critter)

	# ...but a worm under your feet with a jar is still caught.
	_ground_items.clear()
	_resources["glass_jar"] = 1
	_spawn_loot("worm", 1, _player_pos)
	_collect_ground_items(0.1)
	var ok_worm_jar: bool = _inv("worm") == 1 and _ground_items.is_empty()
	_report("worm loot caught with a jar", ok_worm_jar); fails += int(not ok_worm_jar)

	# Dawn re-seeding never grows past the world's baseline density.
	var nat_before := _natural_tile_count()
	_natural_baseline = nat_before
	_cell = Vector2i(45, 45); _player_pos = _cell_center_world(_cell)
	_regrow_world()
	var ok_regrow_cap: bool = _natural_tile_count() == nat_before
	_report("regrow respects baseline cap", ok_regrow_cap); fails += int(not ok_regrow_cap)

	# Dawn won't regrow a solid tile on top of the player (anti-wedge).
	var wedge_c := Vector2i(33, 33)
	_cell = wedge_c; _player_pos = _cell_center_world(wedge_c)
	_set_terrain(wedge_c, Terrain.GRASS)
	_night_snapshot.clear()
	_night_snapshot[_cell_index(wedge_c)] = {"t": Terrain.TREE, "banana": 0, "berry": 0}
	_is_night = true
	_begin_day()
	var ok_nowedge: bool = _terrain_at(wedge_c) == Terrain.GRASS
	_report("dawn won't regrow a tree onto the player", ok_nowedge); fails += int(not ok_nowedge)

	# Can't place a solid block onto a cell your body overlaps.
	_cell = Vector2i(36, 36)
	_player_pos = _cell_center_world(_cell) + Vector2(CELL_SIZE * 0.45, 0)   # body straddles +x neighbour
	var nbr := Vector2i(37, 36)
	_set_terrain(nbr, Terrain.GRASS)
	_resources = _default_inventory(); _resources["wood"] = 10
	_build_struct = "wood_wall"; _drag_action = BuildAction.BUILD
	_apply_build_at(nbr)
	var ok_buildwedge: bool = _terrain_at(nbr) == Terrain.GRASS
	_report("can't wall yourself into your own tile", ok_buildwedge); fails += int(not ok_buildwedge)

	# Adhesive turret's slow field must not stay painted on the ground all day.
	_turrets.clear()
	var adh_idx := _cell_index(Vector2i(28, 28))
	_turrets[adh_idx] = _new_turret(Vector2i(28, 28)); _configure_turret(adh_idx, "adhesive")
	_turrets[adh_idx]["field"] = _cell_center_world(Vector2i(30, 30))   # laid during the night
	_is_night = true; _night_snapshot.clear()
	_begin_day()
	var ok_field_clear: bool = (_turrets[adh_idx]["field"] as Vector2) == Vector2.INF
	_report("adhesive field clears at dawn (no permanent ground field)", ok_field_clear); fails += int(not ok_field_clear)
	_turrets.clear()

	# Quick win #13: a ranged weapon shows its ammo count in the status panel.
	_resources = _default_inventory()
	_resources["slingshot"] = 1; _resources["sling_ammo"] = 7
	_weapon_equipped = "slingshot"
	_update_status()
	var ok_ammo_hud: bool = _lbl_stats.text.contains("Ammo 7")
	_report("ranged weapon shows ammo in status", ok_ammo_hud); fails += int(not ok_ammo_hud)
	_weapon_equipped = ""

	# Quick win #16: water-adjacency helper that drives the drink hint.
	_set_terrain(Vector2i(40, 10), Terrain.WATER)
	_cell = Vector2i(40, 11)
	var ok_water_adj: bool = _adjacent_to_water()
	_cell = Vector2i(44, 11)
	var ok_water_far: bool = not _adjacent_to_water()
	_report("water-adjacency drives the drink hint", ok_water_adj and ok_water_far); fails += int(not (ok_water_adj and ok_water_far))
	_set_terrain(Vector2i(40, 10), Terrain.GRASS)

	_nights_survived = 0; _init_progression(); _day = 1; _resources = _default_inventory()

	print("SELFTEST DONE, failures=%d" % fails)
	get_tree().quit()


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
	_open_storage = _cell_index(b + Vector2i(1, 0))
	_refresh_context_panel()
	queue_redraw()


func _demo_night() -> void:
	_time = 0.92
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
			_time = 0.92; _apply_daylight(); _is_night = true
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
			_choosing_levelup = true
			_refresh_context_panel()
			_update_status()
		if "--turretfight" in args:
			_time = 0.92; _apply_daylight(); _is_night = true
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
			_open_turret = tix
			_refresh_context_panel(); _update_status()
		if "--turretmgr" in args:
			var tc2 := _cell + Vector2i(1, 0)
			_set_terrain(tc2, Terrain.TURRET)
			var tix2 := _cell_index(tc2)
			_turrets[tix2] = _new_turret(tc2)
			_configure_turret(tix2, "sniper")
			_turrets[tix2]["level"] = 5; _turrets[tix2]["points"] = 2
			_turrets[tix2]["xp"] = 7; _turrets[tix2]["hp"] = 9.0; _turrets[tix2]["fuel"] = 64.0
			_open_turret = tix2
			_refresh_context_panel(); _update_status()
		if "--craft" in args:
			_resources = _default_inventory()
			_resources["grass"] = 9; _resources["wood"] = 12; _resources["cup_water"] = 2; _resources["cup_juice"] = 1
			_hydration = 46.0
			_craft_open = true
			_refresh_context_panel(); _update_status()
		if "--util" in args:
			var jc := _cell + Vector2i(1, 0)
			_set_terrain(jc, Terrain.PLANTER)
			var pidx := _cell_index(jc)
			_planters[pidx] = {"planted": true, "berries": 2, "grow": 0.0, "wet": PLANTER_DRY}
			_set_terrain(_cell + Vector2i(2, 0), Terrain.BARREL)
			_set_terrain(_cell + Vector2i(1, 1), Terrain.JUICER)
			_resources = _default_inventory()
			_resources["seed"] = 3; _resources["cup_water"] = 2; _resources["berry"] = 4
			_open_util = pidx
			_refresh_context_panel(); _update_status()
		if "--inv" in args:
			_resources = {"wood": 24, "stone": 9, "banana": 5, "berry": 7, "rotten_banana": 2, "rotten_berry": 1}
			_inv_open = true
			_refresh_context_panel()
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
		for _i in range(3):
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
