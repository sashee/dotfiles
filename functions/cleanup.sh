find ~/workspace -name "node_modules" -type d -prune -exec rm -rf '{}' +
find ~/workspace -name ".terraform" -type d -prune -exec rm -rf '{}' +
yes | docker system prune -a
yes | docker volume prune
npm cache clean --force
rm -rf ~/.npm/_npx
yarn cache clean
find ~/.cache/ -type f -atime +365 -delete
sudo journalctl --vacuum-time=10d
sudo apt-get autoremove -y --purge
sudo apt-get clean -y

