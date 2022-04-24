#!/bin/bash

sudo pacman -S --noconfirm --needed docker

sudo systemctl enable --now docker

sudo groupadd docker
sudo usermod -aG docker $USER

