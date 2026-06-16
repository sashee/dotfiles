#!/bin/bash

sudo mkdir -p /usr/lib/systemd/user/syncthing.service.d
sudo rm -f /usr/lib/systemd/user/syncthing.service.d/1-firejail.conf
sudo cp $PWD/firejail/syncthing_1_firejail.conf /usr/lib/systemd/user/syncthing.service.d/1-firejail.conf
