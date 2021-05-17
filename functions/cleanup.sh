find ~/workspace -name "node_modules" -type d -prune -exec sudo rm -rf '{}' +
find ~/workspace -name ".terraform" -type d -prune -exec rm -rf '{}' +
yes | docker system prune -a
yes | docker volume prune
npm cache clean --force
rm -rf ~/.npm/_npx
yarn cache clean

LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' |
    while read snapname revision; do
        sudo snap remove "$snapname" --revision="$revision"
    done

find ~/.cache/ -type f -atime +365 -delete
sudo journalctl --vacuum-time=10d
sudo apt-get autoremove -y --purge
sudo apt-get clean -y

