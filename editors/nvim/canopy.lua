-- Canopy LSP configuration for Neovim
--
-- This file provides LSP integration for the Canopy programming language
-- using nvim-lspconfig.
--
-- == Installation
--
-- 1. Install the Canopy language server:
--
--    npm install -g @canopy-lang/canopy-language-server
--
-- 2. Copy this file to your Neovim configuration directory, or add
--    the setup call to your init.lua:
--
--    require('canopy')  -- if placed in lua/ directory
--
-- == Requirements
--
-- * Neovim >= 0.8.0
-- * nvim-lspconfig (https://github.com/neovim/nvim-lspconfig)
-- * Node.js >= 16.0 (for the language server)
--
-- == Features
--
-- * Diagnostics (type errors, parse errors, lint warnings)
-- * Go to definition
-- * Find references
-- * Hover information
-- * Code completion
-- * Code formatting
-- * Code actions (quick fixes)

local M = {}

-- Default configuration for the Canopy language server.
M.default_config = {
  cmd = { 'canopy-lsp', '--stdio' },
  filetypes = { 'canopy', 'elm' },
  root_dir = function(fname)
    local lspconfig = require('lspconfig')
    return lspconfig.util.root_pattern('canopy.json', 'elm.json')(fname)
      or lspconfig.util.find_git_ancestor(fname)
  end,
  settings = {
    canopy = {
      -- Path to the canopy compiler binary.
      -- Leave empty to use the canopy binary on PATH.
      compilerPath = '',
      -- Enable auto-formatting on save.
      formatOnSave = false,
      -- Enable lint diagnostics.
      enableLint = true,
      -- Enable type information on hover.
      enableHover = true,
    },
  },
  init_options = {
    -- The runtime for the language server (node or browser).
    runtime = 'node',
  },
}

-- Register Canopy as a language server with nvim-lspconfig.
--
-- Call this function from your init.lua to set up the Canopy LSP:
--
--   require('canopy').setup()
--
-- Or with custom options:
--
--   require('canopy').setup({
--     settings = {
--       canopy = {
--         formatOnSave = true,
--       },
--     },
--   })
function M.setup(opts)
  opts = opts or {}

  local lspconfig = require('lspconfig')
  local configs = require('lspconfig.configs')

  -- Register the canopy LSP if not already registered.
  if not configs.canopy then
    configs.canopy = {
      default_config = M.default_config,
    }
  end

  -- Set up the LSP with user overrides.
  lspconfig.canopy.setup(vim.tbl_deep_extend('force', M.default_config, opts))
end

-- Register Canopy file type detection.
-- Associates .can and .canopy file extensions with the 'canopy' filetype.
vim.filetype.add({
  extension = {
    can = 'canopy',
    canopy = 'canopy',
  },
})

-- Set up basic syntax matching for Canopy files.
-- This provides keyword highlighting without a full tree-sitter grammar.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'canopy',
  callback = function()
    vim.bo.commentstring = '-- %s'
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
    vim.bo.expandtab = true
  end,
})

return M
