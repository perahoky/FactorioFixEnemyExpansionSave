--------------------------------------------------------------------------------
-- Fix Enemy Expansion Save
--
-- game.map_settings is ENGINE state stored inside the save file. A mod that writes
-- into it changes the map itself, so those values survive the mod's uninstall --
-- which is exactly how a removed mod can leave a save permanently boosted.
--
-- This mod exploits the same mechanism to repair the damage: it writes the wanted
-- values through the normal runtime API and then gets removed again. It never runs
-- a script command, so it does not set the permanent flag that /c puts on a save.
--------------------------------------------------------------------------------

local PREFIX = "[fix-enemy-expansion-save] "

-- Factorio 2.1 base values, taken from data/base/prototypes/map-settings.lua (2.1.17).
-- Shown for comparison only; nothing is written from this table.
local VANILLA = {
  enabled = true,
  min_expansion_cooldown = 36000,
  max_expansion_cooldown = 216000,
  settler_group_min_size = 5,
  settler_group_max_size = 10,
  min_expansion_distance = 3,
  max_expansion_distance = 5,
  build_base_unit_dispatch_cooldown = 1800,
  friendly_base_influence_radius = 6,
  enemy_building_influence_radius = 3,
  building_coefficient = 0.5,
  other_base_coefficient = 3.0,
  neighbouring_chunk_coefficient = 0.5,
  neighbouring_base_chunk_coefficient = 0.5,
  max_colliding_tiles_coefficient = 0.8,
}

-- The fields this mod writes. Maxima are listed before their minima so a pair is
-- never left in a transient min > max state while values are written one by one.
local FIELDS = {
  { key = "max_expansion_cooldown", setting = "feas-max-cooldown" },
  { key = "min_expansion_cooldown", setting = "feas-min-cooldown" },
  { key = "settler_group_max_size", setting = "feas-settler-max" },
  { key = "settler_group_min_size", setting = "feas-settler-min" },
  { key = "max_expansion_distance", setting = "feas-max-distance" },
  { key = "min_expansion_distance", setting = "feas-min-distance" },
}

local PAIRS = {
  { min = "min_expansion_cooldown", max = "max_expansion_cooldown", label = "expansion cooldown" },
  { min = "settler_group_min_size", max = "settler_group_max_size", label = "settler group size" },
  { min = "min_expansion_distance", max = "max_expansion_distance", label = "expansion distance" },
}

-- Never written, only shown by /expansion-status so other leftovers stay visible.
local REPORT_ONLY = {
  "build_base_unit_dispatch_cooldown",
  "friendly_base_influence_radius",
  "enemy_building_influence_radius",
  "building_coefficient",
  "other_base_coefficient",
  "neighbouring_chunk_coefficient",
  "neighbouring_base_chunk_coefficient",
  "max_colliding_tiles_coefficient",
}

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function get_setting(name)
  local entry = settings.global[name]
  if entry == nil then return nil end
  return entry.value
end

-- Chat and log carry the same plain text, so the log stays greppable.
local function emit(line, player)
  local text = PREFIX .. line
  log(text)
  if player and player.valid then
    player.print(text)
  else
    game.print(text)
  end
end

local function expansion_settings()
  return game.map_settings and game.map_settings.enemy_expansion or nil
end

