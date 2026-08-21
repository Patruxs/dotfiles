-- Minimal LazyVim options.
-- Keep LazyVim's default keymaps and plugin behavior. Only reduce UI noise.

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.autoformat = true
vim.g.snacks_animate = false
vim.g.lazyvim_picker = "auto"
vim.g.lazyvim_cmp = "auto"

local opt = vim.opt

-- Clean but still useful UI.
opt.number = true
opt.relativenumber = false
opt.cursorline = true
opt.signcolumn = "yes"
opt.wrap = false
opt.scrolloff = 6
opt.sidescrolloff = 8
opt.cmdheight = 1
opt.laststatus = 3
opt.showtabline = 1
opt.showmode = false
opt.ruler = false
opt.termguicolors = true

-- Comfortable editing defaults.
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.timeoutlen = 300

-- Keep system clipboard locally, but avoid breaking SSH/OSC52 behavior.
opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
