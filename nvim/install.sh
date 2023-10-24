sudo pacman -S --needed --noconfirm curl jq wget

sudo pacman -S --needed --noconfirm python-pip

pip3 install --user neovim

sudo pacman -S --needed --noconfirm nodejs npm

npm config set prefix ~/npm

# yarn
npm install -g yarn

npm install -g eslint

sudo pacman -S --needed --noconfirm ack neovim

mkdir -p ~/.config/nvim && ln -s $(pwd -P)/nvim/init.vim ~/.config/nvim/init.vim

curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

nvim +'PlugInstall --sync' +UpdateRemotePlugins +'qall!'

nvim -c ":LspInstall tsserver"
