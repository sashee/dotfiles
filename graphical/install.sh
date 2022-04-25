#!/bin/bash

if [ -f "graphical/.saved_variables" ];
then
	. graphical/.saved_variables
fi

if [[ -z "$ENABLED" ]];
then
	read -p "Enable graphical stuff? (y/n) " ENABLED
fi

declare -p ENABLED > graphical/.saved_variables

if [[ "$ENABLED" == "y" ]];
then
	sudo pacman -S --needed --noconfirm xf86-video-intel acpid intel-media-driver
	sudo pacman -S --needed --noconfirm pulseaudio pavucontrol
	sudo pacman -S --needed --noconfirm redshift
	sudo pacman -S --needed --noconfirm xorg alacritty xmonad xmobar xmonad-contrib dmenu xscreensaver dunst numlockx
	sudo pacman -S --needed --noconfirm vlc ffmpeg chromium leafpad flameshot noto-fonts-emoji

	mkdir -p ~/.xmonad
	rm -f ~/.xmonad/xmonad.hs
	ln -s $PWD/graphical/xmonad.hs ~/.xmonad/xmonad.hs

	rm -f ~/.bashrc
	ln -s $PWD/graphical/bashrc ~/.bashrc

	rm -f ~/.bash_profile
	ln -s $PWD/graphical/bash_profile ~/.bash_profile

	sudo rm -f /etc/X11/xorg.conf.d/00-keyboard.conf
	sudo ln -s $PWD/graphical/xorg_00-keyboard.conf /etc/X11/xorg.conf.d/00-keyboard.conf

	sudo rm -f /etc/X11/xorg.conf.d/20-intel.conf
	sudo ln -s $PWD/graphical/xorg_20-intel.conf /etc/X11/xorg.conf.d/20-intel.conf

	sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf
	sudo ln -s $PWD/graphical/xorg_30-touchpad.conf /etc/X11/xorg.conf.d/30-touchpad.conf

	#sudo mkdir -p /etc/systemd/logind.conf.d
	#sudo rm -f /etc/systemd/logind.conf.d/10-desktop.conf
	sudo rm -f /etc/systemd/logind.conf
	sudo cp $PWD/graphical/logind_10-desktop.conf /etc/systemd/logind.conf
fi

