#!/bin/bash

if [ -f "git/.saved_variables" ];
then
	. git/.saved_variables
fi

if [[ -z "$GIT_NAME" ]];
then
	read -p "Git username: " GIT_NAME
fi

if [[ -z "$GIT_EMAIL" ]];
then
	read -p "Git email: " GIT_EMAIL
fi

declare -p GIT_NAME GIT_EMAIL > git/.saved_variables

cat git/gitconfig | GIT_NAME="$GIT_NAME" GIT_EMAIL="$GIT_EMAIL" envsubst > $HOME/.gitconfig
