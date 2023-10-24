call plug#begin('~/.local/share/nvim/plugged')

Plug 'tpope/vim-surround'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'HerringtonDarkholme/yats.vim'
Plug 'roxma/nvim-yarp'
Plug 'airblade/vim-gitgutter'
Plug 'lifepillar/vim-solarized8'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tpope/vim-fugitive'
Plug 'easymotion/vim-easymotion'
Plug 'jiangmiao/auto-pairs'
Plug 'luochen1990/rainbow'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-repeat'
Plug 'terryma/vim-expand-region'
Plug 'mattn/emmet-vim'
Plug 'editorconfig/editorconfig-vim'
Plug 'vim-scripts/vim-auto-save'
Plug 'rhysd/vim-grammarous'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'David-Kunz/jester'
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
Plug 'ray-x/lsp_signature.nvim'

call plug#end()

let g:gitgutter_map_keys = 0

map <Space> <Leader>

nnoremap <silent> <Leader>t :w <cr>
nnoremap <silent> <Leader>s :q <cr>

let g:rainbow_active = 1
let g:AutoPairsMultilineClose = 0
autocmd FileType markdown let b:AutoPairs = AutoPairsDefine({'```' : '```'})

:set backupcopy=yes

:set number
:set relativenumber
:set signcolumn=yes

nnoremap <C-p> :FZF<CR>

set hidden

set splitbelow

set tabstop=2
set shiftwidth=2
set smartindent
set ignorecase
set smartcase
set autoindent
set tw=160

set background=light
set termguicolors

if $RECORDING_MODE == "true"
	set laststatus=0 cmdheight=1 background=light signcolumn=no nonumber norelativenumber shell=bash\ --norc
endif

silent! colorscheme solarized8_high

" Enable true color 启用终端24位色
if exists('+termguicolors')
  let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
  let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  set termguicolors
endif

" autocmd BufNewFile,BufRead *.json.symlink set syntax=json

" NERDTress File highlighting
function! NERDTreeHighlightFile(extension, fg, bg, guifg, guibg)
 exec 'autocmd filetype nerdtree highlight ' . a:extension .' ctermbg='. a:bg .' ctermfg='. a:fg .' guibg='. a:guibg .' guifg='. a:guifg
 exec 'autocmd filetype nerdtree syn match ' . a:extension .' #^\s\+.*'. a:extension .'$#'
endfunction

if &background == "dark"
	call NERDTreeHighlightFile('jade', 'green', 'none', 'green', '#151515')
	call NERDTreeHighlightFile('ini', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('md', 'blue', 'none', '#3366FF', '#151515')
	call NERDTreeHighlightFile('yml', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('config', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('conf', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('json', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('html', 'yellow', 'none', 'yellow', '#151515')
	call NERDTreeHighlightFile('styl', 'cyan', 'none', 'cyan', '#151515')
	call NERDTreeHighlightFile('css', 'cyan', 'none', 'cyan', '#151515')
	call NERDTreeHighlightFile('coffee', 'Red', 'none', 'red', '#151515')
	call NERDTreeHighlightFile('js', 'Red', 'none', '#ffa500', '#151515')
	call NERDTreeHighlightFile('jsx', 'Red', 'none', '#ffa500', '#151515')
	call NERDTreeHighlightFile('ts', 'Magenta', 'none', '#ff00ff', '#151515')
	call NERDTreeHighlightFile('tsx', 'Magenta', 'none', '#ff00ff', '#151515')
endif
nmap <silent> <F2> :NERDTreeToggle<CR>
nmap <silent> <F3> :NERDTreeFind<CR>

let NERDTreeQuitOnOpen = 1

" call neomake#configure#automake('wn', 2000)

nnoremap H gT
nnoremap L gt

let g:EasyMotion_do_mapping = 0 " Disable default mappings
" Turn on case insensitive feature
let g:EasyMotion_smartcase = 1

nmap s <Plug>(easymotion-overwin-f2)
nmap <Leader>w <Plug>(easymotion-bd-W)
map <Leader>l <Plug>(easymotion-lineforward)
map <Leader>j <Plug>(easymotion-j)
map <Leader>k <Plug>(easymotion-k)
map <Leader>h <Plug>(easymotion-linebackward)

autocmd User fugitive 
  \ if fugitive#buffer().type() =~# '^\%(tree\|blob\)$' |
  \   nnoremap <buffer> .. :edit %:h<CR> |
  \ endif
autocmd BufReadPost fugitive://* set bufhidden=delete

" No line numbers in terminal
lua << EOF
	local mygroup = vim.api.nvim_create_augroup('TerminalStuff', { clear = true })
	vim.api.nvim_create_autocmd({ 'TermOpen' }, {
		pattern = '*',
		group = mygroup,
		callback = function()
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
		end,
	})
EOF

" source vimrc
nnoremap <leader>sv <cmd>source $MYVIMRC<CR>

lua << EOF
require "lsp_signature".setup({})

require("mason").setup()
require("mason-lspconfig").setup()
require'lspconfig'.tsserver.setup{}

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
EOF

lua << EOF
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
EOF

lua << EOF
	require("jester").setup({
		path_to_jest_run = 'NODE_OPTIONS=--experimental-vm-modules ./node_modules/.bin/jest'
	})
	vim.keymap.set('n', '<Leader>rt', function() require"jester".run() end)
EOF

