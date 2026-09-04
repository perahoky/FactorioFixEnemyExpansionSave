
> **Disclaimer:** AI-generated (GitHub Copilot, Claude Opus 5), executed and reviewed by me to the best of
> my knowledge and belief, but provided **as is, without warranty**. It permanently changes
> map settings inside your save — back it up first. Use at your own risk; I accept no
> liability for damaged saves or lost progress.
# fix-enemy-expansion-save

A small Factorio **2.1** mod that repairs `map_settings.enemy_expansion` in a save that was
permanently boosted by the retired *Dynamic Biter Expansion* feature of
[`smart-enemy-ai`](https://mods.factorio.com/mod/smart-enemy-ai) — **without** disabling
achievements for that save.

## Why not the console command?

The fix suggested on the mod portal is a `/c` command. Per the Factorio wiki, script
commands (`/c`, `/command`, `/silent-command`) **permanently** flag the save as cheated;
achievements stay off forever and the only known way back is binary-editing the save.

A mod does not do that. It switches the game to its separate modded-achievement instance
(`achievements-modded.dat`) — a per-session distinction, not a brand burnt into the save.
Commands that a mod registers with `commands.add_command` are ordinary commands and do
**not** set the cheat flag either.

## Why the damage survives uninstalling the mod

`game.map_settings` is engine state **stored inside the save file**. `smart-enemy-ai` wrote
into it; when the mod is removed, nothing runs any more to put the values back. This mod
uses exactly the same mechanism in reverse, which is why its fix is equally permanent —
`test-persistence.ps1` proves that end to end.

Note that `smart-enemy-ai` gained its own restore path in 10.9.4 (`MIGRATIONS[19]`), but it
only works while the mod is still enabled, and it deletes its snapshot after running once.
If the mod is already disabled or removed, that route is gone.

## The forum command is wrong for 2.1

The numbers quoted in the discussion are Factorio **1.1** values. Checked against
`data\base\prototypes\map-settings.lua` of the installed 2.1.17:

| Field | Forum command | **Real 2.1 base** | This mod's default |
| --- | --- | --- | --- |
| `min_expansion_cooldown` | 14400 | **36000** | **14400** |
| `max_expansion_cooldown` | 216000 | 216000 | 216000 |
| `settler_group_min_size` | 5 | 5 | 5 |
| `settler_group_max_size` | 20 | **10** | **20** |
| `max_expansion_distance` | 7 | **5** | 5 |
| `min_expansion_distance` | — | 3 | 3 |
| `enabled` | forced | true | **left alone** |

The defaults ship slightly more aggressive than 2.1 base on purpose (faster first
expansion, larger settler groups). Change any of them in-game — see *Settings* below.

`evolution_group_size_factor` (base `8.0`) is new in 2.x and is **prototype-only**: it is
not part of the runtime `EnemyExpansionMapSettings`, so no mod could have broken it and no
mod can write it. `build_base_unit_dispatch_cooldown` is reported but never written.

## Workflow

### 0. Back up the save

```powershell
Copy-Item "$env:APPDATA\Factorio\saves\your-save.zip" "$env:APPDATA\Factorio\saves\your-save.backup.zip"
```

### 1. Build

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Produces `dist\fix-enemy-expansion-save_1.0.0.zip`. The script only ever writes into
`dist\` and the only thing it deletes is a previous copy of that one zip file.

### 2. Install — this step is yours

The tooling in this repo deliberately never writes into your Factorio directories:

```powershell
Copy-Item '.\dist\fix-enemy-expansion-save_1.0.0.zip' "$env:APPDATA\Factorio\mods\"
```

### 3. Run it

1. **Restart Factorio.** The mod list is only read at startup.
2. Enable *Fix Enemy Expansion Save* in the mod list, restart when prompted.
3. Load the affected save. The mod applies on `on_init` and prints the diff to chat:

   ```
   [fix-enemy-expansion-save] applied (mod added to this save):
   [fix-enemy-expansion-save]   max_expansion_cooldown: 3600 -> 216000
   [fix-enemy-expansion-save]   min_expansion_cooldown: 1800 -> 14400
   [fix-enemy-expansion-save]   settler_group_max_size: 60 -> 20
   [fix-enemy-expansion-save]   settler_group_min_size: 20 -> 5
   [fix-enemy-expansion-save]   max_expansion_distance: 20 -> 5
   [fix-enemy-expansion-save] verified: every value was accepted by the engine.
   [fix-enemy-expansion-save] save the game now - these values live in the save and stay after this mod is removed.
   ```

   The same lines land in `factorio-current.log`, so you can check afterwards.
4. Adjust anything you want in *Settings → Mod settings → Map* — every change re-applies
   immediately. `/expansion-status` shows current vs. target vs. 2.1 base at any time.
5. **Save the game.** Nothing is persisted until you do.
6. Optional: disable or remove the mod. Factorio warns that "data will be lost" — that is
   only this mod's own `storage`; the map settings you wrote stay.

> **Verify before you remove the mod.** Once it is gone, the only in-game way to read
> `map_settings` back is `/c` — the very thing we are avoiding.

## Settings

All settings are **runtime-global**: stored in the map, admin-editable in-game, effective
immediately.

| Setting | Default | Meaning |
| --- | --- | --- |
| `feas-dry-run` | `false` | Report the diff, change nothing |
| `feas-enabled-mode` | `leave` | `leave` / `on` / `off` for the expansion on-off flag |
| `feas-min-cooldown` | `14400` | `min_expansion_cooldown` (ticks) |
| `feas-max-cooldown` | `216000` | `max_expansion_cooldown` (ticks) |
| `feas-settler-min` | `5` | `settler_group_min_size` |
| `feas-settler-max` | `20` | `settler_group_max_size` |
| `feas-min-distance` | `3` | `min_expansion_distance` (chunks) |
| `feas-max-distance` | `5` | `max_expansion_distance` (chunks) |
| `feas-kill-scope` | `none` | One-shot unit cleanup, see below |

`feas-enabled-mode` defaults to `leave` because there is no way to know whether your map
was *generated* with expansion disabled. Set it to `off` only if you know it was.

Contradictory values (`min > max` for cooldown, group size or distance) abort the whole
apply with an explanation instead of silently clamping.

### Unit cleanup

The forum command also runs `kill_all_units()`, to clear settler groups that are already
en route with the old parameters. That is destructive, so it is **off by default**:

- `none` — nothing is killed (default).
- `nauvis` — destroys enemy entities of type `unit` on Nauvis only. Nests and worms are
  untouched. Other planets keep their fauna.
- `all` — `game.forces.enemy.kill_all_units()` across all surfaces (including Gleba), which
  also flushes the pathfinder.

It runs once per toggle, guarded by a flag in `storage`; switching back to `none` re-arms
it. With `feas-dry-run` on, it only counts.

## Commands

| Command | Effect |
| --- | --- |
| `/expansion-status` | Read-only dump: current \| target \| 2.1 base |
| `/expansion-fix` | Re-apply on demand (admin only) |

If another mod already owns those names, they are registered as `/feas-status` and
`/feas-fix` instead; the log line tells you which.

## What this mod never does

Grep-verifiable against `control.lua`: no `player.cheat_mode`, no `unlock_achievement`, no
script/cheat command, and no write anywhere except `map_settings.enemy_expansion` plus the
opt-in unit cleanup.

`unlock_achievement` is worth naming explicitly: it is the *only* achievement-related API a
mod has, there is no API to disable achievements, and handing out achievements from a
repair mod would be exactly the kind of cheating this whole exercise avoids.

## Repo layout

Hard rule: `fix-enemy-expansion-save\` contains **only files that ship inside the mod**.
Every script lives above it. This is kept by construction, not enforced by a check.
`feas-test-harness\` is a mod package too, but a test-only one that is never published.

```
FactorioFixEnemyExpansionSave\        <- tooling only
  build.ps1                           <- packages the mod into dist\
  Find-Factorio.ps1                   <- locates Factorio.exe, no hard-coded paths
  test-headless.ps1                   <- isolated smoke test
  test-persistence.ps1                <- isolated save-persistence test
  README.md
  .gitignore
  dist\                               <- build output (generated)
  fix-enemy-expansion-save\           <- MOD CONTENT ONLY, this is what ships
    info.json
    settings.lua
    control.lua
    changelog.txt
    locale\en\fix-enemy-expansion-save.cfg
  feas-test-harness\                  <- second mod, test-only, never published
    info.json
    control.lua
```

`build.ps1` adds the zip entries one by one rather than using
`ZipFile::CreateFromDirectory`, because on Windows PowerShell 5.1 that helper writes entry
names with a backslash separator — Factorio would then see `locale\en\x.cfg` as a single
flat file name and never load the locale.

## Testing

Two tests, both fully isolated: each writes its own `config.ini` whose `write-data`
points into a throwaway directory and passes `--mod-directory`, so the instance gets its
own mod list, `mod-settings.dat`, saves and `factorio-current.log`. `%APPDATA%\Factorio`
is neither read nor written, and both can run while your game is open. Neither test ever
deletes its directory - remove it yourself when you are done.

They differ in *what* they prove, not in how they run:| | `test-headless.ps1` | `test-persistence.ps1` |
| --- | --- | --- |
| Proves | the mod writes the values and the engine accepts them | the values survive saving **and** removing the mod |
| Asserts | every `old -> new` line, the read-back verification, no Lua errors | six values read back out of the save, repair mod provably gone |
| Needs | one `--benchmark` run, ~20 s | a server run plus a benchmark run, ~60 s |

The overlap is a single assertion: `test-persistence.ps1` also checks `applied (...)` in
phase 1, but only as a precondition, so that a broken mod cannot masquerade as broken
persistence. The per-field diff and the read-back check exist only in the smoke test.

Both find Factorio themselves via `Find-Factorio.ps1`: `FACTORIO_EXE`, then every Steam
library folder, then the usual standalone locations. Override with
`-FactorioExe <path>` if it guesses wrong.

### 1. Smoke test - does the mod repair the live values?

```powershell
powershell -ExecutionPolicy Bypass -File .\test-headless.ps1
```

Runs in `%TEMP%\feas-test`:

1. Create a **deliberately damaged** map via `--create` + `--map-settings` with a boosted
   `enemy_expansion` block — no console command involved.
2. Copy the built zip into the isolated mod directory and enable it.
3. `--benchmark --benchmark-ticks 60`; loading a save with a newly added mod fires
   `on_init`, which is where the repair happens.
4. Assert on the isolated log: every boosted field shows the expected `old -> new` line,
   the engine read-back verification passed, and no Lua error mentions the mod.

### 2. Persistence test - does it survive saving and removing the mod?

```powershell
powershell -ExecutionPolicy Bypass -File .\test-persistence.ps1
powershell -ExecutionPolicy Bypass -File .\test-persistence.ps1 -Visual
```

The smoke test cannot answer this, because `--benchmark` never writes the save back.
This one runs in `%TEMP%\feas-persist-test` and closes the gap in two phases:

| | Phase 1 | Phase 2 |
| --- | --- | --- |
| Mods | repair mod + harness | **harness only** |
| Map | the damaged fixture | the autosave from phase 1 |
| What happens | the mod repairs the values, then the harness calls `game.auto_save()` | the harness reports what is actually in the save |

Between the phases the mod zip is deleted and dropped from `mod-list.json`. Phase 2 then
asserts that all six values are still correct, that the repair mod produced **no** output,
and that `script.active_mods` no longer contains it. If the numbers are still right while
the mod is provably gone, the fix lives in the save and not in the mod.

The reporting is done by `feas-test-harness\`, a second mod package in this repo. It is
copied into the throwaway instance and never published or installed into a real game;
nothing test-related is added to the shipped mod. It decides its own phase from
`script.active_mods`, so the two runs cannot be mixed up in the log.

With `-Visual` both phases open a real game window instead, so you can watch the mod work
and read the messages in the chat. Factorio does not exit by itself there — quit each
window yourself (Esc → Quit) and the script continues.

`-Visual` is a demo mode, **not** a third test: same two phases, same assertions, nothing
extra is proven. Because it needs you to close two windows it cannot be automated, so the
headless run stays the one that actually gets run.

Three engine details this test had to work around:

- **`--benchmark` silently ignores `game.auto_save()`.** The call is accepted, no error is
  logged, and no file is ever written. Headless phase 1 therefore runs `--start-server`
  and is stopped once the log confirms `Saving finished`. Phase 2 writes nothing, so it
  stays a benchmark.
- **A server pauses when nobody is connected**, and a paused game never reaches the tick
  that triggers the save. The generated `server-settings.json` sets `auto_pause: false`.
- **A Steam build re-launches itself**, so in `-Visual` mode the process `Start-Process`
  returns exits within a second while the game keeps running. Waiting on that handle makes
  the script race ahead of the game. It waits for Factorio's own `Goodbye` log line
  instead, which is the last thing a clean shutdown writes.

## Verified environment

Factorio 2.1.17 (build 87315, win64, steam, Space Age), runtime API version 6.