local function build_targets()
  local targets, problems = {}, {}

  for _, field in ipairs(FIELDS) do
    local value = get_setting(field.setting)
    if type(value) ~= "number" then
      problems[#problems + 1] = string.format("setting %s is missing or not a number", field.setting)
    else
      targets[field.key] = math.floor(value)
    end
  end

  for _, pair in ipairs(PAIRS) do
    local low, high = targets[pair.min], targets[pair.max]
    if low and high and low > high then
      problems[#problems + 1] = string.format(
        "%s: minimum (%s) is larger than maximum (%s)", pair.label, tostring(low), tostring(high))
    end
  end

  return targets, problems
end

--------------------------------------------------------------------------------
-- applying
--------------------------------------------------------------------------------

local function apply(reason)
  local expansion = expansion_settings()
  if not expansion then
    emit("enemy expansion map settings are not available, nothing done.")
    return
  end

  local targets, problems = build_targets()
  if #problems > 0 then
    emit("nothing was changed - these settings contradict each other:")
    for _, problem in ipairs(problems) do emit("  " .. problem) end
    return
  end

  local dry_run = get_setting("feas-dry-run") == true
  local mode = get_setting("feas-enabled-mode") or "leave"
  local changes = {}

  for _, field in ipairs(FIELDS) do
    local old, new = expansion[field.key], targets[field.key]
    if new ~= nil and old ~= new then
      changes[#changes + 1] = string.format("%s: %s -> %s", field.key, tostring(old), tostring(new))
      if not dry_run then expansion[field.key] = new end
    end
  end

  if mode ~= "leave" then
    local new = (mode == "on")
    if expansion.enabled ~= new then
      changes[#changes + 1] = string.format("enabled: %s -> %s", tostring(expansion.enabled), tostring(new))
      if not dry_run then expansion.enabled = new end
    end
  end

  if #changes == 0 then
    emit(string.format("checked (%s): enemy expansion already matches the configured values.", reason))
    return
  end

  emit(string.format("%s (%s):", dry_run and "would change" or "applied", reason))
  for _, change in ipairs(changes) do emit("  " .. change) end

  if dry_run then
    emit("report only is switched on - the map was not modified.")
    return
  end

  -- The engine, not this mod, decides what actually stuck, so read it back.
  local after = expansion_settings()
  local mismatches = {}
  for _, field in ipairs(FIELDS) do
    local want, got = targets[field.key], after[field.key]
    if want ~= nil and got ~= want then
      mismatches[#mismatches + 1] = string.format(
        "%s: engine kept %s (requested %s)", field.key, tostring(got), tostring(want))
    end
  end
  if mode ~= "leave" and after.enabled ~= (mode == "on") then
    mismatches[#mismatches + 1] = string.format(
      "enabled: engine kept %s (requested %s)", tostring(after.enabled), tostring(mode == "on"))
  end

  if #mismatches > 0 then
    emit("the engine did not accept every value:")
    for _, mismatch in ipairs(mismatches) do emit("  " .. mismatch) end
  else
    emit("verified: every value was accepted by the engine.")
  end

  emit("save the game now - these values live in the save and stay after this mod is removed.")
end

--------------------------------------------------------------------------------
-- leftover unit cleanup (opt-in, one shot)
--------------------------------------------------------------------------------

local function cleanup_units(scope, reason)
  local dry_run = get_setting("feas-dry-run") == true

  if scope == "all" then
    local total = 0
    for _, surface in pairs(game.surfaces) do
      total = total + surface.count_entities_filtered({ force = "enemy", type = "unit" })
    end
    if dry_run then
      emit(string.format("would kill %d enemy units on all surfaces (%s).", total, reason))
      return false
    end
    game.forces.enemy.kill_all_units()
    emit(string.format("killed %d enemy units on all surfaces and flushed the pathfinder (%s).", total, reason))
    return true
  end

  local surface = game.surfaces["nauvis"]
  if not surface then
    emit("surface nauvis does not exist, no units were touched.")
    return false
  end

  if dry_run then
    local total = surface.count_entities_filtered({ force = "enemy", type = "unit" })
    emit(string.format("would kill %d enemy units on nauvis (%s).", total, reason))
    return false
  end

  local killed = 0
  for _, entity in pairs(surface.find_entities_filtered({ force = "enemy", type = "unit" })) do
    if entity.valid then
      entity.destroy()
      killed = killed + 1
    end
  end
  emit(string.format("killed %d enemy units on nauvis, nests and worms untouched (%s).", killed, reason))
  return true
end

local function maybe_cleanup_units(reason)
  local scope = get_setting("feas-kill-scope") or "none"

  if scope == "none" then
    storage.kill_scope_done = nil
    return
  end
  if storage.kill_scope_done == scope then return end

  if cleanup_units(scope, reason) then
    storage.kill_scope_done = scope
  end
end

--------------------------------------------------------------------------------
-- commands
--------------------------------------------------------------------------------

local function status(player)
  local expansion = expansion_settings()
  if not expansion then
    emit("enemy expansion map settings are not available.", player)
    return
  end

  local targets = build_targets()
  local mode = get_setting("feas-enabled-mode") or "leave"

  emit("enemy expansion - current | target | base 2.1", player)
  emit(string.format("  enabled: %s | %s | %s",
    tostring(expansion.enabled),
    mode == "leave" and "left as-is" or tostring(mode == "on"),
    tostring(VANILLA.enabled)), player)

  for _, field in ipairs(FIELDS) do
    emit(string.format("  %s: %s | %s | %s",
      field.key,
      tostring(expansion[field.key]),
      tostring(targets[field.key]),
      tostring(VANILLA[field.key])), player)
  end

  emit("not managed by this mod - current | base 2.1", player)
  for _, key in ipairs(REPORT_ONLY) do
    emit(string.format("  %s: %s | %s", key, tostring(expansion[key]), tostring(VANILLA[key])), player)
  end
end

local function caller_may_write(command)
  if not command.player_index then return true end
  local player = game.get_player(command.player_index)
  if not player then return false end
  if player.admin then return true end
  player.print(PREFIX .. "only admins can run this command.")
  return false
end

local function command_is_taken(name)
  return (commands.commands and commands.commands[name] ~= nil)
      or (commands.game_commands and commands.game_commands[name] ~= nil)
end

-- Adding a command whose name is already in use is a hard error, so fall back to
-- a prefixed name if another mod got there first.
local function register_command(names, help, handler)
  for _, name in ipairs(names) do
    if not command_is_taken(name) then
      commands.add_command(name, help, handler)
      return
    end
  end
  log(PREFIX .. "all candidate command names are taken: " .. table.concat(names, ", "))
end

register_command(
  { "expansion-status", "feas-status" },
  "Show the live enemy expansion map settings next to the configured target and the Factorio 2.1 base values.",
  function(command)
    status(command.player_index and game.get_player(command.player_index) or nil)
  end)

register_command(
  { "expansion-fix", "feas-fix" },
  "Apply the configured enemy expansion map settings to this save (admin only).",
  function(command)
    if not caller_may_write(command) then return end
    apply("/expansion-fix")
  end)

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

script.on_init(function()
  apply("mod added to this save")
  maybe_cleanup_units("mod added to this save")
end)

script.on_configuration_changed(function()
  apply("configuration changed")
  maybe_cleanup_units("configuration changed")
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  local name = event.setting
  if type(name) ~= "string" or name:sub(1, 5) ~= "feas-" then return end

  if name == "feas-kill-scope" then
    maybe_cleanup_units("kill scope changed")
  else
    apply("setting changed: " .. name)
  end
end)
