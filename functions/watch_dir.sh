mkdir -p $2

dir=$(dirname "$BASH_SOURCE[0]");

watch "find $2 -maxdepth 1 -mindepth 1 -exec "$dir/transfer_files.sh" $1 {} \; -exec rm -r {} \;"
