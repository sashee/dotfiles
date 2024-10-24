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

Plug 'neoclide/coc.nvim', {'branch': 'release'}

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

" Coc
set updatetime=300
set cmdheight=2
" Use tab for trigger completion with characters ahead and navigate.
" Use command ':verbose imap <tab>' to make sure tab is not mapped by other plugin.
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" Make <CR> to accept selected completion item or notify coc.nvim to format
" <C-g>u breaks current undo, please make your own choice.
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-space> coc#refresh()

" Use `[c` and `]c` for navigate diagnostics
nmap <silent> [c <Plug>(coc-diagnostic-prev)
nmap <silent> ]c <Plug>(coc-diagnostic-next)

" Remap keys for gotos
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K for show documentation in preview window
nnoremap <silent> K :call ShowDocumentation()<CR>

function! ShowDocumentation()
  if CocAction('hasProvider', 'hover')
    call CocActionAsync('doHover')
  else
    call feedkeys('K', 'in')
  endif
endfunction

autocmd User fugitive 
  \ if fugitive#buffer().type() =~# '^\%(tree\|blob\)$' |
  \   nnoremap <buffer> .. :edit %:h<CR> |
  \ endif
autocmd BufReadPost fugitive://* set bufhidden=delete

" No line numbers in terminal
augroup TerminalStuff
  autocmd TermOpen * setlocal nonumber norelativenumber
augroup END

" source vimrc
nnoremap <leader>sv <cmd>source $MYVIMRC<CR>

autocmd FileType * setlocal foldmethod=expr foldlevel=0 foldcolumn=2
autocmd BufNewFile,BufRead */awm/blog/**/*.md setlocal foldexpr=getline(v:lnum)=~'^{%\\s*plantuml\\s*%}$'?'>1':getline(v:lnum)=~'^{%\\s*endplantuml\\s*%}$'?'<1':'='
autocmd BufNewFile,BufRead */fiverr-ebooks/**/*.md setlocal foldexpr=getline(v:lnum)=~'^```plantuml'?'>1':getline(v:lnum)=~'^```$'?'<1':'='
