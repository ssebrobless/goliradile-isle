# Goliradile Isle

A top-down pixel-art survival / resource-management / action game built in **Godot 4.6**.
You're a gorilla on a crocodile-infested island: gather by day, build a base, and
survive escalating nights. The twist is the tech — recognizable machines (generators,
filters, refineries) rebuilt out of jungle junk for comedic effect.

## Download & play

Grab a build from the [**Releases**](../../releases) page:

- **Windows** — `GoliradileIsle.exe` (single self-contained file; just double-click).
- **macOS** — `GoliradileIsle.zip` → unzip to get `Goliradile Isle.app`.
  The build is **unsigned**, so the first launch needs a Gatekeeper bypass:
  **right-click the app → Open → Open**, or run
  `xattr -dr com.apple.quarantine "Goliradile Isle.app"` in Terminal.

## Controls

| Key / action | Effect |
|---|---|
| **WASD** | Move |
| **Left-click** | Day: gather / open an adjacent object · Night: punch or shoot at the cursor |
| **B** | Build mode (pick a structure, click grass to place; click a structure to remove) |
| **C** | Craft menu |
| **I** | Inventory (drop items, equip tools/weapons) |
| **E** | Eat · **Q** | Drink |
| **O** | Options — window size (1280×720 / 1600×900 / 1920×1080 / 2560×1440) + fullscreen |

The whole view scales to fit the window, so any size keeps the same layout.

## The loop

- **Day:** gather wood/stone/grass/bananas/berries/coconuts/bamboo/ore/sand, build a base,
  craft tools, weapons, machines, and defenses.
- **Night:** the land clears and crocodiles hunt you — nine color-coded types that each
  fight differently. Turrets, traps, and a powered defense network do the heavy lifting.
- **Tech ladder:** kiln → metal/glass → bees/worms/fish/farming → berry-oil still →
  generators + wires (powered turrets) → pipes + a breeding aquarium. Deep nights demand
  a generator-powered defense — hand-poured wine can't keep up.

## Building from source

Open the project in Godot 4.6.x and run `Main.tscn`, or export via the included
`export_presets.cfg`. A headless self-test suite runs with:

```
godot --headless --path . -- --selftest
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
