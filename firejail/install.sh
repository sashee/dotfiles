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
