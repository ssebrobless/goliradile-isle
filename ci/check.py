#!/usr/bin/env python3
"""Compare the headless tool outputs in ci/out with ci/baselines.json.

Exits non-zero when anything is outside its band. The balance table is deterministic and is
compared exactly; soak and defense depend on unseeded randomness (until the Rng service,
ROADMAP P0-06), so they use bands.
"""
import json
import re
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
update = "--update-balance" in sys.argv
base_path = Path(__file__).with_name("baselines.json")
failures = []


def read(name):
    p = out_dir / f"{name}.txt"
    return p.read_text(errors="replace") if p.exists() else ""


def exit_code(name):
    p = out_dir / f"{name}.exit"
    return int(p.read_text().strip()) if p.exists() else None


def fail(msg):
    failures.append(msg)
    print("FAIL", msg)


def ok(msg):
    print("ok  ", msg)


# --- Selftest --------------------------------------------------------------------------
text = read("selftest")
m = re.search(r"SELFTEST DONE, failures=(\d+)", text)
if not m:
    fail("selftest did not finish (no 'SELFTEST DONE' line)")
else:
    n = int(m.group(1))
    bad = [l for l in text.splitlines() if l.startswith("FAIL")]
    if n or bad or exit_code("selftest") != 0:
        fail(f"selftest: {n} failures, exit {exit_code('selftest')}: " + "; ".join(bad[:5]))
    else:
        ok("selftest: 0 failures")

# --- Balance table (exact) ---------------------------------------------------------------
rows = [" ".join(l.split()) for l in read("balance").splitlines() if re.match(r"^\s*\d+\s+\d+\s+\|", l)]
if update:
    data = json.loads(base_path.read_text())
    data["balance_rows"] = rows
    base_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"updated balance baseline ({len(rows)} rows)")
else:
    base = json.loads(base_path.read_text())
    if rows != base["balance_rows"]:
        fail("balance table changed (run with --update-balance if intentional)")
    else:
        ok(f"balance table unchanged ({len(rows)} rows)")

base = json.loads(base_path.read_text())

# --- Soak ----------------------------------------------------------------------------------
text = read("soak")
m = re.search(r"SOAK runs=(\d+) croc-in-solid=(\d+) stalled-with-route=(\d+) player-in-solid=(\d+)", text)
if not m:
    fail("soak did not finish")
else:
    runs, solid, stalled, psolid = map(int, m.groups())
    s = base["soak"]
    if solid > s["max_croc_in_solid"] or psolid > s["max_player_in_solid"] or stalled > s["max_stalled"]:
        fail(f"soak: croc-in-solid={solid} player-in-solid={psolid} stalled={stalled} outside {s}")
    else:
        ok(f"soak: croc-in-solid={solid} stalled={stalled} player-in-solid={psolid}")
m = re.search(r"SOAK profile: _monster_update avg ([\d.]+) ms/frame", text)
if m:
    ms = float(m.group(1))
    limit = base["soak"]["max_ms_per_frame"]
    (fail if ms > limit else ok)(f"croc update cost {ms:.2f} ms/frame (limit {limit})")

# --- Defense -------------------------------------------------------------------------------
d = base["defense"]
seen = {}
for l in read("defense").splitlines():
    parts = [p.strip() for p in l.split("|")]
    if len(parts) >= 7 and parts[0].isdigit():
        km = re.match(r"(\d+)\s*/\s*(\d+)", parts[2])
        if km:
            seen[(int(parts[0]), parts[1])] = (int(km.group(1)), int(km.group(2)))
if not seen:
    fail("defense produced no table")
else:
    for key, minfrac in d["min_kill_fraction"].items():
        night, layout = key.split(":")
        kills = seen.get((int(night), layout))
        if kills is None:
            fail(f"defense: missing row {key}")
        elif kills[1] and kills[0] / kills[1] < minfrac:
            fail(f"defense {key}: killed {kills[0]}/{kills[1]}, below {minfrac:.0%}")
        else:
            ok(f"defense {key}: killed {kills[0]}/{kills[1]} (min {minfrac:.0%})")
    for (night, layout), (k, t) in seen.items():
        if layout == "none" and k > d["control_kills_max"]:
            fail(f"defense night {night} with no turrets killed {k} (control must be {d['control_kills_max']})")

print()
if failures:
    print(f"{len(failures)} check(s) failed")
    sys.exit(1)
print("all checks passed")
