sudo apt install -y curl jq wget

sudo apt install -y python3-pip

pip3 install --user neovim

# curl -sL https://deb.nodesource.com/setup_11.x | sudo bash -
sudo apt-get install -y nodejs npm

npm config set prefix ~/npm

npm install -g eslint

sudo apt install -y ack-grep

wget $(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | jq -r '.assets[] | select(.name == "nvim.appimage") | .browser_download_url') -O /tmp/nvim.appimage

chmod u+x /tmp/nvim.appimage

(cd ~ && /tmp/nvim.appimage --appimage-extract)

mkdir -p ~/.config/nvim && ln -s $(pwd -P)/nvim/init.vim ~/.config/nvim/init.vim

curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

~/squashfs-root/usr/bin/nvim +'PlugInstall --sync' +UpdateRemotePlugins +'qall!'

~/squashfs-root/usr/bin/nvim -c ":CocInstall coc-html coc-css coc-json coc-tsserver coc-yaml coc-eslint coc-tslint"
