--------------------------------------------------------------------------------
-- Test harness for fix-enemy-expansion-save. Not a mod anybody should install.
--
-- test-persistence.ps1 copies this folder into a throwaway Factorio instance and runs
-- it twice against the same map:
--
--   phase 1  fix-enemy-expansion-save is loaded. It repairs the values on on_init,
--            then this harness triggers an autosave, so the repaired state is written
--            into a save file.
--   phase 2  the repair mod is deleted. This harness loads that autosave and reports
--            what map_settings.enemy_expansion actually contains.
--
-- If phase 2 still shows the repaired numbers, the fix lives in the save and not in
-- the mod - which is exactly the claim that --benchmark alone cannot prove.
--
-- Which phase we are in is not passed in from outside: script.active_mods decides it,
-- so the two runs cannot be mixed up and the log tag is always truthful.
--------------------------------------------------------------------------------

local PREFIX = "[feas-harness] "
local TARGET_MOD = "fix-enemy-expansion-save"
local AUTOSAVE_NAME = "feas-persist"

local KEYS = {
  "enabled",
  "min_expansion_cooldown",
  "max_expansion_cooldown",
  "settler_group_min_size",
  "settler_group_max_size",
  "min_expansion_distance",
  "max_expansion_distance",
}

-- Deliberately a plain local and not storage: storage would be written into the
-- autosave and would then suppress the report when that save is loaded in phase 2.
local reported = false

-- Same text to log and chat, so the assertions work headless and the visual run is
-- readable at the same time.
local function emit(line)
  local text = PREFIX .. line
  log(text)
  game.print(text)
end

script.on_nth_tick(30, function()
  if reported then return end
  reported = true

  local repaired = script.active_mods[TARGET_MOD] ~= nil
  local tag = repaired and "with-mod" or "without-mod"

  emit(string.format("phase %d, repair mod loaded: %s", repaired and 1 or 2, tostring(repaired)))

  local expansion = game.map_settings.enemy_expansion
  for _, key in ipairs(KEYS) do
    emit(string.format("%s %s=%s", tag, key, tostring(expansion[key])))
  end

  if repaired then
    emit("triggering auto_save - the repaired values go into the save file now")
    game.auto_save(AUTOSAVE_NAME)
    emit("phase 1 done. If a game window is open, quit it now (Esc -> Quit).")
  else
    emit("phase 2: the repair mod is NOT loaded, the values above come from the save.")
    emit("If a game window is open, quit it now (Esc -> Quit).")
  end
end)
