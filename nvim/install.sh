sudo apt install -y python3-pip

pip3 install --user neovim

curl -sL https://deb.nodesource.com/setup_11.x | sudo bash -
sudo apt-get install -y nodejs

npm config set prefix ~/npm

npm install -g eslint

wget https://github.com/neovim/neovim/releases/download/stable/nvim.appimage -O /tmp/nvim.appimage

chmod u+x /tmp/nvim.appimage

(cd ~ && /tmp/nvim.appimage --appimage-extract)

ln -s $(pwd -P)/nvim/init.vim ~/.config/nvim/init.vim

curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

~/squashfs-root/usr/bin/nvim +PlugInstall +UpdateRemotePlugins +qall
