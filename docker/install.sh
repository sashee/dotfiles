#!/bin/bash

sudo apt update
sudo apt install -y docker.io

sudo systemctl enable --now docker

sudo groupadd docker
sudo usermod -aG docker $USER

