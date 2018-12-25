wget https://github.com/neovim/neovim/releases/download/stable/nvim.appimage -O /tmp/nvim.appimage

chmod u+x /tmp/nvim.appimage

(cd ~ && /tmp/nvim.appimage --appimage-extract)
