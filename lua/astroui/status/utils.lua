---AstroNvim Status Utilities
---
---Statusline related uitility functions
---
---This module can be loaded with `local status_utils = require "astroui.status.utils"`
---
---copyright 2023
---license GNU General Public License v3.0
---@class astroui.status.utils
local M = {}

local astro = require "astrocore"
local ui = require "astroui"
local config = assert(ui.config.status)
local get_icon = ui.get_icon
local extend_tbl = astro.extend_tbl

--- Convert a component parameter table to a table that can be used with the component builder
---@param opts? table a table of provider options
---@param provider? function|string a provider in `M.providers`
---@return table|false # the provider table that can be used in `M.component.builder`
function M.build_provider(opts, provider, _)
  return opts
      and {
        provider = provider,
        opts = opts,
        condition = opts.condition,
        on_click = opts.on_click,
        update = opts.update,
        hl = opts.hl,
      }
    or false
end

--- Convert key/value table of options to an array of providers for the component builder
---@param opts table the table of options for the components
---@param providers string[] an ordered list like array of providers that are configured in the options table
---@param setup? function a function that takes provider options table, provider name, provider index and returns the setup provider table, optional, default is `M.build_provider`
---@return table # the fully setup options table with the appropriately ordered providers
function M.setup_providers(opts, providers, setup)
  setup = setup or M.build_provider
  for i, provider in ipairs(providers) do
    opts[i] = setup(opts[provider], provider, i)
  end
  return opts
end

--- A utility function to get the width of the bar
---@param is_winbar? boolean true if you want the width of the winbar, false if you want the statusline width
---@return integer # the width of the specified bar
function M.width(is_winbar)
  return vim.o.laststatus == 3 and not is_winbar and vim.o.columns or vim.api.nvim_win_get_width(0)
end

--- Add left and/or right padding to a string
---@param str string the string to add padding to
---@param padding table a table of the format `{ left = 0, right = 0}` that defines the number of spaces to include to the left and the right of the string
---@return string # the padded string
function M.pad_string(str, padding)
  padding = padding or {}
  return str and str ~= "" and (" "):rep(padding.left or 0) .. str .. (" "):rep(padding.right or 0) or ""
end

local function escape(str) return str:gsub("%%", "%%%%") end

--- A utility function to stylize a string with an icon from lspkind, separators, and left/right padding
---@param str? string the string to stylize
---@param opts? table options of `{ padding = { left = 0, right = 0 }, separator = { left = "|", right = "|" }, escape = true, show_empty = false, icon = { kind = "NONE", padding = { left = 0, right = 0 } } }`
---@return string # the stylized string
-- @usage local string = require("astroui.status").utils.stylize("Hello", { padding = { left = 1, right = 1 }, icon = { kind = "String" } })
function M.stylize(str, opts)
  opts = extend_tbl({
    padding = { left = 0, right = 0 },
    separator = { left = "", right = "" },
    show_empty = false,
    escape = true,
    icon = { kind = "NONE", padding = { left = 0, right = 0 } },
  }, opts)
  local icon = M.pad_string(get_icon(opts.icon.kind), opts.icon.padding)
  return str
      and (str ~= "" or opts.show_empty)
      and opts.separator.left .. M.pad_string(icon .. (opts.escape and escape(str) or str), opts.padding) .. opts.separator.right
    or ""
end

--- Surround component with separator and color adjustment
---@param separator string|string[] the separator index to use in the `separators` table
---@param color function|string|table the color to use as the separator foreground/component background
---@param component table the component to surround
---@param condition boolean|function the condition for displaying the surrounded component
---@param update AstroUIUpdateEvents? control updating of separators, either a list of events or true to update freely
---@return table # the new surrounded component
function M.surround(separator, color, component, condition, update)
  local function surround_color(self)
    local colors = type(color) == "function" and color(self) or color
    return type(colors) == "string" and { main = colors } or colors
  end

  separator = type(separator) == "string" and config.separators[separator] or separator
  local surrounded = { condition = condition }
  local base_separator = {
    update = (update or type(color) ~= "function") and function() return false end,
    init = update and require("astroui.status.init").update_events(update),
  }
  if separator[1] ~= "" then
    table.insert(
      surrounded,
      extend_tbl {
        provider = separator[1], --bind alt-j:down,alt-k:up
        hl = function(self)
          local s_color = surround_color(self)
          if s_color then return { fg = s_color.main, bg = s_color.left } end
        end,
      }
    )
  end
  local component_hl = component.hl
  component.hl = function(self)
    local hl = {}
    if component_hl then hl = type(component_hl) == "table" and vim.deepcopy(component_hl) or component_hl(self) end
    local s_color = surround_color(self)
    if s_color then hl.bg = s_color.main end
    return hl
  end
  table.insert(surrounded, component)
  if separator[2] ~= "" then
    table.insert(
      surrounded,
      extend_tbl(base_separator, {
        provider = separator[2],
        hl = function(self)
          local s_color = surround_color(self)
          if s_color then return { fg = s_color.main, bg = s_color.right } end
        end,
      })
    )
  end
  return surrounded
