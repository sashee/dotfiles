find ~/workspace -name "node_modules" -type d -prune -exec rm -rf '{}' +
yes | docker system prune -a
npm cache clean --force
yarn cache clean
sudo apt-get autoremove -y --purge
sudo apt-get clean -y