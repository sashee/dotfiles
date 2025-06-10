local vim = vim

vim.opt.shada = ""

vim.g.mapleader = " "
vim.api.nvim_set_keymap('n', '<Leader>t', ':w<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>s', ':q<cr>', { noremap = true, silent = true })

vim.opt.backupcopy = "yes"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.hidden = true
vim.opt.splitbelow = true

vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.autoindent = true
vim.opt.tw = 160

vim.api.nvim_set_keymap('n', 'H', 'gT', { noremap = true})
vim.api.nvim_set_keymap('n', 'L', 'gt', { noremap = true})

-- No line numbers in terminal
local mygroup = vim.api.nvim_create_augroup('TerminalStuff', { clear = true })
vim.api.nvim_create_autocmd({ 'TermOpen' }, {
	pattern = '*',
	group = mygroup,
	callback = function()
		vim.opt_local.number = false
		vim.opt_local.relativenumber = false
	end,
})

require("neotest").setup({
	icons = {
		child_indent = "│",
		child_prefix = "├",
		collapsed = "─",
		expanded = "╮",
		failed = "X",
		final_child_indent = " ",
		final_child_prefix = "╰",
		non_collapsible = "─",
		passed = "✓",
		running = "𝦎",
		running_animated = { "/", "|", "\\", "-", "/", "|", "\\", "-" },
		skipped = "?",
		unknown = "?",
		watching = "👀"
	},
	status = {
		enabled = false,
	},
  adapters = {
		require('neotest-jest')({
			jestCommand = "npm test --",
			cwd = function(path)
				return vim.fn.getcwd()
			end,
		}),
  },
})

vim.keymap.set('n', '<Leader>rt', function() require("neotest").summary.toggle() end)

require "lsp_signature".setup({})

require'lspconfig'.ts_ls.setup{}
require'lspconfig'.eslint.setup{}
require'lspconfig'.lua_ls.setup{}
require'lspconfig'.rust_analyzer.setup{}
require'lspconfig'.yamlls.setup{}
require'lspconfig'.bashls.setup{}
require'lspconfig'.dockerls.setup{}
require'lspconfig'.marksman.setup{}
require'lspconfig'.terraformls.setup{}
require'lspconfig'.nixd.setup{}

--[[
vim.lsp.config['luals'] = {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { { '.luarc.json', '.luarc.jsonc' }, '.git' },
}
vim.lsp.enable('luals')

vim.lsp.config['tsls'] = {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'javascript.jsx', 'typescript', 'typescriptreact', 'typescript.tsx' },
  root_markers = { {'tsconfig.json', 'package.json'}, '.git' },
}
vim.lsp.enable('tsls')
--]]

vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float)
vim.keymap.set('n', '[d', vim.diagnostic.get_prev)
vim.keymap.set('n', ']d', vim.diagnostic.get_next)
vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist)

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    -- Enable completion triggered by <c-x><c-o>
    vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    -- vim.keymap.set('n', '<Leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    -- vim.keymap.set('n', '<Leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    -- vim.keymap.set('n', '<Leader>wl', function()
      -- print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    -- end, opts)
    vim.keymap.set('n', '<Leader>D', vim.lsp.buf.type_definition, opts)
    -- vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set({ 'n', 'v' }, '<Leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    -- vim.keymap.set('n', '<Leader>f', function()
      -- vim.lsp.buf.format { async = true }
    -- end, opts)
  end,
})

require("nvim-treesitter.configs").setup({
  --ensure_installed = {"html", "markdown", "javascript", "typescript", "lua"},
})

vim.api.nvim_create_autocmd({ 'FileType' }, {
	pattern = '*',
	callback = function()
		vim.opt_local.foldmethod = "expr"
		vim.opt_local.foldlevel = 0
		vim.opt_local.foldcolumn = "2"
	end,
})
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
	pattern = '*',
	callback = function()
		vim.opt_local.foldexpr = "nvim_treesitter#foldexpr()"
		vim.opt_local.foldenable = false
	end,
})
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
	pattern = '*/workspace/**/*.md',
	callback = function()
		vim.opt_local.foldexpr = "getline(v:lnum)=~'^```plantuml'?'>1':getline(v:lnum)=~'^```$'?'<1':'='"
	end,
})
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
	pattern = '*/awm/blog/**/*.md',
	callback = function()
		vim.opt_local.foldexpr = "getline(v:lnum)=~'^{%\\s*plantuml\\s*%}$'?'>1':getline(v:lnum)=~'^{%\\s*endplantuml\\s*%}$'?'<1':'='"
	end,
})

local cmp = require 'cmp'
cmp.setup {
  mapping = cmp.mapping.preset.insert({
    ['<C-u>'] = cmp.mapping.scroll_docs(-4), -- Up
    ['<C-d>'] = cmp.mapping.scroll_docs(4), -- Down
    -- C-b (back) C-f (forward) for snippet placeholder navigation.
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      else
        fallback()
      end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      else
        fallback()
      end
    end, { 'i', 's' }),
  }),
  sources = {
    { name = 'nvim_lsp' },
  },
}

require("nvim-surround").setup()

require('gitsigns').setup()

vim.o.termguicolors = true
vim.opt.background = 'light'
--[[
require('solarized-lua').setup({
	colors = function(colors, colorhelper)
		local darken = colorhelper.darken
		--local lighten = colorhelper.lighten
		--local blend = colorhelper.blend

		return {
			base0 = darken(colors.base0, 10)
		}
	end,
})
--]]
vim.cmd.colorscheme 'solarized'


-- hop
require('hop').setup({
	--keys = "arsdheiqwfpgjluy;zxcvbkmtn"
	keys = "arstneio"
})
local hop = require('hop')

vim.keymap.set('', 's', function()
  hop.hint_char2({})
end, {remap=true})

require("nvim-autopairs").setup({
	break_undo = false
})

require('rainbow-delimiters.setup').setup()

require('telescope').setup{
  defaults = {
    mappings = {
      i = {
        ["<C-k>"] = "move_selection_previous",
        ["<C-j>"] = "move_selection_next",
      }
    },
		history = false
  }
}

local builtin = require('telescope.builtin')
vim.keymap.set('', '<C-f>', builtin.live_grep, {})
vim.keymap.set('', '<C-p>', builtin.find_files, {})

require("neo-tree").setup({
	filesystem = {
		window = {
			fuzzy_finder_mappings = {
				["<C-j>"] = "move_cursor_down",
				["<C-k>"] = "move_cursor_up",
			}
		}
	},
	event_handlers = {
		{
			event = "file_opened",
			handler = function(file_path)
				require("neo-tree.command").execute({ action = "close" })
			end
		}
	}
})

vim.keymap.set('', '<F2>', ':Neotree toggle<CR>')
vim.keymap.set('', '<F3>', ':Neotree reveal<CR>')

vim.keymap.set('n', '<Leader>Te', ':Texplore<CR>')

-- for https://github.com/rachartier/tiny-inline-diagnostic.nvim
vim.diagnostic.config({ virtual_text = false })
require('tiny-inline-diagnostic').setup()
