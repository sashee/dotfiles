find ~ -name "node_modules" -type d -prune -exec rm -rf '{}' +
yes | docker system prune -a
