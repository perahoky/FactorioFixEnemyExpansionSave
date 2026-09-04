-- Every setting is runtime-global: it lives in the map, can be changed in-game by an
-- admin, and takes effect immediately (control.lua reacts to on_runtime_mod_setting_changed).
--
-- Defaults are the values chosen for this save, NOT the Factorio 2.1 base values.
-- Base 2.1 (data/base/prototypes/map-settings.lua) for reference:
--   min_expansion_cooldown 36000, max_expansion_cooldown 216000,
--   settler_group_min_size 5, settler_group_max_size 10,
--   min_expansion_distance 3, max_expansion_distance 5
data:extend({
  {
    type = "bool-setting",
    name = "feas-dry-run",
    setting_type = "runtime-global",
    default_value = false,
    order = "a-a",
  },
  {
    type = "string-setting",
    name = "feas-enabled-mode",
    setting_type = "runtime-global",
    default_value = "leave",
    allowed_values = { "leave", "on", "off" },
    order = "a-b",
  },

  {
    type = "int-setting",
    name = "feas-min-cooldown",
    setting_type = "runtime-global",
    default_value = 14400,
    minimum_value = 0,
    maximum_value = 4294967295,
    order = "b-a",
  },
  {
    type = "int-setting",
    name = "feas-max-cooldown",
    setting_type = "runtime-global",
    default_value = 216000,
    minimum_value = 0,
    maximum_value = 4294967295,
    order = "b-b",
  },

  {
    type = "int-setting",
    name = "feas-settler-min",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 10000,
    order = "c-a",
  },
  {
    type = "int-setting",
    name = "feas-settler-max",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 0,
    maximum_value = 10000,
    order = "c-b",
  },

  {
    type = "int-setting",
    name = "feas-min-distance",
    setting_type = "runtime-global",
    default_value = 3,
    minimum_value = 0,
    maximum_value = 1000,
    order = "d-a",
  },
  {
    type = "int-setting",
    name = "feas-max-distance",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 1000,
    order = "d-b",
  },

  {
    type = "string-setting",
    name = "feas-kill-scope",
    setting_type = "runtime-global",
    default_value = "none",
    allowed_values = { "none", "nauvis", "all" },
    order = "e-a",
  },
})