end

--- Encode a position to a single value that can be decoded later
---@param line integer line number of position
---@param col integer column number of position
---@param winnr integer a window number
---@return integer the encoded position
function M.encode_pos(line, col, winnr) return bit.bor(bit.lshift(line, 16), bit.lshift(col, 6), winnr) end

--- Decode a previously encoded position to it's sub parts
---@param c integer the encoded position
---@return integer line, integer column, integer window
function M.decode_pos(c) return bit.rshift(c, 16), bit.band(bit.rshift(c, 6), 1023), bit.band(c, 63) end

--- Get a list of registered null-ls providers for a given filetype
---@param filetype string the filetype to search null-ls for
---@return table # a table of null-ls sources
function M.null_ls_providers(filetype)
  local registered = {}
  -- try to load null-ls
  local sources_avail, sources = pcall(require, "null-ls.sources")
  if sources_avail then
    -- get the available sources of a given filetype
    for _, source in ipairs(sources.get_available(filetype)) do
      -- get each source name
      for method in pairs(source.methods) do
        registered[method] = registered[method] or {}
        table.insert(registered[method], source.name)
      end
    end
  end
  -- return the found null-ls sources
  return registered
end

--- Get the null-ls sources for a given null-ls method
---@param filetype string the filetype to search null-ls for
---@param method string the null-ls method (check null-ls documentation for available methods)
---@return string[] # the available sources for the given filetype and method
function M.null_ls_sources(filetype, method)
  local methods_avail, methods = pcall(require, "null-ls.methods")
  return methods_avail and M.null_ls_providers(filetype)[methods.internal[method]] or {}
end

--- A helper function for decoding statuscolumn click events with mouse click pressed, modifier keys, as well as which signcolumn sign was clicked if any
---@param self any the self parameter from Heirline component on_click.callback function call
---@param minwid any the minwid parameter from Heirline component on_click.callback function call
---@param clicks any the clicks parameter from Heirline component on_click.callback function call
---@param button any the button parameter from Heirline component on_click.callback function call
---@param mods any the button parameter from Heirline component on_click.callback function call
---@return table # the argument table with the decoded mouse information and signcolumn signs information
-- @usage local heirline_component = { on_click = { callback = function(...) local args = require("astroui.status").utils.statuscolumn_clickargs(...) end } }
function M.statuscolumn_clickargs(self, minwid, clicks, button, mods)
  local args = {
    minwid = minwid,
    clicks = clicks,
    button = button,
    mods = mods,
    mousepos = vim.fn.getmousepos(),
  }
  args.char = vim.fn.screenstring(args.mousepos.screenrow, args.mousepos.screencol)
  if args.char == " " then args.char = vim.fn.screenstring(args.mousepos.screenrow, args.mousepos.screencol - 1) end

  if not self.signs then self.signs = {} end
  args.sign = self.signs[args.char]
  if not args.sign then -- update signs if not found on first click
    ---TODO: remove when dropping support for Neovim v0.9
    if vim.fn.has "nvim-0.10" == 0 then
      for _, sign_def in ipairs(assert(vim.fn.sign_getdefined())) do
        if sign_def.text then self.signs[sign_def.text:gsub("%s", "")] = sign_def end
      end
    end

    if not self.bufnr then self.bufnr = vim.api.nvim_get_current_buf() end
    local row = args.mousepos.line - 1
    for _, extmark in
      ipairs(vim.api.nvim_buf_get_extmarks(self.bufnr, -1, { row, 0 }, { row, -1 }, { details = true, type = "sign" }))
    do
      local sign = extmark[4]
      if not (self.namespaces and self.namespaces[sign.ns_id]) then
        self.namespaces = {}
        for ns, ns_id in pairs(vim.api.nvim_get_namespaces()) do
          self.namespaces[ns_id] = ns
        end
      end
      if sign.sign_text then
        self.signs[sign.sign_text:gsub("%s", "")] = {
          name = sign.sign_name,
          text = sign.sign_text,
          texthl = sign.sign_hl_group or "NoTexthl",
          namespace = sign.ns_id and self.namespaces[sign.ns_id],
        }
      end
    end
    args.sign = self.signs[args.char]
  end
  vim.api.nvim_set_current_win(args.mousepos.winid)
  vim.api.nvim_win_set_cursor(0, { args.mousepos.line, 0 })
  return args
end

return M
