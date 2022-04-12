#!/bin/bash

if [ -f "syncthing-monitoring/.saved_variables" ];
then
	. syncthing-monitoring/.saved_variables
fi

if [[ -z "$TOKEN" ]];
then
	read -p "Token: " TOKEN
fi

if [[ -z "$CHAT_ID" ]];
then
	read -p "Chat ID: " CHAT_ID
fi

declare -p TOKEN CHAT_ID > syncthing-monitoring/.saved_variables

cat syncthing-monitoring/syncthing-monitoring.timer | envsubst | sudo tee /etc/systemd/system/syncthing-monitoring.timer > /dev/null

cat syncthing-monitoring/syncthing-monitoring.service | USERNAME="$(id -u -n)" GROUPNAME="$(id -g -n)" TOKEN="$TOKEN" CHAT_ID="$CHAT_ID" envsubst | \
	sudo tee /etc/systemd/system/syncthing-monitoring.service > /dev/null

sudo systemctl enable syncthing-monitoring.timer
sudo systemctl start syncthing-monitoring.timer

