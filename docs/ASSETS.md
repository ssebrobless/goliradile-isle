# Goliradile Isle — Assets, licences and credits

Status: **draft for owner review.** This is the policy for every piece of art and audio that
ships in the game. The decision (DECISIONS I2 and I3): **use free, open-licensed assets and
credit the creators in the game's end credits.** Nothing here is legal advice; when a licence
is unclear, don't use the asset.

## Rules

1. **Every asset has a manifest entry** (see below) before it is committed.
2. **Only these licences are allowed:**
   - **CC0 / public domain** (no conditions).
   - **CC-BY** (credit required).
   - **Permissive software or font licences:** MIT, BSD, Apache-2.0, SIL OFL (fonts).
3. **Not allowed:**
   - **Non-commercial (NC)** licences. The game is sold.
   - **No-derivatives (ND)** licences. We edit and recolour assets.
   - **GPL, LGPL or other copyleft licences for art and audio** unless the owner has decided
     it is acceptable.
4. **Share-alike (SA) licences** (for example CC-BY-SA) only after the owner approves. They
   can require derived assets to be shared under the same terms, which is a risk for a
   commercial game.
5. **Unclear or missing licence → not used.** If an asset page has no licence, or says
   "free for personal use", skip it.
6. **Attribution is automatic:** the credits screen is generated from the manifest.
7. **No AI-generated art or audio is planned for shipping.** If that changes, it needs an
   owner decision and Steam's disclosure rules checked first.
8. **Keep proof.** Save the licence text or a copy of the page (a URL plus a saved copy)
   with the asset; licence pages change.
9. **Check at download time.** The licence that applies is the one on the page when we took
   the asset, not what a search result said.

## Where to look (and what to verify)

Places that commonly host open-licensed game assets. Always verify the licence **per asset**:
- **Kenney.nl** (large sets, generally CC0).
- **OpenGameArt.org** (mixed licences; filter by CC0 and CC-BY, and check each entry).
- **itch.io free asset packs** (licence is per pack and varies).
- **Freesound.org** (sound effects, licence per sound; avoid CC-BY-NC).
- **Incompetech / Kevin MacLeod and similar music libraries** (CC-BY: credit is mandatory).
- **Google Fonts / Font Squirrel** for fonts (OFL or similar).

## Manifest

One file, **`assets/MANIFEST.csv`**, one row per asset or per pack:

| Field | Meaning |
|---|---|
| `path` | path(s) in the repo (a folder is allowed for a pack) |
| `kind` | `sprite`, `tileset`, `ui`, `font`, `sfx`, `music` |
| `title` | asset or pack name |
| `author` | creator's name as they ask to be credited |
| `source_url` | page we downloaded it from |
| `licence` | `CC0`, `CC-BY-4.0`, `MIT`, `OFL-1.1`, ... (exact SPDX-style id) |
| `licence_url` | link to the licence text |
| `modified` | `yes` or `no` (CC-BY needs changes indicated) |
| `proof` | path to the saved copy of the licence/page |
| `notes` | anything unusual |

**CI check (ROADMAP 0.8):** every file under `assets/` appears in the manifest; every
`licence` is on the allowed list; `NC` and `ND` never appear; `SA` and any unknown licence fail
until the owner adds an explicit exception.

## Credits

- The **end-credits screen** is generated from the manifest, grouped by author, with licence
  names and links where the licence requires them and a note where an asset was modified.
- The credits **play automatically after the first win only** and are replayable from a
  **Credits** button in the main menu. They include the dedication, **"For William."**
- A **Credits** text file is shipped with the game for platforms or users who want it.

## Style: keeping 16 px art coherent

Assets from many artists tend to look inconsistent. To keep one look:
- **Tiles are 16 px.** Sprites are 16 px multiples (bosses are multi-tile).
- Prefer **one or two coherent packs** for the core tiles and characters, and edit the rest to
  match.
- A **shared palette** (about 32 colours) defined in the repo; recolour assets to it.
- Consistent **outline and shading** rules (for example 1 px dark outline, top-left light).
- Edits are allowed under the allowed licences; record `modified: yes`.

## What must be made or edited by us

Open packs rarely include these, so plan custom or edited work:
- **The 10 bosses** (multi-tile, animated, with attack and phase poses).
- **Gorilla** (player) and **palette-swapped co-op variants**.
- **Croc types** with a distinct **shape or icon** each, not just a colour (accessibility).
- **Terrain-event art** (fire, ice, flood, quake, corruption, darkness).
- **UI** for perks, gear, attunement, map, Hall of Fame.
- **Station and automation art** (belts, miners, assemblers, feeders).

## Audio

- **Sound effects:** replace today's synthesised placeholders with open-licensed recordings
  under the same policy; keep the synthesised sounds as fallbacks until replaced.
- **Music:** calm by day, tense by night, with unique boss tracks where available. Prefer
  pieces that loop cleanly; boss music can change by phase (layers or separate tracks).
- Record the **track length and loop points** in the manifest notes.

## Today's art and audio

Everything in the current build is **procedural placeholder** art and sound generated in code.
It does not need a manifest entry, and it is removed from the shipped game as real assets
arrive (ROADMAP 6.2 and 6.3).

## Adding an asset: checklist

1. Confirm the licence is allowed (rules above). If unsure, ask.
2. Download it and save the licence page or text.
3. Add the manifest row.
4. Commit the asset, the manifest row and the proof together.
5. CI must pass.
