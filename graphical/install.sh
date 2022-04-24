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
	sudo pacman -S --needed --noconfirm xorg alacritty xmonad xmobar xmonad-contrib dmenu xscreensaver dunst
	sudo pacman -S --needed --noconfirm vlc ffmpeg chromium leafpad

	mkdir -p ~/.xmonad
	rm -f ~/.xmonad/xmonad.hs
	ln -s $PWD/graphical/xmonad.hs ~/.xmonad/xmonad.hs

	rm -f ~/.bashrc
	ln -s $PWD/graphical/bashrc ~/.bashrc

	rm -f ~/.bash_profile
	ln -s $PWD/graphical/bash_profile ~/.bash_profile
fi

