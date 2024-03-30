noblacklist ~/.ssh/known_hosts
blacklist ~/.ssh/*
blacklist ~/*.kdbx
blacklist ~/**/*.kdbx
blacklist ~/.config/chromium
blacklist ~/.config/Google
blacklist ~/.config/keepassxc
blacklist ~/.config/syncthing
blacklist ~/.gnupg
blacklist ~/laptop-backup
blacklist ~/Mobile-backup
blacklist ~/safe

read-only ~/dotfiles
read-only ~/private_scripts

caps.drop all
seccomp

dbus-system none
dbus-user none
disable-mnt

nosound
notv
novideo
no3d
nodvd
noinput
noprinters
nou2f
private-dev
private-tmp
x11 none

