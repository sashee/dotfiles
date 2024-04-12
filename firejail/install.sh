#!/bin/bash

sudo pacman -S --needed --noconfirm firejail

sudo mkdir -p /usr/lib/systemd/user/syncthing.service.d
sudo rm -f /usr/lib/systemd/user/syncthing.service.d/1-firejail.conf
sudo cp $PWD/firejail/syncthing_1_firejail.conf /usr/lib/systemd/user/syncthing.service.d/1-firejail.conf

rm -f ~/.config/firejail/chromium.local
ln -s $PWD/firejail/chromium.local ~/.config/firejail/chromium.local
rm -f ~/.config/firejail/globals.local
ln -s $PWD/firejail/globals.local ~/.config/firejail/globals.local
rm -f ~/.config/firejail/keepassxc.local
ln -s $PWD/firejail/keepassxc.local ~/.config/firejail/keepassxc.local
rm -f ~/.config/firejail/nix-shell.profile
ln -s $PWD/firejail/nix-shell.profile ~/.config/firejail/nix-shell.profile
rm -f ~/.config/firejail/npm.local
ln -s $PWD/firejail/npm.local ~/.config/firejail/npm.local
rm -f ~/.config/firejail/nvim.local
ln -s $PWD/firejail/nvim.local ~/.config/firejail/nvim.local
rm -f ~/.config/firejail/npm.profile
ln -s $PWD/firejail/npm.profile ~/.config/firejail/npm.profile
rm -f ~/.config/firejail/npx.profile
ln -s $PWD/firejail/npx.profile ~/.config/firejail/npx.profile
rm -f ~/.config/firejail/lazygit.profile
ln -s $PWD/firejail/lazygit.profile ~/.config/firejail/lazygit.profile

sudo firecfg
