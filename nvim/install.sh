sudo apt install -y curl jq wget

sudo apt install -y python3-pip

pip3 install --user neovim

sudo apt-get install -y nodejs npm

npm config set prefix ~/npm

# yarn
npm install -g yarn

npm install -g eslint

sudo apt install -y ack-grep neovim

mkdir -p ~/.config/nvim && ln -s $(pwd -P)/nvim/init.vim ~/.config/nvim/init.vim

curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

nvim +'PlugInstall --sync' +UpdateRemotePlugins +'qall!'

nvim -c ":CocInstall coc-html coc-css coc-json coc-tsserver coc-yaml coc-eslint"
