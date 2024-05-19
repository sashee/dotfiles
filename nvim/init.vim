call plug#begin('~/.local/share/nvim/plugged')

Plug 'kylechui/nvim-surround'

Plug 'lewis6991/gitsigns.nvim'

Plug 'maxmx03/solarized.nvim'
"
" needed by: telescope, neotree
Plug 'nvim-lua/plenary.nvim'

Plug 'MunifTanjim/nui.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'nvim-neo-tree/neo-tree.nvim'

Plug 'smoka7/hop.nvim'

Plug 'windwp/nvim-autopairs'

Plug 'hiphish/rainbow-delimiters.nvim'

Plug 'nvim-neotest/nvim-nio'
Plug 'nvim-neotest/neotest'
Plug 'nvim-neotest/neotest-jest'

Plug 'nvim-telescope/telescope.nvim'

Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-cmdline'
Plug 'hrsh7th/nvim-cmp'
Plug 'ray-x/lsp_signature.nvim'

call plug#end()

map <Space> <Leader>

nnoremap <silent> <Leader>t :w <cr>
nnoremap <silent> <Leader>s :q <cr>

:set backupcopy=yes

:set number
:set relativenumber
:set signcolumn=yes

set hidden

set splitbelow

set tabstop=2
set shiftwidth=2
set smartindent
set ignorecase
set smartcase
set autoindent
set tw=160

nnoremap H gT
nnoremap L gt

lua << EOF
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

require("mason").setup()
require("mason-lspconfig").setup({
	ensure_installed = {'tsserver', 'eslint'}
})
require'lspconfig'.tsserver.setup{}
require'lspconfig'.eslint.setup{}

vim.keymap.set('n', '<space>e', vim.diagnostic.open_float)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next)
vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist)

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
    vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<space>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set('n', '<space>D', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set({ 'n', 'v' }, '<space>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<space>f', function()
      vim.lsp.buf.format { async = true }
    end, opts)
  end,
})

require("nvim-treesitter.configs").setup({
  ensure_installed = {"html", "markdown", "javascript", "typescript"},
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

vim.o.background = 'light'
vim.cmd.colorscheme 'solarized'

require('solarized').setup()

-- hop
local hop = require('hop').setup({
	--keys = "arsdheiqwfpgjluy;zxcvbkmtn"
	keys = "arstneio"
})
local hop = require('hop')
local directions = require('hop.hint').HintDirection

vim.keymap.set('', 's', function()
  hop.hint_char2({})
end, {remap=true})

--nmap s <Plug>(easymotion-overwin-f2)
--nmap <Leader>w <Plug>(easymotion-bd-W)
--map <Leader>l <Plug>(easymotion-lineforward)
--map <Leader>j <Plug>(easymotion-j)
--map <Leader>k <Plug>(easymotion-k)
--map <Leader>h <Plug>(easymotion-linebackward)

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
    }
  }
}

local builtin = require('telescope.builtin')
vim.keymap.set('', '<C-f>', builtin.live_grep, {})
vim.keymap.set('', '<C-p>', builtin.find_files, {})

require("neo-tree").setup({
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

EOF
