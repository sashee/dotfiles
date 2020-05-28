sudo apt install -y curl jq wget

sudo apt install -y python3-pip

pip3 install --user neovim

# node
curl -sSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | sudo apt-key add -

if [ -e "/etc/apt/sources.list.d/nodesource.list" ]; then
	sudo rm /etc/apt/sources.list.d/nodesource.list
fi

VERSION=node_12.x
DISTRO="$(lsb_release -s -c)"
echo "deb https://deb.nodesource.com/$VERSION $DISTRO main" | sudo tee /etc/apt/sources.list.d/nodesource.list
echo "deb-src https://deb.nodesource.com/$VERSION $DISTRO main" | sudo tee -a /etc/apt/sources.list.d/nodesource.list
sudo apt-get update

sudo apt-get install -y nodejs

npm config set prefix ~/npm

# yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -

if [ -e "/etc/apt/sources.list.d/yarn.list" ]; then
	sudo rm /etc/apt/sources.list.d/yarn.list
fi
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update

sudo apt-get install -y yarn


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
