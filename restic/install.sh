#!/bin/bash

sudo rm -f /etc/systemd/system/restic@.service
sudo cp $PWD/restic/restic@.service /etc/systemd/system/restic@.service
sudo rm -f /etc/systemd/system/restic@.timer
sudo cp $PWD/restic/restic@.timer /etc/systemd/system/restic@.timer

