#!/bin/bash

if [ -f "syncthing-monitoring/.saved_variables" ];
then
	. syncthing-monitoring/.saved_variables
fi

if [[ -z "$ENABLED" ]];
then
	read -p "Enable Syncthing monitoring? (y/n) " ENABLED
fi

if [[ -z "$TOKEN" ]];
then
	read -p "Token: " TOKEN
fi

if [[ -z "$CHAT_ID" ]];
then
	read -p "Chat ID: " CHAT_ID
fi

declare -p TOKEN CHAT_ID ENABLED > syncthing-monitoring/.saved_variables

if [[ "$ENABLED" == "y" ]];
then
	cat syncthing-monitoring/syncthing-monitoring.timer | envsubst | sudo tee /etc/systemd/system/syncthing-monitoring.timer > /dev/null

	cat syncthing-monitoring/syncthing-monitoring.service | USERNAME="$(id -u -n)" GROUPNAME="$(id -g -n)" TOKEN="$TOKEN" CHAT_ID="$CHAT_ID" envsubst | \
		sudo tee /etc/systemd/system/syncthing-monitoring.service > /dev/null

	sudo systemctl enable syncthing-monitoring.timer
	sudo systemctl start syncthing-monitoring.timer
fi
