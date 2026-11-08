-- Managed by ~/dev-setup (steps/45-theme.sh): re-running the step overwrites this file. To add or
-- change a theme, edit files/nvim/noctalia-theme.lua in the dev-setup repo, then run
-- ./install.sh --only theme.
--
-- Neovim follows Noctalia's palette the way it follows Omarchy's themes: each palette maps to a real
-- colorscheme plugin, set to the matching variant. dev-theme-sync (run by Noctalia's hooks) writes
-- the palette name and dark/light mode to ~/.local/state/dev-setup/palette. This applies the match
-- at startup, and again in every running Neovim whenever that file changes. A palette without an
-- entry leaves your own colorscheme in place (LazyVim's default, or whatever your config sets).

-- Colorscheme plugins: lazy.nvim installs them all, and loads one only when a theme below uses it.
local plugins = {
  catppuccin = { "catppuccin/nvim", name = "catppuccin" },
  everforest = { "sainnhe/everforest" },
  gruvbox = { "ellisonleao/gruvbox.nvim" },
  gruvbox_material = { "sainnhe/gruvbox-material" },
  rose_pine = { "rose-pine/neovim", name = "rose-pine" },
}

-- Noctalia palettes and the colorscheme each one gets. The first entry that matches wins.
--   palettes     Noctalia palette names, as Settings lists them (or https://api.noctalia.dev/palettes).
--                "Name *" matches every palette whose name starts with "Name ".
--   plugin       a key of `plugins` above
--   colorscheme  the name given to :colorscheme
--   g            vim.g variables set first (Vimscript colorschemes, like sainnhe's)
--   setup        { module = opts }: require(module).setup(opts) first (Lua colorschemes)
--   dark, light  settings for that mode only, merged over the ones above
-- 'background' always follows Noctalia's mode. Each variant was picked by comparing the palette's
-- background (and for Gruvbox Material, foreground) colors with the plugin's own.
local themes = {
  -- sainnhe/everforest: everforest_background = "hard" | "medium" | "soft"
  {
    palettes = { "Everforest" }, -- darker than every variant: hard is nearest. Light: medium (#efebd4)
    plugin = "everforest",
    colorscheme = "everforest",
    dark = { g = { everforest_background = "hard" } },
    light = { g = { everforest_background = "medium" } },
  },
  {
    palettes = { "Everforest Alt" }, -- medium (#2d353b); light: hard (#fffbef)
    plugin = "everforest",
    colorscheme = "everforest",
    dark = { g = { everforest_background = "medium" } },
    light = { g = { everforest_background = "hard" } },
  },
  {
    palettes = { "Everforest Material" }, -- near-black (#161616): hard is nearest; light: hard (#fffbef)
    plugin = "everforest",
    colorscheme = "everforest",
    g = { everforest_background = "hard" },
  },

  -- ellisonleao/gruvbox.nvim: contrast = "hard" | "soft" | "" (medium)
  {
    palettes = { "Gruvbox", "GruvboxAlt" }, -- medium (#282828; light #fbf1c7)
    plugin = "gruvbox",
    colorscheme = "gruvbox",
    setup = { gruvbox = { contrast = "" } },
  },

  -- sainnhe/gruvbox-material, a separate plugin: gruvbox_material_background = "hard" | "medium" |
  -- "soft", gruvbox_material_foreground = "material" | "mix" | "original"
  {
    palettes = { "Gruvbox Material Hard" }, -- #1d2021 (light #f9f5d7), material foreground
    plugin = "gruvbox_material",
    colorscheme = "gruvbox-material",
    g = { gruvbox_material_background = "hard", gruvbox_material_foreground = "material" },
  },
  {
    palettes = { "Gruvbox Material Medium" }, -- #282828 (light #fbf1c7), material foreground
    plugin = "gruvbox_material",
    colorscheme = "gruvbox-material",
    g = { gruvbox_material_background = "medium", gruvbox_material_foreground = "material" },
  },
  {
    palettes = { "Gruvbox Material" }, -- soft: #32302f (light #f2e5bc), material foreground
    plugin = "gruvbox_material",
    colorscheme = "gruvbox-material",
    g = { gruvbox_material_background = "soft", gruvbox_material_foreground = "material" },
  },

  -- catppuccin/nvim: the flavour is in the colorscheme name; every light variant is Latte. The accent
  -- in community palette names (Blue, Mauve, ...) is Noctalia's own; the colorscheme has no accent.
  {
    palettes = { "Catppuccin", "Catppuccin Mocha *" },
    plugin = "catppuccin",
    dark = { colorscheme = "catppuccin-mocha" },
    light = { colorscheme = "catppuccin-latte" },
  },
  {
    palettes = { "Catppuccin Macchiato *" },
    plugin = "catppuccin",
    dark = { colorscheme = "catppuccin-macchiato" },
    light = { colorscheme = "catppuccin-latte" },
  },
  {
    palettes = { "Catppuccin Frappe *" },
    plugin = "catppuccin",
    dark = { colorscheme = "catppuccin-frappe" },
    light = { colorscheme = "catppuccin-latte" },
  },

  -- rose-pine/neovim: the variant is in the colorscheme name; every light variant is Dawn.
  {
    palettes = { "Rosé Pine", "Rose Pine Alt" }, -- main (#191724)
    plugin = "rose_pine",
    dark = { colorscheme = "rose-pine-main" },
    light = { colorscheme = "rose-pine-dawn" },
  },
  {
    palettes = { "Rose Pine Moon", "Rose Pine Moon Alt" }, -- moon (#232136)
    plugin = "rose_pine",
    dark = { colorscheme = "rose-pine-moon" },
    light = { colorscheme = "rose-pine-dawn" },
  },
}

-- ---------------------------------------------------------------------------------------------

local uv = vim.uv or vim.loop
local state_file = (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")) .. "/dev-setup/palette"

-- The palette name and "dark" or "light", or nil before Noctalia has run.
local function read_state()
  local f = io.open(state_file, "r")
  if not f then
    return nil
  end
  local name, mode = f:read("*l"), f:read("*l")
  f:close()
  if not name or name == "" then
    return nil
  end
  return name, mode == "light" and "light" or "dark"
end

local function matches(pattern, name)
  if pattern:sub(-1) == "*" then
    return name:sub(1, #pattern - 1) == pattern:sub(1, -2)
  end
  return name == pattern
end

local function find_theme(name)
  for _, theme in ipairs(themes) do
    for _, pattern in ipairs(theme.palettes) do
      if matches(pattern, name) then
        return theme
      end
    end
  end
end

-- A theme's settings for MODE: the shared ones, with that mode's merged over them.
local function resolve(theme, mode)
  local shared = {}
  for key, value in pairs(theme) do
    if key ~= "palettes" and key ~= "dark" and key ~= "light" then
      shared[key] = value
    end
  end
  return vim.tbl_deep_extend("force", shared, theme[mode] or {})
end

local applied -- the palette and mode last applied, so repeated file events do nothing

local function apply()
  local name, mode = read_state()
  if not name or applied == name .. "\n" .. mode then
    return
  end
  applied = name .. "\n" .. mode
  local theme = find_theme(name)
  if not theme then
    return
  end
  local s = resolve(theme, mode)
  vim.o.background = mode
  for key, value in pairs(s.g or {}) do
    vim.g[key] = value
  end
  for module, opts in pairs(s.setup or {}) do
    require(module).setup(opts) -- lazy.nvim loads the plugin on require
  end
  local ok, err = pcall(vim.cmd.colorscheme, s.colorscheme)
  if not ok then
    vim.notify(("noctalia-theme: %s (palette %q): %s"):format(s.colorscheme, name, err), vim.log.levels.WARN)
  end
end

-- dev-theme-sync replaces the file by renaming a temporary one over it, so watch the folder.
local function watch()
  local dir = vim.fs.dirname(state_file)
  vim.fn.mkdir(dir, "p")
  local handle = uv.new_fs_event()
  if not handle then
    return
  end
  handle:start(dir, {}, vim.schedule_wrap(function(err, filename)
    if not err and filename == "palette" then
      apply()
    end
  end))
end

local specs = {}
for _, plugin in pairs(plugins) do
  specs[#specs + 1] = vim.tbl_extend("force", plugin, { lazy = true, priority = 1000 })
end
specs[#specs + 1] = {
  name = "noctalia-theme",
  dir = vim.fn.stdpath("config"),
  lazy = false,
  -- Loads after LazyVim (priority 10000) has applied its own colorscheme, so the palette's wins.
  priority = 1000,
  config = function()
    apply()
    watch()
  end,
}
return specs
