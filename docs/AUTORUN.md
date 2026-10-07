# Unattended run — goal and rules

How to leave Claude running on Phase 0 without supervision. The **goal text** to paste is at
the bottom; everything above it is the rulebook the goal points to.

## Scope of one run

Phase 0 tasks **P0-03 … P0-18** from `ARCHITECTURE.md` section 11, in the confirmed order:

1. P0-03, P0-04, P0-05, P0-15, P0-16 (low-risk extractions)
2. P0-06 (Rng), P0-07 (events), P0-08 (Grid), P0-09 (Inventory)
3. P0-10 (PlayerState), P0-11 (fixed tick + commands)
4. P0-13 (split selftests), P0-12 (save v2), P0-14 (remaining splits, one PR per area)
5. P0-17 (perf gates), P0-18 (repo guide)

Phase 0 is "no behaviour change". Anything that would change gameplay is **out of scope**
and is recorded as a note, not done.

## Per-task loop

1. Start from the latest base (see Git mode). Re-read the task row and its acceptance test.
2. Run `ci/run_checks.sh` first to prove the baseline is green *before* touching anything.
3. Make the change in small steps (strangler pattern: new code beside old, switch over, delete
   old). Keep `Main.gd` working at every commit.
4. Run `ci/run_checks.sh` plus `--shot` comparisons where the task says so. All must pass
   with `ci/baselines.json` **unchanged** (except tasks that explicitly add baselines:
   P0-06 may tighten soak/defense to exact values once Rng is seeded; P0-17 adds perf).
5. Add the tests the acceptance column asks for. Bug fixes add a test that fails first.
6. Update the docs touched (ROADMAP checkbox, ARCHITECTURE progress note) in the same PR.
7. Open one PR per task, description = what, how verified, anything surprising. Wait for CI.
   Fix red CI on that PR (root cause; never skip/disable a test, never loosen a baseline to
   get green).
8. Move to the next task per Git mode.

## Git mode

**Recommended — stacked PRs, one task each.** Each task gets its own branch
`claude/p0-NN-short-name`, branched from the previous task's branch (first one from `main`),
and a PR whose base is the previous task's branch (first one targets `main`). The owner
merges in order; GitHub retargets the next PR automatically when its base merges.
Claude **never merges**.

This needs the owner to allow pushes to branches other than
`claude/peaceful-fermi-y02kvt` for this run. If that is not allowed, fall back to:
**single branch, one commit per task, one rolling PR** — less reviewable, same checks.

## Hard stops (the run ends and reports; it does not push through)

- Two consecutive attempts at the same task fail CI for a reason Claude cannot root-cause.
- A task would need a gameplay/balance change, a design decision not in `DECISIONS.md`, or
  a baseline loosened.
- `--selftest`, `--balance` or soak show a regression that appears on the base branch too
  (report it; do not paper over it).
- Anything outward-facing beyond PRs on this repo: no merging, no force-pushes, no
  deleting branches, no changing repo settings, no new dependencies or assets with
  unreviewed licences, no secrets.
- More than **6 open unmerged PRs** in the stack: stop and wait for the owner (keeps
  review load and rebase risk bounded).

## Reporting

At the end (or at any hard stop) leave a single status comment on the newest PR and a short
summary in chat: tasks done (with PR links), tasks skipped and why, anything surprising,
numbers that moved (timings), and what the owner must do next (merge order, playtest
checkpoint).

## Owner checklist before starting

- [ ] Confirm Git mode (stacked PRs need push access to `claude/p0-*` branches).
- [ ] Merge or close PR #9 (CI skeleton) so the stack starts from a green `main`.
- [ ] Decide how long the run may go (the goal below stops at the end of the list or at a
      hard stop, whichever comes first).

## Goal text (paste this)

> Execute Phase 0 tasks P0-03 through P0-18 of `docs/ARCHITECTURE.md` section 11 in the order
> given in `docs/AUTORUN.md`, following its per-task loop, Git mode, hard stops and
> reporting rules. No behaviour changes. Every PR must pass `ci/run_checks.sh` with
> baselines unchanged (except where the task adds them). Never merge, never loosen a
> baseline, never skip a test. Stop and report at the first hard stop or when P0-18 is done.
