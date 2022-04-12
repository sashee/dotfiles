#!/bin/sh

if [ $(tmux ls | sed '/^\s*$/d' | wc -l) -eq "0" ]; then
	sleep 60
	if [ $(tmux ls | sed '/^\s*$/d' | wc -l) -eq "0" ]; then
		sudo shutdown -h now
	fi
fi

